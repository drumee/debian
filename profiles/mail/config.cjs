"use strict";
const fs = require("node:fs"), path = require("node:path");
const { api } = require("./consumer.cjs");
function validate(cfg) {
  if (!cfg || cfg.distribution?.profile !== "mail" || Object.keys(cfg.distribution).some(k => k !== "profile") || Object.keys(cfg).some(k => !["distribution", "service", "registry_file", "verifiers_file", "secret_sources", "acceptance", "acceptance_private_listener", "monitoring"].includes(k)) || typeof cfg.acceptance !== "boolean") throw Error("MAIL_PROFILE_INVALID");
  if (cfg.acceptance_private_listener !== undefined && typeof cfg.acceptance_private_listener !== "boolean") throw Error("MAIL_PROFILE_INVALID");
  if (cfg.acceptance_private_listener && !cfg.acceptance) throw Error("MAIL_PROFILE_INVALID");
  if (cfg.monitoring && (Object.keys(cfg.monitoring).some(k => !["queue_age_seconds", "auth_failures"].includes(k)) || Object.values(cfg.monitoring).some(v => !Number.isSafeInteger(v) || v < 1))) throw Error("MAIL_PROFILE_INVALID");
  for (const k of ["registry_file", "verifiers_file"]) if (typeof cfg[k] !== "string" || !path.isAbsolute(cfg[k]) || path.normalize(cfg[k]) !== cfg[k]) throw Error("MAIL_PRIVATE_FILE_UNSAFE");
  const checked = api().validateMailService(cfg.service);
  if (!checked.valid) throw Error("MAIL_SERVICE_INVALID");
  return { ...cfg, service: checked.normalized };
}
function compose(raw) {
  const cfg = validate(raw), M = api();
  const st = fs.lstatSync(cfg.registry_file);
  if (!st.isFile() || st.isSymbolicLink() || st.nlink !== 1 || st.uid !== process.getuid() || (st.mode & 0o077)) throw Error("MAIL_PRIVATE_FILE_UNSAFE");
  const plan = M.planMailService(cfg.service, { registry: JSON.parse(fs.readFileSync(cfg.registry_file)), secret_sources: cfg.secret_sources });
  return M.composeMailService(plan, { acceptance: cfg.acceptance, private_bind: cfg.acceptance_private_listener === true });
}
module.exports = { api, validate, compose };
