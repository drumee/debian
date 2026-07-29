# Native postinst audit — does `apt install drumee` reach a serving state?

Audit of the native install path (`setup-infra/bin/install`, `setup-schemas/bin/install`,
the `.deb` maintainer scripts) against the runtime contract we reverse-engineered for
the container channel.

## ✅ VALIDATED END-TO-END (real `.deb` install, Debian 12)

All four packages were **built from source on WSL** (`infra`, `schemas`, `server-pod`,
`ui-pod`) and **installed on a clean Debian 12** (disposable privileged container). The
result: **MariaDB restored from seed → factory pool stocked (20) + accounts created →
`pm2` running `index.js`/`service.js` → nginx → the real Drumee UI in a browser at
`http://localhost/`, with a working admin login** (`yp.login` → `status: active`).

So native is no longer theoretical — it builds, installs, serves, and authenticates.
Getting there surfaced several real gaps that **only an end-to-end install reveals**;
they're listed below with status. The ones still marked *(needs packaging)* are what
stands between "works after a few manual nudges" and a fully turnkey `apt install drumee`.

### Gaps found during the real install

| # | Gap | Status |
|---|---|---|
| Node 18 too old (ESM `mariadb`) | install Node 20 (NodeSource); `Depends: nodejs (>= 20)`; drop Debian `npm` | ✅ fixed (committed) |
| `args.drumee_root` undefined → infra.js crash | use `data.drumee_root` at the use-sites | ✅ fixed + pushed to `setup-infra` |
| `mariadb-backup` not a dependency → seed restore silently no-op | add to `drumee-schemas` `Depends` | ✅ fixed (committed) |
| factory pool not stocked by `populate.js` → `EMPTY_FACTORY` | `stockFactory()` before account creation | ✅ fixed + pushed to `setup-schemas`; genesis templates packaged |
| debconf→env bridge missing (metapackage path) | templates + config + postinst export | ✅ fixed + verified |
| preseeded `network.ip4/ip6` dropped by the bridge → `infra.js` skipped the whole public branch (nginx `01-public.conf`, BIND public/reverse zones, postfix/opendkim) | postinst exports `PUBLIC_IP4`/`PUBLIC_IP6` from `ip4`/`public_ip4` | ✅ fixed (committed) |
| `ip4`/`ip6` never *asked* interactively — `config` has no `db_input` and nothing `db_subst`s `${__IP4_LIST__}` (only the wizard's `prompt.sh` does) | add detection + prompts to `infra/debian/config`, or drop the templates and document `network.ip4` as wizard-only | ⏳ open |
| nginx `stream{}` (turn-relay) without the stream module → config invalid | `drumee-infra` `Depends: libnginx-mod-stream` | ✅ fixed (committed) |
| pm2 not installed → `/etc/init.d/drumee` can't launch the app | `drumee-server-pod` postinst `npm i -g pm2` | ✅ fixed (committed) |
| `ecosystem.config.js` not generated → init.d has nothing to start | `main()` never called `writeEcoSystem()` | ✅ fixed + pushed to `setup-infra` (verified via chroot render) |
| dpkg **conffile prompt** on infra-rendered MariaDB configs | `baremetal.sh` uses `--force-confold` | ✅ fixed (committed) |
| `server/var/lib/drumee/postinstall/patch.sh` missing | ship a no-op placeholder (`dh_install` wants `files/var/*`) | ✅ fixed (committed) |
| ~~`--conf-path` doubled~~ | **non-issue** — the generated ecosystem passes only `--pushPort/--restPort`; the doubling was a manual-invocation artifact, not a packaging bug | n/a |
| domain `local` awkward for local browser testing | prefer `domain: localhost` for local installs | ⏳ docs / installer default |
| `drumee-static` has no source to build → `/-/static/*` 404 (cosmetic) | obtain/build the `static` repo | ⏳ needs source |

**Net after these fixes:** every blocking gap is closed — a fresh `apt install drumee`
(via `baremetal.sh`, which adds Node 20 + `--force-confold`; packages pull
`mariadb-backup`/`libnginx-mod-stream`/`nodejs>=20` and install pm2; infra generates
the ecosystem; populate stocks the pool) should reach a serving instance **without
manual steps**. Only `domain: localhost` default and `drumee-static` remain (cosmetic /
needs source). The last thing to do is re-run a clean single-pass `apt install drumee`
on a fresh Debian VM to confirm zero-touch.

## Headline (original source audit)

The native installer already produces **most** of the runtime contract — unsurprising,
since the container entrypoints were reverse-engineered *from* it. The process model is
also fully wired (systemd → init.d → pm2). The blockers are a **missing debconf→env
bridge on the metapackage path** and a **factory-pool/seed assumption**, plus the
expected need for a real host to validate.

## Already handled by the native install (✅)

| Contract item | Where | Note |
|---|---|---|
| `credential/db.json` | `infra.js:617` | `{host,user,password}`, password generated; socket auto-detected |
| `credential/email.json` | `infra.js:623` | **nested `auth:{user,pass}`** (matches the shape our container needed) |
| `credential/redis.json` | `redis.json.tpl` | see Redis risk below |
| `credential/crypto/*.pem` (RSA) | `setup-schemas populate.js:71` | `generateKeysPair()` after DB populate |
| `conf.d/{drumee,myDrumee,exchange,conference}.json` | `infra.js:539` | the `--conf-path` content we had to hand-write in containers |
| `drumee.sh` / `drumee.json` | `infra.js:454`, `drumee.sh.tpl` | env + config |
| nginx routing | `routes/main.conf.tpl:50` | `/-/svc`→24000, ws→23000, static `/-/app` `/-/api` `/-/plugins` aliased |
| system accounts (nobody/guest/system/admin) | `organization.js:191-391` | via `drumate_create` in `populate.js` |
| **process start** | `server/etc/init.d/drumee` + `drumee-server-pod.service` | systemd unit (`dh_installsystemd`) → `/etc/init.d/drumee start` → `pm2 start ecosystem.config.js` (index.js + service.js + factory). **Starts on install and on boot.** |
| schema **triggers** | `setup-schemas/bin/install:44` | restored via `mariabackup --copy-back` (**physical** restore) — so it **avoids** the `bin/make-templates` greedy-sed trigger corruption that bit our SQL-dump container path. ✅ |

## Real gaps / risks (native-specific, actionable)

### 1. debconf → env bridge missing on the metapackage path (HIGH) — ✅ FIXED & VERIFIED

> **Fixed:** `drumee-infra` now ships `debian/templates` (registers the
> `drumee-infra/*` questions), `debian/config` (prompts; preseed answers used
> as-is), and a `debian/postinst` that `db_get`s every answer and `export`s the
> matching `DRUMEE_*` var (same mapping as the bootstrap wizard) before running
> `setup-infra/bin/install` — and aborts with a clear message if the domain is
> empty instead of silently failing. Guarded by `tests/native/control-deps.sh`.
> Still needs a Debian VM to confirm the end-to-end install. Original analysis:

`infra.js` reads the domain/admin/paths from **environment variables**
(`process.env.DRUMEE_DOMAIN_NAME`, …; `infra.js:25-42`). With no domain it
**silently `exit(0)`s** (`infra.js:349`) → `drumee.sh` is never written → `bin/install`
prints "Setup has failed" and aborts.

- The **`drumee-bootstrap` wizard** bridges this correctly: `builder/.../menu/install.sh`
  does `. confmodule` → `db_get drumee-infra/domain` → `echo export DRUMEE_DOMAIN_NAME=… >> env`.
- The **metapackage path does not**: `infra/debian/postinst` just calls
  `setup-infra/bin/install` with **no `db_get` / no `export`**. So `apt install drumee`
  with a preseed (what `scripts/baremetal.sh` + `render.mjs debconf` target) runs
  `infra.js` with empty env → silent failure.

**Fix:** have `infra/debian/postinst` read the `drumee-infra/*` debconf answers and
export them as `DRUMEE_*` before calling `bin/install` (mirror `builder/install.sh`), or
unify the metapackage path onto the bootstrap wizard. *This is the #1 thing blocking a
working `apt install drumee` + preseed.* *(verify on VM)*

### 2. Factory pool not stocked by populate.js (MEDIUM) — guard added; root fix is upstream

**Root cause (confirmed in source).** `setup-schemas/populate.js start()` goes straight
from `org.populate()` to `org.createNobody()/createGuest()/createSystemUser()/createAdmin()`.
Those create accounts via `drumate_create` → `pickupEntity()`, which **consumes** entities
from `yp.entity WHERE area='pool' AND pool_state='clean'`. `populate.js` never **stocks**
that pool. So the first-run accounts only succeed if the pool is already filled — which on
native happens **only if the `mariabackup` seed (`seeds.tgz`) was built from a system with a
stocked pool**. A data-free seed → empty pool → the system accounts fail with
`EMPTY_FACTORY`, and the install is silently half-broken. (The runtime `factory` pm2 daemon
*does* maintain the pool, but it only starts with the `server` package, *after* schemas — too
late for `populate.js`.)

The container channel hit exactly this and fixed it: `deploy/docker/container-populate.js`
calls **`stockFactory()` between `populate()` and `createNobody()`** — it tops the
`hub`/`drumate` pools up to `POOL_COUNT` from the genesis templates
(`schemas/templates/factory/{hub,drumate}.sql`) using `create_entity` (idempotent via
`pool_free`).

**What was done here (in-repo, no VM needed):** `schemas/debian/postinst` now runs a
**detection guard** after `bin/install` — it checks `yp.entity(area='pool')` and the
`system` account, and if either is empty it fails *loudly* with the remedy, instead of
leaving a silently-broken install.

**The root fix (upstream `setup-schemas`, needs a VM to validate):** add a `stockFactory`
step to `populate.js`, mirroring the validated `container-populate.js`:

```js
// populate.js start(), after org.populate():
await stockFactory(org.yp);      // <-- add this, before org.createNobody()
```

where `stockFactory` tops each pool to `POOL_COUNT` via `create_entity`, passing the genesis
template path (`schemas/templates/factory/<type>.sql`) as `script`. **Open sub-item:** those
genesis templates must be packaged onto the native host (the `drumee-schemas` build does not
currently ship `templates/factory/`), or `stockFactory` must point at wherever they land.
Wallpaper/tutorial import additionally needs network (`content.drumee.com`, `drumee.com`)
and silently skips if unreachable — cosmetic, not blocking. *(verify on VM)*

### 3. Redis auth posture undefined (LOW)
No password is generated for Redis; `redis.json`'s `redisAuth` is effectively empty →
**no-auth** (matches our container finding). Fine if Redis binds to localhost/the data
network; confirm it isn't exposed. *(verify on VM)*

### 4. Needs a real host (validation-only, not a code gap)
`service mariadb start/stop`, `prosody`/`prosodyctl`, `crontab`, the `www-data` user, and
`mariadb_config --socket` detection all assume a real Debian host with systemd. A plain
(non-systemd) container can't validate the install end-to-end — a disposable **Debian 12
VM** is required.

### 5. Debian 12 ships Node 18 — too old for the runtime deps (HIGH) — found by end-to-end build+install

Confirmed by actually building all four `.deb`s on WSL and installing them in a
disposable `debian:12` container (`tests/native/make-seed.sh` +
`tests/native/install-verify.sh`). The install gets a **long** way:

- builds end-to-end (HTTPS clone + `@drumee` npm + webpack + signing) → 4 `.deb`s;
- `infra.js` runs with the debconf-bridged env and writes **every** config + credential
  (`db.json`, `email.json`, `redis.json`, `crypto/public.pem`, `drumee.json`, `conf.d/*`,
  `ecosystem.json`) — so **gap #1 is validated live**;
- the generated seed restores and MariaDB starts.

Then `infra.js` (and `populate.js`) **crash at the DB-connect step**:

```
Error [ERR_REQUIRE_ESM]: require() of ES Module .../node_modules/mariadb/promise.js
from .../@drumee/server-essentials/lib/mariadb.js not supported.   Node.js v18.20.4
```

`mariadb` npm is **3.5.2** (ESM-only, `"type":"module"`), pulled transitively via
`@drumee/server-essentials`. `require('mariadb')` works on **Node ≥20.19** (which
supports `require(ESM)`) — both channels now ship **Node 22 (current LTS)** — but
**fails on Debian 12's Node 18**, which the packages get via `Depends: nodejs, npm`.
infra failing cascades to schemas.

**Fix (Option A, applied):** make the native install provide **Node 22.x (NodeSource)** —
`scripts/baremetal.sh` adds the NodeSource repo before `apt install`, and the
component `debian/control` files `Depends: nodejs (>= 20)` and drop the Debian `npm`
dep (NodeSource's nodejs bundles npm and Debian's `npm` conflicts with it). This mirrors
the container channel's `node:22` base. Without Node ≥20, `apt` now fails with a clear
unmet-dependency message instead of the cryptic ESM crash mid-postinst. (Node 22, not 20,
because the 20.x line's older point releases carried CVEs; 22 is the current LTS.)

**Confirmed (original ≥20 validation):** on `node:20-slim` (v20.20.2), `require('mariadb')`
of the exact ESM `mariadb@3.5.2` that crashes on Node 18 returns OK — establishing the
≥20 floor that Node 22 also satisfies. The only thing not yet run start-to-finish is a single clean full-stack
install-to-serving pass; it's gated on container apt pulling the heavy deps
(MariaDB + LibreOffice + ffmpeg + …) over a slow/flaky network, not on any code issue.

## Observation (not a gap)

The native pm2 ecosystem runs **`index.js` in fork mode (1 instance)** but
**`service.js` in `cluster_mode` (2–4 instances)** (`infra.js:198-223`). Our *container*
ran both in fork because `cluster_mode` broke the apps' `process.argv` parsing under
`pm2-runtime`. Native's cluster config is the canonical production setup; the divergence
only matters if someone reuses the native ecosystem inside a `pm2-runtime` container.

## Bottom line

Native is closer than it looks: credentials, conf.d, nginx, accounts, RSA, and process
start are all wired, and it dodges the trigger-corruption bug. To get `apt install drumee`
to actually serve, fix the **debconf→env bridge (#1)** and confirm the **seed's factory
pool (#2)**, then validate on a Debian VM. The packaging/ordering is already correct and
tested (`tests/native/control-deps.sh`).
