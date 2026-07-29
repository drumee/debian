# Drumee Self-Host Roadmap

> **Partly superseded — read `docs/distribution.md` first.** That document is the
> design of record for distribution and wins wherever it contradicts this file.
> Nothing below is deleted: it records how the current state was reached, and the
> items still marked `[ ]` outside the superseded sections remain valid.
>
> | Section | Status under the new design |
> |---|---|
> | Phase 2 — container channel | **partly superseded.** The compose stack, profiles and one-line bootstrap stand. What changes: images no longer `git clone` at build time, `ui-build` disappears (the bundles ship inside `drumee-ui-pod`), and the monolith splits into seven role containers. |
> | Phase 3 — native Debian channel | **frozen.** Neither removed nor maintained for the duration of the transition. Do not evolve it. |
> | Phase 5 — CI/CD | still valid, extended: `reprepro` replaces `apt-ftparchive`, channels become suites promoted by copy. |
>
> The invariants are summarised in `CLAUDE.md` and **enforced** by
> `scripts/check-packaging.sh`, which runs in CI and is expected to fail until the
> increments in `AGENT-BRIEF.md` land.

Goal: turn this build factory into a **SOTA, easy-to-self-host** product with **two
supported channels** — Docker Compose (default, easy) and native Debian (advanced).

## Guiding principle

> **Single source of truth, two renderers.** One config schema, one build factory,
> one set of install logic — rendered into either a `docker-compose.yml`+`.env` or a
> native `apt` install. Never two parallel implementations of the same decision.

This is what keeps "two channels" from meaning "double the bugs."

## Phases

### Phase 0 — Foundation & cleanup (prerequisite)
- [x] **0.1** Remove committed `dpkg-buildpackage` artifacts from all `debian/` dirs; add `.gitignore`.
- [x] **0.2** Fix `builder/debian/control` dh_make placeholders.
- [x] **0.3** Fix debconf template mismatch (`drumee-test/*` → `drumee-infra/*`).
- [x] **0.4** Unify the two `utils/` trees (parameterized `REPO_BASE_DEFAULT` + `NPM_AUDIT_FIX`).
- [ ] **0.5** Resolve `infra/` vs `builder/` overlap (both build `drumee-infra`).
- [ ] **0.6** Reproducible builds without insider access (public source path + minimal bootstrap seed).

### Phase 1 — Config single-source-of-truth
- [x] One declarative `drumee.yaml` schema (`config/drumee.schema.json`).
- [x] A renderer (`config/render.mjs`) emitting `.env`, `docker-compose.yml`, and `install.conf` (debconf preseed).
- [x] Config validation before any artifact is emitted (required fields, enums, conditional TLS rules, secret generation).
- [x] Unattended native install documented (`debconf-set-selections` + noninteractive frontend).
- [ ] Follow-up (external `setup` repo): wizard validation loops should `break` under noninteractive frontend.

### Phase 2 — Container channel (flagship easy path)
> Partly superseded by `docs/distribution.md` §1–§2: packages become the unit of
> versioning, `ui-build` goes away, seven role containers replace the monolith.
- [x] `Dockerfile.server` / `Dockerfile.ui` (multi-stage, source via `REPO_BASE` build-arg).
- [x] Generated `docker-compose.yml` driven by `.env`; named volumes; internal network.
- [x] Schema run-once init container; `depends_on` + healthchecks replace dpkg ordering.
- [x] Automatic TLS via Caddy. Optional Jitsi/Prosody/Coturn via compose `profiles:`.
- [x] One-line bootstrap `scripts/containers.sh` (`curl … | bash`).
- [x] **Real images build from local source** (`scripts/build-images-local.sh`): server-pod (Node+pm2) + ui-build (real webpack bundles), no registry needed.
- [x] Topology corrected to match source (UI = build artifact via shared volume; proxy → server-pod). Verified live with `tests/demo-stack.sh`.
- [x] Listener ports + ecosystem args resolved from `configs.js`: `--restPort` 24000, `--pushPort` 23000; `ecosystem.config.js` passes the required args.
- [x] **Serving validated end-to-end on WSL** from local source: `host → Caddy → server-pod`
  returns the real Drumee HTML (`GET / → 200`, `GET /-/svc/* → 401`). Fixes that got it serving:
  pm2 `exec_mode: fork` (apps parse argv), conf.d provisioning in the entrypoint, credential dir
  `/etc/drumee/credential`, and Redis defaulting to no-auth (internal network).

