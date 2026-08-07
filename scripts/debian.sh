#!/bin/bash
# Drumee native (Debian/Ubuntu) bootstrap — adds the signed APT repo and installs
# Drumee.
#
#   curl -fsSL https://apt.drumee.net/debian.sh | sudo bash
#   # unattended (preseed answers first):
#   sudo PRESEED=/path/to/install.conf bash debian.sh
#
# Published under three names, all byte-identical (see scripts/publish-site.sh):
#   debian.sh          current
#   baremetal.sh       previous name, kept because that URL is in circulation
#   install-native.sh  the name before that
#
# The APT repo is the pool/dists repository served from apt.drumee.net, configured as
# a deb822 .sources stanza. APT_URL is the base URL, APT_SUITE the release channel,
# and KEYRING_URL the GPG public key used to verify it. The older flat repository is
# frozen — see the note at the stanza below.
#
# Env:
#   APT_URL       (default https://apt.drumee.net)  pool/dists repo base
#   APT_SUITE     (default trixie)  release channel: trixie | trixie-beta | trixie-edge
#   APT_COMPONENT (default main)    main = AGPL core, enterprise = commercial tier
#   KEYRING_URL   (default https://apt.drumee.net/drumee-archive-keyring.gpg)
#   KEYRING_PATH  (default /etc/apt/keyrings/drumee-archive-keyring.gpg)
#   PRESEED      (optional)  install.conf from config/render.mjs
#
# INTERACTION
#   Unless PRESEED is given, this script asks for EVERY setting drumee-infra
#   accepts and preseeds the answers, so the whole install is decided here rather
#   than half here and half by debconf. It prompts when DRUMEE_NONINTERACTIVE is
#   unset or 0; any other value takes defaults and env values silently.
#
#   Presetting a variable skips its question — that is how an unattended install
#   works without a preseed file. Empty means "not answered yet, ask".
#
#   DRUMEE_NONINTERACTIVE      unset|0 = prompt for everything; anything else = never prompt
#   DRUMEE_RECONFIGURE_EXISTING true|false  re-render an already-configured host
#   DRUMEE_DESCRIPTION         instance label            (default "My Great Drumee Team")
#   DRUMEE_LAN_MODE            dns | wireguard — how a private-address box is
#                              reached; lan branch only (default dns)
#   DRUMEE_DOMAIN              domain name, or "local"   (default example.com)
#   DRUMEE_LOCAL_MODE          true|false, LAN-only      (only when domain is "local")
#   DRUMEE_SERVICE             comma-separated optional services
#   DRUMEE_ADMIN_EMAIL         administrator login + notifications
#   DRUMEE_DB_DIR              database path             (default /srv/db)
#   DRUMEE_DATA_DIR            MFS storage path          (default /data)
#   DRUMEE_BACKUP_LOCATION     backup path or remote:path
#   DRUMEE_EXCHANGE_LOCATION   host<->MFS transfer dir   (default /exchangearea)
#   DRUMEE_PUBLIC_IP4          public IPv4 ("-" to leave unset)
#   DRUMEE_PUBLIC_IP6          public IPv6 ("-" to leave unset)
#   DRUMEE_TLS_METHOD          acme-dns-server|acme-dns-api|caddy|own|self-signed
#   DRUMEE_ACME_EMAIL          ACME account email        (defaults to the admin email)
#   DRUMEE_OWN_SSL_PATH        cert directory            (tls_method=own)
#   DRUMEE_ACME_ENV_FILE       DNS API credentials file  (tls_method=acme-dns-api)
#   DRUMEE_CADDY_DOMAIN        zone to certify           (tls_method=caddy)
#   DRUMEE_CADDY_DNS_PROVIDER  caddy-dns module name     (tls_method=caddy)
#   DRUMEE_CADDY_DNS_API_KEY   DNS provider token        (tls_method=caddy)
#   WIREGUARD_ENABLED          true|false                (default false)
#   WIREGUARD_COORDINATOR      coordination server host  (default coord.drumee.tech)
#   WIREGUARD_LISTEN_PORT      UDP port for wg0          (default 51820)
#   WIREGUARD_REFLECTOR_PORT   reflector port            (default 51821)
set -euo pipefail

APT_URL="${APT_URL:-https://apt.drumee.net}"
KEYRING_URL="${KEYRING_URL:-https://apt.drumee.net/drumee-archive-keyring.gpg}"
KEYRING_PATH="${KEYRING_PATH:-/etc/apt/keyrings/drumee-archive-keyring.gpg}"
# Release channel = APT suite. trixie is stable; trixie-beta and trixie-edge exist for
# pre-release trains and are mutually exclusive with it (suites, not components, so a
# box pins one channel and apt preferences can override per package).
APT_SUITE="${APT_SUITE:-trixie}"
APT_COMPONENT="${APT_COMPONENT:-main}"
PRESEED="${PRESEED:-}"

