# Implementation brief — Drumee distribution

Give this to the agent **one increment at a time**. Each increment is
independently verifiable and ends with a command that proves it works. Do not
chain them: get increment N validated before starting N+1.

Normative reference: `docs/distribution.md`. Invariants: `CLAUDE.md`.
Gate: `scripts/check-packaging.sh` must pass at the end of every increment.

---

## Increment 0 — set up the context

No implementation. Put the documents in place so every later session shares
the same design.

- Add `docs/distribution.md`.
- Merge the "Distribution — invariants" block into `CLAUDE.md`.
- Add `scripts/check-packaging.sh`, make it executable, wire it into
  `.github/workflows/ci.yml`.
- Record in `ROADMAP.md` that phase 3 (native channel) and part of phase 2 are
  superseded by this design, without deleting the history.

Acceptance:
```bash
scripts/check-packaging.sh   # fails at first — expected, and intentional
```
The initial failure is the measure of the debt: it lists exactly what the
following increments must fix. Record it in the PR.

---

## Increment 1 — local APT repository (do this first)

Without it the agent can test nothing: no image can install
`drumee-role-app` if nothing publishes it. `apt.drumee.net` does not exist
yet, so stand up a local repository first.

- `scripts/apt-repo-local.sh`: creates a reprepro repository under
  `.apt-local/`, with suites `trixie`, `trixie-beta`, `trixie-edge`,
  components `main` and `enterprise`, architectures `amd64`, `arm64`, `all`.
- Test key generated locally, never committed; update `.gitignore`.
- The repository is consumable over a `file://` URI for local builds and
  served by a throwaway nginx container for image tests.

Acceptance:
```bash
scripts/apt-repo-local.sh init
scripts/apt-repo-local.sh include ./out-debs/*.deb
apt-ftparchive --version && reprepro -b .apt-local list trixie
```

---

## Increment 2 — the drumee-roles source package

The supplied files are a skeleton to integrate, not to copy verbatim: adapt
the real package names and check the open questions in §9 of
`docs/distribution.md`.

- `roles/debian/{control,rules,changelog,gen-substvars.py}`.
- `release-manifest.yaml` extended to the shape `gen-substvars.py` expects.
- `roles/debian/drumee-release.install` for `/usr/share/drumee/release`.

Acceptance — all three must pass:
```bash
cd roles && dpkg-buildpackage -us -uc -b
lintian ../drumee-role-*.deb ../drumee-release_*.deb
dpkg-deb -f ../drumee-role-app_*.deb Depends | grep -q '2\.9\.45'  # substvars resolved
```

**The test that proves the mechanism** — it must fail, and that is the point:
```bash
# 1. two roles at once: refused by Conflicts drumee-role
apt-get install -s drumee-role-app drumee-role-web
# 2. two release trains mixed: refused by the drumee-release anchor
apt-get install -s drumee-role-app=2.9.45-1~trixie1 \
                   drumee-role-web=2.9.44-1~trixie1
```
If either command succeeds, the increment is not done.

---

## Increment 3 — the two missing component packages

- `drumee-node-runtime`: pm2, pm2-logrotate, shelljs, jsonfile,
  readline-sync, lodash, node-pre-gyp, locked by a committed
  `package-lock.json`, installed with `npm ci` in CI and then packaged.
  Replaces the unpinned `npm install -g`.
- `drumee-bootstrap`: what `COPY ./opt/drumee/init.d/*` used to inject outside
  any versioning, plus the per-role entrypoints and healthchecks.

Acceptance:
```bash
dpkg -L drumee-node-runtime | grep -q pm2
dpkg -L drumee-bootstrap | grep -q '/usr/lib/drumee/entrypoint'
```

---

## Increment 4 — base image

- `docker/Dockerfile.base` (supplied), with the real `debian:trixie-slim`
  digest filled in.
- `docker/keyrings/`: keyrings committed, never fetched at build time.

Acceptance:
```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -f docker/Dockerfile.base -t drumee-base:test .
docker run --rm drumee-base:test id drumee | grep -q 'uid=8000'
docker run --rm drumee-base:test sh -c '/usr/sbin/policy-rc.d; echo $?' | grep -q 101
```

---

## Increment 5 — one role image, then the rest

Start with `drumee-role-web` alone: it has the fewest external dependencies,
so it isolates problems in the chain best. Only generalise to the other six
once that one is green.

Acceptance per role:
```bash
docker build -f docker/Dockerfile.web --build-arg DRUMEE_RELEASE=... -t drumee-web:test .
docker run --rm drumee-web:test dpkg -l | grep -c '^ii  drumee-'
# No build tooling survived:
docker run --rm drumee-web:test sh -c 'command -v gcc g++ node-gyp' && exit 1 || true
```

---

## Increment 6 — compose and ordering

- Render compose from `drumee.yaml`: seven services, shared `drumee_data` and
  `drumee_conf` volumes.
- `infra-init` then `schemas-init` then `migrate` with `restart: "no"` and
  `depends_on: condition: service_completed_successfully` before `drumee-app`.
- `schema_migrations` table; `drumee-app` refuses to start when the schema
  version in the database is below what the code requires.

Acceptance:
```bash
tests/smoke-container.sh          # must serve real Drumee HTML
# A failing migration must stop the stack from coming up:
DRUMEE_FORCE_MIGRATION_FAILURE=1 docker compose up -d ; echo $?   # non-zero
```

---

## Increment 7 — publication and signing

- `reprepro` replaces `apt-ftparchive` in `publish-apt.sh`; channel promotion
  by `reprepro copy`, never by rebuilding.
- `Valid-Until` at 30 days, with periodic re-signing.
- Project key, master offline, signing subkey in CI.
- `cosign` keyless via GitHub OIDC, plus SBOM on the images.

Acceptance:
```bash
reprepro -b .apt-local copy trixie trixie-beta drumee-roles
# the promoted artifact is bit-for-bit identical:
sha256sum .apt-local/pool/main/d/drumee-roles/*.deb   # unchanged after copy
cosign verify --certificate-identity-regexp '.*' ghcr.io/drumee/drumee-web:2.9.45
```

---

## Rules of engagement for the agent

- Do not touch the native channel: it is frozen, not dead.
- Never write a component version anywhere but `release-manifest.yaml`.
- A schema migration containing a `DROP` or an incompatible type change must
  be rejected, not worked around.
- If an open question from §9 of `docs/distribution.md` blocks an increment:
  stop and ask, do not decide alone. In particular `Architecture: all` on
  `drumee-server-pod`, which breaks arm64 silently if the package bundles
  native Node modules.
