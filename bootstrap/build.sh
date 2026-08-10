#!/bin/bash
# Build drumee-bootstrap: the per-role entrypoints and healthchecks each Drumee
# container runs, as a versioned package instead of files copied into an image.
#
#   bootstrap/build.sh
#
# What this replaces: `COPY ./opt/drumee/init.d/*` in the old Dockerfiles, which
# injected these scripts outside any dependency graph — unversioned, unreviewable
# as a unit, and impossible to roll back on their own.
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

packagename=drumee-bootstrap
version=$(get_version "$base")
email=$(get_email "$base")
build_dir=$(get_build_dir "${base}/build/$version")

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

say "Staging the payload"
rsync -ar --exclude ".git" "${base}/usr" "$build_dir/files/"

# An entrypoint that is not executable fails at container start with an exec
# error that says nothing about the cause, so set the modes here rather than
# relying on what git recorded.
chmod 0755 "$build_dir"/files/usr/lib/drumee/entrypoint/* \
           "$build_dir"/files/usr/lib/drumee/healthcheck/* \
           "$build_dir"/files/usr/lib/drumee/schemas/init
chmod 0644 "$build_dir/files/usr/lib/drumee/entrypoint/lib.sh"

# Every role must have both an entrypoint and, where it serves traffic, a probe.
# Checked here because a missing role is only discovered when that container is
# first started, which may be a long way from this build.
say "Checking every role has an entrypoint"
missing=""
for role in app web converter dns mail schemas infra; do
  [ -f "$build_dir/files/usr/lib/drumee/entrypoint/$role" ] || missing="$missing $role"
done
[ -z "$missing" ] || { echo "FATAL: no entrypoint for:$missing" >&2; exit 1; }
echo "  app web converter dns mail schemas infra"

say "Verifying the scripts parse"
for f in "$build_dir"/files/usr/lib/drumee/entrypoint/* "$build_dir"/files/usr/lib/drumee/healthcheck/*; do
  sh -n "$f" || { echo "FATAL: $f does not parse" >&2; exit 1; }
done

cd "$build_dir"
package=${packagename}_${version}
say "BUILDING PACKAGE $package IN $build_dir"
dh_make --native --yes --indep --packagename "$package" --email "$email"
for f in "${base}"/debian/*; do
  cp -r "$f" "$build_dir/debian/"
done
# Unsigned: trust comes from the signed APT repository (§4), not from a signature
# on each .deb — same as roles/ and node-runtime/.
dpkg-buildpackage -us -uc -b

copyToTarget "$base/build/${package}"
say "Done: $(ls "${base}/build/${package}"_all.deb 2>/dev/null)"
