"use strict";
const path = require("node:path");
const api = require("@drumee/infra-layer"), L = require("@drumee/infra-layer/lifecycle");
function fail(code) { throw Object.assign(new Error(code), { code }); }
function keys(value, expected) { if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).some(key => !expected.includes(key))) fail("APPLICATION_CONFIGURATION_INVALID"); }
function absolute(value) { return typeof value === "string" && /^\/[a-zA-Z0-9_./-]+$/.test(value) && path.posix.normalize(value) === value && !value.split("/").some(x => [".", ".."].includes(x)) && !["/", "/etc", "/srv", "/var", "/home", "/data", "/tmp"].includes(value); }
const contains = (parent, child) => parent === child || child.startsWith(parent + "/");
function plan(cfg) { return api.planInfrastructure(cfg.infrastructure.spec, cfg.infrastructure.requirements, cfg.infrastructure.adapter_input); }
function descriptor(cfg) {
  const value = structuredClone(cfg.manifest);
  value.application.environment = { ...value.application.environment, DRUMEE_APP_CONFIG: JSON.stringify({ port: value.external_gateway.container_port, plugins: value.application.plugins }) };
  return value;
}
function validate(cfg) {
  keys(cfg, ["distribution", "deployment", "storage", "infrastructure", "manifest", "imports"]);
  keys(cfg.distribution, ["profile"]); if (cfg.distribution.profile !== "minimal-application") fail("APPLICATION_PROFILE_REQUIRED");
  keys(cfg.deployment, ["id", "project", "owner_uid", "owner_gid", "acceptance"]);
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,79}$/.test(cfg.deployment.id || "") || !/^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,79}$/.test(cfg.deployment.project || "") || !Number.isInteger(cfg.deployment.owner_uid) || cfg.deployment.owner_uid < 1 || !Number.isInteger(cfg.deployment.owner_gid) || cfg.deployment.owner_gid < 0 || typeof cfg.deployment.acceptance !== "boolean") fail("APPLICATION_OWNER_REQUIRED");
  keys(cfg.storage, ["root", "backup_location", "retention_days"]);
  if (!absolute(cfg.storage.root) || !absolute(cfg.storage.backup_location) || contains(cfg.storage.root, cfg.storage.backup_location) || contains(cfg.storage.backup_location, cfg.storage.root) || !Number.isInteger(cfg.storage.retention_days) || cfg.storage.retention_days < 1) fail("APPLICATION_STORAGE_INVALID");
  keys(cfg.infrastructure, ["spec", "requirements", "adapter_input"]);
  const checked = api.validateSpec(cfg.infrastructure.spec, cfg.infrastructure.requirements);
  if (!checked.valid) fail("APPLICATION_INFRASTRUCTURE_INVALID");
  const declared = plan(cfg); if (!declared.applicable) fail("APPLICATION_PLAN_NOT_APPLICABLE");
  if (cfg.infrastructure.spec.instance.id !== cfg.deployment.id || cfg.infrastructure.adapter_input.project !== cfg.deployment.project) fail("APPLICATION_IDENTITY_MISMATCH");
  if (cfg.manifest?.profile !== "application") fail("APPLICATION_MANIFEST_REQUIRED");
  if (cfg.manifest.application?.environment?.DRUMEE_APP_CONFIG !== undefined) fail("APPLICATION_RESERVED_ENVIRONMENT");
  const composed = L.composeDeployment(declared, descriptor(cfg));
  const protected_paths = ["/app/host.js", "/app/health.js", "/app/plugins", "/app/node_modules", "/app/plugins-manifest.json"];
  for (const mount of [...(cfg.manifest.application?.mounts || []), ...(cfg.manifest.application?.secret_mounts || [])]) if (protected_paths.some(item => contains(item, mount.target) || contains(mount.target, item))) fail("APPLICATION_CODE_MOUNT_FORBIDDEN");

  for (const resource of composed.resources) if (!contains(path.join(cfg.storage.root, "durable"), resource.source)) fail("APPLICATION_RESOURCE_OUTSIDE_ROOT");
  const state = composed.resources.find(x => x.id === "operator-state");
  if (!state || state.source !== path.join(cfg.storage.root, "durable/operator-state") || state.uid !== cfg.deployment.owner_uid || state.gid !== cfg.deployment.owner_gid) fail("APPLICATION_OPERATOR_STATE_REQUIRED");
  if (cfg.imports !== undefined) {
    if (!Array.isArray(cfg.imports)) fail("APPLICATION_IMPORT_INVALID");
    for (const value of cfg.imports) { keys(value, ["ref", "file"]); if (!absolute(value.file) || !declared.required_secrets.some(x => x.ref.resource === value.ref?.resource && x.ref.key === value.ref?.key)) fail("APPLICATION_IMPORT_INVALID"); }
  }
  return cfg;
}
function compose(cfg) { validate(cfg); return L.composeDeployment(plan(cfg), descriptor(cfg)); }
module.exports = { validate, compose, fail, absolute, contains };
