# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository builds, packages, and distributes the **Drumee** sovereign data platform through two channels from one source of truth (`config/drumee.yaml`):

- **Container channel** — Docker Compose stack (`scripts/dev-up.sh`, `scripts/containers.sh`)
- **Native Debian channel** — `.deb` packages installable via `apt install drumee`

Each subdirectory under `infra/`, `schemas/`, `server/`, `ui/`, `static/` is a self-contained package builder that clones source from `git@github.com:drumee/`, compiles it, and produces a `.deb` via `dh_make` + `dpkg-buildpackage`. The `deploy/docker/` tree holds Dockerfiles and entrypoints for the container channel.

## Runtime Architecture

Each Drumee endpoint runs **three PM2 processes**:

| Process | Mode | Role |
|---|---|---|
| `main` | fork | Page serving + WebSocket (port 23000) |
| `main/service` | cluster | REST API workers (port 24000, scaled by RAM: 2 GB→2, 6 GB→3, >6 GB→4) |
| `factory` | fork | Schema factory — replenishes entity pool (autorestart disabled) |

All service URLs follow `/-/svc/module.method` — no hardcoded routes.

### Runtime Directory Layout

```
/srv/drumee/
├── runtime/
│   ├── server/main/     # drumee-server-pod: Node.js backend
│   ├── ui/main/         # drumee-ui-pod: LETC frontend engine
│   ├── tmp/             # temporary files (cleaned by cron)
│   └── plugins/server/<endpoint>/<plugin>/
├── static/              # drumee-static: assets, locale files
└── cache/

/data/mfs/               # user file storage (MFS-managed)

/etc/drumee/
├── drumee.sh            # master runtime environment (sourced by server at startup)
├── drumee.json          # master JSON config
├── conf.d/              # exchange, myDrumee, conference configs
├── credential/          # db.json, email.json, redis.json, crypto/ (never committed)
└── infrastructure/ecosystem.json  # PM2 process definitions

/var/lib/drumee/
├── setup-infra/         # infra install scripts + 69 lodash templates
├── setup-schemas/       # schema install scripts + populate.js
├── patches/             # pending schema patches
└── postinstall/patch.sh # applied at server startup
```

### Database Structure

**`yp`** — Central system database: `sys_conf`, `domain`, `vhost`, `entity`, `drumate`, `hub`, `organisation`, `settings`, `privilege`, mailserver tables.

**Per-entity databases** — One database per user and hub, created by `entity_create` stored procedure. Contains `mfs_*`, `permission`, `media`, and activity tables.

Five additional system databases: `utils`, `mailserver`, `template`, `trash`, plus per-hub/per-drumate sharded databases.

## Building Packages

### Prerequisites

- **No root** — all scripts check `$UID` and abort if root
- **Git SSH access** to `git@github.com:drumee/` (private repos)
- **GPG key** matching maintainer email in `debian/changelog` (in local keyring)
- **Node.js 22** — the `debian/control` files still say `nodejs (>= 20)`, but the
  container images and `scripts/debian.sh` (NodeSource) install **22**, and
  the WireGuard agent needs it. Treat 22 as the real baseline; the `>= 20` pin is
  deliberately not bumped (see the Node 22 guard under WireGuard).
- **Debian build tools**: `dh-make`, `dpkg-buildpackage`, `debhelper`, `build-essential`

### Commands

```bash
# Single package
infra/build.sh
schemas/build.sh
server/build.sh
ui/build.sh
static/build.sh
caddy/build.sh                             # drumee-caddy (needs Go >= 1.21 or Docker)
meta/build.sh                              # drumee metapackage (pure deps)
schemas-patch/build.sh --manifest=auto     # incremental schema patch

# All main packages in dependency order
./build-all.sh                             # infra → schemas → ui → server
```

Build outputs land in `<package>/build/<version>/`. Set `DEB_BUILD_TARGET=/path` to copy `.deb` files there (only `infra`, `schemas`, `server` honor this).

### Build flags

Most scripts take **no** flags — version and email are read from `<package>/debian/changelog` via `get_version`/`get_email`. `get_build_dir` unconditionally wipes and recreates the staging dir, so `--force` is unnecessary. Exceptions:

| Script | Flag | Effect |
|---|---|---|
| `ui/build.sh` | `--compile=yes\|no` | Parsed but **not honoured** — webpack always runs |
| `ui/build.sh` | `--enable-api=yes\|no` | Also compile the `api` webpack target (default `no`) |
| `schemas-patch/build.sh` | `--manifest=auto\|<file>` | **Required** — selects the patch manifest |
| `schemas-patch/build.sh` | `<N>` (positional) | Commit depth for `--manifest=auto` (default `2`) |
| `builder/build.sh` | `pull` (positional) | Pull the `setup` repo before packaging |

### Environment variables

| Variable | Effect |
|---|---|
| `DEB_BUILD_TARGET=/path` | Copy `.deb` there after build (infra, schemas, server only) |
| `SEEDS_DIR=/path` | Source for schemas seeds archive (default `$HOME/docker/data/seeds/`) |
| `REPO_BASE=git@...` | Override GitHub base URL for `bundle()` (local mirror) |

### schemas prerequisites — the seed

`schemas/build.sh` must ship a `mariabackup` physical snapshot at
`schemas/var/tmp/drumee/seeds.tgz`. Resolution order (in `schemas/build.sh`):

1. reuse an existing `var/tmp/drumee/seeds.tgz`;
2. archive `$SEEDS_DIR` (default `$HOME/docker/data/seeds/`) if that dir exists;
3. **build one offline** via `scripts/build-seed.sh` — no insider snapshot needed.

`schemas/seeds/` is gitignored. See **Offline Seed Builder** below.

## Offline Seed Builder

Removes the last "insider artifact" from the build (`docs/reproducible-builds.md`,
roadmap 0.6). It produces `seeds.tgz` from source inside one throwaway container:
a local MariaDB + Redis, base DBs from the `schemas` repo's `templates/factory/`,
the **entity pool stocked** via `server-team`'s `offline/factory` (an empty pool
trips the `EMPTY_FACTORY` guard in schemas' postinst), then
`mariabackup --backup/--prepare` tarred in the exact layout
`setup-schemas/bin/install` consumes (`tar --one-top-level=seeds` →
`mariabackup --copy-back`).

```bash
scripts/build-seed.sh [--out=PATH]          # default out: schemas/var/tmp/drumee/seeds.tgz
scripts/check-seed.sh [--seed=PATH]         # interactive shell on a restored seed
scripts/check-seed.sh -- mariadb -N -B -e 'SELECT COUNT(*) FROM yp.entity'
```

| File | Role |
|---|---|
| `scripts/Dockerfile.seed` | Toolbox image (`drumee/seed:$TAG`) — MariaDB + mariabackup + Redis + Node 22 |
| `scripts/seed-entrypoint.sh` | The seed flow (start DB → init → populate → mariabackup → tar) |
| `scripts/Dockerfile.seed-check` / `seed-check-entrypoint.sh` | Restore a seed the way the `.deb` does, then hand over a shell |

**Sources are bind-mounted read-only and their existing `node_modules` are
reused** — so no access to the private `@drumee` registry is needed in-container.
`SERVER_SRC` (default `../server-team`, must already have `node_modules/@drumee`),
`SETUP_SCHEMAS_SRC` and `SCHEMAS_SRC` (default to the trees `schemas/build.sh`
already cloned under `schemas/src/`). Other knobs: `TAG`, `POOL_COUNT` (default
10), `DRUMEE_DOMAIN_NAME`.

**Design rule worth preserving:** steps 1–2 reuse the container channel's assets
verbatim (`deploy/docker/schemas-init.sh`, `populate-entrypoint.sh`,
`container-populate.js`, pulled in via the `helpers` build context) pointed at a
loopback MariaDB instead of the compose `mariadb` service. Both channels are
therefore seeded by the same vetted code paths — don't fork these scripts for the
seed builder.

## Install Order and Dependencies

**Inter-component `Depends` are the minimum, and there is exactly one left.** As of
static 1.0.6 / ui-pod 3.3.75 / server-pod 2.9.99:

```
drumee-schemas  →  drumee-infra        the only component-to-component dependency
                                       (schemas' postinst restores MariaDB from the
                                        seed using the credentials infra renders)

drumee-static      no component Depends
drumee-ui-pod      no component Depends
drumee-server-pod  no component Depends (system packages only + drumee-node-runtime)
```

What the removed edges used to provide, and what provides it now:

| Was | Now |
|---|---|
| completeness — every component installed | the **`drumee` metapackage** pins each one at an exact version (`meta/make-control.sh`) |
| start order — server after schemas, UI after server | **`drumee-server-pod`'s dpkg trigger** (`interest-noawait drumee-server-pod-start`), which dpkg fires once every other package in the transaction is configured, whatever the graph says |
| server-pod finding a rendered config | its postinst **guards** both uses: `if [ -f /etc/drumee/drumee.sh ]` and `if [ -x $patch ]` |

Why they had to go: those `Depends` were single-box assumptions, harmless natively
because the metapackage installs the whole set anyway. In the container channel they
defeated the entire decomposition — `drumee-role-web` (ui-pod + static + nginx) resolved
to **508 packages**, every component plus mariadb-server, redis-server, LibreOffice,
ffmpeg and g++, because static pulled `drumee-infra` and ui-pod pulled
`drumee-server-pod`. And the role image could not even **build**: `drumee-infra`'s
postinst correctly refuses to configure without an answered domain question, so the
transaction failed with five packages unconfigured. Both measured, not predicted.

`tests/native/control-deps.sh` is the guard, and it asserts the *inverse* of what it
used to: static, ui-pod and server-pod must reach nothing, nothing installable in an
image may reach `drumee-infra`, and the two replacement mechanisms above must exist.

`drumee-patch` can be applied after `drumee-schemas`.

## Post-Install Behavior

