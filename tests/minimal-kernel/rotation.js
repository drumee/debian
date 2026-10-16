"use strict";
// Crash/recovery test restricted to this disposable distribution's resources.
const assert = require("node:assert/strict"), fs = require("node:fs"), path = require("node:path");
const { spawnSync } = require("node:child_process");
const fixture_root = path.resolve(__dirname, "../../profiles/minimal-kernel");
const load = name => require(require.resolve(name, { paths: [fixture_root] }));
const lifecycle = load("@drumee/infra-layer/lifecycle"), A = load("@drumee/infra-layer/lifecycle/activation"), T = load("@drumee/infra-layer/lifecycle/transitions");
const driver = require(path.join(fixture_root, "lib/driver")).createDriver();
async function child(root, fingerprint) {
  const source = A.readActive(root).prepared;
  const interrupted = { ...driver, compose(prepared, args, options) {
    const result = driver.compose(prepared, args, options);
    if (args[0] === "up" && args.at(-1) === "redis") process.kill(process.pid, "SIGKILL");
    return result;
  } };
  await lifecycle.rotateSecret(root, { authorized: true, ref: source.composition.plan.inputs.spec.redis.auth_secret_ref, expected_fingerprint: fingerprint, consumer_transition: "il3-owned-kernel-redis" }, { root, authorized: true, create_resources: true, driver: interrupted });
  throw Error("INTERRUPTION_NOT_REACHED");
}
async function verifyRotation(prepared, context) {
  const ref = prepared.composition.plan.inputs.spec.redis.auth_secret_ref;
  const fingerprint = prepared.fingerprints.find(value => JSON.stringify(value.ref) === JSON.stringify(ref)).fingerprint;
  const interrupted = spawnSync(process.execPath, [__filename, "child", prepared.root, fingerprint], { encoding: "utf8", timeout: 300000, maxBuffer: 65536 });
  assert.equal(interrupted.signal, "SIGKILL", "Owned rotation process must reach the actual interruption boundary");
  assert.equal((await lifecycle.inspectDeployment(prepared.root, context)).ready, false);
  const pending = T.pending(prepared.root); assert.ok(pending && pending.candidate_revision);
  assert.equal(pending.previous_fingerprint, fingerprint);
  // Explicit operator recovery only after the exact child has been reaped.
  // Product locks are never automatically stolen by PID/timeout heuristics.
  const lock = path.join(prepared.root, ".infra-lifecycle-lock"), stat = fs.lstatSync(lock);
  assert.ok(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === process.getuid() && !(stat.mode & 0o077));
  assert.equal(fs.readdirSync(lock).length, 0); fs.rmdirSync(lock);
  const result = await lifecycle.resumeSecretRotation(prepared.root, pending.id, context);
  assert.equal(result.status, "committed"); assert.notEqual(result.active_fingerprint, fingerprint);
  assert.deepEqual([...result.consumers].sort(), ["kernel", "redis"]);
  assert.deepEqual([...result.transitioned].sort(), ["kernel", "redis"]);
  assert.equal(T.pending(prepared.root), null);
  assert.ok(fs.readdirSync(path.join(prepared.root, "secrets", ref.resource, ref.key)).filter(name => name.endsWith(".secret")).length >= 2);
  assert.equal((await lifecycle.inspectDeployment(prepared.root, context)).ready, true);
  console.log("REAL_KERNEL_REDIS_INTERRUPTION_RECOVERY_VERIFIED");
  return A.readActive(prepared.root).prepared;
}
if (require.main === module) child(process.argv[3], process.argv[4]).catch(() => { console.error("OWNED_ROTATION_CHILD_FAILED"); process.exitCode = 1; });
module.exports = { verifyRotation };
