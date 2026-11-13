"use strict";
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto"), { createRequire } = require("node:module");
function verify(root, receipt) {
  const seen = [];
  function walk(dir, prefix = "") {
    for (const name of fs.readdirSync(dir)) {
      const relative = prefix + name, file = path.join(dir, name), s = fs.lstatSync(file);
      if (s.isSymbolicLink() || s.uid !== process.getuid() || (s.mode & 0o022)) throw Error("MAIL_INSTALLED_MEMBER_UNSAFE");
      if (s.isDirectory()) walk(file, relative + "/");
      else {
        if (!s.isFile() || s.nlink !== 1 || !Object.hasOwn(receipt.files, relative) || crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex") !== receipt.files[relative]) throw Error("MAIL_INSTALLED_MEMBER_MISMATCH");
        seen.push(relative);
      }
    }
  }
  walk(root);
  if (JSON.stringify(seen.sort()) !== JSON.stringify(Object.keys(receipt.files).sort())) throw Error("MAIL_INSTALLED_INVENTORY_MISMATCH");
}
function api() {
  const consumer = path.join(__dirname, ".cache/consumer");
  verify(path.join(consumer, "node_modules/@drumee/infra-layer"), require("./infra-source-lock.json"));
  return createRequire(path.join(consumer, "package.json"))("@drumee/infra-layer/mail-service");
}
module.exports = { api, verify };
