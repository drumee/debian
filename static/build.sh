#!/bin/bash
set -e 

base="$(dirname "$(readlink -f "$0")")"
packagename=drumee-static
source ${base}/../utils/env.sh
source ${base}/../utils/functions.sh


for arg in "$@"; do
  case $arg in
  --version=*)
    version="${arg#*=}"
    shift
    ;;
  --force=*)
    : # Accepted legacy option; currently has no effect.
    shift
    ;;
  --compile=*)
    : # Accepted legacy option; currently has no effect.
    shift
    ;;
  --enable-api=*)
    : # Accepted legacy option; currently has no effect.
    shift
    ;;
  --email=*)
    email="${arg#*=}"
    shift
    ;;
  esac
done


# vars are returned as exported
# Native control/version checks are intentionally disabled in this frozen builder.
# check_version "$version" "$control"
# check_email "$email" "$control"
# check_build_dir "${base}/build/$version"

version=$(get_version $base)
email=$(get_email $base)
build_dir=$(get_build_dir ${base}/build/$version)
bundle $base "static" "main" "" "srv/drumee/static"
${base}/update-changelog.sh 

cd $build_dir
echo "BUILDING PACKAGE ${packagename}_${version} IN $build_dir"
dh_make --native --yes --indep --packagename ${packagename}_${version} --email $email
rsync -ar "${base}/debian" $build_dir/
for src_file in "${base}/debian/"*; do
  [ -e "$src_file" ] || continue
  cp -r "$src_file" "$build_dir/debian/"
done
dpkg-buildpackage -k$email
