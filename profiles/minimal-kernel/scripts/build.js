"use strict";
const fs = require("node:fs"), path = require("node:path");
const { execFileSync } = require("node:child_process");
const root = path.resolve(__dirname, "..");
const { verify } = require("./verify");
function command(program, args, options = {}) { return execFileSync(program, args, { cwd: root, encoding: "utf8", stdio: "pipe", ...options }); }
async function build() {
  verify();
  if (command("git", ["status", "--porcelain", "--", root]).trim()) throw Error("MINIMAL_BUILD_REQUIRES_COMMITTED_SOURCE");
  const revision = command("git", ["rev-parse", "HEAD"]).trim(), alignment = require("../dependency-alignment.json");
  await require("./browser").build();
  const owner = "drumee-il4-build-" + revision, kernel = "drumee-minimal-kernel:" + revision, tools = "drumee-minimal-tools:" + alignment.infrastructure.revision;
  const labels = (source, rev) => ["--label", "org.drumee.infra.owner=drumee-build-" + source + "-" + rev, "--label", "org.opencontainers.image.source=https://github.com/drumee/" + source, "--label", "org.opencontainers.image.revision=" + rev];
  command("docker", ["build", ...labels("debian", revision), "--label", "org.drumee.distribution.alignment=" + alignment.content_sha256, "-t", kernel, root], { stdio: "inherit" });
  const infra = path.dirname(require.resolve("@drumee/infra-layer/package.json"));
  command("docker", ["build", ...labels("infra-layer", alignment.infrastructure.revision), "-f", path.join(infra, "capabilities/docker/Dockerfile.services"), "-t", tools, infra], { stdio: "inherit" });
  const image = ref => command("docker", ["image", "inspect", ref, "--format", "{{.Id}}"] ).trim();
  for (const ref of Object.values(require("../lib/distribution").images)) command("docker", ["pull", ref]);
  const result = { revision, alignment_sha256: alignment.content_sha256, kernel: image(kernel), tools: image(tools), tags: { kernel, tools }, owner };
  fs.mkdirSync(path.join(root, ".cache"), { recursive: true });
  fs.writeFileSync(path.join(root, ".cache/images.json"), JSON.stringify(result, null, 2) + "\n");
  console.log(JSON.stringify(result));
}
build().catch(error => { console.error(error.code || error.message); process.exitCode = 1; });