# Every answer: empty means "not answered yet, ask for it".
DRUMEE_RECONFIGURE_EXISTING="${DRUMEE_RECONFIGURE_EXISTING:-}"
DRUMEE_DESCRIPTION="${DRUMEE_DESCRIPTION:-}"
DRUMEE_LAN_MODE="${DRUMEE_LAN_MODE:-}"      # lan branch only: dns | wireguard
DRUMEE_DOMAIN="${DRUMEE_DOMAIN:-}"
DRUMEE_LOCAL_MODE="${DRUMEE_LOCAL_MODE:-}"
DRUMEE_SERVICE="${DRUMEE_SERVICE:-}"
DRUMEE_ADMIN_EMAIL="${DRUMEE_ADMIN_EMAIL:-}"
DRUMEE_DB_DIR="${DRUMEE_DB_DIR:-}"
DRUMEE_DATA_DIR="${DRUMEE_DATA_DIR:-}"
DRUMEE_BACKUP_LOCATION="${DRUMEE_BACKUP_LOCATION:-}"
DRUMEE_EXCHANGE_LOCATION="${DRUMEE_EXCHANGE_LOCATION:-}"
DRUMEE_PUBLIC_IP4="${DRUMEE_PUBLIC_IP4:-}"
DRUMEE_PUBLIC_IP6="${DRUMEE_PUBLIC_IP6:-}"
DRUMEE_TLS_METHOD="${DRUMEE_TLS_METHOD:-}"
DRUMEE_ACME_EMAIL="${DRUMEE_ACME_EMAIL:-}"
DRUMEE_OWN_SSL_PATH="${DRUMEE_OWN_SSL_PATH:-}"
DRUMEE_ACME_ENV_FILE="${DRUMEE_ACME_ENV_FILE:-}"
DRUMEE_CADDY_DOMAIN="${DRUMEE_CADDY_DOMAIN:-}"
DRUMEE_CADDY_DNS_PROVIDER="${DRUMEE_CADDY_DNS_PROVIDER:-}"
DRUMEE_CADDY_DNS_API_KEY="${DRUMEE_CADDY_DNS_API_KEY:-}"
WIREGUARD_ENABLED="${WIREGUARD_ENABLED:-}"
WIREGUARD_COORDINATOR="${WIREGUARD_COORDINATOR:-coord.drumee.tech}"
WIREGUARD_LISTEN_PORT="${WIREGUARD_LISTEN_PORT:-51820}"
WIREGUARD_REFLECTOR_PORT="${WIREGUARD_REFLECTOR_PORT:-51821}"

# Prompts must read the keyboard, not stdin: on the documented
# `curl … | sudo bash` path stdin IS the script. /dev/tty is the real terminal.
TTY=/dev/tty

# The single interaction gate. Interactive when DRUMEE_NONINTERACTIVE is unset or
# 0; any other value means unattended. Tested as a value rather than as "= 1" so
# DRUMEE_NONINTERACTIVE=true / yes / 2 are not silently read as "please prompt".
#
# A terminal is still required: on `curl … | sudo bash` under cron or cloud-init
# there is no /dev/tty, and a prompt there would block forever with nothing to
# read it. That case falls back to defaults and env values.
interactive() {
  case "${DRUMEE_NONINTERACTIVE:-0}" in
    0|"") ;;
    *) return 1 ;;
  esac
  { true <"$TTY"; } 2>/dev/null
}

[ "$(id -u)" = "0" ] || { echo "error: run as root (sudo)" >&2; exit 1; }
command -v apt-get >/dev/null || { echo "error: this installer targets Debian/Ubuntu" >&2; exit 1; }

# curl is needed for the very first step, fetching the keyring — not just later
# for NodeSource. A minimal Debian install has neither curl nor ca-certificates,
# and the script used to die on line 1 of its real work with "curl: command not
# found". The documented `curl … | sudo bash` invocation hides this (curl
# obviously exists if it fetched the script), but any other delivery — wget, scp,
# a pre-downloaded copy, a cloud-init file — hits it immediately.
if ! command -v curl >/dev/null; then
  echo "==> Installing curl (absent on minimal installs)"
  apt-get update
  apt-get install -y curl ca-certificates
fi

echo "==> Adding Drumee APT repository ($APT_SUITE, $APT_COMPONENT) at $APT_URL"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL "$KEYRING_URL" -o "$KEYRING_PATH"

