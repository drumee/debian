#!/bin/bash
# Build drumee-archive-keyring: the public keys apt uses to verify apt.drumee.net.
#
#   keyring/build.sh
#
# The keyring is assembled from the ARMOURED KEYS COMMITTED under keyring/keys/, not
# exported from the build host's GnuPG keyring. Two reasons: the contents are then
# reviewable in a diff, and every builder produces the same package. A keyring built
# from "whatever key this machine happens to trust" is exactly how a repository ends
# up shipping a key nobody chose.
#
# To rotate: add the new public key to keyring/keys/, bump the version, and release.
# The new key reaches clients through this package. Only AFTER that has landed should
# the repository start signing with it — otherwise every client sees a signature made
# by a key it does not have yet. Keep the outgoing key here until the fleet has
# upgraded; a keyring may hold several.
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

packagename=drumee-archive-keyring
version=$(get_version "$base")
email=$(get_email "$base")
build_dir=$(get_build_dir "${base}/build/$version")

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

shopt -s nullglob
keys=("$base"/keys/*.asc)
shopt -u nullglob
[ ${#keys[@]} -gt 0 ] || { echo "FATAL: no keys in $base/keys/*.asc" >&2; exit 1; }

say "Assembling the keyring from ${#keys[@]} committed key(s)"
dest="$build_dir/files/usr/share/keyrings"
mkdir -p "$dest"

# --dearmor rather than --export: no keyring is touched and no trust database is
# consulted, so the output depends only on the committed files.
cat "${keys[@]}" | gpg --dearmor > "$dest/$packagename.gpg"
cat "${keys[@]}" > "$dest/$packagename.asc"

# Report what went in, so a release that changed the key set says so in its log
# rather than only in a diff.
for k in "${keys[@]}"; do
  # `expiry`, not `exp` — exp() is an awk built-in and assigning to it is a syntax
  # error, which under set -e aborted the build here.
  gpg --show-keys --with-colons "$k" 2>/dev/null | awk -F: '
    /^pub/ { fpr=""; expiry=$7 }
    /^fpr/ && fpr=="" { fpr=$10 }
    /^uid/ { printf "     %s  %s%s\n", substr(fpr,1,16), $10,
                    (expiry=="" ? "  (no expiry)" : "  expires " strftime("%Y-%m-%d", expiry)) }'
done

# A keyring apt cannot read is worse than none: apt reports the repository as
# unsigned, which reads as a repository problem. Verify it parses before shipping.
gpg --no-default-keyring --keyring "$dest/$packagename.gpg" --list-keys >/dev/null 2>&1 \
  || { echo "FATAL: the assembled keyring is not readable by gpg" >&2; exit 1; }
echo "  keyring parses; $(gpg --no-default-keyring --keyring "$dest/$packagename.gpg" --list-keys --with-colons 2>/dev/null | grep -c '^pub') key(s) inside"

cd "$build_dir"
package=${packagename}_${version}
say "BUILDING PACKAGE $package IN $build_dir"
dh_make --native --yes --indep --packagename "$package" --email "$email"
for f in "${base}"/debian/*; do
  cp -r "$f" "$build_dir/debian/"
done
# Unsigned, like roles/ and node-runtime/: trust comes from the signed APT repository,
# not from a signature on the .deb.
dpkg-buildpackage -us -uc -b

copyToTarget "$base/build/${package}"
say "Done: $(ls "${base}/build/${package}"_all.deb 2>/dev/null)"
