# Release engineering

## Hard rule: regenerate the schema starter kit before tagging

Drumee's per-hub sharding duplicates stored procedures into every hub/drumate
database; the `schemas` repo's `templates/factory/` dumps ("starter kit") are what
fresh installs seed from and what the container `factory` daemon fabricates new
pool databases from. If a release ships schema changes without regenerated dumps,
**new pool entities are built stale** (existing DBs still get the delta via the
manifest patch step).

So before tagging a release, on the reference host (the team flow):

```bash
ssh <reference-host>            # a live, fully-patched Drumee (e.g. drumee.in)
cd <schemas-checkout> && git pull && npm i
bin/make-templates              # re-dump every DB class into templates/factory/
git commit && git push          # commit the regenerated starter kit
```

Then build/publish images from that schemas commit. (Known upstream bug: each
`make-templates` run corrupts the 3 `disk_usage` quota triggers in `seed/yp.sql`
— a greedy DEFINER-stripping sed. Until fixed, `schemas-init` heals them on fresh
installs by applying the patch manifest, which recreates the triggers from source.)

## Coherent versioning

`release-manifest.yaml` is the authoritative version of every package in a release
set. `scripts/check-versions.sh` fails CI if any `debian/changelog` drifts from it.

```bash
# bump versions in release-manifest.yaml, then:
scripts/check-versions.sh --sync     # rewrite COMPONENT changelog top lines to match
meta/make-control.sh                 # the release train's own entry + the = pins
scripts/check-versions.sh            # verify (also runs in CI)
meta/make-control.sh --check         # verify (also runs in CI)
```

`--sync` does not write the release train's changelog — it reports `DRIFT release` and
`meta/make-control.sh` writes it. A train bump also touches **two** manifest keys,
`release:` and `components.meta`. See [version-management.md](version-management.md).

The whole path from a code change to something a client can install — including the
steps that look optional and are not — is in
[build-pipeline.md](build-pipeline.md#end-to-end-from-a-change-to-something-a-client-can-install).
`scripts/release-status.sh` shows local beside live when you want to know where a
release actually got to.

## Pipelines

- **`.github/workflows/ci.yml`** (PR/push) — runs with no secrets: shell syntax +
  ShellCheck, `render.mjs` validation, generated `docker compose config`, and the
  version drift guard.
- **`.github/workflows/release.yml`** (tag `v*`) — builds container images and
  `.deb`s, signs and publishes the APT repo, and runs the container smoke test.
  Jobs needing private source / signing keys / registry creds are gated on the
  corresponding secrets and no-op when absent (so forks run the buildable parts).

## Secrets required for a full release

| Secret | Used for |
|---|---|
| `DRUMEE_SSH_KEY` | read access to component repos (image + deb builds) |
| `GPG_PRIVATE_KEY` / `GPG_PASSPHRASE` | signing `.deb`s and the APT `Release` |
| `REGISTRY_TOKEN` | pushing images to the container registry |
| `APT_DEPLOY_*` | publishing `apt-repo/` to the hosting URL |

## Still needs a decision (see docs/reproducible-builds.md)

- Public source strategy (mirror / tarball / container-only) so non-insiders build.
- Signed artifacts: also consider `cosign` for images and an SBOM step.
