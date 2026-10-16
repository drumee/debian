"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const { validate, digest } = require("../scripts/alignment");
const manifest = require("../dependency-alignment.json");
function altered(change) { const value = structuredClone(manifest); change(value); delete value.content_sha256; value.content_sha256 = digest(JSON.stringify(value)); return value; }
test("IL-4 alignment preserves the original inventory and adds the exact canonical enrollment", () => {
  assert.deepEqual(validate(manifest), { valid: true, npm_artifacts: 213, source_files: 93, release_qualified: false });
  assert.equal(manifest.baseline.npm_artifacts, 213); assert.equal(manifest.baseline.source_files, 71);
  assert.equal(manifest.operator.revision, "59985d4a78e142b64f5976cc7460a723cca29a79");
});
test("published alpha.1 and wrong runtime integrity cannot replace qualified dependencies", () => {
  assert.throws(() => validate(altered(value => { value.npm.find(entry => entry.location === "node_modules/@drumee/infra-layer").resolved = "https://registry.npmjs.org/@drumee/infra-layer/-/infra-layer-0.1.0-alpha.1.tgz"; })), { code: "INFRASTRUCTURE_PROVENANCE_MISMATCH" });
  assert.throws(() => validate(altered(value => { value.runtime.integrity = "sha512-" + "A".repeat(86) + "=="; })), { code: "RUNTIME_PROVENANCE_MISMATCH" });
});
test("enrollment schema omissions and unsafe source destinations fail closed", () => {
  assert.throws(() => validate(altered(value => { value.sources.files = value.sources.files.filter(file => file.path !== "operator-bootstrap/schemas/SCHEMA_MANIFEST.json"); })), { code: "OPERATOR_SOURCE_MISSING" });
  assert.throws(() => validate(altered(value => { value.sources.files[0].path = "../outside"; })), { code: "UNSAFE_SOURCE_INVENTORY" });
});
