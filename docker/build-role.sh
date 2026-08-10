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

ROLE=""; TAG=""; NOCACHE=""
for a in "$@"; do
  case "$a" in
    --tag=*)    TAG="${a#*=}" ;;
    --no-cache) NOCACHE=1 ;;
    -*)         die "unknown option: $a" ;;
    *)          ROLE="$a" ;;
  esac
done
[ -n "$ROLE" ] || die "usage: $0 <role> [--tag=X] [--no-cache]   (role: web, app, converter, dns, mail, schemas, infra)"
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
# Which public keyring under docker/keyrings/ verifies APT_URI. Defaults to the project
# archive key; point it at the throwaway key from scripts/apt-repo-local.sh to build
# against a local repository, which is how a role is tested before anything is published.
APT_KEYRING="${APT_KEYRING:-drumee-archive-keyring.gpg}"

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

# When the repository is LOCAL, always miss the cache on the apt layer.
#
# Iterating means re-including a package at the SAME version — that is what a local
# repository is for. The Dockerfile and every build-arg are then unchanged, so buildx
# reuses the cached apt layer and the new package never reaches the image, while the build
# reports success and prints the version it believes it installed. Measured: a rebuilt
# role-converter still carried the previous entrypoint, and the test that should have
# caught it passed against stale content.
#
# Only for a local URI: against apt.drumee.net a version is immutable, so the cache is
# both safe and worth keeping.
cachebust=""
case "$APT_URI" in
  https://apt.drumee.net*) : ;;
  *) if [ -z "$NOCACHE" ]; then
       cachebust="$(cat "$root/.apt-local/dists/$APT_SUITE/Release" 2>/dev/null \
                    | sha256sum | cut -c1-16)"
       [ -n "$cachebust" ] && say "local repository: busting the apt layer cache ($cachebust)"
     fi ;;
esac

say "role image: drumee/role-$ROLE:$TAG  (drumee-role-$ROLE=$ROLE_VERSION from $APT_URI $APT_SUITE)"
docker buildx build -f "$dockerfile" \
  ${NOCACHE:+--no-cache} \
  ${cachebust:+--build-arg "APT_CACHEBUST=$cachebust"} \
  -t "drumee/role-$ROLE:$TAG" \
  --build-arg "BASE_IMAGE=$REGISTRY/drumee-base" \
  --build-arg "BASE_DIGEST=$digest" \
  --build-arg "ROLE_VERSION=$ROLE_VERSION" \
  --build-arg "APT_URI=$APT_URI" \
  --build-arg "APT_SUITE=$APT_SUITE" \
  --build-arg "APT_COMPONENTS=$APT_COMPONENTS" \
  --build-arg "APT_KEYRING=$APT_KEYRING" \
  --load "$root"

say "result"
printf '  %-28s %s\n' "drumee/role-$ROLE:$TAG" "$(docker image inspect -f '{{.Size}}' "drumee/role-$ROLE:$TAG" | numfmt --to=iec 2>/dev/null || echo '?')"
echo "  release recorded in the image: $(docker run --rm --entrypoint cat "drumee/role-$ROLE:$TAG" /usr/share/drumee/image-release 2>/dev/null || echo '?')"
echo "  drumee packages installed:"
docker run --rm --entrypoint dpkg-query "drumee/role-$ROLE:$TAG" -W -f='    ${Package} ${Version}\n' 'drumee-*' 2>/dev/null | sort
