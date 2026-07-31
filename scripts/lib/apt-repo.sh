# shellcheck shell=bash
# The shape of a Drumee APT repository, defined once.
#
# Sourced by both scripts/apt-repo-local.sh (the throwaway development repository)
# and scripts/publish-pool.sh (what apt.drumee.net serves). One definition, so the
# layout proven locally is by construction the layout that ships —
# docs/distribution.md §4 is the normative description and this is its executable
# form. Two files describing "the same" layout drift, and the drift shows up as a
# client that cannot find a package, long after the change that caused it.

# Channels are SUITES, not components: they are mutually exclusive release trains,
# so a client pins one through /etc/apt/preferences.d. Promotion between them is
# `reprepro copy`, never a rebuild — the artifact tested in beta is bit-for-bit
# the one that ships as stable.
DRUMEE_APT_SUITES=(trixie trixie-beta trixie-edge)

# Components are reserved for the open-core split: main = the AGPL core,
# enterprise = the commercial tier. A customer enables the commercial tier by
# adding a component, not by pointing at a different repository.
DRUMEE_APT_COMPONENTS="main enterprise"

# NOT 'all', despite what a package's Architecture field says: reprepro rejects it
# outright ("Distribution trixie contains an architecture called 'all'"). It is not
# a distributable architecture — it states that one binary serves every
# architecture, so reprepro files Architecture: all packages into EVERY listed
# architecture's index. Listing amd64 and arm64 therefore publishes them to both,
# which is the intent; `verify` proves it rather than asserting it.
#
# `source` is here for AGPL v3 compliance: the Debian source package (.dsc plus
# its tarball) is the canonical artifact for source availability. Nothing fills it
# until the builders produce sources as well as binaries — they currently run
# dpkg-buildpackage -b.
DRUMEE_APT_ARCHITECTURES="amd64 arm64 source"

# Release carries Valid-Until = now + this. A client then refuses an index older
# than that instead of trusting whatever a stale mirror or a cache hands it. It
# also means publication is not fire-and-forget: the indices must be re-exported
# before they expire, even in a month where nothing was released.
DRUMEE_APT_VALID_FOR="30d"

# Write conf/distributions for every suite.
#   $1 conf file    $2 signing key fingerprint (empty = unsigned)    $3 Label
drumee_apt_write_distributions() {
  local conf="$1" fpr="$2" label="$3" suite

  : > "$conf"
  for suite in "${DRUMEE_APT_SUITES[@]}"; do
    cat >> "$conf" <<EOF
Origin: Drumee
Label: $label
Codename: $suite
Suite: $suite
Architectures: $DRUMEE_APT_ARCHITECTURES
Components: $DRUMEE_APT_COMPONENTS
Description: Drumee $suite
ValidFor: $DRUMEE_APT_VALID_FOR
EOF
    # An unsigned repository is only ever acceptable for a local experiment, and
    # even then apt needs [trusted=yes]. Omit the field rather than emit an empty
    # SignWith, which reprepro reads as "sign with the default key" and fails
    # confusingly when there is no default key.
    [ -n "$fpr" ] && printf 'SignWith: %s\n' "$fpr" >> "$conf"
    printf '\n' >> "$conf"
  done
}

# Refuse to publish with a key that is about to expire. When the signing key
# expires, every client's `apt update` fails at once — including boxes that have
# been running untouched for months — and the failure looks like a repository
# outage rather than a key problem. $1 = key id or fingerprint, $2 = days of
# warning (default 60). Returns 1 if the key is already expired.
drumee_apt_check_key_expiry() {
  local key="$1" warn_days="${2:-60}" expiry now left
  expiry="$(gpg --list-keys --with-colons "$key" 2>/dev/null \
            | awk -F: '/^pub:/ {print $7; exit}')"
  [ -n "$expiry" ] || { printf '  key %s does not expire\n' "$key"; return 0; }
  now="$(date +%s)"
  left=$(( (expiry - now) / 86400 ))
  if [ "$left" -le 0 ]; then
    printf '  \033[1;31mEXPIRED\033[0m signing key %s expired %s day(s) ago\n' "$key" "$(( -left ))"
    return 1
  fi
  if [ "$left" -le "$warn_days" ]; then
    printf '  \033[1;33mWARNING\033[0m signing key %s expires in %s day(s) (%s)\n' \
      "$key" "$left" "$(date -d "@$expiry" +%Y-%m-%d)"
  else
    printf '  signing key %s valid for %s more day(s)\n' "$key" "$left"
  fi
  return 0
}
