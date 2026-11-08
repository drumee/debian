"use strict";
// Mixed-service regression against the installed, verified registry dependency.
// Faults use owned resources; guard probes copy real observations, never mock Docker.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const profile = path.resolve(__dirname, "../../profiles/minimal-application");
const D = require(path.join(profile, "node_modules/@drumee/infra-layer/lifecycle/docker"));
const A = require(path.join(profile, "node_modules/@drumee/infra-layer/lifecycle/activation"));
const { authorizeRollback } = require(path.join(profile, "node_modules/@drumee/infra-layer/internal/rollback-authorization"));
const S = require(path.join(profile, "node_modules/@drumee/infra-layer/lib/spec"));
module.exports = async function recovery({ mail, file, cli, write, request, assert, command, own, queueIds, fingerprints, lifecycle }) {
  const root = mail.storage.root, project = mail.deployment.project, port = mail.manifest.external_gateway.host_port;
  const initial = cli("status", file).active_revision;
  assert.equal((await request(port, "qualification.write")).body.data.count, 1);
  const stateFile = root + "/durable/application-state/preserved";
  const digest = () => crypto.createHash("sha256").update(fs.readFileSync(stateFile)).digest("hex");
  const beforeData = digest(), beforeQueue = queueIds(own(mail).find(x => x.Config.Labels["com.docker.compose.service"] === "mail"));
  assert.ok(beforeQueue.length > 0);
  const changed = structuredClone(mail); changed.manifest.application.environment.APP_BANNER = "mixed-rollback";
  assert.equal(cli("install", write(changed, "smtp-changed"), ["--execute"]).ready, true);
  assert.equal((await request(port, "qualification.ping")).body.data.banner, "mixed-rollback");
  assert.equal(cli("rollback", file, ["--execute", "--revision", initial]).ready, true);
  assert.equal((await request(port, "qualification.ping")).body.data.banner, "first");

  const prepared = JSON.parse(fs.readFileSync(root + "/candidates/" + initial + "/prepared.json"));
  let orderChanged = false, mountRecordsEqual = false;
  const first = D.inspectProject(project, ["application", "mail", "dkim"]).find(x => x.service === "mail").mounts;
  const multiset = values => values.map(x => S.serialize(x)).sort().join("\n");
  for (let i = 0; i < 64; i++) {
    const current = D.inspectProject(project, ["application", "mail", "dkim"]).find(x => x.service === "mail").mounts;
    assert.equal(multiset(current), multiset(first));
    if (S.serialize(current) !== S.serialize(first)) {
      orderChanged = true; mountRecordsEqual = true;
      // Feed the earlier actual Docker ordering as the admission snapshot;
      // authorizeRecoveryNetworks performs a fresh real container inspection.
      const observations = D.inspectProject(project, ["application", "mail", "dkim"]);
      observations.find(x => x.service === "mail").mounts = first;
      D.authorizeRecoveryNetworks(prepared.composition, observations);
      break;
    }
  }
  assert.equal(orderChanged, true, "real Docker mount-order variation is required, never simulated");

  const broken = structuredClone(mail); broken.manifest.application.plugins[0].revision = "e".repeat(40);
  assert.equal(cli("install", write(broken, "smtp-broken"), ["--execute"], false).code, "DOCKER_LIFECYCLE_COMMAND_FAILED");
  assert.equal(cli("status", file).ready, false);
  const events = fs.readdirSync(root + "/journal").filter(x => /^\d{8}\.json$/.test(x)).sort().map(x => JSON.parse(fs.readFileSync(root + "/journal/" + x)));
  const pending = events.filter(x => x.phase === "recovery-required").at(-1);
  assert.equal(pending.details.service, "application");
  const prior = A.readActive(root), context = { root, authorized: true, imports: mail.imports || [] };
  const observations = D.inspectProject(project, ["application", "mail", "dkim"]);
  for (const service of ["mail", "dkim"]) {
    assert.equal(observations.find(x => x.service === service).role, "");
    assert.equal(prepared.compose.services[service].labels["org.drumee.infra.role"], undefined);
  }
  const authorize = (values, ctx = context) => authorizeRollback(prepared, values, prior, pending, ctx, D, A.checkObserved);
  const refusal = (mutate, code) => { const values = structuredClone(observations); mutate(values); assert.throws(() => authorize(values), { code }); };
  for (const role of ["unexpected", "", undefined, null]) refusal(x => x.find(v => v.service === "application").role = role, "RUNTIME_IDENTITY_MISMATCH");
  for (const role of ["unexpected", null, false, 0]) refusal(x => x.find(v => v.service === "mail").role = role, "RUNTIME_IDENTITY_MISMATCH");
  assert.throws(() => authorize(observations, { ...context, authorized: false }), { code: "ROLLBACK_OPERATION_NOT_AUTHORIZED" });
  for (const key of ["owner", "project", "name", "image", "image_id", "revision", "service"]) refusal(x => x.find(v => v.service === "application")[key] = "foreign", "RUNTIME_IDENTITY_MISMATCH");
  refusal(x => x.find(v => v.service === "application").configured_ports["3101/tcp"][0].HostIp = "0.0.0.0", "UNEXPECTED_SERVICE_EXPOSURE");
  refusal(x => x.find(v => v.service === "mail").mounts[0].Source = "/foreign", "RUNTIME_MOUNT_MISMATCH");
  refusal(x => x.find(v => v.service === "mail").mounts.push({ Source: "/unexpected", Destination: "/extra", RW: true }), "RUNTIME_IDENTITY_MISMATCH");
  refusal(x => x.find(v => v.service === "mail").mounts.push({ ...x.find(v => v.service === "mail").mounts[0] }), "RUNTIME_IDENTITY_MISMATCH");
  assert.equal(cli("rollback", file, ["--revision", initial], false).code, "APPLICATION_EXECUTION_AUTHORIZATION_REQUIRED");

  const extra = project + "-recovery-negative", app = observations.find(x => x.service === "application"), ids = own(mail).map(x => x.Id).sort();
  command("docker", ["network", "create", "--label", "org.drumee.qualification=" + project, extra]);
  try {
    command("docker", ["network", "connect", extra, app.id]);
    assert.equal(cli("rollback", file, ["--execute", "--revision", initial], false).code, "NETWORK_ATTACHMENT_MISMATCH");
    assert.deepEqual(own(mail).map(x => x.Id).sort(), ids);
  } finally {
    command("docker", ["network", "disconnect", extra, app.id]);
    const n = JSON.parse(command("docker", ["network", "inspect", extra]))[0];
    assert.equal(n.Labels["org.drumee.qualification"], project); assert.equal(Object.keys(n.Containers).length, 0);
    command("docker", ["network", "rm", extra]);
  }
  const recovered = cli("rollback", file, ["--execute", "--revision", initial]);
  assert.equal(recovered.ready, true); assert.equal(recovered.active_revision, initial);
  assert.equal((await request(port, "qualification.ping")).body.data.banner, "first");
  assert.equal(digest(), beforeData);
  assert.deepEqual(queueIds(own(mail).find(x => x.Config.Labels["com.docker.compose.service"] === "mail")), beforeQueue);
  assert.deepEqual((await lifecycle.prepareDeployment(require(path.join(profile, "lib/config")).compose(mail), context)).fingerprints, fingerprints);
  assert.equal((await request(port, "qualification.smtp_probe")).body.data.starttls_authenticated, true);
  return { actual_adapter: true, ordinary_rollback: true, failed_start: true, recovery_required: true, authorized_rollback: true, ready_rpc_smtp_after_recovery: true, data_queue_secrets_preserved: true, absent_roles_observed: true, real_mount_order_variation: orderChanged, complete_mount_records_equal: mountRecordsEqual, copied_observation_guard_probes: true, real_extra_network_refused_without_recreation: true, external_smtp: false };
};
