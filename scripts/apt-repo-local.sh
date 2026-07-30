#!/bin/bash
# Local APT repository, for developing and testing the container distribution.
#
#   scripts/apt-repo-local.sh init                       # create .apt-local/ + a test key
#   scripts/apt-repo-local.sh include [opts] <deb>...    # add packages
#   scripts/apt-repo-local.sh list [suite]               # what is in there
#   scripts/apt-repo-local.sh sources [--http]           # client configuration to paste
#   scripts/apt-repo-local.sh serve [--port=N]           # throwaway nginx over HTTP
#   scripts/apt-repo-local.sh stop                       # stop that container
#   scripts/apt-repo-local.sh purge                      # delete the whole thing
#
# Why this exists: nothing can install drumee-role-app until something publishes
# it, and apt.drumee.net does not exist yet. This stands in for it — same tool
# (reprepro) and same layout as the real repository will use, so what is proven
# here transfers.
#
# Two ways to consume it (see `sources`):
#   file://  — for builds on this host, no server needed
#   http://  — for image builds, which cannot reach a file:// URI in a container
#
# include options:
#   --suite=NAME       default trixie          (trixie-beta, trixie-edge)
#   --component=NAME   default main            (or enterprise)
#
# Env: APT_LOCAL_DIR (default .apt-local), APT_LOCAL_PORT (default 8899)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${APT_LOCAL_DIR:-$root/.apt-local}"
PORT="${APT_LOCAL_PORT:-8899}"
CONTAINER=drumee-apt-local
# Pinned like every other image we depend on: a test repository that changes
# behaviour between runs is worse than no test repository.
NGINX_IMAGE="${NGINX_IMAGE:-nginx:alpine@sha256:4a73073bd557c65b759505da037898b61f1be6cbcc3c2c3aeac22d2a470c1752}"

KEY_UID="Drumee local test key <local@drumee.invalid>"
SUITES=(trixie trixie-beta trixie-edge)
COMPONENTS="main enterprise"
# NOT 'all', despite what a package's Architecture field may say: reprepro
# rejects it outright ("Distribution trixie contains an architecture called
# 'all'"). It is not a distributable architecture, it is a statement that one
# binary serves every architecture — so reprepro files Architecture: all
# packages into EVERY listed architecture's index. Listing amd64 and arm64
# therefore publishes arch-independent packages to both, which is exactly the
# intent. `verify` below proves it rather than asserting it.
ARCHITECTURES="amd64 arm64 source"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32mok\033[0m   %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v reprepro >/dev/null || die "reprepro is required: apt-get install reprepro"
command -v gpg >/dev/null      || die "gpg is required"

# The test key lives with the repository and never leaves it. Exporting
# GNUPGHOME here means reprepro signs with it too, without touching ~/.gnupg.
export GNUPGHOME="$REPO/gnupg"

key_fpr() {
  gpg --list-keys --with-colons "$KEY_UID" 2>/dev/null \
    | awk -F: '/^fpr:/ {print $10; exit}'
}

# ---------------------------------------------------------------------- init
cmd_init() {
  install -d -m 0755 "$REPO/conf"
  install -d -m 0700 "$GNUPGHOME"

  local fpr
  fpr="$(key_fpr || true)"
  if [ -z "$fpr" ]; then
    say "Generating a local test signing key (never committed, no passphrase)"
    # Unattended and passphrase-less on purpose: this key signs a throwaway
    # repository on a developer's machine. The real project key is offline with
    # only a signing subkey in CI — see docs/distribution.md §4.
    gpg --batch --yes --passphrase '' \
        --quick-generate-key "$KEY_UID" rsa3072 sign never >/dev/null 2>&1
    fpr="$(key_fpr)"
    [ -n "$fpr" ] || die "key generation failed"
  fi
  ok "signing key ${fpr:0:16}…"

  say "Writing conf/distributions (${#SUITES[@]} suites x $COMPONENTS)"
  : > "$REPO/conf/distributions"
  local suite
  for suite in "${SUITES[@]}"; do
    cat >> "$REPO/conf/distributions" <<EOF
Origin: Drumee
Label: Drumee local test
Codename: $suite
Suite: $suite
Architectures: $ARCHITECTURES
Components: $COMPONENTS
Description: Drumee local test repository ($suite)
SignWith: $fpr
# Channels are SUITES, not components: they are mutually exclusive release
# trains, so a client pins one through /etc/apt/preferences.d. Components are
# reserved for the open-core split (main = AGPL core, enterprise = commercial).
# Promotion between channels is 'reprepro copy', never a rebuild, so the
# artifact tested in beta is bit-for-bit the one that ships.

EOF
  done

  # Exported in both encodings: .asc for humans and for `apt-key`-free setups,
  # .gpg dearmored for Signed-By, which is what the deb822 stanza references.
  gpg --armor --export "$fpr" > "$REPO/drumee-local-keyring.asc"
  gpg --export "$fpr"        > "$REPO/drumee-local-keyring.gpg"

  for suite in "${SUITES[@]}"; do
    reprepro -b "$REPO" export "$suite" >/dev/null
  done
  ok "repository at $REPO"
  ok "suites: ${SUITES[*]}"
  printf '\n'
  say "Next: scripts/apt-repo-local.sh include out-debs/*.deb"
}

# ------------------------------------------------------------------- include
cmd_include() {
  local suite=trixie component=main debs=()
  local a
  for a in "$@"; do
    case "$a" in
      --suite=*)     suite="${a#*=}" ;;
      --component=*) component="${a#*=}" ;;
      -*) die "unknown option: $a" ;;
      *) debs+=("$a") ;;
    esac
  done
  [ ${#debs[@]} -gt 0 ] || die "no .deb given"
  [ -d "$REPO/conf" ] || die "not initialised — run: $0 init"

  local d
  for d in "${debs[@]}"; do
    [ -f "$d" ] || die "no such file: $d"
    # includedeb is idempotent per (package, version): re-adding the same
    # version is refused, which is what we want — a repository that silently
    # replaces an artifact under an unchanged version is a supply-chain hazard.
    if reprepro -b "$REPO" -C "$component" includedeb "$suite" "$d" 2>&1 | tee /dev/stderr | grep -q "^ERROR"; then
      die "reprepro refused $d"
    fi
    ok "$(basename "$d") -> $suite/$component"
  done
}

cmd_list() { reprepro -b "$REPO" list "${1:-trixie}"; }

# ------------------------------------------------------------------- consume
cmd_sources() {
  local uri="file://$REPO"
  [ "${1:-}" = "--http" ] && uri="http://localhost:$PORT"
  cat <<EOF
# /etc/apt/sources.list.d/drumee-local.sources
Types: deb
URIs: $uri
Suites: ${SUITES[0]}
Components: $COMPONENTS
Architectures: amd64
Signed-By: $REPO/drumee-local-keyring.gpg
EOF
}

cmd_serve() {
  local a
  for a in "$@"; do case "$a" in --port=*) PORT="${a#*=}" ;; esac; done
  command -v docker >/dev/null || die "docker is required to serve over HTTP"
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  # A container build cannot fetch a file:// URI, so image tests need HTTP.
  docker run -d --name "$CONTAINER" -p "$PORT:80" \
    -v "$REPO:/usr/share/nginx/html:ro" "$NGINX_IMAGE" >/dev/null
  ok "serving $REPO on http://localhost:$PORT (container $CONTAINER)"
  say "From another container use http://host.docker.internal:$PORT or the host IP."
}

