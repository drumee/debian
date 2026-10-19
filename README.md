# Drumee — Self-Hosting & Packaging

This repository builds and deploys [**Drumee**](https://drumee.com), a sovereign
data platform (auth, storage, backend, and frontend in one system). It provides
two ways to run Drumee from source:

- **Container channel (recommended)** — a Docker Compose stack rendered from a
  single config file. Isolated, reproducible, with first-class upgrade/rollback.
- **Native Debian channel** — `.deb` packages (`apt install drumee`) that
  configure a dedicated host directly.

Both are generated from one source of truth (`config/drumee.yaml`), so a single
config produces either a `docker-compose.yml` or a debconf-preseeded `apt` install.

---

## Quick start (container, local)

With Docker and the component sources checked out alongside this repo
(`~/server-team`, `~/ui-team`, `~/schemas`, `~/setup-schemas`):

```bash
scripts/build-images-local.sh      # build the images from local source
scripts/dev-up.sh                  # render config + start the stack
```

Open **http://localhost/**; `dev-up` prints the admin login. Stop with
`scripts/dev-down.sh`. Full walkthrough: **[docs/quickstart.md](docs/quickstart.md)**.

For a real server (domain, TLS, email), follow the
**[first-deploy runbook](docs/first-deploy.md)**.

---

## Documentation

### Run & operate Drumee

| Guide | What it covers |
|---|---|
| [Quickstart](docs/quickstart.md) | Get running in ~10 minutes (container & native) |
| [Configuration](config/README.md) | `drumee.yaml` → `.env` / compose / Caddyfile / debconf preseed |
| [Container channel](deploy/docker/README.md) | Services, images, the compose stack |
| [Native channel](docs/native-channel.md) | `apt install drumee`, signed repo, unattended install |
| [Production](docs/production.md) | Published images, real domain + TLS, SMTP, day-2 ops |
| [First deploy runbook](docs/first-deploy.md) | Step-by-step first real-server deployment |
| [Lifecycle](docs/lifecycle.md) | `drumee-ctl`: status, backup, restore, upgrade, rollback |
| [Security](docs/security.md) | Secrets, TLS, hardening checklist |

### Architecture & internals

| Doc | What it covers |
|---|---|
| [Overview](docs/overview.md) | Package map, runtime layout, install order |
| [Database schema & init](docs/schema-init.md) | Per-hub sharding, seeding, schema upgrades |
| [infra-init](docs/infra-init.md) | Rendering Jitsi/mail/DNS configs from `setup-infra` |
| [Roadmap](ROADMAP.md) | Status and remaining work |

### Build & release the packages

| Doc | What it covers |
|---|---|
| [Build pipeline](docs/build-pipeline.md) | Build scripts, flags, GPG signing |
| [Reproducible builds](docs/reproducible-builds.md) | Building without insider access; seeds |
| [Release engineering](docs/release.md) | Versioning, CI/CD, the starter-kit rule |
| [Shared utilities](docs/utilities.md) | `utils/functions.sh` and `utils/env.sh` |
| [Version management](docs/version-management.md) | Changelog lifecycle, `update-changelog.sh` |
| [Deployment scripts](docs/deployment.md) | Legacy `.deb` update workflow, `drumee` CLI |

Per-package detail:
[infra](docs/package-infra.md) ·
[schemas](docs/package-schemas.md) ·
[server](docs/package-server.md) ·
[ui](docs/package-ui.md) ·
[static](docs/package-static.md) ·
[schemas-patch](docs/package-schemas-patch.md) ·
[builder](docs/package-builder.md)

---

## Architecture at a glance

**Runtime components** (each built as a package and a container image):

| Component | Role |
|---|---|
| `drumee-server-pod` | Backend — REST API (`service.js`) + page/WebSocket server (`index.js`) |
| `drumee-ui-pod` | Frontend — LETC rendering engine (built assets) |
| `drumee-schemas` | MariaDB schema, seed data, and upgrade patches |
| `drumee-static` | Static assets, fonts, localization |
| `drumee-infra` | Host infrastructure config (nginx, TLS, DNS, mail, …) |

**Container stack** (`docker compose`): `mariadb` + `redis` →
`schemas-init` → `ui-build` → `schemas-populate` → `server-pod` + `factory`,
fronted by a `caddy` proxy (TLS, static files, routing). Optional `jitsi` / `mail`
/ `dns` profiles consume configs produced by `infra-init`.

---

## Building packages

The `.deb` build factory clones each component from `git@github.com:drumee/`,
compiles it, and produces a package via `dh_make` + `dpkg-buildpackage`.

```bash
./build-all.sh                          # build infra, schemas, ui, server
server/build.sh --force=yes             # build one package
schemas-patch/build.sh --manifest=auto  # build an incremental schema patch
meta/build.sh                           # build the `drumee` metapackage
```

> **Never run build scripts as root** — they abort if `$UID` is 0.

| Directory | Package | Source repo |
|---|---|---|
| `infra/` | `drumee-infra` | `setup-infra` |
| `schemas/` | `drumee-schemas` | `setup-schemas`, `schemas` |
| `server/` | `drumee-server-pod` | `server-team` |
| `ui/` | `drumee-ui-pod` | `ui-team` |
| `static/` | `drumee-static` | `static` |
| `schemas-patch/` | `drumee-patch` | `schemas` |
| `builder/` | `drumee-bootstrap` | `setup` |
| `meta/` | `drumee` | — (metapackage) |

See [docs/build-pipeline.md](docs/build-pipeline.md) for flags, signing, and the
full package map.

---

## Repository layout

```
config/        drumee.yaml schema + render.mjs (single source of truth)
deploy/docker/ Dockerfiles, Caddyfile, entrypoints (container channel)
scripts/       build/publish images, get-drumee, dev-up/down, apt repo, version check
bin/           drumee-ctl (lifecycle operator CLI)
meta/          drumee metapackage
tests/         config + container + end-to-end test suites
docs/          documentation (see above)
<component>/   per-package build dir (infra, schemas, server, ui, static, …)
```

## License

AGPL-3.0 — see [LICENSE](LICENSE).
