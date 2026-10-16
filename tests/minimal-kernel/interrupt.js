"use strict";
// Kills only this dedicated test process after the actual canonical transaction
// has returned, before the lifecycle can acknowledge job completion.
const path = require("node:path"), profile = path.resolve(__dirname, "../../profiles/minimal-kernel");
const module_driver = require(path.join(profile, "lib/driver")), original = module_driver.createDriver;
module_driver.createDriver = options => {
  const driver = original(options);
  return { ...driver, compose(prepared, args, command_options) {
    const result = driver.compose(prepared, args, command_options);
    if (args.length === 4 && args[0] === "run" && args[3] === "initial-operator") process.kill(process.pid, "SIGKILL");
    return result;
  } };
};
require(path.join(profile, "operator")).run({ command: "install", execute: true, config: process.argv[2] }).then(() => { throw Error("INTERRUPTION_NOT_REACHED"); }).catch(() => { console.error("ISOLATED_INITIALIZATION_CHILD_FAILED"); process.exitCode = 1; });
