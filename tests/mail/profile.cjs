"use strict";
const test = require("node:test"), assert = require("node:assert/strict"), fs = require("node:fs"), os = require("node:os"), path = require("node:path"), { spawnSync } = require("node:child_process");
const profile = path.resolve(__dirname, "../../profiles/mail"), { api, verify } = require(profile + "/consumer.cjs"), lock = require(profile + "/infra-source-lock.json");
const installed = profile + "/.cache/consumer/node_modules/@drumee/infra-layer";
test("mail profile uses the closed locked package inventory and detects corruption, extras and links", () => {
  assert.equal(typeof api().prepareMailService, "function");
  const extra = installed + "/unexpected-member";
  try { fs.writeFileSync(extra, "extra"); assert.throws(() => verify(installed, lock), /MAIL_INSTALLED_MEMBER_MISMATCH/); }
  finally { fs.unlinkSync(extra); }
  const file = installed + "/capabilities/mail-service/index.js", original = fs.readFileSync(file);
  try { fs.appendFileSync(file, "\n// mutation"); assert.throws(() => api(), /MAIL_INSTALLED_MEMBER_MISMATCH/); }
  finally { fs.writeFileSync(file, original); }
  try { fs.symlinkSync("package.json", extra); assert.throws(() => verify(installed, lock), /MAIL_INSTALLED_MEMBER_UNSAFE/); }
  finally { fs.unlinkSync(extra); }
  assert.equal(typeof api().planMailService, "function");
});
test("mail profile renderer and administration dispatch remain distinct from Team", () => {
  const example = path.resolve(__dirname, "../../config/drumee.mail.example.json");
  const result = spawnSync(process.execPath, [path.resolve(__dirname, "../../config/render.mjs"), "validate", "--config", example], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr); assert.equal(JSON.parse(result.stdout).distribution.profile, "mail");
  const admin = spawnSync("bash", [path.resolve(__dirname, "../../bin/drumee-ctl"), "--profile", "mail", "mail"], { encoding: "utf8" });
  assert.equal(admin.status, 0); assert.match(admin.stdout, /mailbox\|alias\|account/);
  const unsafe = structuredClone(require(example)); unsafe.extra = true;
  assert.throws(() => require(profile + "/config.cjs").validate(unsafe), /MAIL_PROFILE_INVALID/);
});
test("corrupt archive fails before acquisition and preserves the installed consumer", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "mail02-corrupt-")), archive = root + "/bad.tgz";
  try {
    fs.writeFileSync(archive, "incomplete archive");
    const result = spawnSync(process.execPath, [profile + "/acquire.cjs", archive], { encoding: "utf8" });
    assert.notEqual(result.status, 0); assert.match(result.stderr, /MAIL_ARCHIVE_INTEGRITY_MISMATCH/);
    assert.equal(typeof api().composeMailService, "function");
  } finally { fs.rmSync(root, { recursive: true }); }
});

test("Private Docker descriptor uses the mail-owned frontend without adopting a backend", () => {
  const service=require("../../config/drumee.mail.example.json").service, descriptor=require("../../profiles/mail/private-client.cjs").render(service,service.networks.edge_gateway.replace(/\d+$/, "10"));
  assert.equal(descriptor.network.external,true);assert.equal(descriptor.network.name,service.deployment.project+"-edge");assert.equal(descriptor.submission.verify_peer,true);assert.equal(descriptor.submission.starttls,"required");
  assert.throws(()=>require("../../profiles/mail/private-client.cjs").render(service,service.networks.edge_gateway),/MAIL_PRIVATE_CLIENT_ADDRESS_INVALID/);
});

test("A missing mail state refuses before fallback creation", () => {
  const root=fs.mkdtempSync(path.join(os.tmpdir(),"mail-state-guard-")),cfg=structuredClone(require("../../config/drumee.mail.example.json"));
  cfg.service.deployment.root=path.join(root,"service");cfg.service.deployment.backup_root=path.join(root,"backups");cfg.service.deployment.owner_uid=process.getuid();cfg.service.deployment.owner_gid=process.getgid();
  const config=path.join(root,"config.json");fs.writeFileSync(config,JSON.stringify(cfg),{mode:0o600});
  const result=spawnSync("bash",[path.resolve(__dirname,"../../bin/drumee-ctl"),"--profile","mail","preflight","--config",config],{encoding:"utf8"});
  assert.equal(result.status,1);assert.equal(JSON.parse(result.stdout).code,"MAIL_STORAGE_GUARD_FAILED");assert.equal(fs.existsSync(cfg.service.deployment.root),false);
});
