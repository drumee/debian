# Channel parity — native and container from one configuration path

Status: **proposal**. Change 1 is in progress; the rest are not started.
Scope: how a deployment's settings reach the rendered configuration, on both channels.

This document exists because the two channels currently answer the same question twice,
and the duplication has a measured cost.

## 1. The asymmetry

`config/drumee.yaml` is the single source of truth for both channels, and
`config/render.mjs` emits **two different vocabularies from it**:

| Fact | Native (`install.conf`, debconf) | Container (`.env`) |
| --- | --- | --- |
| domain | `drumee-infra/domain` | `DRUMEE_DOMAIN_NAME` |
| local mode | `local_mode` | `LOCAL_MODE` |
| admin email | `admin_email` | `ADMIN_EMAIL` |
| ACME email | `acme_email` | `ACME_EMAIL_ACCOUNT` |
| TLS | `tls_method`, `own_ssl`, `own_ssl_path` | `TLS_MODE`, `OWN_SSL`, `OWN_SSL_PATH` |
| storage | `db_dir`, `data_dir`, `backup_location`, `exchange_location` | `DRUMEE_DB_DIR`, `DRUMEE_DATA_DIR`, `BACKUP_LOCATION`, `EXCHANGE_LOCATION` |
| services | `service` | `SERVICES` |
| WireGuard | `wireguard_*` ×4 | `WIREGUARD_*` ×4 |

About fifteen facts, stated twice. Only the debconf side carries `caddy_domain`,
`caddy_dns_provider`, `acme_env_file`; only the env side carries `PUBLIC_IP4/6`, the
DB/Redis/SMTP credentials, the ports and the image tags.

Then the two channels *consume* their vocabulary differently:

- **Native**: `install.conf` → `debconf-set-selections` → `infra/debian/postinst` bridges
  every answer to a `DRUMEE_*` environment variable → `setup-infra/bin/install` →
  `infra.js`. That bridge is code, it is reviewed, and
  `tests/native/verify-debconf-bridge.sh` proves a preseeded answer reaches the
  environment `bin/install` receives.
- **Container**: `.env` → `entrypoint/infra` **hand-maps** environment variables to
  `infra.js` command-line flags → `infra.js`.

The second mapping is the problem. It is a hand-written translation of a contract that
already has a tested translator.

## 2. The evidence

Every container-side configuration defect found while building the role images came from
having that second path. Each of these was measured in a running stack, not predicted:

| Defect | Why the second path caused it |
| --- | --- |
| A BIND zone file literally named `auto` | `network.ip4: auto` is a *sentinel* meaning "detect at install time". `renderDebconf` has stripped it since it was written (`config/render.mjs`: only preseed an explicit IP); `renderEnv` emitted it verbatim, and `infra.js` reads `PUBLIC_IP4` from the environment. |
| `domain_name: "localhost"` in `drumee.json` while `drumee.sh` said the real domain | The postinst exports what `infra.js` expects; the hand-mapped path passed `--public-domain` only, and `sysEnv()` supplied the rest. |
| `argparse` exit 2 with a usage dump | `--admin-email` is not an `infra.js` option. The postinst never guessed at flags — it exports `ADMIN_EMAIL`. |
| Unhandled `ENOENT` on the DKIM key, losing the entire render | An undocumented ordering requirement the native `bin/install` already satisfies. |
| `DRUMEE_HTTP_PORT` meaning "host publish port" in compose and "the port nginx binds" to setup-infra | Two vocabularies, so one name could mean two things without anything noticing. |

The preseed path had none of these, because it is the path the native channel exercises on
every install.

## 3. Rejected: configure at image build time

The obvious way to reuse the native mechanism is to let the packages configure themselves
during `docker build` with default answers, then `dpkg-reconfigure` at deploy with the
operator's real ones. The deploy half is right and is change 2 below. The build half must
not happen, for four reasons, three of them measured:

- `getAddresses()` reads the **build container's** interfaces, so the image would carry
  `172.17.x` as the serving address. This is how the `auto` zone appeared, one step
  removed.
