#!/usr/bin/env node
"use strict";
const fs = require("node:fs"), path = require("node:path");
function readPrivate(file) {
  if (typeof file !== "string" || !path.isAbsolute(file) || fs.realpathSync(file) !== file) throw Error("MAIL_PRIVATE_FILE_UNSAFE");
  const s = fs.lstatSync(file);
  if (!s.isFile() || s.nlink !== 1 || s.uid !== process.getuid() || (s.mode & 0o077)) throw Error("MAIL_PRIVATE_FILE_UNSAFE");
  return fs.readFileSync(file);
}
const { api } = require("./consumer.cjs");
function run(argv) {
  const operation = argv.shift(), opts = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--execute") opts.execute = true;
    else if (argv[i] === "--config" && argv[i + 1]) opts.config = path.resolve(argv[++i]);
    else throw Error("MAIL_CLI_USAGE");
  }
  if (operation === "mail") throw Error("MAIL_ADMINISTRATION_RESERVED_FOR_MAIL03");
  if (!["validate", "plan", "install", "start", "stop", "restart", "status", "doctor", "backup", "restore"].includes(operation) || !opts.config) throw Error("MAIL_CLI_USAGE");
  const cfg = require("./config.cjs").validate(JSON.parse(fs.readFileSync(opts.config)));
  if (cfg.distribution?.profile !== "mail") throw Error("MAIL_PROFILE_REQUIRED");
  const M = api(), checked = M.validateMailService(cfg.service);
  if (!checked.valid) return { valid: false, diagnostics: checked.diagnostics };
  if (operation === "validate") return checked;
  if (["backup", "restore"].includes(operation)) throw Error("SMTP_RECOVERY_UNQUALIFIED");
  if (operation === "plan") return M.planMailService(cfg.service, { registry: JSON.parse(readPrivate(cfg.registry_file)), secret_sources: cfg.secret_sources });
  if (process.getuid() !== cfg.service.deployment.owner_uid || process.getgid() !== cfg.service.deployment.owner_gid) throw Error("MAIL_OPERATOR_IDENTITY_MISMATCH");
  const state = path.join(cfg.service.deployment.root, "durable/operator-state/prepared.json");
  if (["status", "doctor"].includes(operation)) return M.operateMailService(JSON.parse(fs.readFileSync(state)), "status", { authorized: true });
  if (!opts.execute) throw Error("MAIL_EXECUTION_AUTHORIZATION_REQUIRED");
  if (operation === "install") {
    const verifiers = JSON.parse(readPrivate(cfg.verifiers_file));
    const plan = M.planMailService(cfg.service, { registry: JSON.parse(readPrivate(cfg.registry_file)), secret_sources: cfg.secret_sources });
    const prepared = M.prepareMailService(plan, { authorized: true, acceptance: cfg.acceptance === true, verifiers });
    if (fs.existsSync(state)) {
      if (JSON.stringify(JSON.parse(fs.readFileSync(state))) !== JSON.stringify(prepared)) throw Error("MAIL_PREPARED_REVISION_CONFLICT");
    } else fs.writeFileSync(state, JSON.stringify(prepared), { mode: 0o600, flag: "wx" });
    return M.operateMailService(prepared, "start", { authorized: true, acceptance: cfg.acceptance === true });
  }
  return M.operateMailService(JSON.parse(fs.readFileSync(state)), operation, { authorized: true, acceptance: cfg.acceptance === true });
}
try { console.log(JSON.stringify(run(process.argv.slice(2)))); }
catch (error) { console.log(JSON.stringify({ ok: false, code: /^[A-Z0-9_]+$/.test(error.code || error.message) ? error.code || error.message : "MAIL_OPERATION_FAILED" })); process.exitCode = 1; }
