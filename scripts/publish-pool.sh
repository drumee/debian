#!/bin/bash
# Build the pool/dists APT repository that apt.drumee.net serves.
#
#   scripts/publish-pool.sh init    --key=EMAIL_OR_KEYID
#   scripts/publish-pool.sh include --debs=DIR [--suite=trixie] [--component=main]
#   scripts/publish-pool.sh promote --from=trixie-beta --to=trixie [PKG...]
#   scripts/publish-pool.sh list    [SUITE]
#   scripts/publish-pool.sh verify  [SUITE]
#   scripts/publish-pool.sh check   [SUITE]      # real apt, in a container
#   scripts/publish-pool.sh sources [SUITE]
#
# This is the layout docs/distribution.md §4 specifies, and the successor to the
# flat repository built by scripts/publish-apt.sh. The two COEXIST during the
# transition: the flat Release/Packages/*.deb stay at the document root, and
# dists/ plus pool/ appear beside them. Nothing installed against the flat
# repository breaks while clients migrate — which matters, because a box that
# installed Drumee already has the flat stanza in its sources.list.d.
#
# Sign with the SAME key as the flat repository. A pool signed with a different
# key is unusable by every box that already trusts the published keyring, and the
# failure ("NO_PUBKEY") looks like a repository problem rather than a decision
# someone made here.
#
# What is deliberately NOT published from this directory: conf/ and db/. They are
# reprepro's configuration and internal state, they sit in the same base
# directory, and rsyncing the base directory wholesale would put the signing
# configuration on a public web server. scripts/deploy-apt-repo.sh --layout=pool
# uploads dists/ and pool/ only.
#
# Env: DRUMEE_POOL_DIR (default apt-pool), DRUMEE_APT_KEY (default for --key)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/apt-repo.sh
source "$root/scripts/lib/apt-repo.sh"

REPO="${DRUMEE_POOL_DIR:-$root/apt-pool}"
KEY="${DRUMEE_APT_KEY:-}"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()  { printf '  \033[1;32mok\033[0m   %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v reprepro >/dev/null || die "reprepro is required: apt-get install reprepro"
command -v gpg      >/dev/null || die "gpg is required"

key_fpr() {
  gpg --list-keys --with-colons "$1" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}'
}

# The key used at init is recorded in conf/distributions, so later commands do not
# need --key and cannot accidentally re-sign with a different one.
recorded_key() {
  [ -f "$REPO/conf/distributions" ] || return 0
  awk '/^SignWith:/ {print $2; exit}' "$REPO/conf/distributions"
}

require_repo() {
  [ -d "$REPO/conf" ] || die "not initialised — run: $0 init --key=..."
}

# ---------------------------------------------------------------------- init
cmd_init() {
  local a
  for a in "$@"; do
    case "$a" in
      --key=*) KEY="${a#*=}" ;;
      --out=*) REPO="${a#*=}" ;;
      *) die "unknown option: $a" ;;
    esac
  done
  [ -n "$KEY" ] || die "--key=EMAIL_OR_KEYID is required (or set DRUMEE_APT_KEY).
  It must be the key that signs the existing flat repository, otherwise clients
  that already trust it cannot read the pool. Available secret keys:
$(gpg --list-secret-keys --keyid-format=long 2>/dev/null | grep -E '^(sec|uid)' | sed 's/^/    /')"

  local fpr
  fpr="$(key_fpr "$KEY")"
  [ -n "$fpr" ] || die "no key matches '$KEY'"
  gpg --list-secret-keys "$fpr" >/dev/null 2>&1 || die "no SECRET key for '$KEY' — cannot sign"

  say "Signing key"
  drumee_apt_check_key_expiry "$fpr" || die "refusing to publish with an expired key"

  install -d -m 0755 "$REPO/conf"
  say "Writing conf/distributions (${#DRUMEE_APT_SUITES[@]} suites x $DRUMEE_APT_COMPONENTS)"
  drumee_apt_write_distributions "$REPO/conf/distributions" "$fpr" "Drumee"

  # Both encodings: .asc for humans and for the curl-into-keyrings bootstrap,
  # dearmored .gpg for the deb822 Signed-By the client stanza uses. Same file
  # names the flat repository already publishes — same key, so overwriting them
  # at the document root changes nothing for existing clients.
  gpg --armor --export "$fpr" > "$REPO/drumee-archive-keyring.asc"
  gpg --export "$fpr"         > "$REPO/drumee-archive-keyring.gpg"

  local suite
  for suite in "${DRUMEE_APT_SUITES[@]}"; do
    reprepro -b "$REPO" export "$suite" >/dev/null
  done
  ok "repository at $REPO"
  ok "suites: ${DRUMEE_APT_SUITES[*]}"
  printf '\n'
  say "Next: $0 include --debs=out-debs"
}

