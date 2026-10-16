"use strict";
// Secure host-to-job bridge, invoked at the enrollment lifecycle boundary.
const { operator } = require("../lib/components");
async function acquire() {
  const value = JSON.parse(process.env.DRUMEE_OPERATOR_INTENT);
  const intent = { contract_version: 1, domain: value.domain, organisation_id: 1, operation_id: value.operation_id, identity: { username: value.username, email: value.email } };
  const provider = operator.createFileCredentialProvider({ mode: "interactive", file: process.argv[2], ...(process.argv[3] === "--descriptor" ? { password_fd: 3 } : {}) });
  const material = await provider.prepare(intent); material.password.fill(0);
}
acquire().catch(error => { console.error(/^[A-Z0-9_]+$/.test(error.code || "") ? error.code : "OPERATOR_SECURE_INPUT_FAILED"); process.exitCode = 1; });
