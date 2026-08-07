#!/bin/bash
# The same lifecycle assertions as tests/native/upgrade-reconfigure.sh, but against a
# REAL box over ssh — because two of the properties cannot be observed in a container
# at all, and both of them have already shipped broken:
#
#   * NetworkManager regenerates /etc/resolv.conf at boot from the connection profile.
#     drumee-infra 1.2.28 wrote 127.0.0.1 with `nmcli +ipv4.dns`, which APPENDS, so the
#     regenerated file listed a public resolver first and the box asked it for its own
#     domain. glibc does not fall through on NXDOMAIN, so that answer is final. Docker
#     re-creates the resolv.conf bind mount on every container start, so the container
#     harness cannot see this either way.
#   * a kernel reboot, and anything below systemd. drumee-server-pod 2.9.95-2.9.97 hung
#     shutdown for five minutes on a synthesized sysv unit; a container restart is a
#     systemd shutdown only.
#
# It is deliberately NOT destructive: it re-renders (which is what dpkg-reconfigure
# does, and the package warns about) and reboots. It does not purge, downgrade or touch
# data. Still, point it at a disposable box.
#
#   tests/native/lifecycle-remote.sh --host=somanos@testbox --domain=drumee.lan
#   tests/native/lifecycle-remote.sh --host=... --no-reboot     # skip L5/L6
#
# Requires: ssh key access, and passwordless sudo on the target.
set -uo pipefail
pass=0; fail=0
ok(){   printf '  \033[1;32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){   printf '  \033[1;31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
note(){ printf '       \033[2m%s\033[0m\n' "$1"; }
hdr(){  printf '\n\033[1;36m── %s\033[0m\n' "$1"; }

HOST=""; DOMAIN=""; REBOOT=1
for a in "$@"; do
  case "$a" in
    --host=*)   HOST="${a#*=}" ;;
    --domain=*) DOMAIN="${a#*=}" ;;
    --no-reboot) REBOOT=0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done
[ -n "$HOST" ] || { echo "usage: $0 --host=user@host [--domain=d] [--no-reboot]"; exit 2; }

# TMO is per-command because dpkg-reconfigure re-renders 69 templates and restarts
# named, nginx and postfix: at the default it was killed part-way through, which showed
# up as "postinst ignored DEBCONF_RECONFIGURE" — the harness accusing the product of the
# exact bug it was written to detect, because it hung up on it mid-sentence.
sh_(){  timeout "${TMO:-120}" ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$1" 2>/dev/null; }
# `sudo sh -c`, not `sudo <words>`: sudo executes a COMMAND, and `for`, `if` and `[[` are
# shell keywords it cannot run. snapshot() below is a for-loop, so `sudo for f in …`
# failed silently and returned nothing — see the guard in snapshot().
sud(){  sh_ "sudo sh -c $(printf '%q' "$1")"; }
# Same, but KEEPING stderr. Needed for anything whose maintainer-script output has to be
# read: postinst sources /usr/share/debconf/confmodule, which claims stdout for the
# debconf protocol and redirects the script's own echo to stderr. So the "re-rendering
# the configuration" line arrives on stderr, and sh_'s `2>/dev/null` dropped it — the
# harness then reported "postinst ignored DEBCONF_RECONFIGURE" on a box where the
# re-render demonstrably happened, since the two assertions after it passed.
sud_err(){ timeout "${TMO:-120}" ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "sudo sh -c $(printf '%q' "$1")" 2>&1; }

echo "==> target: $HOST"
sh_ 'true' || { echo "SKIP: cannot reach $HOST over ssh"; exit 0; }
sud 'true'  || { echo "SKIP: no passwordless sudo on $HOST"; exit 0; }

# The domain the instance was installed with, read from the box rather than assumed —
# an assertion about the wrong name would pass or fail for the wrong reason.
[ -n "$DOMAIN" ] || DOMAIN="$(sud "awk -F\\\" '/domain_name/{print \$4; exit}' /etc/drumee/drumee.json" | tr -d '[:space:]')"
[ -n "$DOMAIN" ] || { echo "SKIP: no Drumee instance found on $HOST (no /etc/drumee/drumee.json)"; exit 0; }
ver="$(sh_ "dpkg-query -W -f='\${Version}' drumee-infra" || true)"
echo "==> instance: $DOMAIN   drumee-infra $ver"

