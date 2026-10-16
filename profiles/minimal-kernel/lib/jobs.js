"use strict";
// Canonical package jobs only. Identity/credential SQL stays in the control plane.
const fs = require("node:fs"), path = require("node:path");
const { connect, manifestEntries, fail } = require("./database");
const { runtime, platform, operator, system_mfs, components } = require("./components");
function intent(database) {
  let value; try { value = JSON.parse(process.env.DRUMEE_OPERATOR_INTENT); } catch (_) { fail("OPERATOR_INTENT_REQUIRED"); }
  return { contract_version: 1, database, platform, domain: value.domain, organisation_id: 1, operation_id: value.operation_id,
    identity: { username: value.username, email: value.email }, authorization: { authorized: true, scope: "initial-operator", operation_id: value.operation_id, domain: value.domain, organisation_id: 1 }, mode: value.mode };
}
async function run(job, mode) {
  if (!["install", "validate"].includes(mode)) fail("INITIALIZATION_OPERATION_INVALID");
  const db = await connect(), options = intent(db);
  try {
    const runtime_root = path.dirname(require.resolve("@drumee/server-runtime/package.json"));
    if (job === "intrinsic") {
      if (mode === "install") for (const entry of manifestEntries(runtime_root).filter(value => value.order < 30)) await db.executeScript(fs.readFileSync(entry.file, "utf8"));
      const manifest = JSON.parse(fs.readFileSync(path.join(runtime_root, "schemas/SCHEMA_MANIFEST.json"), "utf8"));
      const tables = await db.query("SELECT table_name FROM information_schema.tables WHERE table_schema=DATABASE()");
      const routines = await db.query("SELECT routine_name FROM information_schema.routines WHERE routine_schema=DATABASE()");
      if (manifest.objects.tables.some(name => !tables.some(row => row.table_name === name)) || [...manifest.objects.functions, ...manifest.objects.procedures].filter(name => name !== "get_remit").some(name => !routines.some(row => row.routine_name === name))) fail("INTRINSIC_SCHEMA_INVALID");
    } else if (job === "platform") {
      if (mode === "install") await platform.bootstrap({ database: db, domain: options.domain });
      if (!(await platform.validate({ database: db, domain: options.domain })).valid) fail("PLATFORM_NOT_READY");
    } else if (job === "authority") {
      if (mode === "install") for (const entry of manifestEntries(runtime_root).filter(value => value.order === 30)) await db.executeScript(fs.readFileSync(entry.file, "utf8"));
      if (!(await runtime.validatePlatformAuthority({ database: db })).valid) fail("PLATFORM_AUTHORITY_INVALID");
    } else if (job === "operator-schema") {
      if (mode === "install") await operator.installOperatorSchema(options);
      await require("../vendor/operator-bootstrap/lib/store").validateSchema(require("../vendor/operator-bootstrap/lib/store").store(db));
    } else if (job === "kernel-schema") {
      const { hub_store, mfs_store } = components(db);
      if (mode === "install") { await hub_store.install(); await system_mfs.install({ store: mfs_store }); }
      if (!(await system_mfs.validateInstallation({ store: mfs_store })).valid) fail("SYSTEM_MFS_SCHEMA_INVALID");
      if (!(await db.query("SELECT table_name FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='hub_lifecycle'")).length) fail("HUB_SCHEMA_INVALID");
    } else if (job === "enroll") {
      const file = "/operator-state/credential.json";
      if (options.mode === "test" && process.env.DRUMEE_ACCEPTANCE !== "true") fail("TEST_ENROLLMENT_FORBIDDEN");
      {
        if (mode === "install") {
          await operator.enrollInitialOperator({ ...options, credential_provider: operator.createFileCredentialProvider({ mode: options.mode, file }) });
        }
        const report = await operator.validateInitialOperator(options);
        if (!report.valid) fail(report.diagnostic_codes[0]);
        // Replay validates the existing resource too; it never creates one.
        const material = await operator.createFileCredentialProvider({ mode: options.mode, file }).prepare({ contract_version: 1, domain: options.domain, organisation_id: 1, operation_id: options.operation_id, identity: options.identity }, { allow_create: false });
        material.password.fill(0);
      }
    } else if (job === "authenticate") {
      const material = operator.retrieveInitialCredential({ file: "/operator-state/credential.json", authorization: { authorized: true, scope: "retrieve-initial-credential", operation_id: options.operation_id } });
      try {
        const { sessions, yellow_page } = components(db), session = await sessions.fromRequest({ headers: {} });
        await session.signin({ uid: material.username, password: material.password.toString("utf8") });
        if (!(await new runtime.PlatformAuthorizer({ store: yellow_page }).authorize({ session, permission: { scope: "platform", src: "PLATFORM_ADMINISTRATOR" } })).granted) fail("INITIAL_OPERATOR_AUTHENTICATION_FAILED");
      } finally { material.password.fill(0); }
    } else fail("INITIALIZATION_JOB_UNKNOWN");
    return { valid: true, code: "INITIALIZATION_JOB_VALID", job };
  } finally { await db.close(); }
}
if (require.main === module) run(...process.argv.slice(2)).then(value => console.log(JSON.stringify(value))).catch(error => { console.error(JSON.stringify({ valid: false, code: /^[A-Z0-9_]+$/.test(error.code || "") ? error.code : "INITIALIZATION_JOB_FAILED" })); process.exitCode = 1; });
module.exports = { run, intent };
