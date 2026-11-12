"use strict";
const fs = require("node:fs"), path = require("node:path");
const { api } = require("./consumer.cjs");
function validate(cfg) {
  if (!cfg || cfg.distribution?.profile !== "mail" || Object.keys(cfg.distribution).some(k => k !== "profile") || Object.keys(cfg).some(k => !["distribution", "service", "registry_file", "verifiers_file", "secret_sources", "acceptance"].includes(k)) || typeof cfg.acceptance !== "boolean") throw Error("MAIL_PROFILE_INVALID");
  for (const k of ["registry_file", "verifiers_file"]) if (typeof cfg[k] !== "string" || !path.isAbsolute(cfg[k]) || path.normalize(cfg[k]) !== cfg[k]) throw Error("MAIL_PRIVATE_FILE_UNSAFE");
  const checked = api().validateMailService(cfg.service);
  if (!checked.valid) throw Error("MAIL_SERVICE_INVALID: " + JSON.stringify(checked.diagnostics));
  return { ...cfg, service: checked.normalized };
}
function compose(raw) {
  const cfg = validate(raw), M = api();
  const st = fs.lstatSync(cfg.registry_file);
  if (!st.isFile() || st.isSymbolicLink() || st.nlink !== 1 || st.uid !== process.getuid() || (st.mode & 0o077)) throw Error("MAIL_PRIVATE_FILE_UNSAFE");
  const plan = M.planMailService(cfg.service, { registry: JSON.parse(fs.readFileSync(cfg.registry_file)), secret_sources: cfg.secret_sources });
  return M.composeMailService(plan, { acceptance: cfg.acceptance });
}
module.exports = { api, validate, compose };
