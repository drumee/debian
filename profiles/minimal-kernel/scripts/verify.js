"use strict";
const fs = require("node:fs"), path = require("node:path");
const { validate, digest } = require("./alignment");
const root = path.resolve(__dirname, "..");
function verify() {
  const alignment = require("../dependency-alignment.json");
  const result = validate(alignment);
  for (const entry of alignment.sources.files) {
    const file = path.join(root, "vendor", entry.path), stat = fs.lstatSync(file);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || digest(fs.readFileSync(file)) !== entry.sha256) throw Error("SOURCE_INTEGRITY_MISMATCH");
  }
  const runtime = require("@drumee/server-runtime");
  if (runtime.PLATFORM_ADMINISTRATOR?.remit !== 15 || runtime.PLATFORM_AUTHORITY_SCHEMA_VERSION !== "kb01a-platform-authority-1") throw Error("RUNTIME_AUTHORITY_MISSING");
  const operator = require("../vendor/operator-bootstrap/lib");
  for (const name of ["installOperatorSchema", "enrollInitialOperator", "validateInitialOperator", "createFileCredentialProvider", "promptPassword"]) if (typeof operator[name] !== "function") throw Error("OPERATOR_API_MISSING");
  const lifecycle = require("@drumee/infra-layer/lifecycle");
  for (const name of ["composeDeployment", "activateDeployment", "backupDeployment", "restoreDeployment"]) if (typeof lifecycle[name] !== "function") throw Error("INFRASTRUCTURE_LIFECYCLE_MISSING");
  const manifest = require("../vendor/operator-bootstrap/schemas/SCHEMA_MANIFEST.json");
  if (manifest.schemaVersion !== alignment.operator.schema) throw Error("OPERATOR_SCHEMA_MISMATCH");
  return result;
}
if (require.main === module) { try { console.log(JSON.stringify(verify())); } catch (error) { console.error(error.code || error.message); process.exitCode = 1; } }
module.exports = { verify };
