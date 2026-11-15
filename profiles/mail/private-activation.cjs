"use strict";
const fs = require("node:fs"), crypto = require("node:crypto"), path = require("node:path");
function read(cfg) {
  if (!cfg.private_activation) return undefined;
  if (cfg.acceptance || cfg.acceptance_private_listener) throw Error("MAIL_PRIVATE_APPROVAL_MISMATCH");
  const ref = cfg.private_activation;
  if (Object.keys(ref).sort().join(",") !== "file,sha256" || !/^[a-f0-9]{64}$/.test(ref.sha256) || !path.isAbsolute(ref.file) || fs.realpathSync(ref.file) !== ref.file) throw Error("MAIL_PRIVATE_APPROVAL_INVALID");
  const fd = fs.openSync(ref.file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  try {
    const st = fs.fstatSync(fd);
    if (!st.isFile() || st.nlink !== 1 || st.uid !== 0 || (st.mode & 0o222) || st.size > 65536) throw Error("MAIL_PRIVATE_APPROVAL_UNSAFE");
    const bytes = fs.readFileSync(fd);
    if (crypto.createHash("sha256").update(bytes).digest("hex") !== ref.sha256) throw Error("MAIL_PRIVATE_APPROVAL_MISMATCH");
    return JSON.parse(bytes);
  } finally { fs.closeSync(fd); }
}
module.exports = { read };
