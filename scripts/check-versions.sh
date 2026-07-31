#!/bin/bash
# Verify each package's debian/changelog version matches release-manifest.yaml.
# Drift guard for CI. Use --sync to rewrite changelog top lines to the manifest.
#
#   scripts/check-versions.sh         # check only (non-zero exit on drift)
#   scripts/check-versions.sh --sync  # prepend a manifest-matching changelog entry
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$root/release-manifest.yaml"
[ -f "$manifest" ] || { echo "missing $manifest" >&2; exit 1; }
SYNC=0; [ "${1:-}" = "--sync" ] && SYNC=1

# component name (manifest) -> directory that builds it. Anything not listed
# maps to a directory of the same name. Components with no directory yet are
# skipped by the missing-changelog branch below, which is how the packages
# created in increment 3 can be versioned here before they exist.
component_dir() {
  case "$1" in
    server-pod) echo server ;;
    ui-pod)     echo ui ;;
    patch)      echo schemas-patch ;;
    installer)  echo builder ;;
    *)          echo "$1" ;;
  esac
}

drift=0
while read -r name version; do
  [ -n "$name" ] || continue
  dir="$(component_dir "$name")"
  cl="$root/$dir/debian/changelog"
  [ -f "$cl" ] || { echo "WARN no changelog for $dir"; continue; }
  pkg="$(head -1 "$cl" | awk '{print $1}')"
  cur="$(head -1 "$cl" | sed -E 's/^[^(]*\(([^)]+)\).*/\1/')"
  # The manifest states the COMPONENT version; a Debian revision (-1~trixie1) is
  # packaging metadata that can change without the component changing. Compare
  # upstream against upstream, and keep the revision when syncing. Only when the
  # manifest itself carries no revision — if it ever does, compare verbatim.
  rev=""
  cur_upstream="$cur"
  case "$version" in
    *-*) : ;;
    *) case "$cur" in *-*) rev="-${cur##*-}"; cur_upstream="${cur%-*}" ;; esac ;;
  esac
  if [ "$cur_upstream" = "$version" ]; then
    printf '  ok   %-14s %s %s\n' "$dir" "$pkg" "$version"
  elif [ "$SYNC" = 1 ]; then
    printf '  sync %-14s %s %s -> %s\n' "$dir" "$pkg" "$cur" "$version$rev"
    # Reuse the maintainer of the previous entry. Read leniently — some existing
    # changelogs here put the trailer at column 0 instead of the ' -- ' the format
    # requires — but always WRITE the conforming form. Matching strictly used to
    # yield an empty maintainer and an entry dpkg-parsechangelog refuses, which
    # surfaced only at build time, well away from the sync that caused it.
    maint="$(grep -m1 -E '^ ?-- .*<.*>' "$cl" | sed -E 's/^ ?-- //; s/  +[A-Z][a-z][a-z],.*$//')"
    if [ -z "$maint" ] && [ -n "${DEBFULLNAME:-}" ] && [ -n "${DEBEMAIL:-}" ]; then
      maint="$DEBFULLNAME <$DEBEMAIL>"
    fi
    if [ -z "$maint" ]; then
      maint="$(git -C "$root" config user.name) <$(git -C "$root" config user.email)>"
    fi
    case "$maint" in
      *"<"*">"*) : ;;
      *) echo "FATAL cannot determine the maintainer for $dir; set DEBFULLNAME and DEBEMAIL" >&2
         exit 1 ;;
    esac
    tmp="$(mktemp)"
    {
      printf '%s (%s) stable; urgency=medium\n\n  * Release %s (synced from release-manifest.yaml)\n\n -- %s  %s\n\n' \
        "$pkg" "$version$rev" "$version" "$maint" "$(date -R)"
      cat "$cl"
    } > "$tmp"
    mv "$tmp" "$cl"
  else
    printf '  DRIFT %-13s %s changelog=%s manifest=%s\n' "$dir" "$pkg" "$cur" "$version"
    drift=1
  fi
done < <(sed -E 's/#.*$//' "$manifest" | tr -d '\r' \
  | awk '/^components:/ {inc=1; next}
         /^[^[:space:]#]/ {inc=0}
         inc && NF==2 {gsub(/:$/,"",$1); print $1, $2}')

# The metapackage tracks `release` by definition, so it is checked against that
# rather than against a components entry — meta/make-control.sh writes both.
rel="$(sed -E 's/#.*$//' "$manifest" | awk -F': *' '$1=="release"{print $2; exit}')"
meta_cl="$root/meta/debian/changelog"
if [ -n "$rel" ] && [ -f "$meta_cl" ]; then
  cur="$(head -1 "$meta_cl" | sed -E 's/^[^(]*\(([^)]+)\).*/\1/')"
  if [ "$cur" = "$rel" ]; then
    printf '  ok   %-14s %s %s\n' "release" "drumee" "$rel"
  else
    printf '  DRIFT %-13s drumee changelog=%s release=%s\n' "release" "$cur" "$rel"
    drift=1
  fi
fi

[ "$drift" = 0 ] || { echo "version drift detected — bump release-manifest.yaml or run --sync" >&2; exit 1; }
echo "all package versions match the release manifest."
