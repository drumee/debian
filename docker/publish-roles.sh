#!/bin/bash
# Build and publish the role images.
#
#   docker/publish-roles.sh                         # every role, at the manifest's release
#   docker/publish-roles.sh --roles="web app"       # a subset
#   docker/publish-roles.sh --dry-run               # build, verify, push nothing
#   docker/publish-roles.sh --also=stable           # additionally move the `stable` tag
#
# The counterpart of docker/build-role.sh, which builds ONE role locally and `--load`s it.
# This one builds against the REAL apt repository and pushes, which differs in four ways
# that each caused a mistake worth not repeating:
#
#   * the base image has to be PUBLISHED. `FROM name@<image id>` is rejected for an image
#     that was never pushed, so the digest a role pins can only come from a registry.
#     build-role.sh fakes that with a throwaway local registry; here it is the real one,
#     and the base is a published artifact in its own right — it is the pinned foundation
#     every role's provenance rests on.
#   * the packages must already be live. Otherwise the failure is `apt-get install` not
#     finding a version, forty minutes into a build, reported as a Docker error. Checked
#     up front against the published Packages index.
#   * ONE tag for every role (§2). drumee-release pins the train and every role depends on
#     it at strict equality, so a per-role tag would invite exactly the mix that anchor
#     exists to prevent.
#   * the cache is left alone. Against apt.drumee.net a version is immutable, so there is
#     nothing to bust — see the APT_CACHEBUST note in the role Dockerfiles.
#
# NOT DONE HERE: cosign signatures and SBOMs (§8). Those are keyless via GitHub OIDC and
# belong to release.yml, which has the identity to produce them; a locally-signed image
# would assert a provenance this machine cannot back.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say(){ printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok(){  printf '  \033[1;32mok\033[0m   %s\n' "$*"; }
no(){  printf '  \033[1;31mfail\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

ALL_ROLES="infra schemas app web converter dns mail"
ROLES="$ALL_ROLES"; DRY=0; ALSO=""; TAG=""
for a in "$@"; do
  case "$a" in
    --roles=*)    ROLES="${a#*=}" ;;
    --tag=*)      TAG="${a#*=}" ;;
    --also=*)     ALSO="${a#*=}" ;;
    --dry-run)    DRY=1 ;;
    -*)           die "unknown option: $a" ;;
    *)            die "unexpected argument: $a" ;;
  esac
done

# Docker Hub `drumee/`, not ghcr.io/drumee. §8 names GHCR as primary and that remains the
# intent, but it needs a token with write:packages; the one available here is read-only, so
# publishing to it silently is not an option and neither is pretending. Override with
# REGISTRY= once the GHCR token is in place.
REGISTRY="${REGISTRY:-drumee}"
APT_URI="${APT_URI:-https://apt.drumee.net}"

release="$(sed -E 's/#.*$//' "$root/release-manifest.yaml" | awk '/^release:/{print $2; exit}')"
channel="$(sed -E 's/#.*$//' "$root/release-manifest.yaml" | awk '/^channel:/{print $2; exit}')"
[ -n "$release" ] || die "release-manifest.yaml has no top-level 'release'"
channel="${channel:-trixie}"
TAG="${TAG:-$release}"
ROLE_VERSION="${release}-1~${channel}1"
APT_SUITE="${APT_SUITE:-$channel}"
APT_COMPONENTS="${APT_COMPONENTS:-main}"
APT_KEYRING="${APT_KEYRING:-drumee-archive-keyring.gpg}"

# amd64 only, and it is not an oversight. drumee-server-pod is Architecture: any with an
# amd64-only build (18 vendored linux-x64 .node addons — docs/distribution.md §9.1), so an
# arm64 role-app could not install its own package; and the base image takes nodejs from
# NodeSource, which is fetched per architecture. Serving arm64 means building the packages
# for arm64 first, not adding a platform here.
PLATFORM="${PLATFORM:-linux/amd64}"

command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || die "docker unavailable"
for r in $ROLES; do
  [ -f "$root/docker/Dockerfile.role-$r" ] || die "no docker/Dockerfile.role-$r"
done

say "publishing role images"
printf '  %-14s %s\n' registry "$REGISTRY"
printf '  %-14s %s\n' tag "$TAG${ALSO:+  (also: $ALSO)}"
printf '  %-14s %s\n' packages "$ROLE_VERSION from $APT_URI $APT_SUITE/$APT_COMPONENTS"
printf '  %-14s %s\n' platform "$PLATFORM"
printf '  %-14s %s\n' roles "$ROLES"
[ "$DRY" = 1 ] && printf '  %-14s %s\n' mode "DRY RUN — nothing will be pushed"

# ── the packages must be live before anything is built ─────────────────────────────────
say "checking the packages are published"
idx="$(mktemp)"; trap 'rm -f "$idx"' EXIT
curl -fsSL --max-time 30 \
  "$APT_URI/dists/$APT_SUITE/$APT_COMPONENTS/binary-${PLATFORM##*/}/Packages" -o "$idx" \
  || die "could not fetch the Packages index from $APT_URI"
