"use strict";
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto"), { execFileSync } = require("node:child_process");
const baseLock = require("./native/base-image-lock.json");
const base = baseLock.config;
require("./native/base-input.cjs").validateFrom(fs.readFileSync(path.join(__dirname,"Dockerfile.native"),"utf8"),baseLock);
const expected = "sha256:a02cc47d0ebca12a55759edb00757b3a8cdd00112ad4afe9a4ff7b5337ffe843";
const command = args => execFileSync("/usr/bin/docker", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
const hash = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
if (command(["image", "inspect", base, "--format", "{{.Id}}"] ).trim() !== expected) throw Error("MAIL_NATIVE_BASE_IDENTITY_MISMATCH");
const cache=path.join(__dirname,".cache");fs.mkdirSync(cache,{recursive:true,mode:0o700});
const lock=require("./native/source-lock.json"), reference=path.join(cache,"dovecot-reference");
if(!fs.existsSync(reference)) {
 execFileSync("git",["init",reference],{stdio:"pipe"});
 execFileSync("git",["-C",reference,"fetch","--depth=1",lock.repository,lock.commit],{stdio:"pipe"});
}
const build=fs.mkdtempSync(path.join(cache,"quota-build-"));
for(const [file,digest] of Object.entries(lock.files)) {
 const bytes=execFileSync("git",["-C",reference,"show",lock.commit+":src/plugins/quota/"+file]);
 if(hash(bytes)!==digest)throw Error("MAIL_NATIVE_SOURCE_MISMATCH");fs.writeFileSync(path.join(build,file),bytes);
}
execFileSync("python3",[path.join(__dirname,"native/apply-quota.py"),build],{stdio:"pipe"});
fs.copyFileSync(path.join(__dirname,"native/atomic-quota.c"),path.join(build,"atomic-quota.c"));
const name="mail02-compiler-"+crypto.randomBytes(6).toString("hex"), moduleFile=path.join(build,"lib10_quota_plugin.so");
try {
 command(["run","-d","--name",name,"--entrypoint","/bin/sleep",expected,"infinity"]);
 command(["exec",name,"sh","-ec","apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev dovecot-dev=1:2.4.1+dfsg1-6+deb13u7 libtirpc-dev rpcsvc-proto"]);
 command(["cp",build+"/.",name+":/tmp/quota"]);
 command(["exec",name,"sh","-ec",'cd /tmp/quota; rpcgen -h rquota.x > rquota.h; rpcgen -c rquota.x > rquota_xdr.c; gcc -shared -fPIC -DHAVE_CONFIG_H -I/usr/include/dovecot -I/usr/include/tirpc quota.c quota-count.c quota-fs.c quota-imapc.c quota-maildir.c quota-plugin.c quota-settings.c quota-storage.c quota-util.c rquota_xdr.c atomic-quota.c -o lib10_quota_plugin.so -ltirpc']);
 command(["cp",name+":/tmp/quota/lib10_quota_plugin.so",moduleFile]);
} finally { command(["rm","-f",name]); }
const tag="drumee-mail:mail02-atomic-local";
const layout=fs.mkdtempSync(path.join(cache,"base-layout-")), archive=path.join(layout,"base.tar");
command(["save",baseLock.config,"-o",archive]);
const oci=path.join(layout,"oci");
execFileSync("python3",[path.join(__dirname,"native/oci-base.py"),"prepare",archive,oci,path.join(__dirname,"native/base-image-lock.json")],{stdio:"pipe"});
const builder="mail02-native-"+crypto.randomBytes(6).toString("hex");
try {
 command(["buildx","create","--name",builder,"--driver","docker-container","--driver-opt","image="+baseLock.buildkit]);
 command(["buildx","build","--builder",builder,"--build-context",baseLock.from+"=oci-layout://"+oci+"@"+baseLock.manifest,"--load","--build-arg","ATOMIC_QUOTA_MODULE="+path.relative(__dirname,moduleFile),"-t",tag,"-f",path.join(__dirname,"Dockerfile.native"),__dirname]);
} finally { command(["buildx","rm",builder]); }
const id=command(["image","inspect",tag,"--format","{{.Id}}"] ).trim();
const receipt={image:id,base:expected,base_manifest:baseLock.manifest,base_context:baseLock.from,buildkit:baseLock.buildkit,upstream:lock.commit,source_files:lock.files,module_sha256:hash(fs.readFileSync(moduleFile)),patch_sha256:hash(fs.readFileSync(path.join(__dirname,"native/apply-quota.py"))),atomic_source_sha256:hash(fs.readFileSync(path.join(__dirname,"native/atomic-quota.c"))),published:false};
fs.writeFileSync(path.join(cache,"native-image.json"),JSON.stringify(receipt,null,2),{mode:0o600});console.log(JSON.stringify(receipt));