- **drumee-infra**: runs `setup-infra/bin/install` (root) — renders 69 lodash templates into `/etc/drumee/`, `/etc/nginx/`, `/etc/bind/`, `/etc/prosody/`, `/etc/jitsi/`, `/etc/postfix/`, MariaDB, Coturn. Sets up SSL (ACME/self-signed/own certs), DNS (BIND9), DKIM, Prosody XMPP, PM2 ecosystem, and crontab (cert renewal, tmp cleanup, watchdog, DB/storage backups). Whether BIND9 serves the zone depends on the TLS method — `acme-dns-server` and `self-signed` do, the rest leave DNS at the operator's provider. See the DNS-01 section below.
- **drumee-schemas**: runs `setup-schemas/bin/install` (root) — restores MariaDB from seeds via `mariabackup`, creates system accounts (nobody, guest, system, admin), provisions initial hubs, generates RSA key pair, sends welcome email with password-reset link.
- **drumee-server-pod**: sources `/etc/drumee/drumee.sh`, applies pending patches from `/var/lib/drumee/postinstall/patch.sh`.
- **drumee-patch**: stages patch files; applied at next server startup (not immediately).
- **drumee-static**, **drumee-ui-pod**: no special post-install.

## TLS on the Native Channel is DNS-01 Only

Worth knowing before touching anything TLS-related: `setup-infra/bin/init-acme`
issues a **wildcard** (`--issue -d $dom -d "*.$dom" --dns <method>`), and a
wildcard can only be validated by DNS-01. There is **no HTTP-01 path** natively,
so inbound `:80` is irrelevant to certificates here. Three paths, selected by two
env vars that `postinst` bridges from the `drumee-infra/tls_method` debconf menu:

| `tls_method` | env | DNS | What happens |
|---|---|---|---|
| `acme-dns-server` (default) | neither set | **served here** | `bin/init-named` brings up **BIND9 as zone master** (`tsig-keygen` → `/etc/bind/keys/update.key`), ACME uses `dns_nsupdate` against `ns1.<domain>`. Needs NS delegation **and inbound udp/53** — so it cannot work behind a home router |
| `self-signed` | neither set | **served here** | No public certificate. BIND9 serves the zone locally, because a private domain is delegated nowhere and would otherwise resolve for nobody — see below |
| `acme-dns-api` | `ACME_ENV_FILE` | at your provider | acme.sh uses `dns_$ACME_PROVIDER` (any dnsapi; OVH credential templates ship in setup-infra). **Outbound only → works behind NAT** |
| `caddy` | `OWN_SSL` + internal nginx ports | at your provider | **drumee-caddy** (a Caddy built with `caddy-dns` modules) owns 80/443, issues over DNS-01 itself, and proxies to nginx. Outbound-only, and it *can* do wildcards — unlike stock Caddy, which is why the module build matters |
| `own` | `OWN_SSL` | at your provider | ACME skipped, operator's wildcard certs used |

**`DRUMEE_DNS_SERVER` is what decides the DNS column**, not `ACME_ENV_FILE`.
`postinst` derives it from `tls_method` (`1` for the two rows above, `0` for the
rest; local mode forces `1`) and `bin/install` honours it. Unset, it falls back
to the old inference — `init-named` when `ACME_ENV_FILE` is unset or points at a
missing file — which is only about the *certificate challenge* and therefore
also switched DNS on for `tls_method=own`, where nothing wanted it.

`ACME_ENV_FILE` still selects the challenge method: `init-acme` sources the file
to read `ACME_PROVIDER`, so it must exist *before* the package is configured and
must export the provider name itself; `postinst` checks and warns rather than
letting issuance fail later.

**bind9 is `Recommends`, not `Depends`** — three of the five methods have no use
for a nameserver, and one squatting udp/53 for a domain served elsewhere is not
harmless. Consequences worth knowing: `apt install drumee` pulls it in but
`--no-install-recommends` and `dpkg -i` do not (`postinst` says so, with the
command to fix it); a Recommends is **not an ordering constraint**, so
`scripts/debian.sh` installs bind9 in its own transaction *before* Drumee,
and `finish_dns` retries the start once; and when DNS is not wanted, `postinst`
stands named back down — guarded by the setup-infra marker in
`named.conf.local`, so a nameserver Drumee did not configure is never touched.

### Why self-signed implies DNS

A LAN instance is the only thing on the network that knows its own domain.
Nothing delegates `drumee.lan`, no upstream resolver will ever answer for it, and
`/etc/hosts` on every client is not a deployment. So on this path the nameserver
*is* the product, not an ACME implementation detail — the zone was already being
rendered in full under `/var/lib/bind`, and nothing served it.

Two rendering bugs sat behind that, invisible for as long as bind9 was never
installed, both fixed and both guarded by `tests/native/dns-zone-config.sh`:

- **Duplicate reverse zone.** A single-NIC host has `private_ip4 == public_ip4`,
  so the public and private halves of `named.conf.local` derived the *same*
  `<rev>.in-addr.arpa` and declared it twice. named refuses its **entire**
  configuration over that, not just the zone at fault.
- **Zone files named after the wrong thing.** The public reverse zone pointed at
  `/var/lib/bind/<reverse_public_ip4>` while `infra.js` writes it to
  `/var/lib/bind/<public_ip4>`; and both reverse zone files set `$ORIGIN` to the
  bare octets with no `in-addr.arpa` suffix, putting every record out of zone.

Zone declarations now mirror exactly the conditions `infra.js` uses to decide
which files it writes — the two must agree, or named rejects the lot.

`init-named` was also unable to survive its own first line: it ran under
`set -e` starting with `service named stop`, which exits non-zero when the unit
does not exist, so it aborted before generating the TSIG key that
`named.conf.local` includes unconditionally — and `bin/install` runs it under
`set +e`, so nothing reported any of it. It now validates with `named-checkconf`
*before* starting (plain, not `-z`: a record-level complaint should not cost the
instance all of DNS) and reports what it finds.

The remaining half is not the package's to do: **point the LAN at the box**, via
the router's DHCP "DNS server" option or per client. `postinst` prints the `dig`
command to confirm it.

The file holds DNS API secrets and is therefore **never rendered** from
`drumee.yaml` — the config only carries its path (`tls.acme_env_file`), and the
operator creates it 0600 out of band.

Container channel for contrast: the stock `caddy:2` image has no DNS-provider
modules compiled in, so it does HTTP-01/TLS-ALPN and needs 80/443 inbound.
DNS-01 there would require a custom Caddy build (`xcaddy` + `caddy-dns/*`).

### The drumee-caddy contract

`tls_method=caddy` configures the package built by **`caddy/`** in this repo: a
Caddy compiled with the `caddy-dns` provider modules, which is what lets it answer
DNS-01 and therefore issue wildcards (see `caddy/README.md`). It is the only
`Architecture: any` package here that compiles a binary of its own (`drumee-server-pod`
is `any` too, but only because it vendors prebuilt addons), and it is **optional** — not in the metapackage,
since it is only needed for this TLS method. `postinst` writes the two halves of
the interface and both sides must stay in sync:

| Path | Mode | Contents |
|---|---|---|
| `/etc/drumee/conf.d/caddy.json` | 0644, generated | `domain`, `dns_provider`, `acme_email`, `certs_dir`, `upstream_http_port`, `upstream_https_port` |
| `/etc/drumee/credential/caddy-dns.env` | **0600**, generated | `DRUMEE_CADDY_DNS_PROVIDER`, `DRUMEE_CADDY_DNS_TOKEN` |

What the package does in return: **exports each issued and renewed certificate
into the acme.sh layout** — `<certs_dir>/<name>_ecc/` holding `fullchain.cer`
(leaf + intermediates), `ca.cer` (intermediates only), `<name>.key` and
`<name>.cer`. The file names are what setup-infra's nginx includes
(`templates/etc/drumee/ssl/*.conf.tpl`) actually read; publishing only
`<name>.cer` leaves nginx unable to start. One
certificate covers every name, because the generated Caddyfile lists them in a
single site block and Caddy issues one cert with all of them as SANs.
`drumee-caddy-export-certs.timer` polls every 12h since Caddy offers no renewal
hook that is stable across versions.

**The names Drumee requires** are the apex plus one entry per service subdomain,
each needing its own wildcard — **a wildcard matches exactly one label**, in both
TLS and DNS, so `*.example.com` does *not* cover `x.vendors.example.com`:

```
example.com  *.example.com
jit.example.com      *.jit.example.com          (conferencing)
vendors.example.com  *.vendors.example.com
```

The set lives in one place per script — `SUBDOMAINS="jit vendors"` in
`drumee-caddy-config` and `drumee-caddy-export-certs` (override with
`DRUMEE_SUBDOMAINS`) — and must stay in step with setup-infra's nginx vhosts and
BIND zone. Adding a subdomain means touching both, plus the `own_ssl_path`
debconf text that tells operators what their own certs must cover.

`postinst` also moves nginx to `DRUMEE_HTTP_PORT`/`DRUMEE_HTTPS_PORT` (8080/8443
by default) because Caddy has to own 80/443, and sets `OWN_SSL` so acme.sh does
not race Caddy for the same certificates. Both `caddy.json` and `wireguard.json`
are **generated rather than shipped**, for the same reason: dpkg would treat a
shipped file as a conffile and prompt on every upgrade.

Two guards worth keeping: if no Caddy binary is found (`/usr/sbin/drumee-caddy`
or `caddy` on PATH) or no provider module was named, the choice is **refused** —
nginx keeps 80/443 and no `caddy.json` is written, because moving nginx off those
ports when nothing is there to take them leaves the box serving nothing at all.

The DNS API token is a secret, so `render.mjs` never emits it. Interactive
installs are asked (debconf `password` type); unattended installs add the one
line themselves:

```bash
printf 'drumee-infra\tdrumee-infra/caddy_dns_api_key\tpassword\t%s\n' "$TOKEN" \
  | debconf-set-selections
```

This pairs with WireGuard coordination: a **native** box on a home LAN can have
`acme-dns-api` (real wildcard certs, no open port) *and* `wireguard.enabled`
(reachable, no open port) — nothing about it needs port forwarding. The container
wizard's "Behind a home router" mode still falls back to `self-signed` purely
because of the Caddy limitation above, not because DNS-01 is impossible there.

`self-signed` still installs the nameserver (that is the point of the row above);
what it does not do is get you a public certificate. It is only meaningful with a
local domain: setup-infra has no
"public domain, no ACME" mode (`infra.js:42` sets `PUBLIC_DOMAIN` from any
non-empty `DRUMEE_DOMAIN_NAME`, and `bin/install` then runs `init-acme` unless
`OWN_CERTS_DIR` is set), so `postinst` warns when the two are combined. Note
`LOCAL_MODE` is bridged but setup-infra never reads it.

