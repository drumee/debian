"use strict";
module.exports = function configuration() { return {
  distribution: { profile: "minimal-kernel" }, instance: { domain: "drumee.lan" },
  deployment: { id: "minimal-kernel-test", project: "minimal-kernel-test", owner_uid: process.getuid(), owner_gid: process.getgid(), acceptance: false },
  network: { interface: "eth0", lan_address: "192.168.5.202", bind_address: "127.0.0.1", clients: ["127.0.0.0/8", "172.16.0.0/12", "192.168.5.0/24"] },
  dns: { mode: "local" }, tls: { provider: "local" },
  storage: { root: "/tmp/drumee-il4-test-deployment", backup_location: "/tmp/drumee-il4-test-backups", retention_days: 14 },
  ports: { https: 18443, dns: 15353 }, images: { kernel: "sha256:" + "a".repeat(64), tools: "sha256:" + "b".repeat(64) },
  provenance: { revision: "d035f9ed5af437c323d364dfbd732673f24f6c3e", alignment_sha256: require("../dependency-alignment.json").content_sha256 },
  operator: { mode: "automatic", username: "administrator", email: "administrator@drumee.lan", operation_id: "minimal-initial-administrator-1" }
}; };
