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

if [ -d "$SETUP_INFRA_SRC" ]; then
  say "Building drumee/infra-init:$TAG (FROM server-pod + setup-infra + opendkim-tools)"
  docker buildx build -f "$root/deploy/docker/Dockerfile.infra-init" \
    --build-context "helpers=$root/deploy/docker" --build-context "infra=$SETUP_INFRA_SRC" \
    --build-arg "SERVER_IMAGE=drumee/server-pod:$TAG" \
    -t "drumee/infra-init:$TAG" --load "$root/deploy/docker"
else
  say "Skipping drumee/infra-init (no setup-infra source at $SETUP_INFRA_SRC)"
fi

# ---- server plugins ----
# Build each declared server plugin as drumee/<name>:$TAG from its source repo.
# Override the list with SERVER_PLUGINS="name:/path/to/src name2:/path2 ...".
for spec in ${SERVER_PLUGINS:-loby:$HOME/loby}; do
  name="${spec%%:*}"; src="${spec#*:}"
  if [ -d "$src" ]; then
    say "Building drumee/$name:$TAG (server plugin) from $src"
    # Surface the plugin's own worker declaration (package.json drumee.worker) as
    # an image label so the renderer can give it a long-running worker service —
    # without anyone hardcoding the plugin or editing the instance config.
    worker="$(node -e "process.stdout.write(require('$src/package.json').drumee?.worker||'')" 2>/dev/null || true)"
    docker buildx build -f "$root/deploy/docker/Dockerfile.plugin-server" \
      --build-context "helpers=$root/deploy/docker" --build-arg INSTALL_DEPS=0 \
      --label "drumee.worker=$worker" \
      -t "drumee/$name:$TAG" --load "$src"
  else
    say "Skipping server plugin '$name' (no source at $src)"
  fi
done

# ---- ui plugins ----
# Build each declared UI plugin as drumee/<name>-ui:$TAG (webpack bundle).
# Override the list with UI_PLUGINS="name:/path/to/src ...".
for spec in ${UI_PLUGINS:-}; do
  name="${spec%%:*}"; src="${spec#*:}"
  if [ -d "$src" ]; then
    say "Building drumee/$name-ui:$TAG (ui plugin) from $src"
    docker buildx build -f "$root/deploy/docker/Dockerfile.plugin-ui" \
      --build-context "helpers=$root/deploy/docker" --build-arg INSTALL_DEPS=0 \
      --build-arg "PLUGIN_NAME=$name" \
      -t "drumee/$name-ui:$TAG" --load "$src"
  else
    say "Skipping ui plugin '$name' (no source at $src)"
  fi
done

say "Done. Images:"
docker image ls --format '  {{.Repository}}:{{.Tag}}  {{.Size}}' | grep "drumee/.*:$TAG" || true
