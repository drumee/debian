#!/bin/bash

set -e
if [ "$UID" == "0" ]; then
  echo "You should not run this builder with root privilege"
  exit 1
fi

builder_dir="$(dirname "$(readlink -f "$0")")"
target_dir="$(dirname $builder_dir)/target"
deb_base=$builder_dir/debian
# Shared utils (single source of truth). Builder-specific behaviour is set via
# env vars before sourcing: GitLab as the REPO_BASE fallback, and no npm audit fix.
export REPO_BASE_DEFAULT=git@gitlab.drumee.in:drumee
export NPM_AUDIT_FIX=no
source ${builder_dir}/../utils/env.sh
source ${builder_dir}/../utils/functions.sh

version=$(get_version $builder_dir)
email=$(get_email $builder_dir)
build_dir=$(get_build_dir ${builder_dir}/build/$version)

export REPO_BASE=git@github.com:drumee
lib_dir=var/lib/drumee

if [ "$1" = "pull" ]; then
  bundle $builder_dir "setup" "somanos/wip" ""
fi

# bundle_acme $builder_dir "usr/share/acme"
mkdir -p $build_dir/files/var/
mkdir -p $build_dir/files/usr/
mkdir -p $build_dir/files/etc/
OPTIONS=(-ar --delete --exclude '.github' --exclude '.git' --exclude '.npmrc')
rsync "${OPTIONS[@]}" ${target_dir}/var/ $build_dir/files/var/
rsync "${OPTIONS[@]}" ${target_dir}/usr/ $build_dir/files/usr/
rsync "${OPTIONS[@]}" ${target_dir}/etc/ $build_dir/files/etc/
rsync "${OPTIONS[@]}" ${builder_dir}/src/setup $build_dir/files/${lib_dir}
rsync "${OPTIONS[@]}" $deb_base/ $build_dir/debian/
cp -u ${builder_dir}/src/setup/menu/templates $build_dir/debian/templates

cd $build_dir

dpkg-buildpackage -us -uc -k$email


