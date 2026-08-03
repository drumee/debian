#!/bin/bash
# Seed builder — produces schemas' var/tmp/drumee/seeds.tgz (a mariabackup
# physical snapshot) entirely offline, inside one throwaway container.
#
# This is the containerised rework of schemas/make-seed.sh point #3. The flow the
# native .deb build expects:
#   1. a local MariaDB (started here) with the base databases loaded from the
#      schemas repo's templates/factory/seed/*.sql,
#   2. a mariabackup --backup + --prepare, tar'd in the exact layout that
#      setup-schemas/bin/install consumes (tar --one-top-level=seeds ->
#      mariabackup --copy-back --target-dir=.../seeds).
#
# Step 1 REUSES the proven container asset verbatim (schemas-init.sh) — just
# pointed at a local loopback MariaDB instead of the compose 'mariadb' service.
# Step 2 mirrors schemas/src/schemas/bin/build-seeds.
#
# THE SEED CARRIES NO ENTITIES. It used to also run container-populate.js here,
# which stocked the factory pool and created the fixed system accounts, on the
# reasoning that a seed shipping an empty pool would trip the postinst
# EMPTY_FACTORY guard. That produced a seed describing *this container* rather
# than *a Drumee*, and it broke installs in two ways, both measured on a
# from-scratch native box:
#
#   - Every entity it stocked carried an absolute home_dir built from this
#     container's DRUMEE_DATA_DIR (/data). A native install whose data_dir is
#     /srv/data allocated users straight out of that pool, so the admin account
#     and several hubs landed under /data/mfs — which nginx does not serve
#     (`alias /srv/data/mfs/`). 20 of 115 entities were on the wrong root.
#   - `nobody` is the one account with a FIXED id (ID_NOBODY,
#     'ffffffffffffffff'). The seed already held that row, so the target host's
#     populate.js -> createNobody -> updateEntries hit ER_DUP_ENTRY on all six
#     of its UPDATEs, every install. `nobody` kept the seed's dead
#     /data/mfs home_dir and the pool entity drawn for it was stranded. Guest
#     and system don't force an id, so instead of failing they silently
#     duplicated: guest+guest1, system+system1.
#
# The EMPTY_FACTORY premise no longer holds either: setup-schemas'
# populate.js:stockFactory tops the pool up on the TARGET host (idempotent, to
# POOL_COUNT), and schemas' postinst runs bin/install before it counts the pool,
# so the guard sees a stocked pool. Stocking on the target is also the only way
# to get correct paths, since only the target knows its own data_dir.
#
# Keep it this way: anything host-specific written here ships to every install.
# schemas' bin/make-templates asserts the same property for the templates that
# feed step 1.
#
# Source trees are bind-mounted read-only (see scripts/build-seed.sh):
#   /src/schemas       schemas      (templates/factory + schema/patch corpus)
#   /out               host output directory (seeds.tgz lands here)
#
# server-team and setup-schemas used to be mounted here too, purely to run
# container-populate.js. Dropping that step drops them, and with them the
# requirement that server-team already carry node_modules/@drumee — so the seed
# is now buildable from public sources alone, which is what
# docs/reproducible-builds.md was after.
set -euo pipefail

# --- knobs (overridable via `docker run -e`) --------------------------------
DB_PORT="${DB_PORT:-3306}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-seedroot}"
DB_USER="${DB_USER:-drumee-app}"
DB_PASSWORD="${DB_PASSWORD:-seedapp}"
DRUMEE_DOMAIN_NAME="${DRUMEE_DOMAIN_NAME:-localhost}"
DATADIR="${DATADIR:-/var/lib/mysql}"
BACKUP_DIR="${BACKUP_DIR:-/backup}"
OUT_DIR="${OUT_DIR:-/out}"
OUT_FILE="${OUT_FILE:-seeds.tgz}"

SRC_SCHEMAS=/src/schemas
FACTORY_DIR="$SRC_SCHEMAS/templates/factory"

[ -d "$FACTORY_DIR/seed" ] || {
  echo "FATAL: expected mounted source missing: $FACTORY_DIR/seed" >&2; exit 1; }
mkdir -p "$OUT_DIR" "$BACKUP_DIR"

# --- 1. start a local MariaDB on loopback ------------------------------------
echo "==> Initializing throwaway datadir at $DATADIR"
rm -rf "${DATADIR:?}/"* 2>/dev/null || true
mariadb-install-db --user=root --datadir="$DATADIR" \
  --auth-root-authentication-method=normal --skip-test-db >/dev/null

echo "==> Starting mariadbd on 127.0.0.1:$DB_PORT"
mariadbd --user=root --datadir="$DATADIR" \
  --bind-address=127.0.0.1 --port="$DB_PORT" \
  --skip-name-resolve --innodb-buffer-pool-size=256M &
MARIADB_PID=$!
cleanup() { kill "$MARIADB_PID" 2>/dev/null || true; }
trap cleanup EXIT

for _ in $(seq 1 60); do
  mariadb -uroot --socket=/run/mysqld/mysqld.sock -e 'SELECT 1' >/dev/null 2>&1 && break
  sleep 1
done
mariadb -uroot --socket=/run/mysqld/mysqld.sock -e 'SELECT 1' >/dev/null 2>&1 \
  || { echo "FATAL: mariadbd did not come up" >&2; exit 1; }

