# Quickstart — self-host Drumee in ~10 minutes

Two ways to run Drumee. Most people want the **container channel**.

---

## Option A — Containers (recommended)

**Requirements:** a Linux host. That's it — the installer can install Docker for
you, and you don't need a domain (it offers automatic HTTPS by IP, or local-only).

**One command. Answer 3–4 questions. Done:**

```bash
curl -fsSL https://get.drumee.com/install | bash
```

The installer asks:

1. **A name** for the instance.
2. **How people will reach it** — pick one:
   - **a domain** you own (real HTTPS via Let's Encrypt), or
   - **this server's IP, no domain** (automatic HTTPS via `sslip.io`), or
   - **local / testing** (`http://localhost`, no HTTPS).
3. **Admin email** (your login).
4. **Admin password** (leave blank to auto-generate — printed at the end).

It then generates all secrets, renders the stack, starts it, waits until it's
healthy, and prints your **URL + login**. Nothing to hand-edit; re-running is safe.

> **Where do the images come from?** The installer pulls prebuilt images from a
> public registry (default `ghcr.io/drumee`) — you don't build anything. If
> locally-built `drumee/*:local` images are present it uses those instead, and if
> neither is available but the component sources are checked out, it offers to
> build them. Override the source with `IMAGE_REGISTRY=` / `SERVER_TAG=`.
> *(Maintainers publish images once per release — see [production.md](production.md).)*

> No prompts (automation)? Preset the answers, e.g.:
> `ACCESS_MODE=domain DRUMEE_DOMAIN=cloud.example.com ADMIN_EMAIL=you@example.com ASSUME_YES=1 curl -fsSL https://get.drumee.com/install | bash`

Manage it afterwards:

```bash
cd drumee
DRUMEE_DIR=. drumee-ctl status     # service health
DRUMEE_DIR=. drumee-ctl doctor     # deeper checks
```

**From a checkout** (no curl-to-bash) — same wizard:

```bash
scripts/containers.sh
```

---

## Option A2 — Run locally from source (developer, validated on WSL)

When the component repos are checked out next to this one (`~/server-team`,
`~/ui-team`, `~/schemas`, `~/setup-schemas`):

```bash
scripts/build-images-local.sh     # build server-pod, ui-build, schemas, schemas-populate (tag: local)
scripts/dev-up.sh                 # render + start the stack, keep it running
# wait ~60-90s for schemas-init / ui-build / schemas-populate, then:
```

Open **http://localhost/** in your browser. The first-run admin gets a
password-reset link printed by the populate step:

```bash
docker compose -p drumee-dev logs schemas-populate | grep "Init link"
# open the link, but with http:// (the dev stack is HTTP):
#   http://localhost/-/#/welcome/reset/<id>/<token>
```

Manage it:

```bash
docker compose -p drumee-dev ps                 # status
docker compose -p drumee-dev logs -f server-pod # logs
scripts/dev-down.sh                             # stop + remove (KEEP_DATA=1 to keep DB)
```

Notes: the dev stack uses an HTTP-only proxy and runs Redis without auth (the app
has a secondary Redis client that doesn't authenticate yet). For TLS/production use
the container channel above.

---

> **Running for real users (published images, real domain + TLS, SMTP)?**
> See [docs/production.md](production.md).

## Option B — Native Debian/Ubuntu

**Requirements:** a dedicated Debian/Ubuntu host (it configures the whole machine).

```bash
# Interactive
curl -fsSL https://apt.drumee.net/debian.sh | sudo bash

# Unattended — render answers from drumee.yaml first
node config/render.mjs debconf --config config/drumee.yaml --out install.conf
sudo PRESEED=install.conf bash scripts/debian.sh
```

`apt install drumee` pulls the full runtime. Manage with `drumee` (processes) and
`drumee-ctl` (backup/upgrade/rollback).

---

## Day-2

```bash
drumee-ctl backup            # before changes
drumee-ctl upgrade           # backup + pull/install + restart
drumee-ctl rollback          # restore last pre-upgrade snapshot
```

## Troubleshooting

| Symptom | Try |
|---|---|
| TLS not issued | DNS must resolve to this host; ports 80/443 reachable; check `drumee-ctl doctor` |
| DB errors on first boot | `schemas-init` runs once — `docker compose logs schemas-init` |
| Service unhealthy | `drumee-ctl status`, then `docker compose logs <service>` |
| Need to change config | edit `drumee.yaml`, re-render, `docker compose up -d` (or `drumee-ctl upgrade`) |

See also: [container channel](../deploy/docker/README.md) ·
[native channel](native-channel.md) · [lifecycle](lifecycle.md) ·
[security](security.md).
