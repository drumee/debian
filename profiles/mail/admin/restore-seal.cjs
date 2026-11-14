"use strict";
// Private offline bridge. Archive verification and dedicated-mount authorization
// are prerequisites enforced by checkpoint.py; this never starts a service.
const fs=require("node:fs"),path=require("node:path"),M=require("../consumer.cjs").api();
try {
  const root=process.argv[2],checkpoint=process.argv[3],changed=new Map();
  function walk(dir){for(const name of fs.readdirSync(dir)){const file=path.join(dir,name),s=fs.lstatSync(file);if(s.isDirectory())walk(file);else if(s.isFile()&&name==="prepared.json"){const p=JSON.parse(fs.readFileSync(file));if(p.contract==="drumee.mail-prepared/1")changed.set(file,p);}}}
  walk(root+"/candidates");
  // Every immutable candidate has its own seal; aliases in journals/requests are
  // updated from that exact candidate, never synthesized from current JSON.
  const replacements=new Map();
  for(const p of changed.values())replacements.set(p.revision,M.rebindMailServiceStorage(p,{authorized:true,checkpoint}));
  function aliases(dir){for(const name of fs.readdirSync(dir)){const file=path.join(dir,name),s=fs.lstatSync(file);if(s.isDirectory())aliases(file);else if(s.isFile()&&name==="prepared.json"){const p=JSON.parse(fs.readFileSync(file));if(p.contract==="drumee.mail-prepared/1"){const next=replacements.get(p.revision);if(!next)throw Error("MAIL_PREPARED_TAMPERED");const fd=fs.openSync(file,"w",0o600);try{fs.writeFileSync(fd,JSON.stringify(next));fs.fsyncSync(fd);}finally{fs.closeSync(fd);}}}}}
  aliases(root+"/durable/operator-state");
  process.stdout.write(JSON.stringify({ok:true,candidates:replacements.size}));
}catch(e){process.stdout.write(JSON.stringify({ok:false,code:/^[A-Z0-9_]+$/.test(e.message)?e.message:"MAIL_RESTORE_SEAL_FAILED"}));process.exitCode=8;}
