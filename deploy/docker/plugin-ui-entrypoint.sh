#!/bin/sh
# Run-once publisher for a Drumee UI plugin (see Dockerfile.plugin-ui).
# Copies the built bundle + index.json into the shared `plugins` volume at
# /srv/drumee/runtime/plugins/ui/<endpoint>/<name>/, where bootstrap.plugin
# looks it up and the proxy serves it at /-/plugins/<name>/.
set -eu

NAME="${PLUGIN_NAME:?PLUGIN_NAME is required}"
ENDPOINT="${PLUGIN_ENDPOINT:-main}"
DEST="/srv/drumee/runtime/plugins/ui/${ENDPOINT}/${NAME}"

echo "==> [ui-plugin:${NAME}] publishing -> ${DEST}"
rm -rf "$DEST"          # drop stale (hashed) bundles from a previous build
mkdir -p "$DEST"
cp -a "/payload/${NAME}/." "$DEST/"
chmod -R a+rX /srv/drumee/runtime/plugins/ui
echo "==> [ui-plugin:${NAME}] done"
