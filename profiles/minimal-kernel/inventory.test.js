"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const fs = require("node:fs"), path = require("node:path"), os = require("node:os"), crypto = require("node:crypto");
const { validateInventory, verifyArchive, sha256 } = require("./inventory");
const manifest = require("./dependency-manifest.json");
function altered(change) { const value = structuredClone(manifest); change(value); const { content_sha256, ...content } = value; value.content_sha256 = sha256(JSON.stringify(content)); return value; }
test("complete IL-3 dependency graph and acquired source files are inventoried", () => {
  assert.deepEqual(validateInventory(manifest), { valid: true, npm_artifacts: 213, source_files: 71, release_qualified: false });
  assert.equal(manifest.npm.filter(entry => !entry.development_only).length, 53);
  assert.equal(manifest.source_acquisition.modules.length, 7);
  assert.equal(manifest.npm.find(entry => entry.name === "@drumee/infra-layer").classification, "revision-pinned-source");
});
test("edited inventory is rejected before artifact use", () => {
  const value = structuredClone(manifest); value.npm[0].version = "999.0.0";
  assert.throws(() => validateInventory(value), { code: "INVENTORY_DIGEST_MISMATCH" });
});
test("missing required kernel package fails closed", () => {
  assert.throws(() => validateInventory(altered(value => { value.npm = value.npm.filter(entry => entry.name !== "@drumee/server-runtime"); })), { code: "REQUIRED_ARTIFACT_MISSING" });
});
test("older published packages cannot replace the pinned source version", () => {
  assert.throws(() => validateInventory(altered(value => { value.npm.find(entry => entry.name === "@drumee/system-mfs").version = "0.1.0-alpha.1"; })), { code: "WRONG_PACKAGE_REVISION" });
});
test("floating or local artifact locations and missing integrity are rejected", () => {
  for (const location of ["file:../sibling", "https://codeload.github.com/drumee/infra-layer/tar.gz/main", "https://unrelated.invalid/package.tgz"]) assert.throws(() => validateInventory(altered(value => { value.npm[0].resolved = location; })), { code: "UNTRUSTED_ARTIFACT_LOCATION" });
  assert.throws(() => validateInventory(altered(value => { delete value.npm[0].integrity; })), { code: "UNPINNED_PACKAGE_ARTIFACT" });
});
test("duplicate package ownership and unsafe source paths are rejected", () => {
  assert.throws(() => validateInventory(altered(value => value.npm.push(value.npm[0]))), { code: "INVALID_PACKAGE_LOCATION" });
  assert.throws(() => validateInventory(altered(value => { value.source_acquisition.files[0].path = "../escape"; })), { code: "UNSAFE_SOURCE_INVENTORY" });
});
test("inventory cannot claim release readiness", () => {
  assert.throws(() => validateInventory(altered(value => { value.release_qualified = true; })), { code: "INVALID_INVENTORY_CONTRACT" });
});
test("archive checksum is enforced and linked files are refused", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "il4-artifact-"));
  try {
    const filename = path.join(directory, "artifact"); fs.writeFileSync(filename, "nonsecret-test-bytes");
    const entry = { integrity: "sha512-" + crypto.createHash("sha512").update("nonsecret-test-bytes").digest("base64") };
    assert.equal(verifyArchive(entry, filename), true);
    fs.writeFileSync(filename, "changed"); assert.throws(() => verifyArchive(entry, filename), { code: "ARTIFACT_INTEGRITY_MISMATCH" });
    fs.symlinkSync(filename, path.join(directory, "symlink")); assert.throws(() => verifyArchive(entry, path.join(directory, "symlink")), { code: "UNSAFE_ARTIFACT_FILE" });
    fs.linkSync(filename, path.join(directory, "hardlink")); assert.throws(() => verifyArchive(entry, filename), { code: "UNSAFE_ARTIFACT_FILE" });
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
