#!/bin/bash
# Build one package-based role image, with the base image pinned by digest.
#
#   docker/build-role.sh web                     # version from release-manifest.yaml
#   docker/build-role.sh web --tag=1.0.29        # override the image tag
#   APT_URI=http://localhost:8099 docker/build-role.sh web   # build against a local repo
#
# Why a script rather than a bare `docker build`: the role Dockerfile pins its base by
# DIGEST and takes no default, because a floating tag is exactly what
# docs/distribution.md §8 rules out — two builds of the same tag are not the same image.
# A locally-built image has no repo digest to reference (measured: `FROM name@<image id>`
# is rejected for images that were never pushed), so the digest has to come from
# somewhere. This pushes the base to a throwaway local registry and reads it back.
#
# That is also the shape of the release path, where the base is pushed to the real
# registry and the role is built against that digest. Same mechanism, different registry.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
say(){ printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

ROLE=""; TAG=""
for a in "$@"; do
  case "$a" in
    --tag=*) TAG="${a#*=}" ;;
    -*)      die "unknown option: $a" ;;
    *)       ROLE="$a" ;;
  esac
done
[ -n "$ROLE" ] || die "usage: $0 <role> [--tag=X]   (role: web, app, media, dns, mail, schemas, infra)"
dockerfile="$root/docker/Dockerfile.role-$ROLE"
[ -f "$dockerfile" ] || die "no $dockerfile — only the roles with a Dockerfile can be built yet"

command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || die "docker unavailable"

# The role package version comes from the manifest, never from a default in the
# Dockerfile or a flag here: release-manifest.yaml is the only authoritative statement.
# roles/ is versioned as <release>-1~<channel>1, which is what roles/build.sh produces.
release="$(sed -E 's/#.*$//' "$root/release-manifest.yaml" | awk '/^release:/{print $2; exit}')"
channel="$(sed -E 's/#.*$//' "$root/release-manifest.yaml" | awk '/^channel:/{print $2; exit}')"
[ -n "$release" ] || die "release-manifest.yaml has no top-level 'release'"
ROLE_VERSION="${release}-1~${channel:-trixie}1"
TAG="${TAG:-$release}"

REGISTRY="${REGISTRY:-localhost:5000}"
REGISTRY_NAME="${REGISTRY_NAME:-drumee-local-registry}"
APT_URI="${APT_URI:-https://apt.drumee.net}"
APT_SUITE="${APT_SUITE:-${channel:-trixie}}"
APT_COMPONENTS="${APT_COMPONENTS:-main}"

say "base image"
docker buildx build -f "$root/docker/Dockerfile.base" -t drumee-base:latest --load "$root" >/dev/null
echo "  drumee-base:latest  $(docker image inspect -f '{{.Size}}' drumee-base:latest | numfmt --to=iec 2>/dev/null || echo '?')"

# A registry only to obtain a digest. Started if absent, left running — it costs nothing
# idle and re-running this script is the common case.
if ! docker inspect "$REGISTRY_NAME" >/dev/null 2>&1; then
  say "starting a local registry for digest resolution ($REGISTRY)"
  docker run -d --name "$REGISTRY_NAME" -p "${REGISTRY##*:}:5000" registry:2 >/dev/null
  sleep 2
elif [ "$(docker inspect -f '{{.State.Running}}' "$REGISTRY_NAME")" != "true" ]; then
  docker start "$REGISTRY_NAME" >/dev/null; sleep 2
fi

say "resolving the base digest"
docker tag drumee-base:latest "$REGISTRY/drumee-base:latest"
docker push -q "$REGISTRY/drumee-base:latest" >/dev/null
digest="$(docker image inspect -f '{{index .RepoDigests 0}}' "$REGISTRY/drumee-base:latest" | sed 's/.*@//')"
case "$digest" in
  sha256:*) echo "  $digest" ;;
  *) die "could not resolve a digest for the base image" ;;
esac

say "role image: drumee/role-$ROLE:$TAG  (drumee-role-$ROLE=$ROLE_VERSION from $APT_URI $APT_SUITE)"
docker buildx build -f "$dockerfile" \
  -t "drumee/role-$ROLE:$TAG" \
  --build-arg "BASE_IMAGE=$REGISTRY/drumee-base" \
  --build-arg "BASE_DIGEST=$digest" \
  --build-arg "ROLE_VERSION=$ROLE_VERSION" \
  --build-arg "APT_URI=$APT_URI" \
  --build-arg "APT_SUITE=$APT_SUITE" \
  --build-arg "APT_COMPONENTS=$APT_COMPONENTS" \
  --load "$root"

say "result"
printf '  %-28s %s\n' "drumee/role-$ROLE:$TAG" "$(docker image inspect -f '{{.Size}}' "drumee/role-$ROLE:$TAG" | numfmt --to=iec 2>/dev/null || echo '?')"
echo "  release recorded in the image: $(docker run --rm --entrypoint cat "drumee/role-$ROLE:$TAG" /usr/share/drumee/image-release 2>/dev/null || echo '?')"
echo "  drumee packages installed:"
docker run --rm --entrypoint dpkg-query "drumee/role-$ROLE:$TAG" -W -f='    ${Package} ${Version}\n' 'drumee-*' 2>/dev/null | sort