# deb822, pointing at the pool/dists layout. The flat repository it replaces is
# FROZEN: it still serves what it always served, so boxes installed against it keep
# working, but new releases only reach the pool. 1.0.23 was the first pool-only one.
#
# Architectures is deliberately NOT pinned. The pool publishes amd64 and arm64, and
# hardcoding amd64 would silently exclude arm64 — which is the typical target for the
# behind-a-router flow (Raspberry Pi and similar). Omitted, apt uses dpkg's native
# architecture, which is the right answer on both.
#
# The keyring goes to /etc/apt/keyrings, not /usr/share/keyrings: this script is an
# administrator adding a third-party repository, and /usr/share/keyrings belongs to
# files shipped by packages. When drumee-archive-keyring exists it will own the path
# under /usr/share and this can point there instead; writing an unowned file into a
# package-owned location now would collide with it later.
cat > /etc/apt/sources.list.d/drumee.sources <<SOURCES
Types: deb
URIs: $APT_URL
Suites: $APT_SUITE
Components: $APT_COMPONENT
Signed-By: $KEYRING_PATH
SOURCES

# Retire the flat stanza if this box has one. Left in place it keeps pulling from a
# repository that no longer receives releases, and once the flat files are eventually
# withdrawn every `apt update` on the box fails. Re-running this script is therefore
# also the migration path off flat.
if [ -f /etc/apt/sources.list.d/drumee.list ]; then
  echo "==> Migrating off the frozen flat repository (removing drumee.list)"
  rm -f /etc/apt/sources.list.d/drumee.list
fi

echo "==> apt update"
apt-get update

# Drumee's runtime deps require Node.js >= 20 (e.g. the ESM-only mariadb npm), but
# Debian/Ubuntu ship Node 18 or older. Ensure Node 22 (current LTS) from NodeSource
# so the packages' `nodejs (>= 20)` dependency resolves with a supported, non-EOL
# Node (matches the container channel's node:22 base). NodeSource's nodejs bundles npm.
node_major="$(command -v node >/dev/null 2>&1 && node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "${node_major:-0}" -lt 22 ]; then
  echo "==> Installing Node.js 22 (NodeSource); current: ${node_major:-none}"
  command -v curl >/dev/null || apt-get install -y curl ca-certificates
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

# drumee-infra renders MariaDB's conffiles (50-server.cnf/50-client.cnf), so when
# mariadb-server installs afterward dpkg would prompt about the conffile conflict
# and abort on a closed stdin. Keep the Drumee-rendered versions automatically.
CONFOPTS=(-o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)

# BIND9, ahead of Drumee and unconditionally.
#
# Two of the five TLS methods need this host to be authoritative for its own
# zone: acme-dns-server (the default — the DNS-01 challenge is answered by a
# local nsupdate) and self-signed, i.e. every LAN-only install, where nothing
# else on the network knows the domain and the name would otherwise resolve
# nowhere at all. drumee-infra only Recommends bind9, and a Recommends is not an
# ordering constraint: apt may configure drumee-infra first, and its postinst
# would then try to start a nameserver that dpkg has unpacked but not yet set
# up. Installing it in its own transaction first removes the race.
#
# Unconditional because the method is chosen later, by debconf, during the
# install below — this script does not know it yet. That is not a leak: when the
# zone belongs at a DNS provider (acme-dns-api, caddy, own), drumee-infra's
# postinst stands named back down rather than letting it answer for a domain
# served elsewhere.
if ! command -v named >/dev/null 2>&1; then
  echo "==> Installing BIND9 (serves this instance's zone; stood down if unused)"
  apt-get install -y "${CONFOPTS[@]}" bind9 bind9-utils
fi

set_selections() { # set_selections <key> <type> <value>
  command -v debconf-set-selections >/dev/null || apt-get install -y debconf-utils
  printf 'drumee-infra\tdrumee-infra/%s\t%s\t%s\n' "$1" "$2" "$3" | debconf-set-selections
}

# --- prompt helpers ----------------------------------------------------------
# All four read the keyboard, never stdin, and all four are no-ops when the answer
# is already known: an env value is used as given, and without a terminal the
# default is taken. So the same call sites serve the interactive and the
# unattended-without-preseed paths, and both end up preseeding the same keys.
say() { printf '%s\n' "$*" >"$TTY"; }

# ask <var-value> <default> <label> [required]  -> echoes the answer
ask() {
  local cur="$1" def="$2" label="$3" required="${4:-}" answer=""
  if [ -n "$cur" ]; then printf '%s' "$cur"; return 0; fi
  if ! interactive; then printf '%s' "$def"; return 0; fi
  while :; do
    if [ -n "$def" ]; then printf '  %s [%s] ' "$label" "$def" >"$TTY"
    else                   printf '  %s ' "$label" >"$TTY"; fi
    IFS= read -r answer <"$TTY" || answer=""
    [ -z "$answer" ] && answer="$def"
    if [ -z "$answer" ] && [ "$required" = required ]; then
      say "    required — please enter a value"
      continue
    fi
    printf '%s' "$answer"; return 0
  done
}

