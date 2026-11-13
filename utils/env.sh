#!/bin/bash
if [ "$UID" == "0" ]; then 
  echo "You should not run this builder with root privilege"
  exit 1
fi

export DRUMEE_ROOT_DIR=/srv/drumee
export DRUMEE_STATIC_DIR=$DRUMEE_ROOT_DIR/static
export DRUMEE_DATA_DIR=/data
export DRUMEE_MFS_DIR=/data/mfs
export DRUMEE_RUNTIME_DIR=$DRUMEE_ROOT_DIR/runtime
export DRUMEE_TMP_DIR=$DRUMEE_ROOT_DIR/runtime/tmp
export DRUMEE_CACHE_DIR=$DRUMEE_ROOT_DIR/cache
export DRUMEE_SYSTEM_USER=www-data
export DRUMEE_SERVER_HOME=$DRUMEE_ROOT_DIR/runtime/server

export DRUMEE_UI_HOME=$DRUMEE_ROOT_DIR/runtime/ui
export ACME_DIR=/etc/acme
export PUBLIC_UI_LOCALE=$DRUMEE_ROOT_DIR/static/locale
