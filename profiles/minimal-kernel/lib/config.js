"use strict";
// Distribution validation only. Infrastructure planning remains in Infra Layer.
const path = require("node:path"), net = require("node:net");
const fail = code => { throw Object.assign(Error(code), { code }); };
function validate(cfg) {
  const fields = {
    distribution: ["profile"], instance: ["domain"], deployment: ["id", "project", "owner_uid", "owner_gid", "acceptance"],
    network: ["interface", "lan_address", "bind_address", "clients"], dns: ["mode"], tls: ["provider"],
    storage: ["root", "backup_location", "retention_days"], ports: ["https", "dns"],
    images: ["kernel", "tools"], provenance: ["revision", "alignment_sha256"],
    operator: ["mode", "username", "email", "operation_id"]
  };
  if (!cfg || Array.isArray(cfg) || Object.keys(cfg).some(key => !Object.hasOwn(fields, key))) fail("MINIMAL_CONFIG_INVALID");
  for (const [section, keys] of Object.entries(fields)) {
    const value = cfg[section];
    if (!value || Array.isArray(value) || typeof value !== "object" || Object.keys(value).some(key => !keys.includes(key)) || keys.some(key => !Object.hasOwn(value, key))) fail("MINIMAL_CONFIG_REQUIRED_FIELD");
  }
  if (cfg.distribution.profile !== "minimal-kernel" || cfg.instance.domain !== "drumee.lan" || cfg.dns.mode !== "local" || cfg.tls.provider !== "local") fail("MINIMAL_PROFILE_UNSUPPORTED");
  for (const value of [cfg.deployment.id, cfg.deployment.project]) if (typeof value !== "string" || !/^[a-z][a-z0-9-]{7,62}$/.test(value)) fail("MINIMAL_DEPLOYMENT_ID_INVALID");
  if (!Number.isInteger(cfg.deployment.owner_uid) || cfg.deployment.owner_uid < 1 || !Number.isInteger(cfg.deployment.owner_gid) || cfg.deployment.owner_gid < 0 || typeof cfg.deployment.acceptance !== "boolean") fail("MINIMAL_OWNER_INVALID");
  if (!/^[a-zA-Z0-9_.:-]{1,32}$/.test(cfg.network.interface || "") || /^(?:docker|br-|veth|lo$)/.test(cfg.network.interface)) fail("MINIMAL_LAN_INTERFACE_REQUIRED");
  if (net.isIP(cfg.network.lan_address) !== 4 || /^(?:0\.|127\.|169\.254\.|22[4-9]\.|23\d\.)/.test(cfg.network.lan_address) || net.isIP(cfg.network.bind_address) !== 4 || !["0.0.0.0", "127.0.0.1", cfg.network.lan_address].includes(cfg.network.bind_address)) fail("MINIMAL_LAN_ADDRESS_REQUIRED");
  if (!Array.isArray(cfg.network.clients) || !cfg.network.clients.length || cfg.network.clients.some(value => typeof value !== "string" || !/^\d+\.\d+\.\d+\.\d+\/(?:[0-9]|[12][0-9]|3[0-2])$/.test(value))) fail("MINIMAL_NETWORK_ALLOWLIST_REQUIRED");
  for (const value of [cfg.storage.root, cfg.storage.backup_location]) if (typeof value !== "string" || !path.isAbsolute(value) || path.normalize(value) !== value || value === "/" || /[\s,:]/.test(value)) fail("MINIMAL_STORAGE_REQUIRED");
  if (cfg.storage.root === cfg.storage.backup_location || cfg.storage.backup_location.startsWith(cfg.storage.root + "/") || cfg.storage.root.startsWith(cfg.storage.backup_location + "/") || !Number.isInteger(cfg.storage.retention_days) || cfg.storage.retention_days < 1) fail("MINIMAL_BACKUP_POLICY_REQUIRED");
  for (const value of Object.values(cfg.ports)) if (!Number.isInteger(value) || value < 1 || value > 65535) fail("MINIMAL_PORT_INVALID");
  for (const image of Object.values(cfg.images)) if (typeof image !== "string" || !/^(?:[a-zA-Z0-9._/:/-]+@)?sha256:[a-f0-9]{64}$/.test(image)) fail("MINIMAL_IMAGE_PIN_REQUIRED");
  if (!/^[a-f0-9]{40}$/.test(cfg.provenance.revision || "") || cfg.provenance.alignment_sha256 !== require("../dependency-alignment.json").content_sha256) fail("MINIMAL_PROVENANCE_MISMATCH");
  if (!["automatic", "interactive", "test"].includes(cfg.operator.mode) || cfg.operator.mode === "test" && !cfg.deployment.acceptance) fail("MINIMAL_TEST_MODE_FORBIDDEN");
  if (!/^[a-z][a-z0-9._-]{2,63}$/.test(cfg.operator.username || "") || ["nobody", "guest", "system"].includes(cfg.operator.username) || !cfg.deployment.acceptance && /^il[34]-/.test(cfg.operator.username)) fail("MINIMAL_OPERATOR_INVALID");
  if (!/^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/.test(cfg.operator.email || "") || cfg.operator.email.length > 128 || !/^[a-zA-Z0-9][a-zA-Z0-9._:-]{7,127}$/.test(cfg.operator.operation_id || "")) fail("MINIMAL_OPERATOR_INVALID");
  return cfg;
}
module.exports = { validate, fail };
