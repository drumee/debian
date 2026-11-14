"use strict";
// Private orchestration bridge. stdout is captured by the authority, never relayed.
const fs=require("node:fs"),path=require("node:path"),crypto=require("node:crypto"),{spawnSync}=require("node:child_process");
const M=require("../consumer.cjs").api(),cfg=require("../config.cjs").validate(JSON.parse(fs.readFileSync(process.argv[3])));
const root=cfg.service.deployment.root;
function read(file){const s=fs.lstatSync(file);if(!s.isFile()||s.isSymbolicLink()||s.nlink!==1||s.uid!==process.getuid()||(s.mode&0o077))throw Error("MAIL_STORAGE_UNSAFE");return JSON.parse(fs.readFileSync(file));}
const canonical=v=>Array.isArray(v)?v.map(canonical):v&&typeof v==="object"?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])])):v;
function prepared(){const p=read(root+"/durable/operator-state/prepared.json");const owner=read(root+"/owner.json");if(p.transport_digest!==crypto.createHash("sha256").update(JSON.stringify(canonical(cfg.service))).digest("hex")||p.root!==root||p.project!==cfg.service.deployment.project||owner.id!==cfg.service.deployment.id||owner.uid!==process.getuid()||owner.gid!==process.getgid())throw Error("MAIL_RESOURCE_IDENTITY_MISMATCH");return p;}
try{
 const action=process.argv[2];prepared();let result;
 if(action==="identity")result={bound:true};
 else if(action==="snapshot")result=M.verifyMailCredentials(prepared(),read(cfg.verifiers_file),{authorized:true});
 else if(action==="inspect"){M.operateMailService(prepared(),"preflight",{authorized:true});result=M.validateRegistry(read(root+"/durable/registry/public/current.json"),cfg.service);}
 else if(action==="prepare"){
  const input=JSON.parse(fs.readFileSync(0));const plan=M.planMailService(cfg.service,{registry:input.registry,secret_sources:cfg.secret_sources});const p=M.prepareMailService(plan,{authorized:true,acceptance:cfg.acceptance,private_bind:cfg.acceptance_private_listener===true,verifiers:read(input.verifiers)});
  if(fs.existsSync(input.output)&&JSON.stringify(read(input.output))!==JSON.stringify(p))throw Error("MAIL_RESOURCE_IDENTITY_MISMATCH");
  const fd=fs.openSync(input.output,"w",0o600);try{fs.writeFileSync(fd,JSON.stringify(p));fs.fsyncSync(fd);}finally{fs.closeSync(fd);}const d=fs.openSync(path.dirname(input.output),"r");try{fs.fsyncSync(d);}finally{fs.closeSync(d);}result={revision:p.revision};
 }else if(action==="resume-runtime"){const input=JSON.parse(fs.readFileSync(0));result=M.operateMailService(prepared(),"start",{authorized:true,acceptance:cfg.acceptance,recovery_target:read(input.prepared)});}
 else if(action==="apply"||action==="barrier"){const input=JSON.parse(fs.readFileSync(0));result=M[action==="barrier"?"stageMailRegistryBarrier":"activateMailRegistry"](read(input.prepared),{authorized:true,expected_generation:input.previous});}
 else if(action==="usage"){const input=JSON.parse(fs.readFileSync(0));result=M.observeMailMailbox(prepared(),input.id,{authorized:true});}
 else if(action==="observe")result=M.observeMailService(prepared(),{authorized:true,...cfg.monitoring});
 else if(action==="hash"){
  const image=cfg.service.deployment.images.dovecot.split("@").at(-1);if(!/^sha256:[0-9a-f]{64}$/.test(image))throw Error("MAIL_RESOURCE_IDENTITY_MISMATCH");const password=fs.readFileSync(0);const r=spawnSync("/usr/bin/docker",["--host","unix:///var/run/docker.sock","run","--rm","-i","--network","none","--read-only","--tmpfs","/tmp:rw,noexec,nosuid,size=16777216,mode=1777","--cap-drop","ALL","--security-opt","no-new-privileges:true","--memory","134217728","--cpus","1","--pids-limit","32","--user",cfg.service.deployment.owner_uid+":"+cfg.service.deployment.owner_gid,"--entrypoint","doveadm",image,"pw","-s","ARGON2ID"],{input:Buffer.concat([password,Buffer.from("\n"),password,Buffer.from("\n")]),env:{PATH:"/usr/bin:/bin",HOME:"/",DOCKER_CONFIG:"/etc/docker",LANG:"C"},maxBuffer:8192,timeout:30000});password.fill(0);if(r.status!==0)throw Error("MAIL_DEPENDENCY_UNAVAILABLE");const v=r.stdout.toString().trim(),m=v.match(/^\{ARGON2ID\}\$argon2id\$v=19\$m=(\d+),t=(\d+),p=(\d+)\$/);if(!m||+m[1]<65536||+m[2]<3||+m[3]!==1)throw Error("MAIL_DEPENDENCY_UNAVAILABLE");result={verifier:v};
 }else throw Error("MAIL_USAGE");
 process.stdout.write(JSON.stringify({ok:true,data:result}));
}catch(e){process.stdout.write(JSON.stringify({ok:false,code:/^[A-Z0-9_]+$/.test(e.code||e.message)?e.code||e.message:"MAIL_DEPENDENCY_UNAVAILABLE"}));process.exitCode=1;}
