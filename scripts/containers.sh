#!/bin/bash
# Drumee one-command installer — the "easy path".
#
#   curl -fsSL https://get.drumee.com/install | bash      # interactive: asks 3-4 questions, then installs
#   scripts/containers.sh                         # same, from a checkout
#
# One run does everything: checks (and can install) Docker, asks how people will
# reach the server, writes the config, generates secrets, renders the stack,
# starts it, waits until it is healthy, and prints the URL + admin login.
#
# Nothing to hand-edit. Re-running is safe (re-renders + re-applies).
#
# Non-interactive / automation (skip the questions by presetting these):
#   DRUMEE_DOMAIN=         # domain name, or blank for IP/local
#   ACCESS_MODE=           # domain | ip | local | wireguard  (how to reach it)
#   WIREGUARD_ENABLED=     # true = also coordinate a WireGuard tunnel (any mode
#                          #   except local); implied by ACCESS_MODE=wireguard
#   WIREGUARD_COORDINATOR= # coordination server host (default coord.drumee.tech)
#   ADMIN_EMAIL=           # administrator login + notifications
#   ADMIN_PASSWORD=        # blank = auto-generate and print
#   INSTANCE_NAME=         # human label for the instance
#   IMAGE_REGISTRY=        # where to pull images (default ghcr.io/drumee)
#   SERVER_TAG=            # image tag to pull (default latest); forces the pull path
#   DRUMEE_DIR=./drumee    # where to install
#   ASSUME_YES=1           # auto-confirm install prompts (Docker install, etc.)
#   DRUMEE_NONINTERACTIVE=1# never prompt; every value from env or default
#   RECONFIGURE=1          # overwrite an existing drumee.yaml (default: keep it)
#   DRUMEE_NO_START=1      # render the files but don't start (CI / inspection)
set -uo pipefail

# ----------------------------------------------------------------------------- ui
# Colour on a real terminal (or FORCE_COLOR=1), unless NO_COLOR: keeps logs clean.
if { [ -t 1 ] || [ "${FORCE_COLOR:-0}" = "1" ]; } && [ -z "${NO_COLOR:-}" ]; then
  c_cyan=$'\033[38;5;44m'; c_grn=$'\033[1;32m'; c_yel=$'\033[1;33m'; c_red=$'\033[1;31m'
  c_dim=$'\033[2m'; c_bold=$'\033[1m'; c_off=$'\033[0m'
else c_cyan=; c_grn=; c_yel=; c_red=; c_dim=; c_bold=; c_off=; fi
c_blue="$c_cyan"   # back-compat for prompt helpers below
# Glyphs (UTF-8) with ASCII fallback for legacy terminals.
case "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" in
  *[Uu][Tt][Ff]*) G_OK=$'✓'; G_NO=$'✗'; G_WARN=$'⚠'; BAR=$'▌'; RULE=$'───────────────────────────────────────────────';;
  *) G_OK="OK"; G_NO="x"; G_WARN="!"; BAR="|"; RULE="--------------------------------------------------";;
esac
say()  { printf "    ${c_dim}%s %s${c_off}\n" "·" "$*"; }   # secondary note under a step
ok()   { printf "    ${c_grn}%s${c_off} %s\n" "$G_OK" "$*"; }
warn() { printf "    ${c_yel}%s${c_off} %s\n" "$G_WARN" "$*"; }
die()  { printf "\n  ${c_red}%s %s${c_off}\n\n" "$G_NO" "$*" >&2; exit 1; }
hr()   { printf "  ${c_dim}%s${c_off}\n" "$RULE"; }
step() { printf "\n  ${c_cyan}%s${c_off} ${c_bold}%s${c_off}\n" "$BAR" "$*"; }   # phase header
kv()   { printf "    ${c_dim}%-9s${c_off} %s\n" "$1" "$2"; }                      # aligned key/value
banner() {
  printf "\n  ${c_cyan}%s${c_off} ${c_bold}Drumee${c_off}  ${c_dim}self-host installer${c_off}\n" "$BAR"
  hr
}

