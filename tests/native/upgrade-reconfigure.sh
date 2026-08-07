#!/bin/bash
# The lifecycle of an ALREADY-INSTALLED instance: upgrade, reconfigure, reboot.
#
# Why this exists. Every native test in this directory covers a *fresh* install, and
# four consecutive releases shipped bugs that only a second lifecycle event could
# reveal:
#
#   1.2.28  pointed the host at its own named. Verified working, then a reboot put it
#           back — nmcli `+ipv4.dns` appends, and NetworkManager writes resolv.conf in
#           list order, so the box asked a public resolver for its own domain.
#   1.2.30  stopped publishing a link-local AAAA. Correct, and unreachable on every
#           installed host, for the reason below.
#   1.2.31  `dpkg-reconfigure drumee-infra` re-rendered nothing, on any installed host,
#           since it was written: dpkg-reconfigure runs `postinst configure`, not
#           `postinst reconfigure`, so the arm that passed --reconfigure=1 was dead
#           code, and the reachable arm ran bin/install, which called infra.js with no
#           arguments, so the "there is already an instance" guard held. The command
#           reported success and changed not one file — and it is the advice eight
#           messages in that postinst give.
#
# All three are lifecycle bugs, and a fresh-install test cannot see any of them: the
# install path was well covered and the apply-a-fix-to-an-existing-box path was not
# covered at all. That is the gap this closes.
#
# What it asserts, in order, because the order IS the property:
#
#   A1  a fresh install renders the configuration tree
#   A2  an upgrade leaves it byte-for-byte alone      (operator edits must survive)
#   A3  dpkg-reconfigure re-renders it                (1.2.31)
#   A4  a planted defect is GONE after reconfigure    (a fix can reach an installed box)
#   A5  no rendered zone publishes a link-local AAAA  (1.2.30)
#   A6  the host resolves its own domain, through nsswitch, to the A record  (1.2.29)
#   A7  a systemd reboot brings the units back, without a stop-job timeout
#   A8  no `reconfigure)` arm has come back in postinst  (static, host-side)
#
# Honest limits, so nobody reads more into a pass than is there:
#
#   * A7's reboot is a systemd shutdown and boot inside a container, not a kernel one.
#     It catches a hanging stop job, which is what bit 2.9.95-2.9.97; it cannot catch
#     anything below systemd.
#   * NetworkManager is not present, so A6 exercises the plain-resolv.conf branch of
#     point_host_at_named, NOT the nmcli branch that 1.2.28 got wrong. And Docker
#     re-creates the /etc/resolv.conf bind mount on every container start, so whether
#     the setting PERSISTS cannot be observed here at all — that is the exact property
#     1.2.28 got wrong, and it needs a real box. See the note printed at the end.
#   * drumee-infra only. Every bug above lived in the rendering/debconf layer, and
#     leaving out schemas keeps this to minutes and no seed archive.
#
# Needs Docker (privileged, for systemd) and a built drumee-infra .deb.
# SKIPs (exit 0) without them.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pass=0; fail=0
ok(){ printf '  \033[1;32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[1;31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
note(){ printf '       \033[2m%s\033[0m\n' "$1"; }
hdr(){ printf '\n\033[1;36m── %s\033[0m\n' "$1"; }

IMAGE="${IMAGE:-drumee/lifecycle-test:trixie}"
CNAME="drumee-lifecycle-$$"
DOMAIN="${DOMAIN:-drumee.lan}"

command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || { echo "SKIP: docker unavailable"; exit 0; }
command -v node   >/dev/null 2>&1 || { echo "SKIP: node unavailable"; exit 0; }

# INFRA_DEB overrides which package is exercised. Its reason for existing is that a
# harness which only ever passes proves nothing: the way to trust A3/A4 is to point
# this at a deliberately regressed package (postinst without DEBCONF_RECONFIGURE,
# bin/install without the --reconfigure forward) and watch them fail.
deb="${INFRA_DEB:-$(find "$root/infra/build" -name 'drumee-infra_*_all.deb' 2>/dev/null | sort -V | tail -1)}"
[ -n "$deb" ] && [ -f "$deb" ] || { echo "SKIP: no drumee-infra .deb built (run infra/build.sh)"; exit 0; }
ver="$(dpkg-deb -f "$deb" Version)"
echo "==> under test: $(basename "$deb")"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"; docker rm -f "$CNAME" >/dev/null 2>&1' EXIT
mkdir -p "$tmp/repo"
cp "$deb" "$tmp/repo/"

# ---------------------------------------------------------------------------
# A synthetic "previous" version: the same payload, repacked with a lower version.
#
# Deliberately not "install what the pool serves, then upgrade to local": the pool
# serves exactly one version per package, so on the normal path that is the SAME
# version and the upgrade is a no-op — a test that appears to cover the upgrade path
# while performing no upgrade at all. A repack exercises the real dpkg transition
# (prerm upgrade / postinst configure <old-version>), which is what A2 is about, and
# it needs no network and no release history.
# ---------------------------------------------------------------------------
prev="${ver}~prev1"
( set -e
  rm -rf "$tmp/prev"; dpkg-deb -R "$deb" "$tmp/prev"
  sed -i "s/^Version: .*/Version: $prev/" "$tmp/prev/DEBIAN/control"
  dpkg-deb -Znone -b "$tmp/prev" "$tmp/repo/drumee-infra_${prev}_all.deb" >/dev/null
) || { echo "SKIP: could not repack a previous version"; exit 0; }
echo "==> upgrade path: $prev  ->  $ver"

# ---- preseed ---------------------------------------------------------------
# local_mode true is the shape all three bugs lived in: it forces tls_method
# self-signed, which is the one path that turns DNS on, which is what renders a zone
# and what points the resolver at it.
cat > "$tmp/drumee.yaml" <<YAML
instance:
  description: Lifecycle Test
  domain: $DOMAIN
  local_mode: true
  admin_email: admin@$DOMAIN
tls:
  mode: self-signed
YAML
node "$root/config/render.mjs" debconf --config "$tmp/drumee.yaml" > "$tmp/install.conf" 2>/dev/null || true
grep -q "drumee-infra/domain" "$tmp/install.conf" 2>/dev/null \
  || { echo "SKIP: could not render a debconf preseed"; exit 0; }

# ---- image with systemd as PID 1 -------------------------------------------
# A real PID 1 is the point: `docker restart` then becomes an actual systemd shutdown
# followed by an actual boot, which is what A7 measures. The dependencies are baked in
# so a re-run costs seconds rather than re-fetching nginx and bind9 every time.
hdr "image"
cat > "$tmp/Dockerfile" <<'DOCKER'
FROM debian:trixie
ENV DEBIAN_FRONTEND=noninteractive container=docker
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      systemd systemd-sysv dbus \
      dpkg-dev debconf-utils ca-certificates curl procps \
      nginx libnginx-mod-stream bind9 bind9-utils bind9-dnsutils \
      nodejs git g++ cron iproute2 wireguard-tools openssh-client apt-utils binutils \
 && mkdir -p /var/log/journal \
 && printf '[Journal]\nStorage=persistent\n' > /etc/systemd/journald.conf.d-persistent.conf \
 && install -d /etc/systemd/journald.conf.d \
 && printf '[Journal]\nStorage=persistent\n' > /etc/systemd/journald.conf.d/00-persistent.conf \
 && rm -f /etc/systemd/journald.conf.d-persistent.conf \
 && rm -f /lib/systemd/system/getty.target /lib/systemd/system/multi-user.target.wants/* \
 && apt-get clean && rm -rf /var/lib/apt/lists/*
# 37 is SIGRTMIN+3, which is how you ask systemd to power off. Docker's default
# SIGTERM does NOT shut it down — the stop then always runs to the full timeout and
# ends in SIGKILL, which reads exactly like a hanging stop job. A7 would have
# reported the product broken on every run.
STOPSIGNAL 37
CMD ["/lib/systemd/systemd"]
DOCKER
if ! docker build -q -t "$IMAGE" "$tmp" >/dev/null 2>&1; then
  echo "SKIP: could not build the systemd test image"; exit 0
fi
ok "image built ($IMAGE)"

hdr "boot"
docker rm -f "$CNAME" >/dev/null 2>&1
if ! docker run -d --name "$CNAME" --privileged --cgroupns=host \
      --tmpfs /run --tmpfs /run/lock \
      -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
      -v "$tmp":/in:ro "$IMAGE" >/dev/null 2>&1; then
  echo "SKIP: could not start a privileged systemd container"; exit 0
fi
# The state is CAPTURED and then matched, rather than piped into grep. Under
# `set -o pipefail` a pipeline takes the last non-zero status, and `systemctl
# is-system-running` exits 1 for "degraded" — which is the normal state for a
# container, where a handful of units cannot start. So the grep matched and the
# pipeline still reported failure, and this loop timed out against a container that
# had booted perfectly well. Exactly the trap the harness exists to catch, hit while
# writing the harness.
booted=0
for _ in $(seq 1 30); do
  state="$(docker exec "$CNAME" systemctl is-system-running 2>/dev/null || true)"
  case "$state" in running|degraded) booted=1; break ;; esac
  sleep 1
done
if [ "$booted" != 1 ]; then
  # A SKIP that says nothing is how a broken harness stays broken — report enough to
  # tell "this kernel/cgroup setup cannot run systemd in a container" apart from "the
  # image is wrong".
  echo "SKIP: systemd did not come up in the container"
  echo "  container state: $(docker inspect -f '{{.State.Status}} exit={{.State.ExitCode}}' "$CNAME" 2>/dev/null)"
  echo "  is-system-running: $(docker exec "$CNAME" systemctl is-system-running 2>&1 | head -1)"
  docker logs "$CNAME" 2>&1 | tail -12 | sed 's/^/  /'
  exit 0
fi
ok "systemd is PID 1 and the system reached a running state"

dex(){ docker exec "$CNAME" bash -c "$1"; }

# Docker bind-mounts /etc/resolv.conf from the host, read-only from the container's
# point of view, so point_host_at_named could not write it and A6 would test nothing.
# Replace the mount with a real file — privileged, so the unmount is allowed.
dex 'cp /etc/resolv.conf /tmp/rc && umount /etc/resolv.conf 2>/dev/null; cp /tmp/rc /etc/resolv.conf' >/dev/null 2>&1
if dex 'findmnt -no TARGET /etc/resolv.conf >/dev/null 2>&1'; then
  note "/etc/resolv.conf is still a mount — A6 will be reported as SKIP"
  RESOLV_WRITABLE=0
else
  RESOLV_WRITABLE=1
fi

# ---- local repo + preseed --------------------------------------------------
dex 'cp -r /in/repo /tmp/repo && cd /tmp/repo && dpkg-scanpackages -m . > Packages 2>/dev/null
     echo "deb [trusted=yes] file:/tmp/repo ./" > /etc/apt/sources.list.d/drumee-local.list
     apt-get update -qq 2>/dev/null' >/dev/null 2>&1
dex 'debconf-set-selections < /in/install.conf' >/dev/null 2>&1 || true

# The files whose content decides A1-A3. Chosen because each is rendered by a
# different template family, so a partial re-render cannot pass by touching one.
WATCH='/etc/drumee/drumee.sh /etc/drumee/drumee.json /var/lib/bind/'"$DOMAIN"' /etc/nginx/sites-enabled/00-local.conf /etc/nginx/sites-enabled/01-public.conf'
snapshot(){ dex "for f in $WATCH; do [ -f \"\$f\" ] && printf '%s %s\n' \"\$(sha256sum \"\$f\" | cut -c1-16)\" \"\$f\"; done | sort"; }

# ---------------------------------------------------------------------------
hdr "A1 — a fresh install renders the configuration tree"
CONFOPTS='-o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef'
dex "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $CONFOPTS drumee-infra=$prev </dev/null" \
  > "$tmp/install.log" 2>&1 || true
if dex 'test -f /etc/drumee/drumee.json'; then
  ok "drumee.json rendered"
else
  no "drumee.json was not rendered — the install did not get far enough to test anything"
  tail -20 "$tmp/install.log" | sed 's/^/       /'
  echo; echo "== $pass passed, $fail failed =="; exit 1
fi
zone_present=0
dex "test -f /var/lib/bind/$DOMAIN" && { ok "zone file /var/lib/bind/$DOMAIN rendered"; zone_present=1; } \
  || no "no zone file at /var/lib/bind/$DOMAIN — the DNS path did not run"
before="$(snapshot)"
printf '%s\n' "$before" | sed 's/^/       /'

# ---------------------------------------------------------------------------
hdr "A2 — an upgrade must leave the rendered tree alone"
note "operator edits under /etc must survive apt; re-rendering here would silently discard them"
dex "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $CONFOPTS drumee-infra=$ver </dev/null" \
  > "$tmp/upgrade.log" 2>&1 || true
got_ver="$(dex "dpkg-query -W -f='\${Version}' drumee-infra" 2>/dev/null || true)"
if [ "$got_ver" = "$ver" ]; then
  ok "upgraded to $ver"
else
  no "the upgrade to $ver did not take (dpkg reports '$got_ver')"; tail -15 "$tmp/upgrade.log" | sed 's/^/       /'
fi
after_upgrade="$(snapshot)"
if [ "$before" = "$after_upgrade" ]; then
  ok "the rendered tree is byte-for-byte unchanged by the upgrade"
else
  no "the upgrade re-rendered the configuration — operator edits would be lost"
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after_upgrade") | sed 's/^/       /'
fi

# ---------------------------------------------------------------------------
hdr "A3/A4 — dpkg-reconfigure must re-render, and a planted defect must go"
note "this is the property that was broken since it was written: reconfigure reported"
note "success and changed nothing, so no configuration fix could reach an installed host"
# The sentinel is the exact defect 1.2.30 fixed, so A4 is not an abstract "something
# changed" check: it is "the class of fix that could not land, lands".
SENTINEL_ADDR='fe80::dead:beef:cafe:1'
SENTINEL="@		60	IN	AAAA	$SENTINEL_ADDR"
if [ "$zone_present" = 1 ]; then
  dex "printf '%s\n' '$SENTINEL' >> /var/lib/bind/$DOMAIN"
  dex "grep -q '$SENTINEL_ADDR' /var/lib/bind/$DOMAIN" \
    && note "planted a link-local AAAA in the zone" \
    || no "could not plant the sentinel"
fi
# The baseline for A3 is taken AFTER planting, not before.
#
# It was before, and that produced a false PASS on the genuinely broken package:
# writing the sentinel changes the zone file's hash by itself, so "the tree changed"
# was satisfied by the harness's own edit rather than by any re-render. Verified
# against the real pre-fix 1.2.30 artifact — A3 passed while A4 failed, which is
# incoherent, and only A4's failure was true.
planted="$(snapshot)"
dex 'DEBIAN_FRONTEND=noninteractive dpkg-reconfigure drumee-infra' > "$tmp/reconf.log" 2>&1 || true
grep -q 're-rendering the configuration of this existing instance' "$tmp/reconf.log" \
  && ok "postinst recognised the reconfigure (DEBCONF_RECONFIGURE honoured)" \
  || no "postinst did not take the reconfigure path — DEBCONF_RECONFIGURE was ignored"

after_reconf="$(snapshot)"
if [ "$after_reconf" != "$planted" ]; then
  ok "the rendered tree changed — reconfigure re-renders"
else
  no "reconfigure changed nothing — not even the sentinel was overwritten: the 1.2.31 regression"
  note "look for 'Use --reconfigure=1' in the log below"
  grep -n 'reconfigure' "$tmp/reconf.log" | head -5 | sed 's/^/       /'
fi
if [ "$zone_present" = 1 ]; then
  if dex "grep -q 'fe80::dead:beef' /var/lib/bind/$DOMAIN"; then
    no "the planted defect survived — a fix shipped in a package cannot reach this host"
  else
    ok "the planted defect is gone — a shipped fix reaches an installed host"
  fi
fi

# ---------------------------------------------------------------------------
hdr "A5 — no rendered zone may publish a link-local AAAA"
note "fe80::/10 cannot be dialled without an interface scope, and an AAAA cannot carry one"
note "the A4 sentinel is excluded here — a surviving sentinel is A4's finding, not this one's"
ll="$(dex "grep -rhoiE 'AAAA[[:space:]]+fe[89ab][0-9a-f]:[^[:space:]]*' /var/lib/bind/ 2>/dev/null | grep -v '$SENTINEL_ADDR'" || true)"
if [ -n "$ll" ]; then
  no "a zone publishes a link-local address"; printf '%s\n' "$ll" | sed 's/^/       /'
else
  ok "no link-local AAAA in any rendered zone"
fi

# ---------------------------------------------------------------------------
hdr "A6 — the host resolves its own domain, through nsswitch"
note "asked with getent, not dig: a check that queries 127.0.0.1 directly passes while"
note "nsswitch is broken, which is exactly how the 1.2.28 regression stayed hidden"
if [ "$RESOLV_WRITABLE" != 1 ]; then
  note "SKIP: /etc/resolv.conf is not writable in this container"
elif ! dex 'systemctl is-active --quiet named'; then
  note "SKIP: named is not running in this container, so there is nothing to resolve against"
  dex 'journalctl -u named -n 5 --no-pager 2>/dev/null' | sed 's/^/       /'
else
  got="$(dex "getent hosts $DOMAIN | awk '{print \$1; exit}'" || true)"
  case "$got" in
    "")            no "the host cannot resolve $DOMAIN at all" ;;
    fe80:*|FE80:*) no "resolves to a link-local address ($got) — unusable" ;;
    *:*)           ok "resolves $DOMAIN -> $got" ;;
    *)             ok "resolves $DOMAIN -> $got" ;;
  esac
  first="$(dex "awk '/^nameserver/{print \$2; exit}' /etc/resolv.conf" || true)"
  [ "$first" = "127.0.0.1" ] \
    && ok "127.0.0.1 is the first nameserver" \
    || no "the first nameserver is '$first', not 127.0.0.1 — a public resolver answers for the domain first"
fi

# ---------------------------------------------------------------------------
hdr "A7 — a systemd reboot brings it back, with no hanging stop job"
note "a container restart is a real systemd shutdown and boot; it cannot see below systemd"
units="$(dex "systemctl list-units --state=active --no-legend 'nginx*' 'named*' 'drumee*' 2>/dev/null | awk '{print \$1}'" || true)"
note "active before: $(printf '%s' "$units" | tr '\n' ' ')"
# Timed as stop-then-start rather than `docker restart`, so the number reported is
# the SHUTDOWN, which is the half that hangs. A restart's total would fold in the
# boot and hide a slow teardown behind a fast one.
t0=$(date +%s)
docker stop -t 90 "$CNAME" >/dev/null 2>&1
elapsed=$(( $(date +%s) - t0 ))
docker start "$CNAME" >/dev/null 2>&1
for _ in $(seq 1 40); do
  state="$(docker exec "$CNAME" systemctl is-system-running 2>/dev/null || true)"
  case "$state" in running|degraded) break ;; esac
  sleep 1
done
# 90s is `docker stop`'s timeout, so hitting it means SIGKILL, which is the shape of
# the bug: a stop job that never returns. A healthy teardown here is a few seconds.
if [ "$elapsed" -lt 30 ]; then
  ok "systemd shut down in ${elapsed}s"
else
  no "shutdown took ${elapsed}s — something held a stop job (the 2.9.95-2.9.97 shape)"
fi
missing=""
while IFS= read -r u; do
  [ -n "$u" ] || continue
  dex "systemctl is-active --quiet '$u'" || missing="$missing $u"
done < <(printf '%s\n' "$units")
[ -z "$missing" ] && ok "every unit that was active is active again" \
                  || no "did not come back:$missing"
# grep -c prints 0 AND exits 1 when nothing matches, so `|| echo 0` used to append a
# second line and the count arrived as "0\n0" — which is neither empty nor "0", so a
# clean journal was reported as a failure whose message was two lines of zeros.
to="$(dex "journalctl -b -1 --no-pager 2>/dev/null | grep -icE 'timed out waiting for|stop job' || true" 2>/dev/null | head -1 | tr -dc '0-9')"
if [ -z "${to:-}" ]; then
  note "SKIP: no previous boot in the journal to inspect"
elif [ "$to" = "0" ]; then
  ok "no stop-job timeout in the previous boot's journal"
else
  no "$to stop-job timeout message(s) in the previous boot"
  dex "journalctl -b -1 --no-pager 2>/dev/null | grep -iE 'timed out waiting for|stop job' | tail -5" | sed 's/^/       /'
fi
# Deliberately NOT asserting that 127.0.0.1 survived here. Docker re-creates the
# /etc/resolv.conf bind mount on every container start, so the file is replaced by the
# daemon's copy no matter what the package did — the assertion measured Docker, not
# Drumee, and failed on a correct package. Persistence is a NetworkManager property
# and belongs on a real box; the closing note says where.
note "resolv.conf persistence is not observable here — Docker re-creates the mount on start"

# ---------------------------------------------------------------------------
hdr "A8 — the dead maintscript arm must not come back"
note "dpkg-reconfigure runs 'postinst configure', never 'postinst reconfigure'; an arm"
note "for the latter is unreachable and looks exactly like the fix for A3"
if grep -qE '^[[:space:]]*reconfigure\)' "$root/infra/debian/postinst"; then
  no "infra/debian/postinst has a reconfigure) arm — nothing invokes it"
else
  ok "no unreachable reconfigure) arm in postinst"
fi

# ---------------------------------------------------------------------------
echo
printf '\033[1m== %d passed, %d failed ==\033[0m\n' "$pass" "$fail"
cat <<'TAIL'

  Not covered here, and only a real box can show it:
    * NetworkManager's regeneration of resolv.conf — the 1.2.28 regression was an
      ORDERING bug in the nmcli profile, and NM is not present in a container.
    * a kernel reboot, and anything below systemd.
  On the test box:  apt upgrade; dpkg-reconfigure drumee-infra; reboot; then
  getent hosts <domain> and cat /etc/resolv.conf.
TAIL
[ "$fail" = "0" ] || exit 1
