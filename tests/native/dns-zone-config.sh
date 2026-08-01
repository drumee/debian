#!/bin/bash
# The rendered BIND configuration must be one BIND actually accepts.
#
# Why this exists: on a LAN instance (tls_method=self-signed) the host is the
# only thing that knows its own domain, so DNS is not optional there — and the
# rendered named.conf.local was rejected outright by named. Two independent
# reasons, both invisible on a box where bind9 was never installed:
#
#   1. a single-NIC host has private_ip4 == public_ip4, so the public and
#      private halves of the template derived the SAME reverse zone and
#      declared "<rev>.in-addr.arpa" twice. named refuses its whole
#      configuration over that, not just the duplicate.
#   2. the public reverse zone named its file /var/lib/bind/<reverse_public_ip4>
#      while infra.js renders it to /var/lib/bind/<public_ip4>.
#
# Renders the real template from setup-infra and hands it to a real
# named-checkconf. SKIPs (exit 0) without Docker, node, or a setup-infra
# checkout, so it is safe in CI.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# The template lives upstream; prefer a sibling checkout, fall back to the tree
# infra/build.sh clones under infra/src/.
SETUP_INFRA_SRC="${SETUP_INFRA_SRC:-}"
for cand in "$SETUP_INFRA_SRC" "$root/../setup-infra" "$root/infra/src/setup-infra"; do
  [ -n "$cand" ] && [ -f "$cand/templates/etc/bind/named.conf.local" ] && { SETUP_INFRA_SRC="$cand"; break; }
done
[ -n "$SETUP_INFRA_SRC" ] || { echo "SKIP: no setup-infra checkout (set SETUP_INFRA_SRC)"; exit 0; }
command -v node >/dev/null 2>&1 || { echo "SKIP: node unavailable"; exit 0; }
[ -d "$SETUP_INFRA_SRC/node_modules/lodash" ] || { echo "SKIP: setup-infra has no node_modules (npm i)"; exit 0; }
command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || { echo "SKIP: docker unavailable"; exit 0; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bind" "$tmp/libbind"

# The case that broke: one NIC, one address, a private domain derived from the
# public one — i.e. every LAN install.
cat > "$tmp/render.js" <<'JS'
const { readFileSync, writeFileSync } = require('fs');
const { template } = require(process.env.SETUP_INFRA_SRC + '/node_modules/lodash');
const src = process.env.SETUP_INFRA_SRC, out = process.env.OUT;

const data = {
  nsupdate_key: '/etc/bind/keys/update.key',
  serial: '2026080101',
  public_domain: 'drumee.lan',   private_domain: 'drumee.local',
  public_ip4: '192.168.5.164',   private_ip4: '192.168.5.164',
  public_ip6: '',
  reverse_public_ip4: '5.168.192', reverse_private_ip4: '5.168.192',
  jitsi_public_domain: 'jit.drumee.lan', jitsi_private_domain: 'jit.drumee.local',
  dkim_key: '"v=DKIM1; k=rsa; p=TESTKEY"',
  allow_recursion: 'localhost; 192.168.5.164;',
};
const render = (tpl) => template(readFileSync(`${src}/templates/${tpl}`, 'utf8'))(data);

writeFileSync(`${out}/bind/named.conf.local`, render('etc/bind/named.conf.local'));
writeFileSync(`${out}/bind/named.conf.log`,   render('etc/bind/named.conf.log'));
// infra.js writes the zone files under the ADDRESS, not the reverse form —
// that mismatch is half of what this test guards.
writeFileSync(`${out}/libbind/${data.public_domain}`,  render('var/lib/bind/public.tpl'));
writeFileSync(`${out}/libbind/${data.private_domain}`, render('var/lib/bind/private.tpl'));
writeFileSync(`${out}/libbind/${data.public_ip4}`,     render('var/lib/bind/public-reverse.tpl'));
writeFileSync(`${out}/libbind/${data.private_ip4}`,    render('var/lib/bind/private-reverse.tpl'));
JS

SETUP_INFRA_SRC="$SETUP_INFRA_SRC" OUT="$tmp" node "$tmp/render.js" || {
  echo "FAIL: could not render the bind templates"; exit 1; }

echo "==> rendered zone declarations:"
grep -E '^zone ' "$tmp/bind/named.conf.local" | sed 's/^/   /'

# Catch the duplicate here too, so the failure is legible even if the container
# step is skipped or its output is noisy.
dupes=$(grep -oE '^zone "[^"]+"' "$tmp/bind/named.conf.local" | sort | uniq -d)
if [ -n "$dupes" ]; then
  echo "FAIL: the same zone is declared twice — named rejects the whole config:"
  echo "$dupes" | sed 's/^/   /'
  exit 1
fi

echo "==> named-checkconf (real BIND, disposable container)…"
docker run --rm -i -v "$tmp":/in:ro debian:trixie bash -s <<'INNER'
set -u
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq --no-install-recommends bind9 bind9-utils >/dev/null 2>&1 \
  || { echo "SKIP: could not install bind9 in the container"; exit 0; }

install -d /etc/bind/keys /var/lib/bind
cp /in/bind/named.conf.local /in/bind/named.conf.log /etc/bind/
cp /in/libbind/* /var/lib/bind/
# init-named generates this before starting named; named.conf.local includes it
# unconditionally, so without it nothing loads at all.
tsig-keygen -a hmac-sha512 update > /etc/bind/keys/update.key
chown -R bind:bind /etc/bind /var/lib/bind

if ! out=$(named-checkconf 2>&1); then
  echo "FAIL: named-checkconf rejected the configuration:"; printf '   %s\n' "$out"; exit 1
fi
echo "   config: OK"

# Zone loading is reported, not enforced: init-named starts named anyway rather
# than trading a record-level complaint for no DNS at all. Assert the two zones
# that must resolve for a LAN instance do load.
zout=$(named-checkconf -z 2>&1)
echo "$zout" | sed 's/^/   /'
for z in drumee.lan drumee.local; do
  echo "$zout" | grep -q "zone $z/IN: loaded serial" \
    || { echo "FAIL: zone $z did not load"; exit 1; }
done
echo "   zones: OK"
INNER
rc=$?
[ "$rc" = "0" ] || { echo "FAIL: named rejected the rendered configuration"; exit 1; }
echo "PASS: the rendered BIND configuration is one named accepts"
