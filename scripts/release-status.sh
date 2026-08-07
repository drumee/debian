#!/bin/bash
# Build and sync state at a glance: what this checkout says, next to what is live.
#
#   scripts/release-status.sh              # packages, git, tags, installer
#   scripts/release-status.sh --no-remote  # skip every network call (fast, offline)
#
# LEFT is local, RIGHT is live. "Local" is deliberately three separate facts,
# because they drift independently and each drift has bitten this project:
#
#   manifest  release-manifest.yaml — the only authoritative version statement
#   built     the newest .deb under <pkg>/build/ — a bump with no rebuild ships nothing
#   staged    what apt-repo/Packages advertises — a build that was never staged
#
# and RIGHT is what apt.drumee.net actually serves, which is the only column a user
# ever sees. A green manifest column with a stale live column is the normal shape of
# "I bumped the version and forgot to publish".
#
# Uses git and curl only — no GitHub API, no gh.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$root/release-manifest.yaml"
APT_URL="${APT_URL:-https://apt.drumee.net}"
REMOTE=1
for a in "$@"; do [ "$a" = "--no-remote" ] && REMOTE=0; done

# ANSI only when stdout is a terminal, so piping into a file or a pager stays clean.
if [ -t 1 ]; then R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; D=$'\e[2m'; B=$'\e[1m'; Z=$'\e[0m'
else R=""; G=""; Y=""; D=""; B=""; Z=""; fi

hdr() { printf '\n%s── %s%s\n' "$B" "$1" "$Z"; }
# "?" means we could not look (--no-remote, or the fetch failed); empty means we
# looked and it is not there. Collapsing the two reads as a problem when it is not:
# several components in the manifest are deliberately unpublished.
verdict() { # verdict <local> <live>
  if   [ "$2" = "?" ];  then printf '%sunknown%s'       "$Y" "$Z"
  elif [ -z "$2" ];     then printf '%snot published%s' "$D" "$Z"
  elif [ "$1" = "$2" ]; then printf '%sin sync%s'       "$G" "$Z"
  else                       printf '%sdiffers%s'       "$R" "$Z"; fi
}

# Same mapping as scripts/check-versions.sh. Kept in step by hand rather than
# sourced, because that script runs work on load; if it ever grows a library half,
# use it here instead of copying.
component_dir() {
  case "$1" in
    server-pod) echo server ;;
    ui-pod)     echo ui ;;
    patch)      echo schemas-patch ;;
    installer)  echo builder ;;
    *)          echo "$1" ;;
  esac
}

# Highest version for a package in a flat Packages file. sort -V, not tail: the file
# keeps every version ever published, and a string sort puts 1.0.9 after 1.0.20.
highest() { # highest <packages-file> <pkg>
  [ -s "$1" ] || { echo ""; return; }
  awk -v P="$2" '/^Package:/{p=$2} /^Version:/{if(p==P) print $2}' "$1" \
    | sort -V | tail -1
}

live_packages="$(mktemp)"; trap 'rm -f "$live_packages"' EXIT
if [ "$REMOTE" = 1 ]; then
  curl -fsSL --max-time 25 "$APT_URL/Packages" -o "$live_packages" 2>/dev/null \
    || : > "$live_packages"
fi

# ---------------------------------------------------------------- packages
hdr "packages — local vs $APT_URL"
printf '  %-24s %-9s %-9s %-9s   %-9s %s\n' "" "manifest" "built" "staged" "LIVE" ""
while read -r name version; do
  [ -n "$name" ] || continue
  dir="$(component_dir "$name")"
  cl="$root/$dir/debian/changelog"
  [ -f "$cl" ] || continue
  pkg="$(head -1 "$cl" | awk '{print $1}')"

  built="$(find "$root/$dir/build" -maxdepth 2 -name "${pkg}_*.deb" -printf '%f\n' 2>/dev/null \
    | sed -E "s/^${pkg}_(.+)_[a-z0-9]+\.deb$/\1/" | sort -V | tail -1)"
  staged="$(highest "$root/apt-repo/Packages" "$pkg")"
  live="$(highest "$live_packages" "$pkg")"
  [ "$REMOTE" = 1 ] || live="?"

  label="$pkg"; [ "$name" = meta ] && label="$pkg (release train)"
  printf '  %-24s %-9s %-9s %-9s   %-9s %s\n' \
    "$label" "$version" "${built:--}" "${staged:--}" "${live:--}" "$(verdict "$version" "$live")"
