#!/bin/bash
# Install the locally-built drumee .debs in a DISPOSABLE privileged debian:12
# container and report how far the native install gets toward serving. The host
# is never touched. Skips drumee-static (no source) and the metapackage; installs
# infra -> schemas -> server -> ui directly via a local apt repo so system deps
# (mariadb/nginx/redis/nodejs/…) resolve.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || { echo "error: docker unavailable" >&2; exit 1; }

# node-runtime is in the glob because drumee-server-pod Depends on it (it supplies
# pm2, which Debian does not package). Left out, apt refuses the whole app install
# with "drumee-node-runtime but it is not installable" and the test reports a broken
# install that has nothing to do with the packages under test.
debs=$(find "$root"/{infra,schemas,server,ui,node-runtime}/build -name '*.deb' 2>/dev/null)
[ -n "$debs" ] || { echo "error: no .debs built (run the */build.sh first)" >&2; exit 1; }
echo "==> packages:"; echo "$debs" | sed 's#.*/#   #'

# Stage repo + preseed for the container.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo"; cp $debs "$tmp/repo/"
cat > "$tmp/drumee.yaml" <<YAML
instance:
  description: Native Verify
  domain: local
  local_mode: true
  admin_email: admin@local
tls:
  mode: self-signed
YAML
node "$root/config/render.mjs" debconf --config "$tmp/drumee.yaml" > "$tmp/install.conf" 2>/dev/null || true
# local_mode preseed (domain 'local' triggers the local branch in the wizard/bridge)
grep -q drumee-infra "$tmp/install.conf" 2>/dev/null || echo "drumee-infra drumee-infra/domain string local" > "$tmp/install.conf"

