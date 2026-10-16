"use strict";
// Additive IL-4R inventory. The qualified IL-3 inventory remains unchanged.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");
const root = path.resolve(__dirname, "..");
const digest = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
const fail = code => { throw Object.assign(Error(code), { code }); };
const runtime_integrity = "sha512-bOZ/v6/4mQ/FPa8iE21polPx2PjJWFYTKqTz+2duqxI2ljpviemNgOtpwkxF4j/1Xn/1aVIxdvVCc8Tch2ctEQ==";
function create(repository) {
  const source = require("../sources.lock.json");
  const git = args => execFileSync("git", ["-C", repository, ...args], { maxBuffer: 16 * 1024 * 1024 });
  if (git(["rev-parse", source.revision + "^{commit}"]).toString().trim() !== source.revision) fail("SOURCE_REVISION_UNAVAILABLE");
  const files = Object.entries(source.paths).flatMap(([prefix, destination]) => git(["ls-tree", "-r", source.revision, "--", prefix]).toString().trim().split("\n").map(line => {
    const match = /^(100644|100755) blob ([a-f0-9]{40})\t(.+)$/.exec(line);
    if (!match) fail("UNSAFE_SOURCE_OBJECT");
    return { source: match[3], path: match[3] === prefix ? destination : destination + "/" + match[3].slice(prefix.length + 1), git_blob: match[2], sha256: digest(git(["cat-file", "blob", match[2]])) };
  }));
  const lock = require("../package-lock.json");
  const value = {
    contract_version: 1, profile: "minimal-kernel", release_qualified: false,
    baseline: { path: "dependency-manifest.json", sha256: digest(fs.readFileSync(path.join(root, "dependency-manifest.json"))), npm_artifacts: 213, source_files: 71 },
    runtime: { version: "0.1.0-alpha.4", repository: "https://github.com/drumee/server-runtime.git", revision: "f961f6214432c2e6dbbcde2b926544c076935950", integrity: runtime_integrity, authority_schema: "kb01a-platform-authority-1" },
    infrastructure: { repository: "https://github.com/drumee/infra-layer.git", revision: lock.packages["node_modules/@drumee/infra-layer"].resolved.split("/").pop(), artifact: lock.packages["node_modules/@drumee/infra-layer"], qualification: "unpublished-qualified-development-source; registry alpha.1 lacks lifecycle" },
    operator: { repository: source.repository, revision: source.revision, path: "target/control-plane/operator-bootstrap", schema: "kb01b-initial-operator-1", mode: "canonical-api-only" },
    package_sha256: digest(fs.readFileSync(path.join(root, "package.json"))), lock_sha256: digest(fs.readFileSync(path.join(root, "package-lock.json"))), sources_sha256: digest(fs.readFileSync(path.join(root, "sources.lock.json"))),
    npm: Object.entries(lock.packages).filter(([location]) => location).map(([location, entry]) => ({ location, ...entry })),
    sources: { ...source, files }
  };
  value.content_sha256 = digest(JSON.stringify(value)); return value;
}
function validate(value, directory = root) {
  const { content_sha256, ...content } = value;
  if (value.contract_version !== 1 || value.profile !== "minimal-kernel" || value.release_qualified !== false || digest(JSON.stringify(content)) !== content_sha256) fail("ALIGNMENT_MANIFEST_INVALID");
  for (const [file, expected] of [["dependency-manifest.json", value.baseline.sha256], ["package.json", value.package_sha256], ["package-lock.json", value.lock_sha256], ["sources.lock.json", value.sources_sha256]]) if (digest(fs.readFileSync(path.join(directory, file))) !== expected) fail("ALIGNMENT_INPUT_CHANGED");
  const runtime = value.npm.find(entry => entry.location === "node_modules/@drumee/server-runtime");
  if (runtime?.version !== "0.1.0-alpha.4" || runtime.integrity !== runtime_integrity || value.runtime.integrity !== runtime_integrity) fail("RUNTIME_PROVENANCE_MISMATCH");
  for (const entry of value.npm) {
    if (!/^sha512-[A-Za-z0-9+/]{86}==$/.test(entry.integrity || "") || !/^https:\/\/(?:registry\.npmjs\.org\/[^\s?#]+\.tgz|codeload\.github\.com\/drumee\/[a-z-]+\/tar\.gz\/[a-f0-9]{40})$/.test(entry.resolved || "")) fail("UNPINNED_DEPENDENCY");
  }
  const infrastructure = value.npm.find(entry => entry.location === "node_modules/@drumee/infra-layer");
  if (infrastructure?.resolved !== `https://codeload.github.com/drumee/infra-layer/tar.gz/${value.infrastructure.revision}` || infrastructure.integrity !== value.infrastructure.artifact.integrity) fail("INFRASTRUCTURE_PROVENANCE_MISMATCH");
  if (value.operator.revision !== value.sources.revision || value.operator.mode !== "canonical-api-only") fail("OPERATOR_PROVENANCE_MISMATCH");
  const locations = new Set();
  for (const file of value.sources.files) {
    if (typeof file.path !== "string" || !/^[a-zA-Z0-9_./-]+$/.test(file.path) || file.path.startsWith("/") || file.path.split("/").includes("..") || locations.has(file.path) || !/^[a-f0-9]{40}$/.test(file.git_blob) || !/^[a-f0-9]{64}$/.test(file.sha256)) fail("UNSAFE_SOURCE_INVENTORY");
    locations.add(file.path);
  }
  for (const file of ["operator-bootstrap/lib/enrollment.js", "operator-bootstrap/lib/credentials.js", "operator-bootstrap/schemas/SCHEMA_MANIFEST.json", "operator-bootstrap/schemas/001-initial-operator.sql"]) if (!locations.has(file)) fail("OPERATOR_SOURCE_MISSING");
  return { valid: true, npm_artifacts: value.npm.length, source_files: locations.size, release_qualified: false };
}
if (require.main === module) {
  try {
    const [command, repository] = process.argv.slice(2);
    if (command === "create" && repository) console.log(JSON.stringify(create(repository), null, 2));
    else if (command === "validate" && !repository) console.log(JSON.stringify(validate(require("../dependency-alignment.json"))));
    else fail("USAGE_ALIGNMENT_CREATE_REPOSITORY_OR_VALIDATE");
  } catch (error) { console.error(error.code || "ALIGNMENT_FAILED"); process.exitCode = 1; }
}
module.exports = { create, validate, digest };
