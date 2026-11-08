"use strict";
const test = require("node:test"), assert = require("node:assert/strict"), fs = require("node:fs"), path = require("node:path"), os = require("node:os");
const { verify } = require("../scripts/infrastructure-source"), source = require("../infra-source-lock.json"), lock = require("../package-lock.json"), manifest = require("../package.json");
test("published registry acquisition and installed bytes identify qualified alpha.6", () => {
  assert.equal(source.revision, "09b7f28bce99ba3744e31a0ee5b2dde868a9a86a");
  assert.equal(source.integrity, "sha512-ZuGENEDYE1Ug6FJYzvSR+MG8zzOaBMBkYhgx+5nNR5OKMDBHpOvCfdzDe1XNfNz7fKqRfCHFQZGlxvYQzEm+YQ==");
  assert.equal(source.sha256, "562a01bf5d8dba6151bf3a1768e56655df9e9302ed2ea6f072a4ed72eb177874");
  assert.equal(source.package.version, "0.1.0-alpha.6");
  assert.equal(source.package.files["lib/smtp-auth.js"], "c64632ccd15a366ce12b55a25c716067dacd2fe2ba356d86880e3adad08ffab9");
  assert.equal(Object.keys(source.package.files).length, 44); assert.equal(verify().revision, source.revision);
});
test("floating references, old source integrity and wrong package versions fail before building", () => {
  for (const change of [x => x.packages["node_modules/@drumee/infra-layer"].resolved = "https://codeload.github.com/drumee/infra-layer/tar.gz/main", x => x.packages["node_modules/@drumee/infra-layer"].integrity = "sha512-faoNlMWBO05FM+ozsuGu9tqFgq/IYc9WJwb4KCyZcZiTlEIrgJ9QLqLxslTADdipaItg02r2f6qFG07HDxhVqA==", x => x.packages[""].devDependencies["@drumee/infra-layer"] = "next", x => x.packages["node_modules/@drumee/infra-layer"].version = "0.1.0-alpha.3"]) {
    const changed = structuredClone(lock); change(changed); assert.throws(() => verify(changed), /APPLICATION_INFRASTRUCTURE_PROVENANCE_INVALID/);
  }
  const changed = structuredClone(manifest); changed.devDependencies["@drumee/infra-layer"] = "^0.1.0-alpha.6";
  assert.throws(() => verify(lock, changed), /APPLICATION_INFRASTRUCTURE_PROVENANCE_INVALID/);
});
test("modified, missing, unexpected and linked installed members are rejected", () => {
  for (const mutate of [root => fs.appendFileSync(path.join(root, "lib/smtp-auth.js"), "tampered"), root => fs.unlinkSync(path.join(root, "lib/smtp-auth.js")), root => fs.writeFileSync(path.join(root, "unexpected.js"), ""), root => { fs.unlinkSync(path.join(root, "CHANGELOG.md")); fs.symlinkSync(path.resolve(__dirname, "../node_modules/@drumee/infra-layer/CHANGELOG.md"), path.join(root, "CHANGELOG.md")); }]) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "alpha4-installed-test-"));
    try { fs.cpSync(path.resolve(__dirname, "../node_modules/@drumee/infra-layer"), root, { recursive: true }); mutate(root); assert.throws(() => verify(lock, manifest, root), /APPLICATION_INFRASTRUCTURE_BYTES_INVALID/); }
    finally { fs.rmSync(root, { recursive: true, force: true }); }
  }
});
