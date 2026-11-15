#!/bin/bash
# Container entrypoint: materialize /etc/drumee config from environment, then
# exec the service command (pm2-runtime ...). In the native channel these files
# are written by setup-infra; in containers we render them from the .env that
# config/render.mjs produced, so both channels stay configuration-equivalent.
set -euo pipefail

CRED=/etc/drumee/credential
mkdir -p "$CRED"

# --- credential files (shapes mirror target/etc/drumee/credential/*.json) ---
# Shape mirrors the real credential file: user/host/port/password, NO default
# database — Drumee uses many DBs (yellow_page + per-hub/drumate) and connects
# without a default schema. The user must be privileged (CREATE DATABASE) because
# the app provisions per-hub/drumate databases at runtime.
cat > "$CRED/db.json" <<JSON
{
  "user": "${DB_USER:-drumee-app}",
  "host": "${DB_HOST:-mariadb}",
  "port": ${DB_PORT:-3306},
  "password": "${DB_PASSWORD:-}"
}
JSON

cat > "$CRED/redis.json" <<JSON
{
  "redisHost": "${REDIS_HOST:-redis}",
  "redisPort": ${REDIS_PORT:-6379},
  "redisAuth": $( [ -n "${REDIS_PASSWORD:-}" ] && printf '"%s"' "$REDIS_PASSWORD" || printf 'null' ),
  "liveUpdateChannel": "${LIVE_UPDATE_CHANNEL:-LIVE_UPDATE_CHANNEL}"
}
JSON

# nodemailer shape: the server reads email.json.auth.{user,pass} (server-essentials
# messenger.js, otp.js). A flat shape triggers "No credenial for email. Ignored."
cat > "$CRED/email.json" <<JSON
{
  "host": "${SMTP_HOST:-}",
  "port": ${SMTP_PORT:-587},
  "secure": ${SMTP_SECURE:-false},
  "auth": {
    "user": "${SMTP_USER:-}",
    "pass": $( [ -n "${SMTP_PASSWORD:-}" ] && printf '"%s"' "$SMTP_PASSWORD" || printf 'null' )
  },
  "rejectUnauthorized": false
}
JSON

# --- runtime env sourced by the app / drumee CLI ---
cat > /etc/drumee/drumee.sh <<SH
export DRUMEE_ROOT_DIR=${DRUMEE_ROOT_DIR:-/srv/drumee}
export DRUMEE_SERVER_HOME=${DRUMEE_SERVER_HOME:-/srv/drumee/runtime/server}
export DRUMEE_UI_HOME=${DRUMEE_UI_HOME:-/srv/drumee/runtime/ui}
export DRUMEE_DATA_DIR=${DRUMEE_DATA_DIR:-/data}
export DRUMEE_SYSTEM_USER=${DRUMEE_SYSTEM_USER:-www-data}
export DRUMEE_DOMAIN_NAME=${DRUMEE_DOMAIN_NAME:-localhost}
export ADMIN_EMAIL=${ADMIN_EMAIL:-}
SH

# --- drumee.json — what server-essentials sysEnv() reads at startup ---
cat > /etc/drumee/drumee.json <<JSON
{ "domain_name": "${DRUMEE_DOMAIN_NAME:-localhost}",
  "domain_desc": "${DRUMEE_DESCRIPTION:-Drumee}",
  "data_dir": "${DRUMEE_DATA_DIR:-/data}",
  "db_user": "${DB_USER:-drumee-app}",
  "system_user": "www-data", "system_group": "www-data",
  "drumee_root": "/srv/drumee", "cache_dir": "/srv/drumee/cache",
  "credential_dir": "/etc/drumee/credential" }
JSON

# --- conf.d/* — app config the server loads via --conf-path (APP_CONF_DIR).
# Natively produced by the infra package; rendered here for the container. ---
CONFD=/etc/drumee/conf.d
mkdir -p "$CONFD"
cat > "$CONFD/drumee.json" <<JSON
{ "arch": "pod", "sys_languages": ["en","fr","km","ru","zh"], "forceDefaultLanguage": true, "quota": { "watermark": "Infinity" } }
JSON
cat > "$CONFD/myDrumee.json" <<JSON
{ "arch": "single", "sys_languages": ["en","fr","km","ru","zh"],
  "conference": { "hosts": { "domain": "", "muc": "" }, "bosh": "" } }
JSON
cat > "$CONFD/exchange.json" <<JSON
{ "export_dir": "${EXCHANGE_LOCATION:-/exchangearea}", "import_dir": "${EXCHANGE_LOCATION:-/exchangearea}" }
JSON

chmod 600 "$CRED"/*.json 2>/dev/null || true
exec "$@"
