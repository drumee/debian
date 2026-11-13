#!/bin/bash
set -e

if [ "$UID" == "0" ]; then
  echo "You should not run this builder with root privilege"
  exit 1
fi

base="$(dirname "$(readlink -f "$0")")"
source ${base}/../utils/env.sh
source ${base}/../utils/functions.sh

packagename=drumee-ui-pod
enableApi=no
export DRUMEE_INSTANCE_NAME=main
export UI_BUILD_MODE=production

for arg in "$@"; do
  case $arg in
  --compile=*)
    : # Accepted legacy option; currently has no effect.
    shift
    ;;
  --enable-api=*)
    enableApi="${arg#*=}"
    shift
    ;;
  esac
done

version=$(get_version $base)
email=$(get_email $base)
build_dir=$(get_build_dir ${base}/build/$version)

export DRUMEE_UI_HOME=$build_dir/files/$DRUMEE_UI_HOME
export UI_BUILD_PATH=$DRUMEE_UI_HOME/main
mkdir -p $UI_BUILD_PATH

export UI_SRC_PATH=${base}/src/ui-team
export REPO_BASE=git@github.com:drumee
bundle $base "ui-team" "preview"
${base}/update-changelog.sh

echo $UI_SRC_PATH
export PATH=$UI_SRC_PATH/node_modules/.bin:$PATH

cd $UI_SRC_PATH
npx update-browserslist-db@latest
npm i
npm audit fix

config=webpack.js
echo "BUILDING FROM CONFIG $config"
export BUILD_TARGET=app
export ENDPOINT=main
webpack --config $config
if [ "$enableApi" == "yes" ]; then
  export BUILD_TARGET=api
  webpack --config $config
fi

rm -f $UI_BUILD_PATH/app/stats.json
rm -rf $build_dir/debian/

cd $build_dir
package=${packagename}_${version}
echo "BUILDING PACKAGE $package IN $build_dir"
dh_make --native --yes --indep --packagename $package --email $email
rsync -ar "${base}/debian" $build_dir/
for src_file in "${base}/debian/"*; do
  [ -e "$src_file" ] || continue
  cp -r "$src_file" "$build_dir/debian/"
done
dpkg-buildpackage -k$email

# copyToTarget $base/build/${package}
