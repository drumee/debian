"use strict";
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const profile = path.resolve(__dirname, ".."), source = require("../infra-source-lock.json");
// Verify installed bytes as well as npm's acquisition lock before any Docker build.
function verify(lock = require("../package-lock.json"), manifest = require("../package.json"), directory = path.join(profile, "node_modules/@drumee/infra-layer")) {
  const entry = lock.packages["node_modules/@drumee/infra-layer"];
  if (manifest.devDependencies["@drumee/infra-layer"] !== source.url || lock.packages[""].devDependencies["@drumee/infra-layer"] !== source.url || entry?.resolved !== source.url || entry.integrity !== source.integrity || entry.version !== source.package.version) throw Error("APPLICATION_INFRASTRUCTURE_PROVENANCE_INVALID");
  for (const [name, expected] of Object.entries(source.package.files)) {
    const file = path.join(directory, name), stat = fs.lstatSync(file);
    if (!stat.isFile() || stat.isSymbolicLink() || crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex") !== expected) throw Error("APPLICATION_INFRASTRUCTURE_BYTES_INVALID");
  }
  return { revision: source.revision, integrity: source.integrity, sha256: source.sha256, package_integrity: source.package.integrity };
}
module.exports = { verify };
