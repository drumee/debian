"use strict";
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const profile = path.resolve(__dirname, ".."), source = require("../infra-source-lock.json");
// Verify the immutable registry acquisition and every installed member before Docker.
function verify(lock = require("../package-lock.json"), manifest = require("../package.json"), directory = path.join(profile, "node_modules/@drumee/infra-layer")) {
  const entry = lock.packages["node_modules/@drumee/infra-layer"], version = source.package.version;
  if (source.acquisition !== "npm-registry" || !/^\d+\.\d+\.\d+-alpha\.\d+$/.test(version) || source.url !== `https://registry.npmjs.org/@drumee/infra-layer/-/infra-layer-${version}.tgz` || source.integrity !== source.package.integrity || source.sha256 !== source.package.sha256 || manifest.devDependencies["@drumee/infra-layer"] !== version || lock.packages[""].devDependencies["@drumee/infra-layer"] !== version || entry?.resolved !== source.url || entry.integrity !== source.integrity || entry.version !== version) throw Error("APPLICATION_INFRASTRUCTURE_PROVENANCE_INVALID");
  const files = [];
  function inspect(root, relative = "") {
    if (!fs.lstatSync(root).isDirectory() || fs.lstatSync(root).isSymbolicLink()) throw Error("APPLICATION_INFRASTRUCTURE_BYTES_INVALID");
    for (const name of fs.readdirSync(root)) {
      const file = path.join(root, name), key = relative + name, stat = fs.lstatSync(file);
      if (stat.isSymbolicLink()) throw Error("APPLICATION_INFRASTRUCTURE_BYTES_INVALID");
      if (stat.isDirectory()) inspect(file, key + "/");
      else if (stat.isFile()) {
        if (crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex") !== source.package.files[key]) throw Error("APPLICATION_INFRASTRUCTURE_BYTES_INVALID");
        files.push(key);
      } else throw Error("APPLICATION_INFRASTRUCTURE_BYTES_INVALID");
    }
  }
  inspect(directory);
  if (files.length !== source.members || files.length !== Object.keys(source.package.files).length) throw Error("APPLICATION_INFRASTRUCTURE_BYTES_INVALID");
  return { acquisition: source.acquisition, version, revision: source.revision, integrity: source.integrity, sha256: source.sha256, package_integrity: source.package.integrity };
}
module.exports = { verify };
