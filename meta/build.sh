#!/bin/bash
# Build the `drumee` metapackage (no payload — pure dependencies).
set -e
if [ "$UID" == "0" ]; then
  echo "You should not run this builder with root privilege"
  exit 1
fi

base="$(dirname "$(readlink -f "$0")")"
source ${base}/../utils/env.sh
source ${base}/../utils/functions.sh

packagename=drumee
version=$(get_version $base)
email=$(get_email $base)
build_dir=$(get_build_dir ${base}/build/$version)
echo "Building $packagename version=$version build_dir=$build_dir"

mkdir -p $build_dir/files
cd $build_dir
package=${packagename}_${version}
dh_make --native --yes --indep --packagename $package --email $email
for src_file in "${base}/debian/"*; do
  [ -e "$src_file" ] || continue
  cp -r "$src_file" "$build_dir/debian/"
done
dpkg-buildpackage -k$email

copyToTarget $base/build/${package}