cmd_stop()  { docker rm -f "$CONTAINER" >/dev/null 2>&1 && ok "stopped $CONTAINER" || ok "not running"; }
cmd_purge() { cmd_stop >/dev/null 2>&1 || true; rm -rf "$REPO"; ok "removed $REPO"; }

# -------------------------------------------------------------------- verify
# Proves the two properties that are easy to assume and expensive to get wrong:
# the indices are signed, and Architecture: all packages really are published
# for every architecture even though 'all' is not in the Architectures list.
cmd_verify() {
  local suite="${1:-trixie}" rc=0
  [ -f "$REPO/dists/$suite/InRelease" ] && ok "InRelease present ($suite)" \
    || { printf '  FAIL InRelease missing\n'; rc=1; }
  if gpg --verify "$REPO/dists/$suite/InRelease" >/dev/null 2>&1; then
    ok "InRelease signature verifies against the local key"
  else
    printf '  FAIL InRelease does not verify\n'; rc=1
  fi
  local arch found
  for arch in amd64 arm64; do
    found=$(zcat -f "$REPO/dists/$suite/main/binary-$arch/Packages" 2>/dev/null \
            | grep -c '^Package: ' || true)
    printf '  %-6s binary-%s: %s package(s)\n' "" "$arch" "${found:-0}"
  done
  return $rc
}

case "${1:-}" in
  init)    shift; cmd_init "$@" ;;
  include) shift; cmd_include "$@" ;;
  list)    shift; cmd_list "$@" ;;
  sources) shift; cmd_sources "$@" ;;
  serve)   shift; cmd_serve "$@" ;;
  stop)    shift; cmd_stop "$@" ;;
  verify)  shift; cmd_verify "$@" ;;
  purge)   shift; cmd_purge "$@" ;;
  *) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; exit 2 ;;
esac
