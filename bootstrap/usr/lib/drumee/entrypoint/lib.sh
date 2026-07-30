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
  [ -f /etc/drumee/drumee.sh ] && . /etc/drumee/drumee.sh
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

# Writes the JSON credential files the application reads. Only roles that talk to
# the database call this: the media role deliberately gets none (§2).
drumee_write_credentials() {
  mkdir -p "$CRED"
  cat > "$CRED/db.json" <<JSON
{
  "user": "${DB_USER:-drumee-app}",
  "host": "${DB_HOST:-drumee-db}",
  "port": ${DB_PORT:-3306},
  "password": "${DB_PASSWORD:-}"
}
JSON
  cat > "$CRED/redis.json" <<JSON
{
  "redisHost": "${REDIS_HOST:-drumee-cache}",
  "redisPort": ${REDIS_PORT:-6379},
  "redisAuth": $( [ -n "${REDIS_PASSWORD:-}" ] && printf '"%s"' "$REDIS_PASSWORD" || printf 'null' ),
  "liveUpdateChannel": "${LIVE_UPDATE_CHANNEL:-LIVE_UPDATE_CHANNEL}"
}
JSON
  chmod 0640 "$CRED/db.json" "$CRED/redis.json"
  echo "[drumee] credentials written to $CRED"
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