# Prompts must read from the terminal even under `curl … | bash` (where stdin is
# the script). /dev/tty is the real keyboard; fall back to defaults if absent.
TTY=/dev/tty
# DRUMEE_NONINTERACTIVE=1 forces the no-prompt path (CI/automation), even when a
# terminal is attached: every value must then come from an env var or default.
have_tty() { [ "${DRUMEE_NONINTERACTIVE:-0}" = "1" ] && return 1; { true <"$TTY"; } 2>/dev/null; }
ask() { # ask <var> <prompt> <default>   — env override wins; blank answer -> default
  local __v="$1" __p="$2" __d="$3" __a="" __e="${!1:-}"
  if [ -n "$__e" ]; then printf -v "$__v" '%s' "$__e"; return; fi
  if have_tty; then
    printf "  %s ${c_dim}[%s]${c_off} " "$__p" "${__d:-}" >"$TTY"
    IFS= read -r __a <"$TTY" || true
  fi
  [ -z "$__a" ] && __a="$__d"
  printf -v "$__v" '%s' "$__a"
}
ask_secret() { # ask_secret <var> <prompt>   — hidden input; env override wins
  local __v="$1" __p="$2" __a="" __e="${!1:-}"
  if [ -n "$__e" ]; then printf -v "$__v" '%s' "$__e"; return; fi
  if have_tty; then
    printf "  %s ${c_dim}(blank = auto-generate)${c_off} " "$__p" >"$TTY"
    IFS= read -rs __a <"$TTY" || true; printf "\n" >"$TTY"
  fi
  printf -v "$__v" '%s' "$__a"
}
confirm() { # confirm <prompt>   — default YES; ASSUME_YES / no TTY -> yes
  [ "${ASSUME_YES:-0}" = "1" ] && return 0
  have_tty || return 0
  local __a=""; printf "  %s ${c_dim}[Y/n]${c_off} " "$1" >"$TTY"; IFS= read -r __a <"$TTY" || true
  case "${__a,,}" in n|no) return 1;; *) return 0;; esac
}
confirm_no() { # confirm_no <prompt>  — default NO; ASSUME_YES does NOT force it
  have_tty || return 1                # unattended -> keep the safe default (no)
  local __a=""; printf "  %s ${c_dim}[y/N]${c_off} " "$1" >"$TTY"; IFS= read -r __a <"$TTY" || true
  case "${__a,,}" in y|yes) return 0;; *) return 1;; esac
}
valid_email() { [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; }
yaml_get() { awk -F': *' -v k="  $1:" '$0 ~ "^"k {print $2; exit}' drumee.yaml; }

case "${1:-}" in
  -h|--help)
    # Print the leading comment block (skip the shebang, stop at the first code line).
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]:-$0}" 2>/dev/null \
      || echo "Drumee installer — see https://get.drumee.com"
    exit 0 ;;
esac

# --------------------------------------------------------------------- locate src
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || echo)"
RELEASE_BASE="${RELEASE_BASE:-https://get.drumee.com}"
[ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/config/render.mjs" ] || REPO_ROOT=""
fetch() { # fetch <relative-path> <dest>
  local rel="$1" dest="$2"
  if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/$rel" ]; then cp "$REPO_ROOT/$rel" "$dest"
  else curl -fsSL "$RELEASE_BASE/$rel" -o "$dest"; fi
}

banner

# ------------------------------------------------------------- 1. ensure Docker
step "Checking Docker"
ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    warn "Docker is not installed."
    if confirm "Install Docker now? (uses the official get.docker.com script, needs sudo)"; then
      say "Installing Docker"
      curl -fsSL https://get.docker.com | sudo sh || die "Docker install failed — install manually: https://docs.docker.com/engine/install/"
      sudo systemctl enable --now docker 2>/dev/null || sudo service docker start 2>/dev/null || true
    else
      die "Docker is required. Install: https://docs.docker.com/engine/install/"
    fi
  fi
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required (the 'docker compose' command)."
  # Pick the right docker invocation (with or without sudo).
  if docker info >/dev/null 2>&1; then DOCKER="docker"
  elif sudo -n true 2>/dev/null && sudo docker info >/dev/null 2>&1; then DOCKER="sudo docker"; warn "Using sudo for Docker (add yourself to the 'docker' group to avoid this)."
  elif sudo docker info >/dev/null 2>&1; then DOCKER="sudo docker"; warn "Using sudo for Docker."
  else die "Cannot talk to the Docker daemon (is it running? do you have permission?)."; fi
  ok "Docker ready"
}
ensure_docker

