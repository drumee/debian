#!/bin/bash
# One fact, one place — the guard for docs/channel-parity.md.
#
# The two channels used to derive the same ~15 facts from drumee.yaml through two different
# vocabularies: a debconf preseed for native, environment variables for containers. That
# duplication was not merely untidy, it HID BUGS. Each of these was measured in a running
# stack, and each is a direct consequence of the second vocabulary:
#
#   * a BIND zone file literally named `auto` — renderDebconf has always stripped that
#     sentinel, renderEnv did not, and infra.js reads PUBLIC_IP4 from the environment.
#   * "domain_name": "localhost" in drumee.json beside the real domain in drumee.sh, from
#     one render, because the container path passed --public-domain and nothing else.
#   * an argparse usage dump, because --admin-email is not an infra.js option — the
#     postinst never guessed at flags, it exports ADMIN_EMAIL.
#   * DRUMEE_HTTP_PORT meaning "host publish port" in compose and "the port nginx binds"
#     to setup-infra, so a healthy container refused connections.
#
# Since change 1, the roles stack takes its settings from the preseed via
# `dpkg-reconfigure drumee-infra`. This asserts the duplication has not come back.
#
# Needs node only, so it runs in CI.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok(){ printf '  \033[1;32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[1;31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
note(){ printf '       \033[2m%s\033[0m\n' "$1"; }

command -v node >/dev/null 2>&1 || { echo "SKIP: node unavailable"; exit 0; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Env names the PRESEED owns. Each is a Drumee-semantic fact — something about this
# deployment rather than about compose — and each has a drumee-infra/* debconf key.
# A container must not be able to learn any of them from .env.
OWNED_BY_PRESEED="DRUMEE_DESCRIPTION LOCAL_MODE ADMIN_EMAIL ACME_EMAIL_ACCOUNT TLS_MODE
OWN_SSL OWN_SSL_PATH PUBLIC_IP4 PUBLIC_IP6 SERVICES BACKUP_LOCATION EXCHANGE_LOCATION
WIREGUARD_ENABLED WIREGUARD_COORDINATOR WIREGUARD_LISTEN_PORT WIREGUARD_REFLECTOR_PORT"

mk(){ # mk <stack>
  cat > "$tmp/$1.yaml" <<YAML
instance:
  description: Parity Test
  domain: parity.example.com
  admin_email: ops@parity.example.com
tls:
  mode: self-signed
images:
  registry: drumee
  stack: $1
versions:
  product: 9.9.9
YAML
  node "$root/config/render.mjs" env --config "$tmp/$1.yaml" 2>/dev/null | grep -E '^[A-Z]' | cut -d= -f1 | sort
}

printf '\033[1;36m── roles stack: no container may learn a Drumee fact from .env\033[0m\n'
roles_keys="$(mk roles)"
[ -n "$roles_keys" ] || { no "could not render the roles .env"; echo; exit 1; }
leaked=""
for k in $OWNED_BY_PRESEED; do
  printf '%s\n' "$roles_keys" | grep -qx "$k" && leaked="$leaked $k"
done
if [ -z "$leaked" ]; then
  ok "none of the $(echo $OWNED_BY_PRESEED | wc -w) preseed-owned names appear in the roles .env"
else
  no "these are in both vocabularies again:$leaked"
  note "they belong to the preseed — see docs/channel-parity.md"
fi

# The three that look semantic and stay, with the reason, so a future reader does not
# "fix" them: bin/drumee-ctl runs on the HOST and reads them. Nothing in a container does.
printf '\033[1;36m── the host CLI still gets what it reads\033[0m\n'
for k in DRUMEE_DOMAIN_NAME DRUMEE_DATA_DIR DB_ROOT_PASSWORD; do
  if printf '%s\n' "$roles_keys" | grep -qx "$k"; then
    ok "$k present (bin/drumee-ctl reads it, and it is not a container)"
  else
    no "$k missing — drumee-ctl doctor/backup would break"
  fi
done

printf '\033[1;36m── the guard cannot pass by breaking the source stack\033[0m\n'
# If someone dropped these unconditionally instead of per-stack, the check above would go
# green while the deprecated-but-working stack lost its configuration. So assert the
# source stack still carries them.
source_keys="$(mk source)"
missing=""
for k in $OWNED_BY_PRESEED; do
  printf '%s\n' "$source_keys" | grep -qx "$k" || missing="$missing $k"
done
[ -z "$missing" ] && ok "the source stack still carries all $(echo $OWNED_BY_PRESEED | wc -w) of them" \
                  || no "the source stack lost:$missing"

printf '\033[1;36m── every preseed-owned fact really is in the preseed\033[0m\n'
# The claim "the preseed owns it" has to be true, or dropping it from .env loses it
# entirely. Checked against the rendered preseed, not against a list.
preseed="$(node "$root/config/render.mjs" debconf --config "$tmp/roles.yaml" 2>/dev/null)"
for pair in "LOCAL_MODE:local_mode" "ADMIN_EMAIL:admin_email" "TLS_MODE:tls_method" \
            "ACME_EMAIL_ACCOUNT:acme_email" "OWN_SSL:own_ssl" "SERVICES:service" \
            "BACKUP_LOCATION:backup_location" "EXCHANGE_LOCATION:exchange_location" \
            "DRUMEE_DESCRIPTION:description" "WIREGUARD_ENABLED:wireguard_enabled"; do
  env_name="${pair%%:*}"; key="${pair##*:}"
  printf '%s\n' "$preseed" | grep -q "drumee-infra/$key[[:space:]]" \
    || no "$env_name was dropped from .env but drumee-infra/$key is not in the preseed"
done
ok "each dropped fact has a matching drumee-infra/* key in the preseed"

echo
printf '\033[1m== config parity: %d passed, %d failed ==\033[0m\n' "$pass" "$fail"
[ "$fail" = "0" ] || exit 1