# ask_bool <var-value> <default true|false> <label> -> echoes true|false
ask_bool() {
  local cur="$1" def="$2" label="$3" hint answer=""
  if [ -n "$cur" ]; then
    case "$cur" in true|yes|1) printf 'true' ;; *) printf 'false' ;; esac
    return 0
  fi
  if ! interactive; then printf '%s' "$def"; return 0; fi
  [ "$def" = true ] && hint='[Y/n]' || hint='[y/N]'
  printf '  %s %s ' "$label" "$hint" >"$TTY"
  IFS= read -r answer <"$TTY" || answer=""
  case "$answer" in
    y|Y|yes|YES) printf 'true' ;;
    n|N|no|NO)   printf 'false' ;;
    *)           printf '%s' "$def" ;;      # bare Enter keeps the default
  esac
}

# ask_select <var-value> <default> <label> <choice…> -> echoes the chosen choice
ask_select() {
  local cur="$1" def="$2" label="$3"; shift 3
  local choices=("$@") i answer=""
  if [ -n "$cur" ]; then printf '%s' "$cur"; return 0; fi
  if ! interactive; then printf '%s' "$def"; return 0; fi
  while :; do
    printf '  %s\n' "$label" >"$TTY"
    for i in "${!choices[@]}"; do
      printf '    %d) %s\n' "$((i + 1))" "${choices[$i]}" >"$TTY"
    done
    printf '  choice [%s] ' "$def" >"$TTY"
    IFS= read -r answer <"$TTY" || answer=""
    [ -z "$answer" ] && { printf '%s' "$def"; return 0; }
    # accept either the number or the name itself
    case "$answer" in
      *[!0-9]*) for i in "${choices[@]}"; do
                  [ "$answer" = "$i" ] && { printf '%s' "$i"; return 0; }
                done ;;
      *) if [ "$answer" -ge 1 ] && [ "$answer" -le "${#choices[@]}" ] 2>/dev/null; then
           printf '%s' "${choices[$((answer - 1))]}"; return 0
         fi ;;
    esac
    say "    not one of the choices"
  done
}

# ask_secret <var-value> <label> -> echoes the answer, never echoes the typing
ask_secret() {
  local cur="$1" label="$2" answer=""
  if [ -n "$cur" ]; then printf '%s' "$cur"; return 0; fi
  if ! interactive; then printf ''; return 0; fi
  printf '  %s ' "$label" >"$TTY"
  IFS= read -rs answer <"$TTY" || answer=""
  printf '\n' >"$TTY"
  printf '%s' "$answer"
}

# --- network topology --------------------------------------------------------
# The shape of the whole install follows from what addresses this host actually
# has, so it is settled before anything is asked:
#
#   wan        at least one public address  -> ACME can work, tls_method is a real
#                                              choice, the box serves a public name
#   lan        no public, one or more private -> nothing delegates its name and no
#                                              CA can validate it: self-signed,
#                                              local_mode, and BIND9 serving the
#                                              zone for the LAN
#   localhost  neither                      -> nothing to serve to anyone else
#
# Loopback and link-local never reach the classifier: the kernel is asked for
# `scope global` addresses only. Private means RFC1918, CGNAT (100.64/10) and
# IPv6 ULA (fc00::/7) — CGNAT is not RFC1918 but is just as unreachable from
# outside, which is the only property that matters here.
DRUMEE_BRANCH=""          # wan | lan | localhost
PUB4=""; PUB6=""; PRIV4=""; PRIV6=""

detect_topology() {
  local ip
  # `|| true` on the pipelines: `set -o pipefail` would otherwise take the whole
  # installer down on a host with no iproute2 or no address of that family.
  for ip in $(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true); do
    case "$ip" in
      10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) PRIV4="${PRIV4:-$ip}" ;;
      100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) PRIV4="${PRIV4:-$ip}" ;;
      *) PUB4="${PUB4:-$ip}" ;;
    esac
  done
  for ip in $(ip -o -6 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true); do
    case "${ip,,}" in
      f[cd]*) PRIV6="${PRIV6:-$ip}" ;;
      [23]*)  PUB6="${PUB6:-$ip}" ;;
      *)      PRIV6="${PRIV6:-$ip}" ;;
    esac
  done

  if   [ -n "$PUB4$PUB6" ];   then DRUMEE_BRANCH=wan
  elif [ -n "$PRIV4$PRIV6" ]; then DRUMEE_BRANCH=lan
  else                             DRUMEE_BRANCH=localhost
  fi
}

