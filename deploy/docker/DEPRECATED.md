# The source-based images are deprecated

Everything under `deploy/docker/` builds container images **from source trees**: the
build context is a checkout of `server-team`, `ui-team`, `schemas`, `static`, and the
image runs `npm ci` or webpack at build time. That approach is being replaced by images
that **install `.deb` packages** from `apt.drumee.net`, per `docs/distribution.md` §1.

Do not add to this tree. Fixes to keep the current stack running are fine; new
components, new services and new build logic belong in the package-based path.

## Why

The `.deb` is the unit of versioning and of dependency. An image built from a source
checkout has neither:

- **Nothing pins what went in.** The image content is whatever the branch HEAD was at
  build time, so two builds of the same tag are not the same image. `Dockerfile.server`
  and `Dockerfile.ui` are multi-stage builds over a working tree; there is no version
  recorded in the result.
- **No dependency graph.** `nginx`, `bind9`, `ffmpeg`, `libreoffice`, `redis-server`,
  `postfix`, `opendkim` are named in Dockerfiles rather than in `debian/control`, so
  nothing reviews them, nothing versions them, and nothing resolves them together.
- **It duplicates the native channel.** The same components are already built,
  versioned and signed as packages for `apt.drumee.net`. Building them a second way
  means two supply chains to keep honest, and only one of them has a signed index and
  a keyring.
- **The runtime does work the build should have done.** `ui-build` compiles webpack in
  the running stack, so a deployment depends on a compiler. `drumee-ui-pod` already
  contains the built bundles.

## What replaces it

Seven roles, declared in `roles/debian/control`, each `Provides`/`Conflicts:
drumee-role` so only one can be installed per image:

| Deprecated image | Replacement |
| --- | --- |
| `drumee/server-pod` (`Dockerfile.server`) | `drumee-role-app` |
| `drumee/ui-build` + `drumee/static` (`Dockerfile.ui`, `Dockerfile.static`) | `drumee-role-web` |
| — (conversion ran inside server-pod) | `drumee-role-converter` |
| `drumee/schemas` + `drumee/schemas-populate` | `drumee-role-schemas` |
| `drumee/infra-init` (`Dockerfile.infra-init`) | `drumee-role-infra` |
| — (bind9 ran on the host or not at all) | `drumee-role-dns` |
| — (mail likewise) | `drumee-role-mail` |

The base image they install into is `docker/Dockerfile.base`, which is already what the
design asks for: pinned by digest, fixed UID/GID 8000, the NodeSource keyring committed
under `docker/keyrings/` rather than fetched, `policy-rc.d` returning 101 so maintainer
scripts touch no service during a build, and `USER drumee`.

`drumee/wireguard` (`Dockerfile.wireguard`) is a special case: it copies
`bootstrap.sh`/`agent.js` from the `infra/` tree deliberately, so both channels run
byte-identical coordination logic against the shared protocol in `coord-server`. It
still needs replacing, but not by copying the agent a third time.

## The invariant failures in this tree are expected

`scripts/check-packaging.sh` reports two, and **both of them are here**:

```
FAIL  FROM without a digest          — 11 occurrences, every one in deploy/docker/ and scripts/Dockerfile.seed*
FAIL  npm install -g                 — Dockerfile.server:24, `npm install -g pm2`
```

They are **not worth fixing in place**. Digest-pinning `node:22-bookworm` in a file
that is being deleted buys nothing, and `npm install -g pm2` is already obsolete:
`drumee-node-runtime` is built, published, and in the pool. The failures clear when
this tree goes, and until then they are an accurate signal that the container channel
has not yet moved.

There used to be a third — `drumee-server-pod` claiming `Architecture: all` while
shipping native addons — and that one did need settling regardless of this tree,
because the role images inherit it. Fixed at 2.9.98: `Architecture: any`, amd64 only.
See `docs/distribution.md` §9.1. The consequence the role images inherit is now
`Architecture: amd64`, so the role metapackages must not claim arm64 until there is
an arm64 `server-pod` to depend on.

## Removal criteria

This tree goes when all of the following are true, and not before — it is currently the
**only** working container path:

1. ~~Per-role Dockerfiles exist over `docker/Dockerfile.base` and build the seven roles.~~
   **Done at 1.0.55.** All seven build:
   `docker/Dockerfile.role-{web,infra,app,schemas,dns,mail,converter}`.
2. ~~`config/render.mjs compose` emits the role services instead of the 15 current ones.~~
   **Done** — `images.stack: roles`, eight services plus profile-gated `dns` and `mail`.
   Still not the default, because of 4.
3. `tests/smoke-container.sh` and `tests/e2e-local.sh` pass against role images.
   Both still target the source stack.
4. Images are published and signed for the architectures the roles claim.
   None are published — every role image so far is built against a local repository
   (`scripts/apt-repo-local.sh`). This is now the binding criterion.
