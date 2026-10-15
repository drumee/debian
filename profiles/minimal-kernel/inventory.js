"use strict";
// Read-only qualification tooling. This does not plan, install or activate
// infrastructure and contains no replacement for Infra Layer's lifecycle.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");
const revision = "c5ee4591c87e7be2a7d91398cfcaa277787558e0";
const fixture_path = "target/distributions/minimal-kernel-il3";
const versions = { "@drumee/server-runtime": "0.1.0-alpha.3", "@drumee/ui-runtime": "0.1.0-alpha.2", "@drumee/system-mfs": "0.1.0-alpha.2", "@drumee/finder": "0.1.0-alpha.4", "@drumee/window-manager": "0.1.0-alpha.2", "@drumee/infra-layer": "0.1.0-alpha.1" };
const sha256 = value => crypto.createHash("sha256").update(value).digest("hex");
const fail = code => { throw Object.assign(Error(code), { code }); };
const sources = {
  "@drumee/server-runtime": ["server-runtime", "fc7d9de3f3e63baea8258885e55efe8e242904d0", "HTTP/session/ACL/WebSocket and intrinsic schemas"],
  "@drumee/ui-runtime": ["ui-runtime", "5366d904356b414e87848a0bc8870b612e6c748a", "LETC runtime and frontend transport"],
  "@drumee/finder": ["finder", "b46e2c94b615a1993b6162716d9e8965d0029564", "Finder system application"],
  "@drumee/window-manager": ["window-manager", "e294979dfcb59f73af19975e40f890a0b366cd8c", "Window host"],
  "@drumee/system-mfs": ["system-mfs", "53101c4a995ffca9118f795ab5d4c7c731200a2f", "MFS schemas, provisioning, permissions and content API"],
  "@drumee/infra-layer": ["infra-layer", "95db6c7aed097b62aa8081df17b3467d850e779c", "Unpublished IL-3 plan, composition, activation and recovery (build/operator only)"]
};
function createInventory(repository) {
  const git = args => execFileSync("git", ["-C", repository, ...args], { maxBuffer: 16 * 1024 * 1024 });
  const read = (ref, file) => git(["show", ref + ":" + file]);
  if (git(["rev-parse", revision + "^{commit}"]).toString().trim() !== revision) fail("SOURCE_REVISION_UNAVAILABLE");
  const package_bytes = read(revision, fixture_path + "/package.json");
  const lock_bytes = read(revision, fixture_path + "/package-lock.json");
  const source_bytes = read(revision, fixture_path + "/sources.lock.json");
  const manifest = JSON.parse(package_bytes), lock = JSON.parse(lock_bytes), acquired = JSON.parse(source_bytes);
  const npm = Object.entries(lock.packages).filter(([name]) => name).map(([location, entry]) => {
    const name = location.slice(location.lastIndexOf("node_modules/") + 13);
    const direct = Object.hasOwn(manifest.dependencies, name) || Object.hasOwn(manifest.devDependencies, name);
    const source = direct && sources[name];
    return { location, name, version: entry.version, resolved: entry.resolved, integrity: entry.integrity,
      classification: entry.resolved?.startsWith("https://codeload.github.com/") ? "revision-pinned-source" : "published-immutable-npm",
      development_only: entry.dev === true, optional: entry.optional === true,
      license: entry.license || "UNRECORDED_IN_LOCKFILE",
      repository: source ? "https://github.com/drumee/" + source[0] : null,
      source_revision: source ? source[1] : null,
      role: source ? source[2] : direct ? "Explicit fixture dependency" : "Transitive dependency; installed only at its locked location",
      dependencies: entry.dependencies || {}, peer_dependencies: entry.peerDependencies || {},
      owner: source ? "drumee/" + source[0] : "upstream npm package maintainer",
      compatibility_tests: direct ? "transient/tests/integration/infra-il3; IL-4 qualification pending" : "Consuming package tests; no independent transitive compatibility claim"
    };
  });
  const treeFiles = (ref, prefix) => git(["ls-tree", "-r", ref, "--", prefix]).toString().trim().split("\n").map(line => {
    const match = /^(100644|100755) blob ([a-f0-9]{40})\t(.+)$/.exec(line); if (!match) fail("UNSAFE_SOURCE_OBJECT");
    const bytes = git(["cat-file", "blob", match[2]]);
    return { path: match[3], git_blob: match[2], sha256: sha256(bytes) };
  });
  const acquired_files = Object.entries(acquired.paths).flatMap(([source, destination]) => treeFiles(acquired.revision, source).map(entry => ({ ...entry, destination: entry.path === source ? destination : destination + "/" + entry.path.slice(source.length + 1) })));
  const private_modules = Object.entries(acquired.paths).filter(([source]) => source.startsWith("target/")).map(([source, destination]) => {
    const pkg = JSON.parse(read(acquired.revision, source + "/package.json"));
    return { source, destination, package: pkg.name, version: pkg.version, classification: "revision-pinned-source", license: pkg.license || "UNDECLARED_IN_PACKAGE_METADATA", owner: "drumee/transient", revision: acquired.revision, role: destination === "ui-build" ? "build-only" : "kernel/control-plane capability", configuration: "Explicit composition adapters and kernel-owned manifests; see IL-3 fixture lib/components.js and lib/host.js", compatibility_tests: "transient/tests/integration/kernel and tests/integration/infra-il3" };
  });
  const result = {
    contract_version: "1", profile: "minimal-kernel", qualification: "inventory-only", release_qualified: false,
    fixture: { repository: "https://github.com/drumee/transient.git", revision, path: fixture_path, license: "AGPL-3.0-only (fixture glue; acquired notices retained)", files: treeFiles(revision, fixture_path), package_sha256: sha256(package_bytes), lock_sha256: sha256(lock_bytes), sources_lock_sha256: sha256(source_bytes) },
    npm, source_acquisition: { ...acquired, files: acquired_files, modules: private_modules,
      essentials_upstream_revision: "b9460ba442c9962471a592c49ce36b01e0327ff5", essentials_license: "AGPL-3.0; original LICENSE included in acquired paths", source_integrity: "Per-file SHA-256 and Git blob identity; verified against immutable commit" },
    distribution_owned: ["lib/database.js", "lib/components.js", "lib/host.js", "browser/entry.js", "scripts/browser.js"].map(file => ({ file, classification: "distribution-owned-implementation", owner: "drumee/transient IL-3 fixture; proposed migration owner drumee/debian", acceptance_only: ["lib/host.js", "browser/entry.js"].includes(file) })),
    test_only: ["lib/initialize.js (disposable owner/reader/outsider identities)", "lib/distribution-driver.js (ALL on yp and hub_* for fixture)", "lib/distribution.js (acceptance domain/network/paths)", "tests/integration/infra-il3/* (acceptance, NOT installation)"],
    historical_to_eliminate: ["Team role-app/server-pod", "schemas/populate.js and factory pools", "legacy Caddy gateway", "legacy drumee-ctl database-only recovery"],
    image_sources: { node: "node:22-bookworm-slim@sha256:c3de60bf2f9dd0ac6370e6117950ff62d6e339527e7472301c9c78a017978392", database: "mariadb@sha256:611a2fcc5fa7c6ceb8644c6f74b25ede004ff6c3a6b38c8f8c23d3bbf6c26430", redis: "redis@sha256:ff02b58f971e7d7d156a1267e283fcbbeee91773b6aa36c49dac28ecfe28eadf", gateway: "nginx@sha256:4a73073bd557c65b759505da037898b61f1be6cbcc3c2c3aeac22d2a470c1752" },
    prerequisites: ["Kernel-owned first-human/operator provisioning contract", "Approved runtime/provisioner SQL role separation", "License metadata confirmation for private transitional modules", "Qualified Infra Layer candidate artifact containing lifecycle APIs; registry alpha.1 is insufficient"],
    unsupported: ["SMTP full recovery", "Automatic trust/resolver installation", "Production installation from acceptance accounts", "Schema downgrade by image switch"]
  };
  result.content_sha256 = sha256(JSON.stringify(result)); validateInventory(result); return result;
}
function validateInventory(value) {
  if (!value || value.contract_version !== "1" || value.profile !== "minimal-kernel" || value.release_qualified !== false || value.qualification !== "inventory-only") fail("INVALID_INVENTORY_CONTRACT");
  const { content_sha256, ...content } = value;
  if (sha256(JSON.stringify(content)) !== content_sha256) fail("INVENTORY_DIGEST_MISMATCH");
  if (value.fixture?.revision !== revision || value.fixture.path !== fixture_path || !Array.isArray(value.npm) || !Array.isArray(value.source_acquisition?.files)) fail("INVENTORY_SOURCE_MISMATCH");
  const locations = new Set();
  for (const entry of value.npm) {
    if (typeof entry.location !== "string" || !/^node_modules\/(?:@?[a-zA-Z0-9_.-]+\/)*[a-zA-Z0-9_.-]+$/.test(entry.location) || entry.location.split("/").includes("..") || locations.has(entry.location)) fail("INVALID_PACKAGE_LOCATION");
    locations.add(entry.location);
    if (!/^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?$/.test(entry.version || "") || !/^sha512-[A-Za-z0-9+/]{86}==$/.test(entry.integrity || "")) fail("UNPINNED_PACKAGE_ARTIFACT");
    if (!/^https:\/\/(?:registry\.npmjs\.org\/[^\s?#]+\.tgz|codeload\.github\.com\/drumee\/[a-z-]+\/tar\.gz\/[a-f0-9]{40})$/.test(entry.resolved || "")) fail("UNTRUSTED_ARTIFACT_LOCATION");
  }
  for (const name of Object.keys(sources)) {
    const entry = value.npm.find(entry => entry.location === "node_modules/" + name);
    if (!entry) fail("REQUIRED_ARTIFACT_MISSING");
    if (entry.source_revision !== sources[name][1] || entry.version !== versions[name]) fail("WRONG_PACKAGE_REVISION");
  }
  for (const entry of [...value.fixture.files, ...value.source_acquisition.files]) if (!/^[a-f0-9]{64}$/.test(entry.sha256 || "") || !/^[a-f0-9]{40}$/.test(entry.git_blob || "") || typeof entry.path !== "string" || entry.path.startsWith("/") || entry.path.split("/").includes("..")) fail("UNSAFE_SOURCE_INVENTORY");
  return { valid: true, npm_artifacts: value.npm.length, source_files: value.source_acquisition.files.length, release_qualified: false };
}
function verifyArchive(entry, filename) {
  if (!entry || !/^sha512-[A-Za-z0-9+/]{86}==$/.test(entry.integrity || "")) fail("INVALID_ARTIFACT_INTEGRITY");
  const stat = fs.lstatSync(filename); if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) fail("UNSAFE_ARTIFACT_FILE");
  const integrity = "sha512-" + crypto.createHash("sha512").update(fs.readFileSync(filename)).digest("base64");
  if (integrity !== entry.integrity) fail("ARTIFACT_INTEGRITY_MISMATCH"); return true;
}
if (require.main === module) {
  try {
    const [command, argument] = process.argv.slice(2);
    if (command === "create" && argument) console.log(JSON.stringify(createInventory(path.resolve(argument)), null, 2));
    else if (command === "validate" && !argument) console.log(JSON.stringify(validateInventory(require("./dependency-manifest.json"))));
    else fail("USAGE_INVENTORY_CREATE_REPOSITORY_OR_VALIDATE");
  } catch (error) { console.error(/^[A-Z0-9_]+$/.test(error.code || "") ? error.code : "INVENTORY_FAILED"); process.exitCode = 1; }
}
module.exports = { createInventory, validateInventory, verifyArchive, sha256 };
