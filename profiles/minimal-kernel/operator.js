#!/usr/bin/env node
"use strict";
const fs = require("node:fs"), path = require("node:path"), os = require("node:os");
const { pathToFileURL } = require("node:url");
const { spawnSync } = require("node:child_process");
const lifecycle = require("@drumee/infra-layer/lifecycle");
const { validate, fail } = require("./lib/config");
const { compose } = require("./lib/distribution");
const { createDriver } = require("./lib/driver");
const F = require("@drumee/infra-layer/lib/filesystem-safety");
const { readActive } = require("@drumee/infra-layer/lifecycle/activation");
function options(argv) {
  const [command, ...args] = argv, value = { command, config: path.resolve("config/drumee.yaml"), execute: false, recover: false };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--execute") value.execute = true;
    else if (args[i] === "--recover") value.recover = true;
    else if (["--config", "--backup", "--revision", "--password-fd"].includes(args[i]) && args[i + 1] && !args[i + 1].startsWith("--")) value[args[i++].slice(2).replace("-", "_")] = args[i];
    else fail("MINIMAL_CLI_USAGE");
  }
  if (value.password_fd !== undefined) { value.password_fd = Number(value.password_fd); if (!Number.isInteger(value.password_fd) || value.password_fd < 3) fail("OPERATOR_SECURE_INPUT_REQUIRED"); }
  return value;
}
async function load(file) {
  const { parseYaml } = await import(pathToFileURL(path.resolve(__dirname, "../../config/render.mjs")));
  return validate(parseYaml(fs.readFileSync(file, "utf8")));
}
function owner(cfg, host = false) {
  if (cfg.deployment.owner_uid !== process.getuid() || cfg.deployment.owner_gid !== process.getgid()) fail("MINIMAL_OWNER_MISMATCH");
  if (host && !(os.networkInterfaces()[cfg.network.interface] || []).some(value => value.address === cfg.network.lan_address && !value.internal)) fail("MINIMAL_HOST_LAN_MISMATCH");
}
function imageProvenance(cfg, driver) {
  const record = JSON.parse(driver.docker(["image", "inspect", cfg.images.kernel, "--format", "{{json .Config.Labels}}"]));
  if (record?.["org.opencontainers.image.source"] !== "https://github.com/drumee/debian" || record["org.opencontainers.image.revision"] !== cfg.provenance.revision || record["org.drumee.distribution.alignment"] !== cfg.provenance.alignment_sha256) fail("MINIMAL_IMAGE_PROVENANCE_MISMATCH");
  const tools = JSON.parse(driver.docker(["image", "inspect", cfg.images.tools, "--format", "{{json .Config.Labels}}"]));
  if (tools?.["org.opencontainers.image.source"] !== "https://github.com/drumee/infra-layer" || tools["org.opencontainers.image.revision"] !== require("./dependency-alignment.json").infrastructure.revision) fail("MINIMAL_TOOLS_PROVENANCE_MISMATCH");
}
function assets(prepared, driver) {
  const target = path.join(prepared.root, "durable/public");
  const script = `const fs=require('node:fs'),path=require('node:path');function copy(src,dst){const s=fs.lstatSync(src);if(s.isSymbolicLink()||(!s.isFile()&&!s.isDirectory()))throw Error('unsafe');if(s.isDirectory()){if(!fs.existsSync(dst))fs.mkdirSync(dst,{mode:0o755});for(const name of fs.readdirSync(src))copy(path.join(src,name),path.join(dst,name));}else if(fs.existsSync(dst)){if(!fs.readFileSync(dst).equals(fs.readFileSync(src)))throw Error('asset conflict');}else fs.copyFileSync(src,dst,fs.constants.COPYFILE_EXCL);}copy('/app/public-build','/output');fs.chmodSync('/output',0o755);`;
  driver.docker(["run", "--rm", "--network", "none", "--read-only", "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true", "--user", `${process.getuid()}:${process.getgid()}`, "--label", "org.drumee.infra.owner=" + prepared.project, "--mount", `type=bind,source=${target},target=/output`, prepared.composition.distribution.kernel.image, "-e", script]);
  fs.chmodSync(path.join(prepared.root, "durable/content"), 0o755);
}
async function run(opts) {
  const allowed = ["plan", "validate", "install", "status", "doctor", "start", "stop", "backup", "restore", "upgrade", "rollback", "credential"];
  if (!allowed.includes(opts.command)) fail("MINIMAL_CLI_USAGE");
  const cfg = await load(opts.config), composition = compose(cfg);
  if (opts.command === "validate") return { valid: true, code: "MINIMAL_CONFIGURATION_VALID", profile: "minimal-kernel", composition_revision: composition.revision };
  if (opts.command === "plan") return composition;
  owner(cfg);
  const owner_file = path.join(cfg.storage.root, "deployment-owner.json");
  if (fs.existsSync(owner_file)) {
    const record = JSON.parse(F.read(owner_file));
    if (record.project !== cfg.deployment.project || record.instance_id !== cfg.deployment.id || record.uid !== process.getuid()) fail("DEPLOYMENT_OWNERSHIP_MISMATCH");
  }
  const driver = createDriver({ password_fd: opts.password_fd });
  const context = { root: cfg.storage.root, authorized: true, driver, recover: opts.recover };
  if (opts.command === "status" || opts.command === "doctor") {
    const state = await lifecycle.inspectDeployment(cfg.storage.root, context);
    return opts.command === "doctor" ? { ...lifecycle.diagnoseDeployment(state), state } : state;
  }
  if (!opts.execute) fail("MINIMAL_EXECUTION_AUTHORIZATION_REQUIRED");
  if (["install", "start"].includes(opts.command) && cfg.operator.mode === "interactive" && !fs.existsSync(path.join(cfg.storage.root, "durable/operator-state/credential.json")) && opts.password_fd === undefined && (!process.stdin.isTTY || !process.stderr.isTTY)) fail("OPERATOR_SECURE_INPUT_REQUIRED");
  owner(cfg, ["install", "restore", "upgrade"].includes(opts.command));
  if (["install", "start", "upgrade", "restore"].includes(opts.command)) imageProvenance(cfg, driver);
  if (opts.command === "credential") {
    F.privateDirectory(cfg.storage.root);
    const result = spawnSync(process.execPath, [path.join(__dirname, "vendor/operator-bootstrap/scripts/retrieve.js"), "--authorize-retrieval", "--resource", path.join(cfg.storage.root, "durable/operator-state/credential.json"), "--operation-id", cfg.operator.operation_id], { stdio: "inherit" });
    if (result.error || result.status !== 0) fail("OPERATOR_SECURE_RETRIEVAL_FAILED");
    return { code: "OPERATOR_CREDENTIAL_DELIVERED_TO_TTY" };
  }
  if (opts.command === "backup") {
    if (!opts.backup) fail("MINIMAL_BACKUP_DESTINATION_REQUIRED");
    const target = path.resolve(opts.backup);
    if (!target.startsWith(cfg.storage.backup_location + "/")) fail("MINIMAL_BACKUP_POLICY_MISMATCH");
    const result = await lifecycle.backupDeployment(cfg.storage.root, target, { ...context, quiescence: "stop-owned-writers", resume_after_backup: true });
    return { ...result, retention_days: cfg.storage.retention_days, pruning: "explicit-owner-operation-only" };
  }
  if (opts.command === "restore") {
    if (!opts.backup) fail("MINIMAL_BACKUP_SOURCE_REQUIRED");
    const restored = await lifecycle.restoreDeployment(path.resolve(opts.backup), composition, { ...context, create_resources: true });
    const snapshot = path.join(cfg.storage.root, "durable/distribution-state/config.json");
    const source_snapshot = F.read(snapshot);
    F.atomic(path.join(cfg.storage.root, "durable/distribution-state/restored-from-config.json"), source_snapshot, 0o600, true);
    F.atomic(snapshot, JSON.stringify(cfg));
    const state = await lifecycle.activateDeployment(restored.prepared, { ...context, create_resources: false });
    if (!state.ready) fail("MINIMAL_APPLICATION_NOT_READY");
    return { ...state, restored: true, enrollment_authentication_validated: true };
  }
  if (opts.command === "rollback") {
    if (!opts.revision) fail("MINIMAL_ROLLBACK_REVISION_REQUIRED");
    return lifecycle.rollbackDeployment(cfg.storage.root, opts.revision, context);
  }
  const active = readActive(cfg.storage.root);
  if (opts.command === "stop") {
    if (!active) fail("DEPLOYMENT_NOT_ACTIVE");
    return lifecycle.stopDeployment(active.prepared, context);
  }
  if (opts.command === "start" && active) {
    if (composition.revision !== active.prepared.composition.revision) fail("MINIMAL_ACTIVE_CONFIG_MISMATCH");
    return lifecycle.activateDeployment(active.prepared, context);
  }
  if (opts.command === "upgrade" && (!active || !opts.backup)) fail("VERIFIED_BACKUP_REQUIRED");
  if (opts.command === "upgrade") {
    const manifest = lifecycle.validateBackup(path.resolve(opts.backup), active.prepared.composition.distribution.schema_versions, context);
    if (manifest.owner !== cfg.deployment.id || manifest.source_revision !== active.revision) fail("VERIFIED_BACKUP_REQUIRED");
  }
  const prepared = await lifecycle.prepareDeployment(composition, { ...context, create_resources: opts.command === "install" });
  const snapshot = path.join(prepared.root, "durable/distribution-state/config.json"), config_bytes = Buffer.from(JSON.stringify(cfg));
  if (fs.existsSync(snapshot)) { if (!F.read(snapshot).equals(config_bytes)) fail("MINIMAL_CONFIGURATION_SNAPSHOT_CONFLICT"); }
  else F.atomic(snapshot, config_bytes, 0o600, true);
  assets(prepared, driver);
  const backup_evidence = opts.backup ? { directory: path.resolve(opts.backup), manifest_digest: JSON.parse(F.read(path.join(path.resolve(opts.backup), "backup.json"))).digest } : undefined;
  const state = await lifecycle.activateDeployment(prepared, { ...context, backup_evidence });
  if (!state.ready) fail("MINIMAL_APPLICATION_NOT_READY");
  return { ...state, credential_resource: path.join(cfg.storage.root, "durable/operator-state/credential.json"), retrieval: "Use drumee-ctl --profile minimal-kernel credential --execute with this config at a private controlling TTY." };
}
if (require.main === module) Promise.resolve().then(() => run(options(process.argv.slice(2)))).then(value => { console.log(JSON.stringify(value, null, 2)); if (value.ready === false || value.valid === false) process.exitCode = 1; }).catch(error => { console.error(JSON.stringify({ code: /^[A-Z0-9_]+$/.test(error.code || "") ? error.code : "MINIMAL_OPERATION_FAILED", diagnostics: Array.isArray(error.diagnostics) ? error.diagnostics : undefined })); process.exitCode = 1; });
module.exports = { options, load, run, owner, assets };
