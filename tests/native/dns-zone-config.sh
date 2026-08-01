#!/bin/bash
# The rendered BIND configuration must be one BIND actually accepts.
#
# Why this exists: on a LAN instance (tls_method=self-signed) the host is the
# only thing that knows its own domain, so DNS is not optional there — and the
# rendered named.conf.local was rejected outright by named. Three independent
# reasons, all invisible on a box where bind9 was never installed:
#
#   1. a single-NIC host has private_ip4 == public_ip4, so the public and
#      private halves of the template derived the SAME reverse zone and
#      declared "<rev>.in-addr.arpa" twice. named refuses its whole
#      configuration over that, not just the duplicate.
#   2. the public reverse zone named its file /var/lib/bind/<reverse_public_ip4>
#      while infra.js renders it to /var/lib/bind/<public_ip4>.
#   3. own_certs_dir nulls private_domain in infra.js on a LOCAL variable, so
#      the private zone files are not written while data.private_domain stays
#      populated — the template declared a zone whose file never existed.
#
# The general rule these are all instances of: a declared zone whose file was
# not rendered costs the host ALL of DNS, so the template's conditions have to
# mirror infra.js's exactly. That is the invariant checked below — the zone
# files are written by replicating infra.js's OWN decision logic, and every
# `file` named in named.conf.local must be one of them.
#
# Renders the real templates from setup-infra and hands them to a real
# named-checkconf. SKIPs (exit 0) without Docker, node, or a setup-infra
# checkout, so it is safe in CI.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# The templates live upstream; prefer a sibling checkout, fall back to the tree
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

cat > "$tmp/render.js" <<'JS'
const { readFileSync, writeFileSync, mkdirSync } = require('fs');
const { template } = require(process.env.SETUP_INFRA_SRC + '/node_modules/lodash');
const src = process.env.SETUP_INFRA_SRC, out = process.env.OUT;
const render = (tpl, data) => template(readFileSync(`${src}/templates/${tpl}`, 'utf8'))(data);

const base = {
  nsupdate_key: '/etc/bind/keys/update.key',
  serial: '2026080101', public_ip6: '',
  dkim_key: '"v=DKIM1; k=rsa; p=TESTKEY"',
  allow_recursion: 'localhost;',
};

const cases = {
  // Every LAN install: one NIC, one address, a private domain derived from the
  // public one. This is the shape that produced the duplicate reverse zone.
  lan: { ...base,
    public_domain: 'drumee.lan',   private_domain: 'drumee.local',
    public_ip4: '192.168.5.164',   private_ip4: '192.168.5.164',
    reverse_public_ip4: '5.168.192', reverse_private_ip4: '5.168.192',
    jitsi_public_domain: 'jit.drumee.lan', jitsi_private_domain: 'jit.drumee.local',
    own_certs_dir: '',
    expect_zones: ['drumee.lan', '5.168.192.in-addr.arpa', 'drumee.local'],
  },
  // tls_method=own. own_certs_dir makes infra.js skip the private zone files
  // while data.private_domain stays populated — declaring that zone anyway is
  // what makes named reject everything.
  own: { ...base,
    public_domain: 'example.com',  private_domain: 'example.local',
    public_ip4: '203.0.113.7',     private_ip4: '192.168.5.164',
    reverse_public_ip4: '113.0.203', reverse_private_ip4: '5.168.192',
    jitsi_public_domain: 'jit.example.com', jitsi_private_domain: 'jit.example.local',
    own_certs_dir: '/etc/drumee/ssl',
    expect_zones: ['example.com', '113.0.203.in-addr.arpa'],
  },
};

for (const [name, data] of Object.entries(cases)) {
  mkdirSync(`${out}/${name}/bind`, { recursive: true });
  mkdirSync(`${out}/${name}/libbind`, { recursive: true });
  writeFileSync(`${out}/${name}/bind/named.conf.local`, render('etc/bind/named.conf.local', data));
  writeFileSync(`${out}/${name}/bind/named.conf.log`,   render('etc/bind/named.conf.log', data));

  // Replicate infra.js's OWN conditions for which zone files get written
  // (infra.js: `if (own_certs_dir) private_domain = null`, then
  //  `if (data.public_ip4 && public_domain)` / `if (data.private_ip4 && private_domain)`).
  // Deliberately NOT the template's conditions — the whole point is to catch
  // the two disagreeing.
  const privDomain = data.own_certs_dir ? null : data.private_domain;
  if (data.public_ip4 && data.public_domain) {
    writeFileSync(`${out}/${name}/libbind/${data.public_domain}`, render('var/lib/bind/public.tpl', data));
    writeFileSync(`${out}/${name}/libbind/${data.public_ip4}`,    render('var/lib/bind/public-reverse.tpl', data));
  }
  if (data.private_ip4 && privDomain) {
    writeFileSync(`${out}/${name}/libbind/${privDomain}`,       render('var/lib/bind/private.tpl', data));
    writeFileSync(`${out}/${name}/libbind/${data.private_ip4}`, render('var/lib/bind/private-reverse.tpl', data));
  }
  writeFileSync(`${out}/${name}/expect_zones`, data.expect_zones.join('\n') + '\n');
}
JS

