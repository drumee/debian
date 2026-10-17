"use strict";
module.exports = function configuration(root = "/tmp/drumee-application-example", project = "application-example", image = "sha256:" + "a".repeat(64), port = 28971) {
  const uid = process.getuid(), gid = process.getgid();
  return {
    distribution: { profile: "minimal-application" },
    deployment: { id: project, project, owner_uid: uid, owner_gid: gid, acceptance: false },
    storage: { root, backup_location: root + "-backups", retention_days: 14 },
    infrastructure: {
      spec: { contract_version: "2", instance: { id: project }, dns: { mode: "none" }, http: { enabled: false, https: false }, secrets: { store_resource: "application-secrets", resources: [] } },
      requirements: { contract_version: "2", capabilities: [] },
      adapter_input: { kind: "docker-services", project, network: project + "-application", services: {}, resource_sources: [] }
    },
    manifest: {
      contract_version: "1", id: "minimal-application", profile: "application",
      helper_image: "node:22-bookworm-slim@sha256:c3de60bf2f9dd0ac6370e6117950ff62d6e339527e7472301c9c78a017978392",
      init_jobs: [], schema_versions: {}, external_writers: "none",
      persistent_resources: [{ id: "operator-state", source: root + "/durable/operator-state", uid, gid, backup_required: true }],
      provenance: { repository: "https://github.com/drumee/debian", revision: "1".repeat(40), path: "profiles/minimal-application", acceptance: "real-application" },
      application: { id: "application", image, uid, gid, command: ["node", "/app/host.js"], plugins: [], listener_ports: [3101], requires: [], mounts: [], secret_mounts: [], healthcheck: { test: ["CMD", "node", "/app/health.js"], interval: "2s", timeout: "2s", retries: 10 } },
      external_gateway: { kind: "host-loopback", protocol: "http", host_address: "127.0.0.1", host_port: port, container_port: 3101, route_prefix: "/-/", rpc_prefix: "/-/svc/", tls_termination: "external", readiness_path: "/-/svc/health.ready" }
    }
  };
};
