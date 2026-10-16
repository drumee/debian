"use strict";
// Explicit acceptance-only SMTP inputs. Capture mode never attempts Internet
// delivery. Production relay configuration remains the canonical mail contract.
module.exports = function smtp(cfg, tools, imported) {
  const root = cfg.storage.root, ref = key => ({ resource: "mail-test", key });
  const ca = ref("ca-key"), leaf = ref("leaf-key"), certificate = ref("certificate"), bundle = ref("ca-certificate"), password = ref("submission"), dkim = ref("dkim");
  const spec = cfg.infrastructure.spec, adapter = cfg.infrastructure.adapter_input;
  spec.instance.domain = "drumee.lan";
  spec.secrets.resources = [
    { ref: ca, type: "tls-ca-key", consumers: ["tls-issuer"] },
    { ref: leaf, type: "tls-leaf-key", consumers: ["mail", "tls-issuer"] },
    { ref: password, type: "smtp-relay-credential", consumers: ["application", "mail"] },
    { ref: dkim, type: "dkim-key", consumers: ["dkim"] }
  ];
  spec.tls = { provider: "local", certificate_ref: certificate, private_key_ref: leaf, ca_key_ref: ca, ca_bundle_ref: bundle, state_resource: "tls-state", leaf_days: 30, renew_before_days: 10 };
  spec.mail = { mode: "capture", endpoint: { host: "mail", port: 2525, transport: "tcp" }, hostname: "drumee.lan", relay_endpoint: { host: "capture", port: 2525, transport: "tcp" }, relay_tls: "none", submission_user: "fixture", submission_secret_ref: password, clients: ["127.0.0.1/32"], queue_resource: "mail-queue", initialize: true, dkim: { domain: "drumee.lan", selector: "infra", key_ref: dkim } };
  adapter.services = { mail: { image: tools, uid: 0, gid: 0, data_source: root + "/durable/mail", listen_port: 2525, bindings: [] }, dkim: { image: tools, uid: process.getuid(), gid: process.getgid(), listen_port: 8891, bindings: [] } };
  adapter.resource_sources = [[leaf, "leaf"], [certificate, "certificate"], [bundle, "bundle"], [password, "submission"], [dkim, "dkim"]].map(([ref, name]) => ({ ref, source: root + "/durable/projections/" + name }));
  cfg.imports = [{ ref: password, file: imported }];
  cfg.manifest.application.secret_mounts = [{ ref: password, consumer: "application", target: "/run/secrets/submission", format: "raw" }, { ref: bundle, consumer: "application", target: "/run/secrets/mail-ca", format: "tls-ca-bundle" }];
  cfg.manifest.application.environment = { APP_SMTP_CONFIG: JSON.stringify({ host: "mail", port: 2525, user: "fixture", servername: "drumee.lan", ca_file: "/run/secrets/mail-ca", password_file: "/run/secrets/submission" }) };
  return cfg;
};
