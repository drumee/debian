"use strict";
const fs = require("node:fs"), path = require("node:path"), os = require("node:os"), net = require("node:net"), http = require("node:http"), https = require("node:https"), crypto = require("node:crypto");
const { execFileSync, spawn } = require("node:child_process");
const command = (file, args, options = {}) => execFileSync(file, args, { encoding: "utf8", stdio: "pipe", timeout: 300000, ...options });
const freePort = () => new Promise((resolve, reject) => { const s = net.createServer(); s.on("error", reject); s.listen(0, "127.0.0.1", () => { const p = s.address().port; s.close(() => resolve(p)); }); });
function request(port, service, input = {}, tls) { return new Promise((resolve, reject) => { const req = (tls ? https : http).request({ hostname: "127.0.0.1", port, path: "/-/svc/" + service, method: "POST", agent: false, ...(tls ? { ca: tls, servername: "application.test", rejectUnauthorized: true } : {}), headers: { "content-type": "application/json" } }, res => { const chunks = []; res.on("data", x => chunks.push(x)); res.on("error", reject); res.on("end", () => { let body; try { body = JSON.parse(Buffer.concat(chunks)); } catch (_) {} resolve({ status: res.statusCode, body }); }); }); req.setTimeout(10000, () => req.destroy()); req.on("error", reject); req.end(JSON.stringify(input)); }); }
async function externalNetwork(port, lan, client) {
  if (!Object.values(os.networkInterfaces()).flat().some(x => x.address === lan && !x.internal)) throw Error("EXPLICIT_LAN_ADDRESS_REQUIRED");
  const nonce = crypto.randomBytes(16).toString("hex"), control = http.createServer((req, res) => res.end(nonce));
  await new Promise((resolve, reject) => { control.once("error", reject); control.listen(0, lan, resolve); });
  const script = `const http=require('node:http'),net=require('node:net');(async()=>{const control=await new Promise((resolve,reject)=>{const q=http.get({hostname:${JSON.stringify(lan)},port:${control.address().port}},r=>{let s='';r.on('data',x=>s+=x);r.on('end',()=>resolve(s))});q.setTimeout(4000,()=>q.destroy());q.on('error',reject)});if(control!==${JSON.stringify(nonce)})throw Error('CONTROL_ROUTE_FAILED');const result=await new Promise((resolve,reject)=>{const s=net.connect({host:${JSON.stringify(lan)},port:${port}});s.setTimeout(3000,()=>{s.destroy();resolve('timeout')});s.on('connect',()=>{s.destroy();reject(Error('PUBLIC_APPLICATION_EXPOSURE'))});s.on('error',e=>['ECONNREFUSED','ETIMEDOUT','EHOSTUNREACH'].includes(e.code)?resolve(e.code):reject(e));});console.log(JSON.stringify({control_route:true,application_non_loopback:result}));})().catch(()=>process.exit(1));`;
  try {
    const response = await new Promise((resolve, reject) => { const child = spawn("ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", client, "node -e '" + script.replaceAll("'", "'\\''") + "'"], { stdio: ["ignore", "pipe", "pipe"] }); let output = ""; child.stdout.on("data", b => output += b); child.stderr.resume(); child.on("error", reject); child.on("exit", code => code === 0 ? resolve(JSON.parse(output)) : reject(Error("EXTERNAL_NETWORK_QUALIFICATION_FAILED"))); });
    if (!response.control_route || !response.application_non_loopback) throw Error("EXTERNAL_NETWORK_QUALIFICATION_FAILED"); return response;
  } finally { await new Promise(resolve => control.close(resolve)); }
}
module.exports = { freePort, request, externalNetwork };
