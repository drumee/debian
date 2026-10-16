"use strict";
// Explicit pinned acquisition; never writes to transient/sources or sibling repos.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");
const root = path.resolve(__dirname, "..");
const lock = require("../sources.lock.json");
function acquire() {
  const alignment = require("../dependency-alignment.json");
  require("./alignment").validate(alignment);
  const cache = path.join(root, ".cache"); fs.mkdirSync(cache, { recursive: true });
  const checkout = path.join(cache, lock.revision);
  fs.mkdirSync(checkout, { recursive: true });
  if (fs.lstatSync(checkout).isSymbolicLink()) throw Error("UNSAFE_SOURCE_CACHE");
  execFileSync("git", ["init", "-q", checkout]);
  execFileSync("git", ["-C", checkout, "config", "http.version", "HTTP/1.1"]);
  execFileSync("git", ["-C", checkout, "config", "remote.origin.url", lock.repository]);
  execFileSync("git", ["-C", checkout, "config", "remote.origin.promisor", "true"]);
  execFileSync("git", ["-C", checkout, "config", "remote.origin.partialclonefilter", "blob:none"]);
  let present = false;
  try { present = execFileSync("git", ["-C", checkout, "rev-parse", "--verify", lock.revision + "^{commit}"], { encoding: "utf8", stdio: "pipe" }).trim() === lock.revision; } catch (_) {}
  if (!present) execFileSync("git", ["-C", checkout, "fetch", "--quiet", "--depth=1", "--filter=blob:none", "origin", lock.revision], { stdio: "pipe", timeout: 180000 });
  const entries = Object.entries(lock.paths).flatMap(([source, destination]) => execFileSync("git", ["-C", checkout, "ls-tree", "-r", lock.revision, "--", source], { encoding: "utf8" }).trim().split("\n").map(record => ({ record, source, destination })));
  const blobs = [...new Set(entries.map(({ record }) => /^(?:100644|100755) blob ([a-f0-9]+)\t/.exec(record)?.[1]).filter(Boolean))];
  // Fetch only the allowlisted blobs in one request, not historical payloads.
  execFileSync("git", ["-C", checkout, "fetch", "--quiet", "--no-tags", "--no-write-fetch-head", "origin", ...blobs], { stdio: "pipe", timeout: 180000 });
  const vendor = path.join(root, "vendor"); fs.mkdirSync(vendor, { recursive: true });
  const inventory = [];
  for (const { record, source, destination } of entries) {
      const match = /^(100644|100755) blob ([a-f0-9]+)\t(.+)$/.exec(record);
      if (!match) throw Error("UNSAFE_SOURCE_OBJECT");
      const relative = match[3] === source ? destination : path.join(destination, path.relative(source, match[3]));
      if (relative.split(path.sep).some(value => value === ".." || value === "node_modules")) throw Error("UNSAFE_SOURCE_PATH");
      const bytes = execFileSync("git", ["-C", checkout, "cat-file", "blob", match[2]], { maxBuffer: 8 * 1024 * 1024 });
      const expected = alignment.sources.files.find(entry => entry.source === match[3] && entry.path === relative);
      if (!expected || expected.git_blob !== match[2] || expected.sha256 !== crypto.createHash("sha256").update(bytes).digest("hex")) throw Error("SOURCE_INTEGRITY_MISMATCH");
      const file = path.join(vendor, relative); fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, bytes, { mode: 0o644 });
      inventory.push({ source: match[3], path: relative, sha256: crypto.createHash("sha256").update(bytes).digest("hex") });
  }
  if (inventory.length !== alignment.sources.files.length) throw Error("SOURCE_INVENTORY_MISMATCH");
  fs.writeFileSync(path.join(vendor, "inventory.json"), JSON.stringify({ ...lock, files: inventory }, null, 2) + "\n");
  console.log(`Pinned source files verified: ${inventory.length}`);
}
if (require.main === module) acquire();
module.exports = { acquire };
