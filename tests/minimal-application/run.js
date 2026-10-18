"use strict";
// Real operator acceptance. Docker is used only for observation, fault injection
// and cleanup of resources whose canonical ownership was checked first.
const fs = require("node:fs"), path = require("node:path"), os = require("node:os"), crypto = require("node:crypto");
const strict = require("node:assert/strict"), { execFileSync, spawn } = require("node:child_process");
const { freePort, request, externalNetwork } = require("./network");
const repository = path.resolve(__dirname, "../.."), profile = path.join(repository, "profiles/minimal-application");
const L = require(path.join(profile, "node_modules/@drumee/infra-layer/lifecycle"));
const { compose } = require(path.join(profile, "lib/config")), configuration = require(path.join(profile, "test/configuration"));
let assertions = 0;
const assert = new Proxy(strict, { get(target, key) { const value = target[key]; return typeof value === "function" ? (...args) => { assertions++; return value(...args); } : value; } });
const command = (file, args, options = {}) => execFileSync(file, args, { encoding: "utf8", stdio: "pipe", timeout: 300000, ...options });
async function main() {
  if (!process.env.IL5_NETWORK_CLIENT || !process.env.IL5_LAN_ADDRESS || !process.env.IL5_HOST_NGINX) throw Error("EXPLICIT_NETWORK_AND_HOST_PROXY_REQUIRED");
  const receipt = JSON.parse(fs.readFileSync(process.env.IL5_IMAGES || path.join(profile, ".cache/images.json")));
  const project = "drumee-il5-debian-" + crypto.randomBytes(4).toString("hex"), base = fs.mkdtempSync(path.join(os.tmpdir(), project + "-"));
  const port = await freePort(), root = path.join(base, "deployment"), cfg = configuration(root, project, receipt.image, port);
  cfg.deployment.acceptance = true; cfg.manifest.provenance.revision = receipt.revision; cfg.manifest.application.plugins = receipt.plugins;
  cfg.manifest.persistent_resources.push({ id: "application-state", source: root + "/durable/application-state", uid: process.getuid(), gid: process.getgid(), backup_required: true });
  cfg.manifest.application.mounts.push({ resource: "application-state", target: "/app/state", read_only: false });
  const configs = [], report = { project, source_revision: receipt.revision, infrastructure: receipt.infrastructure, image: receipt.image, runtime: receipt.runtime, groups: [], internet_delivery: "not-tested" };
  let proxy;
  const step = async (name, fn) => { await fn(); report.groups.push(name); console.log("IL5_DISTRIBUTION_OK " + name); };
  function write(value, name = "config") { const file = path.join(base, name + ".json"); fs.writeFileSync(file, JSON.stringify(value), { mode: 0o600 }); return file; }
  const file = write(cfg);
  function cli(operation, config = file, extra = [], ok = true) {
    let result;
    try { result = JSON.parse(command(path.join(repository, "bin/drumee-ctl"), ["--profile", "minimal-application", operation, "--config", config, ...extra])); }
    catch (error) { if (ok) throw Object.assign(Error("OPERATOR_" + operation.toUpperCase() + "_FAILED"), { diagnostic: String(error.stderr || "").slice(0, 1000) }); result = JSON.parse(String(error.stderr)); }
    if (!ok) assert.ok(result.code && result.code !== "APPLICATION_CONFIGURATION_VALID"); return result;
  }
  function observed(value) { const ids = command("docker", ["ps", "-aq", "--filter", "label=com.docker.compose.project=" + value.deployment.project]).trim().split("\n").filter(Boolean); return ids.length ? JSON.parse(command("docker", ["inspect", ...ids])) : []; }
  function own(value) { const owner = JSON.parse(fs.readFileSync(path.join(value.storage.root, "deployment-owner.json"))); assert.equal(owner.project, value.deployment.project); assert.equal(owner.uid, process.getuid()); const objects = observed(value); for (const object of objects) { assert.equal(object.Config.Labels["org.drumee.infra.owner"], value.deployment.project); } return objects; }
  function clean(value) {
    if (!fs.existsSync(path.join(value.storage.root, "deployment-owner.json"))) return;
    const objects = own(value); for (const object of objects) command("docker", ["rm", "-f", object.Id]);
    const composition = compose(value);
    for (const network of Object.values(composition.compose.networks)) {
      const matches = command("docker", ["network", "ls", "--filter", "name=^" + network.name + "$", "-q"]).trim();
      if (matches) { const inspected = JSON.parse(command("docker", ["network", "inspect", matches]))[0]; assert.equal(inspected.Labels["org.drumee.infra.owner"], value.deployment.project); assert.equal(Object.keys(inspected.Containers).length, 0); command("docker", ["network", "rm", inspected.Id]); }
    }
  }
  try {
    await step("selector-public-plan-and-operator-authorization", async () => { assert.equal(cli("validate").valid, true); assert.deepEqual(Object.keys(cli("plan").compose.services), ["application"]); assert.equal(cli("install", file, [], false).code, "APPLICATION_EXECUTION_AUTHORIZATION_REQUIRED"); });
    configs.push(cfg);
    let initial;
    await step("install-real-runtime-native-rpc-and-authorization", async () => { const prepared = await L.prepareDeployment(compose(cfg), { root, authorized: true, create_resources: true }); assert.equal(prepared.activated, false); assert.equal(observed(cfg).length, 0); const state = cli("install", file, ["--execute"]); assert.equal(state.ready, true); initial = state.active_revision; assert.equal((await request(port, "health.ready")).body.status, "ok"); assert.equal((await request(port, "qualification.ping")).body.data.message, "native-distribution-rpc"); assert.equal((await request(port, "qualification.denied")).status, 403); assert.equal((await request(port, "qualification.write")).body.data.count, 1); assert.equal(cli("doctor").ready, true); });
    await step("docker-host-and-separate-lan-network-observations", async () => { const objects = own(cfg); assert.equal(objects.length, 1); assert.deepEqual(objects[0].NetworkSettings.Ports["3101/tcp"], [{ HostIp: "127.0.0.1", HostPort: String(port) }]); const sockets = command("ss", ["-H", "-ltn", "sport = :" + port]); assert.equal(sockets.includes("0.0.0.0:" + port) || sockets.includes("[::]:" + port), false); report.network = await externalNetwork(port, process.env.IL5_LAN_ADDRESS, process.env.IL5_NETWORK_CLIENT); report.socket_observation = sockets.trim(); });
    await step("operator-proxy-fragment-with-real-host-nginx-and-verified-tls", async () => {
      const proxy_port = await freePort(), certificate = path.join(base, "proxy.pem"), key = path.join(base, "proxy.key");
      command("openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2", "-subj", "/CN=application.test", "-addext", "subjectAltName=DNS:application.test", "-keyout", key, "-out", certificate]); fs.chmodSync(key, 0o600);
      const fragment = cli("proxy-config"); assert.equal(fragment.applied, false); assert.ok(fragment.content.includes("proxy_pass http://127.0.0.1:" + port + ";"));
      const nginx_file = path.join(base, "nginx.conf"); fs.writeFileSync(nginx_file, `worker_processes 1; pid ${base}/nginx.pid; error_log ${base}/nginx-error.log warn; events { worker_connections 128; } http { access_log off; client_body_temp_path ${base}/client-temp; proxy_temp_path ${base}/proxy-temp; fastcgi_temp_path ${base}/fastcgi-temp; uwsgi_temp_path ${base}/uwsgi-temp; scgi_temp_path ${base}/scgi-temp; server { listen 127.0.0.1:${proxy_port} ssl; server_name application.test; ssl_certificate ${certificate}; ssl_certificate_key ${key}; ${fragment.content} location / { return 404; } } }`);
      command(process.env.IL5_HOST_NGINX, ["-p", base, "-c", nginx_file, "-t"]); proxy = spawn(process.env.IL5_HOST_NGINX, ["-p", base, "-c", nginx_file, "-g", "daemon off;"], { stdio: "ignore" });
      let result; for (let i = 0; i < 100; i++) { try { result = await request(proxy_port, "qualification.ping", {}, fs.readFileSync(certificate)); break; } catch (_) { await new Promise(resolve => setTimeout(resolve, 50)); } }
      assert.equal(result.status, 200); assert.equal(result.body.data.message, "native-distribution-rpc"); assert.equal((await request(proxy_port, "qualification.denied", {}, fs.readFileSync(certificate))).status, 403); report.host_proxy = { containerized: false, ca_san_verified: true, operator_fragment: true };
    });
    await step("restart-stop-start-and-idempotent-install-preserve-data", async () => { assert.equal(cli("restart", file, ["--execute"]).ready, true); assert.equal((await request(port, "qualification.write")).body.data.count, 2); assert.equal(cli("stop", file, ["--execute"]).data_preserved, true); assert.equal(cli("status").ready, false); assert.equal(cli("start", file, ["--execute"]).ready, true); assert.equal(cli("install", file, ["--execute"]).active_revision, initial); assert.equal(fs.readFileSync(root + "/durable/application-state/preserved", "utf8"), "2"); });
    await step("real-operator-interruption-and-explicit-recovery", async () => {
      assert.equal(cli("stop", file, ["--execute"]).data_preserved, true);
      const journal = path.join(root, "journal"), before = fs.readdirSync(journal).length;
      const child = spawn(path.join(repository, "bin/drumee-ctl"), ["--profile", "minimal-application", "start", "--config", file, "--execute"], { detached: true, stdio: "ignore" });
      const exited = new Promise((resolve, reject) => { child.once("error", reject); child.once("exit", (code, signal) => resolve({ code, signal })); });
      let interrupted = false;
      try {
        const deadline = Date.now() + 30000;
        while (Date.now() < deadline && child.exitCode === null && child.signalCode === null) {
          const entries = fs.readdirSync(journal).filter(name => /^\d{8}\.json$/.test(name)).sort().slice(before).map(name => JSON.parse(fs.readFileSync(path.join(journal, name))));
          if (entries.some(entry => entry.phase === "activation-intent")) { process.kill(-child.pid, "SIGKILL"); interrupted = true; break; }
          await new Promise(resolve => setTimeout(resolve, 5));
        }
        assert.equal(interrupted, true); assert.equal((await exited).signal, "SIGKILL");
      } finally { if (child.exitCode === null && child.signalCode === null) { process.kill(-child.pid, "SIGKILL"); await exited; } }
      assert.equal(cli("status").ready, false);
      // Only this known-dead acceptance process's empty exclusive lock is removed.
      const lock = path.join(root, ".infra-lifecycle-lock"), stat = fs.lstatSync(lock);
      assert.equal(stat.uid, process.getuid()); assert.equal(stat.isDirectory() && !stat.isSymbolicLink(), true); assert.deepEqual(fs.readdirSync(lock), []); fs.rmdirSync(lock);
      assert.equal(cli("start", file, ["--execute"], false).code, "ACTIVATION_RECOVERY_REQUIRED");
      assert.equal(cli("start", file, ["--execute", "--recover"]).ready, true);
      assert.equal(fs.readFileSync(root + "/durable/application-state/preserved", "utf8"), "2");
      report.interruption = { real_sigkill: true, explicit_recovery_required: true, data_preserved: true };
    });
    await step("configuration-rollback-and-failed-plugin-startup-preserve-state", async () => {
      const changed = structuredClone(cfg); changed.manifest.application.environment = { APP_BANNER: "second" }; const next_file = write(changed, "next"); assert.equal(cli("install", next_file, ["--execute"]).ready, true); assert.equal((await request(port, "qualification.ping")).body.data.banner, "second"); assert.equal(cli("stop", file, ["--execute"], false).code, "APPLICATION_ACTIVE_CONFIGURATION_MISMATCH"); assert.equal(cli("rollback", file, ["--execute", "--revision", initial]).ready, true); assert.equal((await request(port, "qualification.ping")).body.data.banner, "first");
      const broken = structuredClone(cfg); broken.manifest.application.plugins[0].revision = "e".repeat(40); const broken_file = write(broken, "broken"); cli("install", broken_file, ["--execute"], false); assert.equal(cli("status").ready, false); assert.equal(fs.readFileSync(root + "/durable/application-state/preserved", "utf8"), "2"); assert.equal(cli("rollback", file, ["--execute", "--revision", initial]).ready, true);
    });
    await step("operator-backup-and-isolated-restore", async () => {
      fs.mkdirSync(cfg.storage.backup_location, { mode: 0o700 }); const backup = path.join(cfg.storage.backup_location, "snapshot"); assert.equal(cli("backup", file, ["--execute", "--backup", backup]).protected, true);
      const next = structuredClone(cfg); next.deployment.project += "-restored"; next.infrastructure.adapter_input.project = next.deployment.project; next.infrastructure.adapter_input.network = next.deployment.project + "-application"; next.storage.root = path.join(base, "restored"); next.storage.backup_location = next.storage.root + "-backups"; next.manifest.external_gateway.host_port = await freePort(); for (const resource of next.manifest.persistent_resources) resource.source = resource.source.replace(root, next.storage.root); configs.push(next);
      const restored_file = write(next, "restored"); const result = cli("restore", restored_file, ["--execute", "--backup", backup]); assert.equal(result.ready, true); assert.equal(result.restored, true); assert.equal(result.kernel_recovery_verified, false); assert.equal((await request(next.manifest.external_gateway.host_port, "qualification.write")).body.data.count, 3); assert.equal(fs.readFileSync(root + "/durable/application-state/preserved", "utf8"), "2");
    });
    await step("unknown-existing-installation-and-owner-mismatch-refused", async () => { const unknown = structuredClone(cfg); unknown.storage.root = path.join(base, "unknown"); unknown.storage.backup_location = unknown.storage.root + "-backups"; for (const resource of unknown.manifest.persistent_resources) resource.source = resource.source.replace(root, unknown.storage.root); fs.mkdirSync(unknown.storage.root, { mode: 0o700 }); fs.writeFileSync(unknown.storage.root + "/keep", "outside"); assert.equal(cli("install", write(unknown, "unknown"), ["--execute"], false).code, "UNOWNED_DEPLOYMENT_DIRECTORY"); assert.equal(fs.readFileSync(unknown.storage.root + "/keep", "utf8"), "outside"); const wrong = structuredClone(cfg); wrong.deployment.owner_uid += 1; wrong.manifest.persistent_resources[0].uid += 1; assert.equal(cli("install", write(wrong, "owner"), ["--execute"], false).code, "APPLICATION_OWNER_MISMATCH"); assert.equal(cli("status").ready, true); });
    await step("optional-canonical-smtp-dkim-isolation-and-failure-preservation", async () => {
      if (!receipt.tools) throw Error("EXPLICIT_SMTP_TOOLS_IMAGE_REQUIRED");
      const mail = structuredClone(cfg), mail_root = path.join(base, "smtp"); mail.deployment.id += "-smtp"; mail.deployment.project += "-smtp"; mail.infrastructure.spec.instance.id = mail.deployment.id; mail.infrastructure.adapter_input.project = mail.deployment.project; mail.infrastructure.adapter_input.network = mail.deployment.project + "-application"; mail.storage.root = mail_root; mail.storage.backup_location = mail_root + "-backups"; mail.manifest.external_gateway.host_port = await freePort(); for (const resource of mail.manifest.persistent_resources) resource.source = resource.source.replace(root, mail_root);
      const imported = path.join(base, "submission-import"); fs.writeFileSync(imported, crypto.randomBytes(32).toString("base64url"), { mode: 0o600 }); require("./smtp")(mail, receipt.tools.image, imported); configs.push(mail);
      const mail_file = write(mail, "smtp"), mail_port = mail.manifest.external_gateway.host_port; assert.equal(cli("install", mail_file, ["--execute"]).ready, true);
      const objects = own(mail), relay = objects.find(x => x.Config.Labels["com.docker.compose.service"] === "mail"), backend = objects.find(x => x.Config.Labels["com.docker.compose.service"] === "application");
      for (const object of objects.filter(x => x !== backend)) assert.deepEqual(object.HostConfig.PortBindings || {}, {});
      const dkim = objects.find(x => x.Config.Labels["com.docker.compose.service"] === "dkim"), dkimNetworks = Object.keys(dkim.NetworkSettings.Networks);
      assert.equal(dkimNetworks.length, 1); assert.equal(JSON.parse(command("docker", ["network", "inspect", dkimNetworks[0]]))[0].Internal, true);
      assert.equal(Object.hasOwn(backend.NetworkSettings.Networks, dkimNetworks[0]), false);
      assert.deepEqual(backend.Mounts.filter(x => x.Destination.startsWith("/run/secrets/")).map(x => x.Destination).sort(), ["/run/secrets/mail-ca", "/run/secrets/submission"]);
      assert.equal((await request(mail_port, "qualification.smtp_probe")).body.data.starttls_authenticated, true); assert.equal((await request(mail_port, "qualification.smtp_probe", { bad_auth: true })).body.code, "EAUTH"); assert.equal((await request(mail_port, "qualification.smtp_probe", { bad_tls: true })).body.code, "ESOCKET"); assert.equal((await request(mail_port, "qualification.smtp_probe", { unauthenticated: true })).body.code, "EENVELOPE");
      assert.equal((await request(mail_port, "qualification.smtp_probe", { queue_message: true })).body.data.queued, true);
      const queueIds = object => command("docker", ["exec", object.Id, "postqueue", "-j"]).trim().split("\n").filter(Boolean).map(line => JSON.parse(line).queue_id).sort();
      const queued = queueIds(relay); assert.ok(queued.length > 0);
      const fingerprints = (await L.prepareDeployment(compose(mail), { root: mail_root, authorized: true, imports: mail.imports })).fingerprints;
      command("docker", ["stop", relay.Id]); assert.equal(cli("status", mail_file).ready, true); assert.equal((await request(mail_port, "qualification.ping")).status, 200);
      command("docker", ["kill", backend.Id]); assert.equal(cli("status", mail_file).ready, false); assert.ok(fs.existsSync(mail_root + "/durable/mail/.infra-owner")); assert.equal(cli("start", mail_file, ["--execute"]).ready, true);
      const resumedRelay = own(mail).find(x => x.Config.Labels["com.docker.compose.service"] === "mail");
      assert.deepEqual(queueIds(resumedRelay), queued);
      assert.deepEqual((await L.prepareDeployment(compose(mail), { root: mail_root, authorized: true, imports: mail.imports })).fingerprints, fingerprints);
      mail.infrastructure.requirements.capabilities = ["smtp"]; mail.manifest.application.requires = ["mail"];
      const requiredFile = write(mail, "required-smtp"); assert.equal(cli("install", requiredFile, ["--execute"]).ready, true);
      command("docker", ["stop", own(mail).find(x => x.Config.Labels["com.docker.compose.service"] === "mail").Id]);
      assert.equal(cli("status", requiredFile).ready, false); assert.equal((await request(mail_port, "qualification.ping")).status, 200);
      assert.equal(cli("start", requiredFile, ["--execute"]).ready, true);
      fs.mkdirSync(mail.storage.backup_location, { mode: 0o700 }); assert.equal(cli("backup", requiredFile, ["--execute", "--backup", mail.storage.backup_location + "/refused"], false).code, "SMTP_RECOVERY_UNQUALIFIED"); assert.equal(cli("status", requiredFile).ready, true);
      report.smtp = { starttls_auth: true, invalid_tls_name_refused: true, private_dkim_observed: true, no_open_relay: true, optional_failure_isolated: true, backend_failure_preserves_queued_message: true, secrets_preserved: true, required_failure_diagnosed: true, smtp_recovery: "explicitly-unsupported", internet_delivery: false };
    });
    report.status = "passed";
  } catch (error) { report.status = "failed"; report.failure = { code: error.code || error.message, diagnostic: error.diagnostic }; console.error(JSON.stringify(report.failure)); throw error; }
  finally {
    if (proxy) { proxy.kill("SIGTERM"); if (proxy.exitCode === null && proxy.signalCode === null) await new Promise(resolve => proxy.once("exit", resolve)); }
    for (const value of configs.reverse()) clean(value);
    // Backups may contain root-owned native resources. This exclusive base is
    // guarded by its random name and owner before using the pinned helper.
    assert.equal(fs.lstatSync(base).uid, process.getuid()); assert.ok(path.basename(base).startsWith(project + "-"));
    command("docker", ["run", "--rm", "--network", "none", "--user", "0:0", "--mount", "type=bind,source=" + base + ",target=/work", cfg.manifest.helper_image, "node", "-e", "const fs=require('node:fs');for(const name of fs.readdirSync('/work'))fs.rmSync('/work/'+name,{recursive:true,force:true});"]);
    fs.rmdirSync(base); report.assertions = assertions; const report_file = path.join(os.tmpdir(), project + "-report.json"); fs.writeFileSync(report_file, JSON.stringify(report, null, 2), { mode: 0o600 }); console.log("IL5_DISTRIBUTION_REPORT " + report_file);
  }
}
main().catch(() => { process.exitCode = 1; });
