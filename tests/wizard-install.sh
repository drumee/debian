#!/bin/bash
# Tests for the interactive container installer (scripts/containers.sh).
# Runs it in render-only mode (DRUMEE_NO_START=1) with answers preset via env,
# so it exercises the wizard's config-building + render without starting Docker.
# Needs Node 20; Docker only used to validate the generated compose if present.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$root"
pass=0; fail=0
ok(){ printf '  \033[1;32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[1;31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
chk(){ if eval "$2" >/dev/null 2>&1; then ok "$1"; else no "$1"; fi; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
run_wizard(){ # run_wizard <subdir> <env...>
  local d="$W/$1"; shift
  env DRUMEE_DIR="$d" DRUMEE_NO_START=1 ASSUME_YES=1 DRUMEE_NONINTERACTIVE=1 "$@" \
    bash scripts/containers.sh >"$d.log" 2>&1
}

printf '\033[1;36m── installer: local mode\033[0m\n'
run_wizard local ACCESS_MODE=local INSTANCE_NAME="T" ADMIN_EMAIL=me@acme.com ADMIN_PASSWORD='S3cret!'
chk "domain=localhost"     "grep -q 'domain: localhost'   $W/local/drumee.yaml"
chk "local_mode=true"      "grep -q 'local_mode: true'    $W/local/drumee.yaml"
chk ".env written 0600"    "[ \"\$(stat -c %a $W/local/.env)\" = 600 ]"
chk "CREATE_ADMIN set"     "grep -q '^CREATE_ADMIN=1'     $W/local/.env"
chk "ADMIN_PASSWORD set"   "grep -q '^ADMIN_PASSWORD=S3cret!' $W/local/.env"
chk "compose produced"     "test -s $W/local/docker-compose.yml"
chk "Caddyfile produced"   "test -s $W/local/Caddyfile"

printf '\033[1;36m── installer: domain mode (ACME)\033[0m\n'
run_wizard dom ACCESS_MODE=domain DRUMEE_DOMAIN=cloud.acme.com ADMIN_EMAIL=me@acme.com ADMIN_PASSWORD=x
chk "domain set"           "grep -q 'domain: cloud.acme.com' $W/dom/drumee.yaml"
chk "tls mode acme"        "grep -q 'mode: acme'             $W/dom/drumee.yaml"
chk "acme_email set"       "grep -q 'acme_email: me@acme.com' $W/dom/drumee.yaml"
chk "Caddyfile has domain" "grep -q 'cloud.acme.com'         $W/dom/Caddyfile"

printf '\033[1;36m── installer: IP mode (sslip.io magic DNS)\033[0m\n'
run_wizard ip ACCESS_MODE=ip PUBIP=203.0.113.10 ADMIN_EMAIL=me@acme.com ADMIN_PASSWORD=x
chk "sslip.io domain from IP" "grep -q 'domain: 203-0-113-10.sslip.io' $W/ip/drumee.yaml"
chk "tls mode acme"           "grep -q 'mode: acme'                    $W/ip/drumee.yaml"

printf '\033[1;36m── installer: WireGuard mode (no router port)\033[0m\n'
run_wizard wg ACCESS_MODE=wireguard DRUMEE_DOMAIN=box.acme.org ADMIN_EMAIL=me@acme.com ADMIN_PASSWORD=x
chk "wireguard enabled"        "grep -q 'enabled: true'        $W/wg/drumee.yaml"
chk "coordinator default"      "grep -q 'coordinator: coord.drumee.tech' $W/wg/drumee.yaml"
chk "not local_mode"           "grep -q 'local_mode: false'    $W/wg/drumee.yaml"
# No inbound port means ACME's HTTP-01 challenge can never be answered.
chk "tls falls back to local CA" "grep -q 'mode: self-signed'  $W/wg/drumee.yaml"
chk "env WIREGUARD_ENABLED"     "grep -q '^WIREGUARD_ENABLED=true' $W/wg/.env"
chk "wireguard profile on"      "grep -q '^COMPOSE_PROFILES=.*wireguard' $W/wg/.env"
chk "compose has the service"   "grep -q '^  wireguard:'       $W/wg/docker-compose.yml"
# Opt-in on a normal domain install, and refused on a LAN-only one (render.mjs
# rejects wireguard.enabled together with instance.local_mode).
run_wizard wgdom ACCESS_MODE=domain DRUMEE_DOMAIN=cloud.acme.com ADMIN_EMAIL=me@acme.com ADMIN_PASSWORD=x WIREGUARD_ENABLED=true
chk "opt-in on domain mode"    "grep -q '^WIREGUARD_ENABLED=true' $W/wgdom/.env"
run_wizard wgloc ACCESS_MODE=local ADMIN_EMAIL=me@acme.com ADMIN_PASSWORD=x WIREGUARD_ENABLED=true
chk "forced off in local mode" "grep -q '^WIREGUARD_ENABLED=false' $W/wgloc/.env"

printf '\033[1;36m── installer: published-registry pull path\033[0m\n'
# Forcing SERVER_TAG selects the pull path; DRUMEE_NO_START keeps it from actually
# pulling/building, so we just assert the generated config is consistent.
run_wizard pull ACCESS_MODE=local ADMIN_EMAIL=me@acme.com ADMIN_PASSWORD=x SERVER_TAG=2.9.45
chk "registry = ghcr.io/drumee"   "grep -q 'registry: ghcr.io/drumee' $W/pull/drumee.yaml"
chk "all 4 image tags = 2.9.45"   "[ \$(grep -c ': 2.9.45' $W/pull/drumee.yaml) -eq 4 ]"
chk "env IMAGE_REGISTRY set"       "grep -q '^IMAGE_REGISTRY=ghcr.io/drumee' $W/pull/.env"
chk "env SERVER_TAG set"           "grep -q '^SERVER_TAG=2.9.45' $W/pull/.env"
# IMAGE_REGISTRY override is honored.
run_wizard reg ACCESS_MODE=local ADMIN_EMAIL=me@acme.com ADMIN_PASSWORD=x SERVER_TAG=1.0 IMAGE_REGISTRY=registry.example.com/drumee
chk "registry override honored"   "grep -q 'registry: registry.example.com/drumee' $W/reg/drumee.yaml"

printf '\033[1;36m── installer: input validation + safety\033[0m\n'
# --help works and doesn't start anything.
chk "--help exits 0"          "bash scripts/containers.sh --help"
# Invalid admin email is rejected up front (non-interactive -> die, non-zero).
run_wizard bad ACCESS_MODE=local ADMIN_EMAIL='not-an-email' ADMIN_PASSWORD=x
chk "invalid email rejected"  "test -f $W/bad.log && ! test -f $W/bad/docker-compose.yml"
# Re-running with an existing config (keep path) must not crash (set -u / unbound).
run_wizard reuse ACCESS_MODE=local ADMIN_EMAIL=me@acme.com ADMIN_PASSWORD=x
chk "second run keeps config"  "env DRUMEE_DIR=$W/reuse DRUMEE_NO_START=1 ASSUME_YES=1 DRUMEE_NONINTERACTIVE=1 bash scripts/containers.sh"
chk "domain preserved on reuse" "grep -q 'domain: localhost' $W/reuse/drumee.yaml"

if docker compose version >/dev/null 2>&1; then
  printf '\033[1;36m── installer: generated compose is valid\033[0m\n'
  for d in local dom ip wg; do
    chk "compose config -q ($d)" "docker compose -f $W/$d/docker-compose.yml --env-file $W/$d/.env config -q"
  done
fi

printf '\n\033[1m== installer: %d passed, %d failed ==\033[0m\n' "$pass" "$fail"
[ "$fail" = 0 ]
