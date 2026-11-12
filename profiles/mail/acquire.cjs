"use strict";
// Explicit local qualification acquisition; no publication or registry fallback.
const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto"), { execFileSync } = require("node:child_process");
const receipt = require("./infra-source-lock.json"), archive = path.resolve(process.argv[2]);
const data = fs.readFileSync(archive);
if (crypto.createHash("sha256").update(data).digest("hex") !== receipt.sha256 || "sha512-" + crypto.createHash("sha512").update(data).digest("base64") !== receipt.integrity) throw Error("MAIL_ARCHIVE_INTEGRITY_MISMATCH");
const consumer = path.join(__dirname, ".cache/consumer"); fs.mkdirSync(consumer, { recursive: true, mode: 0o700 });
fs.writeFileSync(path.join(consumer, "package.json"), JSON.stringify({ private: true, dependencies: { "@drumee/infra-layer": "file:" + archive } }), { mode: 0o600 });
execFileSync("npm", ["install", "--ignore-scripts", "--no-audit", "--no-fund"], { cwd: consumer, stdio: "pipe" });
const installed = path.join(consumer, "node_modules/@drumee/infra-layer");
require("./consumer.cjs").verify(installed, receipt);
console.log(JSON.stringify({ acquired: true, source: receipt.revision, sha256: receipt.sha256, published: false }));
