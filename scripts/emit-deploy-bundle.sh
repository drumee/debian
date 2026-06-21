#!/bin/bash
# Emit the node's PORTABLE deploy bundle (docker-compose.yml + .env, named
# volumes, plugins generic from drumee.yaml) into the node's credential volume at
# /deploy/. That dir lives under /etc/drumee/credential, which the backup worker
# already captures — so the deploy definition rides INSIDE every backup. A blank
# recovery box then pulls it back out (dr-up.sh) and brings the node up with no
# hand-maintained DR compose and no registry.
#
#   scripts/emit-deploy-bundle.sh                 # uses ~/.drumee-dev + drumee-dev
#   CONFIG=/path/drumee.yaml PROJECT=drumee CRED_VOLUME=drumee_drumee_cred \
#     scripts/emit-deploy-bundle.sh
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="${DRUMEE_DEV_DIR:-$HOME/.drumee-dev}"
CONFIG="${CONFIG:-$W/drumee.yaml}"
PROJECT="${PROJECT:-drumee-dev}"
CRED_VOLUME="${CRED_VOLUME:-${PROJECT}_drumee_cred}"

[ -f "$CONFIG" ] || { echo "config not found: $CONFIG" >&2; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

echo "==> Rendering portable deploy bundle from $CONFIG"
node "$root/config/render.mjs" dr-bundle --config "$CONFIG" --out-dir "$stage" >/dev/null

echo "==> Writing bundle into ${CRED_VOLUME}:/deploy (backed up via /etc/drumee/credential)"
docker run --rm -v "${CRED_VOLUME}:/cred" -v "$stage:/stage:ro" --entrypoint sh \
  "${IMAGE:-drumee/restore-appliance:local}" -c '
    mkdir -p /cred/deploy
    cp /stage/docker-compose.yml /cred/deploy/docker-compose.yml
    cp /stage/.env /cred/deploy/.env
    chmod 600 /cred/deploy/.env
    ls -l /cred/deploy'
echo "==> Done. The next backup will include the deploy bundle."
