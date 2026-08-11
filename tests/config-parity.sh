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

printf '\033[1;36m── the preseed carries an admin-derived acme_email\033[0m\n'
# An EMPTY acme_email is not neutral downstream. sysEnv defaults ACME_EMAIL_ACCOUNT to
# admin@localhost, infra.js writes acme_email_account from it, and setup-schemas' createAdmin
# resolves ADMIN_EMAIL || ACME_EMAIL_ACCOUNT || admin@<domain> — so an empty answer here
# created the ADMIN ACCOUNT as admin@localhost, on an instance whose admin_email was correct
# in the very same file. Measured twice on a real install before it was understood.
acme="$(printf '%s\n' "$preseed" | sed -n 's/^drumee-infra[[:space:]]*drumee-infra\/acme_email[[:space:]]*string[[:space:]]*//p')"
if [ -n "$acme" ]; then
  ok "acme_email is answered ($acme)"
else
  no "acme_email is empty — the admin account will be created as admin@localhost"
fi

printf '\033[1;36m── the converter role cannot learn a database credential\033[0m\n'
# docs/distribution.md §2: the converter is the only component that parses untrusted user
# documents, so code execution there is a realistic outcome of an upload. "Runs with no
# database credentials" is the reason the role exists, and it is one careless line away from
# being false: adding `env_file: [.env]` to the service, or widening its conf mount from
# etc/drumee/credential/converter to etc/drumee/credential, would hand it DB_PASSWORD or
# db.json without changing anything a reader would look at twice.
# Comments stripped, or the check reads the prose instead of the configuration: the
# service carries a comment saying "NO env_file, deliberately", which matched.
conv="$(node "$root/config/render.mjs" compose --config "$tmp/roles.yaml" 2>/dev/null \
        | sed -n '/^  converter:/,/^  [a-z-]*:$/p' | grep -v '^[[:space:]]*#')"
if [ -z "$conv" ]; then
  no "the roles compose has no converter service"
else
  printf '%s\n' "$conv" | grep -q 'env_file' \
    && no "the converter service has an env_file — .env carries DB_PASSWORD" \
    || ok "no env_file on the converter service"

  # The mount must name the scoped directory. A subpath of the shared credential dir, or
  # of /etc/drumee as a whole, would expose db.json and email.json.
  if printf '%s\n' "$conv" | grep -qE 'subpath: etc/drumee/credential/converter'; then
    ok "its only credential mount is the scoped converter directory"
  else
    no "the converter's credential mount is not the scoped etc/drumee/credential/converter"
    printf '%s\n' "$conv" | grep -E 'subpath|source:' | sed 's/^/       /'
  fi
  printf '%s\n' "$conv" | grep -qE 'subpath: etc/drumee$|subpath: etc/drumee/credential$' \
    && no "the converter mounts the whole credential tree — db.json would be readable" \
    || ok "it does not mount the shared credential tree"

  printf '%s\n' "$conv" | grep -qE '^\s+ports:' \
    && no "the converter publishes a port — §2 says no inbound network exposure" \
    || ok "no published port"
fi

# And the writer half: infra-init has to actually create that directory, or the subpath
# mount fails and the service never starts.
if grep -q 'credential/converter' "$root/bootstrap/usr/lib/drumee/entrypoint/infra"; then
  ok "infra-init writes the scoped credential directory the mount needs"
else
  no "nothing creates etc/drumee/credential/converter — the subpath mount would fail"
fi

printf '\033[1;36m── no stray backtick inside the compose template literals\033[0m\n'
# render.mjs's compose renderers are JS template literals, and a backtick in a COMMENT
# inside one closes the string. That has broken every render.mjs command four separate
# times in one sitting; `node --check` catches it, but only if someone runs it. Now
# something does, on every CI run.
if node --check "$root/config/render.mjs" 2>/dev/null; then
  ok "config/render.mjs parses"
else
  no "config/render.mjs does not parse — most likely a backtick in a template-literal comment"
  node --check "$root/config/render.mjs" 2>&1 | head -4 | sed 's/^/       /'
fi

echo
printf '\033[1m== config parity: %d passed, %d failed ==\033[0m\n' "$pass" "$fail"
[ "$fail" = "0" ] || exit 1
