"use strict";
// Portable artifact export; infrastructure composition/identity checks are unchanged.
const fs = require("node:fs"), path = require("node:path"), zlib = require("node:zlib");
const { spawn, execFileSync } = require("node:child_process"), { pipeline } = require("node:stream/promises");
async function main() {
  const [archive, receipt_file = path.join(__dirname, "../.cache/images.json")] = process.argv.slice(2);
  if (!archive || !path.isAbsolute(archive) || !archive.endsWith(".tar.gz") || fs.existsSync(archive) || fs.existsSync(archive + ".json")) throw Error("NEW_ABSOLUTE_ARCHIVE_PATH_REQUIRED");
  const receipt = JSON.parse(fs.readFileSync(receipt_file));
  for (const role of ["kernel", "tools"]) {
    if (!new RegExp("^drumee-minimal-" + role + ":[a-f0-9]{40}$").test(receipt.tags?.[role] || "")) throw Error("IMAGE_BUILD_TAG_INVALID");
    if (execFileSync("docker", ["image", "inspect", receipt.tags[role], "--format", "{{.Id}}"], { encoding: "utf8", stdio: "pipe" }).trim() !== receipt[role]) throw Error("IMAGE_BUILD_TAG_CHANGED");
  }
  const child = spawn("docker", ["save", receipt.tags.kernel, receipt.tags.tools], { stdio: ["ignore", "pipe", "pipe"] });
  child.stderr.resume();
  const completion = new Promise((resolve, reject) => { child.once("error", reject); child.once("exit", code => code === 0 ? resolve() : reject(Error("IMAGE_EXPORT_FAILED"))); });
  await Promise.all([completion, pipeline(child.stdout, zlib.createGzip({ level: 1 }), fs.createWriteStream(archive, { flags: "wx", mode: 0o600 }))]);
  const metadata = execFileSync("python3", [path.join(__dirname, "image-archive.py"), archive, receipt_file], { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"], maxBuffer: 1024 * 1024 });
  fs.writeFileSync(archive + ".json", metadata, { flag: "wx", mode: 0o600 });
  console.log(metadata);
}
main().catch(error => { console.error(/^[A-Z0-9_]+$/.test(error.message || "") ? error.message : "IMAGE_EXPORT_FAILED"); process.exitCode = 1; });