WATCH="/etc/drumee/drumee.sh /etc/drumee/drumee.json /var/lib/bind/$DOMAIN /etc/nginx/sites-enabled/00-local.conf /etc/nginx/sites-enabled/01-public.conf"
# Prints __EMPTY__ rather than nothing when it finds no files. An empty result compares
# equal to another empty result, so every downstream "unchanged"/"changed" assertion
# passed or failed vacuously — L2 reported PASS on a box whose snapshot had never run.
snapshot(){
  local out
  out="$(sud "for f in $WATCH; do [ -f \"\$f\" ] && printf '%s %s\n' \"\$(sha256sum \"\$f\" | cut -c1-16)\" \"\$f\"; done | sort")"
  [ -n "$out" ] && printf '%s\n' "$out" || echo __EMPTY__
}

# ---------------------------------------------------------------------------
hdr "L1 — the instance is configured and serving before we touch it"
before="$(snapshot)"
if [ "$before" != "__EMPTY__" ]; then
  ok "rendered tree present"; printf '%s\n' "$before" | sed 's/^/       /'
else
  no "none of the watched files could be read — every assertion below would be vacuous"
  note "checked: $WATCH"
  echo; printf '\033[1m== %d passed, %d failed ==\033[0m\n' "$pass" "$fail"; exit 1
fi
code="$(sh_ "curl -sk -o /dev/null -w '%{http_code}' --max-time 15 https://$DOMAIN/" || true)"
[ "$code" = "200" ] && ok "https://$DOMAIN/ serves 200 from the box itself" \
                    || no "https://$DOMAIN/ returned '${code:-nothing}' from the box"

# ---------------------------------------------------------------------------
hdr "L2 — an apt run must not re-render"
note "operator edits under /etc must survive apt; this is why re-rendering is opt-in"
sud 'DEBIAN_FRONTEND=noninteractive apt-get update -qq' >/dev/null
TMO=900 sud 'DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef drumee' >/dev/null 2>&1
after_apt="$(snapshot)"
if [ "$before" = "$after_apt" ]; then
  ok "the rendered tree is byte-for-byte unchanged by apt"
else
  no "apt re-rendered the configuration"
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after_apt") | sed 's/^/       /'
fi

# ---------------------------------------------------------------------------
hdr "L3 — dpkg-reconfigure must re-render, and a planted defect must go"
note "this is the 1.2.31 regression: reconfigure reported success and changed nothing,"
note "so no configuration fix could reach an installed host"
SENTINEL_ADDR='fe80::dead:beef:cafe:1'
zone_ok=0
if sud "test -f /var/lib/bind/$DOMAIN"; then
  zone_ok=1
  # sud() already wraps in `sh -c`, so no second layer of quoting here.
  sud "printf '@\t\t60\tIN\tAAAA\t$SENTINEL_ADDR\n' >> /var/lib/bind/$DOMAIN"
  sud "grep -q '$SENTINEL_ADDR' /var/lib/bind/$DOMAIN" && note "planted a link-local AAAA in the zone" \
                                                       || no "could not plant the sentinel"
else
  note "no zone file — L3's sentinel leg is skipped (DNS is not served on this box)"
