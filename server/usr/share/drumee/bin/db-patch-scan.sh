#!/bin/bash
shopt -s extglob dotglob
source /etc/drumee/drumee.sh
export NODE_PATH=/usr/share/drumee/lib/server/node_modules/

for i in "$2/"*.sql; do
    [ -f "$i" ] || continue
    #echo $i 
    "$DRUMEE_SERVER_HOME/build/$USER/offline/db-patch.js" "--schemas=$HOME/devel/schemas" "--source=$i" --force "--target=$1"
done 