echo "==> launching debian:12 (privileged, for services)…"
# The script is MOUNTED and stdin is /dev/null, rather than piped in via `bash -s`.
# Fed on stdin, dpkg's conffile prompt for /etc/mysql/mariadb.conf.d/50-client.cnf
# (infra renders that file, so mariadb-client's version clashes with it) read the
# rest of THIS SCRIPT as its answers: everything from the pool-entity report onwards
# — the server-pod/ui-pod install, the app start probe and the summary — was
# silently swallowed, and the test still exited 0, reporting success while never
# testing the app at all. CONFOPTS below stops the prompt happening in the first
# place; this mount stops any future prompt from eating the script.
cat > "$tmp/run.sh" <<'INNER'
set -u
export DEBIAN_FRONTEND=noninteractive
log(){ printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

# The same options scripts/baremetal.sh passes, and for the same reason:
# drumee-infra renders MariaDB's conffiles (50-server.cnf / 50-client.cnf), so when
# mariadb-client is configured afterwards dpkg finds a file "created by you or by a
# script" and asks what to do. Without these the prompt reads stdin — it was eating
# the rest of this script when it was fed by heredoc — and with stdin closed it
# fails outright, taking mariadb-client, mariadb-server, drumee-schemas and every
# mariadb plugin with it, so server-pod and ui-pod are then held back. The test has
# to install the way the documented installer installs, or it tests nothing.
CONFOPTS=(-o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)

log "base tooling + local repo"
apt-get update -qq >/dev/null
apt-get install -y -qq dpkg-dev debconf-utils curl >/dev/null
# Allow service start/stop in this container (Debian's image ships a deny-all
# policy-rc.d; setup-schemas/bin/install needs to start MariaDB).
printf '#!/bin/sh\nexit 0\n' > /usr/sbin/policy-rc.d; chmod +x /usr/sbin/policy-rc.d
cp -r /in/repo /tmp/repo
# Stub drumee-static to satisfy server-pod's Depends (no static source to build).
mkdir -p /tmp/stub/DEBIAN
printf 'Package: drumee-static\nVersion: 1.0.0\nArchitecture: all\nMaintainer: t <t@d>\nDepends: drumee-infra\nDescription: stub static for the install test\n' > /tmp/stub/DEBIAN/control
dpkg-deb -Znone -b /tmp/stub /tmp/repo/drumee-static_stub.deb >/dev/null
( cd /tmp/repo && dpkg-scanpackages -m . > Packages 2>/dev/null )
echo "deb [trusted=yes] file:/tmp/repo ./" > /etc/apt/sources.list.d/drumee.list
apt-get update -qq 2>/dev/null

log "Node 22 (NodeSource) — required by the runtime deps (Debian ships 18)"
curl -fsSL https://deb.nodesource.com/setup_22.x 2>/dev/null | bash - >/dev/null 2>&1
apt-get install -y -qq nodejs >/dev/null 2>&1
echo "  node: $(node --version 2>/dev/null)"

log "preseed debconf"
debconf-set-selections < /in/install.conf || true

log "install drumee-infra (renders config + credentials)"
apt-get install -y "${CONFOPTS[@]}" drumee-infra </dev/null 2>&1 | tail -40 || true
echo "  --- setup-infra log (if any) ---"; tail -25 /var/log/drumee/*.log 2>/dev/null | sed 's/^/    /' || echo "    (none)"
echo "  drumee.sh present? $([ -f /etc/drumee/drumee.sh ] && echo yes || echo NO)"
echo "  db.json present?   $([ -f /etc/drumee/credential/db.json ] && echo yes || echo NO)"
echo "  /etc/drumee contents:"; ls -R /etc/drumee 2>/dev/null | head -30 | sed 's/^/    /'

log "install drumee-schemas (DB restore + populate + stockFactory)"
# NOT piped through `tail -N`. The truncation discarded the actual mariadb-server
# configure failure — the only thing that explains drumee-schemas ending up
# unconfigured — leaving a log that showed the symptom and not the cause.
apt-get install -y "${CONFOPTS[@]}" drumee-schemas </dev/null 2>&1 || echo "  !! apt returned $? for drumee-schemas"
echo "MARK schemas-step-done"
echo "  dpkg state:"; dpkg -l 'drumee-*' 'mariadb-server' 2>/dev/null | awk '/^[a-z]/{printf "    %-6s %-28s %s\n", $1, $2, $3}'

# `set +u` around the source. drumee.sh is rendered per install, and an unset
# variable inside it aborts this entire script under `set -u` — a candidate for why
# every step below here silently failed to run in earlier runs.
set +u
[ -f /etc/drumee/drumee.sh ] && . /etc/drumee/drumee.sh 2>/dev/null
set -u
echo "MARK sourced-drumee-sh"
echo "  pool entities: $(mariadb -N -B -e "SELECT COUNT(*) FROM yp.entity WHERE area='pool'" 2>/dev/null || echo '?')"
echo "  system acct:   $(mariadb -N -B -e "SELECT COUNT(*) FROM yp.drumate WHERE category='system'" 2>/dev/null || echo '?')"
echo "MARK db-report-done"

log "install drumee-server-pod + drumee-ui-pod"
apt-get install -y "${CONFOPTS[@]}" drumee-server-pod drumee-ui-pod </dev/null 2>&1 | tail -40 || true
echo "MARK app-packages-step-done"

log "the shutdown-hang regression checks (2.9.96)"
# Gated on the package actually being configured: an absent /usr/sbin/drumee means
# "server-pod never installed", not "the fix regressed", and conflating the two turns
# an install failure into a false accusation against the package.
if dpkg-query -W -f='${Status}' drumee-server-pod 2>/dev/null | grep -q 'install ok installed'; then
  echo "  /etc/init.d/drumee        $([ -e /etc/init.d/drumee ] && echo 'PRESENT — REGRESSION' || echo 'absent (correct)')"
  echo "  /etc/rc3.d/S02drumee      $([ -e /etc/rc3.d/S02drumee ] && echo 'PRESENT — REGRESSION' || echo 'absent (correct)')"
  echo "  /etc/rc6.d/K01drumee      $([ -e /etc/rc6.d/K01drumee ] && echo 'PRESENT — REGRESSION' || echo 'absent (correct)')"
  echo "  /usr/sbin/drumee          $([ -x /usr/sbin/drumee ] && echo 'present (correct)' || echo 'MISSING — REGRESSION')"
  echo "  unit ExecStart            $(grep -h '^ExecStart=' /lib/systemd/system/drumee-server-pod.service 2>/dev/null || echo '?')"
else
  echo "  SKIPPED — drumee-server-pod is not installed, so nothing to check."
fi

log "start app (drumee CLI -> pm2) + probe"
[ -x /usr/sbin/drumee ] && /usr/sbin/drumee start 2>&1 | tail -5 || echo "  no /usr/sbin/drumee"
sleep 8
echo "  pm2: $(su -s /bin/bash ${DRUMEE_SYSTEM_USER:-www-data} -c 'HOME='"${DRUMEE_SERVER_HOME:-/srv/drumee/runtime/server}"' pm2 ls' 2>/dev/null | grep -cE 'online|main' || echo '?') procs"
echo "  GET :23000  -> $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:23000/ 2>/dev/null || echo down)"
echo "  GET :80     -> $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:80/ 2>/dev/null || echo down)"

log "summary"
echo "  installed: $(dpkg -l 'drumee-*' 2>/dev/null | grep -c '^ii') drumee packages"
dpkg -l 'drumee-*' 2>/dev/null | grep '^ii' | awk '{print "   "$2" "$3}'
echo "MARK inner-complete"
INNER
docker run --rm --privileged -v "$tmp":/in:ro debian:12 bash /in/run.sh </dev/null 2>&1
echo "==> done"
