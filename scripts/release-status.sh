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
#   staged    what apt-pool/ (reprepro) advertises — a build that was never included
#
# and RIGHT is what apt.drumee.net actually serves, which is the only column a user
# ever sees. A green manifest column with a stale live column is the normal shape of
# "I bumped the version and forgot to publish".
#
# Both read the POOL layout (dists/<suite>/<component>/binary-<arch>/Packages), not the
# flat one. The flat repository is frozen at 1.0.22 on purpose, so reading it made every
# current package report "differs" against a repository nobody is meant to install from
# — a status tool answering about the wrong repository is worse than no status tool. The
# flat repo still gets its own section at the bottom, labelled as frozen.
#
# The arch column exists because an arch:all package is filed into every architecture's
# index while an arch:any one is filed only where it was built. drumee-server-pod became
# Architecture: any at 2.9.98 (amd64 only), so "amd64" there is correct and "amd64+arm64"
# would be the bug — see docs/distribution.md §9.1.
#
# Uses git and curl only — no GitHub API, no gh.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$root/release-manifest.yaml"
APT_URL="${APT_URL:-https://apt.drumee.net}"
POOL_SUITE="${POOL_SUITE:-trixie}"
POOL_COMPONENT="${POOL_COMPONENT:-main}"
POOL_ARCHES="${POOL_ARCHES:-amd64 arm64}"
REMOTE=1
for a in "$@"; do [ "$a" = "--no-remote" ] && REMOTE=0; done

# ANSI only when stdout is a terminal, so piping into a file or a pager stays clean.
if [ -t 1 ]; then R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; D=$'\e[2m'; B=$'\e[1m'; Z=$'\e[0m'
else R=""; G=""; Y=""; D=""; B=""; Z=""; fi

hdr() { printf '\n%s── %s%s\n' "$B" "$1" "$Z"; }
# "?" means we could not look (--no-remote, or the fetch failed); empty means we
# looked and it is not there. Collapsing the two reads as a problem when it is not:
# several components in the manifest are deliberately unpublished.
# The Debian revision is not part of the upstream version, so it must not decide the
# verdict. roles/ is versioned <release>-1~<channel>1, so a correctly published
# 1.0.55-1~trixie1 compared literally against the manifest's 1.0.55 reads "differs" —
# a red row on a release that is exactly right, which trains the reader to ignore the
# column that matters.
# Placeholders pass through untouched: "-" and "?" are not versions, and ${x%%-*} turns a
# bare "-" into the empty string, which silently erased the "not published" placeholder
# from three columns.
upstream_of() {
  case "$1" in
    -|?|'') printf '%s' "$1" ;;
    *)      printf '%s' "${1%%-*}" ;;
  esac
}

