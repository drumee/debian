"use strict";
const path = require("node:path");
const infra = require("@drumee/infra-layer"), lifecycle = require("@drumee/infra-layer/lifecycle");
const { validate } = require("./config");
const original = require("../dependency-manifest.json").image_sources;
const images = { node: original.node, database: original.database, redis: original.redis, nginx: original.gateway };
function compose(cfg) {
  validate(cfg);
  const { id: instance_id, project, owner_uid: uid, owner_gid: gid } = cfg.deployment;
  const root = cfg.storage.root, durable = name => path.join(root, "durable", name);
  const ref = (resource, key) => ({ resource, key });
  const keys = { admin: ref("database", "admin"), schema: ref("database", "schema"), bootstrap: ref("database", "bootstrap"), enrollment: ref("database", "enrollment"), provisioner: ref("database", "provisioner"), runtime: ref("database", "runtime"), redis: ref("redis", "auth"), ca: ref("tls", "ca-key"), leaf: ref("tls", "leaf-key"), certificate: ref("tls", "certificate"), bundle: ref("tls", "ca-certificate") };
  const resources = [
    [keys.admin, "database-admin", ["database"]], [keys.schema, "database-service", ["database-client", "schema-job"]],
    ...["bootstrap", "enrollment", "provisioner", "runtime"].map(name => [keys[name], "database-service", ["database-account", name]]),
    [keys.redis, "redis-auth", ["redis", "kernel"]], [keys.ca, "tls-ca-key", ["tls-issuer"]], [keys.leaf, "tls-leaf-key", ["gateway", "tls-issuer"]]
  ].map(([ref, type, consumers]) => ({ ref, type, consumers }));
  const spec = {
    contract_version: "2", instance: { id: instance_id, domain: cfg.instance.domain }, http: { enabled: true, https: true },
    dns: { mode: cfg.dns.mode, ipv4: cfg.network.lan_address, serial: 1, clients: cfg.network.clients, listen: ["0.0.0.0"], recursion: false, state_resource: "dns-state" },
    tls: { provider: cfg.tls.provider, certificate_ref: keys.certificate, private_key_ref: keys.leaf, ca_key_ref: keys.ca, ca_bundle_ref: keys.bundle, state_resource: "tls-state", leaf_days: 30, renew_before_days: 10 },
    database: { mode: "managed", endpoint: { host: "database", port: 3306, transport: "tcp" }, engine_series: "11.4", admin_secret_ref: keys.admin, service_secret_ref: keys.schema, service_user: "kernel_schema", state_resource: "database-state", initialize: true,
      accounts: ["bootstrap", "enrollment", "provisioner", "runtime"].map(name => ({ user: "kernel_" + name, secret_ref: keys[name] })) },
    redis: { mode: "managed", endpoint: { host: "redis", port: 6379, transport: "tcp" }, auth_secret_ref: keys.redis, persistence: "ephemeral" },
    secrets: { store_resource: "infrastructure-secrets", resources }
  };
  const requirements = { contract_version: "2", capabilities: ["http-gateway", "tls", "dns", "database", "redis"], http: {
    service_endpoint: { host: "kernel", port: 3101, transport: "tcp" }, page_endpoint: { host: "kernel", port: 3102, transport: "tcp" }, websocket_endpoint: { host: "kernel", port: 3101, transport: "tcp" },
    public_assets: [{ id: "plugins", url_prefix: "/-/plugins/", root: "/public/plugins" }], delegated_artifact_root: "/content", internal_artifact_prefix: "/__drumee_artifacts/", max_binary_chunk_bytes: 1024 * 1024, readiness_path: "/__ready", bootstrap_paths: ["/bootstrap.js"]
  } };
  const tool = (data_source, listen_port) => ({ image: cfg.images.tools, uid, gid, data_source, listen_port, bindings: [] });
  const gateway = { kind: "docker-nginx", project, network: project + "-kernel", image: images.nginx, listen_port: 8080, health_port: 9180, bindings: [{ host_address: cfg.network.bind_address, host_port: cfg.ports.https }],
    artifact_view: { source: durable("content"), target: "/srv/protected", kernel_target: "/content" }, public_views: [{ id: "plugins", source: durable("public") + "/plugins", target: "/srv/public/plugins" }],
    tls_views: [{ ref: keys.certificate, source: root + "/logical/certificate", target: "/run/secrets/tls-certificate" }, { ref: keys.leaf, source: root + "/logical/key", target: "/run/secrets/tls-private-key" }],
    tmpfs_bytes: 32 * 1024 * 1024, timeouts: { client_body_seconds: 5, upstream_seconds: 30, websocket_seconds: 90, send_seconds: 10 } };
  const adapter = { kind: "docker-services", project, network: project + "-kernel", gateway, services: {
    dns: { ...tool(durable("dns"), 1053), bindings: ["tcp", "udp"].map(protocol => ({ host_address: cfg.network.bind_address, host_port: cfg.ports.dns, protocol })) },
    database: { ...tool(durable("database"), 3306), image: images.database, uid: 0, gid: 0 }, redis: { image: images.redis, uid, gid, listen_port: 6379, bindings: [] }
  }, resource_sources: [keys.admin, keys.redis].map(ref => ({ ref, source: root + "/logical/" + ref.resource + "-" + ref.key })) };
  const plan = infra.planInfrastructure(spec, requirements, adapter);
  if (!plan.applicable) throw Object.assign(Error("MINIMAL_INFRASTRUCTURE_PLAN_REJECTED"), { code: "MINIMAL_INFRASTRUCTURE_PLAN_REJECTED", diagnostics: plan.diagnostics });
  const mount = (resource, target, read_only) => ({ resource, target, read_only });
  const sql = (name, consumer = name) => ({ ref: keys[name], consumer, target: "/run/infra/database", format: "raw" });
  const environment = { DRUMEE_OPERATOR_INTENT: JSON.stringify({ domain: cfg.instance.domain, ...cfg.operator }), DRUMEE_ACCEPTANCE: String(cfg.deployment.acceptance) };
  const jobs = [], job = (id, role, command, mounts = []) => {
    const result = { id, image: cfg.images.kernel, uid, gid, entrypoint: ["node"], command: ["lib/jobs.js", command, "install"], validation_command: ["node", "lib/jobs.js", command, "validate"], effect: "idempotent", artifact_revision: cfg.provenance.revision,
      environment: { ...environment, DRUMEE_SQL_ROLE: role }, requires: ["database", "redis", ...jobs.map(value => value.id)], mounts, secret_mounts: [sql(role, role === "schema" ? "schema-job" : role)] };
    jobs.push(result); return result;
  };
  job("intrinsic-schema", "schema", "intrinsic");
  job("platform-bootstrap", "bootstrap", "platform");
  job("platform-authority", "schema", "authority");
  job("operator-schema", "schema", "operator-schema");
  job("kernel-schema", "schema", "kernel-schema");
  job("initial-operator", "enrollment", "enroll", [mount("operator-state", "/operator-state", false)]);
  job("operator-authentication", "runtime", "authenticate", [mount("operator-state", "/operator-state", true)]);
  const readiness = port => ({ test: ["CMD", "node", "-e", `fetch('http://127.0.0.1:${port}/${port === 3103 ? "-/svc/health.ready" : "__ready"}').then(r=>process.exit(r.status===200?0:1)).catch(()=>process.exit(1))`], interval: "2s", timeout: "3s", retries: 30 });
  const requires = ["database", "redis", ...jobs.map(value => value.id)];
  const distribution = { contract_version: "1", id: "debian-minimal-kernel", profile: "kernel", helper_image: images.node, external_writers: "none", init_jobs: jobs,
    persistent_resources: ["content", "operator-state", "public"].map(id => ({ id, source: durable(id), uid, gid, backup_required: true })),
    schema_versions: { runtime: "kb01a-platform-authority-1", operator: "kb01b-initial-operator-1", platform: "git-59985d4a78e142b64f5976cc7460a723cca29a79", hub: "git-59985d4a78e142b64f5976cc7460a723cca29a79", mfs: "phase4.8-system-mfs-2" },
    provenance: { repository: "https://github.com/drumee/debian", revision: cfg.provenance.revision, path: "profiles/minimal-kernel", acceptance: "real-kernel" },
    services: [{ id: "provisioner", image: cfg.images.kernel, uid, gid, entrypoint: ["node"], command: ["lib/provisioner.js"], environment: { DRUMEE_SQL_ROLE: "provisioner" }, requires, mounts: [], secret_mounts: [sql("provisioner")], listener_ports: [3103], healthcheck: readiness(3103) }],
    kernel: { id: "kernel", image: cfg.images.kernel, uid, gid, entrypoint: ["node"], command: ["lib/host.js"], environment: { DRUMEE_SQL_ROLE: "runtime", DRUMEE_DOMAIN: cfg.instance.domain }, requires: [...requires, "provisioner"], mounts: [mount("content", "/content", false), mount("public", "/public", true)], secret_mounts: [sql("runtime"), { ref: keys.redis, consumer: "kernel", target: "/run/infra/redis-config.json", format: "redis-client-config" }], listener_ports: [3101, 3102], healthcheck: readiness(3102) }
  };
  return lifecycle.composeDeployment(plan, distribution);
}
module.exports = { compose, images };