# ---------------------------------------------------------- 2. choose where + how
DRUMEE_DIR="${DRUMEE_DIR:-./drumee}"
mkdir -p "$DRUMEE_DIR"; cd "$DRUMEE_DIR"; DRUMEE_DIR="$(pwd)"

# An existing config is KEPT by default (idempotent re-runs). Reconfigure only on
# an explicit RECONFIGURE=1 or an interactive "yes" (default no).
reconfigure=1
if [ -f drumee.yaml ]; then
  if [ "${RECONFIGURE:-0}" = "1" ]; then reconfigure=1
  elif confirm_no "Found an existing config ($DRUMEE_DIR/drumee.yaml). Reconfigure?"; then reconfigure=1
  else reconfigure=0; fi
fi
step "Configuration"
if [ "$reconfigure" = "0" ]; then
  say "Keeping existing config — re-rendering and (re)starting."
else
  say "Answer a few questions. Press Enter to accept the [default]."
  echo

  ask INSTANCE_NAME "Name for this instance" "My Drumee"

  # Detect a public IPv4 so we can offer the no-domain HTTPS path (unless preset).
  PUBIP="${PUBIP:-}"
  if [ -z "$PUBIP" ]; then
    PUBIP="$(curl -fsS --max-time 4 https://api.ipify.org 2>/dev/null || true)"
    [ -z "$PUBIP" ] && PUBIP="$(curl -fsS --max-time 4 https://icanhazip.com 2>/dev/null | tr -d '[:space:]' || true)"
  fi
  is_public_ip() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ ! "$1" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|127\.) ]]; }
  default_mode="local"; is_public_ip "${PUBIP:-}" && default_mode="ip"

  if [ -z "${ACCESS_MODE:-}" ]; then
    printf "  ${c_bold}How will people reach this server?${c_off}\n"
    printf "    ${c_cyan}1${c_off}  A domain you own             ${c_dim}real HTTPS — best for production${c_off}\n"
    printf "    ${c_cyan}2${c_off}  This server's IP, no domain  ${c_dim}auto HTTPS via sslip.io${c_off}${PUBIP:+ ${c_dim}·${c_off} ${c_cyan}$PUBIP${c_off}}\n"
    printf "    ${c_cyan}3${c_off}  Local / testing only         ${c_dim}http://localhost, no HTTPS${c_off}\n"
    printf "    ${c_cyan}4${c_off}  Behind a home router         ${c_dim}no port to open — WireGuard coordination${c_off}\n"
    case "$default_mode" in ip) def="2";; *) def="3";; esac
    ask MENU "Choose 1-4" "$def"
    case "$MENU" in
      1) ACCESS_MODE=domain;; 2) ACCESS_MODE=ip;; 4) ACCESS_MODE=wireguard;; *) ACCESS_MODE=local;;
    esac
  fi

  case "$ACCESS_MODE" in
    domain)
      ask DRUMEE_DOMAIN "Your domain (DNS A-record must point here)" "example.com"
      [ "$DRUMEE_DOMAIN" = "example.com" ] && warn "example.com is a placeholder — TLS will fail until you use a real domain."
      TLS_MODE=acme; LOCAL_MODE=false ;;
    ip)
      is_public_ip "${PUBIP:-}" || ask PUBIP "This server's public IP" ""
      [ -n "${PUBIP:-}" ] || die "Need a public IP for the no-domain path; re-run and pick a domain or local."
      DRUMEE_DOMAIN="${PUBIP//./-}.sslip.io"; TLS_MODE=acme; LOCAL_MODE=false
      warn "Using $DRUMEE_DOMAIN — ports 80 and 443 must be open to the internet for HTTPS." ;;
    wireguard)
      # No inbound port, so ACME's HTTP-01 challenge cannot be answered: TLS is a
      # local CA cert, and clients reach the box through the tunnel rather than DNS.
      ask DRUMEE_DOMAIN "Name for this instance (used in links, reached via the tunnel)" "drumee.local"
      TLS_MODE=self-signed; LOCAL_MODE=false; WIREGUARD_ENABLED=true
      say "Nothing to forward on the router — the node dials out to the coordination server." ;;
    *)
      DRUMEE_DOMAIN="localhost"; TLS_MODE=self-signed; LOCAL_MODE=true ;;
  esac

  # Coordination is meaningless on a LAN-only instance (there is no NAT to
  # traverse), and render.mjs rejects the combination outright.
  [ "$LOCAL_MODE" = "true" ] && WIREGUARD_ENABLED=false
  WIREGUARD_ENABLED="${WIREGUARD_ENABLED:-false}"
  if [ "$WIREGUARD_ENABLED" = "true" ]; then
    ask WIREGUARD_COORDINATOR "Coordination server host" "coord.drumee.tech"
  fi

  ask ADMIN_EMAIL "Administrator email (your login)" "admin@${DRUMEE_DOMAIN}"
  while ! valid_email "$ADMIN_EMAIL"; do
    warn "\"$ADMIN_EMAIL\" doesn't look like an email address."
    have_tty || die "ADMIN_EMAIL is invalid: $ADMIN_EMAIL"
    ADMIN_EMAIL=""; ask ADMIN_EMAIL "Administrator email (your login)" "admin@${DRUMEE_DOMAIN}"
  done
  ask_secret ADMIN_PASSWORD "Administrator password"

  # ---- pick images: locally-built (tag :local) if present, else pull from a
  #      published registry (default ghcr.io/drumee). One tag for all four images.
  if [ -z "${SERVER_TAG:-}" ] && $DOCKER image inspect drumee/server-pod:local >/dev/null 2>&1; then
    REGISTRY="drumee"; TAG="local"; ok "Found locally-built images — using tag :local"
  else
    REGISTRY="${IMAGE_REGISTRY:-ghcr.io/drumee}"; TAG="${SERVER_TAG:-latest}"
    say "No local images — will pull from ${REGISTRY} (tag: ${TAG})."
  fi

  # ---- write drumee.yaml (only what the user chose; rest defaults/auto-gen) ----
  acme_line=""; [ "$TLS_MODE" = "acme" ] && acme_line="  acme_email: ${ADMIN_EMAIL}"
  ver_block="versions:"$'\n'"  server: ${TAG}"$'\n'"  ui: ${TAG}"$'\n'"  schemas: ${TAG}"$'\n'"  static: ${TAG}"
  {
    echo "instance:"
    echo "  description: ${INSTANCE_NAME}"
    echo "  domain: ${DRUMEE_DOMAIN}"
    echo "  local_mode: ${LOCAL_MODE}"
    echo "  admin_email: ${ADMIN_EMAIL}"
    echo "tls:"
    echo "  mode: ${TLS_MODE}"
    [ -n "$acme_line" ] && echo "$acme_line"
    echo "storage:"
    echo "  data_dir: ${DRUMEE_DIR}/data"
    echo "  db_dir: ${DRUMEE_DIR}/db"
    echo "database:"
    echo "  host: mariadb"
    echo "redis:"
    echo "  host: redis"
    # Must stay ABOVE images:/versions: — use_local_images() rewrites the file
    # from ^images: to EOF when it falls back to locally-built images.
    if [ "$WIREGUARD_ENABLED" = "true" ]; then
      echo "wireguard:"
      echo "  enabled: true"
      echo "  coordinator: ${WIREGUARD_COORDINATOR:-coord.drumee.tech}"
    fi
    echo "images:"
    echo "  registry: ${REGISTRY}"
    echo "$ver_block"
  } > drumee.yaml
  ok "Wrote $DRUMEE_DIR/drumee.yaml"
