# Drumee container channel

> **The images in this directory are deprecated.** They build from source checkouts;
> the replacement installs `.deb` packages from `apt.drumee.net` into
> `docker/Dockerfile.base`. This tree still works and is still the only container path
> that does, so nothing is removed yet — but new work belongs in the package-based
> path. See [DEPRECATED.md](DEPRECATED.md) for what replaces each image, why, and what
> has to be true before this tree can go.

The recommended, easiest way to self-host Drumee: one config file, a few
containers, automatic HTTPS.

## Quick start

```bash
curl -fsSL https://get.drumee.com/install | bash       # creates ./drumee/drumee.yaml
# edit ./drumee/drumee.yaml (domain, admin_email, ...)
curl -fsSL https://get.drumee.com/install | bash       # renders + starts
```

From a checkout:

```bash
scripts/containers.sh                          # same flow, uses local files
```

## What runs

`config/render.mjs` turns `drumee.yaml` into `.env` + `docker-compose.yml`, and the
compose brings up:

| Service | Image | Role |
|---|---|---|
| `mariadb` | `mariadb:11` | Database (volume: `DRUMEE_DB_DIR`) |
| `redis` | `redis:7` | Cache / live-update channel |
| `schemas-init` | `drumee/schemas` | Run-once schema restore, then exits |
| `server-pod` | `drumee/server-pod` | REST API + WebSocket (volume: `DRUMEE_DATA_DIR`) |
| `ui-pod` | `drumee/ui-pod` | LETC frontend engine |
| `proxy` | `caddy:2` | Reverse proxy + automatic TLS |
| `jitsi`/`prosody`/`coturn` | — | Optional, via `COMPOSE_PROFILES` |

Ordering is handled by `depends_on` + healthchecks (no manual install order):
`mariadb (healthy)` → `schemas-init (completed)` → `server-pod` → `ui-pod` → `proxy`.

## Building the images

Images are built from the component repos (same source as the native packages):

```bash
docker build -f deploy/docker/Dockerfile.server \
  --build-arg REPO_BASE=git@github.com:drumee --build-arg BRANCH=preview \
  -t drumee/server-pod:<tag> deploy/docker
docker build -f deploy/docker/Dockerfile.ui \
  --build-arg REPO_BASE=... -t drumee/ui-pod:<tag> deploy/docker
```

Offline/CI builds: drop the source under `deploy/docker/.src/server-team` (or
`ui-team`) and the Dockerfile uses it instead of cloning. Publishing these images
is Phase 5 (CI/CD). Public source options: see `docs/reproducible-builds.md`.

## Verified locally

Built from local source (`scripts/build-images-local.sh`, `INSTALL_DEPS=0`):
`drumee/server-pod` (Node + pm2) and `drumee/ui-build` (real webpack bundles).
The corrected topology orchestrates correctly (`tests/demo-stack.sh`, stub app
images). server-pod boots pm2 + index.js/service.js against MariaDB/Redis.

## Resolved (from server-team/configs.js)

- **Listener ports** — confirmed: `--restPort` 24000 (service.js, `/-/*`),
  `--pushPort` 23000 (index.js, pages + WebSocket). `drumee.yaml` `ports.api`/`ports.ui`
  and the `Caddyfile` now use these.
- **`ecosystem.config.js`** — not shipped by the repo (dev-tools generates it). The
  image now ships `deploy/docker/ecosystem.config.js`, which passes the required
  `--restPort/--pushPort/--http-port/--conf-path` args (the scripts exit with
  "unrecognized arguments" without them).

## Static assets (`drumee-static`)

The app's UI styles ship in the webpack bundles (served from `/-/app/`), so the
stack is fully usable without `drumee-static`. That package only provides the
pre-boot **splash CSS, fonts, and logo** (`/-/static/*`, `/-/images/*`). It's
wired but **opt-in**:

- `Dockerfile.static` builds `drumee/static` from the `static` source repo.
- A profile-gated `static` service publishes the assets into a `static_assets`
  volume the proxy serves from `/srv/static`.
- To enable: clone the `static` repo (e.g. `~/static`), `scripts/build-images-local.sh`
  (it builds `drumee/static` when the source is present), then bring the stack up with
  `COMPOSE_PROFILES=static`.

Without it, `/-/static/*` returns 404 (harmless) and the splash uses fallback fonts.

## Remaining gates to a fully-serving real instance

- **`--conf-path`** — index.js/service.js load `<conf-path>/etc/drumee/conf.d`.
  The container must provide a populated `conf.d` (today supplied by the infra
  package). `CONF_PATH` defaults to `/`; wire conf.d provisioning into the image
  or a config volume.
- **Schema seed** — server needs the DB schema restored before it serves; this is
  the `schemas-init` + bootstrap-seed work (Phase 0.6, `make-seed.sh`). Until then
  server-pod will start but error against an empty database.
- ~~**Healthcheck**~~ — resolved: probes the page listener (`:23000/` → 200). `/-/svc/*`
  replies 401 without a session, which `curl -f` treats as failure (container was
  marked permanently unhealthy).
- **Pool replenisher** — resolved: the `factory` service (same image as
  `schemas-populate`, running `container-factory.js`) keeps the hub/drumate entity
  pool at `POOL_WATERMARK` (default 10) so signups never hit `EMPTY_FACTORY`.