have(){ awk -v P="$1" -v V="$2" '/^Package:/{p=$2} /^Version:/{if(p==P && $2==V) f=1} END{exit !f}' "$idx"; }
missing=""
for r in $ROLES; do
  have "drumee-role-$r" "$ROLE_VERSION" || missing="$missing drumee-role-$r"
done
have drumee-release "$ROLE_VERSION" || missing="$missing drumee-release"
[ -z "$missing" ] || die "not published at $ROLE_VERSION:$missing
  publish the packages first: scripts/publish-pool.sh include --debs=… then scripts/deploy-apt-repo.sh --layout=pool"
ok "drumee-release and $(echo $ROLES | wc -w) role package(s) live at $ROLE_VERSION"

# ── the base image, published so a digest exists ───────────────────────────────────────
say "base image"
docker buildx build -f "$root/docker/Dockerfile.base" \
  --platform "$PLATFORM" -t "$REGISTRY/drumee-base:$TAG" --load "$root" >/dev/null
echo "  $REGISTRY/drumee-base:$TAG  $(docker image inspect -f '{{.Size}}' "$REGISTRY/drumee-base:$TAG" | numfmt --to=iec 2>/dev/null || echo '?')"

if [ "$DRY" = 1 ]; then
  # No push means no repo digest, so the roles cannot be pinned the way a real publish
  # pins them. Say so rather than substituting the image id, which Docker would reject
  # from a FROM line anyway — that rejection is the whole reason this script exists.
  say "dry run: not pushing the base, so no digest is available"
  echo "  a dry run can validate the checks above and the Dockerfiles, not the pinned build"
  exit 0
fi

say "pushing the base image"
docker push -q "$REGISTRY/drumee-base:$TAG" >/dev/null
digest="$(docker image inspect -f '{{index .RepoDigests 0}}' "$REGISTRY/drumee-base:$TAG" | sed 's/.*@//')"
case "$digest" in
  sha256:*) ok "$REGISTRY/drumee-base@$digest" ;;
  *) die "could not resolve a digest for the base image" ;;
esac

# ── the roles ──────────────────────────────────────────────────────────────────────────
built=""; failed=""
for r in $ROLES; do
  say "role-$r"
  tags=(-t "$REGISTRY/role-$r:$TAG")
  for extra in $ALSO; do tags+=(-t "$REGISTRY/role-$r:$extra"); done
  if docker buildx build -f "$root/docker/Dockerfile.role-$r" \
       --platform "$PLATFORM" \
       "${tags[@]}" \
       --build-arg "BASE_IMAGE=$REGISTRY/drumee-base" \
       --build-arg "BASE_DIGEST=$digest" \
       --build-arg "ROLE_VERSION=$ROLE_VERSION" \
       --build-arg "APT_URI=$APT_URI" \
       --build-arg "APT_SUITE=$APT_SUITE" \
       --build-arg "APT_COMPONENTS=$APT_COMPONENTS" \
       --build-arg "APT_KEYRING=$APT_KEYRING" \
       --push "$root"; then
    built="$built $r"
    ok "pushed $REGISTRY/role-$r:$TAG"
  else
    failed="$failed $r"
    no "role-$r did not build"
  fi
done

# ── verify what was pushed, by pulling it back ─────────────────────────────────────────
# Not a formality: the local build cache can satisfy a `docker run` from content that was
# never uploaded. Pulling by tag into a clean state is the only check that the registry has
# what this script claims it has.
say "verifying the published images"
for r in $built; do
  docker rmi "$REGISTRY/role-$r:$TAG" >/dev/null 2>&1 || true
  if ! docker pull -q "$REGISTRY/role-$r:$TAG" >/dev/null 2>&1; then
    no "role-$r: could not be pulled back"; failed="$failed $r"; continue
  fi
  got="$(docker run --rm --entrypoint cat "$REGISTRY/role-$r:$TAG" \
           /usr/share/drumee/image-release 2>/dev/null | tr -d '\r\n')"
  ver="$(docker run --rm --entrypoint dpkg-query "$REGISTRY/role-$r:$TAG" \
           -W -f='${Version}' "drumee-role-$r" 2>/dev/null)"
  if [ "$got" = "$release" ] && [ "$ver" = "$ROLE_VERSION" ]; then
    ok "role-$r: image-release $got, drumee-role-$r $ver"
  else
    no "role-$r: image-release '$got' (want $release), package '$ver' (want $ROLE_VERSION)"
    failed="$failed $r"
  fi
done

echo
if [ -n "$failed" ]; then
  printf '\033[1;31m== published:%s   FAILED:%s ==\033[0m\n' "${built:- none}" "$failed"
  exit 1
fi
printf '\033[1m== published %s role image(s) at %s:%s ==\033[0m\n' \
  "$(echo $built | wc -w)" "$REGISTRY/role-*" "$TAG"
echo "  base: $REGISTRY/drumee-base@$digest"
echo "  NOT signed — cosign/SBOM is release.yml's job (§8), see the header."
