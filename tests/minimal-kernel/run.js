"use strict";
// Owned, disposable real distribution acceptance. Never installs a test principal
// in an ordinary deployment. Canonical enrollment creates the human administrator.
const fs = require("node:fs"), path = require("node:path"), os = require("node:os"), net = require("node:net"), crypto = require("node:crypto"), https = require("node:https");
const { assert, counts } = require("./assertions"), { spawnSync, spawn } = require("node:child_process");
const profile = path.resolve(__dirname, "../../profiles/minimal-kernel");
const load = name => require(require.resolve(name, { paths: [profile] }));
const lifecycle = load("@drumee/infra-layer/lifecycle"), A = load("@drumee/infra-layer/lifecycle/activation");
const { createDriver, query } = require(path.join(profile, "lib/driver"));
const driver = { ...createDriver(), query };
const operator = require(path.join(profile, "operator"));
const yaml = cfg => Object.entries(cfg).map(([section, values]) => section + ":\n" + Object.entries(values).map(([key, value]) => "  " + key + ": " + JSON.stringify(value)).join("\n")).join("\n") + "\n";
const port = () => new Promise((resolve, reject) => { const s = net.createServer(); s.once("error", reject); s.listen(0, "127.0.0.1", () => { const p = s.address().port; s.close(() => resolve(p)); }); });
function installChild(file) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [path.join(profile, "operator.js"), "install", "--execute", "--recover", "--config", file], { stdio: ["ignore", "pipe", "pipe"] });
    let stderr = ""; child.stdout.resume(); child.stderr.on("data", bytes => { stderr += bytes; }); child.once("error", reject); child.once("exit", status => resolve({ status, stderr }));
  });
}
async function interruptedInitialization(file, cfg) {
  const child = spawnSync(process.execPath, [path.join(__dirname, "interrupt.js"), file], { encoding: "utf8", timeout: 600000 });
  assert.equal(child.signal, "SIGKILL", "Canonical enrollment commit interruption was not reached");
  const lock = path.join(cfg.storage.root, ".infra-lifecycle-lock"), stat = fs.lstatSync(lock);
  assert.equal(stat.uid, process.getuid()); assert.equal(stat.isDirectory() && !stat.isSymbolicLink(), true); assert.equal(fs.readdirSync(lock).length, 0);
  // Explicit test recovery after the exact killed child has been reaped.
  fs.rmdirSync(lock);
  const candidates = fs.readdirSync(path.join(cfg.storage.root, "candidates")).map(name => path.join(cfg.storage.root, "candidates", name, "prepared.json")).filter(fs.existsSync);
  const prepared = JSON.parse(fs.readFileSync(candidates.at(-1)));
  const state = query(prepared, "SELECT uid,operation_id,credential_commitment FROM yp.initial_operator_enrollment;");
  const resource = path.join(cfg.storage.root, "durable/operator-state/credential.json"), bytes = fs.readFileSync(resource), parked = resource + ".test-parked";
  fs.renameSync(resource, parked);
  try {
    await assert.rejects(operator.run({ command: "install", config: file, execute: true, recover: true }));
    assert.equal(fs.existsSync(resource), false, "Committed credentials must never be regenerated");
    assert.equal(query(prepared, "SELECT uid,operation_id,credential_commitment FROM yp.initial_operator_enrollment;"), state);
  } finally { fs.renameSync(parked, resource); }
  const raced = await Promise.all([installChild(file), installChild(file)]);
  assert.ok(raced.some(value => value.status === 0)); assert.ok(raced.every(value => [0, 1].includes(value.status)));
  assert.equal(query(A.readActive(cfg.storage.root).prepared, "SELECT uid,operation_id,credential_commitment FROM yp.initial_operator_enrollment;"), state);
  assert.equal(fs.readFileSync(resource).equals(bytes), true);
  assert.equal(query(A.readActive(cfg.storage.root).prepared, "SELECT COUNT(*) FROM yp.drumate WHERE remit=15;").trim(), "1");
  console.log("INITIALIZATION_INTERRUPTION_CONCURRENCY_AND_MISSING_CREDENTIAL_PRESERVATION_VERIFIED");
}
function clean(prepared) {
  assert.match(prepared.project, /^drumee-il4-[a-f0-9]{8}(?:-restored)?$/);
  driver.inspectProject(prepared.project, Object.keys(prepared.compose.services));
  driver.checkNetworks(prepared.composition);
  const owner = JSON.parse(fs.readFileSync(path.join(prepared.root, "deployment-owner.json")));
  assert.equal(owner.project, prepared.project); assert.equal(owner.uid, process.getuid());
  driver.compose(prepared, ["down"]);
  driver.helper(prepared.composition, prepared.root, "const fs=require('node:fs');for(const name of fs.readdirSync('/work'))fs.rmSync('/work/'+name,{recursive:true,force:true});", [], true);
  fs.rmdirSync(prepared.root);
}
async function request(prepared, service, input, cookie) {
  const binding = prepared.composition.plan.inputs.adapter_input.gateway.bindings[0];
  return new Promise((resolve, reject) => {
    const req = https.request({ agent: false, hostname: binding.host_address, port: binding.host_port, servername: "drumee.lan", ca: fs.readFileSync(path.join(prepared.candidate, "ca-public.pem")), rejectUnauthorized: true, method: "POST", path: "/-/svc/" + service, headers: { Host: "drumee.lan:" + binding.host_port, "content-type": "application/json", ...(cookie ? { Cookie: cookie } : {}) } }, res => {
      const chunks = []; res.on("data", bytes => chunks.push(bytes)); res.on("end", () => resolve({ status: res.statusCode, headers: res.headers, body: JSON.parse(Buffer.concat(chunks)) })); res.on("error", reject);
    }); req.on("error", reject); req.setTimeout(120000, () => req.destroy()); req.end(JSON.stringify(input));
  });
}
async function preparation(prepared, cfg) {
  assert.equal(cfg.deployment.acceptance, true, "EXPLICIT_ISOLATION_REQUIRED");
  const principals = { owner: { id: query(prepared, `SELECT id FROM yp.drumate WHERE username='${cfg.operator.username}' AND domain_id=1;`).trim(), email: cfg.operator.email } };
  assert.match(principals.owner.id, /^[a-f0-9]{16}$/);
  assert.equal(query(prepared, "SELECT COUNT(*) FROM yp.hub;").trim(), "0", "Enrollment must create no Hubs");
  for (const name of ["reader", "outsider"]) {
    const id = query(prepared, "SELECT yp.uniqueId();").trim(), password = crypto.randomBytes(32).toString("base64url");
    assert.match(id, /^[a-f0-9]{16}$/);
    const fingerprint = crypto.createHash("sha512").update(password).digest("hex");
    principals[name] = { id, email: `il4-${name}@drumee.lan`, password };
    // Explicit acceptance-only auxiliary identities. No owner/admin fixture SQL.
    query(prepared, `START TRANSACTION;
      INSERT INTO yp.entity (id,ident,db_name,home_dir,type,area,dom_id,status,ctime,mtime,settings) VALUES ('${id}','il4-${name}','identity_${id}','/acceptance/${id}','drumate','personal',1,'active',UNIX_TIMESTAMP(),UNIX_TIMESTAMP(),'{}');
      INSERT INTO yp.drumate (id,username,domain_id,fingerprint,profile) VALUES ('${id}','il4-${name}',1,'${fingerprint}','{"email":"il4-${name}@drumee.lan","otp":0}');
      INSERT INTO yp.privilege (uid,domain_id,privilege,is_authoritative) VALUES ('${id}',1,3,1); COMMIT;`);
  }
  const credential = require(path.join(profile, "vendor/operator-bootstrap/lib")).retrieveInitialCredential({ file: path.join(prepared.root, "durable/operator-state/credential.json"), authorization: { authorized: true, scope: "retrieve-initial-credential", operation_id: cfg.operator.operation_id } });
  let signin;
  try { signin = await request(prepared, "yp.signin", { uid: cfg.operator.email, password: credential.password.toString() }); }
  finally { credential.password.fill(0); }
  assert.equal(signin.status, 200); const cookie = signin.headers["set-cookie"][0].split(";")[0];
  const created = [];
  for (const name of ["a", "b"]) {
    const result = await request(prepared, "kernel.create_hub", { name: "IL4 " + name, idempotency_key: "il4-" + name }, cookie);
    assert.equal(result.status, 200, result.body.code); assert.equal(result.body.data.status, "ready"); created.push(result.body.data.hub_id);
  }
  const hubs = created.sort();
  const read = require(path.join(profile, "vendor/essentials/lex/constants")).privilege.read;
  query(prepared, `INSERT INTO yp.hub_acl (hub_id,uid,privilege,granted_by,ctime,mtime) VALUES ('${hubs[0]}','${principals.reader.id}',${read},'${principals.owner.id}',UNIX_TIMESTAMP(),UNIX_TIMESTAMP());
    INSERT INTO hub_${hubs[0]}.permission (resource_id,entity_id,message,expiry_time,ctime,utime,permission,assign_via) VALUES ('*','${principals.reader.id}','IL4 isolated reader',0,UNIX_TIMESTAMP(),UNIX_TIMESTAMP(),3,'root');`);
  const reader_login = await request(prepared, "yp.signin", { uid: principals.reader.id, password: principals.reader.password });
  const reader_cookie = reader_login.headers["set-cookie"][0].split(";")[0];
  assert.equal((await request(prepared, "kernel.create_hub", { name: "Denied", idempotency_key: "denied-reader" }, reader_cookie)).status, 403);
  query(prepared, `UPDATE yp.drumate SET remit=15 WHERE id='${principals.reader.id}';`);
  const foreign = await request(prepared, "kernel.create_hub", { name: "Other principal Hub", idempotency_key: "il4-foreign" }, reader_cookie);
  query(prepared, `UPDATE yp.drumate SET remit=0 WHERE id='${principals.reader.id}';`);
  assert.equal(foreign.status, 200); assert.match(foreign.body.data.hub_id, /^[a-f0-9]{16}$/);
  const foreign_id = foreign.body.data.hub_id, nid = query(prepared, `SELECT root_id FROM yp.system_mfs_provisioning WHERE hub_id='${foreign_id}';`).trim();
  const foreign_root = { hub_id: foreign_id, nid };
  assert.equal((await request(prepared, "mfs.list", { location: foreign_root }, cookie)).status, 403);
  // Test that Hub administration itself still does not confer MFS node access.
  const admin = require(path.join(profile, "vendor/essentials/lex/constants")).privilege.admin;
  query(prepared, `INSERT INTO yp.hub_acl (hub_id,uid,privilege,granted_by,ctime,mtime) VALUES ('${foreign_id}','${principals.owner.id}',${admin},'${principals.reader.id}',UNIX_TIMESTAMP(),UNIX_TIMESTAMP());`);
  return { principals, foreign_root };
}
function negativeSql(prepared) {
  query(prepared, "CREATE DATABASE IF NOT EXISTS il4_unrelated; CREATE TABLE IF NOT EXISTS il4_unrelated.protected (id INT);");
  const sql = ["CREATE DATABASE forbidden_il4", "CREATE DATABASE hub_fffffffffffffffe", "ALTER TABLE yp.entity ADD COLUMN forbidden INT", "UPDATE yp.drumate SET remit=15", "UPDATE yp.initial_operator_enrollment SET operation_id='forbidden'", "CREATE USER forbidden_il4 IDENTIFIED BY 'not-a-credential'", "SELECT * FROM mysql.global_priv", "CREATE TABLE yp.forbidden(id INT)", "GRANT ALL ON *.* TO 'kernel_runtime'@'%'", "DELETE FROM yp.hub_acl", "ALTER TABLE il4_unrelated.protected ADD COLUMN forbidden INT", "SELECT * FROM il4_unrelated.protected", "SELECT * FROM yp.initial_operator_enrollment", "UPDATE yp.cookie SET uid=uid", "DELETE FROM yp.socket WHERE 1=0", "INSERT INTO yp.cookie (id) VALUES ('never-a-real-session')"];
  const script = `const assert=require('node:assert/strict');(async()=>{const db=await require('./lib/database').connect();for(const sql of ${JSON.stringify(sql)})await assert.rejects(db.query(sql),error=>[1044,1045,1142,1227,1370].includes(error.errno));await db.close();console.log('SQL_NEGATIVES_PASSED ${sql.length}')})().catch(()=>process.exit(1));`;
  assert.equal(driver.compose(prepared, ["exec", "-T", "kernel", "node", "-e", script]).trim(), "SQL_NEGATIVES_PASSED " + sql.length);
  console.log("SQL_NEGATIVE_ASSERTIONS " + sql.length); return sql.length;
}
async function run() {
  if (!process.env.IL4_INTERFACE || !process.env.IL4_LAN_ADDRESS) throw Error("EXPLICIT_HOST_NETWORK_REQUIRED");
  const image_file = process.env.IL4_IMAGES || path.join(profile, ".cache/images.json"), images = JSON.parse(fs.readFileSync(image_file));
  const cfg = require(path.join(profile, "test/configuration"))(), project = "drumee-il4-" + crypto.randomBytes(4).toString("hex");
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), project + "-")); fs.chmodSync(directory, 0o700);
  Object.assign(cfg.deployment, { id: project, project, acceptance: true });
  cfg.operator.mode = process.env.IL4_MODE || "automatic";
  if (!["automatic", "interactive"].includes(cfg.operator.mode)) throw Error("EXPLICIT_ENROLLMENT_MODE_REQUIRED");
  Object.assign(cfg.network, { interface: process.env.IL4_INTERFACE, lan_address: process.env.IL4_LAN_ADDRESS, bind_address: process.env.IL4_BIND_ADDRESS || "127.0.0.1" });
  cfg.ports = { https: process.env.IL4_HTTPS_PORT ? Number(process.env.IL4_HTTPS_PORT) : await port(), dns: process.env.IL4_DNS_PORT ? Number(process.env.IL4_DNS_PORT) : await port() };
  cfg.storage = { root: path.join(directory, "deployment"), backup_location: path.join(directory, "backups"), retention_days: 14 };
  cfg.images = { kernel: images.kernel, tools: images.tools }; cfg.provenance = { revision: images.revision, alignment_sha256: images.alignment_sha256 };
  const file = path.join(directory, "config.yaml"); fs.writeFileSync(file, yaml(cfg), { mode: 0o600 });
  let prepared, restored, composition;
  console.log("IL4_SCENARIO " + directory);
  try {
    if (cfg.operator.mode === "interactive") {
      const absent = spawnSync(process.execPath, [path.join(profile, "operator.js"), "install", "--execute", "--config", file], { encoding: "utf8", timeout: 30000 });
      assert.equal(absent.status, 1); assert.match(absent.stderr, /OPERATOR_SECURE_INPUT_REQUIRED/); assert.equal(fs.existsSync(cfg.storage.root), false);
      const result = spawnSync("python3", [path.join(__dirname, "install-pty.py"), path.join(profile, "operator.js"), file, path.join(cfg.storage.root, "durable/operator-state/credential.json")], { encoding: "utf8", timeout: 950000 });
      assert.equal(result.status, 0, result.stderr.slice(0, 250)); assert.equal(JSON.parse(result.stdout).pty_no_echo, true);
      assert.equal((await operator.run({ command: "status", config: file })).ready, true);
      console.log("INTERACTIVE_PTY_NO_ECHO_RESTORATION_VERIFIED");
    } else if (process.env.IL4_INTERRUPT === "1") await interruptedInitialization(file, cfg);
    else assert.equal((await operator.run({ command: "install", config: file, execute: true })).ready, true);
    prepared = A.readActive(cfg.storage.root).prepared; composition = prepared.composition;
    const accounts = await preparation(prepared, cfg), sql_negatives = negativeSql(prepared);
    const acceptance = require("./acceptance"), baseline = await acceptance.verify({ prepared, directory, driver, accounts, operation_id: cfg.operator.operation_id });
    assert.equal((await operator.run({ command: "install", config: file, execute: true })).ready, true);
    prepared = await require("./rotation").verifyRotation(prepared, { root: cfg.storage.root, authorized: true, create_resources: true, driver });
    driver.compose(prepared, ["restart", "database", "redis", "provisioner", "kernel"]);
    assert.equal((await operator.run({ command: "status", config: file })).ready, false);
    assert.equal((await operator.run({ command: "start", config: file, execute: true, recover: true })).ready, true);
    const restart = await acceptance.verify({ prepared, directory, driver, accounts, baseline, operation_id: cfg.operator.operation_id });
    const backup = path.join(cfg.storage.backup_location, "full"), receipt = await operator.run({ command: "backup", config: file, execute: true, backup });
    assert.equal(receipt.protected, true);
    assert.equal((await operator.run({ command: "upgrade", config: file, execute: true, backup })).ready, true);
    assert.equal((await operator.run({ command: "rollback", config: file, execute: true, revision: prepared.revision })).ready, true);
    const restore_cfg = structuredClone(cfg); restore_cfg.deployment.project = project + "-restored"; restore_cfg.storage.root = path.join(directory, "restored"); restore_cfg.network.bind_address = "127.0.0.1"; restore_cfg.ports = { https: await port(), dns: await port() };
    const restore_file = path.join(directory, "restore.yaml"); fs.writeFileSync(restore_file, yaml(restore_cfg), { mode: 0o600 });
    const result = await operator.run({ command: "restore", config: restore_file, backup, execute: true });
    assert.equal(result.ready, true); restored = A.readActive(restore_cfg.storage.root).prepared;
    assert.equal((await operator.run({ command: "install", config: restore_file, execute: true })).ready, true);
    negativeSql(restored);
    const recovery = await acceptance.verify({ prepared: restored, directory, driver, accounts, baseline, operation_id: cfg.operator.operation_id });
    const report = { project, source_revision: images.revision, image_ids: cfg.images, mode: cfg.operator.mode, initialization_interruption: process.env.IL4_INTERRUPT === "1", sql_negative_cases: sql_negatives, stages: { fresh: { groups: baseline.checks, assertions: baseline.assertions }, restart: { groups: restart.checks, assertions: restart.assertions }, restore: { groups: recovery.checks, assertions: recovery.assertions } }, total_harness_assertions: { ...counts }, browser_scenarios: 3, credential_preserved: true, ca_preserved: true, isolated_restore: true, https_port: cfg.ports.https, dns_port: cfg.ports.dns, lan_address: cfg.network.lan_address };
    fs.writeFileSync(path.join(directory, "report.json"), JSON.stringify(report, null, 2)); console.log(JSON.stringify(report));
  } catch (error) {
    console.error(JSON.stringify({ code: error.code || "IL4_ACCEPTANCE_FAILED", assertion: error.code === "ERR_ASSERTION" ? error.message.slice(0, 180) : null }));
    throw error;
  } finally {
    // Recover prepared state even when activation failed before the active pointer.
    for (const root of [path.join(directory, "restored"), cfg.storage.root]) if (fs.existsSync(path.join(root, "candidates"))) {
      const active = A.readActive(root); let value = active?.prepared;
      if (!value) { const files = fs.readdirSync(path.join(root, "candidates")).map(name => path.join(root, "candidates", name, "prepared.json")).filter(fs.existsSync); if (files.length) value = JSON.parse(fs.readFileSync(files.at(-1))); }
      if (value) clean(value);
    }
    const backup = path.join(cfg.storage.backup_location, "full");
    if (composition && fs.existsSync(backup)) { driver.helper(composition, backup, "const fs=require('node:fs');for(const name of fs.readdirSync('/work'))fs.rmSync('/work/'+name,{recursive:true,force:true});", [], true); fs.rmdirSync(backup); }
    console.log("IL4_OWNED_RESOURCES_CLEANED " + directory);
  }
}
if (require.main === module) run().catch(() => { process.exitCode = 1; });
module.exports = { run, yaml, clean, preparation, negativeSql, request };
