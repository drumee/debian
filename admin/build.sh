#!/bin/bash

set -e
if [ "$UID" == "0" ]; then
  echo "You should not run this builder with root privilege"
  exit 1
fi

base=$0
if [[ $base =~ ^\/ ]]; then
  base=$(dirname $base)
else
  if [[ $base =~ ^\.\/ ]]; then
    base=$(echo $base | sed -e "s/^\.//")
    base="$(pwd)$(dirname $base)"
  else
    base=$(pwd)/$(dirname $base)
  fi
fi

if [[ $base =~ ^.+\/$ ]]; then
  base=$base
else
  base=$base/
fi
packagename=drumee-schemas-patch
# shellcheck source=utils/env.sh
source "${base}../utils/env.sh"
# shellcheck source=utils/functions.sh
source "${base}../utils/functions.sh"
#echo ${base}../utils/functions.sh

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
  --email=*)
    email="${arg#*=}"
    shift
    ;;
  esac
done

# vars are returned as exported
control="${base}/debian/control"
check_version "$version" "$control"
check_email "$email" "$control"
check_build_dir "${base}/build/$version"
build_dir="${build_dir:?check_build_dir did not initialize the build directory}"

src=${base}../schemas/src/schemas
manifest=${src}/patches/manifest.txt
bundle_schmas_patches $base $src $manifest "opt/drumee/schemas/patches"

rsync -ar ${base}/opt $build_dir/files/
cd $build_dir
echo "BUILDING PACKAGE IN  $build_dir"
dh_make --native --yes --indep --packagename ${packagename}_${version} --email $email
for src_file in "${base}/debian/"*; do
  if [ -f $src_file ]; then
    cp -r $src_file $build_dir/debian/
  fi
done
dpkg-buildpackage -k$email
