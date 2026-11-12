"use strict";
// Qualification-only driver; administrative mailbox/password verbs remain MAIL-03.
const fs = require("node:fs"), path = require("node:path");
try {
  const cfg = JSON.parse(fs.readFileSync(process.argv[3])), M = require("../../profiles/mail/consumer.cjs").api();
  const prepared = JSON.parse(fs.readFileSync(path.join(cfg.service.deployment.root, "durable/operator-state/prepared.json")));
  const input = process.argv[4] ? JSON.parse(fs.readFileSync(process.argv[4])) : {};
  let result;
  if (process.argv[2] === "rotate") result = M.rotateMailTLS(prepared, input, { authorized: true });
  else if (process.argv[2] === "reconcile") result = M.reconcileMailTLS(prepared, { authorized: true });
  else if (process.argv[2] === "observe") result = M.observeMailService(prepared, { authorized: true, ...cfg.monitoring });
  else if (process.argv[2] === "prepare") {
    const plan = M.planMailService(cfg.service, { registry: JSON.parse(fs.readFileSync(cfg.registry_file)), secret_sources: cfg.secret_sources });
    result = M.prepareMailService(plan, { authorized: true, acceptance: true, private_bind: cfg.acceptance_private_listener === true, verifiers: JSON.parse(fs.readFileSync(cfg.verifiers_file)) });
    result = { prepared: true, revision: result.revision };
  } else if (process.argv[2] === "registry") {
    const previous = JSON.parse(fs.readFileSync(path.join(cfg.service.deployment.root, "durable/registry/public/current.json")));
    const plan = M.planMailService(cfg.service, { registry: input, secret_sources: cfg.secret_sources });
    const target = M.prepareMailService(plan, { authorized: true, acceptance: true, private_bind: cfg.acceptance_private_listener === true, verifiers: JSON.parse(fs.readFileSync(cfg.verifiers_file)) });
    result = M.activateMailRegistry(target, { authorized: true, expected_generation: previous.generation });
  } else throw Error("MAIL_TEST_OPERATION_INVALID");
  console.log(JSON.stringify(result));
} catch (error) {
  console.log(JSON.stringify({ ok: false, code: /^[A-Z0-9_]+$/.test(error.code || error.message) ? error.code || error.message : "MAIL_TEST_OPERATION_FAILED" })); process.exitCode = 1;
}