fi

# Resolve the values the summary/image step need from the config on disk, so the
# "keep existing config" path (where the wizard block was skipped) works too.
DRUMEE_DOMAIN="${DRUMEE_DOMAIN:-$(yaml_get domain)}"
ADMIN_EMAIL="${ADMIN_EMAIL:-$(yaml_get admin_email)}"
REGISTRY="${REGISTRY:-$(yaml_get registry)}"
TAG="${TAG:-$(yaml_get server)}"   # versions.server doubles as the shared image tag
# 'enabled' only ever appears under wireguard: in the file we write.
WIREGUARD_ENABLED="${WIREGUARD_ENABLED:-$(yaml_get enabled)}"
WIREGUARD_ENABLED="${WIREGUARD_ENABLED:-false}"

# --- image acquisition: ensure the images exist (pull) or can be built ---------
have_sources() { [ -d "$HOME/server-team" ] && [ -d "$HOME/ui-team" ] && [ -d "$HOME/schemas" ]; }
use_local_images() {  # switch config to the just-built :local images and re-point vars
  REGISTRY="drumee"; TAG="local"
  sed -i '/^images:/,$d' drumee.yaml
  { echo "images:"; echo "  registry: drumee"; echo "versions:";
    for k in server ui schemas static; do echo "  $k: local"; done; } >> drumee.yaml
  ok "Built images locally — using tag :local"
}
build_or_die() {
  if [ -n "$REPO_ROOT" ] && [ -x "$REPO_ROOT/scripts/build-images-local.sh" ] && have_sources; then
    if confirm "Component sources detected. Build the images locally now? (~several minutes)"; then
      "$REPO_ROOT/scripts/build-images-local.sh" || die "Image build failed."
      use_local_images; return
    fi
  fi
  die "Images aren't available at ${REGISTRY}/…:${TAG}, and can't be built here.
    Publish them once (maintainer):  REGISTRY=ghcr.io/drumee TAG=<version> scripts/publish-images.sh
    or build from source (needs the component repos):  scripts/build-images-local.sh"
}
ensure_images() {
  step "Fetching images"
  if [ "$TAG" = "local" ]; then
    $DOCKER image inspect drumee/server-pod:local >/dev/null 2>&1 && { ok "Using local images (tag :local)"; return; }
    warn "Tag :local selected but the images aren't built."; build_or_die; return
  fi
  say "Pulling ${REGISTRY}/server-pod:${TAG} …"
  if $DOCKER pull "${REGISTRY}/server-pod:${TAG}" >/dev/null 2>&1; then ok "Images available from ${REGISTRY}"
  else warn "Could not pull ${REGISTRY}/server-pod:${TAG} (registry public? logged in?)."; build_or_die; fi
}
# Coordination ships as its own image. If it isn't there, keep the rest of the
# stack working: turn coordination off with a clear message instead of letting
# `compose up` abort on an unresolvable image.
ensure_wireguard_image() {
  [ "$WIREGUARD_ENABLED" = "true" ] || return 0
  local ref="${REGISTRY}/wireguard:${TAG}"
  if [ "$TAG" = "local" ]; then
    $DOCKER image inspect drumee/wireguard:local >/dev/null 2>&1 \
      && { ok "WireGuard agent image ready (:local)"; return 0; }
  elif $DOCKER pull "$ref" >/dev/null 2>&1; then
    ok "WireGuard agent image ready (${ref})"; return 0
  fi
  warn "WireGuard agent image unavailable (${ref}) — coordination left off."
  say "Build it with scripts/build-images-local.sh, then re-run with RECONFIGURE=1."
  sed -i 's/^  enabled: true$/  enabled: false/' drumee.yaml 2>/dev/null || true
  WIREGUARD_ENABLED=false
}
# Skip in render-only mode (don't touch Docker); otherwise run before render so a
# build-fallback's :local switch is reflected in the rendered compose.
[ "${DRUMEE_NO_START:-0}" = "1" ] || { ensure_images; ensure_wireguard_image; }

