"use strict";
// Run on the explicitly configured LAN client; no CA/resolver installation.
// Only private requests from our task-owned testbox directory are consumed.
const fs = require("node:fs"), os = require("node:os"), path = require("node:path"), net = require("node:net"), https = require("node:https");
const { execFileSync, spawn } = require("node:child_process");
const assert = require("node:assert/strict");
const { browser } = require("./acceptance");
const sleep = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const remote = process.argv[2];
if (!/^\/tmp\/drumee-il4-[a-zA-Z0-9_-]+\/browser$/.test(remote || "")) throw Error("INVALID_REMOTE_BROWSER_DIRECTORY");
function ssh(script, input) { return execFileSync("ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "testbox", "node -e " + "'" + script.replaceAll("'", "'\\''") + "'"], { encoding: "utf8", timeout: 30000, input, stdio: ["pipe", "pipe", "pipe"] }); }
async function main() {
  const seen = new Set();
  for (let poll = 0; poll < 1800 && seen.size < 3; poll++) {
    const script = `const fs=require('node:fs'),path=require('node:path');const root=${JSON.stringify(remote)};const s=fs.lstatSync(root);if(!s.isDirectory()||s.isSymbolicLink()||s.uid!==process.getuid()||(s.mode&63))process.exit(78);const values=[];for(const file of fs.readdirSync(root)){if(!/^request-[a-f0-9]{32}\\.json$/.test(file))continue;const p=path.join(root,file),f=fs.lstatSync(p);if(!f.isFile()||f.isSymbolicLink()||f.nlink!==1||f.uid!==process.getuid()||(f.mode&63))process.exit(78);values.push(JSON.parse(fs.readFileSync(p)));}process.stdout.write(JSON.stringify(values));`;
    const requests = JSON.parse(ssh(script));
    for (const request of requests) {
      if (seen.has(request.nonce)) continue;
      assert.match(request.nonce, /^[a-f0-9]{32}$/);
      assert.match(request.project, /^drumee-il4-[a-f0-9]{8}(?:-restored)?$/);
      assert.ok(["127.0.0.1", "192.168.5.202"].includes(request.binding.host_address));
      const port = request.binding.host_port; assert.ok(Number.isInteger(port) && port > 0 && port < 65536);
      assert.equal(request.origin, "https://drumee.lan:" + port);
      const directory = fs.mkdtempSync(path.join(os.tmpdir(), "drumee-il4-lan-browser-")); fs.chmodSync(directory, 0o700);
      let tunnel, success = false;
      try {
        if (request.binding.host_address === "127.0.0.1") {
          await new Promise((resolve, reject) => { const probe = net.createServer(); probe.on("error", reject); probe.listen(port, "127.0.0.1", () => probe.close(resolve)); });
          tunnel = spawn("ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ExitOnForwardFailure=yes", "-N", "-L", `127.0.0.1:${port}:127.0.0.1:${port}`, "testbox"], { stdio: "ignore" });
          await sleep(1000); assert.equal(tunnel.exitCode, null);
        } else {
          const dns = execFileSync("dig", ["@192.168.5.202", "drumee.lan", "A", "+short"], { encoding: "utf8" }); assert.equal(dns.trim(), "192.168.5.202");
          console.log("LAN_DNS_VERIFIED 192.168.5.202");
        }
        fs.writeFileSync(path.join(directory, "ca-public.pem"), request.ca);
        fs.writeFileSync(path.join(directory, "leaf.pem"), request.certificate);
        await new Promise((resolve, reject) => { const req = https.get({ agent: false, hostname: request.binding.host_address, port, servername: "drumee.lan", ca: request.ca, rejectUnauthorized: true, path: "/__infra_ready", headers: { Host: "drumee.lan:" + port } }, response => { response.resume(); response.on("end", () => response.statusCode === 200 ? resolve() : reject(Error("LAN_HTTPS_FAILED"))); }); req.setTimeout(5000, () => req.destroy()); req.on("error", reject); });
        await browser({ origin: request.origin, binding: request.binding, prepared: { candidate: directory, compose: { services: { gateway: { volumes: [{ target: "/run/secrets/tls-certificate", source: "leaf.pem" }] } } } }, directory, account: request.account });
        success = true; console.log("EXTERNAL_BROWSER_VERIFIED " + request.nonce);
      } finally {
        tunnel?.kill("SIGTERM"); fs.rmSync(directory, { recursive: true, force: true });
        ssh(`const fs=require('node:fs');fs.writeFileSync(${JSON.stringify(path.join(remote, "result-" + request.nonce + ".json"))},JSON.stringify({nonce:${JSON.stringify(request.nonce)},success:${success}}),{mode:384,flag:'wx'});`);
      }
      seen.add(request.nonce);
    }
    await sleep(1000);
  }
  assert.equal(seen.size, 3, "Missing remote browser acceptance stages");
}
main().catch(() => { console.error("EXTERNAL_BROWSER_FAILED"); process.exitCode = 1; });