# --- the questions -----------------------------------------------------------
# Order, conditions and defaults mirror infra/debian/config and
# infra/debian/templates. They must stay in step: a question asked here is marked
# seen, so debconf will not ask it — if this asked the wrong thing, or skipped one
# that config asks at "high" priority, the difference lands silently in the
# rendered configuration.
#
# Why ask here at all, rather than let debconf do it: debconf only asks when it
# has a terminal, and on the documented `curl … | sudo bash` path stdin is the
# pipe. It would take every default without a word. On top of that, config asks
# db_dir, data_dir, backup_location, exchange_location and the wireguard ports at
# medium/low priority, which the default debconf priority never shows at all.
collect_answers() {
  detect_topology

  if interactive; then
    say ""
    say "  Drumee setup — press Enter to accept the value in brackets."
    say ""
    case "$DRUMEE_BRANCH" in
      wan)       say "  Detected a PUBLIC address (${PUB4:-$PUB6}): this instance can serve the"
                 say "  Internet and hold a real certificate." ;;
      lan)       say "  Detected only PRIVATE addresses (${PRIV4:-$PRIV6}): nothing outside this"
                 say "  network can reach it as things stand." ;;
      localhost) say "  Detected NO routable address: configuring a localhost-only instance." ;;
    esac
  fi

  # A private-address box has two ways to be useful, and they are mutually
  # exclusive by construction, not by preference: render.mjs rejects
  # wireguard.enabled together with instance.local_mode (config/render.mjs:210),
  # and infra/debian/config skips the wireguard questions entirely when local_mode
  # is true. So the choice is made once, here, and the domain, the certificate and
  # local_mode all follow from it.
  if [ "$DRUMEE_BRANCH" = lan ]; then
    if interactive && [ -z "$DRUMEE_LAN_MODE" ]; then
      say ""
      say "  How should this instance be reached?"
      say "    dns        LAN only. BIND9 runs here and serves the zone for your"
      say "               domain, so the name resolves for every client you point at"
      say "               this host — nothing else on the network knows it. The"
      say "               certificate is self-signed: no authority can validate a"
      say "               name that is delegated nowhere."
      say "    wireguard  Reachable from outside with NO router port opened. The node"
      say "               holds an outbound connection to a coordination server,"
      say "               which pairs it with clients so both sides punch their own"
      say "               firewall. Traffic stays peer-to-peer and end-to-end"
      say "               encrypted. A real certificate becomes possible, over"
      say "               DNS-01 — also outbound-only."
    fi
    DRUMEE_LAN_MODE=$(ask_select "$DRUMEE_LAN_MODE" dns "Reachability:" dns wireguard)
  fi

  # Branch-derived defaults. local_mode is what infra's config script reads back
  # to force self-signed and to skip the wireguard questions, so the two travel
  # together; the domain is not the literal string "local", and does not need to
  # be — config only *asks* local_mode when it is, and never overwrites a
  # preseeded answer.
  local def_domain def_admin def_serve4 def_serve6 branch_local
  case "$DRUMEE_BRANCH" in
    wan)       def_domain="example.com"; branch_local=false
               def_serve4="${PUB4:--}";  def_serve6="${PUB6:--}" ;;
    lan)       def_serve4="${PRIV4:--}"; def_serve6="${PRIV6:--}"
               if [ "$DRUMEE_LAN_MODE" = wireguard ]; then
                 # Reachable from outside, so a real name and a real certificate
                 # both make sense — and local_mode would be refused outright.
                 def_domain="example.com"; branch_local=false
               else
                 def_domain="drumee.lan";  branch_local=true
               fi ;;
    localhost) def_domain="localhost";   branch_local=true
               def_serve4="-";           def_serve6="-" ;;
  esac
  # whoami is root under `sudo bash`, which is nobody's mailbox; SUDO_USER is the
  # operator who actually ran the install. Keyed on branch_local rather than on the
  # branch, so a wireguard-reachable lan box gets a real administrator address.
  if [ "$branch_local" = true ]; then def_admin="${SUDO_USER:-$(whoami)}@localhost"
  else def_admin="admin@example.com"; fi

  echo "==> Topology: $DRUMEE_BRANCH${DRUMEE_LAN_MODE:+/$DRUMEE_LAN_MODE}" \
       "(public4=${PUB4:-none} public6=${PUB6:-none}" \
       "private4=${PRIV4:-none} private6=${PRIV6:-none})"

  # Only when there is something to lose, and with the same test infra's config
  # script uses (a drumee.json naming a non-empty domain).
  if [ -f /etc/drumee/drumee.json ] \
     && grep -qE '"domain_name"[[:space:]]*:[[:space:]]*"[^"]+"' /etc/drumee/drumee.json 2>/dev/null; then
    if interactive; then
      say ""
      say "  This host is already configured. Re-rendering adopts this version's"
      say "  configuration fixes and overwrites hand edits under /etc/drumee,"
      say "  /etc/nginx, /etc/bind, Prosody and Postfix. Passwords are kept."
    fi
    DRUMEE_RECONFIGURE_EXISTING=$(ask_bool "$DRUMEE_RECONFIGURE_EXISTING" false \
      "Re-generate the configuration of this existing instance?")
    set_selections reconfigure_existing boolean "$DRUMEE_RECONFIGURE_EXISTING"
  fi

  interactive && say ""
  DRUMEE_DESCRIPTION=$(ask "$DRUMEE_DESCRIPTION" "My Great Drumee Team" "Instance label")
  set_selections description string "$DRUMEE_DESCRIPTION"

  # --- the address that serves Drumee ---------------------------------------
  # infra's config script never asks these, but its postinst reads them, so on
  # the interactive path they were always empty and infra.js skipped the entire
  # public branch — no nginx 01-public.conf, no public/reverse BIND zones, no
  # postfix/opendkim. The select answer *is* the address unless it reads "other",
  # in which case the free-text one carries it; that pair is what gets preseeded.
  #
  # Detected values are offered as interactive defaults only. Unattended they stay
  # unset unless the env says otherwise: the address of the default route is
  # usually the LAN one, and preseeding it as *public* would quietly change the
  # meaning of every existing unattended install.
  if [ "$DRUMEE_BRANCH" != localhost ]; then
    if interactive; then
      say ""
      say "  Which address should serve Drumee? \"-\" leaves a family unset."
    else
      def_serve4="-"; def_serve6="-"
    fi
    DRUMEE_PUBLIC_IP4=$(ask "$DRUMEE_PUBLIC_IP4" "$def_serve4" "IPv4 address")
    DRUMEE_PUBLIC_IP6=$(ask "$DRUMEE_PUBLIC_IP6" "$def_serve6" "IPv6 address")
    if [ -n "$DRUMEE_PUBLIC_IP4" ] && [ "$DRUMEE_PUBLIC_IP4" != "-" ]; then
      set_selections ip4        select "other"
      set_selections public_ip4 string "$DRUMEE_PUBLIC_IP4"
    fi
    if [ -n "$DRUMEE_PUBLIC_IP6" ] && [ "$DRUMEE_PUBLIC_IP6" != "-" ]; then
      set_selections ip6        select "other"
      set_selections public_ip6 string "$DRUMEE_PUBLIC_IP6"
    fi
  fi

  # --- domain ---------------------------------------------------------------
  if interactive && [ "$DRUMEE_BRANCH" = wan ]; then
    say ""
    say "  The domain this instance serves."
  fi
  DRUMEE_DOMAIN=$(ask "$DRUMEE_DOMAIN" "$def_domain" "Domain name" required)
  set_selections domain string "$DRUMEE_DOMAIN"

  # Exactly one of the two, on the same condition config uses. A wan install is
  # public by construction; lan and localhost are not, and say so.
  if [ "$branch_local" = true ] || [ "$DRUMEE_DOMAIN" = "local" ]; then
    DRUMEE_LOCAL_MODE=$(ask_bool "$DRUMEE_LOCAL_MODE" true \
      "Confirm this instance stays on the local network only?")
  else
    DRUMEE_LOCAL_MODE=false
    DRUMEE_SERVICE=$(ask "$DRUMEE_SERVICE" "" "Optional services to enable (comma-separated, empty for none)")
    set_selections service string "$DRUMEE_SERVICE"
  fi
  # ALWAYS preseeded, including the false case. drumee-infra 1.2.26 also writes
  # this value itself, so the two agree — but stating it here is what makes this
  # script correct against an older drumee-infra, where the template defaulted to
  # true and an unanswered local_mode therefore meant "LAN-only": config read that
  # back and forced `db_set tls_method self-signed` over whatever was chosen,
  # without ever showing the tls_method question. A preseed carrying local_mode was
  # the only thing that escaped it.
  set_selections local_mode boolean "$DRUMEE_LOCAL_MODE"

  DRUMEE_ADMIN_EMAIL=$(ask "$DRUMEE_ADMIN_EMAIL" "$def_admin" \
    "Administrator email (also the admin login)" required)
  set_selections admin_email string "$DRUMEE_ADMIN_EMAIL"

  # --- storage --------------------------------------------------------------
  if interactive; then
    say ""
    say "  Storage paths. None of these may be a native system path (/usr, /sys …),"
    say "  and the backup should sit on a different partition from the data."
  fi
  DRUMEE_DB_DIR=$(ask "$DRUMEE_DB_DIR" "/srv/db" "Database directory")
  set_selections db_dir string "$DRUMEE_DB_DIR"
  DRUMEE_DATA_DIR=$(ask "$DRUMEE_DATA_DIR" "/data" "Filesystem storage directory")
  set_selections data_dir string "$DRUMEE_DATA_DIR"
  DRUMEE_BACKUP_LOCATION=$(ask "$DRUMEE_BACKUP_LOCATION" "" \
    "Backup location (path or host:/path, empty for none)")
  set_selections backup_location string "$DRUMEE_BACKUP_LOCATION"
  DRUMEE_EXCHANGE_LOCATION=$(ask "$DRUMEE_EXCHANGE_LOCATION" "/exchangearea" "Exchange area")
  set_selections exchange_location string "$DRUMEE_EXCHANGE_LOCATION"

  # --- TLS ------------------------------------------------------------------
  # Only a wan box gets a choice. On lan and localhost no certificate authority
  # can validate the name — nothing delegates it — so self-signed is the only
  # honest answer, and it is also the path that installs BIND9 to serve the zone
  # locally, which is what makes the name usable on the LAN at all.
  if [ "$DRUMEE_LOCAL_MODE" = true ]; then
    DRUMEE_TLS_METHOD=self-signed
  elif [ "$DRUMEE_LAN_MODE" = wireguard ]; then
    # Outbound-only methods only. acme-dns-server is deliberately absent: it
    # answers the challenge from a BIND9 that the CA has to reach on inbound
    # udp/53, which is precisely what this box does not have — offering it would
    # be offering a choice that cannot succeed.
    if interactive; then
      say ""
      say "  Drumee needs a WILDCARD certificate, and only a DNS-01 challenge can"
      say "  issue one. These are the methods that work with no inbound port:"
      say ""
      say "    acme-dns-api     challenge via your DNS provider's API (any provider"
      say "                     acme.sh supports). You publish the zone yourself."
      say "    caddy            drumee-caddy issues the certs itself over DNS-01 and"
      say "                     fronts nginx. Needs the drumee-caddy package."
      say "    own              you already have wildcard certs; no ACME, no DNS here."
      say "    self-signed      no public certificate — clients will warn."
    fi
    DRUMEE_TLS_METHOD=$(ask_select "$DRUMEE_TLS_METHOD" acme-dns-api "DNS and TLS handling:" \
      acme-dns-api caddy own self-signed)
  else
    if interactive; then
      say ""
      say "  Drumee needs a WILDCARD certificate, which only a DNS-01 challenge can"
      say "  issue. This answer decides both how that challenge is answered and who"
      say "  runs DNS for the domain:"
      say ""
      say "    acme-dns-server  BIND9 runs here as the authoritative nameserver and"
      say "                     answers the challenge locally. Needs NS delegation"
      say "                     and inbound udp/53 — NOT possible behind a router."
      say "    acme-dns-api     challenge via your DNS provider's API. Outbound only,"
      say "                     so it works behind NAT. You publish the zone yourself."
      say "    caddy            drumee-caddy issues the certs and fronts nginx on"
      say "                     80/443. Outbound only. Needs the drumee-caddy package."
      say "    own              you already have wildcard certs; no ACME, no DNS here."
    fi
    DRUMEE_TLS_METHOD=$(ask_select "$DRUMEE_TLS_METHOD" acme-dns-server "DNS and TLS handling:" \
      acme-dns-server acme-dns-api caddy own)
  fi
  set_selections tls_method select "$DRUMEE_TLS_METHOD"

  # Whatever the chosen method needs, and nothing else.
  case "$DRUMEE_TLS_METHOD" in
    own)
      if interactive; then
        say ""
        say "  The directory must already hold the certificates, in the acme.sh"
        say "  layout — <dir>/<name>_ecc/{fullchain.cer,ca.cer,<name>.key} — and"
        say "  cover the apex, *.apex, jit, *.jit, vendors and *.vendors."
      fi
      DRUMEE_OWN_SSL_PATH=$(ask "$DRUMEE_OWN_SSL_PATH" "" "Certificate directory" required)
      set_selections own_ssl_path string "$DRUMEE_OWN_SSL_PATH"
      ;;
    acme-dns-api)
      if interactive; then
        say ""
        say "  A shell file, mode 0600, that exports ACME_PROVIDER (an acme.sh dnsapi"
        say "  name without the dns_ prefix) plus that provider's variables. It must"
        say "  exist before the package is configured."
      fi
      DRUMEE_ACME_ENV_FILE=$(ask "$DRUMEE_ACME_ENV_FILE" "/etc/drumee/credential/dns-api.env" \
        "DNS provider credentials file")
      set_selections acme_env_file string "$DRUMEE_ACME_ENV_FILE"
      ;;
    caddy)
      DRUMEE_CADDY_DOMAIN=$(ask "$DRUMEE_CADDY_DOMAIN" "$DRUMEE_DOMAIN" "Zone to certify with Caddy")
      set_selections caddy_domain string "$DRUMEE_CADDY_DOMAIN"
      DRUMEE_CADDY_DNS_PROVIDER=$(ask "$DRUMEE_CADDY_DNS_PROVIDER" "" \
        "caddy-dns module the binary was built with (ovh, cloudflare, …)" required)
      set_selections caddy_dns_provider string "$DRUMEE_CADDY_DNS_PROVIDER"
      # Never echoed, and written to a 0600 file by the postinst.
      DRUMEE_CADDY_DNS_API_KEY=$(ask_secret "$DRUMEE_CADDY_DNS_API_KEY" "DNS provider API token (not echoed):")
      set_selections caddy_dns_api_key password "$DRUMEE_CADDY_DNS_API_KEY"
      ;;
  esac

  # ACME account email — only where a certificate is actually issued.
  case "$DRUMEE_TLS_METHOD" in
    acme-*|caddy)
      DRUMEE_ACME_EMAIL=$(ask "$DRUMEE_ACME_EMAIL" "$DRUMEE_ADMIN_EMAIL" "ACME account email")
      set_selections acme_email string "$DRUMEE_ACME_EMAIL"
      ;;
  esac

  # --- WireGuard ------------------------------------------------------------
  # Pointless on a box that is only reachable on its own LAN, and config skips it
  # there too.
  if [ "$DRUMEE_LOCAL_MODE" = true ]; then
    WIREGUARD_ENABLED=false
  else
    # On the lan branch this was already chosen as the reachability method, so
    # don't ask the same thing twice — a non-empty value makes ask_bool a no-op.
    if [ "$DRUMEE_LAN_MODE" = wireguard ]; then WIREGUARD_ENABLED=true; fi
    if [ -z "$WIREGUARD_ENABLED" ] && interactive; then
      say ""
      say "  Remote access without opening a router port?"
      say "    WireGuard peer coordination keeps an outbound connection to a"
      say "    coordination server, which pairs this node with clients so both sides"
      say "    punch their own firewall. Traffic is peer-to-peer and end-to-end"
      say "    encrypted; the server only does signaling. Useful for a box on a home"
      say "    LAN — pointless if this instance is already reachable on 443."
    fi
    WIREGUARD_ENABLED=$(ask_bool "$WIREGUARD_ENABLED" false "Enable WireGuard coordination?")
    if [ "$WIREGUARD_ENABLED" = "true" ]; then
      WIREGUARD_COORDINATOR=$(ask "$WIREGUARD_COORDINATOR" "$WIREGUARD_COORDINATOR" "Coordination server host")
      # The listen port must stay fixed: the agent learns its NAT mapping by
      # probing from this exact port.
      WIREGUARD_LISTEN_PORT=$(ask "$WIREGUARD_LISTEN_PORT" "$WIREGUARD_LISTEN_PORT" "WireGuard listen port (UDP)")
      WIREGUARD_REFLECTOR_PORT=$(ask "$WIREGUARD_REFLECTOR_PORT" "$WIREGUARD_REFLECTOR_PORT" "Reflector port on the coordination server")
    fi
  fi
  set_selections wireguard_enabled        boolean "$WIREGUARD_ENABLED"
  set_selections wireguard_coordinator    string  "$WIREGUARD_COORDINATOR"
  set_selections wireguard_listen_port    string  "$WIREGUARD_LISTEN_PORT"
  set_selections wireguard_reflector_port string  "$WIREGUARD_REFLECTOR_PORT"

  echo "==> Answers recorded: branch=$DRUMEE_BRANCH domain=$DRUMEE_DOMAIN" \
       "tls=$DRUMEE_TLS_METHOD local_mode=$DRUMEE_LOCAL_MODE wireguard=$WIREGUARD_ENABLED"
}

if [ -n "$PRESEED" ]; then
  [ -f "$PRESEED" ] || { echo "error: PRESEED file not found: $PRESEED" >&2; exit 1; }
  echo "==> Applying preseed for unattended install"
  command -v debconf-set-selections >/dev/null || apt-get install -y debconf-utils
  debconf-set-selections < "$PRESEED"
  # render.mjs always emits the four wireguard_* keys, so the preseed decides.
  echo "==> Installing drumee (noninteractive)"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${CONFOPTS[@]}" drumee
else
  collect_answers
  echo "==> Installing drumee"
  # Hand apt the terminal even though every drumee-infra question is now answered
  # and marked seen: its *dependencies* still have debconf questions of their own
  # (postfix's mail configuration, for one), and without this they would inherit
  # the curl pipe as stdin and fall back to defaults.
  if interactive; then
    apt-get install -y "${CONFOPTS[@]}" drumee <"$TTY"
  else
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${CONFOPTS[@]}" drumee
  fi
fi

echo "Done. Manage with the 'drumee' CLI (drumee status, drumee log, ...)."
