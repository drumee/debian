# Native Debian channel

For dedicated Debian/Ubuntu hosts (advanced / IaC). Installs Drumee directly onto
the host via `apt`, configured from a debconf preseed for unattended runs.

## For end users

```bash
# Interactive
curl -fsSL https://apt.drumee.net/baremetal.sh | sudo bash

# Unattended — preseed answers rendered from drumee.yaml first
node config/render.mjs debconf --out install.conf
sudo PRESEED=install.conf bash scripts/baremetal.sh
```

`apt install drumee` pulls the `drumee` metapackage (`meta/`), which depends on
`drumee-infra`, `drumee-schemas`, `drumee-static`, `drumee-server-pod`,
`drumee-ui-pod`.

## For maintainers — publishing the repo

```bash
./build-all.sh                       # build the component .debs
static/build.sh                      # build drumee-static (REPO_BASE=https://github.com/drumee)
meta/build.sh                        # build the drumee metapackage
scripts/publish-apt.sh --debs=./out-debs --out=/tmp/apt-flat --key=release@drumee.org
APT_LOCAL_DIR=/tmp/apt-flat scripts/deploy-apt-repo.sh   # --host=debian@apt.drumee.net
```

`publish-apt.sh` builds a signed **flat** repo (`apt-ftparchive` + `gpg`), emits
`InRelease`/`Release.gpg`, and exports the public key as
`drumee-archive-keyring.asc`.

`deploy-apt-repo.sh` rsyncs that directory to the VPS document root
(`/var/www/apt.drumee.net` by default), writes an nginx vhost for the domain, and
reloads nginx. Override with `--repo-dir=` / `--domain=`. TLS is provisioned
separately (`certbot --nginx -d apt.drumee.net`); the script prints the follow-up
steps, including uncommenting the port-80 → 443 redirect once the cert exists.

## Certificates: DNS-01, and what works behind a router

Drumee needs a **wildcard** certificate, so the ACME challenge is always DNS-01 —
opening port 80 does nothing for issuance. The names it must cover:

```
example.com          *.example.com
jit.example.com      *.jit.example.com          (conferencing)
vendors.example.com  *.vendors.example.com
```

Every subdomain needs its own wildcard entry, because **a wildcard matches exactly
one label** — `*.example.com` does not cover `x.vendors.example.com`. The same
applies to the DNS zone: a `*` record does not answer for `*.vendors`.

`apt install drumee-infra` asks how to answer the challenge — which is also the
question of **who runs DNS for the domain**:

| Choice | Requirements |
|---|---|
| **acme-dns-server** (default) | **Drumee provides the DNS.** BIND9 is installed here as the authoritative nameserver and serves the whole zone (see below), answering the challenge through a TSIG-signed dynamic update. The domain's NS records must be delegated here and **inbound udp/53 must reach it** — not possible behind a typical home router. |
| **acme-dns-api** | The TXT record is created through your DNS provider's API. **Outbound only, so no port forwarding at all** — the right choice for a box on a home LAN. No DNS server is installed, so **every other record below is yours to publish**. |
| **caddy** | The `drumee-caddy` package (a Caddy compiled with `caddy-dns` provider modules) takes 80/443, obtains and renews the certificates itself over DNS-01, and proxies to nginx on internal ports. **Outbound only**, and it can issue wildcards. Asks for the domain, the provider module and the API token. |
| **own** | You supply wildcard certs and give their path. |
| **self-signed** | LAN-only/test instance, no public certificate. **BIND9 is installed here too**, serving the zone for your private domain — nothing delegates a private name, so without a resolver on this box it resolves for nobody. Point the LAN at this host afterwards (the router's DHCP "DNS server" option, or each client). |

BIND9 is a **Recommends** of `drumee-infra`, so `apt install drumee` brings it in
and `--no-install-recommends` or `dpkg -i` do not — the postinst says so, with the
command to fix it. On the three choices that keep DNS at a provider, the postinst
stands named back down rather than let it answer for a domain served elsewhere.

### What the zone contains

`acme-dns-server` and `self-signed` publish this for you — the first on a public
domain, the second on your LAN. On the other three choices it is the checklist of
what you must create at your own DNS provider, and the certificate is the
smallest part of it:

| Records | Purpose |
|---|---|
| `ns1`, `ns2` + the `NS` records at the apex | delegation, so the zone answers at all |
| `@`, `*`, `www` | the instance itself |
| `jit`, `*.jit` | conferencing |
| `vendors`, `*.vendors` | vendor sites |
| `smtp` + `MX 10 smtp` | mail delivery to this instance |
| `SPF`, `DKIM` (`@`, `smtp._domainkey`, `dkim._domainkey`), `_dmarc` | mail *from* this instance being accepted elsewhere |
| `_acme-challenge` | the certificate challenge |

The mail authentication records are the ones most often forgotten: without them
the instance still works, but mail it sends is likely to be filed as spam. The
DKIM key is generated during `drumee-infra` configuration, so those records can
only be published after the first install.

For `acme-dns-api`, create the credentials file on the host **before** installing,
mode `0600`, exporting an [acme.sh dnsapi](https://github.com/acmesh-official/acme.sh/wiki/dnsapi)
name plus its variables:

```bash
sudo install -d -m 0700 /etc/drumee/credential
sudo tee /etc/drumee/credential/dns-api.env >/dev/null <<'ENV'
export ACME_PROVIDER=ovh
export OVH_AK=...  OVH_AS=...  OVH_CK=...
ENV
sudo chmod 0600 /etc/drumee/credential/dns-api.env
```

Declaratively, the same thing in `drumee.yaml` (the path only — never the
secrets), which `render.mjs debconf` turns into the preseed:

```yaml
tls:
  mode: acme
  acme_email: ssl@example.com
  dns_challenge: api
  acme_env_file: /etc/drumee/credential/dns-api.env
```

If that file is missing when the package configures, installation does **not**
fail: it falls back to setting up the local DNS server, and `postinst` prints
what to fix followed by `dpkg-reconfigure drumee-infra`.

### Letting Caddy handle certificates

`tls_method=caddy` hands certificate management to the `drumee-caddy` package,
which ships a Caddy built with the DNS provider modules. Install that package
first — without it the choice is refused and nginx keeps ports 80/443, so you
cannot end up with nothing listening on 443.

Interactively you are asked for the domain, the provider module (`ovh`,
`cloudflare`, `gandi`, … — it must be one the binary was built with) and the API
token. Declaratively:

```yaml
tls:
  mode: acme
  acme_email: ssl@example.com
  terminator: caddy
  dns_provider: ovh
```

The token is **never** written into `drumee.yaml` or the rendered preseed. For an
unattended install, add it yourself before `apt install`:

```bash
printf 'drumee-infra\tdrumee-infra/caddy_dns_api_key\tpassword\t%s\n' "$TOKEN" \
  | sudo debconf-set-selections
```

Configuring this way moves nginx to `8080`/`8443` (Caddy needs 80/443) and writes
`/etc/drumee/conf.d/caddy.json` plus `/etc/drumee/credential/caddy-dns.env`
(mode `0600`). Providers that need more than one credential — an application key
*and* a secret, say — take the extra values in that env file.

The packages are **self-hosted on `apt.drumee.net`** — the `drumee-static` deb alone
is ~175 MB, over GitHub's 100 MB git-file limit, so they cannot live in a Pages git
repo. Clients use a flat repo:

```
deb [signed-by=/etc/apt/keyrings/drumee.asc] https://apt.drumee.net/ ./
```

The signing key is served from the same host at
`https://apt.drumee.net/drumee-archive-keyring.asc`.

## Needs your infrastructure

- **VPS + DNS + TLS** — an `A`/`AAAA` record for `apt.drumee.net` pointing at the
  nginx host, and a certbot cert for it.
- **Signing key** — a project (not personal) GPG key in the publishing
  environment; CI publishes with it (Phase 5). The repo currently published is
  signed with a local build key and must be re-signed before launch.
- **Deploy key** — `.github/workflows/release.yml` publishes the repo on a version
  tag via `scripts/publish-site.sh`. It needs these repository secrets:
  `APT_SSH_HOST` (`user@host`), `APT_SSH_KEY` (private half of a key authorized on
  the VPS), and ideally `APT_SSH_KNOWN_HOSTS` (pinned host key — without it the
  workflow falls back to `ssh-keyscan`, i.e. trust on first use). The deploy user
  only needs write access to the doc root; CI runs `deploy-apt-repo.sh
  --no-provision`, so no sudo.

## Install ordering (resolved)

`apt` configures a package only after the packages it `Depends` on, so the
components now encode the required order (`infra → schemas → static → server → ui`)
with explicit inter-package dependencies in each `debian/control`:

| Package | Depends (ordering) |
|---|---|
| `drumee-infra` | — (base) |
| `drumee-schemas` | `drumee-infra` |
| `drumee-static` | `drumee-infra` |
| `drumee-server-pod` | `drumee-schemas`, `drumee-static` |
| `drumee-ui-pod` | `drumee-server-pod` |

So `apt install drumee` (or installing the components in any order) configures
them in dependency order without relying on the command-line order.

## Still blocked for a real build/validation here

Building the `.deb`s and validating the install end-to-end needs inputs not
present in this checkout (they live in the Drumee build environment):

| Input | Needed by | Status |
|---|---|---|
| Private `@drumee` npm auth (or pre-installed `node_modules`) | every component (`bundle()` runs `npm i`) | only `infra`/`server`/`ui`/`schemas` checkouts have `node_modules`; `setup-schemas` does not |
| **Seeds archive** (`seeds.tgz`, a `mariabackup` physical backup) | `drumee-schemas` build | absent |
| **`static` source repo** | `drumee-static` build | absent |
| A **project GPG key** | signed `.deb`s + APT `Release` | absent (build unsigned with `-us -uc` for testing) |
| A disposable **Debian VM/systemd container** | running the host-reconfiguring postinst | required for true validation |
