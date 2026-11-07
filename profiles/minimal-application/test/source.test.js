"use strict";
const test = require("node:test"), assert = require("node:assert/strict"), fs = require("node:fs"), path = require("node:path"), os = require("node:os");
const { verify } = require("../scripts/infrastructure-source"), source = require("../infra-source-lock.json"), lock = require("../package-lock.json"), manifest = require("../package.json");
test("published registry acquisition and installed bytes identify qualified alpha.4", () => {
  assert.equal(source.revision, "a8037dd62a50ae4bcb8ab0b36f6a8e1b5f23a0a6");
  assert.equal(source.integrity, "sha512-8R0syrXk74veTYi9AogxGNEOUX6djiLkVIj4DIJ26owR45o8BT9vqI5Bu9Ffuqf1upu80o9/d4ZfnTqvVS2Mqg==");
  assert.equal(source.sha256, "e9ceff871f45331c9f3308c5efa20ab4308b8c59a5b511485be1426645431023");
  assert.equal(source.package.version, "0.1.0-alpha.4");
  assert.equal(Object.keys(source.package.files).length, 43); assert.equal(verify().revision, source.revision);
});
test("floating references, old source integrity and wrong package versions fail before building", () => {
  for (const change of [x => x.packages["node_modules/@drumee/infra-layer"].resolved = "https://codeload.github.com/drumee/infra-layer/tar.gz/main", x => x.packages["node_modules/@drumee/infra-layer"].integrity = "sha512-faoNlMWBO05FM+ozsuGu9tqFgq/IYc9WJwb4KCyZcZiTlEIrgJ9QLqLxslTADdipaItg02r2f6qFG07HDxhVqA==", x => x.packages[""].devDependencies["@drumee/infra-layer"] = "next", x => x.packages["node_modules/@drumee/infra-layer"].version = "0.1.0-alpha.3"]) {
    const changed = structuredClone(lock); change(changed); assert.throws(() => verify(changed), /APPLICATION_INFRASTRUCTURE_PROVENANCE_INVALID/);
  }
  const changed = structuredClone(manifest); changed.devDependencies["@drumee/infra-layer"] = "^0.1.0-alpha.4";
  assert.throws(() => verify(lock, changed), /APPLICATION_INFRASTRUCTURE_PROVENANCE_INVALID/);
});
test("modified, missing, unexpected and linked installed members are rejected", () => {
  for (const mutate of [root => fs.appendFileSync(path.join(root, "CHANGELOG.md"), "tampered"), root => fs.unlinkSync(path.join(root, "CHANGELOG.md")), root => fs.writeFileSync(path.join(root, "unexpected.js"), ""), root => { fs.unlinkSync(path.join(root, "CHANGELOG.md")); fs.symlinkSync(path.resolve(__dirname, "../node_modules/@drumee/infra-layer/CHANGELOG.md"), path.join(root, "CHANGELOG.md")); }]) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "alpha4-installed-test-"));
    try { fs.cpSync(path.resolve(__dirname, "../node_modules/@drumee/infra-layer"), root, { recursive: true }); mutate(root); assert.throws(() => verify(lock, manifest, root), /APPLICATION_INFRASTRUCTURE_BYTES_INVALID/); }
    finally { fs.rmSync(root, { recursive: true, force: true }); }
  }
});
