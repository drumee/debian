"use strict";
// Debian SQL authorization boundary. Infra Layer owns accounts/secrets/lifecycle.
const fs = require("node:fs"), path = require("node:path");
const { spawnSync } = require("node:child_process");
const D = require("@drumee/infra-layer/lifecycle/docker");
const { grants } = require("./sql-policy");
const { fail } = require("./config");
function query(prepared, sql) {
  const owned = D.inspectProject(prepared.project, Object.keys(prepared.compose.services));
  if (!owned.some(value => value.service === "database" && value.running && value.revision === prepared.revision)) fail("OWNED_DATABASE_REQUIRED");
  return D.compose(prepared, ["exec", "-T", "database", "/bin/sh", "-c", 'MYSQL_PWD="$(cat /run/secrets/database-admin)" exec mariadb --protocol=socket -uroot --batch --skip-column-names'], { input: sql, encoding: "utf8" });
}
function createDriver({ password_fd } = {}) {
  return { ...D, compose(prepared, args, options) {
    const job = args[0] === "run" && args.length === 4 && args[1] === "--rm" && args[2] === "--no-deps" && prepared.composition.distribution.init_jobs.find(value => value.id === args[3]);
    if (job) {
      const tables = query(prepared, "SELECT table_name FROM information_schema.tables WHERE table_schema='yp';").trim().split("\n").filter(Boolean);
      query(prepared, grants(job.id, tables));
      const intent = JSON.parse(job.environment.DRUMEE_OPERATOR_INTENT);
      if (job.id === "initial-operator" && intent.mode === "interactive" && !fs.existsSync(path.join(prepared.root, "durable/operator-state/credential.json"))) {
        // Never prepare replacement material for an already committed identity.
        if (query(prepared, "SELECT uid IS NOT NULL FROM yp.initial_operator_enrollment WHERE singleton=1;").trim() !== "0") fail("OPERATOR_CREDENTIAL_RESOURCE_MISSING");
        if (password_fd === undefined && (!process.stdin.isTTY || !process.stderr.isTTY)) fail("OPERATOR_SECURE_INPUT_REQUIRED");
        const result = spawnSync(process.execPath, [path.join(__dirname, "../scripts/acquire.js"), path.join(prepared.root, "durable/operator-state/credential.json"), ...(password_fd === undefined ? [] : ["--descriptor"])], { env: { ...process.env, DRUMEE_OPERATOR_INTENT: job.environment.DRUMEE_OPERATOR_INTENT }, stdio: ["inherit", "inherit", "inherit", ...(password_fd === undefined ? [] : [password_fd])] });
        if (result.error || result.status !== 0) fail("OPERATOR_SECURE_INPUT_FAILED");
      }
    }
    return D.compose(prepared, args, job ? { ...options, stdio: ["pipe", "pipe", "inherit"] } : options);
  } };
}
module.exports = { createDriver, query };