fi
# Baseline AFTER planting: the sentinel changes the zone's hash by itself, so measuring
# against the pre-plant snapshot would report "the tree changed" on a box where nothing
# re-rendered. That exact mistake gave a false PASS in the container harness.
planted="$(snapshot)"
TMO=900 sud_err 'DEBIAN_FRONTEND=noninteractive dpkg-reconfigure drumee-infra' > /tmp/lifecycle-reconf.$$
grep -q 're-rendering the configuration of this existing instance' /tmp/lifecycle-reconf.$$ \
  && ok "postinst took the reconfigure path (DEBCONF_RECONFIGURE honoured)" \
  || no "postinst ignored DEBCONF_RECONFIGURE — the 1.2.31 regression"
after_reconf="$(snapshot)"
[ "$after_reconf" != "$planted" ] \
  && ok "the rendered tree changed — reconfigure re-renders" \
  || no "reconfigure changed nothing, not even the sentinel"
if [ "$zone_ok" = 1 ]; then
  sud "grep -q '$SENTINEL_ADDR' /var/lib/bind/$DOMAIN" \
    && no "the planted defect survived — a shipped fix cannot reach this host" \
    || ok "the planted defect is gone — a shipped fix reaches an installed host"
fi
rm -f /tmp/lifecycle-reconf.$$

# ---------------------------------------------------------------------------
hdr "L4 — the zone and the resolver, after re-rendering"
ll="$(sud "grep -rhoiE 'AAAA[[:space:]]+fe[89ab][0-9a-f]:[^[:space:]]*' /var/lib/bind/ 2>/dev/null | grep -v '$SENTINEL_ADDR'" || true)"
[ -z "$ll" ] && ok "no link-local AAAA in any rendered zone" \
             || { no "a zone publishes a link-local address"; printf '%s\n' "$ll" | sed 's/^/       /'; }
got="$(sh_ "getent hosts $DOMAIN | awk '{print \$1; exit}'" || true)"
case "$got" in
  "")            no "the box cannot resolve $DOMAIN through nsswitch" ;;
  fe80:*|FE80:*) no "resolves to a link-local address ($got) — nothing can dial it" ;;
  *)             ok "getent resolves $DOMAIN -> $got" ;;
esac
first="$(sh_ "awk '/^nameserver/{print \$2; exit}' /etc/resolv.conf" || true)"
[ "$first" = "127.0.0.1" ] && ok "127.0.0.1 is the first nameserver" \
                           || no "first nameserver is '${first:-none}', not 127.0.0.1"

if [ "$REBOOT" != 1 ]; then
  echo; printf '\033[1m== %d passed, %d failed (reboot legs skipped) ==\033[0m\n' "$pass" "$fail"
  [ "$fail" = "0" ] || exit 1
  exit 0
fi

# ---------------------------------------------------------------------------
hdr "L5 — reboot"
note "the two legs no container can cover: NetworkManager regenerating resolv.conf,"
note "and a real kernel shutdown"
old_boot="$(sh_ 'cat /proc/sys/kernel/random/boot_id')"
note "boot id before: ${old_boot:0:8}"
sud 'sh -c "nohup sh -c \"sleep 2; systemctl reboot\" >/dev/null 2>&1 &"' >/dev/null 2>&1
t0=$(date +%s)
# Wait for a DIFFERENT boot id, not merely for ssh to answer. Waiting for ssh races the
# shutdown: the first probe succeeds against the box that is still going down, and the
# checks below then run against the pre-reboot system and pass for the wrong reason.
back=0
for _ in $(seq 1 90); do
  sleep 5
  nb="$(sh_ 'cat /proc/sys/kernel/random/boot_id' || true)"
  [ -n "$nb" ] && [ "$nb" != "$old_boot" ] && { back=1; break; }
done
if [ "$back" != 1 ]; then
  no "the box did not come back with a new boot id within 450s"
  echo; printf '\033[1m== %d passed, %d failed ==\033[0m\n' "$pass" "$fail"; exit 1
fi
ok "rebooted and back after $(( $(date +%s) - t0 ))s (boot id ${nb:0:8}, was ${old_boot:0:8})"

