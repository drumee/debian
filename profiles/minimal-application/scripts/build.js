"use strict";
const fs = require("node:fs"), path = require("node:path"), os = require("node:os"), crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");
const profile = path.resolve(__dirname, ".."), repository = path.resolve(profile, "../.."), runtimeSRI = "sha512-bOZ/v6/4mQ/FPa8iE21polPx2PjJWFYTKqTz+2duqxI2ljpviemNgOtpwkxF4j/1Xn/1aVIxdvVCc8Tch2ctEQ==";
const run = (name, args, options = {}) => execFileSync(name, args, { encoding: "utf8", stdio: "pipe", ...options });
function fail(code) { throw Error(code); }
function build(input) {
  if (!input || Object.keys(input).some(key => !["plugins", "tools"].includes(key)) || !Array.isArray(input.plugins) || typeof input.tools !== "boolean") fail("APPLICATION_BUILD_INPUT_INVALID");
  const revision = run("git", ["rev-parse", "HEAD"], { cwd: repository }).trim();
  if (run("git", ["status", "--porcelain", "--", "profiles/minimal-application"], { cwd: repository }).trim()) fail("APPLICATION_SOURCE_MUST_BE_COMMITTED");
  const lock = require("../package-lock.json");
  if (lock.packages["node_modules/@drumee/server-runtime"].version !== "0.1.0-alpha.4" || lock.packages["node_modules/@drumee/server-runtime"].integrity !== runtimeSRI) fail("APPLICATION_RUNTIME_PROVENANCE_INVALID");
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "drumee-il5-build-"));
  try {
    for (const name of ["package.json", "package-lock.json", "Dockerfile"]) fs.copyFileSync(path.join(profile, name), path.join(directory, name));
    fs.cpSync(path.join(profile, "runtime"), path.join(directory, "runtime"), { recursive: true }); fs.mkdirSync(path.join(directory, "plugins"));
    const plugins = [], artifacts = [], ids = new Set();
    for (const plugin of input.plugins) {
      if (Object.keys(plugin).sort().join(",") !== "archive,id,integrity,revision" || !/^[a-z][a-z0-9_-]{0,63}$/.test(plugin.id) || ids.has(plugin.id) || !path.isAbsolute(plugin.archive) || !/^[a-f0-9]{40,64}$/.test(plugin.revision)) fail("APPLICATION_PLUGIN_BUILD_INVALID");
      ids.add(plugin.id);
      const destination = path.join(directory, "plugins", plugin.id);
      const verified = JSON.parse(run("python3", [path.join(__dirname, "plugin-artifact.py"), plugin.archive, plugin.integrity, destination]));
      fs.writeFileSync(path.join(destination, ".drumee-artifact.json"), JSON.stringify({ id: plugin.id, revision: plugin.revision, integrity: plugin.integrity }), { mode: 0o644 });
      plugins.push({ id: plugin.id, root: "/app/plugins/" + plugin.id + "/server", revision: plugin.revision }); artifacts.push({ id: plugin.id, ...verified });
    }
    fs.writeFileSync(path.join(directory, "plugins-manifest.json"), JSON.stringify(plugins), { mode: 0o644 });
    const plugin_digest = crypto.createHash("sha256").update(JSON.stringify(artifacts)).digest("hex"), tag = "drumee-minimal-application:" + revision.slice(0, 16) + "-" + plugin_digest.slice(0, 16);
    run("docker", ["build", "--label", "org.opencontainers.image.source=https://github.com/drumee/debian", "--label", "org.opencontainers.image.revision=" + revision, "--label", "org.drumee.application.plugins=" + plugin_digest, "-t", tag, directory], { stdio: "inherit" });
    const image = run("docker", ["image", "inspect", tag, "--format", "{{.Id}}"] ).trim();
    let tools;
    if (input.tools) {
      const source = path.join(profile, "node_modules/@drumee/infra-layer"), tools_tag = "drumee-minimal-application-tools:" + revision.slice(0, 16);
      run("docker", ["build", "--label", "org.opencontainers.image.source=https://github.com/drumee/infra-layer", "--label", "org.opencontainers.image.revision=c6ef6e9b8d33921ffa39c289490067adfc63a8b0", "-f", path.join(source, "capabilities/docker/Dockerfile.services"), "-t", tools_tag, source], { stdio: "inherit" });
      tools = { tag: tools_tag, image: run("docker", ["image", "inspect", tools_tag, "--format", "{{.Id}}"] ).trim() };
    }
    const receipt = { revision, runtime: { version: "0.1.0-alpha.4", integrity: runtimeSRI }, infrastructure: { revision: "c6ef6e9b8d33921ffa39c289490067adfc63a8b0", integrity: lock.packages["node_modules/@drumee/infra-layer"].integrity }, image, tag, plugins, artifacts, ...(tools ? { tools } : {}) };
    fs.mkdirSync(path.join(profile, ".cache"), { recursive: true }); fs.writeFileSync(path.join(profile, ".cache/images.json"), JSON.stringify(receipt, null, 2), { mode: 0o600 }); return receipt;
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
}
if (require.main === module) { try { console.log(JSON.stringify(build(JSON.parse(fs.readFileSync(process.argv[2]))))); } catch (error) { console.error(/^[A-Z_]+$/.test(error.message || "") ? error.message : "APPLICATION_BUILD_FAILED"); process.exitCode = 1; } }
module.exports = { build };