verdict() { # verdict <local> <live>
  local a b; a="$(upstream_of "$1")"; b="$(upstream_of "$2")"
  if   [ "$2" = "?" ];  then printf '%sunknown%s'       "$Y" "$Z"
  elif [ -z "$2" ];     then printf '%snot published%s' "$D" "$Z"
  elif [ "$a" = "$b" ]; then printf '%sin sync%s'       "$G" "$Z"
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

# One index file per architecture, for each side. Kept per-arch rather than
# concatenated because the arch column needs to know which one a version came from.
tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT
for a in $POOL_ARCHES; do
  : > "$tmpd/live.$a"
  [ "$REMOTE" = 1 ] || continue
  curl -fsSL --max-time 25 \
    "$APT_URL/dists/$POOL_SUITE/$POOL_COMPONENT/binary-$a/Packages" \
    -o "$tmpd/live.$a" 2>/dev/null || : > "$tmpd/live.$a"
done

pool_index() { # pool_index <arch>  -> path to the local staged index
  echo "$root/apt-pool/dists/$POOL_SUITE/$POOL_COMPONENT/binary-$1/Packages"
}

# Highest version across every architecture, plus which arches carry it.
across() { # across <prefix|local> <pkg>  -> "<version> <arch,arch>"
  local kind="$1" pkg="$2" a v best="" arches=""
  for a in $POOL_ARCHES; do
    if [ "$kind" = local ]; then v="$(highest "$(pool_index "$a")" "$pkg")"
    else                        v="$(highest "$tmpd/live.$a" "$pkg")"; fi
    [ -n "$v" ] || continue
    if [ -z "$best" ] || [ "$v" = "$(printf '%s\n%s\n' "$best" "$v" | sort -V | tail -1)" ]; then
      [ "$v" = "$best" ] || arches=""
      best="$v"
    fi
    [ "$v" = "$best" ] && arches="${arches:+$arches+}$a"
  done
  # A sentinel, not an empty first field: `read` collapses leading whitespace, so
  # "" plus "-" arrives as version="-" and the "not published" verdict is lost.
  echo "${best:-__NONE__} ${arches:--}"
}

# ---------------------------------------------------------------- packages
hdr "packages — local vs $APT_URL ($POOL_SUITE/$POOL_COMPONENT)"
printf '  %-24s %-9s %-9s %-9s   %-9s %-12s %s\n' \
  "" "manifest" "built" "staged" "LIVE" "live arch" ""
while read -r name version; do
  [ -n "$name" ] || continue
  dir="$(component_dir "$name")"
  cl="$root/$dir/debian/changelog"
  [ -f "$cl" ] || continue
  pkg="$(head -1 "$cl" | awk '{print $1}')"

  # The changelog's first field is the SOURCE package name, which for most components is
  # also the binary name. `roles` is the exception: it is one source producing
  # drumee-release plus seven drumee-role-* binaries, and "drumee-roles" appears in no
  # Packages index anywhere. Left alone, that row read "not published" forever — including
  # immediately after a release in which the roles demonstrably published, verified with a
  # real apt client. A row that is permanently wrong is worse than no row, because this
  # table is the thing that answers "is what I have what users get".
  #
  # drumee-release is the right stand-in: every role Depends on it at strict equality, so
  # if it is live at the train version the set is coherent by construction. The role count
  # is reported separately below, because equality alone cannot show a PARTIAL publish.
  binpkg="$pkg"; debdir="$root/$dir/build"
  if [ "$name" = roles ]; then
    binpkg=drumee-release
    # roles/build.sh leaves its .deb files beside the source tree, where dpkg-buildpackage
    # puts them, not under roles/build/.
    debdir="$root"
  fi

  built="$(find "$debdir" -maxdepth 2 -name "${binpkg}_*.deb" -printf '%f\n' 2>/dev/null \
    | sed -E "s/^${binpkg}_(.+)_[a-z0-9]+\.deb$/\1/" | sort -V | tail -1)"
  read -r staged _        < <(across local "$binpkg")
  read -r live live_arch  < <(across live  "$binpkg")
  [ "$staged" = __NONE__ ] && staged=""
  [ "$live"   = __NONE__ ] && live=""
  if [ "$REMOTE" != 1 ]; then live="?"; live_arch="?"; fi

  label="$pkg"; [ "$name" = meta ] && label="$pkg (release train)"
  [ "$name" = roles ] && label="$pkg -> release"
  # Displayed WITHOUT the Debian revision, for the same reason the verdict ignores it, plus
  # one of its own: 1.0.55-1~trixie1 is 17 characters in a 9-wide column, and one long cell
  # shifts every field after it so the whole row stops lining up with the header.
  printf '  %-24s %-9s %-9s %-9s   %-9s %-12s %s\n' \
    "$label" "$(upstream_of "$version")" "$(upstream_of "${built:--}")" \
    "$(upstream_of "${staged:--}")" "$(upstream_of "${live:--}")" "${live_arch:--}" \
    "$(verdict "$version" "$live")"
done < <(sed -E 's/#.*$//' "$manifest" | tr -d '\r' \
  | awk '/^components:/ {inc=1; next}
         /^[^[:space:]#]/ {inc=0}
         inc && NF==2 {gsub(/:$/,"",$1); print $1, $2}')

# The seven roles, counted rather than inferred. drumee-release being live says the train
# is coherent; it cannot say every role reached the repository, and a role missing from the
# index is invisible until someone tries to build that image.
roles_expected="app web converter dns mail schemas infra"
roles_want=$(echo $roles_expected | wc -w)
roles_live=0; roles_missing=""
for r in $roles_expected; do
  read -r v _ < <(across live "drumee-role-$r")
  if [ "$v" != "__NONE__" ]; then roles_live=$((roles_live+1)); else roles_missing="$roles_missing $r"; fi
done
if [ "$REMOTE" = 1 ]; then
  if [ "$roles_live" = "$roles_want" ]; then
    printf '  %-26s %-9s %-9s %-9s   %-9s %-12s %s\n' \
      "  └ role packages" "$roles_want" "" "" "$roles_live" "" "all live"
  else
    printf '  %-26s %-9s %-9s %-9s   %-9s %-12s %s\n' \
      "  └ role packages" "$roles_want" "" "" "$roles_live" "" "MISSING:$roles_missing"
  fi
fi

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
# pool/ is checked without --delete, exactly as deploy-apt-repo.sh uploads it: the
# artifacts are immutable and older indices still reference them, so a file present
# on the server and absent locally is normal rather than drift.
hdr "pool repo — apt-pool/ vs the server"
if [ "$REMOTE" = 1 ] && [ -d "$root/apt-pool/dists" ] && [ -n "${APT_SSH_HOST:-debian@apt.drumee.net}" ]; then
  host="${APT_SSH_HOST:-debian@apt.drumee.net}"
  for sub in pool dists; do
    del=(); [ "$sub" = dists ] && del=(--delete)
    out="$(timeout 90 rsync -az --dry-run "${del[@]}" \
            "$root/apt-pool/$sub/" "$host:${APT_REPO_DIR:-/var/www/apt.drumee.net}/$sub/" 2>/dev/null)" \
      || out="__FAIL__"
    if [ "$out" = "__FAIL__" ]; then
      printf '  %-24s %-38s %-24s %s\n' "rsync dry-run $sub/" "apt-pool/$sub/" "$host" "${Y}unreachable${Z}"
      continue
    fi
    xfer="$(printf '%s\n' "$out" | grep -cE '\.deb$|^(In)?Release|^Packages')"
    d="$(printf '%s\n' "$out" | grep -c '^deleting')"
    v="${G}in sync${Z}"; [ "$xfer" != 0 ] && v="${R}$xfer to upload${Z}"
    [ "$d" != 0 ] && v="$v ${R}$d would be DELETED${Z}"
    printf '  %-24s %-38s %-24s %s\n' "rsync dry-run $sub/" "apt-pool/$sub/" "$host" "$v"
  done
else
  printf '  %-22s %s\n' "rsync dry-run" "${D}skipped${Z}"
fi

# The flat layout is FROZEN at 1.0.22 and served only so already-installed boxes keep
# working; they are migrated by hand. "in sync" here means the frozen bytes are intact,
# NOT that the current release is published — that is the pool section above.
hdr "flat repo (frozen — kept for pre-pool installs) vs the server"
if [ "$REMOTE" = 1 ] && [ -d "$root/apt-repo" ] && [ -n "${APT_SSH_HOST:-debian@apt.drumee.net}" ]; then
  host="${APT_SSH_HOST:-debian@apt.drumee.net}"
  frozen="$(highest "$root/apt-repo/Packages" drumee)"
  printf '  %-24s %s\n' "frozen at" "${D}drumee ${frozen:-?}${Z}"
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
