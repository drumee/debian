#!/bin/bash
# Build and push all Drumee images to a registry, tagged by version (+ latest).
# Used by CI on release and runnable by hand.
#
#   REGISTRY=ghcr.io/drumee TAG=2.9.45 scripts/publish-images.sh
#
# Env:
#   REGISTRY  (default ghcr.io/drumee)   image namespace
#   TAG       (required)                 version tag, e.g. a git tag or manifest version
#   PUSH      (default 1)                1 = buildx --push; 0 = --load (local only)
#   PLATFORMS (default linux/amd64)      buildx target platforms. Add linux/arm64
#                                        for Raspberry Pi / ARM boxes — the common
#                                        home-server target. Multi-platform needs
#                                        PUSH=1: a manifest list cannot be --load'ed
#                                        into the local docker image store.
#   ALSO_LATEST (default 1)              also tag/push :latest
#   ALSO_STABLE (default 1)              also tag/push :stable (the moving release channel)
#   *_SRC     source checkouts (default ~/<repo>)
#   MEDIA_DEPS (default 1)               include media tools in server-pod (prod)
#
# Requires: docker buildx, and (for PUSH=1) a prior `docker login` to REGISTRY.
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
REGISTRY="${REGISTRY:-ghcr.io/drumee}"
TAG="${TAG:?set TAG to the release version}"
PUSH="${PUSH:-1}"
ALSO_LATEST="${ALSO_LATEST:-1}"
ALSO_STABLE="${ALSO_STABLE:-1}"
MEDIA_DEPS="${MEDIA_DEPS:-1}"
# Single-arch by default: emulated cross-builds of the media stack (libreoffice,
# ffmpeg) take the better part of an hour, so opting in is a conscious choice.
PLATFORMS="${PLATFORMS:-linux/amd64}"
# 0 reuses the checkout's node_modules (installed with registry auth on the
# host/runner); 1 runs `npm ci` inside the build (needs in-build @drumee auth).
INSTALL_DEPS="${INSTALL_DEPS:-0}"
SERVER_SRC="${SERVER_SRC:-$HOME/server-team}"
UI_SRC="${UI_SRC:-$HOME/ui-team}"
SCHEMAS_SRC="${SCHEMAS_SRC:-$HOME/schemas}"
SETUP_SCHEMAS_SRC="${SETUP_SCHEMAS_SRC:-$HOME/setup-schemas}"
SETUP_INFRA_SRC="${SETUP_INFRA_SRC:-$HOME/setup-infra}"
STATIC_SRC="${STATIC_SRC:-$HOME/static}"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
docker buildx version >/dev/null 2>&1 || { echo "docker buildx required" >&2; exit 1; }

out_flag=(--load); [ "$PUSH" = 1 ] && out_flag=(--push)
plat_flag=(--platform "$PLATFORMS")
case "$PLATFORMS" in
  *,*)
    # buildx can only --load a single-platform result; a manifest list has to go
    # straight to a registry. Fail now rather than after the first long build.
    [ "$PUSH" = 1 ] || { echo "PLATFORMS lists more than one platform, which requires PUSH=1" >&2; exit 1; }
    docker buildx inspect --bootstrap >/dev/null 2>&1 || true
    ;;
esac
tags() { local n="$1"; printf -- '-t %s/%s:%s ' "$REGISTRY" "$n" "$TAG"
  [ "$ALSO_STABLE" = 1 ] && printf -- '-t %s/%s:stable ' "$REGISTRY" "$n"
  [ "$ALSO_LATEST" = 1 ] && printf -- '-t %s/%s:latest ' "$REGISTRY" "$n"; }

say "Registry=$REGISTRY Tag=$TAG Push=$PUSH Platforms=$PLATFORMS"

say "server-pod"
docker buildx build "${plat_flag[@]}" -f "$root/deploy/docker/Dockerfile.server" \
  --build-context "helpers=$root/deploy/docker" \
  --build-context "pkg=$root/bootstrap/usr/lib/drumee/schemas" \
  --build-arg "INSTALL_DEPS=$INSTALL_DEPS" --build-arg "MEDIA_DEPS=$MEDIA_DEPS" \
  $(tags server-pod) "${out_flag[@]}" "$SERVER_SRC"

say "ui-build"
docker buildx build "${plat_flag[@]}" -f "$root/deploy/docker/Dockerfile.ui" \
  --build-arg "INSTALL_DEPS=$INSTALL_DEPS" $(tags ui-build) "${out_flag[@]}" "$UI_SRC"

say "schemas"
docker buildx build "${plat_flag[@]}" -f "$root/deploy/docker/Dockerfile.schemas" \
  --build-context "helpers=$root/deploy/docker" \
  --build-context "pkg=$root/bootstrap/usr/lib/drumee/schemas" \
  $(tags schemas) "${out_flag[@]}" "$SCHEMAS_SRC"

say "schemas-populate (FROM published server-pod)"
docker buildx build "${plat_flag[@]}" -f "$root/deploy/docker/Dockerfile.populate" \
  --build-context "helpers=$root/deploy/docker" \
  --build-context "pkg=$root/bootstrap/usr/lib/drumee/schemas" \
  --build-context "setup=$SETUP_SCHEMAS_SRC" \
  --build-context "schemas=$SCHEMAS_SRC" \
  --build-arg "SERVER_IMAGE=$REGISTRY/server-pod:$TAG" \
  $(tags schemas-populate) "${out_flag[@]}" "$root/deploy/docker"

say "wireguard (coordination agent; bootstrap.sh + agent.js from infra/)"
docker buildx build "${plat_flag[@]}" -f "$root/deploy/docker/Dockerfile.wireguard" \
  --build-context "wg=$root/infra/var/lib/drumee/wireguard" \
  $(tags wireguard) "${out_flag[@]}" "$root/deploy/docker"

if [ -d "$SETUP_INFRA_SRC" ]; then
  say "infra-init (FROM published server-pod)"
  docker buildx build "${plat_flag[@]}" -f "$root/deploy/docker/Dockerfile.infra-init" \
    --build-context "helpers=$root/deploy/docker" --build-context "infra=$SETUP_INFRA_SRC" \
    --build-arg "SERVER_IMAGE=$REGISTRY/server-pod:$TAG" \
    $(tags infra-init) "${out_flag[@]}" "$root/deploy/docker"
else
  say "skip infra-init (no source at $SETUP_INFRA_SRC)"
fi

if [ -d "$STATIC_SRC" ]; then
  say "static"
  docker buildx build "${plat_flag[@]}" -f "$root/deploy/docker/Dockerfile.static" \
    $(tags static) "${out_flag[@]}" "$STATIC_SRC"
else
  say "skip static (no source at $STATIC_SRC)"
fi

say "Done. Images under $REGISTRY tagged :$TAG${ALSO_LATEST:+ (+ :latest)}"
