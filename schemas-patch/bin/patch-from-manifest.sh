#!/bin/bash
script_dir=$(dirname "$(readlink -f "$0")")

count=$(drumee list | grep -w factory | grep online | wc -l)
factory=no
if [ $count != "0" ]; then 
   echo "Stopping factory"
   factory=yes
   drumee stop factory
fi

mariadb -e "set GLOBAL character_set_collations='utf8mb4=utf8mb4_general_ci'"

SCHEMAS_PATH=$(dirname "$script_dir")
export SCHEMAS_PATH

if [ ! -f "$SCHEMAS_PATH/manifest.txt" ]; then
  echo "No manifest were found. Aborted"
  exit 1
fi

options=(--force=1 --orphan=remove --ignore-error)

cd "$SCHEMAS_PATH" || exit 1
for i in $(cat manifest.txt); do
  echo $i
  target=null
  if [[ $i =~ ^yellow_page\/.+\.sql$ ]]; then
    target=yp 
  elif [[ $i =~ ^drumate\/.+\.sql$ ]]; then
    target=drumate
  elif [[ $i =~ ^hub\/.+\.sql$ ]]; then
    target=hub
  elif [[ $i =~ ^common\/.+\.sql$ ]]; then
    target=common
  elif [[ $i =~ ^utils\/.+\.sql$ ]]; then
    target=utils
  else 
    target=null
  fi

  if [ $target != "null" ]; then
    "$script_dir/patch.js" "--source=$i" "--target=$target" "${options[@]}"
  fi
done

if [ "$factory" == "yes" ]; then
  drumee restart factory
fi