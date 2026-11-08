"use strict";
// Consumer qualification: only the installed, byte-verified registry dependency.
// A test-only TLS provider is separate from the protected application networks.
const fs = require("node:fs"), path = require("node:path"), os = require("node:os"), crypto = require("node:crypto"), http = require("node:http"), strict = require("node:assert/strict");
const { execFileSync, spawnSync } = require("node:child_process"), { freePort, request } = require("./network");
const repository = path.resolve(__dirname, "../.."), profile = path.join(repository, "profiles/minimal-application"), installed = path.join(profile, "node_modules/@drumee/infra-layer");
const source = require(path.join(profile, "scripts/infrastructure-source")).verify(), L = require(installed + "/lifecycle"), { compose } = require(path.join(profile, "lib/config")), configuration = require(path.join(profile, "test/configuration"));
const command = (program, args, options = {}) => execFileSync(program, args, { encoding: "utf8", stdio: "pipe", timeout: 300000, ...options });
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
function status(port, release = false) { return new Promise((resolve, reject) => { const req = http.request({ hostname: "127.0.0.1", port, path: release ? "/allow" : "/", method: release ? "POST" : "GET", agent: false }, res => { let body = ""; res.on("data", b => body += b); res.on("end", () => { try { resolve(JSON.parse(body)); } catch { reject(Error("SYNTHETIC_STATUS_INVALID")); } }); }); req.on("error", reject); req.setTimeout(3000, () => req.destroy()); req.end(); }); }
async function main() {
  const input = JSON.parse(fs.readFileSync(process.argv[2])), images = JSON.parse(fs.readFileSync(input.images));
  strict.ok(path.isAbsolute(input.output)); strict.deepEqual(images.infrastructure, source); strict.equal(source.version, "0.1.0-alpha.6");
  strict.equal(fs.realpathSync(require.resolve(installed)), installed + "/lib/index.js"); strict.ok(images.tools);
  const suffix = crypto.randomBytes(5).toString("hex"), base = fs.mkdtempSync(path.join(os.tmpdir(), "debian-relay-auth-")), fixture = path.join(__dirname, "fixtures/relay"), build = base + "/build"; fs.mkdirSync(build);
  for (const file of ["package.json", "package-lock.json", "server.js"]) fs.copyFileSync(fixture + "/" + file, build + "/" + file);
  fs.writeFileSync(build + "/Dockerfile", 'FROM node:22-bookworm-slim@sha256:c3de60bf2f9dd0ac6370e6117950ff62d6e339527e7472301c9c78a017978392\nWORKDIR /fixture\nCOPY package.json package-lock.json ./\nRUN npm ci --ignore-scripts --no-audit --no-fund\nCOPY server.js ./\nUSER 1000:1000\nENTRYPOINT ["node", "/fixture/server.js"]\n');
  const tag = "debian-synthetic-relay:" + suffix; command("docker", ["build", "--label", "org.drumee.qualification=" + suffix, "-t", tag, build]);
  const providerImage = command("docker", ["image", "inspect", tag, "--format", "{{.Id}}"] ).trim();
  const report = { source_revision: images.revision, qualification_revision: command("git", ["rev-parse", "HEAD"]).trim(), infrastructure: source, application_image: images.image, tools_image: images.tools.image, provider_image: providerImage, cases: [], assertions: 0, external_provider: false, real_owner_credentials: false, real_mailbox: false };
  const check = (value, expected) => { strict.deepEqual(value, expected); report.assertions++; };
  const cases = [
    { name: "simple", user: "synthetic-simple", password: "synthetic:formerly!restricted/+=@" },
    { name: "full-address-and-shell-literals", user: "synthetic@example.invalid", password: ' leading!#$%&*()[]{};:,?`"\\=+/@ $(touch /tmp/DEBIAN_SMTP_EXPANDED) END' },
    { name: "opaque-and-utf8", user: "opaque +/$ name-é", password: " leading\ttabs:spaces-café-🔒" },
    { name: "wrong-authentication", user: "synthetic@example.invalid", password: "synthetic!bad-password", mode: "wrong-password" },
    { name: "untrusted-ca", user: "synthetic@example.invalid", password: "synthetic!ca", mode: "untrusted-ca" },
    { name: "wrong-hostname", user: "synthetic@example.invalid", password: "synthetic!name", mode: "wrong-hostname" },
    { name: "no-starttls", user: "synthetic@example.invalid", password: "synthetic!tls", mode: "no-starttls" }
  ];
  try {
    for (let index = 0; index < cases.length; index++) {
      const c = cases[index], project = "debian-auth-" + suffix + "-" + index, network = project + "-upstream", owned = base + "/case-" + index, keys = owned + "/keys"; fs.mkdirSync(owned); fs.mkdirSync(keys);
      let provider, networkCreated = false, cfg;
      report.current_case = c.name; report.phase = "fixture-setup";
      try {
        command("docker", ["network", "create", "--label", "org.drumee.qualification=" + project, network]); networkCreated = true;
        const gateway = JSON.parse(command("docker", ["network", "inspect", network]))[0].IPAM.Config[0].Gateway, smtpPort = await freePort(), control = await freePort();
        const openssl = args => command("openssl", args, { stdio: "ignore" });
        for (const name of ["relay", "provider"]) openssl(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=synthetic-" + name, "-addext", "basicConstraints=critical,CA:TRUE", "-keyout", keys + "/" + name + "-ca.key", "-out", keys + "/" + name + "-ca.pem"]);
        for (const name of ["relay", "provider"]) {
          const host = name === "relay" ? "drumee.lan" : c.mode === "wrong-hostname" ? "wrong.fixture.invalid" : gateway;
          openssl(["req", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=" + host, "-keyout", keys + "/" + name + ".key", "-out", keys + "/" + name + ".csr"]);
          fs.writeFileSync(keys + "/" + name + ".ext", "subjectAltName=DNS:" + host + (host === gateway ? ",IP:" + host : "") + "\nbasicConstraints=critical,CA:FALSE\n");
          openssl(["x509", "-req", "-in", keys + "/" + name + ".csr", "-CA", keys + "/" + name + "-ca.pem", "-CAkey", keys + "/" + name + "-ca.key", "-set_serial", "1", "-days", "1", "-extfile", keys + "/" + name + ".ext", "-out", keys + "/" + name + ".pem"]);
        }
        fs.writeFileSync(keys + "/trust.pem", Buffer.concat([fs.readFileSync(keys + "/relay-ca.pem"), ...(c.mode === "untrusted-ca" ? [] : [fs.readFileSync(keys + "/provider-ca.pem")])]));
        fs.writeFileSync(keys + "/input.json", JSON.stringify({ user: c.user, password: c.mode === "wrong-password" ? "different-synthetic-password" : c.password, mode: c.mode, defer: index === 0 }), { mode: 0o600 });
        provider = command("docker", ["run", "-d", "--name", project + "-provider", "--label", "org.drumee.qualification=" + project, "--network", network, "--read-only", "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true", "--pids-limit", "128", "--memory", "128m", "--user", process.getuid() + ":" + process.getgid(), "-p", gateway + ":" + smtpPort + ":2525", "-p", "127.0.0.1:" + control + ":8025", ...["provider.key", "provider.pem", "input.json"].flatMap(f => ["--mount", "type=bind,source=" + keys + "/" + f + ",target=/fixture/" + f + ",readonly"]), providerImage]).trim();
        for (let i = 0; ; i++) { try { await status(control); break; } catch (error) { if (i > 50) throw error; await delay(100); } }
        const submission = crypto.randomBytes(32).toString("base64url"), upstream = { resource: "mail-test", key: "upstream" };
        fs.writeFileSync(keys + "/submission", submission, { mode: 0o600 }); fs.writeFileSync(keys + "/upstream", c.password, { mode: 0o600 });
        function configurationFor(id, root, port) {
          const value = require("./smtp")(configuration(root, id, images.image, port), images.tools.image, keys + "/submission");
          value.deployment.acceptance = true; value.manifest.provenance.revision = images.revision; value.manifest.application.plugins = images.plugins;
          const spec = value.infrastructure.spec, adapter = value.infrastructure.adapter_input, tls = spec.tls;
          spec.tls = { provider: "provided", certificate_ref: tls.certificate_ref, private_key_ref: tls.private_key_ref, ca_bundle_ref: tls.ca_bundle_ref };
          spec.secrets.resources = spec.secrets.resources.filter(x => x.type !== "tls-ca-key"); spec.secrets.resources.push({ ref: upstream, type: "smtp-external-credential", consumers: ["mail"] });
          for (const [ref, file] of [[tls.private_key_ref, "relay.key"], [tls.certificate_ref, "relay.pem"], [tls.ca_bundle_ref, "trust.pem"]]) adapter.resource_sources.find(x => JSON.stringify(x.ref) === JSON.stringify(ref)).source = keys + "/" + file;
          adapter.resource_sources.push({ ref: upstream, source: root + "/durable/projections/upstream" });
          Object.assign(spec.mail, { mode: "relay", relay_tls: "required", relay_endpoint: { host: gateway, port: smtpPort, transport: "tcp" }, relay_user: c.user, relay_secret_ref: upstream });
          value.manifest.persistent_resources.push({ id: "application-state", source: root + "/durable/application-state", uid: process.getuid(), gid: process.getgid(), backup_required: true });
          value.manifest.application.mounts.push({ resource: "application-state", target: "/app/state", read_only: false });
          value.imports.push({ ref: tls.private_key_ref, file: keys + "/relay.key" }, { ref: upstream, file: keys + "/upstream" }); return value;
        }
        if (index === 0) {
          report.phase = "canonical-import-refusals";
          const invalid = [Buffer.alloc(0), Buffer.from("final\n"), Buffer.from("final\r\n"), Buffer.from("bad\0value"), Buffer.from("bad\rvalue"), Buffer.from("bad\nvalue"), Buffer.from("final "), Buffer.from("final\t"), Buffer.from([0xff]), Buffer.from("\uFEFFvalue"), Buffer.alloc(256, 65)];
          for (let i = 0; i < invalid.length; i++) {
            fs.writeFileSync(keys + "/upstream", invalid[i]); const value = configurationFor(project + "-refusal-" + i, owned + "/refusal-" + i, await freePort());
            await strict.rejects(L.prepareDeployment(compose(value), { root: value.storage.root, authorized: true, create_resources: true, imports: value.imports }), { code: "SMTP_RELAY_CREDENTIAL_INVALID" }); report.assertions++;
          }
          check((await status(control)).connections, 0); fs.writeFileSync(keys + "/upstream", c.password);
          report.refusals = { canonical_file_imports: invalid.length, before_connection: true, final_lf_and_crlf_refused_without_trimming: true };
        }
        cfg = configurationFor(project, owned + "/deployment", await freePort()); const file = owned + "/config.json"; fs.writeFileSync(file, JSON.stringify(cfg), { mode: 0o600 });
        report.phase = "canonical-profile-install";
        const result = JSON.parse(command(repository + "/bin/drumee-ctl", ["--profile", "minimal-application", "install", "--config", file, "--execute"])); check(result.ready, true);
        const ids = command("docker", ["ps", "-aq", "--filter", "label=com.docker.compose.project=" + project]).trim().split("\n").filter(Boolean), initialObjects = JSON.parse(command("docker", ["inspect", ...ids]));
        let objects = initialObjects, mail = objects.find(x => x.Config.Labels["com.docker.compose.service"] === "mail");
        for (const object of objects) { check(object.Config.Labels["org.drumee.infra.owner"], project); if (object !== objects.find(x => x.Config.Labels["com.docker.compose.service"] === "application")) check(object.HostConfig.PortBindings || {}, {}); }
        report.phase = "exact-map-and-private-permissions";
        check(command("docker", ["exec", mail.Id, "postmap", "-q", "[" + gateway + "]:" + smtpPort, "hash:/run/infra-mail/auth/sasl_passwd"], { encoding: null }).equals(Buffer.from(c.user + ":" + c.password + "\n")), true);
        check(command("docker", ["exec", mail.Id, "postmap", "-s", "hash:/run/infra-mail/auth/sasl_passwd"]).split("\n").filter(Boolean).length, 1);
        check(command("docker", ["exec", mail.Id, "stat", "-c", "%a", "/run/infra-mail/auth"]).trim(), "700"); check(command("docker", ["exec", mail.Id, "stat", "-c", "%a", "/run/infra-mail/auth/sasl_passwd.db"]).trim(), "600");
        check(command("docker", ["exec", mail.Id, "cat", "/run/secrets/mail-relay"], { encoding: null }).equals(Buffer.from(c.password)), true); check(command("docker", ["exec", mail.Id, "stat", "-c", "%a", "/run/secrets/mail-relay"]).trim(), "600");
        const queued = await request(cfg.manifest.external_gateway.host_port, "qualification.smtp_probe", { queue_message: true }); check(queued.status, 200); check(queued.body.data.queued, true);
        if (index === 0) {
          report.phase = "authenticated-mixed-failed-start-recovery";
          let before; for (let i = 0; i < 100; i++) { before = await status(control); if (before.deferrals > 0) break; await delay(100); }
          check(before.deferrals > 0, true); check(before.messages, 0); check(before.account_exact, true); check(before.password_exact, true); check(before.tls_only, true);
          const countedAssert = new Proxy(strict, { get(target, key) { const fn = target[key]; return typeof fn === "function" ? (...args) => { report.assertions++; return fn(...args); } : fn; } });
          function own(value) {
            const owner = JSON.parse(fs.readFileSync(value.storage.root + "/deployment-owner.json")); check(owner.project, value.deployment.project); check(owner.uid, process.getuid());
            const ids = command("docker", ["ps", "-aq", "--filter", "label=com.docker.compose.project=" + value.deployment.project]).trim().split("\n").filter(Boolean), values = JSON.parse(command("docker", ["inspect", ...ids]));
            for (const object of values) check(object.Config.Labels["org.drumee.infra.owner"], value.deployment.project); return values;
          }
          function write(value, name) { const destination = owned + "/" + name + ".json"; fs.writeFileSync(destination, JSON.stringify(value), { mode: 0o600 }); return destination; }
          function cli(operation, config = file, extra = [], ok = true) {
            try { const result = JSON.parse(command(repository + "/bin/drumee-ctl", ["--profile", "minimal-application", operation, "--config", config, ...extra])); if (!ok) throw Error("EXPECTED_REFUSAL_MISSING"); return result; }
            catch (error) { if (ok) throw Object.assign(Error("CANONICAL_OPERATION_FAILED"), { code: "CANONICAL_OPERATION_FAILED", operation }); return JSON.parse(String(error.stderr)); }
          }
          const queueIds = object => command("docker", ["exec", object.Id, "postqueue", "-j"]).trim().split("\n").filter(Boolean).map(line => JSON.parse(line).queue_id).sort();
          const fingerprints = (await L.prepareDeployment(compose(cfg), { root: cfg.storage.root, authorized: true, imports: cfg.imports })).fingerprints;
          report.mixed_recovery = await require("./recovery")({ mail: cfg, file, cli, write, request, assert: countedAssert, command, own, queueIds, fingerprints, lifecycle: L });
          objects = own(cfg); mail = objects.find(x => x.Config.Labels["com.docker.compose.service"] === "mail");
          check(command("docker", ["exec", mail.Id, "postmap", "-q", "[" + gateway + "]:" + smtpPort, "hash:/run/infra-mail/auth/sasl_passwd"], { encoding: null }).equals(Buffer.from(c.user + ":" + c.password + "\n")), true);
          await status(control, true); command("docker", ["exec", mail.Id, "postqueue", "-f"]);
        }
        report.phase = "upstream-sasl-and-sink";
        let proof; for (let i = 0; i < 150; i++) { proof = await status(control); if (c.mode ? (c.mode === "wrong-password" ? proof.authentications > 0 : proof.connections > 0) : proof.messages > 0) break; await delay(100); }
        if (!c.mode) { check(proof.messages, 1); check(proof.authentications > 0, true); check(proof.account_exact, true); check(proof.password_exact, true); check(proof.envelope_exact, true); check(proof.body_exact, true); }
        else { await delay(1000); proof = await status(control); check(proof.messages, 0); check(proof.connections > 0, true); if (c.mode === "wrong-password") check(proof.authentications > 0, true); else check(proof.authentications, 0); }
        check(proof.tls_only, true); check(command("docker", ["exec", mail.Id, "test", "!", "-e", "/tmp/DEBIAN_SMTP_EXPANDED"]), "");
        for (const object of objects) { const logs = spawnSync("docker", ["logs", object.Id], { encoding: "utf8" }); check(logs.status, 0); for (const secret of [c.user, c.password, submission]) check((logs.stdout + logs.stderr).includes(secret), false); check(/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(logs.stdout + logs.stderr), false); }
        check(JSON.stringify({ env: mail.Config.Env, cmd: mail.Config.Cmd, entrypoint: mail.Config.Entrypoint }).includes(c.password), false);
        report.cases.push({ name: c.name, passed: true, exact_map: true, entries: 1, private_modes: true, accepted_by_private_relay: true, authenticated: !c.mode, received_by_synthetic_sink: proof.messages === 1, no_plaintext_authentication: proof.tls_only });
        console.log("DEBIAN_RELAY_AUTH_OK " + c.name);
      } finally {
        if (cfg && fs.existsSync(cfg.storage.root + "/deployment-owner.json")) {
          const owner = JSON.parse(fs.readFileSync(cfg.storage.root + "/deployment-owner.json")); check(owner.project, project); check(owner.uid, process.getuid());
          const ids = command("docker", ["ps", "-aq", "--filter", "label=com.docker.compose.project=" + project]).trim().split("\n").filter(Boolean);
          for (const id of ids) { const x = JSON.parse(command("docker", ["inspect", id]))[0]; check(x.Config.Labels["org.drumee.infra.owner"], project); command("docker", ["rm", "-f", id]); }
          for (const net of Object.values(compose(cfg).compose.networks)) { const found = command("docker", ["network", "ls", "--filter", "name=^" + net.name + "$", "-q"]).trim(); if (found) { const x = JSON.parse(command("docker", ["network", "inspect", found]))[0]; check(x.Labels["org.drumee.infra.owner"], project); check(Object.keys(x.Containers).length, 0); command("docker", ["network", "rm", found]); } }
        }
        if (provider) { check(JSON.parse(command("docker", ["inspect", provider]))[0].Config.Labels["org.drumee.qualification"], project); command("docker", ["rm", "-f", provider]); }
        if (networkCreated) { const x = JSON.parse(command("docker", ["network", "inspect", network]))[0]; check(x.Labels["org.drumee.qualification"], project); check(Object.keys(x.Containers).length, 0); command("docker", ["network", "rm", network]); }
      }
    }
    report.status = "passed"; delete report.current_case; delete report.phase;
  } catch (error) { report.status = "failed"; report.failure = { code: /^[A-Z_]+$/.test(error.code || "") ? error.code : "SMTP_CONSUMER_QUALIFICATION_FAILED", frame: String(error.stack).split("\n").find(line => line.includes("relay-auth.js:") && !line.includes("at check")) }; process.exitCode = 1; console.error(JSON.stringify(report.failure)); }
  finally {
    check(fs.lstatSync(base).uid, process.getuid()); command("docker", ["run", "--rm", "--network", "none", "--user", "0:0", "--mount", "type=bind,source=" + base + ",target=/work", "node:22-bookworm-slim@sha256:c3de60bf2f9dd0ac6370e6117950ff62d6e339527e7472301c9c78a017978392", "node", "-e", "const f=require('fs');for(const x of f.readdirSync('/work'))f.rmSync('/work/'+x,{recursive:true,force:true})"]); fs.rmdirSync(base);
    fs.writeFileSync(input.output, JSON.stringify(report, null, 2), { mode: 0o600 }); console.log("DEBIAN_RELAY_AUTH_REPORT_WRITTEN");
  }
}
main().catch(() => { console.error("SMTP_CONSUMER_QUALIFICATION_FAILED"); process.exitCode = 1; });