### Phase 3 — Native Debian channel (advanced)
> **Frozen** by `docs/distribution.md`: the container channel on Trixie is the
> single target for now. Kept working, not extended.
- [x] `drumee` metapackage (`meta/`) pulling the full runtime.
- [x] Signed APT repo publisher (`scripts/publish-apt.sh`) + native bootstrap (`scripts/baremetal.sh`) with unattended preseed.
- [ ] Repo hosting (`apt.drumee.net`, nginx on VPS via `scripts/deploy-apt-repo.sh`) + project signing key (your infra).
- [ ] Explicit inter-package `Depends` for robust configure ordering.

### Phase 4 — Lifecycle CLI (both channels)
- [x] `bin/drumee-ctl` channel-aware: `status`, `doctor`, `backup`, `restore`, `upgrade`, `rollback`.
- [ ] Physical (`mariabackup`) backups for large instances; auto version revert on rollback.

### Phase 5 — CI/CD & release engineering
- [x] `ci.yml` (no secrets): shell lint, render + compose validation, version drift guard.
- [x] `release.yml` (tag): build images + debs, sign, publish APT, smoke test (secret-gated).
- [x] Coherent release manifest (`release-manifest.yaml`) + `scripts/check-versions.sh`.
- [ ] `cosign` image signing + SBOM.

### Phase 6 — Tests, security, docs
- [x] `tests/smoke-config.sh` (10 assertions) + `tests/smoke-container.sh` (config→compose→live).
- [x] Secret generation at render; `0600` perms; threat model (`docs/security.md`).
- [x] 10-minute quickstart + lifecycle/troubleshooting runbooks (`docs/quickstart.md`).

## Sequencing

`0 → 1` are non-negotiable prerequisites. Then `2` (containers) to first-class quality,
then `3` (native) reusing the same config layer, then `4–6` to harden into a product
strangers can trust. Build Phase 1 **first** so the two channels stay thin adapters over
shared logic.

## Remaining external decisions / inputs

These are blocked on your infrastructure or internal knowledge, not on more code:
- Public source strategy (mirror / tarball / container-only) — `docs/reproducible-builds.md`.
- APT repo hosting + project GPG signing key.
- `--conf-path` provisioning for containers (a populated `etc/drumee/conf.d`, today produced by the infra package).

**Service-config parity (from analyzing `setup-infra` — see `docs/infra-init.md`):**
- [x] Feasibility validated: `infra.js --chroot` renders the full 39-file native config
  tree (bind/postfix/opendkim/nginx/mysql/conf.d) from env vars — no host writes.
- [ ] Implement the `infra-init` run-once service + adapter (jitsi/mail/dns profiles).
- [ ] Upstream: `args.drumee_root` crash (1-line fix) + `exchange.json.tpl` key drift.

**Schema/DB (from analyzing the `schemas` repo — see `docs/schema-init.md`):**
- [x] **`schemas-init` built + validated**: `Dockerfile.schemas` + `schemas-init.sh` create
  `yp/utils/mailserver/template/trash` from `templates/factory/`, configure the domain, and
  create the privileged app user. Verified: yp = 130 tables + 645 routines, app user can
  `CREATE DATABASE`.
- [x] Container DB model fixed: known `MARIADB_ROOT_PASSWORD`, app user granted broadly
  (runtime `CREATE DATABASE`), scoped `MARIADB_USER`/`MARIADB_DATABASE` removed.
- [x] Schema DDL source resolved: `templates/factory/` (data-free) + `bin/build-seeds`.
- [x] **setup-schemas parity — validated end-to-end.** `schemas-populate` (Dockerfile.populate +
  populate-entrypoint + container-populate.js, reusing setup-schemas' real lib over server-pod's
  node_modules) stocks the entity pool from the genesis templates and creates the system accounts
  (nobody/guest/system) + RSA keypair. Verified live: accounts created, EMPTY_FACTORY resolved,
  public.pem generated. Wired into compose as a run-once service + shared `drumee_cred` volume.
- [ ] Optional: admin account (CREATE_ADMIN=1), wallpapers/tutorials (network), welcome email.
- [ ] Upstream bug: `schemas/bin/make-templates` line 95 greedy sed corrupts yp triggers
  (worked around with `--force`).

Resolved this session from the real source: listener ports (24000/23000), the
ecosystem arg contract, and that both app images build & boot.