done < <(sed -E 's/#.*$//' "$manifest" | tr -d '\r' \
  | awk '/^components:/ {inc=1; next}
         /^[^[:space:]#]/ {inc=0}
         inc && NF==2 {gsub(/:$/,"",$1); print $1, $2}')

# ---------------------------------------------------------------- installer
# debian.sh is served from the flat repo, and publish-apt.sh does NOT copy it —
# only publish-site.sh does. So it silently goes stale while packages publish fine,
# and the documented `curl … | sudo bash` then installs with the previous flow.
# Checked under the current name; publish-site.sh also serves baremetal.sh and
# install-native.sh as byte-identical aliases for URLs already in circulation.
hdr "installer (bootstrap script)"
local_bm="$root/scripts/debian.sh"
lsum="$(sha256sum "$local_bm" 2>/dev/null | cut -c1-12)"
llines="$(wc -l < "$local_bm" 2>/dev/null | tr -d ' ')"
if [ "$REMOTE" = 1 ]; then
  tmp_bm="$(mktemp)"
  if curl -fsSL --max-time 25 "$APT_URL/debian.sh" -o "$tmp_bm" 2>/dev/null; then
    rsum="$(sha256sum "$tmp_bm" | cut -c1-12)"; rlines="$(wc -l < "$tmp_bm" | tr -d ' ')"; rcell=""
  elif [ "$?" = 22 ]; then
    # curl exit 22 with -f is an HTTP >= 400: we reached the server and it does not
    # have this path. That is "not published", not "could not look" — the distinction
    # matters right after a rename, when the new URL genuinely is not there yet.
    rsum=""; rcell="not on the server"
  else rsum="?"; rcell="?"; fi
  rm -f "$tmp_bm"
else rsum="?"; rcell="?"; fi
: "${rcell:=$rlines lines  $rsum}"
printf '  %-24s %-38s %-24s %s\n' "debian.sh" "$llines lines  $lsum" \
  "$rcell" "$(verdict "$lsum" "$rsum")"

# ---------------------------------------------------------------- git
hdr "git — working tree vs origin"
for r in "$root" "$root/../setup-infra" "$root/../setup-schemas" "$root/../drumee.github.io"; do
  [ -d "$r/.git" ] || continue
  name="$(basename "$(cd "$r" && pwd)")"
  br="$(git -C "$r" branch --show-current 2>/dev/null)"
  dirty="$(git -C "$r" status --porcelain 2>/dev/null | grep -vc '^$')"
  ahead="-"; behind="-"; rhead="no upstream"
  if git -C "$r" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    ahead="$(git -C "$r" rev-list --count '@{u}..HEAD' 2>/dev/null)"
    behind="$(git -C "$r" rev-list --count 'HEAD..@{u}' 2>/dev/null)"
    rhead="$(git -C "$r" rev-parse --short '@{u}' 2>/dev/null)"
  fi
  # Reported in severity order, worst last, so the tail of the line is the thing to
  # act on. `behind` matters as much as `ahead`: it means someone else pushed and this
  # checkout would build from a stale tree.
  state="$G""in sync""$Z"
  [ "$dirty"  != 0 ] && [ "$dirty"  != "-" ] && state="$Y$dirty uncommitted$Z"
  [ "$behind" != 0 ] && [ "$behind" != "-" ] && state="$Y$behind behind origin$Z"
  [ "$ahead"  != 0 ] && [ "$ahead"  != "-" ] && state="$R$ahead unpushed$Z"
  if [ "$ahead" != "-" ] && [ "$ahead" != 0 ] && [ "$behind" != 0 ]; then
    state="${R}diverged +$ahead/-$behind${Z}"
  fi
  printf '  %-24s %-38s %-24s %s\n' "$name" \
    "$br @ $(git -C "$r" rev-parse --short HEAD 2>/dev/null)" "origin @ $rhead" "$state"
done

# ---------------------------------------------------------------- tags
# Compared against the remote with git ls-remote, so a tag that exists only locally
# shows up: the packages are published from a tagged tree, and an unpushed tag means
# nobody else can identify what is running.
hdr "release tags"
if [ "$REMOTE" = 1 ]; then
  remote_tags="$(git -C "$root" ls-remote --tags origin 2>/dev/null \
    | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+$' | sort -Vu)"
else remote_tags=""; fi
local_tags="$(git -C "$root" tag --list 'v*' | sort -Vu)"
for t in $(printf '%s\n%s\n' "$local_tags" "$remote_tags" | sort -Vu | grep -v '^$'); do
  l="-"; printf '%s\n' "$local_tags"  | grep -qx "$t" && l="$t"
  if [ "$REMOTE" = 1 ]; then
    m="-"; printf '%s\n' "$remote_tags" | grep -qx "$t" && m="$t"
  else m="?"; fi
  printf '  %-24s %-38s %-24s %s\n' "$t" "$l" "$m" "$(verdict "$l" "$m")"
done
[ -n "$local_tags$remote_tags" ] || echo "  (no v* tags)"

# ---------------------------------------------------------------- staged vs served
# The only check that compares FILES rather than versions, and the one that catches a
# staged repo that was signed but never uploaded. Needs ssh; skipped without it.
hdr "flat repo — apt-repo/ vs the server"
if [ "$REMOTE" = 1 ] && [ -d "$root/apt-repo" ] && [ -n "${APT_SSH_HOST:-debian@apt.drumee.net}" ]; then
  host="${APT_SSH_HOST:-debian@apt.drumee.net}"
  out="$(timeout 90 rsync -az --dry-run --delete \
          --exclude='dists/' --exclude='pool/' \
          "$root/apt-repo/" "$host:${APT_REPO_DIR:-/var/www/apt.drumee.net}/" 2>/dev/null)" || out="__FAIL__"
  if [ "$out" = "__FAIL__" ]; then
    printf '  %-24s %-38s %-24s %s\n' "rsync dry-run" "apt-repo/" "$host" "${Y}unreachable${Z}"
  else
    xfer="$(printf '%s\n' "$out" | grep -cE '\.deb$|^(In)?Release|^Packages')"
    del="$(printf '%s\n' "$out" | grep -c '^deleting')"
    v="${G}in sync${Z}"; [ "$xfer" != 0 ] && v="${R}$xfer to upload${Z}"
    [ "$del" != 0 ] && v="$v ${R}$del would be DELETED${Z}"
    printf '  %-24s %-38s %-24s %s\n' "rsync dry-run" "apt-repo/" "$host" "$v"
  fi
else
  printf '  %-22s %s\n' "rsync dry-run" "${D}skipped${Z}"
fi

echo
