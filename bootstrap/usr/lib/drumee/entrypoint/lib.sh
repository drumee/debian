#!/bin/sh
# Shared by every role entrypoint. Sourced, not executed.
#
# Provisioning credentials from environment variables belongs here rather than in
# each image: it was duplicated across the old entrypoint scripts, and a copy that
# drifts writes a config the application reads without anyone noticing.
set -eu

CRED=/etc/drumee/credential

drumee_env() {
  # /etc/drumee/drumee.sh is written by the infra role; absent on a fresh stack,
  # which is not an error — the variables then come from the container env.
  #
  # Sourced with `set -u` OFF and restored afterwards. That file is generated per
  # deployment and legitimately references variables it does not define — OWN_CERTS_DIR
  # among them — so under `set -u` sourcing it aborts the entrypoint with
  # "OWN_CERTS_DIR: parameter not set" and the role crash-loops before it starts
  # anything. Measured on the web role against a real rendered tree; the same trap has
  # already bitten the native install harness for the same reason.
  if [ -f /etc/drumee/drumee.sh ]; then
    set +u
    . /etc/drumee/drumee.sh
    set -u
  fi
  :
}

drumee_release() {
  # Shipped by drumee-release, the anchor every role depends on at an exact
  # version. If it is missing, the image was not built from a role metapackage.
  if [ -f /usr/share/drumee/release ]; then
    . /usr/share/drumee/release
    echo "[drumee] release ${DRUMEE_RELEASE:-?} channel ${DRUMEE_CHANNEL:-?}"
  else
    echo "[drumee] WARNING: /usr/share/drumee/release is missing — not a role image?" >&2
  fi
}

# Credentials are READ here, never written.
#
# This used to write db.json and redis.json from the environment, in both the app and the
# schemas role — which made two writers for one file and, worse, meant the copy the infra
# render produced was never the one in use. The compose topology hid the consequence: the
# roles mounted a separate writable volume over /etc/drumee/credential, and a mount
# replaces what is underneath it, so email.json and postfix.json — rendered, correct, and
# never overwritten by anyone — were simply invisible to the application. Verified with a
# two-volume mount test, not deduced.
#
# One writer now: the infra job seeds db.json before the render (so infra.js keeps that
# password through existingCredential) and writes redis.json after it. Every other role
# reads the shared volume. So this checks, and fails loudly and specifically, because a
# missing credential otherwise surfaces as an access-denied from MariaDB with no hint
# about which file was absent.
drumee_require_credentials() {
  local missing=""
  for f in "$@"; do
    [ -s "$CRED/$f" ] || missing="$missing $f"
  done
  if [ -n "$missing" ]; then
    echo "[drumee] missing credential(s) in $CRED:$missing" >&2
    echo "[drumee] they are produced by the infra role — has infra-init run against" >&2
    echo "[drumee] this deployment's configuration volume?" >&2
    exit 1
  fi
  echo "[drumee] credentials present: $*"
}

# A role must refuse to run against a schema older than its code expects (§6).
# The comparison itself lands with the migrate job in increment 6; this is the
# single place it will be wired, so no role grows its own copy.
drumee_require_schema() {
  if [ -n "${DRUMEE_REQUIRE_SCHEMA:-}" ]; then
    echo "[drumee] schema floor ${DRUMEE_REQUIRE_SCHEMA} requested" >&2
    echo "[drumee] NOT IMPLEMENTED: schema_migrations check lands with the migrate job" >&2
  fi
  :
}

die() { echo "[drumee] $*" >&2; exit 1; }
