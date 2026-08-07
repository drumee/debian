#!/bin/bash
# Build Drumee images from LOCAL source checkouts, reusing their existing
# node_modules (no private @drumee registry access needed).
#
#   scripts/build-images-local.sh
#
# Env:
#   SERVER_SRC (default ~/server-team)   UI_SRC (default ~/ui-team)
#   TAG        (default local)
#   MEDIA_DEPS (default 0)   1 = install libreoffice/ffmpeg/etc (large, slow)
set -euo pipefail
if [ -z "${DRUMEE_QUIET_DEPRECATION:-}" ]; then
  # Deprecation notice, printed rather than only written down: this script builds images
  # from SOURCE CHECKOUTS, which is the approach docs/distribution.md §1 replaces with
  # images that install .deb packages. It still works and is still the only container path
  # that does, so this warns rather than refuses — but nothing new should be added to it.
  # See deploy/docker/DEPRECATED.md for what replaces each image and what has to be true
  # before the tree can go.
  printf '\033[1;33m==> DEPRECATED\033[0m source-based image build (deploy/docker/).\n'
  printf '    Replacement: role packages installed into docker/Dockerfile.base.\n'
  printf '    See deploy/docker/DEPRECATED.md. Set DRUMEE_QUIET_DEPRECATION=1 to silence.\n'
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_SRC="${SERVER_SRC:-$HOME/server-team}"
UI_SRC="${UI_SRC:-$HOME/ui-team}"
SCHEMAS_SRC="${SCHEMAS_SRC:-$HOME/schemas}"
SETUP_SCHEMAS_SRC="${SETUP_SCHEMAS_SRC:-$HOME/setup-schemas}"
SETUP_INFRA_SRC="${SETUP_INFRA_SRC:-$HOME/setup-infra}"
TAG="${TAG:-local}"
MEDIA_DEPS="${MEDIA_DEPS:-0}"
say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

[ -d "$SERVER_SRC" ]  || { echo "server source not found: $SERVER_SRC" >&2; exit 1; }
[ -d "$UI_SRC" ]      || { echo "ui source not found: $UI_SRC" >&2; exit 1; }
[ -d "$SCHEMAS_SRC" ] || { echo "schemas source not found: $SCHEMAS_SRC" >&2; exit 1; }
docker buildx version >/dev/null 2>&1 || { echo "docker buildx required" >&2; exit 1; }

say "Building drumee/schemas:$TAG from $SCHEMAS_SRC (factory templates + init)"
docker buildx build \
  -f "$root/deploy/docker/Dockerfile.schemas" \
  --build-context "helpers=$root/deploy/docker" \
  -t "drumee/schemas:$TAG" --load "$SCHEMAS_SRC"

say "Building drumee/server-pod:$TAG from $SERVER_SRC (INSTALL_DEPS=0, MEDIA_DEPS=$MEDIA_DEPS)"
docker buildx build \
  -f "$root/deploy/docker/Dockerfile.server" \
  --build-context "helpers=$root/deploy/docker" \
  --build-arg INSTALL_DEPS=0 \
  --build-arg "MEDIA_DEPS=$MEDIA_DEPS" \
  -t "drumee/server-pod:$TAG" --load "$SERVER_SRC"

say "Building drumee/ui-build:$TAG from $UI_SRC (INSTALL_DEPS=0, runs webpack)"
docker buildx build \
  -f "$root/deploy/docker/Dockerfile.ui" \
  --build-arg INSTALL_DEPS=0 \
  -t "drumee/ui-build:$TAG" --load "$UI_SRC"

STATIC_SRC="${STATIC_SRC:-$HOME/static}"
if [ -d "$STATIC_SRC" ]; then
  say "Building drumee/static:$TAG from $STATIC_SRC (splash/fonts/logo)"
  docker buildx build -f "$root/deploy/docker/Dockerfile.static" -t "drumee/static:$TAG" --load "$STATIC_SRC"
else
  say "Skipping drumee/static (no source at $STATIC_SRC). UI works without it; enable later"
  say "  by cloning the 'static' repo there, rebuilding, and COMPOSE_PROFILES=static."
fi

say "Building drumee/schemas-populate:$TAG (FROM server-pod + setup-schemas + genesis templates)"
docker buildx build \
  -f "$root/deploy/docker/Dockerfile.populate" \
  --build-context "helpers=$root/deploy/docker" \
  --build-context "setup=$SETUP_SCHEMAS_SRC" \
  --build-context "schemas=$SCHEMAS_SRC" \
  --build-arg "SERVER_IMAGE=drumee/server-pod:$TAG" \
  -t "drumee/schemas-populate:$TAG" --load "$root/deploy/docker"

say "Building drumee/wireguard:$TAG (coordination agent, from the infra/ package tree)"
docker buildx build \
  -f "$root/deploy/docker/Dockerfile.wireguard" \
  --build-context "wg=$root/infra/var/lib/drumee/wireguard" \
  -t "drumee/wireguard:$TAG" --load "$root/deploy/docker"

if [ -d "$SETUP_INFRA_SRC" ]; then
  say "Building drumee/infra-init:$TAG (FROM server-pod + setup-infra + opendkim-tools)"
  docker buildx build -f "$root/deploy/docker/Dockerfile.infra-init" \
    --build-context "helpers=$root/deploy/docker" --build-context "infra=$SETUP_INFRA_SRC" \
    --build-arg "SERVER_IMAGE=drumee/server-pod:$TAG" \
    -t "drumee/infra-init:$TAG" --load "$root/deploy/docker"
else
  say "Skipping drumee/infra-init (no setup-infra source at $SETUP_INFRA_SRC)"
fi

say "Done. Images:"
docker image ls --format '  {{.Repository}}:{{.Tag}}  {{.Size}}' | grep "drumee/.*:$TAG" || true
