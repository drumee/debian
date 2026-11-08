"use strict";
const test = require("node:test"), assert = require("node:assert/strict"), fs = require("node:fs"), os = require("node:os"), path = require("node:path");
const api = require("@drumee/infra-layer"), { createFilesystemSecretStore } = require("@drumee/infra-layer/capabilities/secrets"), { validate } = require("../lib/config"), configuration = require("./configuration"), smtp = require("../../../tests/minimal-application/smtp");
function fixture(user = "provider@example.invalid") {
  const cfg = smtp(configuration(), "sha256:" + "a".repeat(64), "/tmp/synthetic-submission");
  const ref = { resource: "mail-test", key: "upstream" };
  cfg.infrastructure.spec.secrets.resources.push({ ref, type: "smtp-external-credential", consumers: ["mail"] });
  Object.assign(cfg.infrastructure.spec.mail, { mode: "relay", relay_tls: "required", relay_user: user, relay_secret_ref: ref });
  cfg.infrastructure.adapter_input.resource_sources.push({ ref, source: cfg.storage.root + "/durable/projections/upstream" });
  return cfg;
}
test("installed alpha.6 profile separates external accounts from internal submission and requires verified relay TLS", () => {
  for (const user of ["simple", "provider@example.invalid", "opaque +/$ name-é"]) assert.equal(validate(fixture(user)).infrastructure.spec.mail.relay_user, user);
  for (const user of ["", "a:b", " leading", "bad\0name", "bad\rname", "bad\nname", "x".repeat(256)]) {
    const cfg = fixture(user); assert.equal(api.validateSpec(cfg.infrastructure.spec, cfg.infrastructure.requirements).diagnostics.some(x => x.code === "INVALID_SMTP_AUTH_ACCOUNT"), true); assert.throws(() => validate(cfg), { code: "APPLICATION_INFRASTRUCTURE_INVALID" });
  }
  for (const mutate of [cfg => cfg.infrastructure.spec.mail.submission_user = "internal@example.invalid", cfg => cfg.infrastructure.spec.mail.submission_secret_ref = cfg.infrastructure.spec.mail.relay_secret_ref, cfg => cfg.infrastructure.spec.mail.relay_tls = "none"]) { const cfg = fixture(); mutate(cfg); assert.throws(() => validate(cfg), { code: "APPLICATION_INFRASTRUCTURE_INVALID" }); }
});
test("installed canonical external secret import preserves bytes, refuses final newlines and retains consumer ACLs", t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "debian-smtp-contract-")); t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const store = createFilesystemSecretStore(root + "/store", "fixture"), descriptor = { ref: { resource: "mail", key: "upstream" }, type: "smtp-external-credential", consumers: ["mail"] };
  const value = Buffer.from(" leading\t!#$:'\"\\`$() / é:END"); store.import(descriptor, value, { authorized: true });
  assert.equal(store.read(descriptor.ref, "mail").equals(value), true); assert.throws(() => store.read(descriptor.ref, "application"), { code: "SECRET_CONSUMER_FORBIDDEN" });
  store.materialize(descriptor.ref, "mail", root + "/projection/value"); assert.equal(fs.readFileSync(root + "/projection/value").equals(value), true); assert.equal(fs.statSync(root + "/projection/value").mode & 0o777, 0o600);
  for (const bytes of [Buffer.alloc(0), Buffer.from("final\n"), Buffer.from("final\r\n"), Buffer.from("bad\0value"), Buffer.from("bad\rvalue"), Buffer.from("bad\nvalue"), Buffer.from("final "), Buffer.from("final\t"), Buffer.from([0xff]), Buffer.from("\uFEFFvalue"), Buffer.alloc(256, 65)]) assert.throws(() => store.import({ ...descriptor, ref: { resource: "mail", key: "invalid" } }, bytes, { authorized: true }), { code: "SMTP_RELAY_CREDENTIAL_INVALID" });
});
