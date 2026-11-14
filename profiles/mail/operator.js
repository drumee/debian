#!/usr/bin/env node
"use strict";
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === "object" ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
function readPrivate(file) {
  if (typeof file !== "string" || !path.isAbsolute(file) || fs.realpathSync(file) !== file) throw Error("MAIL_PRIVATE_FILE_UNSAFE");
  const s = fs.lstatSync(file);
  if (!s.isFile() || s.nlink !== 1 || s.uid !== process.getuid() || (s.mode & 0o077)) throw Error("MAIL_PRIVATE_FILE_UNSAFE");
  return fs.readFileSync(file);
}
if (process.argv[2] === "mail") {
  const { spawnSync } = require("node:child_process");
  const args=process.argv.slice(3), i=args.includes("--help")?-1:args.findIndex(x=>x==="--password-fd"||x.startsWith("--password-fd="));
  const fd=i>=0 ? Number(args[i].includes("=")?args[i].split("=")[1]:args[i+1]) : null;
  if (i>=0 && (!Number.isInteger(fd)||fd<3||fd>128)) { console.log(JSON.stringify({contract:"drumee.mail-cli/1",ok:false,code:"MAIL_SECRET_INPUT_UNSAFE"}));process.exit(2); }
  const stdio=["inherit","inherit","inherit"];
  if(fd!==null){for(let n=3;n<=fd;n++)stdio[n]="ignore";try{fs.fstatSync(fd);stdio[fd]=fd;}catch{stdio[fd]="ignore";}}
  const result=spawnSync("/usr/bin/python3",[path.join(__dirname,"admin/main.py"),...args],{stdio,env:{PATH:"/usr/bin:/bin",LANG:"C",LC_ALL:"C",HOME:"/"}});
  process.exit(result.status??7);
}
const result=require("node:child_process").spawnSync("/usr/bin/python3",[path.join(__dirname,"admin/lifecycle.py"),...process.argv.slice(2)],{stdio:"inherit",env:{PATH:"/usr/bin:/bin",LANG:"C",LC_ALL:"C",HOME:"/"}});
process.exit(result.status??7);