hdr "L6 — after the reboot"
# WAIT for the units rather than sampling them once, and do it before the rest of L6 so
# nothing else is measured against a half-booted box.
#
# sshd answers early: drumee-server-pod finished at monotonic 14.7s on the test box while
# ssh was already accepting connections at around 10s. A single sample reported
# "drumee-server-pod not active after the reboot" on a unit that was merely still
# activating — a false accusation, and an intermittent one, which is the worst kind.
#
# Waiting on `systemctl is-system-running` instead does NOT work, which is worth
# recording: on any desktop-flavoured Debian, plymouth-quit-wait.service holds until the
# splash is dismissed, which never happens on a headless box, so multi-user.target stays
# pending and the state is "starting" forever. Measured on the test box — the wait ran to
# its full bound on every run and the assertions passed only because the timeout was long
# enough to hide the race.
UNITS="drumee-server-pod nginx mariadb redis-server named"
bad="$UNITS"
for _ in $(seq 1 40); do
  bad=""
  for u in $UNITS; do
    sh_ "systemctl is-active --quiet $u" || bad="$bad $u"
  done
  [ -z "$bad" ] && break
  sleep 3
done
[ -z "$bad" ] && ok "every service came back: $UNITS" \
              || no "still not active 120s after the reboot:$bad"
first="$(sh_ "awk '/^nameserver/{print \$2; exit}' /etc/resolv.conf" || true)"
if [ "$first" = "127.0.0.1" ]; then
  ok "resolv.conf still lists 127.0.0.1 first — the resolver fix persists"
else
  no "resolv.conf now lists '${first:-none}' first — this is the 1.2.28 regression"
  sh_ 'cat /etc/resolv.conf' | sed 's/^/       /'
fi
got="$(sh_ "getent hosts $DOMAIN | awk '{print \$1; exit}'" || true)"
[ -n "$got" ] && [ "${got#fe80}" = "$got" ] \
  && ok "getent still resolves $DOMAIN -> $got" \
  || no "after the reboot the box resolves $DOMAIN to '${got:-nothing}'"
code="$(sh_ "curl -sk -o /dev/null -w '%{http_code}' --max-time 20 https://$DOMAIN/" || true)"
[ "$code" = "200" ] && ok "https://$DOMAIN/ serves 200 again" \
                    || no "https://$DOMAIN/ returned '${code:-nothing}' after the reboot"
# -t systemd: only PID 1 logs a stop-job timeout, and without the filter this matched
# sudo's OWN audit line from the previous run of this very check — the command string
# contains "stop job", so the journal recorded the search and the next run found it.
# A test that fails because it ran before is worse than no test.
to="$(sud "journalctl -b -1 -t systemd --no-pager 2>/dev/null | grep -icE 'timed out waiting for|stop job' || true" | head -1 | tr -dc '0-9')"
if [ "${to:-0}" = "0" ]; then
  ok "no stop-job timeout in the previous boot's journal"
else
  no "$to stop-job timeout message(s) during the last shutdown"
  sud "journalctl -b -1 -t systemd --no-pager 2>/dev/null | grep -iE 'timed out waiting for|stop job' | tail -5" | sed 's/^/       /'
fi
# How long the teardown itself took, from the journal rather than from wall clock, so
# BIOS and POST are not counted as Drumee's shutdown.
#
# Anchored on the LAST reboot marker, not the first "Stopped target": a unit stopping
# mid-session also logs that, so the first occurrence can be hours before the shutdown —
# it reported 2039s for a teardown that took 4.
span="$(sud "journalctl -b -1 --no-pager -o short-unix 2>/dev/null | awk '/Starting .*[Rr]eboot|systemd-shutdown\[/{s=\$1} {e=\$1} END{if(s!=\"\")printf \"%d\", e-s}'" || true)"
[ -n "$span" ] && note "teardown took ${span}s (journal, from the reboot marker — excludes POST)"

echo
printf '\033[1m== %d passed, %d failed ==\033[0m\n' "$pass" "$fail"
[ "$fail" = "0" ] || exit 1
