"use strict";
const test = require("node:test"), assert = require("node:assert/strict"), fs = require("node:fs"), os = require("node:os"), path = require("node:path");
const { spawnSync } = require("node:child_process"), cfg = require("./configuration"), { validate, compose } = require("../lib/config"), operator = require("../operator");
test("minimal application selects only its explicit native host and operator metadata", () => {
  const value = cfg(), result = compose(value);
  assert.deepEqual(Object.keys(result.compose.services), ["application"]);
  assert.deepEqual(result.plan.capabilities, []); assert.deepEqual(result.plan.required_secrets, []);
  assert.deepEqual(result.activation_order, ["application"]);
  const intent = JSON.parse(result.distribution.application.environment.DRUMEE_APP_CONFIG);
  assert.deepEqual(intent, { port: 3101, plugins: [] });
  assert.deepEqual(result.compose.services.application.ports, [{ target: 3101, published: 28971, host_ip: "127.0.0.1", protocol: "tcp" }]);
  assert.deepEqual(Object.keys(require("../package.json").dependencies), ["@drumee/server-runtime"]);
  assert.equal(require("../package.json").dependencies["@drumee/server-runtime"], "0.1.0-alpha.4");
});
test("canonical manifest rejects public bindings, mutable images, undeclared dependencies and secret values", () => {
  for (const mutate of [v => v.manifest.external_gateway.host_address = "0.0.0.0", v => v.manifest.external_gateway.host_address = "::1", v => v.manifest.external_gateway.rpc_prefix = "/rpc/", v => v.manifest.application.image = "node:latest", v => v.manifest.application.requires = ["redis"], v => v.manifest.application.environment = { PASSWORD: "never-a-secret" }, v => v.infrastructure.spec.password = "never-a-secret"]) { const value = cfg(); mutate(value); assert.throws(() => validate(value)); }
});
test("operator profile binds identity, resources, ownership, backup policy and immutable code paths", () => {
  for (const key of Object.keys(cfg())) { const value = cfg(); delete value[key]; assert.throws(() => validate(value)); }
  for (const mutate of [v => v.deployment.owner_uid = 0, v => v.infrastructure.spec.instance.id = "unknown", v => v.infrastructure.adapter_input.project = "unknown", v => v.storage.backup_location = v.storage.root + "/backups", v => v.manifest.persistent_resources = [], v => v.manifest.persistent_resources[0].source = "/tmp/unowned", v => v.manifest.application.mounts = [{ resource: "operator-state", target: "/app/plugins", read_only: true }], v => v.manifest.application.environment = { DRUMEE_APP_CONFIG: "{}" }]) { const value = cfg(); mutate(value); assert.throws(() => validate(value)); }
});
test("existing CLI dispatch, JSON renderer and explicit mutation guards work without Docker", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "il5-profile-unit-")), file = path.join(root, "config.json");
  try {
    const value = cfg(path.join(root, "deployment")); fs.writeFileSync(file, JSON.stringify(value));
    const cli = path.resolve(__dirname, "../../../bin/drumee-ctl");
    const selected = spawnSync("bash", [cli, "--profile", "minimal-application", "validate", "--config", file], { encoding: "utf8" }); assert.equal(selected.status, 0, selected.stderr); assert.equal(JSON.parse(selected.stdout).valid, true);
    const rendered = spawnSync(process.execPath, [path.resolve(__dirname, "../../../config/render.mjs"), "compose", "--config", file], { encoding: "utf8" }); assert.equal(rendered.status, 0, rendered.stderr); assert.deepEqual(Object.keys(JSON.parse(rendered.stdout).compose.services), ["application"]);
    await assert.rejects(operator.run({ command: "install", config: file, execute: false }), { code: "APPLICATION_EXECUTION_AUTHORIZATION_REQUIRED" }); assert.equal(fs.existsSync(value.storage.root), false);
    const proxy = await operator.run({ command: "proxy-config", config: file }); assert.equal(proxy.applied, false); assert.match(proxy.content, /location \/-\//); assert.match(proxy.content, /proxy_pass http:\/\/127\.0\.0\.1:28971;/); assert.doesNotMatch(proxy.content, /proxy_pass[^;]+28971\//);
    const rejected = spawnSync("bash", [cli, "--profile", "minimal-application", "install", "--password", "never-echo-me"], { encoding: "utf8" }); assert.equal(rejected.status, 1); assert.deepEqual(JSON.parse(rejected.stderr), { code: "APPLICATION_CLI_USAGE" }); assert.equal(rejected.stdout, "");
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});
test("profile uses public lifecycle exports and adds no session, identity SQL or SMTP stack", () => {
  const text = fs.readFileSync(require.resolve("../operator"), "utf8") + fs.readFileSync(require.resolve("../lib/config"), "utf8");
  assert.doesNotMatch(text, /infra-layer\/(?:lib|lifecycle\/(?!['"]))/);
  assert.doesNotMatch(text, /docker compose|INSERT INTO|createPrivateHub|SessionManager|createHash|nodemailer/);
  const lock = require("../package-lock.json"); assert.equal(lock.packages["node_modules/@drumee/server-runtime"].integrity, "sha512-bOZ/v6/4mQ/FPa8iE21polPx2PjJWFYTKqTz+2duqxI2ljpviemNgOtpwkxF4j/1Xn/1aVIxdvVCc8Tch2ctEQ==");
  assert.equal(lock.packages["node_modules/@drumee/infra-layer"].resolved, "https://codeload.github.com/drumee/infra-layer/tar.gz/aa9057f224f4ae5cf80d777e3cb2fad092193fb1");
});
