#!/bin/bash
source /etc/drumee/drumee.sh
export NODE_PATH=/usr/share/drumee/lib/server/node_modules/
count=$(drumee list | grep -w factory | grep online | wc -l)
factory=no
if [ $count != "0" ]; then 
   echo "Stopping factory"
   factory=yes
   drumee stop factory
fi

export SCHEMAS_PATH=/opt/drumee/schemas/patches
if [ ! -f "$SCHEMAS_PATH/manifest.txt" ]; then
  echo "No manifest were found. Aborted"
  exit 1
fi

patcher=$DRUMEE_SERVER_HOME/main/offline/db-patch.js
if [ ! -x $patcher ]; then 
  if [ ! -f $patcher ]; then 
    echo "Could not find patcher ($patcher). Aborted"
    exit 1
  fi 
  chmod +x $patcher
fi 


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
  	$patcher --source=$i --target=$target --force --orphan=remove --ignore-error
  fi
done

if [ "$factory" == "yes" ]; then
  drumee restart factory
fi