# Give root a password over TCP so the reused container scripts (which speak TCP,
# as they do against the compose 'mariadb' service) can connect over loopback.
# mariadb-install-db pre-creates root@'127.0.0.1' / root@'::1' with EMPTY passwords,
# and a loopback TCP connection matches those SPECIFIC accounts before root@'%' —
# so we must set the password on them (CREATE IF NOT EXISTS is a no-op when the
# account already exists, hence the explicit ALTER).
for h in '127.0.0.1' '::1' '%'; do
  mariadb -uroot --socket=/run/mysqld/mysqld.sock <<SQL
CREATE USER IF NOT EXISTS 'root'@'$h' IDENTIFIED BY '$DB_ROOT_PASSWORD';
ALTER USER 'root'@'$h' IDENTIFIED BY '$DB_ROOT_PASSWORD';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'$h' WITH GRANT OPTION;
SQL
done
mariadb -uroot --socket=/run/mysqld/mysqld.sock -e 'FLUSH PRIVILEGES'

# --- 2. base databases + factory seed (reuse schemas-init.sh) ----------------
echo "==> schemas-init: base DBs from templates/factory/seed + schema patches"
DB_HOST=127.0.0.1 DB_PORT="$DB_PORT" DB_ROOT_PASSWORD="$DB_ROOT_PASSWORD" \
DB_USER="$DB_USER" DB_PASSWORD="$DB_PASSWORD" \
DRUMEE_DOMAIN_NAME="$DRUMEE_DOMAIN_NAME" \
FACTORY_DIR="$FACTORY_DIR" SCHEMAS_DIR="$SRC_SCHEMAS" \
  /usr/local/bin/schemas-init

# --- 3. neutrality assertion -------------------------------------------------
# The seed must describe a Drumee, not this container. Asserted rather than
# assumed, because the previous version of this script violated it silently and
# the damage only showed up as an admin account whose files nginx would not
# serve (see the header). Anything that reintroduces host state — a template
# that regained rows, a populate step added back here — fails the build now.
echo "==> Checking the seed carries no host-specific entities"
seed_check() { mariadb -uroot -p"$DB_ROOT_PASSWORD" -h127.0.0.1 -P"$DB_PORT" -N -B -e "$1" 2>/dev/null || echo 0; }
bad=0
entities=$(seed_check "SELECT COUNT(*) FROM yp.entity")
homedirs=$(seed_check "SELECT COUNT(*) FROM yp.entity WHERE home_dir IS NOT NULL AND home_dir<>''")
trashed=$(seed_check "SELECT COUNT(*) FROM trash.entity")
if [ "${entities:-0}" != 0 ]; then
  echo "FATAL: seed contains $entities yp.entity rows — it must contain none." >&2
  echo "  Entities carry an absolute home_dir, so they can only be created on the" >&2
  echo "  target host, which is the only party that knows its own data_dir." >&2
  bad=1
fi
[ "${homedirs:-0}" = 0 ] || { echo "FATAL: seed contains $homedirs baked home_dir values." >&2; bad=1; }
[ "${trashed:-0}" = 0 ] || { echo "FATAL: seed's trash.entity carries $trashed deleted account(s) from the template host." >&2; bad=1; }
[ "$bad" = 0 ] || { echo "Refusing to publish a host-specific seed." >&2; exit 1; }
echo "Seed is host-neutral (0 entities; pool is stocked by populate.js on the target)"

echo "==> Pool status (expected empty — the target host stocks it)"
mariadb -uroot -p"$DB_ROOT_PASSWORD" -h127.0.0.1 -P"$DB_PORT" -N -B \
  -e "SELECT area, type, COUNT(*) FROM yp.entity GROUP BY area, type" || true

# --- 3. mariabackup -> seeds.tgz (mirrors schemas/bin/build-seeds) ----------
# Pin the collation like build-seeds does, then take a hot physical backup.
collation=$(mariadb -uroot -p"$DB_ROOT_PASSWORD" -h127.0.0.1 -P"$DB_PORT" \
  -e "show variables like 'character_set_collations';" | tail -1 || true)
if [ -n "$collation" ]; then
  mariadb -uroot -p"$DB_ROOT_PASSWORD" -h127.0.0.1 -P"$DB_PORT" \
    -e "set GLOBAL character_set_collations='utf8mb4=utf8mb4_general_ci'" || true
fi

echo "==> mariabackup --backup"
rm -rf "${BACKUP_DIR:?}/"* 2>/dev/null || true
mariabackup --backup --target-dir="$BACKUP_DIR" \
  --datadir="$DATADIR" --user=root --password="$DB_ROOT_PASSWORD" \
  --host=127.0.0.1 --port="$DB_PORT"
echo "==> mariabackup --prepare"
mariabackup --prepare --target-dir="$BACKUP_DIR"

echo "==> Archiving prepared backup -> $OUT_DIR/$OUT_FILE"
# Top-level = prepared backup contents, so setup-schemas/bin/install's
# `tar --one-top-level=seeds` + `mariabackup --copy-back --target-dir=.../seeds`
# restores it correctly.
tar zcfp "$OUT_DIR/$OUT_FILE" -C "$BACKUP_DIR" .

echo "==> Done: $OUT_DIR/$OUT_FILE ($(du -h "$OUT_DIR/$OUT_FILE" | cut -f1))"
