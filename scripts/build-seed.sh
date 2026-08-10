#!/bin/bash
# Build the schemas seed (var/tmp/drumee/seeds.tgz) offline, from local source.
#
# Rework of schemas/make-seed.sh point #3: spin up a throwaway MariaDB in a
# container, populate the base databases from the schemas repo's
# templates/factory + STOCK the entity pool via server-team's offline/factory,
# then mariabackup the datadir into a seeds.tgz laid out exactly as
# setup-schemas/bin/install expects. See scripts/seed-entrypoint.sh.
#
#   scripts/build-seed.sh [--out=PATH]
#
# One source is bind-mounted read-only:
#   SCHEMAS_SRC        schemas checkout       (default schemas/src/schemas)
# Other env: TAG (image tag, default local), DRUMEE_DOMAIN_NAME (default localhost).
#
# server-team and setup-schemas used to be mounted too, so the seed builder could
# run container-populate.js and pre-stock the entity pool. That is gone: entities
# carry an absolute home_dir, so only the target host — the one party that knows
# its own data_dir — can create them (setup-schemas' populate.js stocks the pool
# at install). Dropping it also drops the requirement that server-team already
# carry node_modules/@drumee, so the seed no longer needs the private registry
# in any form.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

OUT="$root/schemas/var/tmp/drumee/seeds.tgz"
for arg in "$@"; do
  case $arg in
    --out=*) OUT="${arg#*=}" ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

TAG="${TAG:-local}"
DRUMEE_DOMAIN_NAME="${DRUMEE_DOMAIN_NAME:-localhost}"

# Prefer the tree schemas/build.sh already cloned via bundle(); fall back to env.
SCHEMAS_SRC="${SCHEMAS_SRC:-$root/schemas/src/schemas}"

docker buildx version >/dev/null 2>&1 || { echo "docker buildx required" >&2; exit 1; }
[ -f "$SCHEMAS_SRC/templates/factory/seed/yp.sql" ] || {
  echo "schemas factory templates not found at: $SCHEMAS_SRC (set SCHEMAS_SRC=)" >&2; exit 1; }

say "Building drumee/seed:$TAG"
docker buildx build \
  -f "$root/scripts/Dockerfile.seed" \
  # schemas-init and populate.js now live in drumee-bootstrap, which is where they
  # survive the deletion of deploy/docker. One copy, three consumers.
  --build-context "helpers=$root/bootstrap/usr/lib/drumee/schemas" \
  -t "drumee/seed:$TAG" --load "$root/scripts"

out_dir="$(dirname "$OUT")"
out_file="$(basename "$OUT")"
mkdir -p "$out_dir"

say "Building seed -> $OUT  (domain=$DRUMEE_DOMAIN_NAME, no entities by design)"
docker run --rm \
  --ulimit "nofile=1048576:1048576" \
  -e "DRUMEE_DOMAIN_NAME=$DRUMEE_DOMAIN_NAME" \
  -e "OUT_FILE=$out_file" \
  -v "$SCHEMAS_SRC:/src/schemas:ro" \
  -v "$out_dir:/out" \
  "drumee/seed:$TAG"

say "Seed ready: $OUT"
