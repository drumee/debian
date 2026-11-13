"use strict";
// This is a local OCI manifest, not a configuration ID disguised as a registry digest.
function validateFrom(source, lock) {
  const sha = /^sha256:[0-9a-f]{64}$/;
  if (lock.contract !== "drumee.mail-native-base/1" || !sha.test(lock.manifest) || !sha.test(lock.config) || lock.from !== "drumee-minimal-application-tools@" + lock.manifest || !/^moby\/buildkit@sha256:[0-9a-f]{64}$/.test(lock.buildkit)) throw Error("MAIL_NATIVE_BASE_LOCK_INVALID");
  const from = source.split("\n").filter(line => /^\s*FROM\s/i.test(line));
  if (from.length !== 1 || from[0].trim() !== "FROM " + lock.from) throw Error("MAIL_NATIVE_FROM_MISMATCH");
}
module.exports = { validateFrom };
