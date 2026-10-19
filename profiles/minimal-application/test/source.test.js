"use strict";
const test = require("node:test"), assert = require("node:assert/strict"), fs = require("node:fs"), path = require("node:path"), os = require("node:os");
const { verify } = require("../scripts/infrastructure-source"), source = require("../infra-source-lock.json"), lock = require("../package-lock.json"), manifest = require("../package.json");
test("qualified source archive, npm package and installed bytes have separate immutable identities", () => {
  assert.equal(source.revision, "aa9057f224f4ae5cf80d777e3cb2fad092193fb1");
  assert.equal(source.integrity, "sha512-faoNlMWBO05FM+ozsuGu9tqFgq/IYc9WJwb4KCyZcZiTlEIrgJ9QLqLxslTADdipaItg02r2f6qFG07HDxhVqA==");
  assert.notEqual(source.integrity, source.package.integrity);
  assert.equal(Object.keys(source.package.files).length, 40); assert.equal(verify().revision, source.revision);
});
test("source revision, floating URL and wrong artifact integrity fail before building", () => {
  for (const change of [x => x.packages["node_modules/@drumee/infra-layer"].resolved = source.url.replace(source.revision, "main"), x => x.packages["node_modules/@drumee/infra-layer"].integrity = source.package.integrity, x => x.packages[""].devDependencies["@drumee/infra-layer"] = "latest"]) {
    const changed = structuredClone(lock); change(changed); assert.throws(() => verify(changed), /APPLICATION_INFRASTRUCTURE_PROVENANCE_INVALID/);
  }
});
test("modified installed source is rejected independently of matching lock metadata", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "il59b-source-test-"));
  try { fs.cpSync(path.resolve(__dirname, "../node_modules/@drumee/infra-layer"), root, { recursive: true }); fs.appendFileSync(path.join(root, "CHANGELOG.md"), "tampered"); assert.throws(() => verify(lock, manifest, root), /APPLICATION_INFRASTRUCTURE_BYTES_INVALID/); }
  finally { fs.rmSync(root, { recursive: true, force: true }); }
});