# --------------------------------------------------------------- 3. render + run
step "Rendering deployment files"
if [ -n "$REPO_ROOT" ]; then render_cmd=(node "$REPO_ROOT/config/render.mjs" all --config drumee.yaml --out-dir .)
else
  # render.mjs reads drumee.schema.json from next to itself — fetch both.
  fetch config/render.mjs render.mjs
  fetch config/drumee.schema.json drumee.schema.json
  render_cmd=(node render.mjs all --config drumee.yaml --out-dir .)
fi
if ! render_out="$("${render_cmd[@]}" 2>&1)"; then echo "$render_out" | sed 's/^/    /'; die "Rendering failed."; fi
[ -f docker-compose.yml ] && [ -f .env ] || die "Render did not produce docker-compose.yml/.env"
ok "Wrote .env, docker-compose.yml, Caddyfile"

# Provision the admin on first boot (idempotent in the populate step).
grep -q '^CREATE_ADMIN=' .env || echo "CREATE_ADMIN=1" >> .env
if [ -n "${ADMIN_PASSWORD:-}" ] && ! grep -q '^ADMIN_PASSWORD=' .env; then
  echo "ADMIN_PASSWORD=${ADMIN_PASSWORD}" >> .env
fi

# Make the data/db dirs the compose volumes expect.
dd="$(grep -E '^DRUMEE_DATA_DIR=' .env | cut -d= -f2-)"; bb="$(grep -E '^DRUMEE_DB_DIR=' .env | cut -d= -f2-)"
mkdir -p "${dd:-$DRUMEE_DIR/data}" "${bb:-$DRUMEE_DIR/db}" 2>/dev/null || sudo mkdir -p "$dd" "$bb"

