#!/bin/bash
# Generate meta/debian/control with component dependencies PINNED to the exact
# versions in release-manifest.yaml, and the metapackage version set to `product`.
#
# This makes `apt install drumee` resolve a *coherent set* (every component at the
# release-train version) instead of whatever happens to be newest per component.
#
#   meta/make-control.sh            # regenerate control + changelog from the manifest
#   meta/make-control.sh --check    # non-zero exit if they are out of sync (CI guard)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$root/release-manifest.yaml"
control="$root/meta/debian/control"
changelog="$root/meta/debian/changelog"
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1

# Reads the nested manifest: `release` at top level, everything else under
# `components:`. Keys there are component names (server-pod), not directories.
mver() { sed -E 's/#.*$//' "$manifest" | awk -F': *' -v k="$1" '
  {gsub(/^[[:space:]]+/,"",$1)} $1==k {gsub(/[[:space:]]+$/,"",$2); print $2; exit}'; }
PRODUCT="$(mver release)"
[ -n "$PRODUCT" ] || { echo "error: no 'release:' in $manifest" >&2; exit 1; }

# exact-pin each runtime component to its manifest version
dep() { printf '  drumee-%s (= %s)' "$1" "$(mver "$2")"; }
gen_control() {
  cat <<EOF
Source: drumee
Section: non-free
Priority: optional
Maintainer: Somanos Sar <somanos.sar@drumee.com>
Build-Depends: debhelper (>= 11)
Standards-Version: $PRODUCT
Homepage: https://drumee.org

Package: drumee
Architecture: all
Depends: \${misc:Depends},
$(dep infra infra),
$(dep schemas schemas),
$(dep static static),
$(dep server-pod server-pod),
$(dep ui-pod ui-pod)
Description: Drumee sovereign data platform (metapackage)
 Installs the full Drumee runtime: infrastructure, database schemas, static
 assets, backend server and frontend UI. This metapackage pins every component
 to the release-train version ($PRODUCT) so the set installs coherently.
 .
 For unattended installs, preseed answers first:
 debconf-set-selections < install.conf  (see config/render.mjs).
EOF
}

if [ "$CHECK" = 1 ]; then
  cur_ver="$(head -1 "$changelog" 2>/dev/null | sed -E 's/^[^(]*\(([^)]+)\).*/\1/')"
  if ! diff -q <(gen_control) "$control" >/dev/null 2>&1; then
    echo "meta/debian/control is out of sync with release-manifest.yaml — run meta/make-control.sh" >&2; exit 1
  fi
  [ "$cur_ver" = "$PRODUCT" ] || { echo "meta changelog $cur_ver != product $PRODUCT — run meta/make-control.sh" >&2; exit 1; }
  echo "meta package pinned to product $PRODUCT, deps match manifest."; exit 0
fi

gen_control > "$control"
echo "wrote $control (deps pinned to manifest, product=$PRODUCT)"

# keep the metapackage changelog version == product
cur_ver="$(head -1 "$changelog" 2>/dev/null | sed -E 's/^[^(]*\(([^)]+)\).*/\1/')"
if [ "$cur_ver" != "$PRODUCT" ]; then
  maint="$(grep -m1 -E '^ -- ' "$changelog" 2>/dev/null | sed -E 's/^ -- //; s/  .*$//')"
  tmp="$(mktemp)"
  printf 'drumee (%s) stable; urgency=medium\n\n  * Release %s\n\n -- %s  %s\n\n' \
    "$PRODUCT" "$PRODUCT" "${maint:-Drumee <release@drumee.org>}" "$(date -R)" > "$tmp"
  cat "$changelog" >> "$tmp" 2>/dev/null || true
  mv "$tmp" "$changelog"
  echo "prepended meta changelog entry for $PRODUCT"
fi