# ------------------------------------------------------------------- include
cmd_include() {
  local suite=trixie component=main debs="" a
  for a in "$@"; do
    case "$a" in
      --debs=*)      debs="${a#*=}" ;;
      --suite=*)     suite="${a#*=}" ;;
      --component=*) component="${a#*=}" ;;
      --out=*)       REPO="${a#*=}" ;;
      *) die "unknown option: $a" ;;
    esac
  done
  require_repo
  [ -n "$debs" ] && [ -d "$debs" ] || die "--debs=DIR (a directory of .deb files) required"

  # Re-check on every publish, not only at init: the key can expire between the
  # day the repository was created and the day something is added to it.
  drumee_apt_check_key_expiry "$(recorded_key)" || die "refusing to publish with an expired key"

  shopt -s nullglob
  local files=("$debs"/*.deb) f out
  shopt -u nullglob
  [ ${#files[@]} -gt 0 ] || die "no .deb files in $debs"

  local added=0 present=0 unchanged=() failed=()
  for f in "${files[@]}"; do
    # includedeb refuses to REPLACE an existing (package, version): a repository that
    # silently serves different bytes under a version it already published is the
    # supply-chain hazard this whole layout exists to avoid. Bump the version instead.
    out=$(reprepro -b "$REPO" -C "$component" includedeb "$suite" "$f" 2>&1 || true)
    printf '%s' "$out" | grep -vE '^(Exporting|Deleting|Created)' | sed '/^$/d; s/^/     /' >&2 || true
    if printf '%s' "$out" | grep -qE '^ERROR'; then
      # Recorded and carried on, rather than aborting the loop. A single conflicting
      # package used to stop the run, so every file after it was never attempted and
      # the operator could not tell what had actually been published without
      # re-reading the log. Failures are summarised at the end and the command still
      # exits non-zero.
      failed+=("$(basename "$f")")
      printf '  \033[1;31mfailed\033[0m %s\n' "$(basename "$f")"
      continue
    fi
    # "Skipping inclusion of 'X' 'V' … as it has already 'V'" is idempotent success,
    # NOT failure: a release normally moves only some components, and the rest arrive
    # at a version the pool already carries. Treating it as fatal aborted the whole
    # include on the first unchanged package and silently left every later one out.
    if printf '%s' "$out" | grep -qE 'Skipping inclusion'; then
      present=$((present + 1)); unchanged+=("$(basename "$f")")
      printf '  \033[2malready present\033[0m %s\n' "$(basename "$f")"
      continue
    fi
    added=$((added + 1))
    ok "$(basename "$f") -> $suite/$component"
  done

  printf '  %d added, %d already present in %s/%s\n' "$added" "$present" "$suite" "$component"
  # Said out loud, because this is also what a rebuild-without-a-version-bump looks
  # like: reprepro keys on version, so a changed .deb under a version already
  # published is skipped and the pool keeps serving the OLD bytes.
  if [ "$present" -gt 0 ]; then
    printf '  \033[1;33mnote\033[0m the pool kept its existing copy of: %s\n' "${unchanged[*]}"
    printf '       If any of those were rebuilt with changed content, the new bytes are\n'
    printf '       NOT published — bump the version and include again.\n'
  fi
  if [ "${#failed[@]}" -gt 0 ]; then
    printf '  \033[1;31m%d failed\033[0m: %s\n' "${#failed[@]}" "${failed[*]}"
    printf '       A "cannot be included / can only be included again if they are the same"\n'
    printf '       error means the pool already publishes that VERSION with different bytes.\n'
    printf '       Do not force it: bump the version so the new content gets its own.\n'
    exit 1
  fi
}

# ------------------------------------------------------------------- promote
# Channel promotion is a copy, never a rebuild: the bytes tested in beta are the
# bytes that ship. With no package names given, everything in --from moves.
cmd_promote() {
  local from="" to="" pkgs=() a
  for a in "$@"; do
    case "$a" in
      --from=*) from="${a#*=}" ;;
      --to=*)   to="${a#*=}" ;;
      --out=*)  REPO="${a#*=}" ;;
      -*) die "unknown option: $a" ;;
      *) pkgs+=("$a") ;;
    esac
  done
  require_repo
  [ -n "$from" ] && [ -n "$to" ] || die "--from=SUITE and --to=SUITE are required"

  if [ ${#pkgs[@]} -eq 0 ]; then
    mapfile -t pkgs < <(reprepro -b "$REPO" list "$from" | awk '{print $2}' | sort -u)
    [ ${#pkgs[@]} -gt 0 ] || die "$from is empty — nothing to promote"
  fi
  say "Promoting ${#pkgs[@]} package(s): $from -> $to"
  reprepro -b "$REPO" copy "$to" "$from" "${pkgs[@]}"
  ok "promoted: ${pkgs[*]}"
}

cmd_list() { require_repo; reprepro -b "$REPO" list "${1:-trixie}"; }

# ------------------------------------------------------------------- sources
cmd_sources() {
  local suite="${1:-${DRUMEE_APT_SUITES[0]}}"
  cat <<EOF
# /etc/apt/sources.list.d/drumee.sources
Types: deb
URIs: https://apt.drumee.net
Suites: $suite
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/drumee-archive-keyring.gpg
EOF
}

# -------------------------------------------------------------------- verify
# Offline structural checks. `check` below is the one that proves apt agrees.
cmd_verify() {
  local suite="${1:-trixie}" rc=0 arch found
  require_repo
  local rel="$REPO/dists/$suite"

  [ -f "$rel/InRelease" ] && ok "InRelease present ($suite)" \
    || { printf '  FAIL InRelease missing\n'; rc=1; }
  # The PUBLISHED keyring must contain the key the suite is signed with. These are
  # produced at different times — the keyring at init, the signature on every export —
  # so changing SignWith afterwards leaves a repository that verifies fine here (the
  # local keyring has every key) and is unusable by a client, which sees only
  # "Missing key ... needed to verify signature". Caught for real: the pool was
  # re-signed with the flat repository's key and its keyring still held the old one.
  local signwith kr_keys
  signwith="$(awk '/^SignWith:/ {print $2; exit}' "$REPO/conf/distributions" 2>/dev/null)"
  kr_keys="$(gpg --show-keys "$REPO/drumee-archive-keyring.asc" 2>/dev/null | grep -oE '[0-9A-F]{40}')"
  if [ -n "$signwith" ] && printf '%s\n' "$kr_keys" | grep -qx "$signwith"; then
    ok "published keyring carries the signing key"
  else
    printf '  FAIL published keyring does not carry %s (has: %s)\n' \
      "${signwith:-<unset>}" "$(printf '%s' "$kr_keys" | tr '\n' ' ')"; rc=1
  fi

  gpg --verify "$rel/InRelease" >/dev/null 2>&1 \
    && ok "InRelease signature verifies" \
    || { printf '  FAIL InRelease does not verify\n'; rc=1; }

  # Valid-Until is the point of ValidFor; a repository that silently stopped
  # carrying it would let clients trust an arbitrarily stale index.
  if grep -q '^Valid-Until:' "$rel/Release" 2>/dev/null; then
    ok "Valid-Until: $(awk '/^Valid-Until:/{ $1=""; print substr($0,2); exit }' "$rel/Release")"
  else
    printf '  FAIL Release carries no Valid-Until\n'; rc=1
  fi

  # The Architecture: all question: arch-independent packages must appear in
  # every architecture's index even though 'all' is not a listed architecture.
  for arch in amd64 arm64; do
    found=$(zcat -f "$rel/main/binary-$arch/Packages" 2>/dev/null | grep -c '^Package: ' || true)
    printf '       binary-%-6s %s package(s)\n' "$arch" "${found:-0}"
    [ "${found:-0}" -gt 0 ] || rc=1
  done
  [ "$rc" = 0 ] && ok "$suite is consistent" || printf '  FAIL %s\n' "$suite"
  return $rc
}

# --------------------------------------------------------------------- check
# The only check that matters in the end: a stock Debian client, with nothing but
# the published keyring, resolving a package out of this repository. Bind-mounted
# read-only over file://, so it needs no server. Self-SKIPs without Docker.
cmd_check() {
  local suite="${1:-trixie}" pkg="${2:-drumee-infra}"
  require_repo
  if ! command -v docker >/dev/null || ! docker info >/dev/null 2>&1; then
    printf '  SKIP no usable Docker — cannot run the apt client check\n'; return 0
  fi
  say "Resolving $pkg from $suite with a real apt client"
  # --platform is explicit because a locally cached debian:trixie-slim may be
  # another architecture, and apt would then resolve against that one instead.
  # Debian's own sources are left in place: Drumee packages depend on Debian
  # packages, so removing them proves nothing except that binutils is missing.
  docker run --rm --platform=linux/amd64 -v "$REPO:/repo:ro" debian:trixie-slim bash -euc "
    install -d /usr/share/keyrings
    cp /repo/drumee-archive-keyring.gpg /usr/share/keyrings/drumee-archive-keyring.gpg
    printf 'Types: deb\nURIs: file:///repo\nSuites: $suite\nComponents: main\nArchitectures: amd64\nSigned-By: /usr/share/keyrings/drumee-archive-keyring.gpg\n' \
      > /etc/apt/sources.list.d/drumee.sources
    apt-get update -o Acquire::Check-Valid-Until=true 2>&1 | sed 's/^/     /'
    apt-cache policy $pkg | sed 's/^/     /'
    # --print-uris resolves the full dependency graph without downloading, so it
    # proves the index is trusted, parseable and solvable in one step.
    apt-get install -y --no-install-recommends --print-uris $pkg >/dev/null
  " && ok "apt resolved $pkg from $suite" || die "apt could not resolve $pkg from $suite"
}

case "${1:-}" in
  init)    shift; cmd_init "$@" ;;
  include) shift; cmd_include "$@" ;;
  promote) shift; cmd_promote "$@" ;;
  list)    shift; cmd_list "$@" ;;
  verify)  shift; cmd_verify "$@" ;;
  check)   shift; cmd_check "$@" ;;
  sources) shift; cmd_sources "$@" ;;
  *) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; exit 2 ;;
esac
