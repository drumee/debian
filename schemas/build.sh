#!/bin/bash

set -e
if [ "$UID" == "0" ]; then
  echo "You should not run this builder with root privilege"
  exit 1
fi

base="$(dirname "$(readlink -f "$0")")"
packagename=drumee-schemas
source ${base}/../utils/env.sh
source ${base}/../utils/functions.sh

version=$(get_version $base)
email=$(get_email $base)
echo EMAIL ${base} $email $version
build_dir=$(get_build_dir ${base}/build/$version)

REPO_BASE=git@github.com:drumee
bundle $base "setup-schemas" "main" "" "var/lib/drumee/setup-schemas"
# fix/neutral-templates, not preview: it carries the regenerated host-neutral
# templates (no dev-box rows, no baked /data/mfs roots, intact trigger DDL) and
# the strip_definer fix. Move this back to preview once that branch merges.
bundle $base "schemas" "fix/neutral-templates" "" ""
schemas_src=${base}/src/schemas

# --- seed resolution ---------------------------------------------------------
# The package must ship a mariabackup snapshot at var/tmp/drumee/seeds.tgz.
# Resolution order: reuse an existing seed -> archive $SEEDS_DIR -> build one
# offline from source (scripts/build-seed.sh: throwaway MariaDB + offline/factory
# stocks the pool + mariabackup). See docs/reproducible-builds.md.
if [ "$SEEDS_DIR" = "" ]; then
  SEEDS_DIR=$HOME/docker/data/seeds/
fi
SEEDS_FILE=${base}/var/tmp/drumee/seeds.tgz
if [[ $0 =~ rebuild ]]; then
  echo Removing existing seeds
  rm -f $SEEDS_FILE
fi

if [ -f $SEEDS_FILE ]; then
  echo Already have seeds file. Skipped
elif [ -d "$SEEDS_DIR" ]; then
  cd $SEEDS_DIR
  echo Creating seeds $SEEDS_FILE
  tar zcfp $SEEDS_FILE .
else
  echo "No prebuilt seed and no SEEDS_DIR ($SEEDS_DIR) — building one offline"
  # server-team supplies offline/factory + @drumee node_modules; default to the
  # sibling checkout, honour SERVER_SRC if the caller set it.
  export SERVER_SRC="${SERVER_SRC:-$(cd "$base/../.." && pwd)/server-team}"
  if ! ${base}/../scripts/build-seed.sh --out=$SEEDS_FILE; then
    echo "FATAL: offline seed build failed. Provide a seed instead via one of:" >&2
    echo "  1. Place a prebuilt seed at $SEEDS_FILE" >&2
    echo "  2. Point SEEDS_DIR at a directory to archive" >&2
    echo "  3. Run scripts/build-seed.sh manually (needs Docker + server-team source)" >&2
    echo "See docs/reproducible-builds.md for details." >&2
    exit 1
  fi
fi

cd $schemas_src
rsync -arv --exclude ".git:.npmrc" ${base}/var $build_dir/files/

# Install schemas utils
schemas_dir=$build_dir/files/var/lib/drumee/schemas
mkdir -p $schemas_dir
rsync -arvp $schemas_src/bin $schemas_dir/
# Package the genesis entity templates so populate.js stockFactory can stock the
# factory pool at install time (gap #2). populate.js reads GENESIS_DIR, which
# defaults to /var/lib/drumee/schemas/templates/factory.
mkdir -p $schemas_dir/templates
rsync -arvp $schemas_src/templates/factory $schemas_dir/templates/
cp $schemas_src/package.json $schemas_dir/
cd $schemas_dir
npm i

cd $build_dir
package=${packagename}_${version}

echo "BUILDING PACKAGE IN  $build_dir"
dh_make --native --yes --indep --packagename $package --email $email
for f in $(ls ${base}/debian); do
  cp -r ${base}/debian/$f $build_dir/debian/
done
# DEB_UNSIGNED=1 builds without a maintainer signature.
#
# What apt actually verifies is the REPOSITORY's Release signature, not the .deb's — which
# is why reprepro re-signs on include and why an unsigned .deb installs perfectly well from
# a signed suite. So a local iteration loop (scripts/apt-repo-local.sh, which signs with a
# throwaway key of its own) does not need the project maintainer key at all, and requiring
# it means every image rebuild waits on a passphrase prompt that cannot be answered from a
# non-interactive shell.
#
# Deliberately opt-IN: a release build must stay signed, so the default is unchanged.
if [ "${DEB_UNSIGNED:-0}" = "1" ]; then
  echo "DEB_UNSIGNED=1 — building without a maintainer signature (not for release)"
  dpkg-buildpackage -us -uc
else
  dpkg-buildpackage -k$email
fi

copyToTarget $base/build/${package}