# Render-only mode (CI / inspection): produce the files but don't start anything.
if [ "${DRUMEE_NO_START:-0}" = "1" ]; then
  ok "Rendered into $DRUMEE_DIR (DRUMEE_NO_START=1 — not starting)."; exit 0
fi

step "Starting Drumee"
say "First run initializes the database — this can take a couple of minutes."
if ! up_out="$($DOCKER compose --env-file .env up -d 2>&1)"; then
  echo "$up_out" | sed 's/^/    /'
  if echo "$up_out" | grep -qiE 'address already in use|port is already allocated|bind for'; then
    die "Ports 80/443 are already in use. Stop the other web server (nginx/apache, or another Drumee stack) and re-run."
  fi
  die "docker compose up failed (see output above)."
fi

# ------------------------------------------------------------------- 4. wait + show
say "Waiting for first-run setup (schema · UI build · accounts)…"
DC="$DOCKER compose --env-file .env"
[ -t 1 ] && printf "    ${c_dim}"
populate_done=""; for _ in $(seq 1 120); do
  st="$($DC ps -a --format '{{.Service}}:{{.State}}:{{.ExitCode}}' 2>/dev/null | grep '^schemas-populate:' || true)"
  echo "$st" | grep -q ':exited:0' && { populate_done=1; break; }
  echo "$st" | grep -qE ':exited:[1-9]' && { populate_done=fail; break; }
  [ -t 1 ] && printf "·"
  sleep 5
done
[ -t 1 ] && printf "${c_off}\n"
[ "$populate_done" = "fail" ] && warn "schemas-populate failed — logs: $DC logs schemas-populate"
[ "$populate_done" = "1" ] && ok "Database initialized + admin provisioned"

# Once the admin exists, scrub the password from .env so it doesn't sit in
# plaintext, and stop re-provisioning on future re-runs (the account is created).
if [ "$populate_done" = "1" ] && grep -q '^ADMIN_PASSWORD=' .env 2>/dev/null; then
  sed -i '/^ADMIN_PASSWORD=/d' .env 2>/dev/null && sed -i 's/^CREATE_ADMIN=.*/CREATE_ADMIN=0/' .env 2>/dev/null \
    && ok "Removed the admin password from .env"
fi