## Config System (Single Source of Truth)

`config/drumee.yaml` drives both channels. `config/render.mjs` is a dependency-free YAML parser + validator + renderer:

```bash
node config/render.mjs validate --config config/drumee.yaml
node config/render.mjs all --config config/drumee.yaml --out-dir out
# Commands: validate | env | compose | debconf | caddyfile | all
```

Outputs: `.env`, `docker-compose.yml`, `install.conf` (debconf preseed), `Caddyfile`. Null passwords in `database.password`/`redis.password` trigger automatic strong-random generation.

`tls.dns_challenge` (`nsupdate` | `api`) and `tls.acme_env_file` are native-only and
render into the `tls_method` / `acme_env_file` debconf keys — see the DNS-01
section above. The preseed still carries `own_ssl` so a package built before
`tls_method` existed selects the same path.

`config/drumee.schema.json` is the JSON Schema (draft 2020-12) defining the config contract. `config/drumee.example.yaml` is the annotated template.

## WireGuard Peer Coordination

Lets a Drumee node be reached from outside **without opening a port on the
user's router**. **Disabled by default**, and available on **both channels** —
systemd units from `drumee-infra` natively, a `wireguard` compose service in
containers. This is
the client half; the server half lives in the separate **`drumee/coord-server`**
repo (signaling server + UDP reflector + relay). The two repos share a config
contract (`coordinator_url`, `reflector_host`, `listen_port`) and must stay in
sync — a change to the message protocol on one side needs the matching change
on the other.

### Why it exists

Plugging a box into a home LAN gives it a routable (IPv6) address for free, but
the router's stateful firewall drops unsolicited inbound, so `:443` is
unreachable. Coordination exploits the one thing that always works — outbound.
The node holds an outbound WSS connection to the coordination server; when a
client wants in, both sides are told the other's public `IP:port` and fire
their WireGuard handshake at the same instant, punching each firewall's return
pinhole. Result: a direct, end-to-end encrypted P2P tunnel. The server never
sees traffic content. If the direct path fails (e.g. symmetric NAT), traffic
falls back through the server's relay.

### Components (in this repo)

| Piece | Path | Role |
|---|---|---|
| `bootstrap.sh` | `infra/var/lib/drumee/wireguard/` | First boot: generate keypair, bring up `wg0` on a **fixed** port |
| `agent.js` | `infra/var/lib/drumee/wireguard/` | Long-lived: probe reflector, register over WSS, program peers on `peer-info` |
| `drumee-wg-bootstrap.service` | `infra/etc/systemd/system/` | oneshot, ordered **before** the agent |
| `drumee-wg-agent.service` | `infra/etc/systemd/system/` | `Restart=always`, `CAP_NET_ADMIN` only |
| `wireguard.json` | generated into `/etc/drumee/conf.d/` by `postinst` | **Not** shipped as a conffile — avoids dpkg upgrade prompts |
| `Dockerfile.wireguard` + `wireguard-entrypoint.sh` | `deploy/docker/` | Container channel: **copies** `bootstrap.sh`/`agent.js` from the infra tree (build context `wg=`), renders `wireguard.json` from `WIREGUARD_*` env |

The private key is generated on-device and never leaves it; only the public key
reaches the coordination server. The two channels must run byte-identical
coordination logic (shared protocol with `coord-server`) — hence the copy from
`infra/var/lib/drumee/wireguard/` instead of a second implementation.

### Config contract

`config/drumee.yaml` — one block, both channels:

```yaml
wireguard:
  enabled: false
  coordinator: coord.drumee.tech
  listen_port: 51820      # MUST stay fixed — the NAT mapping is probed from it
  reflector_port: 51821
```

Defined in `config/drumee.schema.json` and validated in `config/render.mjs`
(`validate`): ports must be 1–65535, `coordinator` required when enabled, and
**`enabled` is rejected together with `instance.local_mode`** (NAT traversal is
meaningless on a LAN-only box). `render.mjs debconf` emits four keys:
`wireguard_enabled`, `wireguard_coordinator`, `wireguard_listen_port`,
`wireguard_reflector_port`; `render.mjs env` emits the matching `WIREGUARD_*`
and adds `wireguard` to `COMPOSE_PROFILES` when enabled.

### Install flow (native)

The debconf `config` script asks the WireGuard questions **only when
`local_mode` is false**. `postinst` bridges the answers to `WIREGUARD_*` env
vars, writes `/etc/drumee/conf.d/wireguard.json`, and enables/starts the two
units (or leaves them inactive when disabled). To change later:
`dpkg-reconfigure drumee-infra`.

`scripts/debian.sh` asks these questions itself (from `/dev/tty`) and
preseeds the four keys before `apt install` — along with **every other
drumee-infra setting**; see "debian.sh owns the interaction" below.
`WIREGUARD_ENABLED` / `WIREGUARD_COORDINATOR` / `…_LISTEN_PORT` /
`…_REFLECTOR_PORT` skip those prompts.

### Install flow (container)

`scripts/containers.sh` offers it as a **4th** answer to "How will people reach
this server?" — *Behind a home router*. That mode writes the `wireguard:` block,
keeps `local_mode: false`, and uses `tls.mode: self-signed` (with no inbound
port, ACME HTTP-01 cannot be answered). Opt-in on the domain/IP modes with
`WIREGUARD_ENABLED=true`; forced off in local mode. If the agent image is
neither pullable nor built, the wizard disables coordination with a message
rather than letting `compose up` fail on a missing image.

The rendered service uses `network_mode: host` + `cap_add: [NET_ADMIN]` — `wg0`
must live in the host namespace so the tunnel reaches the ports the proxy
publishes there and the probed NAT mapping is the host's own. That also excludes
the `drumee` network (mutually exclusive with host mode); the agent only talks to
the coordinator. The keypair persists on the `drumee_cred` volume. **The host
must have the `wireguard` kernel module** — a container cannot supply it.

### Two design decisions worth knowing

- **`wireguard.json` is generated by `postinst`, not shipped** in `infra/etc/`.
  This diverges from the other `conf.d/*.json` (which are shipped) but avoids
  dpkg treating it as a conffile and prompting on every upgrade.
- **Node 22 guard in `postinst`.** The agent uses the global `WebSocket` API
  (stable from Node 22), but the package only `Depends: nodejs (>= 20)`.
  `postinst` checks the running major version and, if < 22, leaves coordination
  disabled with a clear message instead of installing a service that
  crash-loops at boot. Bumping `Depends` was avoided because it would affect the
  whole stack.

### Why the listen port must stay fixed

The agent learns its public `IP:port` by probing the coordination server's UDP
reflector, which echoes back what it observes. That mapping is only usable if
the probe leaves from the **same** port `wg0` uses. A random port would yield a
mapping that points nowhere. Keep `listen_port` fixed in config; don't let
`wg-quick`-style tooling randomize it.

### Testing (lives in `coord-server`, references this repo)

The `coord-server` repo carries the test harness; the netns test points back
here for `agent.js` via `DRUMEE_AGENT_SRC`:

```bash
# Layer 1 — signaling logic, runs anywhere (no root, no wireguard module)
DRUMEE_AGENT_SRC=$PWD/infra/var/lib/drumee/wireguard/agent.js \
  bash ../coord-server/test/signaling-e2e.sh

# Layer 2 — real WireGuard through simulated NAT (root + wireguard module + Node 22)
sudo DRUMEE_AGENT_SRC=$PWD/infra/var/lib/drumee/wireguard/agent.js \
  bash ../coord-server/test/netns-e2e.sh
```

Layer 1 is stable (35+ consecutive passes) but uses `wg`/`ip` **shims**, so it
cannot see anything about real kernel behaviour. Layer 2 (`netns-e2e.sh`, real
WireGuard through simulated NAT) still has **not** been run.

In between, in this repo:

```bash
tests/wireguard/probe-port.sh [once|cycle|race]   # real kernel wg, ~70s
```

It runs the shipped agent against real kernel WireGuard inside a container's own
netns (Docker + the host's `wireguard` module; self-SKIPs otherwise, and never
touches host networking). The dev host *does* have the module — that is how the
port-borrowing bug below was found. Not in `run-all.sh`: needs Docker and a
kernel module.

### The endpoint probe borrows wg0's port (don't "simplify" this)

The reflector records the mapping of **whatever source port it observes**
(`coord-server/src/udpReflector.js` → `onObservedEndpoint`), so the probe must
leave from the port `wg0` uses or the coordinator hands peers an endpoint that
points nowhere.

A userspace socket **cannot** share that port with kernel WireGuard: the wg
socket is created kernel-side without `SO_REUSEPORT`, so the bind fails with
`EADDRINUSE` whatever options are set. This was measured, and the original
`SO_REUSEADDR`-plus-ephemeral-fallback silently produced useless mappings —
every session would have fallen back to relay.

`agent.js` therefore **borrows** the port: `wg set wg0 listen-port 0` → bind →
probe → hand the fixed port straight back (with retries; losing it makes the node
unreachable). Three invariants keep that safe, each with a regression scenario in
`tests/wireguard/`:

- **Never while busy.** `tunnelBusy()` skips the probe when a peer handshook in
  the last 180 s (wg's own keepalives then refresh the mapping) or a rendezvous
  was programmed in the last 30 s.
- **Never concurrently.** `probeInFlight` serializes cycles — a reconnect
  re-triggers the probe, and two overlapping borrows fight over the port.
- **`peer-info` waits for the port.** Programming a peer mid-probe would fire the
  handshake from the temporary ephemeral port, so the handler awaits
  `probeInFlight` first.

Also note `closeSocket()`: `dgram.close()` only *starts* teardown, and handing
the port back before `'close'` fires races the kernel (`wg set listen-port` then
fails with EADDRINUSE). Both this and the concurrency bug were caught by the
tests, not by reading the code.

### Open points / validation TODO

- **`WG_RELAY_PUBKEY`** must be set on the coordination server (from
  `/etc/wireguard/server_public.key`) or relay fallback returns a clear
  `connect-failed` instead of relaying.
- **Symmetric NAT** always falls back to relay — known limitation, not a bug.
- **The client APP is the connect initiator**; the shipped agent is purely
  passive (it waits for `peer-info`). The initiator protocol reference is
  `coord-server/test/initiator.js`.

## Container Channel

**The source-based images under `deploy/docker/` are deprecated** — see
@deploy/docker/DEPRECATED.md. They build from source checkouts, so nothing pins what
went into an image and the OS dependencies live in Dockerfiles instead of
`debian/control`. The replacement installs the seven role packages
(`roles/debian/control`, each `Provides`/`Conflicts: drumee-role`) into
`docker/Dockerfile.base`, which is already digest-pinned with UID/GID 8000 and a
committed NodeSource keyring.

Nothing is removed yet: this is still the only working container path. The build
scripts print a deprecation notice (`DRUMEE_QUIET_DEPRECATION=1` silences it), and the
removal criteria are listed in DEPRECATED.md.

Worth knowing: **all three `check-packaging.sh` failures live in this deprecated tree**
and are deliberately not being fixed in place — digest-pinning a `FROM` in a file that
is being deleted buys nothing, and `npm install -g pm2` is already obsolete now that
`drumee-node-runtime` is published. The exception is `Architecture: all` on
`drumee-server-pod`, which needs deciding regardless because the role images inherit it
(`docs/distribution.md` §9.1).

```bash
scripts/build-images-local.sh   # build images from local source (tag: local)
scripts/dev-up.sh               # render config + bring up compose stack
scripts/dev-down.sh             # stop stack (KEEP_DATA=1 to preserve volumes)
```

Compose orchestration order: `mariadb` healthcheck → `schemas-init` → `ui-build` → `schemas-populate` → `server-pod` + `factory`, fronted by a `caddy` proxy.

Dockerfiles live in `deploy/docker/`. Key files:
- `ecosystem.config.js` — pm2 config (`--restPort 24000`, `--pushPort 23000`, `--http-port`, `--conf-path`)
- `entrypoint.sh` — sources `/etc/drumee/drumee.sh`, applies pending patches, launches pm2
- `schemas-init.sh` — idempotent DB bootstrap (creates `yp`, `utils`, `mailserver`, `template`, `trash`)
- `container-populate.js` — creates system accounts + RSA keypair + entity pool
- `container-factory.js` — daemon replenishing the pool (watermark-based, default 10)

Env vars for local builds: `SERVER_SRC`, `UI_SRC`, `SCHEMAS_SRC`, `SETUP_SCHEMAS_SRC`, `SETUP_INFRA_SRC`.

## Release & Version Management

### release-manifest.yaml

The authoritative version file. `product` is the user-facing release-train version; component versions are internal:

```yaml
product: 1.0.0
infra: 1.2.11
schemas: 2.6.99
server: 2.9.73
...
```

### Version coherence workflow

```bash
scripts/check-versions.sh          # verify changelogs match manifest (CI guard)
scripts/check-versions.sh --sync   # auto-update changelogs from manifest
meta/make-control.sh               # regenerate metapackage deps pinned to manifest
meta/make-control.sh --check       # CI guard: fail if out of sync
```

To bump a version: edit `release-manifest.yaml`, then run `--sync` + `make-control.sh`.

A **release-train** bump touches **two** manifest keys — top-level `release:` *and*
`components.meta` — and `--sync` writes only the component changelogs, reporting
`DRIFT release` for the train; `meta/make-control.sh` writes that one. Bumping either
key alone leaves a guard failing. Full walkthrough of the build→publish path, and the
steps that look optional but are not, in @docs/build-pipeline.md.

### Where the release stands: `scripts/release-status.sh`

```bash
scripts/release-status.sh              # local (left) vs live (right)
scripts/release-status.sh --no-remote  # no network calls
```

One table answering "is what I have what users get". Two details are load-bearing rather
than cosmetic, both found by a release that was correct while the table said otherwise:
**`drumee-roles` is a source package**, whose binaries are `drumee-release` plus seven
`drumee-role-*`, so the row tracks `drumee-release` (the anchor every role depends on at
strict equality) and a separate `└ role packages` line counts the seven — equality cannot
reveal a *partial* publish. And the **Debian revision never decides the verdict**: roles
are versioned `<release>-1~<channel>1`, so comparing that literally against the manifest's
`1.0.55` painted a correct release red, which teaches the reader to ignore the one column
that matters.

Local is three separate columns
because they drift independently: **manifest** (authoritative), **built** (newest
`.deb` under `<pkg>/build/` — a bump with no rebuild ships nothing), **staged** (what
`apt-pool/` advertises). The right column is what `apt.drumee.net` actually
serves, plus a **live arch** column — `amd64+arm64` for the arch:all packages,
`amd64` alone for `drumee-server-pod` since 2.9.98.

Both sides read the **pool** layout. They used to read the flat one, which went wrong
the moment flat was frozen at 1.0.22: every current package reported `differs` against
a repository nobody is meant to install from. The flat repo keeps its own section,
labelled frozen, where "in sync" means the frozen bytes are intact — not that the
current release is published. Also covers git per repo, tags local vs `git ls-remote`, the checksum of the
published `debian.sh` against `scripts/debian.sh`, and an rsync dry-run of
`apt-repo/` against the server. `git` and `curl` only.

The installer row exists because `publish-apt.sh` does **not** copy `debian.sh` —
only `publish-site.sh` does — so the documented `curl … | sudo bash` can serve a
previous installer while packages publish fine.

### update-changelog.sh

`server/`, `static/`, `ui/`, `schemas-patch/` each have one. Compares `debian/changelog` version against the upstream `package.json` version and picks whichever is **higher**. Without `--message`, it pulls the last 5 non-merge git commits as bullet points. Called automatically by `server/build.sh`, `ui/build.sh`, and `static/build.sh` (not `schemas-patch`).

### Debian changelog format

```
<package-name> (<version>) unstable; urgency=medium

  * Change description

 -- Maintainer Name <email>  Day, DD Mon YYYY HH:MM:SS +TZOFF
```

Two-space indent before bullets and single-space before `--` are required by `dpkg-parsechangelog`.

## Publishing & Distribution

Two layouts are served from `apt.drumee.net` at once, deliberately: the flat
repository that existing installs already point at, and the `dists/pool` tree
that replaces it. See "Coexistence with the flat repository" in
`docs/distribution.md` §4 — in short, `dists/` and `pool/` deploy *beside* the
flat files, the flat publish excludes them from its `--delete`, and reprepro's
`conf/`+`db/` are never uploaded.

### APT repository — pool/dists (`scripts/publish-pool.sh`)

```bash
scripts/publish-pool.sh init    --key=EMAIL_OR_KEYID
scripts/publish-pool.sh include --debs=DIR [--suite=trixie] [--component=main]
scripts/publish-pool.sh promote --from=trixie-beta --to=trixie
scripts/publish-pool.sh verify|check|list|sources [SUITE]
scripts/deploy-apt-repo.sh --layout=pool --no-provision
```

reprepro-based, staged in `apt-pool/` (gitignored). Suites are the channels
(`trixie`, `trixie-beta`, `trixie-edge`), components are the open-core split
(`main`, `enterprise`); the shape lives in `scripts/lib/apt-repo.sh`, shared with
`apt-repo-local.sh` so the two cannot drift. `check` resolves a package with a
real apt client in a container. **Sign with the same key as the flat repository**
or already-installed boxes get `NO_PUBKEY`.

Clients configure (deb822, pointing at the pool):

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://apt.drumee.net/drumee-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/drumee-archive-keyring.gpg >/dev/null
sudo tee /etc/apt/sources.list.d/drumee.sources >/dev/null <<'SOURCES'
Types: deb
URIs: https://apt.drumee.net
Suites: trixie
Components: main
Signed-By: /etc/apt/keyrings/drumee-archive-keyring.gpg
SOURCES
sudo apt update && sudo apt install drumee
```

`Suites` is the release channel — `trixie` is stable, `trixie-beta` and `trixie-edge`
exist for pre-release trains and are mutually exclusive with it. `Architectures` is
deliberately omitted so apt uses dpkg's native architecture; the pool publishes both
`amd64` and `arm64`.

`scripts/debian.sh` does this automatically. Overridable: `APT_URL`, `APT_SUITE`
(the channel), `APT_COMPONENT`, `KEYRING_URL`, `KEYRING_PATH`. Re-running it on a box
that still carries the flat `drumee.list` **removes that stanza**, so the installer is
also the migration path off flat.

### APT repository (flat, FROZEN)

```bash
scripts/publish-apt.sh --debs=DIR --out=REPO_DIR [--key=EMAIL_OR_KEYID]
scripts/deploy-apt-repo.sh [--host=USER@HOST] [--repo-dir=DIR] [--domain=DOMAIN]
```

**Frozen as of release 1.0.23, which was published to the pool only.** It still serves
everything it already served — boxes installed against it keep working, and its `.deb`
files stay downloadable — but new releases do not go here. Do not publish to it without
a deliberate reason; new work belongs in the pool above.

Existing clients are migrated by re-running `scripts/debian.sh`, which replaces the flat
`drumee.list` with the deb822 `.sources` stanza. Until a box is migrated it simply stops
seeing new versions; nothing breaks.

`publish-apt.sh` generates `Packages`, `Packages.gz`, `Release`, `InRelease`, `Release.gpg`, and `drumee-archive-keyring.asc` into a flat directory (no `dists/pool` tree). Requires `apt-utils` (for `apt-ftparchive`) and `gpg`.

`deploy-apt-repo.sh` rsyncs that directory to the VPS document root (default `/var/www/apt.drumee.net`), installs an nginx vhost for the domain (default `apt.drumee.net`), and reloads nginx. `--host` defaults to **`debian@apt.drumee.net`** (production) — pass it to target a staging box or mirror; it prints the resolved target before doing anything. TLS is set up separately with certbot; `APT_LOCAL_DIR` selects the local repo dir (default `apt-repo`). CI does not rely on the default: `publish-site.sh` always passes `--host="$APT_SSH_HOST"` and skips the deploy entirely when that is unset.

### Package-based role images (the replacement path)

```bash
docker/build-role.sh web                  # version from release-manifest.yaml
docker/build-role.sh infra                # the configuration-rendering job
APT_URI=http://localhost:8099 docker/build-role.sh web   # against a local repo
```

**All seven now exist**: `docker/Dockerfile.role-{web,infra,app,schemas,dns,mail,converter}`.
Each contains **no source checkout, no git clone, no webpack and not one component
version** — it installs one metapackage at an exact version and lets dpkg resolve the
rest. `ROLE_VERSION` has no
default on purpose: a default would be a component version written outside
`release-manifest.yaml`.

The base is pinned by **digest**, and `build-role.sh` exists because of how that has to
be obtained: a locally-built image has no repo digest, and `FROM name@<image id>` is
rejected for an image that was never pushed (measured). So the script pushes the base to
a throwaway local registry and reads the digest back — the same mechanism the release
path uses against the real registry.

`docker/keyrings/drumee-archive-keyring.gpg` is the **public** half of the archive key,
committed rather than fetched: fetching a key at build time is what the
`curl … | gpg --dearmor` invariant forbids. `drumee-apt-source` refuses to write a
stanza whose keyring is missing, so an unsigned source cannot appear by accident.

**The roles do not decompose anything yet, and the reason is in `debian/control`.**
`drumee-role-web` asks for `ui-pod`, `static`, `bootstrap` and nginx, and resolves to
**508 packages** — every Drumee component plus mariadb-server, redis-server, LibreOffice
(23 packages), ffmpeg, GraphicsMagick, nodejs, g++ and binutils. The chain:

```
role-web → drumee-ui-pod → drumee-server-pod → drumee-schemas → mariadb-server
                                             → libreoffice, ffmpeg, graphicsmagick
         → drumee-static  → drumee-infra    → nginx, g++, binutils, gyp
```

Those `Depends` are native-channel assumptions from when everything was one box, and
they are harmless there because the metapackage installs the whole set anyway. In the
container channel they defeat the entire decomposition — including the security argument
for splitting out `drumee-converter` (`docs/distribution.md` §2), since the web role would
carry the document parsers. **Fixing this means `drumee-ui-pod` dropping
`Depends: drumee-server-pod` and `drumee-static` dropping `Depends: drumee-infra`** (plus
the `binutils`/`git`/`nodejs` build-time leftovers). Neither has a postinst that needs
the other, and `tests/native/control-deps.sh` is the guard for the ordering question.

A second consequence: `role-web` is `Architecture: all` but transitively requires
`drumee-server-pod`, which is amd64-only — so it is **not installable on arm64** today,
verified against the published `binary-arm64` index.

### The role stack — `images.stack: roles`

```yaml
images:
  registry: drumee
  stack: roles        # default is still 'source'
```

`render.mjs compose` emits the package-based topology of `docs/distribution.md` §2 when
this is set: **db, cache, infra-init, schemas-init, migrate, app, web, converter** plus
profile-gated **dns** and **mail**. `docker compose config` validates it, and
`docker/build-role.sh` builds the images.

It is not the default because none of the role images are **published** yet — every one is
built locally against a local repository. Emitting it by default would hand every existing
caller a stack that cannot pull. That is criterion 1 of `deploy/docker/DEPRECATED.md`.

Four differences that are the point of the exercise:

- **No `ui-build`.** `drumee-ui-pod` already contains the webpack output. Nothing compiles
  in a running deployment.
- **One tag for every role** (`ROLES_TAG`), not one per component. `drumee-release` pins
  the train and every role depends on it at strict equality, so a per-role tag would
  invite exactly the mix the anchor exists to prevent.
- **Configuration comes from a volume**, not from packages configuring hosts. Consumers
  mount `volume.subpath` of `drumee_conf` **read-only**, so each role sees only its part
  of the tree and cannot rewrite it. Needs Compose ≥ 2.26 / Engine ≥ 25.
- **mariadb and redis are the official images**, `mariadb:11.8` matching what Trixie
  ships.

Proven end to end with the two images that exist: `infra-init` renders 41 files into
`drumee_conf`, the **web role serves 301 on HTTP and 502 on HTTPS** — 502 being exactly
right, since it proxies to an `app` role that has no image yet — and the certificate it
presents is `CN=roles.lan`, created by `infra-init` and read from the shared volume, not
baked into the image.

Five things bringing that up actually taught, each a measured failure:

| Symptom | Cause |
|---|---|
| BIND zone file named `auto` | `network.ip4: auto` is a *sentinel*; `renderDebconf` stripped it, `renderEnv` did not — and `infra.js` reads `PUBLIC_IP4` from the environment, so dropping the flag alone was not enough |
| `mkdir "/srv/drumee/cache/<domain>" failed` | nginx creates its `proxy_cache_path` at startup; the directory has to exist, owned by uid 8000 |
| `mkdir "/var/lib/nginx/body" failed (13)` | Debian's nginx expects root→www-data; this role runs as 8000, so nginx is master *and* worker and every path it writes must belong to that uid |
| `"pid" directive is duplicate` | `-g "pid ..."` is **additive**, not an override. Ownership of `/run/nginx.pid` is the fix |
| `OWN_CERTS_DIR: parameter not set` | `drumee.sh` is generated per deployment and references variables it does not define; sourcing it under `set -u` aborts every entrypoint. Fixed once, in `lib.sh` |

And one conflation worth remembering: **`DRUMEE_HTTP_PORT` is the port nginx binds**, because setup-infra renders it into the `listen` directive. Mapping it to container port 80 published a port nothing was listening on — a healthy container refusing connections. The roles stack publishes the same number on both sides, so one name keeps one meaning.

**Iterate against a local repository, not by publishing.** `scripts/apt-repo-local.sh
init|include|serve` plus `APT_URI=http://<docker-gateway>:8099
APT_KEYRING=drumee-local-keyring.gpg docker/build-role.sh <role>`. Role image tags follow
the release train, so every entrypoint or Dockerfile fix otherwise costs a release — four
were burned before switching to this.

Two traps that come with that loop, both measured:

- **reprepro refuses to re-include a version it already has.** `reprepro -b .apt-local
  --gnupghome .apt-local/gnupg remove trixie <pkg>` first, then include.
- **buildx will happily reuse the apt layer** once the package is replaced, because the
  Dockerfile and every build-arg are unchanged — so the new package never reaches the
  image and the build prints the version it *believes* it installed. A rebuilt
  `role-converter` still carried the previous entrypoint, and the check meant to catch
  that passed against stale content. `docker/build-role.sh` now passes an
  `APT_CACHEBUST` derived from the local repository's `Release` file whenever `APT_URI`
  is not `apt.drumee.net` (and takes `--no-cache`); against the real repository a version
  is immutable, so the cache stays.

### The schemas role — the database, and how far provisioning gets

`docker/build-role.sh schemas` builds `drumee/role-schemas`, a run-once job taking `init`
or `migrate` (two invocations of one image, because §6 needs `migrate` separately
re-runnable). It installs `drumee-schemas` and `drumee-patch`, and it deliberately does
**not** run `setup-schemas/bin/install`: that restores a mariabackup **physical** snapshot
with `--copy-back`, which cannot reach a database living in another container. The image
deletes the 35 MB seed it will never use.

`init` does both halves, as `bin/install` does natively — bootstrap, then populate:

- **bootstrap** is `/usr/lib/drumee/schemas/init`, shipped by `drumee-bootstrap` (it moved
  out of `deploy/docker/` so it is versioned in a package rather than copied into an image,
  §9.2). It creates the base databases from the schemas repo's own `templates/factory/`
  tree over TCP as root, configures the domain and grants the application user. One copy,
  three consumers: this role, the deprecated images, and the offline seed builder.
- **populate** is `setup-schemas`' **own** `populate.js` — not a container fork. See
  `docs/channel-parity.md` §5b.

It reads the application credentials from the rendered volume's `db.json` and the domain
from `drumee.sh`; only `DB_ROOT_PASSWORD` comes from the deployment, because creating
databases is the one thing that needs root. Populate is skipped when `yp.sys_conf` already
has rows — otherwise a restarted run-once job would mint new system accounts and a second
entity pool every time. The job mounts the config tree **read-write** and the storage
volume, because provisioning creates the MFS roots and the RSA keypair; every long-running
role still mounts that tree read-only.

**Verified:** 5 databases, **143 tables in `yp`**, the `drumee-app` user authenticates,
**20 factory pool entities** stocked, and the four system accounts (`nobody`, `guest`,
`system`, `admin`) created.

**Where provisioning stops today**, and it is not a channel problem: `createHub` returns
undefined for the system user's media hub and `createAdmin` then fails with
`Cannot read properties of undefined (reading 'id')` at `lib/organization.js:264`. The log
prints `Failed to create hub` beside a result set that looks successful — `failed: 0`,
permissions granted, a `db_name` and an `mfs_root` — so `createHub` is rejecting its own
result. Answering why needs `setup-schemas`/`server-core` domain knowledge about what that
function expects, not more container work. Until it is answered the instance has a schema,
a pool and accounts but no workspace, and the app answers 500 with
`call undefined.get_fonts_faces()` — which is what an empty `yp.sys_conf` looks like from
the outside.

### The app role — how far the stack gets

`docker/build-role.sh app` builds `drumee/role-app` (2.6 GB): `drumee-server-pod`,
`drumee-node-runtime`, `drumee-bootstrap`, `drumee-release`, uid 8000, no build tooling,
**no `mariadb-server`** — the database lives in its own container on the official image,
which is what dropping `server-pod → drumee-schemas` at 2.9.99 bought.

Running it against `db`, `cache` and `infra-init` gets to:

```
Successfully connected to Redis redis:6379          ← the alias works
Access denied for user 'drumee-app'@'172.23.0.4'    ← the schemas role has not run
loadUiinfo: app UI information file was not found under /srv/drumee/runtime/ui/main
```

That is the correct place to stop: the `drumee-app` database user and the `yp`/`utils`/
`mailserver`/`template`/`trash` databases are created by **`drumee-role-schemas`**, which
has no image yet. The app is not broken, it is unprovisioned.

Three things the bring-up taught, each already fixed where it belongs:

- **Named volumes inherit ownership from the image directory beneath them.**
  `/etc/drumee/credential` is mounted writable over the read-only config tree (the app
  writes `db.json`/`redis.json` from `.env`, because a compose deployment's credentials
  come from there and not from infra-init's generated ones). `drumee-infra` is
  deliberately absent from this role, so that directory did not exist and Docker created
  the mountpoint root-owned — `cannot create /etc/drumee/credential/db.json: Permission
  denied`. The Dockerfile creates it owned by 8000.
- **`pm2-runtime` IS the no-daemon entry point.** `--no-daemon` makes it exit with
  `unknown option`, which crash-looped the role before it reached any application code.
- **The service names and `database.host`/`redis.host` must agree.** The config says
  `mariadb` and `redis`; §2 names the services `db` and `cache`. The app dials what the
  config says, so it resolved nothing (`getaddrinfo ENOTFOUND redis`) inside a container
  pm2 reported as running. Fixed with network **aliases** rather than renaming the
  services, so the topology keeps the design's names and the deployment keeps its config's
  hostnames.

Two findings left open, both in `drumee-server-pod`'s `Depends` rather than in the image:

- It still pulls **`nginx`, `redis-server`** and the whole **media stack** (LibreOffice,
  ffmpeg, GraphicsMagick), which is most of the 2.6 GB. nginx and redis-server are pure
  declaration errors — this role runs neither. The media tools are not: `server-pod`'s code
  shells out to them, so moving them to the media role needs a change in `server-team`,
  not just a control file.
- `loadUiinfo` reads `/srv/drumee/runtime/ui/main`, which is `drumee-ui-pod`'s payload and
  belongs to the web role. Either the app needs that manifest mounted, or the lookup
  belongs on the web side. It logs a warning today, so it is not blocking, but it is a
  cross-role coupling the split has not resolved.

### Channel parity — one configuration path

Design: @docs/channel-parity.md. **Change 1 is done**: the container channel no longer has
its own configuration vocabulary. `infra-init` renders by reconfiguring the package:

```
debconf-set-selections < install.conf
DEBCONF_RECONFIGURE=1 DRUMEE_CHROOT=/out dpkg-reconfigure drumee-infra
```

so both channels drive the same preseed, the same debconf→`DRUMEE_*` bridge, the same
`bin/install` and the same renderers. `install.conf` is mounted read-only into the job.
The hand-mapped env→`infra.js`-flags translation is gone, and with it the five defects
`channel-parity.md` §2 lists — all of which came from having a second mapping.

`DRUMEE_CHROOT` does double duty, deliberately: `bin/install` forwards it as `--chroot`,
and `postinst` reads it as *"this is a render, not a host configure"* and skips
`ensure_nginx_stream_module`, `finish_dns`, `setup_wireguard` and `reload_nginx`.
`bin/install` skips the crontab and the host steps below it for the same reason. One
signal rather than a new flag — rendering into a target and reconfiguring the machine you
are on are different operations, and the target is what distinguishes them.

Adopting the native path immediately surfaced **three bugs that were invisible while the
two channels were separate**, and every one of them also affected native installs:

| Defect | Why it hid |
|---|---|
| `DRUMEE_BUILD_TIME` beat `DRUMEE_CHROOT`, so a deploy-time reconfigure was treated as an image build and rendered nothing | The two flags were added days apart for different purposes and had never met. A render target is the more specific signal and is never the host, so it wins |
| `bin/install` reported `Setup has failed` after rendering the entire tree | Its postcondition read the absolute `/etc/drumee/drumee.sh`. An absolute path hides until something renders somewhere else |
| nginx refused **all** configuration: `open() "/etc/jitsi/meet.public.conf" failed` | `jitsi.js` ran unconditionally and emits a vhost that includes the Jitsi tree. Natively the same run rendered that tree too, so nginx was satisfied and nobody looked. Now gated on `USE_JITSI`, derived from the services answer |

Note the Jitsi gate changes **fresh** renders only — a render adds files, it does not prune,
so an upgraded box keeps a `20-jitsi.public.conf` it already had (harmlessly, since its
`/etc/jitsi` tree is there too).

Verified both ways at 1.0.41: the container job renders 41 files and exits 0 with the host
steps skipped, the web role serves 301/502 against it, and `lifecycle-remote.sh` on testbox
is 15/15 with `https://` still 200.

### infra-init — the configuration-rendering job

`docs/distribution.md` §5 made real: the package delivers the payload at build time, this
container executes it at deploy time. `drumee/role-infra` runs
`docker/infra-init-entrypoint.sh`, which renders with **setup-infra's own engine**
(`infra.js --chroot=/out`) into the shared configuration volume and exits. Nothing here
reimplements a template — the 43-file tree has one source of truth and the container
channel must not grow a second.

```bash
docker volume create drumee_conf
docker run --rm -v drumee_conf:/out \
  -e DRUMEE_DOMAIN_NAME=example.com -e PUBLIC_IP4=203.0.113.7 \
  -e ADMIN_EMAIL=ops@example.com drumee/role-infra:<release>
```

Measured: 43 files, `domain_name` correct, all three nginx vhosts, all four BIND zones,
credentials `0640` in a `0750` directory, the whole tree owned `8000:8000` and readable by
the web role running as uid 8000. **Its own filesystem is unchanged by the render** —
verified by hashing `/etc/drumee`, `/etc/nginx`, `/var/lib/bind`, `/etc/bind`,
`/srv/drumee` and `/etc/postfix` before and after. (The 12 files already under
`/etc/drumee` in that image are `drumee-infra` conffiles, not render output.)

Idempotence is `infra.js`'s own: `hasExistingSettings()` sees the `drumee.json` a previous
run wrote and does nothing, so a restarted job is a no-op; `FORCE_RENDER=1` passes
`--reconfigure=1`. That is deliberately the same contract as `dpkg-reconfigure` on the
native channel — same behaviour, same reason.

**`DRUMEE_BUILD_TIME` is what made this image possible at all.** `drumee-infra`'s postinst
rightly refuses to configure a host without an answered domain question, so installing
`drumee-role-infra` in a Dockerfile failed the whole apt transaction. `policy-rc.d`
already stops a maintainer script *starting a service* during a build; nothing stopped one
*configuring the machine*. The flag is set as `ENV` in `docker/Dockerfile.base` next to
`policy-rc.d`, and infra's postinst delivers its payload and renders nothing when it sees
it. It stays set in the running container on purpose — configuration there comes from the
volume, not from dpkg.

Three things the job's env contract depends on, each found by running it rather than
reading it:

- `--admin-email` **is not an `infra.js` option**; that value travels in the environment.
  Passing it makes argparse exit 2 with a usage dump that reads like a crash.
- A render with no public IP produces only the private branch — no `01-public.conf`, no
  public zone. Compose must supply `PUBLIC_IP4` for a public deployment.
- `drumee-infra` `Depends` on `g++` and `gyp`, so this job image carries build tooling
  (716 MB). It is a run-once job rather than a running service, so it is tolerable, but
  those two dependencies look wrong in a runtime package and are worth revisiting.

### Container images

```bash
scripts/publish-images.sh   # build + push to registry
# Env: REGISTRY, TAG, PUSH=1, PLATFORMS, ALSO_LATEST, ALSO_STABLE, MEDIA_DEPS, INSTALL_DEPS
```

**On demand, without cutting a release tag** — the container channel is unusable
until images exist in the registry, so `release.yml` also takes a
`workflow_dispatch` with `tag`, `platforms` and `push` inputs. A manual run builds
and signs images only; the `.deb`/apt jobs are gated on `github.event_name ==
'push'` so they stay tied to real tags.

`PLATFORMS` defaults to `linux/amd64`. Add `linux/arm64` for Raspberry Pi and
other ARM home servers — which is the *typical* target for the behind-a-router
flow, so a release meant for those boxes must publish it. **But an arm64 image is
not enough on its own now that the roles install packages**: `drumee-server-pod` is
`Architecture: any` and only amd64 is built, so an arm64 role image would fail at
`apt install`. Publishing arm64 means building the package for arm64 first. Multi-platform requires
`PUSH=1` (buildx cannot `--load` a manifest list) and QEMU, which the workflow
installs. Emulated cross-builds of the media stack take the better part of an
hour, which is why it is opt-in rather than the default.

**`INSTALL_DEPS=0` means the image packages the checkout's `node_modules`.** Both
`Dockerfile.server` and `Dockerfile.ui` now **fail** when that directory is
missing: previously the build succeeded and produced a server-pod with no
dependencies at all — verified — which crashes at startup while CI reports a green
publish. The private `@drumee` packages need `NPM_TOKEN` in CI for the install to
succeed at all; without it the workflow now stops with a named error instead of
publishing an empty image.

### Full site publish (apt + Pages)

```bash
APT_SSH_HOST=deploy@vps GH_TOKEN=<token> scripts/publish-site.sh --debs=out-debs [--key=KEYID]
```

Builds the flat repo once, then deploys it to two independent targets: `apt.drumee.net` over rsync/SSH (`APT_SSH_HOST`, `APT_REPO_DIR`, `APT_DOMAIN`) and the `get.drumee.com` Pages content — installers, renderer, keyring, CLIs — to `PAGES_REPO` (`GH_TOKEN`). Each target is skipped with a notice when its credential is absent; setting neither is an error. `scripts/debian.sh` is copied into the flat repo so `https://apt.drumee.net/debian.sh` serves the bootstrap without depending on Pages. It is **also** copied to both earlier names — `baremetal.sh` and `install-native.sh` — so bootstrap commands already in circulation keep working; retire one only after confirming it is referenced nowhere. Note a renamed or newly added URL only goes live after the next `publish-site.sh` run (or an equivalent manual stage + deploy).

## debian.sh owns the interaction

`scripts/debian.sh` asks for **every** drumee-infra setting itself and
preseeds the answers, rather than leaving the questions to debconf. Two reasons,
both structural:

- On the documented `curl … | sudo bash` path **stdin is the script**, so debconf
  never has a terminal and silently takes every default. All prompts therefore
  read `/dev/tty`, and apt is handed `<"$TTY"` too so dependencies with their own
  questions (postfix) still work.
- `infra/debian/config` asks `db_dir`, `data_dir`, `backup_location`,
  `exchange_location` and the wireguard ports at **medium/low** priority, which
  the default debconf priority never displays. They were unreachable interactively.

| | |
|---|---|
| Gate | `DRUMEE_NONINTERACTIVE` unset or `0` → prompt; **any other value** → silent |
| Per-answer override | `DRUMEE_DOMAIN`, `DRUMEE_TLS_METHOD`, … (full list in the script header) — set means don't ask |
| `PRESEED=<install.conf>` | unattended, no prompts at all; the preseed decides everything |

### Topology decides the shape of the install

`detect_topology` classifies the host's `scope global` addresses *before* asking
anything, and the branch it picks drives the domain, the TLS method and the admin
email. Full walkthrough in `docs/debian.md`.

| Branch | Condition | Serving address | `tls_method` | `local_mode` | Domain default |
|---|---|---|---|---|---|
| **wan** | ≥1 public address | asked, defaults to first public | asked: `acme-dns-server` (default), `acme-dns-api`, `caddy`, `own` | `false` | `example.com` |
| **lan** + `dns` | no public, ≥1 private | asked, defaults to first private | `self-signed`, not asked | `true` | `drumee.lan` |
| **lan** + `wireguard` | as above | as above | asked: `acme-dns-api` (default), `caddy`, `own`, `self-signed` | `false` | `example.com` |
| **localhost** | neither | not asked | `self-signed`, not asked | `true` | `localhost` |

The lan branch asks **how it should be reached** before anything else, because the
two answers are mutually exclusive by construction: `render.mjs:210` rejects
`wireguard.enabled` with `local_mode`, and `infra/debian/config:106` skips the
WireGuard questions when `local_mode` is true. `dns` = LAN-only, BIND9 serves the
zone, self-signed. `wireguard` = reachable with no open port, `local_mode=false`,
and a real certificate becomes possible over DNS-01. `acme-dns-server` is absent
from the wireguard menu on purpose — it needs inbound udp/53, which is the one
thing that box hasn't got.

**`local_mode` is always preseeded, including `false`** — see the trap below. It is
belt-and-braces now that drumee-infra ≥ 1.2.26 writes the value itself, and it is
what keeps this script correct against an older infra package.

### The local_mode trap (fixed in drumee-infra 1.2.26)

`local_mode` is only ever *asked* for the literal domain `"local"`, so on any other
install nothing answered it — and an unanswered debconf question reads back as its
template default, which was **`true`**. `infra/debian/config` read that back and ran
`db_set tls_method self-signed`, never showing the `tls_method` question at all
because its `db_input` sits in the other arm of the same test.

Measured against the real `config` script in a Trixie container, before the fix:

| Preseed | `local_mode` | `tls_method` |
|---|---|---|
| `domain=example.com` only | `true` | **`self-signed`** |
| `domain=example.com` + `tls_method=acme-dns-api` | `true` | **`self-signed`** — overwritten |
| … + `local_mode=false` | `false` | `acme-dns-api` |

So only a preseed carrying `local_mode` escaped it. `render.mjs debconf` always
emits that key, which is why the rendered-preseed path never hit this and anything
partial or hand-written did.

Fixed in both halves, because two paths read the value: the **template** now
defaults to `false` (what a bare `dpkg -i` reads — dpkg runs no config script), and
**`config` writes it explicitly** for the apt/`dpkg-reconfigure` path, guarded by
`db_fget … seen` so a preseed still wins. The `"local"` branch pre-sets `true`
before asking, so that question keeps offering the answer the operator just implied.

Private means RFC1918, **CGNAT `100.64/10`** and IPv6 ULA `fc00::/7` — CGNAT is
not RFC1918 but is exactly as unreachable from outside, which is the only property
that matters. Everything else is public, including IPv6 GUA `2000::/3`.

Why `lan` is not a real TLS choice: no CA can validate a name that is delegated
nowhere, so `self-signed` is the only honest answer — and it is also the path that
installs BIND9 to *serve* the zone locally, which is what makes the name usable on
the LAN at all. `local_mode=true` travels with it and skips the WireGuard
questions.

The domain on those branches is not the literal string `"local"`, and does not
need to be: `infra/debian/config:29` only *asks* `local_mode` when it is, and
never overwrites a preseeded answer — line 55 then reads `local_mode` back and
forces `self-signed` from it. The two agree.

Everything else — question order, conditions, defaults — **mirrors
`infra/debian/config` and `infra/debian/templates`**. The two must stay in step: a
question asked here is marked *seen*, so debconf will not ask it, and a divergence
lands silently in the rendered configuration rather than as an error.

One deliberate addition: it also asks for the **serving IPv4/IPv6**, which
`infra/debian/config` never asks but `infra/debian/postinst` reads. On the
interactive path they were always empty, so `infra.js` skipped the entire public
branch — no nginx `01-public.conf`, no public/reverse BIND zones, no
postfix/opendkim. Detected addresses are offered as interactive defaults only;
unattended they stay unset (the detected address is usually the LAN one, and
preseeding it as *public* would quietly change every existing unattended install).
`-` declines a family.

## Deployment

### Manual native install

```bash
# On build machine
./build-all.sh
scp infra/build/drumee-infra_*.deb schemas/build/drumee-schemas_*.deb \
    server/build/drumee-server-pod_*.deb ui/build/drumee-ui-pod_*.deb \
    static/build/drumee-static_*.deb user@server:/tmp/

# On target server — install in dependency order
dpkg -i /tmp/drumee-infra_*.deb
dpkg -i /tmp/drumee-schemas_*.deb
dpkg -i /tmp/drumee-static_*.deb
dpkg -i /tmp/drumee-server-pod_*.deb
dpkg -i /tmp/drumee-ui-pod_*.deb
```

### Patch-only update

```bash
schemas-patch/build.sh --manifest=auto
scp schemas-patch/build/drumee-patch_*.deb user@server:/tmp/
# On server:
dpkg -i /tmp/drumee-patch_*.deb
drumee restart   # patches are staged on install, applied at restart
```

## Testing

```bash
tests/run-all.sh             # CI suite (no private source or images needed)
tests/smoke-config.sh        # 10-assertion config rendering smoke test
tests/smoke-container.sh     # container install smoke test (needs Docker)
tests/e2e-local.sh           # full-stack E2E against tag:local images
tests/demo-stack.sh [--keep] # live compose stack from stub images (Docker + internet)
tests/wizard-install.sh      # interactive installer render-only test
tests/native/install-verify.sh        # native channel E2E (disposable Debian container)
tests/native/control-deps.sh         # inter-package dependency ordering check
tests/native/verify-debconf-bridge.sh # preseed → debconf → DRUMEE_* env, in a real .deb install
tests/native/make-seed.sh            # generate bootstrap seeds.tgz for schemas build
tests/config-parity.sh       # one fact, one place: .env vs the debconf preseed
tests/native/dns-zone-config.sh      # rendered BIND config vs. a real named-checkconf
tests/native/upgrade-reconfigure.sh  # the lifecycle of an INSTALLED box: upgrade → reconfigure → reboot
tests/native/lifecycle-remote.sh     # the same, on a REAL box over ssh (covers NM + a kernel reboot)
tests/wireguard/probe-port.sh        # endpoint probe against real kernel WireGuard
```

`run-all.sh` runs: shell syntax (`bash -n`, over `git ls-files '*.sh' 'bin/*'`
excluding `*/src/*`) → ShellCheck → renderer parse → config smoke → version drift
guard → end-to-end render → compose validity (if Docker available) → operator CLI
guards → wizard render → `native/control-deps.sh` → `config-parity.sh`.

The heavier suites are **not** in `run-all.sh` and must be run by hand:
`smoke-container.sh`, `e2e-local.sh`, `demo-stack.sh`, `native/install-verify.sh`,
`native/verify-debconf-bridge.sh`, `native/dns-zone-config.sh`,
`native/upgrade-reconfigure.sh`, `wireguard/probe-port.sh`. All of them self-`SKIP` (exit 0) when Docker or Node
is unavailable — check their output, not just the exit code.

### The lifecycle suite — `tests/native/upgrade-reconfigure.sh`

Every other native test covers a **fresh install**. Four consecutive releases shipped
bugs that only a *second* lifecycle event could reveal — 1.2.28's resolver fix undone by
a reboot, 1.2.30's zone fix unreachable on any installed host, and 1.2.31's discovery
that `dpkg-reconfigure drumee-infra` had never re-rendered anything. The install path was
well covered; the apply-a-fix-to-an-existing-box path was not covered at all.

It runs **systemd as PID 1** in a privileged disposable Trixie container (so
`docker stop` is a real systemd shutdown, which is what a hanging stop job shows up in),
installs `drumee-infra` only (every one of those bugs lived in the rendering/debconf
layer, so no schemas and no seed archive), and asserts eight things in an order that *is*
the property:

| | |
|---|---|
| A1 | a fresh install renders the configuration tree |
| A2 | an upgrade leaves it **byte-for-byte** alone — operator edits must survive apt |
| A3 | `dpkg-reconfigure` **does** re-render |
| A4 | a **planted defect is gone** afterwards — the "a shipped fix reaches an installed host" property |
| A5 | no rendered zone publishes a link-local AAAA |
| A6 | the host resolves its own domain **through `getent`**, not by querying 127.0.0.1 directly |
| A7 | a systemd reboot brings every unit back, with no stop-job timeout |
| A8 | no unreachable `reconfigure)` arm has come back in `postinst` |

Two design points worth keeping. The **upgrade is a repack**, not "install from the pool
then upgrade": the pool serves exactly one version per package, so that would be a no-op
upgrade — a test that appears to cover the path while performing no upgrade. And
`INFRA_DEB=<path>` exists so the harness can be pointed at a deliberately regressed
package: it was validated against the real pre-fix `1.2.30` artifact, where exactly A3
and A4 fail and nothing else does.

That validation found a false PASS in the harness itself — A3's baseline was taken
*before* planting the sentinel, so writing the sentinel satisfied "the tree changed" on
its own and A3 passed on the broken package while A4 failed. The baseline is taken after
planting now, and A5 excludes the sentinel address so a surviving sentinel is reported
once, by A4.

**Not covered, and it needs a real box:** NetworkManager's regeneration of
`resolv.conf` — Docker re-creates that bind mount on every container start, so
*persistence*, the exact thing 1.2.28 got wrong, cannot be observed here. Nor can a
kernel reboot. That is what the next script is for.

### The same, on a real box — `tests/native/lifecycle-remote.sh`

```bash
tests/native/lifecycle-remote.sh --host=somanos@testbox [--domain=drumee.lan] [--no-reboot]
```

Six legs (L1–L6) over ssh, covering the two properties the container cannot: **NM
regenerating `resolv.conf` at boot** and a **kernel reboot**. Needs key access and
passwordless sudo; it re-renders and reboots, so point it at a disposable box. It does
not purge, downgrade or touch data. Verified on testbox: 15/15, twice consecutively.

Four things it took to make it trustworthy, each a trap worth not re-learning:

- **`sudo for f in …` cannot work** — sudo runs a command, `for` is a shell keyword. The
  snapshot loop silently returned nothing, and two empty snapshots compare *equal*, so
  "unchanged by apt" passed on a box that had never been measured. `snapshot()` now emits
  `__EMPTY__` and L1 aborts on it rather than letting six vacuous assertions run.
- **debconf redirects maintainer-script output to stderr.** `postinst` sources
  `confmodule`, which claims stdout for the debconf protocol — so the "re-rendering"
  line arrives on stderr, and dropping stderr made the harness report the 1.2.31
  regression on a box where the re-render demonstrably happened.
- **`journalctl … | grep 'stop job'` matched sudo's own audit line** from the *previous
  run of that same check*. Scoped to `-t systemd`, since only PID 1 logs a stop-job
  timeout.
- **`systemctl is-system-running` is not a usable "booted" signal on desktop-flavoured
  Debian**: `plymouth-quit-wait.service` holds until a splash nobody will dismiss, so
  `multi-user.target` stays pending and the state is `starting` forever. L6 waits for the
  specific units instead — sshd answers at ~10s while `drumee-server-pod` finishes at
  ~14.7s, and a single sample accused a unit that was merely still activating.

`native/dns-zone-config.sh` also needs a **setup-infra checkout with its
`node_modules`** (a sibling `../setup-infra`, or `infra/src/setup-infra` after a
build, or `SETUP_INFRA_SRC=`): it renders the actual lodash templates rather
than a copy of them, so it cannot drift from what the package ships.

## CI/CD (GitHub Actions)

- **`.github/workflows/ci.yml`** — every PR/push to `main` or `feat/**`: shell lint + ShellCheck + `tests/run-all.sh`. No secrets needed.
- **`.github/workflows/release.yml`** — on `v*` tags: version coherence guard → build+push images (cosign-signed via GitHub OIDC, SBOM via syft) → build `.deb` packages → native install E2E → publish apt-stable + Pages → container smoke test. Secrets (all gated — missing = skip, not fail): `DRUMEE_SSH_KEY`, `GPG_PRIVATE_KEY`/`GPG_PASSPHRASE`, `REGISTRY_TOKEN`, `PAGES_DEPLOY_TOKEN`.

## CLIs

### drumee (PM2 wrapper)

Installed by `drumee-server-pod` to `/usr/sbin/drumee`:

```bash
drumee start|stop|restart [<service>]
drumee restart <user>/service       # restart a specific plugin service
drumee log <service>                # tail PM2 logs
```

### drumee-ctl (lifecycle operator)

Channel-aware (detects container vs. native). In `bin/drumee-ctl`:

```bash
drumee-ctl status|doctor|backup|restore <file>|upgrade [tag]|rollback
```

`doctor` checks Docker/DB/Redis/TLS health. `backup` creates timestamped tgz with DB dump + data + config. Set `DRUMEE_DIR` to point at the compose project.

### drumee-plugin

In `bin/drumee-plugin`:

```bash
drumee-plugin add <source> [--endpoint=E] [--name=N]
drumee-plugin list|remove|enable|disable <ep/name>
drumee-plugin apply <manifest.json>
```

Source can be git URL (`#ref`), local dir, or archive. Installs to `$PLUGIN_DIR/<endpoint>/<name>` (default `/srv/drumee/runtime/plugins/server`). Restarts backend after changes.

## Shared Utilities

`utils/env.sh` — exports runtime path constants (`DRUMEE_ROOT_DIR=/srv/drumee`, `DRUMEE_DATA_DIR=/data`, `DRUMEE_SERVER_HOME`, `DRUMEE_UI_HOME`, `ACME_DIR=/etc/acme`, etc.). Also re-checks `$UID`.

`utils/functions.sh` — provides:
- `bundle <base> <repo-name> <branch> [src-files] [dest-path] [npm-script]` — clone/pull from `${REPO_BASE:-git@github.com:drumee}`, `npm i`, rsync to build dir. On re-runs: `git stash` + `git pull` + `git checkout` instead of fresh clone.
- `bundle_acme <base> <dest>` — clone `acmesh-official/acme.sh` from GitHub (not Drumee)
- `get_version <base>` / `get_email <base>` — parse from `debian/changelog`
- `get_build_dir <dir>` — unconditionally wipe + recreate staging dir
- `copyToTarget <path>` — copy `.deb` to `$DEB_BUILD_TARGET` if set
- Obsolete interactive helpers (`check_version`, `check_email`, `check_build_dir`, `parse_args`) — only `admin/build.sh` still uses the `check_*` flow

## Package Directory Map

| Directory | Package | Source repo(s) | Notes |
|---|---|---|---|
| `infra/` | `drumee-infra` | `setup-infra`, `acme.sh` | Post-install renders 69 config templates |
| `schemas/` | `drumee-schemas` | `setup-schemas`, `schemas` | Requires `seeds.tgz`; post-install restores MariaDB |
| `server/` | `drumee-server-pod` | `server-team` | `Architecture: any` since 2.9.98 — **amd64 only, arm64 is not served**. Post-install applies pending patches |
| `ui/` | `drumee-ui-pod` | `ui-team` | Webpack build during package build |
| `static/` | `drumee-static` | `static` | No deps, served by nginx |
| `caddy/` | `drumee-caddy` | upstream Caddy + `caddy-dns/*` | `Architecture: any`, and the only one that actually compiles anything. Compiles the binary with `xcaddy` (local Go ≥ 1.21 or Docker); optional, install it before choosing `tls_method=caddy` |
| `schemas-patch/` | `drumee-patch` | `schemas` | Requires `--manifest` |
| `builder/` | `drumee-installer` | `setup` | Interactive installer, builds unsigned, GitLab fallback. Renamed from `drumee-bootstrap` at 1.2.7 — that name now belongs to the container entrypoints package |
| `meta/` | `drumee` | — | Metapackage, deps pinned via `make-control.sh` |
| `admin/` | — | — | Admin scripts only (uses interactive `check_*` flow) |

## Key Directories

```
config/         drumee.yaml schema + render.mjs (single source of truth)
deploy/docker/  Dockerfiles, Caddyfile, entrypoints (container channel)
scripts/        build/publish images, get-drumee, dev-up/down, apt repo, seed builder
bin/            drumee-ctl + drumee-plugin CLIs
meta/           drumee metapackage + make-control.sh
tests/          config + container + native + E2E test suites
target/         pre-built artifacts for drumee-installer
docs/           full documentation (quickstart, lifecycle, security, per-package details)
```

Generated / untracked working dirs: `out/` and `out-debs/` (renderer + build
output), `apt-repo/` (local flat repo staged by `publish-apt.sh`), `<pkg>/src/`
(trees cloned by `bundle()`), `<pkg>/build/`. Never edit under `*/src/` — it is
overwritten from the upstream repos on the next build.

## External Documentation

Full docs are in `docs/` and at [drumee.github.io/docs/package-building](https://drumee.github.io/docs/package-building/):
- Per-package deep dives: infra, schemas, server, ui, static, schemas-patch, builder
- Quickstart, first-deploy runbook, production ops, lifecycle, security
- Build pipeline, reproducible builds, release engineering, version management —
  start with `docs/build-pipeline.md` "End to end", which is the ordered path from a
  code change to a package a client can install, with the steps that silently ship
  nothing when skipped
- `docs/wireguard.md` (peer coordination), `docs/native-audit.md` (native-channel gap audit)
- `docs/debian.md` (the native bootstrap: three modes, the wan/lan/localhost
  branches, and every question in order)

`ROADMAP.md` tracks what is done vs. outstanding per phase, including known
upstream bugs and workarounds — read it before assuming a gap is an oversight.

## Distribution — invariants

Design of record: @docs/distribution.md
These rules take precedence over `ROADMAP.md` where they conflict.

Single target: container channel, Debian 13 Trixie. The native channel is
frozen — do not evolve it, do not delete it.

The `.deb` is the unit of versioning and of dependency. A container image
installs one role metapackage at an exact version and nothing else.

Forbidden, checked by `scripts/check-packaging.sh`:

- `git clone` or `REPO_BASE` in a Dockerfile — sources arrive as packages,
  never by cloning at build time.
- `FROM` without a digest — a bare tag drifts silently.
- `curl … | bash` or `| gpg --dearmor` in a Dockerfile — keyrings are
  committed under `docker/keyrings/`.
- Installing a Drumee package without `=version`.
- `apt-get update` in a `RUN` layer separate from its `install`.
- `npm install -g` — global Node modules come from `drumee-node-runtime`,
  locked by lockfile.
- Build tooling (`build-essential`, `g++`, `node-gyp`, `default-jdk`) in a
  runtime image.

Required:

- Every component version comes from `release-manifest.yaml`, resolved into
  substvars. Never write a component version anywhere else.
- Every role: `Provides: drumee-role` and `Conflicts: drumee-role`.
- Every role: `Depends: drumee-release (= ${binary:Version})`.
- Fixed UID/GID 8000, defined only in `docker/Dockerfile.base`.
- `--no-install-recommends` on every `apt-get install`.
- Migrations are **additive only**: nullable columns, new tables, new
  routines. No `DROP`, no incompatible type change in the same version.
  Cleanup waits one release.
- Maintainer scripts touch no service and no database during an image build.
  The package delivers the payload; the job container executes it.

Before declaring any task complete: `scripts/check-packaging.sh` and then
`scripts/check-versions.sh` must both pass.