- The render **generates secrets** — database password, DKIM key, RSA keypair, self-signed
  certificates. Baked into a layer, every deployment from that image starts with identical
  secrets until a reconfigure overwrites them, and the originals stay in the layer history
  for good.
- Two builds of one tag would embed different detected addresses and different secrets,
  which contradicts the digest pinning of §1 and §8 in `distribution.md`.
- `infra`'s postinst deliberately **refuses** to configure on an unanswered domain,
  because an install that succeeds against a placeholder looks successful and is wrong.

So: same input, same engine, same verb — configuration **produced at deploy, never baked**.
`DRUMEE_BUILD_TIME` and §5 stay exactly as they are.

## 4. The changes

### 1. Feed the container channel the preseed, not `.env`

`infra-init` becomes: `debconf-set-selections < install.conf` →
`DEBCONF_RECONFIGURE=1 DRUMEE_CHROOT=/out dpkg-reconfigure drumee-infra`. The postinst's
existing debconf→`DRUMEE_*` bridge does the mapping; the hand-mapped flag list disappears,
and with it the class of defect in §2.

Two mechanisms make it possible, and both are small:

- `DRUMEE_CHROOT` is honoured by `setup-infra/bin/install`, which forwards `--chroot`.
  This mirrors the `DRUMEE_RECONFIGURE` → `--reconfigure=1` forwarding already there.
- `DRUMEE_CHROOT` **also means "this is a render, not a host configure"**: the postinst
  skips `ensure_nginx_stream_module`, `finish_dns`, `setup_wireguard` and `reload_nginx`
  when it is set. One signal, no new flag — rendering into a target directory and
  reconfiguring the machine you are running on are different operations, and the target
  is what distinguishes them.

`install.conf` is mounted read-only into the job, so the container channel consumes the
file the native channel installs from.

### 2. One reconfigure verb

`dpkg-reconfigure drumee-infra` natively; `drumee-ctl reconfigure` in containers, which
re-runs `infra-init` with `FORCE_RENDER=1`. The idempotence contract is already identical
by construction — `infra.js`'s own `hasExistingSettings()` governs both — so this is
naming and a CLI verb, not new behaviour.

### 3. `.env` keeps only what compose needs

Image tags, published ports, `COMPOSE_PROFILES`. Every Drumee-semantic fact moves to the
preseed. This is what stops the two vocabularies re-diverging once change 1 lands.

### 4. Finish moving the misplaced `Depends`

`drumee-server-pod` still pulls `nginx` and `redis-server`, which this role runs neither
of — the same declaration error already fixed for `drumee-schemas` and `drumee-static`.
The media stack is **not** the same case: `server-pod`'s code shells out to LibreOffice,
ffmpeg and GraphicsMagick, so moving them decides whether `drumee-media` is a separate
image or merely a separate process, and needs a change in `server-team`.

### 5. One healthcheck definition

`drumee-bootstrap` ships `healthcheck/*`; the native channel has a watchdog cron. Neither
is wired into compose. One definition, consumed by both.

## 5. Guards

Asserted, not trusted — the repository's existing pattern:

- **No role image may contain a rendered configuration tree.** `drumee.json`,
  `drumee.sh` and `sites-enabled/*` must be absent from every image. This is §5 as a
  test, and it is what would catch a future "just configure it at build time".
- **No Drumee-semantic fact may appear in both `renderEnv` and `renderDebconf`** — a diff
  of the two key sets with the compose-only names allowlisted. That is the table in §1,
  enforced.

## 6. What stays different, deliberately

Symmetry is not the goal everywhere, and forcing it would be wrong twice over.

The native channel configures a **host**: systemd units, host nginx, BIND on udp/53, ACME
renewal crontab, a WireGuard agent with `CAP_NET_ADMIN`. The container channel configures
a **volume consumed by several containers**, and delegates supervision to compose. So
`init-acme`, `init-named` and the systemd/cron half of `bin/install` have no container
analogue: `infra-init` renders and nothing else, and certificate acquisition in containers
belongs to whatever terminates TLS.

The ordering mechanisms also differ and should stay that way — a self-interest dpkg
trigger natively, `depends_on: service_completed_successfully` in compose. They are
analogous, both correct for their channel, and neither is improved by adopting the other.