# Wait for the app to answer (server-pod healthy).
healthy=""; for _ in $(seq 1 30); do
  $DC ps --format '{{.Service}}:{{.Status}}' 2>/dev/null | grep -q '^server-pod:.*healthy' && { healthy=1; break; }; sleep 4
done

# --------------------------------------------------------------- 5. management CLI
# Put drumee-ctl (+ its drumee-plugin helper) on PATH so management commands work
# without a checkout. Prefer /usr/local/bin; fall back to the install dir.
step "Installing the drumee-ctl CLI"
bindir=/usr/local/bin
if [ -w "$bindir" ] || sudo -n true 2>/dev/null; then SUDO=""; [ -w "$bindir" ] || SUDO=sudo
else bindir="$DRUMEE_DIR/bin"; SUDO=""; mkdir -p "$bindir"; fi
cli_ok=1
for tool in drumee-ctl drumee-plugin; do
  if fetch "bin/$tool" "/tmp/$tool.$$" 2>/dev/null; then
    $SUDO install -m 0755 "/tmp/$tool.$$" "$bindir/$tool" 2>/dev/null || cli_ok=""
    rm -f "/tmp/$tool.$$"
  else cli_ok=""; fi
done
if [ -n "$cli_ok" ]; then
  case ":$PATH:" in *":$bindir:"*) ok "Installed drumee-ctl to $bindir";;
    *) ok "Installed drumee-ctl to $bindir"; say "add it to PATH:  export PATH=\"$bindir:\$PATH\"";; esac
else warn "Could not install drumee-ctl automatically (get it from $RELEASE_BASE/bin/drumee-ctl)."; fi

# Apply any declared plugins (render emits plugins.json from drumee.yaml's plugins:).
if [ -f plugins.json ] && [ -n "$healthy" ]; then
  step "Installing declared plugins"
  DRUMEE_DIR="$DRUMEE_DIR" "$bindir/drumee-ctl" plugin apply plugins.json 2>&1 | sed 's/^/    /' \
    || warn "plugin apply failed — run: drumee-ctl plugin apply plugins.json"
fi

if [ "$DRUMEE_DOMAIN" = "localhost" ]; then URL="http://localhost/"; else URL="https://${DRUMEE_DOMAIN}/"; fi
echo
if [ -n "$healthy" ]; then
  printf "  ${c_grn}%s${c_off} ${c_bold}Drumee is up.${c_off}\n" "$G_OK"
else
  printf "  ${c_yel}%s${c_off} ${c_bold}Drumee is starting${c_off} ${c_dim}— give it a minute, then open the URL below.${c_off}\n" "$G_WARN"
fi
hr
kv "Open" "${c_cyan}${URL}${c_off}"
if [ "$WIREGUARD_ENABLED" = "true" ]; then
  kv "Tunnel" "WireGuard via ${WIREGUARD_COORDINATOR:-coord.drumee.tech} ${c_dim}· no router port needed${c_off}"
  say "needs the host's wireguard module: sudo modprobe wireguard  ·  logs: $DC logs wireguard"
fi
kv "Login" "$ADMIN_EMAIL"
if [ -n "${ADMIN_PASSWORD:-}" ]; then
  kv "Password" "${c_dim}(the one you set)${c_off}"
else
  cred="$($DC logs schemas-populate 2>/dev/null | grep -aiE 'password:|init link|reset' | tail -3)"
  if [ -n "$cred" ]; then kv "Password" "${c_dim}(see setup log below)${c_off}"; echo "$cred" | sed "s/^/      ${c_dim}/;s/$/${c_off}/"
  else kv "Password" "${c_dim}run: $DC logs schemas-populate${c_off}"; fi
fi
hr
kv "Status" "${c_dim}cd $DRUMEE_DIR && $DOCKER compose ps${c_off}"
kv "Health" "${c_dim}DRUMEE_DIR=$DRUMEE_DIR drumee-ctl doctor${c_off}"
kv "Stop" "${c_dim}cd $DRUMEE_DIR && $DOCKER compose down${c_off}"
echo
