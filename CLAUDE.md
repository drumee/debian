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
├── setup-infra/         # infra install scripts + 88 lodash templates
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
  container images and `scripts/baremetal.sh` (NodeSource) install **22**, and
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

```
drumee-infra → drumee-schemas → drumee-static → drumee-server-pod → drumee-ui-pod
```

`drumee-patch` can be applied after `drumee-schemas`.

```
drumee-infra
└── drumee-schemas   (mariadb-server, mariadb-client)
    ├── drumee-static
    ├── drumee-server-pod  (nginx, redis, ffmpeg, libreoffice, graphicsmagick, …)
    └── drumee-ui-pod      (nodejs, git)
        └── drumee-patch   (mariadb-server, mariadb-client)
```

## Post-Install Behavior

- **drumee-infra**: runs `setup-infra/bin/install` (root) — renders 88 lodash templates into `/etc/drumee/`, `/etc/nginx/`, `/etc/bind/`, `/etc/prosody/`, `/etc/jitsi/`, `/etc/postfix/`, MariaDB, Coturn. Sets up SSL (ACME/self-signed/own certs), DNS (BIND9), DKIM, Prosody XMPP, PM2 ecosystem, and crontab (cert renewal, tmp cleanup, watchdog, DB/storage backups). Whether BIND9 serves the zone depends on the TLS method — `acme-dns-server` and `self-signed` do, the rest leave DNS at the operator's provider. See the DNS-01 section below.
- **drumee-schemas**: runs `setup-schemas/bin/install` (root) — restores MariaDB from seeds via `mariabackup`, creates system accounts (nobody, guest, system, admin), provisions initial hubs, imports wallpapers/tutorials, generates RSA key pair, sends welcome email with password-reset link.
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
`scripts/baremetal.sh` installs bind9 in its own transaction *before* Drumee,
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
`Architecture: any` package here, and it is **optional** — not in the metapackage,
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

`scripts/baremetal.sh` asks these questions itself (from `/dev/tty`) and
preseeds the four keys before `apt install` — along with **every other
drumee-infra setting**; see "baremetal.sh owns the interaction" below.
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

### APT repository (flat, the layout being superseded)

```bash
scripts/publish-apt.sh --debs=DIR --out=REPO_DIR [--key=EMAIL_OR_KEYID]
scripts/deploy-apt-repo.sh [--host=USER@HOST] [--repo-dir=DIR] [--domain=DOMAIN]
```

`publish-apt.sh` generates `Packages`, `Packages.gz`, `Release`, `InRelease`, `Release.gpg`, and `drumee-archive-keyring.asc` into a flat directory (no `dists/pool` tree). Requires `apt-utils` (for `apt-ftparchive`) and `gpg`.

`deploy-apt-repo.sh` rsyncs that directory to the VPS document root (default `/var/www/apt.drumee.net`), installs an nginx vhost for the domain (default `apt.drumee.net`), and reloads nginx. `--host` defaults to **`debian@apt.drumee.net`** (production) — pass it to target a staging box or mirror; it prints the resolved target before doing anything. TLS is set up separately with certbot; `APT_LOCAL_DIR` selects the local repo dir (default `apt-repo`). CI does not rely on the default: `publish-site.sh` always passes `--host="$APT_SSH_HOST"` and skips the deploy entirely when that is unset.

Clients configure:

```bash
curl -fsSL https://apt.drumee.net/drumee-archive-keyring.asc \
  | sudo tee /etc/apt/keyrings/drumee.asc >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/drumee.asc] https://apt.drumee.net/ ./" \
  | sudo tee /etc/apt/sources.list.d/drumee.list
sudo apt update && sudo apt install drumee
```

`scripts/baremetal.sh` does this automatically (`APT_URL`/`KEYRING_URL` override the defaults).

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
flow, so a release meant for those boxes must publish it. Multi-platform requires
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

Builds the flat repo once, then deploys it to two independent targets: `apt.drumee.net` over rsync/SSH (`APT_SSH_HOST`, `APT_REPO_DIR`, `APT_DOMAIN`) and the `get.drumee.com` Pages content — installers, renderer, keyring, CLIs — to `PAGES_REPO` (`GH_TOKEN`). Each target is skipped with a notice when its credential is absent; setting neither is an error. `scripts/baremetal.sh` is copied into the flat repo so `https://apt.drumee.net/baremetal.sh` serves the bootstrap without depending on Pages. It is **also** copied to the pre-rename name `install-native.sh`, so bootstrap commands already in circulation keep working — drop that line in `publish-site.sh` once the old URL is no longer referenced anywhere. Note the new URL only goes live after the next `publish-site.sh` run.

## baremetal.sh owns the interaction

`scripts/baremetal.sh` asks for **every** drumee-infra setting itself and
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
email. Full walkthrough in `docs/baremetal.md`.

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
tests/native/dns-zone-config.sh      # rendered BIND config vs. a real named-checkconf
tests/wireguard/probe-port.sh        # endpoint probe against real kernel WireGuard
```

`run-all.sh` runs: shell syntax (`bash -n`, over `git ls-files '*.sh' 'bin/*'`
excluding `*/src/*`) → ShellCheck → renderer parse → config smoke → version drift
guard → end-to-end render → compose validity (if Docker available) → operator CLI
guards → wizard render → `native/control-deps.sh`.

The heavier suites are **not** in `run-all.sh` and must be run by hand:
`smoke-container.sh`, `e2e-local.sh`, `demo-stack.sh`, `native/install-verify.sh`,
`native/verify-debconf-bridge.sh`, `native/dns-zone-config.sh`,
`wireguard/probe-port.sh`. All of them self-`SKIP` (exit 0) when Docker or Node
is unavailable — check their output, not just the exit code.

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
| `infra/` | `drumee-infra` | `setup-infra`, `acme.sh` | Post-install renders 88+ config templates |
| `schemas/` | `drumee-schemas` | `setup-schemas`, `schemas` | Requires `seeds.tgz`; post-install restores MariaDB |
| `server/` | `drumee-server-pod` | `server-team` | Post-install applies pending patches |
| `ui/` | `drumee-ui-pod` | `ui-team` | Webpack build during package build |
| `static/` | `drumee-static` | `static` | No deps, served by nginx |
| `caddy/` | `drumee-caddy` | upstream Caddy + `caddy-dns/*` | **Only `Architecture: any` package.** Compiles the binary with `xcaddy` (local Go ≥ 1.21 or Docker); optional, install it before choosing `tls_method=caddy` |
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
- Build pipeline, reproducible builds, release engineering, version management
- `docs/wireguard.md` (peer coordination), `docs/native-audit.md` (native-channel gap audit)
- `docs/baremetal.md` (the native bootstrap: three modes, the wan/lan/localhost
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
