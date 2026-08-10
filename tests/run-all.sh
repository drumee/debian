#!/bin/bash
# Run every test that needs no private source and no published images.
# Safe to run on any machine with Node 20 (Docker optional — used only to
# validate the generated compose if the daemon is reachable).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
pass=0; fail=0
hdr()  { printf '\n\033[1;36m── %s\033[0m\n' "$*"; }
good() { printf '  \033[1;32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
run()  { if eval "$2" >/dev/null 2>&1; then good "$1"; else bad "$1"; fi; }

hdr "1. Shell syntax (bash -n)"
# The extensionless scripts matter as much as the *.sh ones and were never swept: the
# role entrypoints, the healthchecks and the schemas bootstrap are all shell, all shipped
# in drumee-bootstrap, and all run as PID 1 of a container. A syntax error there is a
# crash-loop with no output. Noticed when a script moved out of *.sh and the pass count
# silently dropped by one.
# ...filtered by type, not by name: that directory also holds populate.js, and `bash -n`
# on JavaScript fails for the obvious reason. Node files are checked below.
for f in $(git ls-files '*.sh' 'bin/*' 'bootstrap/usr/lib/drumee/*/*' 'infra/debian/config' 2>/dev/null | grep -v '/src/' | grep -vE '\.js$'); do
  [ -f "$f" ] || continue   # skip files deleted from the worktree (e.g. unstaged removals)
  run "$f" "bash -n '$f'"
done

# The shipped JavaScript, checked the same way for the same reason: populate.js runs inside
# a run-once job where a syntax error is an exit code and nothing else.
if command -v node >/dev/null 2>&1; then
  for f in $(git ls-files 'bootstrap/usr/lib/drumee/*/*.js' 2>/dev/null); do
    run "$f" "node --check '$f'"
  done
fi

hdr "2. Renderer parses"
run "config/render.mjs (node --check)" "node --check config/render.mjs"

hdr "3. Config smoke suite (10 assertions)"
if tests/smoke-config.sh >/dev/null 2>&1; then good "smoke-config.sh"; else bad "smoke-config.sh"; fi

hdr "4. Version drift guard"
run "release manifest matches changelogs" "scripts/check-versions.sh"

hdr "5. End-to-end render from example config"
rm -rf "$root/out"
cp config/drumee.example.yaml config/drumee.yaml
run "render: validate" "node config/render.mjs validate --config config/drumee.yaml"
run "render: all (.env + compose + install.conf)" "node config/render.mjs all --config config/drumee.yaml --out-dir out"
run "out/.env produced"            "test -s out/.env"
run "out/docker-compose.yml produced" "test -s out/docker-compose.yml"
run "out/install.conf produced"    "test -s out/install.conf"

hdr "6. Generated compose validity"
if docker compose version >/dev/null 2>&1; then
  cp deploy/docker/Caddyfile out/Caddyfile
  run "docker compose config -q" "docker compose -f out/docker-compose.yml --env-file out/.env config -q"
else
  printf '  \033[1;33mSKIP\033[0m docker compose not installed\n'
fi

hdr "7. Operator CLI guards"
run "drumee-ctl usage guard" "DRUMEE_DIR=/nonexistent bin/drumee-ctl bogus; test \$? -ne 0"

hdr "8. Installer wizard (render-only)"
if tests/wizard-install.sh >/dev/null 2>&1; then good "wizard-install.sh"; else bad "wizard-install.sh"; fi

hdr "9. Native channel packaging metadata"
if tests/native/control-deps.sh >/dev/null 2>&1; then good "native/control-deps.sh"; else bad "native/control-deps.sh"; fi

hdr "10. Channel parity — one fact, one place"
if tests/config-parity.sh >/dev/null 2>&1; then good "config-parity.sh"; else bad "config-parity.sh"; fi

printf '\n\033[1m== %d passed, %d failed ==\033[0m\n' "$pass" "$fail"
[ "$fail" = 0 ]
