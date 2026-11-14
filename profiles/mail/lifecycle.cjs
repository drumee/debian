#!/usr/bin/env node
"use strict";
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === "object" ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
function readPrivate(file) {
  if (typeof file !== "string" || !path.isAbsolute(file) || fs.realpathSync(file) !== file) throw Error("MAIL_PRIVATE_FILE_UNSAFE");
  const s = fs.lstatSync(file);
  if (!s.isFile() || s.nlink !== 1 || s.uid !== process.getuid() || (s.mode & 0o077)) throw Error("MAIL_PRIVATE_FILE_UNSAFE");
  return fs.readFileSync(file);
}
const { api } = require("./consumer.cjs");
function administration(config,cfg) {
  const file=path.join(cfg.service.deployment.root,"durable/operator-state/admin/registry.sqlite3");
  if(!fs.existsSync(file))return null;
  const result=require("node:child_process").spawnSync("/usr/bin/python3",["-I",path.join(__dirname,"admin/main.py"),"status","--config",config,"--json"],{env:{PATH:"/usr/bin:/bin",LANG:"C",LC_ALL:"C",HOME:"/"},encoding:"utf8",timeout:30000,maxBuffer:65536});
  try { const value=JSON.parse(result.stdout);return value.ok?{available:true,desired_revision:value.desired_revision,applied_revision:value.applied_revision,...value.data}:{available:false,code:value.code}; }
  catch { return {available:false,code:"MAIL_RECOVERY_REQUIRED"}; }
}
function run(argv) {
  const operation = argv.shift(), opts = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--execute") opts.execute = true;
    else if (argv[i] === "--config" && argv[i + 1]) opts.config = path.resolve(argv[++i]);
    else throw Error("MAIL_CLI_USAGE");
  }
  if (!["validate", "plan", "install", "start", "stop", "restart", "status", "doctor", "backup", "restore", "preflight", "boot-unit"].includes(operation) || !opts.config) throw Error("MAIL_CLI_USAGE");
  const cfg = require("./config.cjs").validate(JSON.parse(fs.readFileSync(opts.config)));
  if (cfg.distribution?.profile !== "mail") throw Error("MAIL_PROFILE_REQUIRED");
  const M = api(), checked = M.validateMailService(cfg.service);
  if (!checked.valid) return { valid: false, diagnostics: checked.diagnostics };
  if (operation === "validate") return checked;
  if (operation === "boot-unit") return { unit: require("./boot-unit.cjs").render(opts.config, cfg) };
  if (["backup", "restore"].includes(operation)) throw Error("SMTP_RECOVERY_UNQUALIFIED");
  if (operation === "plan") return M.planMailService(cfg.service, { registry: JSON.parse(readPrivate(cfg.registry_file)), secret_sources: cfg.secret_sources });
  if (process.getuid() !== cfg.service.deployment.owner_uid || process.getgid() !== cfg.service.deployment.owner_gid) throw Error("MAIL_OPERATOR_IDENTITY_MISMATCH");
  const state = path.join(cfg.service.deployment.root, "durable/operator-state/prepared.json");
  const loadState = () => {
    if (!fs.existsSync(state)) throw Error("MAIL_STORAGE_GUARD_FAILED");
    const prepared = JSON.parse(readPrivate(state));
    const digest = crypto.createHash("sha256").update(JSON.stringify(canonical(checked.normalized))).digest("hex");
    if (prepared.root !== cfg.service.deployment.root || prepared.project !== cfg.service.deployment.project || prepared.hostname !== cfg.service.hostname || prepared.transport_digest !== digest) throw Error("MAIL_PROFILE_STATE_MISMATCH");
    const binding = (prepared.compose.services.postfix.ports || []).some(port => port.target === checked.normalized.networks.private_submission.port && port.host_ip === checked.normalized.networks.private_submission.address);
    if (cfg.acceptance === true && (prepared.compose.networks.edge.internal !== !cfg.acceptance_private_listener || binding !== !!cfg.acceptance_private_listener)) throw Error("MAIL_PROFILE_STATE_MISMATCH");
    return prepared;
  };
  if (operation === "doctor") {
    const value=M.observeMailService(loadState(), { authorized: true, ...cfg.monitoring }),managed=administration(opts.config,cfg);
    if(managed){value.administration=managed;if(!managed.available||managed.pending_operation){value.healthy=false;if(!value.alerts.some(x=>x.code==="MAIL_GENERATION_INCOMPLETE"))value.alerts.push({code:"MAIL_GENERATION_INCOMPLETE",source:"administrative-journal"});}}
    return value;
  }
  if (operation === "status") {
    const value=M.operateMailService(loadState(), "status", { authorized: true }),managed=administration(opts.config,cfg);if(managed)value.administration=managed;return value;
  }
  if (operation === "preflight") return M.operateMailService(loadState(), "preflight", { authorized: true });
  if (!opts.execute) throw Error("MAIL_EXECUTION_AUTHORIZATION_REQUIRED");
  if (operation === "install") {
    const verifiers = JSON.parse(readPrivate(cfg.verifiers_file));
    const plan = M.planMailService(cfg.service, { registry: JSON.parse(readPrivate(cfg.registry_file)), secret_sources: cfg.secret_sources });
    const prepared = M.prepareMailService(plan, { authorized: true, acceptance: cfg.acceptance === true, private_bind: cfg.acceptance_private_listener === true, verifiers });
    if (fs.existsSync(state)) {
      if (JSON.stringify(JSON.parse(fs.readFileSync(state))) !== JSON.stringify(prepared)) throw Error("MAIL_PREPARED_REVISION_CONFLICT");
    } else fs.writeFileSync(state, JSON.stringify(prepared), { mode: 0o600, flag: "wx" });
    return M.operateMailService(prepared, "start", { authorized: true, acceptance: cfg.acceptance === true });
  }
  return M.operateMailService(loadState(), operation, { authorized: true, acceptance: cfg.acceptance === true });
}
try { console.log(JSON.stringify(run(process.argv.slice(2)))); }
catch (error) { console.log(JSON.stringify({ ok: false, code: /^[A-Z0-9_]+$/.test(error.code || error.message) ? error.code || error.message : "MAIL_OPERATION_FAILED" })); process.exitCode = 1; }
