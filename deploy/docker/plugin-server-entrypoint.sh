#!/bin/bash
# Run-once publisher for a Drumee backend plugin (see Dockerfile.plugin-server).
#
# Reconstructs, for the container channel, what `drumee-server-plugin add` + a
# schema patch do natively:
#   1. publish the plugin tree into the shared `plugins` volume
#   2. load its SQL schema into the hub template + every entity DB (so the
#      plugin's tables/procedures exist in whatever app_db a request resolves to)
#   3. register the plugin dir in /etc/drumee/conf.d/plugins/<endpoint>.json,
#      which Acl.loadPlugins() reads at server-pod startup
#
# Idempotent: skips if already registered (set FORCE=1 to re-run).
#
# Env (from the rendered .env): DB_HOST DB_PORT DB_ROOT_PASSWORD
#      PLUGIN_NAME (required) PLUGIN_ENDPOINT (default main)
set -euo pipefail

NAME="${PLUGIN_NAME:?PLUGIN_NAME is required}"
ENDPOINT="${PLUGIN_ENDPOINT:-main}"
DB_HOST="${DB_HOST:-mariadb}"
DB_PORT="${DB_PORT:-3306}"
ROOT_PW="${DB_ROOT_PASSWORD:?DB_ROOT_PASSWORD is required}"

PLUGROOT="/srv/drumee/runtime/plugins/server/${ENDPOINT}"
DEST="${PLUGROOT}/${NAME}"
CONFD="/etc/drumee/conf.d/plugins"
REG="${CONFD}/${ENDPOINT}.json"

root() { mariadb --host="$DB_HOST" --port="$DB_PORT" -uroot -p"$ROOT_PW" "$@"; }

echo "==> [plugin:${NAME}] waiting for MariaDB at ${DB_HOST}:${DB_PORT}"
for _ in $(seq 1 60); do root -e 'SELECT 1' >/dev/null 2>&1 && break; sleep 2; done
root -e 'SELECT 1' >/dev/null 2>&1 || { echo "MariaDB not reachable" >&2; exit 1; }

mkdir -p "$CONFD" "$PLUGROOT"

# Idempotency: registered already + not forced -> nothing to do.
if [ -f "$REG" ] && grep -q "\"${DEST}\"" "$REG" && [ "${FORCE:-0}" != "1" ]; then
  echo "==> [plugin:${NAME}] already registered in ${REG} — skipping (FORCE=1 to redo)"
  exit 0
fi

# 1. publish the plugin tree (its own node_modules ship with it).
echo "==> [plugin:${NAME}] publishing -> ${DEST}"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -a /payload/. "$DEST/"
chmod -R a+rX "$PLUGROOT"

# 2. load the plugin schema into the hub template + every entity DB. The plugin's
#    tables/procedures are not DB-qualified and run in whatever app_db a request
#    resolves to (per hub/drumate DB), so they must exist everywhere a request
#    might land. System DBs are skipped.
if [ -d "${DEST}/schemas" ]; then
  DBS=$(root -N -e "SHOW DATABASES" | grep -vxF \
    -e information_schema -e mysql -e performance_schema -e sys \
    -e yp -e utils -e mailserver -e trash || true)
  files=$(ls "${DEST}"/schemas/tables/*.sql "${DEST}"/schemas/procedures/*.sql 2>/dev/null || true)
  if [ -n "$files" ]; then
    n=0
    for db in $DBS; do
      for f in $files; do
        root --force "$db" < "$f" 2>/dev/null || true
      done
      n=$((n+1))
    done
    echo "==> [plugin:${NAME}] schema loaded into ${n} databases"
  fi
fi

# 3. register the plugin dir so Acl.loadPlugins() picks it up. The registry shape
#    matches what drumee-server-plugin writes: { "acl": ["/abs/plugin/dir", ...] }.
node -e '
  const fs = require("fs");
  const [file, dir] = process.argv.slice(1);
  let reg = { acl: [] };
  try { reg = JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) {}
  if (!Array.isArray(reg.acl)) reg.acl = [];
  if (!reg.acl.includes(dir)) reg.acl.push(dir);
  fs.writeFileSync(file, JSON.stringify(reg, null, 2));
' "$REG" "$DEST"
echo "==> [plugin:${NAME}] registered in ${REG}"
echo "==> [plugin:${NAME}] done"
