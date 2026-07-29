#!/bin/bash
# Drumee bare-metal bootstrap — adds the signed APT repo and installs Drumee.
#
#   curl -fsSL https://apt.drumee.net/baremetal.sh | sudo bash
#   # unattended (preseed answers first):
#   sudo PRESEED=/path/to/install.conf bash baremetal.sh
#
# The APT repo is a *flat* repository served from apt.drumee.net. APT_URL is the
# base URL; KEYRING_URL points to the GPG public key used to verify the repo.
#
# Env:
#   APT_URL      (default https://apt.drumee.net)  flat repo base
#   KEYRING_URL  (default https://apt.drumee.net/drumee-archive-keyring.asc)
#   PRESEED      (optional)  install.conf from config/render.mjs
#
# WireGuard peer coordination (asked interactively; preset to skip the question):
#   WIREGUARD_ENABLED         true | false   (default: ask, else false)
#   WIREGUARD_COORDINATOR     coordination server host (default coord.drumee.tech)
#   WIREGUARD_LISTEN_PORT     UDP port for wg0        (default 51820)
#   WIREGUARD_REFLECTOR_PORT  reflector port          (default 51821)
#   DRUMEE_NONINTERACTIVE=1   never prompt; take defaults / the env values
set -euo pipefail

APT_URL="${APT_URL:-https://apt.drumee.net}"
KEYRING_URL="${KEYRING_URL:-https://apt.drumee.net/drumee-archive-keyring.asc}"
PRESEED="${PRESEED:-}"

WIREGUARD_ENABLED="${WIREGUARD_ENABLED:-}"          # empty = not answered yet
WIREGUARD_COORDINATOR="${WIREGUARD_COORDINATOR:-coord.drumee.tech}"
WIREGUARD_LISTEN_PORT="${WIREGUARD_LISTEN_PORT:-51820}"
WIREGUARD_REFLECTOR_PORT="${WIREGUARD_REFLECTOR_PORT:-51821}"

# Prompts must read the keyboard, not stdin: on the documented
# `curl … | sudo bash` path stdin IS the script. /dev/tty is the real terminal.
TTY=/dev/tty
have_tty() { [ "${DRUMEE_NONINTERACTIVE:-0}" = "1" ] && return 1; { true <"$TTY"; } 2>/dev/null; }

[ "$(id -u)" = "0" ] || { echo "error: run as root (sudo)" >&2; exit 1; }
command -v apt-get >/dev/null || { echo "error: this installer targets Debian/Ubuntu" >&2; exit 1; }

echo "==> Adding Drumee APT repository (flat: $APT_URL)"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL "$KEYRING_URL" -o /etc/apt/keyrings/drumee.asc
# Flat repo: trailing slash on the base + "./" component (no suite/section).
echo "deb [signed-by=/etc/apt/keyrings/drumee.asc] $APT_URL/ ./" \
  > /etc/apt/sources.list.d/drumee.list

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

set_selections() { # set_selections <key> <type> <value>
  command -v debconf-set-selections >/dev/null || apt-get install -y debconf-utils
  printf 'drumee-infra\tdrumee-infra/%s\t%s\t%s\n' "$1" "$2" "$3" | debconf-set-selections
}

# --- WireGuard peer coordination ---------------------------------------------
# drumee-infra offers this over debconf, but debconf only asks when it has a
# terminal — and on the `curl … | sudo bash` path stdin is the pipe, so the
# question would silently take its default (disabled). Ask here from /dev/tty
# and preseed the answer, which also keeps interactive and unattended installs
# answering the same four keys.
ask_wireguard() {
  if [ -z "$WIREGUARD_ENABLED" ]; then
    if have_tty; then
      cat >"$TTY" <<'TXT'

  Remote access without opening a router port?
    WireGuard peer coordination keeps an outbound connection to a coordination
    server, which pairs this node with clients so both sides punch their own
    firewall. Traffic is peer-to-peer and end-to-end encrypted; the server only
    does signaling. Useful for a box on a home LAN — pointless if this instance
    is LAN-only or already reachable on 443.
TXT
      printf '  Enable WireGuard coordination? [y/N] ' >"$TTY"
      IFS= read -r answer <"$TTY" || answer=""
      case "$answer" in
        y|Y|yes|YES) WIREGUARD_ENABLED=true ;;
        *)           WIREGUARD_ENABLED=false ;;
      esac
    else
      WIREGUARD_ENABLED=false        # unattended: keep the shipped default
    fi
  fi

  if [ "$WIREGUARD_ENABLED" = "true" ] && have_tty; then
    printf '  Coordination server host [%s] ' "$WIREGUARD_COORDINATOR" >"$TTY"
    IFS= read -r answer <"$TTY" || answer=""
    [ -n "$answer" ] && WIREGUARD_COORDINATOR="$answer"
  fi

  if [ "$WIREGUARD_ENABLED" = "true" ]; then
    echo "==> WireGuard coordination enabled via $WIREGUARD_COORDINATOR (udp/$WIREGUARD_LISTEN_PORT)"
  else
    echo "==> WireGuard coordination disabled"
  fi
  set_selections wireguard_enabled        boolean "$WIREGUARD_ENABLED"
  set_selections wireguard_coordinator    string  "$WIREGUARD_COORDINATOR"
  set_selections wireguard_listen_port    string  "$WIREGUARD_LISTEN_PORT"
  set_selections wireguard_reflector_port string  "$WIREGUARD_REFLECTOR_PORT"
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
  ask_wireguard
  echo "==> Installing drumee (interactive)"
  # Hand apt the terminal too: without this, debconf's remaining questions
  # (domain, admin email, …) inherit the curl pipe as stdin and fall back to
  # defaults. Preseeded questions are marked seen and stay unasked.
  if have_tty; then
    apt-get install -y "${CONFOPTS[@]}" drumee <"$TTY"
  else
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${CONFOPTS[@]}" drumee
  fi
fi

echo "Done. Manage with the 'drumee' CLI (drumee status, drumee log, ...)."
