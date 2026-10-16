#!/usr/bin/env node
"use strict";
const fs = require("node:fs"), path = require("node:path"), { pathToFileURL } = require("node:url");
const L = require("@drumee/infra-layer/lifecycle"), { validate, compose, fail, contains } = require("./lib/config");
function options(argv) {
  const [command, ...args] = argv, value = { command, config: path.resolve("config/drumee.yaml"), execute: false, recover: false };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--execute") value.execute = true;
    else if (args[i] === "--recover") value.recover = true;
    else if (["--config", "--backup", "--revision"].includes(args[i]) && args[i + 1] && !args[i + 1].startsWith("--")) value[args[i++].slice(2)] = args[i];
    else fail("APPLICATION_CLI_USAGE");
  }
  return value;
}
async function load(file) { const { parseYaml } = await import(pathToFileURL(path.resolve(__dirname, "../../config/render.mjs"))); return validate(parseYaml(fs.readFileSync(file, "utf8"))); }
function owner(cfg) { if (process.getuid() !== cfg.deployment.owner_uid || process.getgid() !== cfg.deployment.owner_gid) fail("APPLICATION_OWNER_MISMATCH"); }
function proxyConfig(cfg) { const g = cfg.manifest.external_gateway; return `# Include inside the externally managed HTTPS server. No URI rewrite.\nlocation /-/ {\n  proxy_pass http://${g.host_address}:${g.host_port};\n  proxy_http_version 1.1;\n  proxy_set_header Host $host;\n  proxy_set_header X-Forwarded-Proto $scheme;\n  proxy_set_header X-Forwarded-For $remote_addr;\n}\n`; }
function snapshot(cfg, prepared) {
  const directory = path.join(cfg.storage.root, "durable/operator-state/configurations"); fs.mkdirSync(directory, { mode: 0o700, recursive: true });
  const directory_stat = fs.lstatSync(directory);
  if (!directory_stat.isDirectory() || directory_stat.isSymbolicLink() || directory_stat.uid !== process.getuid() || (directory_stat.mode & 0o077)) fail("APPLICATION_CONFIG_SNAPSHOT_UNSAFE");
  const file = path.join(directory, prepared.revision + ".json"), bytes = JSON.stringify(cfg);
  const stat = fs.lstatSync(file, { throwIfNoEntry: false });
  if (stat) { if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.uid !== process.getuid() || (stat.mode & 0o077) || fs.readFileSync(file, "utf8") !== bytes) fail("APPLICATION_CONFIG_SNAPSHOT_CONFLICT"); }
  else fs.writeFileSync(file, bytes, { mode: 0o600, flag: "wx" });
}
async function run(opts) {
  if (!["plan", "validate", "proxy-config", "install", "status", "doctor", "stop", "start", "restart", "backup", "restore", "rollback"].includes(opts.command)) fail("APPLICATION_CLI_USAGE");
  const cfg = await load(opts.config), composition = compose(cfg);
  if (opts.command === "validate") return { valid: true, code: "APPLICATION_CONFIGURATION_VALID", revision: composition.revision };
  if (opts.command === "plan") return composition;
  if (opts.command === "proxy-config") return { code: "EXTERNAL_PROXY_CONFIGURATION", content: proxyConfig(cfg), applied: false };
  owner(cfg);
  const context = { root: cfg.storage.root, authorized: true, recover: opts.recover, imports: cfg.imports || [] };
  const state = await L.inspectDeployment(cfg.storage.root, context);
  if (state.project && state.project !== cfg.deployment.project) fail("APPLICATION_IDENTITY_MISMATCH");
  if (["status", "doctor"].includes(opts.command)) return opts.command === "doctor" ? { ...L.diagnoseDeployment(state), state } : state;
  if (!opts.execute) fail("APPLICATION_EXECUTION_AUTHORIZATION_REQUIRED");
  if (opts.command === "restore") {
    if (!opts.backup) fail("APPLICATION_BACKUP_SOURCE_REQUIRED");
    const restored = await L.restoreDeployment(path.resolve(opts.backup), composition, { ...context, create_resources: true });
    snapshot(cfg, restored.prepared);
    return { ...await L.activateDeployment(restored.prepared, context), restored: true, kernel_recovery_verified: false };
  }
  const prepared = await L.prepareDeployment(composition, { ...context, create_resources: opts.command === "install" });
  if (opts.command === "rollback") { if (!opts.revision) fail("APPLICATION_ROLLBACK_REVISION_REQUIRED"); return L.rollbackDeployment(cfg.storage.root, opts.revision, context); }
  if (["stop", "restart", "backup"].includes(opts.command) && state.active_revision !== prepared.revision) fail("APPLICATION_ACTIVE_CONFIGURATION_MISMATCH");
  if (opts.command === "stop") return L.stopDeployment(prepared, context);
  if (opts.command === "backup") {
    if (!opts.backup || !contains(cfg.storage.backup_location, path.resolve(opts.backup)) || path.resolve(opts.backup) === cfg.storage.backup_location) fail("APPLICATION_BACKUP_DESTINATION_INVALID");
    return { ...await L.backupDeployment(cfg.storage.root, path.resolve(opts.backup), { ...context, quiescence: "stop-owned-writers", resume_after_backup: true }), retention_days: cfg.storage.retention_days, pruning: "explicit-owner-operation" };
  }
  snapshot(cfg, prepared);
  if (opts.command === "restart") await L.stopDeployment(prepared, context);
  return L.activateDeployment(prepared, context);
}
if (require.main === module) Promise.resolve().then(() => run(options(process.argv.slice(2)))).then(value => console.log(JSON.stringify(value))).catch(error => { console.error(JSON.stringify({ code: /^[A-Z][A-Z0-9_]+$/.test(error.code || "") ? error.code : "APPLICATION_OPERATION_FAILED" })); process.exitCode = 1; });
module.exports = { options, load, run, proxyConfig };
