#!/bin/bash

set -e
if [ "$UID" == "0" ]; then
  echo "You should not run this builder with root privilege"
  exit 1
fi

base="$(dirname "$(readlink -f "$0")")"
top=$(dirname $base)

packagename=drumee-patch
source ${top}/utils/env.sh
source ${top}/utils/functions.sh


# vars are returned as exported
# control="${base}/debian/control"
# check_version "$version" "$control"
# check_email "$email" "$control"
# check_build_dir "${base}/build/$version"


version=$(get_version $base)
email=$(get_email $base)
echo EMAIL ${base} $email $version
build_dir=$(get_build_dir ${base}/build/$version)

REPO_BASE=git@github.com:drumee

DEPTH=2
manifest=""

for arg in "$@"; do
  case "$arg" in
    --manifest=*) manifest="${arg#--manifest=}" ;;
    --manifest)   manifest="auto" ;;
    [0-9]*)       DEPTH="$arg" ;;
  esac
done

if [ -z "$manifest" ]; then
  echo "No --manifest provided, skipping patch build"
  exit 0
fi

bundle $base "schemas" "preview" "" ""
schemas_src=${base}/src/schemas
cd $schemas_src
npm i @drumee/server-essentials

if [ "$manifest" = "auto" ]; then
  tmpfile=/tmp/drumee.build.$$
  echo $tmpfile
  git log -$DEPTH | egrep "^commit" | awk '{print $2}' > $tmpfile
  hash1=$(head -1 $tmpfile)
  hash2=$(tail -1 $tmpfile)
  echo "DEPTH" "$hash1" "$hash2"
  rm -f $tmpfile
  if [ "$hash1" != "" -a "$hash2" != "" ]; then
    echo Building manifest
    bin/make-manifest $hash1 $hash2
  fi
else
  if [ ! -f "$manifest" ]; then
    echo "Manifest file not found: $manifest"
  fi
  cp "$manifest" $schemas_src/patches/manifest.txt
fi

# bundle_schmas_patches $base $src $manifest "var/lib/drumee/patches/schemas"
#
# ${base}/var only exists once a build has staged patches into it, so on a release with NO
# pending migrations this rsync failed with `link_stat ... No such file or directory` and
# took the whole build with it. An empty patch set is a normal state — most releases have
# no schema change — and drumee-role-schemas Depends on drumee-patch at an exact version,
# so an unbuildable empty package makes the entire schemas role uninstallable.
#
# The package is still worth producing when empty: it is what pins "this release carries no
# migrations", and entrypoint/schemas already treats an absent patch directory as nothing
# to do.
mkdir -p ${base}/var/lib/drumee/patches/schemas
rsync -arv --exclude ".git:.npmrc" ${base}/var $build_dir/files/
if [ -f $schemas_src/patches/manifest.txt ]; then
  schemas_dir=$build_dir/files/var/lib/drumee/patches/schemas
  mkdir -p $schemas_dir
  filtered_manifest=$(mktemp)
  while IFS= read -r file; do
    file="${file#"${file%%[! ]*}"}"
    [ -z "$file" ] && continue
    if [ -f "$schemas_src/$file" ]; then
      echo "$file" >> "$filtered_manifest"
    else
      echo "MISSING: $file"
    fi
  done < "$schemas_src/patches/manifest.txt"
  rsync -arv --files-from="$filtered_manifest" "$schemas_src/" "$schemas_dir/"
  mkdir -p "$schemas_dir/patches"
  cp "$filtered_manifest" "$schemas_dir/patches/manifest.txt"
  rm -f "$filtered_manifest"
  rsync -arvp $schemas_src/bin $schemas_dir/
  cp $schemas_src/package.json $schemas_dir/
  cd $schemas_dir
  npm i
else
  echo No change to build patch
  exit 1
fi


# chmod +x $build_dir/files/var/lib/drumee/schemas/patches/
cd $build_dir
echo "BUILDING PACKAGE IN  $build_dir"
dh_make --native --yes --indep --packagename ${packagename}_${version} --email $email
for f in $(ls ${base}/debian); do
  src_file=${base}/debian/$f
  if [ -f $src_file ]; then
    cp -r $src_file $build_dir/debian/
  fi
done
dpkg-buildpackage -k$email
#copyToTarget $base/build/${package}