SETUP_INFRA_SRC="$SETUP_INFRA_SRC" OUT="$tmp" node "$tmp/render.js" || {
  echo "FAIL: could not render the bind templates"; exit 1; }

fail=0
for case_name in lan own; do
  conf="$tmp/$case_name/bind/named.conf.local"
  echo "==> [$case_name] zone declarations:"
  grep -oE '^zone "[^"]+"' "$conf" | sed 's/^/   /'

  # Exactly the set expected — catches both a missing zone and a stray one.
  got=$(grep -oE '^zone "[^"]+"' "$conf" | sed 's/^zone "//; s/"$//' | sort)
  want=$(sort "$tmp/$case_name/expect_zones")
  if [ "$got" != "$want" ]; then
    echo "   FAIL: declared zones differ from what infra.js renders files for"
    diff <(echo "$want") <(echo "$got") | sed 's/^/     /'
    fail=1
  fi

  dupes=$(grep -oE '^zone "[^"]+"' "$conf" | sort | uniq -d)
  [ -n "$dupes" ] && { echo "   FAIL: zone declared twice — named rejects the whole config:"; echo "$dupes" | sed 's/^/     /'; fail=1; }

  # The invariant: every file named must be one this render actually produced.
  while IFS= read -r f; do
    [ -f "$tmp/$case_name/libbind/$(basename "$f")" ] \
      || { echo "   FAIL: declares $f but no such zone file was rendered"; fail=1; }
  done < <(grep -oE 'file "[^"]+"' "$conf" | sed 's/file "//; s/"$//')

  [ "$fail" = "0" ] && echo "   ok: declarations match the rendered files"
done
[ "$fail" = "0" ] || exit 1

echo "==> named-checkconf (real BIND, disposable container)…"
docker run --rm -i -v "$tmp":/in:ro debian:trixie bash -s <<'INNER'
set -u
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq --no-install-recommends bind9 bind9-utils >/dev/null 2>&1 \
  || { echo "SKIP: could not install bind9 in the container"; exit 0; }

rc=0
for case_name in lan own; do
  rm -rf /etc/bind/named.conf.local /etc/bind/named.conf.log /var/lib/bind/*
  install -d /etc/bind/keys /var/lib/bind
  cp /in/$case_name/bind/named.conf.local /in/$case_name/bind/named.conf.log /etc/bind/
  cp /in/$case_name/libbind/* /var/lib/bind/ 2>/dev/null
  # init-named generates this before starting named; named.conf.local includes
  # it unconditionally, so without it nothing loads at all.
  [ -f /etc/bind/keys/update.key ] || tsig-keygen -a hmac-sha512 update > /etc/bind/keys/update.key
  chown -R bind:bind /etc/bind /var/lib/bind

  if ! out=$(named-checkconf 2>&1); then
    echo "   [$case_name] FAIL: named-checkconf rejected the configuration:"
    printf '     %s\n' "$out"; rc=1; continue
  fi
  # Zone loading is reported by init-named, not enforced — it starts named
  # anyway rather than trading a record-level complaint for no DNS at all. Here
  # it IS enforced: every declared zone must load, which is what proves the
  # declaration/file agreement end to end.
  if ! zout=$(named-checkconf -z 2>&1); then
    echo "   [$case_name] FAIL: a zone did not load:"; printf '     %s\n' "$zout"; rc=1; continue
  fi
  while IFS= read -r z; do
    echo "$zout" | grep -q "zone $z/IN: loaded serial" \
      || { echo "   [$case_name] FAIL: zone $z did not load"; rc=1; }
  done < /in/$case_name/expect_zones
  echo "   [$case_name] config OK, $(grep -c . /in/$case_name/expect_zones) zones loaded"
done
exit $rc
INNER
rc=$?
[ "$rc" = "0" ] || { echo "FAIL: named rejected the rendered configuration"; exit 1; }
echo "PASS: the rendered BIND configuration is one named accepts"
