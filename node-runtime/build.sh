#!/bin/bash
# Build drumee-node-runtime: the pinned set of global Node modules Drumee's roles
# expect, packaged so the set is versioned instead of resolved at image-build time
# by an unpinned `npm install -g`.
#
#   node-runtime/build.sh
#
# The payload comes from `npm ci` against the COMMITTED package-lock.json, so the
# same package version always contains the same modules. All dependencies are
# public: no @drumee registry access, and therefore no NPM_TOKEN in CI.
#
# Env: DEB_BUILD_TARGET (copy the .deb there)
set -e
if [ "$UID" = "0" ]; then
  echo "You should not run this builder with root privilege"
  exit 1
fi

base="$(dirname "$(readlink -f "$0")")"
source "${base}/../utils/env.sh"
source "${base}/../utils/functions.sh"

packagename=drumee-node-runtime
prefix=usr/lib/drumee/node-runtime

version=$(get_version "$base")
email=$(get_email "$base")
build_dir=$(get_build_dir "${base}/build/$version")

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

[ -f "$base/package-lock.json" ] || {
  echo "FATAL: package-lock.json is missing — the point of this package is that" >&2
  echo "  the module set is locked. Regenerate with: npm install --package-lock-only" >&2
  exit 1; }

say "Installing the locked module set (npm ci)"
( cd "$base" && npm ci --omit=dev --no-audit --no-fund >/dev/null )

# --- the Architecture: all claim, enforced -----------------------------------
# debian/control says Architecture: all, which promises an identical payload on
# every architecture. Verify it instead of trusting it: if a dependency ever
# pulls in native code, the amd64 build would otherwise ship an amd64 binary to
# arm64 hosts under an `all` label, and fail at require() with no dpkg error.
say "Checking the payload is architecture independent"
addons=$(find "$base/node_modules" -name '*.node' -type f 2>/dev/null | head -5)
elf=$(find "$base/node_modules" -type f -perm -u+x -exec sh -c 'head -c4 "$1" | grep -q "ELF" && echo "$1"' _ {} \; 2>/dev/null | head -5)
if [ -n "$addons$elf" ]; then
  echo "FATAL: the payload contains compiled objects, so Architecture: all is wrong." >&2
  printf '  %s\n' $addons $elf >&2
  echo "  Either drop the offending dependency, or change debian/control to" >&2
  echo "  Architecture: any and build once per architecture." >&2
  exit 1
fi
echo "  no .node addons, no ELF executables — Architecture: all holds"

say "Assembling the payload"
mkdir -p "$build_dir/files/$prefix"
# -a preserves the relative symlinks in node_modules/.bin, which is how the
# module set exposes its executables.
cp -a "$base/node_modules" "$build_dir/files/$prefix/"
cp -a "$base/package.json" "$base/package-lock.json" "$build_dir/files/$prefix/"

# The supervisor has to be callable by name from the role entrypoints, so expose
# just those two rather than every .bin symlink.
mkdir -p "$build_dir/files/usr/bin"
for exe in pm2 pm2-runtime; do
  ln -sf "/$prefix/node_modules/.bin/$exe" "$build_dir/files/usr/bin/$exe"
done

cd "$build_dir"
package=${packagename}_${version}
say "BUILDING PACKAGE $package IN $build_dir"
dh_make --native --yes --indep --packagename "$package" --email "$email"
for f in "${base}"/debian/*; do
  cp -r "$f" "$build_dir/debian/"
done
# Unsigned, like roles/: trust for the container channel comes from the signed
# APT repository (§4) and from cosign on the images (§8), not from a signature on
# each .deb. Requiring a maintainer key here would also stop anyone without it
# from building — the native builders still sign because that channel predates
# the repository signing.
dpkg-buildpackage -us -uc -b

copyToTarget "$base/build/${package}"
say "Done: $(ls "${base}/build/${package}"_all.deb 2>/dev/null)"
