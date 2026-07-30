#!/bin/sh
# Write the Drumee APT stanza. Installed into the base image as
# /usr/local/sbin/drumee-apt-source and called by each role image, so the stanza
# is written in one place instead of being repeated in seven Dockerfiles.
#
#   drumee-apt-source <uri> <suite> <components> <keyring-path>
#
# The base image configures no Drumee source itself: the project signing key does
# not exist yet (docs/distribution.md §4), and committing a developer's throwaway
# test key would ship trust in it. Role builds therefore pass the repository they
# should install from — the local test repository during development,
# apt.drumee.net once it is signed with the project key.
set -eu

[ $# -eq 4 ] || { echo "usage: drumee-apt-source <uri> <suite> <components> <keyring>" >&2; exit 2; }
uri="$1"; suite="$2"; components="$3"; keyring="$4"

# Fail here rather than at apt-get update: an unsigned or unverifiable source is
# how an image ends up installing something nobody chose.
[ -f "$keyring" ] || { echo "drumee-apt-source: keyring not found: $keyring" >&2; exit 1; }

cat > /etc/apt/sources.list.d/drumee.sources <<SOURCES
Types: deb
URIs: $uri
Suites: $suite
Components: $components
Signed-By: $keyring
SOURCES

echo "drumee-apt-source: $uri $suite [$components] signed-by $keyring"
