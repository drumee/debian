"use strict";
const test = require("node:test"), assert = require("node:assert/strict"), fs = require("node:fs");
const configuration = require("./configuration"), { validate } = require("../lib/config"), { compose } = require("../lib/distribution");
test("normal profile uses canonical enrollment, isolated SQL roles and persistent local TLS", () => {
  const cfg = configuration(), result = compose(cfg);
  assert.equal(result.plan.inputs.spec.tls.provider, "local");
  assert.equal(result.plan.inputs.spec.dns.ipv4, cfg.network.lan_address);
  assert.equal(result.plan.inputs.spec.database.accounts.length, 4);
  const kernel = result.distribution.kernel;
  assert.deepEqual(kernel.secret_mounts.map(value => value.ref.key).sort(), ["auth", "runtime"]);
  assert.deepEqual(kernel.mounts.map(value => value.resource).sort(), ["content", "public"]);
  assert.equal(result.distribution.services[0].secret_mounts[0].ref.key, "provisioner");
  assert.deepEqual(result.distribution.init_jobs.map(value => value.id), ["intrinsic-schema", "platform-bootstrap", "platform-authority", "operator-schema", "kernel-schema", "initial-operator", "operator-authentication"]);
  assert.ok(result.activation_order.indexOf("initial-operator") < result.activation_order.indexOf("provisioner"));
  assert.ok(result.activation_order.indexOf("operator-authentication") < result.activation_order.indexOf("kernel"));
  assert.doesNotMatch(fs.readFileSync(require.resolve("../lib/jobs"), "utf8"), /INSERT INTO (?:entity|drumate|privilege)|createPrivateHub|il3-owner/);
  for (const [name, service] of Object.entries(result.compose.services)) if (!["gateway", "dns"].includes(name)) assert.equal((service.ports || []).length, 0);
});
test("profile requires explicit deployment, ownership, provenance, backup and LAN settings", () => {
  for (const section of Object.keys(configuration())) { const cfg = configuration(); delete cfg[section]; assert.throws(() => validate(cfg)); }
  for (const change of [cfg => { cfg.network.interface = "docker0"; }, cfg => { cfg.network.lan_address = "auto"; }, cfg => { cfg.images.kernel = "kernel:latest"; }, cfg => { cfg.provenance.alignment_sha256 = "0".repeat(64); }, cfg => { cfg.storage.backup_location = cfg.storage.root + "/backup"; }]) { const cfg = configuration(); change(cfg); assert.throws(() => validate(cfg)); }
});
test("drumee.lan refuses public ACME, implicit test identities and unprotected credential fields", () => {
  for (const change of [cfg => { cfg.tls.provider = "acme"; }, cfg => { cfg.instance.domain = "example.com"; }, cfg => { cfg.operator.mode = "test"; }, cfg => { cfg.operator.password = "forbidden"; }, cfg => { cfg.operator.username = "system"; }]) { const cfg = configuration(); change(cfg); assert.throws(() => validate(cfg)); }
  const isolated = configuration(); isolated.deployment.acceptance = true; isolated.operator.mode = "test"; assert.equal(validate(isolated), isolated);
});
test("operator parser admits protected descriptors and requires explicit mutation authorization", async () => {
  const { options, run } = require("../operator");
  assert.equal(options(["install", "--password-fd", "3", "--execute"]).password_fd, 3);
  assert.throws(() => options(["install", "--password", "never-a-cli-secret"]), { code: "MINIMAL_CLI_USAGE" });
  const rejected = require("node:child_process").spawnSync(process.execPath, [require.resolve("../operator"), "install", "--password", "never-a-cli-secret"], { encoding: "utf8" });
  assert.equal(rejected.status, 1); assert.deepEqual(JSON.parse(rejected.stderr), { code: "MINIMAL_CLI_USAGE" }); assert.equal(rejected.stdout, "");
  const directory = fs.mkdtempSync("/tmp/drumee-il4-cli-test-");
  try {
    const cfg = configuration(), file = directory + "/config.yaml";
    const yaml = Object.entries(cfg).map(([name, value]) => name + ":\n" + Object.entries(value).map(([key, item]) => "  " + key + ": " + (Array.isArray(item) ? JSON.stringify(item) : JSON.stringify(item))).join("\n")).join("\n");
    fs.writeFileSync(file, yaml);
    await assert.rejects(run({ command: "install", config: file, execute: false }), { code: "MINIMAL_EXECUTION_AUTHORIZATION_REQUIRED" });
    assert.equal(fs.existsSync(cfg.storage.root), false);
  } finally { fs.rmSync(directory, { recursive: true }); }
});
