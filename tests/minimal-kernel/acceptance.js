"use strict";
const { assert, counts, setScope } = require("./assertions");
const fs = require("node:fs"), path = require("node:path"), https = require("node:https"), crypto = require("node:crypto");
const { spawn, spawnSync } = require("node:child_process");
const fixture_root = path.resolve(__dirname, "../../profiles/minimal-kernel");
const { client: WebSocketClient } = require(require.resolve("websocket", { paths: [fixture_root] }));
const sleep = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
async function verify({ prepared, directory, driver, baseline, accounts, operation_id }) {
  const starting_counts = { ...counts };
  const config = prepared.composition.plan.inputs.adapter_input;
  const binding = config.gateway.bindings[0], port = binding.host_port;
  const ca = fs.readFileSync(path.join(prepared.candidate, "ca-public.pem"));
  const hostname = "drumee.lan:" + port, origin = "https://" + hostname;
  const operator = require(path.join(fixture_root, "vendor/operator-bootstrap/lib"));
  const credential = operator.retrieveInitialCredential({ file: path.join(prepared.root, "durable/operator-state/credential.json"), authorization: { authorized: true, scope: "retrieve-initial-credential", operation_id } });
  accounts.principals.owner.password = credential.password.toString(); credential.password.fill(0);
  const cookies = {};
  const request = (method, route, { user, body, headers = {} } = {}) => new Promise((resolve, reject) => {
    const req = https.request({ agent: false, hostname: binding.host_address, port, servername: "drumee.lan", ca, rejectUnauthorized: true, method, path: route, headers: { Host: hostname, ...(cookies[user] ? { Cookie: cookies[user] } : {}), ...headers } }, res => {
      const chunks = []; res.on("data", chunk => chunks.push(chunk)); res.on("end", () => resolve({ status: res.statusCode, headers: res.headers, bytes: Buffer.concat(chunks) })); res.on("error", reject);
    }); req.on("error", reject); req.setTimeout(15000, () => req.destroy(Error("REQUEST_TIMEOUT"))); req.end(body);
  });
  async function service(name, input = {}, user = "owner", status = 200) {
    const response = await request("POST", "/-/svc/" + name, { user, body: JSON.stringify(input), headers: { "content-type": "application/json" } });
    assert.equal(response.status, status, "Unexpected status for " + name + " / " + (user || "anonymous"));
    const value = JSON.parse(response.bytes);
    return { ...response, value, data: value.data };
  }
  let checks = 0;
  const check = async (name, callback) => { await callback(); checks++; console.log("KERNEL_CONTRACT_OK " + name); };
  await check("real-signin-session-and-invalid-credentials", async () => {
    await service("yp.signin", { uid: accounts.principals.owner.id, password: "deliberately-invalid" }, null, 401);
    for (const [name, principal] of Object.entries(accounts.principals)) {
      const response = await service("yp.signin", { uid: principal.id, password: principal.password }, null);
      assert.equal(response.data.authenticated, true);
      cookies[name] = response.headers["set-cookie"][0].split(";")[0];
      assert.equal(response.headers.regsid, cookies[name].slice("regsid=".length));
    }
  });
  await check("canonical-enrolled-platform-administrator-dispatch", async () => {
    assert.equal((await service("kernel.platform_info")).data.policy, "PLATFORM_ADMINISTRATOR");
    await service("kernel.platform_info", {}, "reader", 403);
    await service("kernel.platform_info", {}, "outsider", 403);
  });
  const { data: context } = await service("kernel.context"); const a = context.hubs[0].root, b = context.hubs[1].root;
  await check("canonical-hub-acl-and-cross-hub-denial", async () => {
    assert.equal(context.hubs.length, 2);
    await service("mfs.list", { location: a }, "reader");
    await service("mfs.list", { location: a }, "outsider", 403);
    await service("mfs.list", { location: b }, "reader", 403);
    await service("mfs.list", { location: a }, null, 404);
    await service("mfs.mkdir", { destination: a, name: "reader-cannot-write" }, "reader", 403);
  });
  await check("platform-remit-cannot-bypass-foreign-hub-mfs-acl", async () => {
    await service("mfs.list", { location: accounts.foreign_root }, "owner", 403);
    await service("mfs.list", { location: accounts.foreign_root }, "outsider", 403);
    await service("mfs.list", { location: accounts.foreign_root }, "reader");
  });
  let node = baseline?.node;
  const bytes = Buffer.alloc(2 * 1024 * 1024 + 17, 0x51); bytes.write("Drumee IL3 persistent original\n");
  const digest = crypto.createHash("sha256").update(bytes).digest("hex");
  if (!baseline) await check("real-binary-chunks-retries-order-limits-and-commit", async () => {
    const { data: start } = await service("mfs-transfer.upload_start", { destination: a, metadata: { filename: "IL3 original.bin", mimetype: "application/octet-stream", size: bytes.length }, size: bytes.length });
    for (const index of [1, 0, 1, 2]) {
      const chunk = bytes.subarray(index * start.chunk_size, Math.min(bytes.length, (index + 1) * start.chunk_size));
      const response = await request("POST", `/-/svc/mfs-transfer.upload_chunk?transfer_id=${start.transfer_id}&index=${index}`, { user: "owner", body: chunk, headers: { "content-type": "application/octet-stream", ...(index === 1 ? { "transfer-encoding": "chunked" } : { "content-length": String(chunk.length) }) } });
      assert.equal(response.status, 200, "binary chunk rejected");
    }
    const too_large = await request("POST", `/-/svc/mfs-transfer.upload_chunk?transfer_id=${start.transfer_id}&index=0`, { user: "owner", body: Buffer.alloc(1024 * 1024 + 1), headers: { "content-type": "application/octet-stream" } });
    assert.equal(too_large.status, 413);
    const result = await service("mfs-transfer.upload_complete", { transfer_id: start.transfer_id, sha256: digest });
    node = { hub_id: result.data.result.hub_id, nid: result.data.result.nid };
    assert.match(node.nid, /^[a-f0-9]{16}$/);
  });
  const media = `/-/svc/media.orig?hub_id=${node.hub_id}&nid=${node.nid}`;
  await check("real-fileio-protected-bytes-range-head-and-denials", async () => {
    for (const user of ["owner", "reader"]) { const response = await request("GET", media, { user }); assert.equal(response.status, 200); assert.equal(crypto.createHash("sha256").update(response.bytes).digest("hex"), digest); assert.equal(response.headers["x-accel-redirect"], undefined); }
    assert.equal((await request("GET", media, { user: "outsider" })).status, 403);
    assert.equal((await request("GET", media)).status, 404);
    const range = await request("GET", media, { user: "owner", headers: { Range: "bytes=3-20" } }); assert.equal(range.status, 206); assert.deepEqual(range.bytes, bytes.subarray(3, 21));
    assert.equal((await request("GET", media, { user: "owner", headers: { Range: "bytes=999999999-" } })).status, 416);
    const head = await request("HEAD", media, { user: "owner" }); assert.equal(head.status, 200); assert.equal(head.bytes.length, 0); assert.equal(head.headers["content-length"], String(bytes.length));
    for (const uri of ["/__drumee_artifacts/", "/__drumee_artifacts/../acceptance/principals.json", "/__drumee_artifacts/%252e%252e/secrets", "/mfs/raw", "/etc/passwd"]) assert.ok([400, 403, 404].includes((await request("GET", uri)).status));
  });
  await check("nginx-refuses-protected-symlink-escape", async () => {
    const original = path.join(prepared.root, "durable/content", node.hub_id, node.nid);
    const saved = original + ".il3-symlink-test";
    fs.renameSync(original, saved);
    try {
      // Readable in kernel, absent from gateway; delegation cannot expose it.
      fs.symlinkSync("/run/infra/database", original);
      const response = await request("GET", media, { user: "owner" });
      assert.ok([403, 404].includes(response.status));
    } finally { fs.unlinkSync(original); fs.renameSync(saved, original); }
  });
  await check("real-archive-through-fileio", async () => {
    const { data: job } = await service("mfs-transfer.download_prepare", { roots: [node] });
    let ready = false;
    for (let attempt = 0; attempt < 100; attempt++) { const status = await service("mfs-transfer.download_status", { transfer_id: job.transfer_id }); if (status.data.status === "ready") { ready = true; break; } await sleep(50); }
    assert.equal(ready, true);
    const response = await request("POST", "/-/svc/mfs-transfer.download_retrieve", { user: "owner", body: JSON.stringify({ transfer_id: job.transfer_id }), headers: { "content-type": "application/json" } });
    assert.equal(response.status, 200); assert.equal(response.bytes.subarray(0, 2).toString(), "PK");
    await service("mfs-transfer.download_release", { transfer_id: job.transfer_id });
  });
  async function socket(token, protocol = "service", requested_origin = origin) {
    return new Promise((resolve, reject) => {
      const client = new WebSocketClient({ tlsOptions: { ca, rejectUnauthorized: true, servername: "drumee.lan" } });
      client.once("connectFailed", () => reject(Error("WEBSOCKET_REJECTED")));
      client.once("connect", connection => { const messages = []; connection.on("message", message => { if (message.type === "utf8") messages.push(JSON.parse(message.utf8Data)); }); resolve({ connection, messages }); });
      client.connect(`wss://${binding.host_address}:${port}/-/websocket/?otak=${encodeURIComponent(token || "")}`, protocol, requested_origin, { Host: hostname });
    });
  }
  await check("real-otak-origin-protocol-redis-events-and-reconnect", async () => {
    await assert.rejects(() => socket(null));
    const token = (await service("bootstrap.authn")).data.token;
    await assert.rejects(() => socket(token, "wrong"));
    await assert.rejects(() => socket(token, "service", "https://unexpected.invalid"));
    const opened = await socket(token);
    try {
      opened.connection.sendUTF(JSON.stringify({ service: "sys.ping", data: { proof: "il3" } }));
      for (let attempt = 0; attempt < 100 && !opened.messages.some(message => message.service === "sys.ping"); attempt++) await sleep(20);
      assert.ok(opened.messages.some(message => message.service === "sys.ping" && message.data.ok));
      // Actual RedisStore publisher -> Redis -> runtime subscriber -> socket.
      driver.compose(prepared, ["exec", "-T", "kernel", "node", "-e", `process.env.credential_dir='/run/infra';const R=require('./vendor/essentials/redis-store');(async()=>{await new R().init();const db=await require('./lib/database').connect();const ids=await db.query('SELECT id AS socket_id FROM socket WHERE uid=?',${JSON.stringify(accounts.principals.owner.id)});await R.sendData({service:'fixture.redis',data:{proof:'redis-pubsub'}},ids);await db.close();process.exit(0)})().catch(()=>process.exit(1))`]);
      for (let attempt = 0; attempt < 100 && !opened.messages.some(message => message.service === "fixture.redis"); attempt++) await sleep(20);
      assert.ok(opened.messages.some(message => message.service === "fixture.redis" && message.data.proof === "redis-pubsub"));
    } finally { opened.connection.close(); }
    const second = await socket((await service("bootstrap.authn")).data.token); second.connection.close();
  });
  await check("bind-authority-no-recursion-and-private-network-exposure", async () => {
    const dns = config.services.dns.bindings[0];
    const output = spawnSync("dig", ["@" + dns.host_address, "-p", String(dns.host_port), "drumee.lan", "A", "+short"], { encoding: "utf8" }); assert.equal(output.status, 0); assert.equal(output.stdout.trim(), prepared.composition.plan.inputs.spec.dns.ipv4);
    const denied = spawnSync("dig", ["@" + dns.host_address, "-p", String(dns.host_port), "example.net", "A"], { encoding: "utf8" }); assert.equal(denied.status, 0); assert.match(denied.stdout, /status: REFUSED/);
    const resources = driver.inspectProject(prepared.project, Object.keys(prepared.compose.services));
    for (const resource of resources.filter(value => ["database", "redis", "kernel"].includes(value.service))) assert.ok(Object.values(resource.ports || {}).every(value => value === null));
    assert.equal(driver.compose(prepared, ["exec", "-T", "gateway", "nginx", "-t"]).includes(""), true);
  });
  const queries = [
    "SELECT e.id,e.dom_id,e.type,e.status,d.username,d.fingerprint,d.email,d.remit FROM yp.entity e JOIN yp.drumate d ON e.id=d.id ORDER BY e.id",
    "SELECT uid,domain_id,privilege,is_authoritative FROM yp.privilege ORDER BY uid",
    "SELECT id,owner_id,domain_id,name FROM yp.hub ORDER BY id",
    "SELECT hub_id,uid,privilege FROM yp.hub_acl ORDER BY hub_id,uid",
    "SELECT conf_key,conf_value FROM yp.sys_conf ORDER BY conf_key",
    "SELECT * FROM yp.initial_operator_enrollment"
  ];
  const shards = driver.query(prepared, "SELECT database_name FROM yp.hub_lifecycle ORDER BY hub_id;").trim().split("\n");
  for (const shard of shards) { assert.match(shard, /^hub_[a-f0-9]{16}$/); queries.push(`SELECT * FROM ${shard}.media ORDER BY id`, `SELECT * FROM ${shard}.permission ORDER BY resource_id,entity_id`); }
  const credential_resource_digest = crypto.createHash("sha256").update(fs.readFileSync(path.join(prepared.root, "durable/operator-state/credential.json"))).digest("hex");
  if (baseline) assert.equal(credential_resource_digest, baseline.credential_resource_digest, "Initial operator credential changed across restart/recovery");
  const inventory_digest = crypto.createHash("sha256").update(driver.query(prepared, queries.join(";\n") + ";")).digest("hex");
  assert.match(inventory_digest, /^[a-f0-9]{64}$/);
  if (baseline) {
    assert.equal(inventory_digest, baseline.inventory_digest, "Canonical identity/ACL/MFS recovery digest mismatch");
    assert.equal(prepared.certificate.ca_fingerprint, baseline.ca_fingerprint);
  }
  await check("chromium-letc-finder-and-websocket", async () => {
    if (process.env.IL4_EXTERNAL_BROWSER_DIRECTORY) await externalBrowser({ origin, binding, prepared, account: accounts.principals.owner });
    else await browser({ origin, binding, prepared, directory, account: accounts.principals.owner });
  });
  console.log("KERNEL_ACCEPTANCE_CHECKS " + checks);
  return { node, inventory_digest, credential_resource_digest, ca_fingerprint: prepared.certificate.ca_fingerprint, checks, assertions: { functional: counts.functional - starting_counts.functional, browser: counts.browser - starting_counts.browser } };
}
async function browser({ origin, binding, prepared, directory, account }) {
  const previous_scope = setScope("browser");
  const { once } = require("node:events");
  const certificate_mount = prepared.compose.services.gateway.volumes.find(mount => mount.target === "/run/secrets/tls-certificate");
  const cert = new crypto.X509Certificate(fs.readFileSync(path.resolve(prepared.candidate, certificate_mount.source)));
  const spki = crypto.createHash("sha256").update(cert.publicKey.export({ type: "spki", format: "der" })).digest("base64");
  const profile = fs.mkdtempSync(path.join(directory, "chrome-"));
  const chrome = spawn(process.env.CHROME_BIN || "/usr/bin/google-chrome", ["--headless=new", "--no-sandbox", "--disable-gpu", "--no-proxy-server", "--no-first-run", "--disable-background-networking", "--remote-debugging-port=0", "--user-data-dir=" + profile, "--host-resolver-rules=MAP drumee.lan " + binding.host_address, "--ignore-certificate-errors-spki-list=" + spki, "about:blank"], { stdio: "ignore", detached: true });
  let socket;
  try {
    let devtools;
    for (let attempt = 0; attempt < 200; attempt++) { const file = path.join(profile, "DevToolsActivePort"); if (fs.existsSync(file)) { devtools = fs.readFileSync(file, "utf8").split("\n")[0]; break; } if (chrome.exitCode !== null) throw Error("CHROMIUM_EXITED"); await sleep(50); }
    assert.ok(devtools, "Chromium debugging unavailable");
    const pages = await (await fetch("http://127.0.0.1:" + devtools + "/json/list")).json();
    socket = new WebSocket(pages.find(page => page.type === "page").webSocketDebuggerUrl); await once(socket, "open");
    let serial = 0; const pending = new Map(); const failures = [], responses = [];
    socket.addEventListener("message", event => { const message = JSON.parse(event.data); if (message.method === "Runtime.exceptionThrown") failures.push("JS_EXCEPTION"); if (message.method === "Network.loadingFailed" && message.params.type !== "Other") failures.push("NETWORK_FAILED"); if (message.method === "Network.responseReceived") responses.push({ type: message.params.type, status: message.params.response.status }); if (pending.has(message.id)) { const call = pending.get(message.id); pending.delete(message.id); message.error ? call.reject(Error("DEVTOOLS_ERROR")) : call.resolve(message.result); } });
    const send = (method, params = {}) => new Promise((resolve, reject) => { const id = ++serial; pending.set(id, { resolve, reject }); socket.send(JSON.stringify({ id, method, params })); });
    const evaluate = async expression => { const result = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true }); if (result.exceptionDetails) { console.error("BROWSER_EXCEPTION_TYPE " + (result.exceptionDetails.exception?.className || "unknown")); throw Error("BROWSER_EVALUATION_FAILED"); } return result.result.value; };
    await send("Runtime.enable"); await send("Network.enable"); await send("Page.enable");
    await send("Page.navigate", { url: origin });
    for (let attempt = 0; attempt < 100 && !await evaluate("typeof openDrumee==='function'"); attempt++) await sleep(100);
    console.log("BROWSER_BOOTSTRAP_STATE " + JSON.stringify({ ...(await evaluate("({title:document.title,bundle:document.body?.dataset.bundle,error:document.body?.dataset.error,entry:typeof openDrumee})")), responses, failures }));
    assert.equal(await evaluate("typeof openDrumee"), "function", "Frontend bootstrap unavailable");
    await evaluate("(()=>{const form=document.getElementById('login');form.elements.username.value=" + JSON.stringify(account.email) + ";form.elements.password.value=" + JSON.stringify(account.password) + ";form.requestSubmit();return true})()");
    for (let attempt = 0; attempt < 100 && !await evaluate("document.body.dataset.ready==='true'"); attempt++) await sleep(100);
    const result = await evaluate("({ready:document.body.dataset.ready==='true',hubs:window.kernelAcceptance?.context.hubs.length,kind:window.kernelAcceptance?.view?'finder':null})");
    assert.equal(result.ready, true); assert.equal(result.hubs, 2); assert.equal(result.kind, "finder");
    assert.equal(await evaluate("document.getElementById('login').elements.password.value.length"), 0);
    assert.equal(await evaluate("kernelAcceptance.websocket.connected || document.body.dataset.ready==='true'"), true);
    assert.deepEqual(failures, []);
    console.log("BROWSER_LETC_FINDER_WEBSOCKET_VERIFIED");
    await send("Browser.close").catch(() => {});
  } finally {
    setScope(previous_scope);
    socket?.close();
    // Only this detached process group is owned; never kill by executable name.
    if (chrome.exitCode === null) { try { process.kill(-chrome.pid, "SIGTERM"); } catch (_) {} await Promise.race([once(chrome, "exit"), sleep(2000)]); }
    try { process.kill(-chrome.pid, "SIGKILL"); } catch (_) {}
    await sleep(200);
    fs.rmSync(profile, { recursive: true, force: true, maxRetries: 20, retryDelay: 100 });
  }
}
async function externalBrowser({ origin, binding, prepared, account }) {
  const root = process.env.IL4_EXTERNAL_BROWSER_DIRECTORY;
  const stat = fs.lstatSync(root);
  assert.ok(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === process.getuid() && !(stat.mode & 0o077));
  const nonce = crypto.randomBytes(16).toString("hex");
  const mount = prepared.compose.services.gateway.volumes.find(value => value.target === "/run/secrets/tls-certificate");
  const dns = prepared.composition.plan.inputs.adapter_input.services.dns.bindings[0];
  const request = { nonce, origin, binding, dns, project: prepared.project, revision: prepared.revision, ca: fs.readFileSync(path.join(prepared.candidate, "ca-public.pem"), "utf8"), certificate: fs.readFileSync(path.resolve(prepared.candidate, mount.source), "utf8"), account };
  fs.writeFileSync(path.join(root, "request-" + nonce + ".json"), JSON.stringify(request), { mode: 0o600, flag: "wx" });
  console.log("EXTERNAL_LAN_BROWSER_REQUESTED " + nonce);
  try {
    for (let attempt = 0; attempt < 600; attempt++) {
      const result_file = path.join(root, "result-" + nonce + ".json");
      if (fs.existsSync(result_file)) {
        const result = JSON.parse(fs.readFileSync(result_file, "utf8"));
        assert.equal(result.nonce, nonce); assert.equal(result.success, true, "External LAN browser acceptance failed");
        return;
      }
      await sleep(1000);
    }
    throw Error("EXTERNAL_BROWSER_TIMEOUT");
  } finally { fs.unlinkSync(path.join(root, "request-" + nonce + ".json")); }
}
module.exports = { verify, browser };
