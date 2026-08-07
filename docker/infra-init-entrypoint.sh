#!/bin/bash
# infra-init — render the configuration tree into the shared volume, once, at deploy
# time. This is the run-once job of docs/distribution.md §5: the package delivered the
# payload at image build time, this executes it.
#
# It renders with setup-infra's OWN engine (infra.js --chroot), which is the point: the
# 39-odd files under /etc/drumee, /etc/nginx, /var/lib/bind, /etc/postfix and friends
# have one authoritative source of truth, and the container channel must not grow a
# second one. Nothing here reimplements a template.
#
# --chroot means every write lands under the target directory and nothing touches the
# container's own filesystem. Verified by snapshotting /etc/drumee, /etc/nginx,
# /var/lib/bind, /etc/bind and /srv/drumee before and after a render.
#
# Required env:
#   DRUMEE_DOMAIN_NAME     the deployment's domain
# Optional env:
#   ADMIN_EMAIL            defaults to admin@<domain>
#   PUBLIC_IP4/PUBLIC_IP6  serving addresses; without them only the private branch
#                          renders (no 01-public.conf, no public zone)
#   PRIVATE_IP4/PRIVATE_IP6
#   DRUMEE_DATA_DIR        default /data
#   DRUMEE_DB_DIR          default /srv/db
#   OWN_CERTS_DIR          operator-supplied wildcard certificates
#   LOCAL_MODE=1           LAN-only instance
#   RENDER_TARGET          where to write, default /out
#   FORCE_RENDER=1         re-render over an existing tree
set -euo pipefail
say(){ printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

SETUP_INFRA_DIR=/var/lib/drumee/setup-infra
TARGET="${RENDER_TARGET:-/out}"
DOMAIN="${DRUMEE_DOMAIN_NAME:?DRUMEE_DOMAIN_NAME is required}"
UID_DRUMEE="${DRUMEE_UID:-8000}"
GID_DRUMEE="${DRUMEE_GID:-8000}"

[ -f "$SETUP_INFRA_DIR/infra.js" ] || die "no setup-infra payload at $SETUP_INFRA_DIR — is drumee-infra installed?"
[ -d "$TARGET" ] || die "$TARGET is not mounted — the shared configuration volume must be there"

export ADMIN_EMAIL="${ADMIN_EMAIL:-admin@$DOMAIN}"
export DRUMEE_DOMAIN_NAME

# Idempotence is infra.js's own: hasExistingSettings() sees the drumee.json a previous
# run wrote and exits without touching anything, unless --reconfigure=1. So a restarted
# job is a no-op and a deliberate re-render is one flag — the same contract as
# `dpkg-reconfigure` on the native channel, which is what makes the two channels behave
# the same way for the same reason.
RECONF=()
if [ "${FORCE_RENDER:-0}" = "1" ]; then
  say "FORCE_RENDER=1 — re-rendering over the existing tree"
  RECONF=(--reconfigure=1)
elif [ -f "$TARGET/etc/drumee/drumee.json" ]; then
  say "already rendered ($TARGET/etc/drumee/drumee.json exists) — nothing to do"
  echo "    domain: $(grep -oE '"domain_name": "[^"]*"' "$TARGET/etc/drumee/drumee.json" || echo '?')"
  echo "    set FORCE_RENDER=1 to render again"
  exit 0
fi

# DKIM before the render, when the tooling is here. infra.js no longer DIES on a missing
# key (it warns and emits an empty record), but a real key is what makes outbound mail
# verifiable, and it must exist before the render because the zone embeds its public half.
KEYDIR="$TARGET/etc/opendkim/keys/$DOMAIN"
if [ ! -s "$KEYDIR/dkim.txt" ]; then
  if command -v opendkim-genkey >/dev/null 2>&1; then
    say "generating a DKIM key for $DOMAIN"
    mkdir -p "$KEYDIR"
    opendkim-genkey -b 2048 -d "$DOMAIN" -s dkim -D "$KEYDIR"
    chmod 0640 "$KEYDIR/dkim.private"
  else
    say "opendkim-genkey absent — the render will emit an empty DKIM record"
  fi
fi

# Only the flags infra.js actually declares. Passing an undeclared one makes argparse
# exit 2 with a usage dump, which reads like a crash; `--admin-email` is not an option,
# for instance — that value travels in the environment.
args=(--chroot="$TARGET" --public-domain="$DOMAIN")
[ -n "${PUBLIC_IP4:-}" ]     && args+=(--public-ip4="$PUBLIC_IP4")
[ -n "${PUBLIC_IP6:-}" ]     && args+=(--public-ip6="$PUBLIC_IP6")
[ -n "${PRIVATE_IP4:-}" ]    && args+=(--private-ip4="$PRIVATE_IP4")
[ -n "${PRIVATE_IP6:-}" ]    && args+=(--private-ip6="$PRIVATE_IP6")
[ -n "${DRUMEE_DATA_DIR:-}" ]&& args+=(--data-dir="$DRUMEE_DATA_DIR")
[ -n "${DRUMEE_DB_DIR:-}" ]  && args+=(--db-dir="$DRUMEE_DB_DIR")
[ -n "${OWN_CERTS_DIR:-}" ]  && args+=(--own-certs-dir="$OWN_CERTS_DIR")
[ "${LOCAL_MODE:-0}" = "1" ] && args+=(--localhost=1)

say "rendering $DOMAIN into $TARGET"
printf '    infra.js %s\n' "${args[*]} ${RECONF[*]:-}"
( cd "$SETUP_INFRA_DIR" && node infra.js "${args[@]}" ${RECONF[@]+"${RECONF[@]}"} )

[ -f "$TARGET/etc/drumee/drumee.json" ] \
  || die "the render produced no $TARGET/etc/drumee/drumee.json — refusing to report success"

# The other roles run as uid 8000 and only read this tree. Credentials stay 0640: the
# rendered db.json and email.json carry passwords, and a config volume shared with the
# media role — the one component that parses untrusted documents — should not be
# world-readable.
say "fixing ownership to $UID_DRUMEE:$GID_DRUMEE"
chown -R "$UID_DRUMEE:$GID_DRUMEE" "$TARGET"
[ -d "$TARGET/etc/drumee/credential" ] && chmod 0750 "$TARGET/etc/drumee/credential"
find "$TARGET/etc/drumee/credential" -type f -exec chmod 0640 {} + 2>/dev/null || true

say "done — $(find "$TARGET" -type f | wc -l) files"
printf '    %-22s %s\n' "domain_name" "$(grep -oE '"domain_name": "[^"]*"' "$TARGET/etc/drumee/drumee.json")"
printf '    %-22s %s\n' "nginx vhosts" "$(ls "$TARGET/etc/nginx/sites-enabled" 2>/dev/null | paste -sd, - )"
printf '    %-22s %s\n' "bind zones" "$(ls "$TARGET/var/lib/bind" 2>/dev/null | paste -sd, - )"
printf '    %-22s %s\n' "credentials" "$(ls "$TARGET/etc/drumee/credential" 2>/dev/null | paste -sd, - )"
