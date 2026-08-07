# Distribution — design of record

Status: design agreed, implementation pending.
Scope: container channel, Debian 13 Trixie only. The native channel is frozen
— neither removed nor maintained — for the duration of this transition.

This document is normative. Where it contradicts `ROADMAP.md` or any other
document, this one wins.

## 1. Founding principle

The `.deb` is the unit of versioning and of dependency. A container image is a
thin runtime that installs one role metapackage at an exact version; `dpkg`
resolves everything else.

What this replaces: the current Dockerfiles fetch sources by `git clone` via
the `REPO_BASE` build-arg. Image content therefore depends on the branch HEAD
at build time, two builds of the same tag do not produce the same result, and
there is no dependency graph between components at all.

Direct consequence: the dependency list (`nginx bind9 ffmpeg libreoffice
redis-server postfix opendkim…`) moves out of the Dockerfile and into
`debian/control`, where it is versioned and reviewed in code review.

Collateral consequence: the `ui-build` service disappears from the stack.
`drumee-ui-pod` already contains the webpack bundles, produced once in CI when
the package was built. Nothing compiles at runtime any more.

## 2. Multi-container decomposition

Seven roles, one per container. Only one role is installable at a time: each
role `Provides` and `Conflicts` the virtual package `drumee-role`, which makes
the monolith impossible to reassemble by accident.

| Container | Metapackage | Contents |
| --- | --- | --- |
| `drumee-app` | `drumee-role-app` | Node 22, `drumee-server-pod`, pm2 fork mode, REST 24000 / push 23000 |
| `drumee-web` | `drumee-role-web` | nginx, `drumee-ui-pod`, `drumee-static` |
| `drumee-media` | `drumee-role-media` | ffmpeg, GraphicsMagick, LibreOffice, poppler, dcraw, p7zip |
| `drumee-dns` | `drumee-role-dns` | bind9, TSIG dynamic updates |
| `drumee-mail` | `drumee-role-mail` | postfix, opendkim, spamass-milter |
| `drumee-db` | — | official `mariadb:11.8` image |
| `drumee-cache` | — | official `redis` image |
| `infra-init` | `drumee-role-infra` | renders the configuration tree (run-once) |
| `schemas-init`, `migrate` | `drumee-role-schemas` | init and migrations (run-once) |

MariaDB and Redis stay on their official images. `mariadb:11.8` matches the
version Trixie ships, so the 130 tables and 645 routines in `yp` are validated
against a single branch.

Splitting out `drumee-media` is deliberate and not negotiable: it carries the
heaviest dependencies in the platform, and it is the only component that
parses untrusted documents. It runs with no database credentials and no
inbound network exposure.

## 3. Version coherence

`release-manifest.yaml` is the only authoritative statement of versions.
Nothing else in the build is permitted to name a component version.

```
release-manifest.yaml
        │
        ├─ gen-substvars.py ─→ debian/*.substvars ─→ Depends: component (= exact version)
        │
        └─ drumee-release ──→ Depends: drumee-release (= ${binary:Version}) in every role
```

Components may legitimately sit at different upstream versions: static assets
and infrastructure configuration change far less often than the server. What
must never happen is two containers of one deployment coming from two
different rows of the manifest — hence the `drumee-release` anchor.

## 4. APT repository

pool/dists layout, hosted on `apt.drumee.net`.

```
dists/
  trixie/                      stable channel
    InRelease  Release  Release.gpg
    main/binary-amd64/{Packages,Packages.gz,Packages.xz,Release}
    main/binary-arm64/…
    main/source/{Sources,Sources.gz}
    enterprise/binary-amd64/…
  trixie-beta/                 beta channel
  trixie-edge/                 dev channel
pool/
  main/d/{drumee-roles,drumee-server-pod,drumee-ui-pod,drumee-static,
          drumee-schemas,drumee-patch,drumee-infra,drumee-bootstrap,
          drumee-node-runtime}/          # drumee-bootstrap here is the NEW
                                         # entrypoints package; the interactive
                                         # installer was renamed to
                                         # drumee-installer at 1.2.7
  enterprise/d/…
```

Decisions:

- Channels are **suites**, not components: they are mutually exclusive release
  trains, and suites allow natural pinning through `/etc/apt/preferences.d`.
- **Components** are reserved for the open-core split: `main` for the AGPL
  core, `enterprise` for the commercial tier, enabled by adding a component
  rather than by switching repository.
- Tooling: `reprepro` (or `aptly`), not raw `apt-ftparchive`. Channel
  promotion happens by copy — `reprepro copy trixie trixie-beta drumee` — so
  the artifact tested in beta is bit-for-bit the one that ships as stable.
- `Valid-Until` set to 30 days in `Release`, re-signed periodically, so a
  client cannot be served a stale index.
- A dedicated **project** signing key, master offline, signing subkey only in
  CI. The currently published repository is signed with a local build key and
  must be re-signed before any launch.
- Publishing `source/` gives AGPL v3 compliance: the Debian source package
  (`.dsc` + `orig.tar.gz`) is the canonical artifact for source availability,
  which also closes the open "public source strategy" question.

Client configuration, deb822:

```
# /etc/apt/sources.list.d/drumee.sources
Types: deb
URIs: https://apt.drumee.net
Suites: trixie
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/drumee-archive-keyring.gpg
```

The keyring is delivered by a `drumee-archive-keyring` package, which makes
key rotation manageable by `apt`.

`scripts/apt-repo-local.sh` stands up the same thing locally under `.apt-local/`
— consumable over `file://` for host builds and over HTTP from a throwaway nginx
container for image builds. Its signing key is generated on the spot and never
committed. One deviation is forced by the tool: `all` cannot be listed in
`Architectures`, since reprepro rejects it as not being a distributable
architecture. It is not a gap — reprepro files `Architecture: all` packages into
every listed architecture's index, so they are published for `amd64` and `arm64`
alike, which `verify` checks.

### Building and publishing it

`scripts/publish-pool.sh` produces the tree above, and both scripts source the
same definition (`scripts/lib/apt-repo.sh`) for suites, components,
architectures and `ValidFor` — one file, so the layout proven locally is by
construction the layout that ships.

```bash
scripts/publish-pool.sh init    --key=EMAIL_OR_KEYID
scripts/publish-pool.sh include --debs=out-debs [--suite=trixie] [--component=main]
scripts/publish-pool.sh promote --from=trixie-beta --to=trixie
scripts/publish-pool.sh verify  [SUITE]     # structure, signature, Valid-Until
scripts/publish-pool.sh check   [SUITE]     # a real apt client, in a container
scripts/deploy-apt-repo.sh --layout=pool --no-provision
```

Three properties that are cheap to assume and expensive to get wrong, so each is
checked rather than asserted:

- **Promotion copies, it does not rebuild.** Promoting six packages from `trixie`
  to `trixie-beta` leaves six files in `pool/`, referenced by both suites. The
  bytes tested in beta are the bytes that ship.
- **`Architecture: all` reaches every architecture.** `verify` counts the
  packages in `binary-amd64` and `binary-arm64` and fails if either is empty.
- **The signing key is not about to expire.** Both `init` and `include` refuse an
  expired key and warn inside 60 days. When a repository key expires, every
  client's `apt update` fails at once, on boxes nobody has touched for months,
  and it presents as an outage rather than as a key problem.

### Coexistence with the flat repository

The flat repository stays at the document root while clients migrate: a box that
already installed Drumee carries the flat stanza in its `sources.list.d`, and
removing it under them breaks `apt update` on a machine nobody changed. So
`dists/` and `pool/` are deployed *beside* the flat files, and two rules in
`deploy-apt-repo.sh` keep both layouts intact:

| Path | Sync | Why |
| --- | --- | --- |
| `pool/` | no `--delete` | immutable artifacts, still referenced by older indices |
| `dists/` | `--delete` | generated indices; a stale one advertises packages that are gone |
| flat root | `--delete`, excluding `dists/` and `pool/` | without the exclusion a flat publish deletes the entire pool tree |

That last exclusion is load-bearing, not defensive decoration: a dry run of a
flat publish against a document root containing the pool tree lists every
`dists/` and `pool/` file for deletion when it is omitted.

`conf/` and `db/` are **never** uploaded. They are reprepro's configuration and
internal state and they live in the same base directory as `dists/` and `pool/`,
so uploading the base directory wholesale would put the signing configuration on
a public web server. The deploy names the two published subdirectories
explicitly.

## 5. Maintainer scripts must be inert at build time

Drumee postinst scripts legitimately reconfigure a host: nginx, TLS, DNS, the
database. None of that exists during a `docker build`, and half of it would
bake machine-specific state into the image.

The base image therefore installs a `/usr/sbin/policy-rc.d` returning 101,
which makes `invoke-rc.d` refuse every service start.

The rule that follows: **the package delivers the payload, the job container
executes it**. `drumee-patch` installs its migrations under
`/usr/share/drumee/patches/` and does nothing else; the `schemas` role
entrypoint applies them at deploy time.

## 6. Additive migrations — the one-way door

Image digests allow exact rollback of *code*. The *schema* is not reversible.
Today `rollback` restores a dump, which loses everything produced between the
upgrade and the rollback.

Rule imposed on every migration: **additive only**. Nullable column additions,
new tables, new routines. Never a `DROP` and never an incompatible type change
in the same version; cleanup waits one release, once rolling back is no longer
an option.

Under this rule, code at N-1 runs against schema N, and `rollback` becomes a
plain version revert that never touches data. Without it, every rollback is
destructive no matter how good the versioning is.

Corollaries: strict ordering of `schemas-init` then `migrate` before
`drumee-app`, via `depends_on: condition: service_completed_successfully`; the
upgrade fails if migration fails, rather than letting `drumee-app` start
against a half-migrated schema; a `schema_migrations` table making the job
idempotent and letting `drumee-app` refuse to start when the schema version in
the database is below what the code requires.

## 7. Runtime identity

UID 8000 and GID 8000, fixed, defined once in the base image.

The MFS data volume and the rendered configuration volume are shared between
the app, media and web containers. If each image let `adduser` pick the next
free id, the same file would be owned by a different user in each container.

## 8. Image publication chain

Git tag → multi-arch buildx build → cosign keyless signature + SBOM →
registry, under channel tags → the host resolves the tag to a digest and pins
it.

- Registry configurable in `drumee.yaml`, the natural extension of the
  existing `REPO_BASE` build-arg. GHCR as primary, mirrored to a self-hosted
  registry for deployments that require it.
- Tags: `2.9.45` immutable, plus moving `2.9`, `stable`, `beta`, `edge`.
- `drumee-ctl upgrade` resolves the channel tag to a digest, writes the digest
  set into the pre-upgrade archive, then starts. `rollback` reinstalls those
  digests.
- Multi-arch only where it is needed: webpack bundles and static assets are
  architecture-independent. Only `drumee-server-pod` requires it, because of
  native Node modules. This avoids running a webpack build under arm64
  emulation.
- Keyless signing via GitHub OIDC: no long-lived key to hold.

## 9. Open blocking questions

1. ~~`drumee-server-pod` is currently `Architecture: all`.~~ **Settled at 2.9.98:
   it bundles native code, so it is `Architecture: any`, and amd64 is the only
   architecture built.** The payload carries 18 compiled `.node` addons — every one
   `linux-x64` (`@img/sharp-linux-x64`, `@msgpackr-extract/…-linux-x64`,
   `@parcel/watcher-linux-x64-*`) — plus private copies of libvips, cairo and rsvg.
   Under `all`, reprepro filed the amd64 build into `binary-arm64` too, so an arm64
   box installed it cleanly and then died at the first `require()` into sharp: no
   dpkg error, nothing in the journal until the first thumbnail.

   Two consequences, both deliberate:

   - `debian/rules` overrides `dh_shlibdeps`, `dh_strip` and `dh_dwz`. `any`
     activates `binary-arch`, which ran those three over the vendored tree for the
     first time; `dh_shlibdeps` failed outright trying to resolve the bundled `.so`
     files against system packages. Letting it succeed would be worse — it would
     add `Depends` on whatever system libraries happened to match, for objects that
     link against their own bundled copies. The runtime dependencies are declared by
     hand in `control`, which is correct for a vendored payload.
   - **arm64 has no `drumee-server-pod` at all**, and the stale `all` copy was
     removed from `binary-arm64` rather than left in place. So `apt install drumee`
     on arm64 now fails with `Depends: drumee-server-pod (= 2.9.98) but it is not
     installable` instead of installing something that cannot run. Measured with a
     real apt client on both architectures (`docker run --platform linux/arm64`).

   What this leaves open is no longer a packaging question but a build-capacity one:
   arm64 — the typical behind-a-router target — needs a builder (native, or buildx
   under QEMU with an arm64 `npm ci`) before it can be served again. `verify`'s
   "`Architecture: all` reaches every architecture" count is therefore 8 for amd64
   and 7 for arm64 by design, not drift.
2. `drumee-node-runtime` and `drumee-bootstrap` do not exist yet. The first
   replaces the unpinned `npm install -g`, the second replaces
   `COPY ./opt/drumee/init.d/*`, which bypasses versioning entirely.
3. Package names to verify on Trixie: `bind9-utils` (not `bind9utils`), and the
   runtime replacement for `libgraphicsmagick1-dev`, which is a development
   package.
4. `mysql-common` sat alongside `mariadb-server` in the original Dockerfile —
   a potential conflict to confirm.
5. ~~Availability of a Node 22 image on a Trixie base, or NodeSource pinning.~~
   **Measured: Trixie ships nodejs 20.19.2+dfsg-1+deb13u2**, so `Depends: nodejs
   (>= 22)` — which `drumee-node-runtime` and `drumee-role-app` both declare — is
   unsatisfiable from Debian alone. NodeSource (or an equivalent) must therefore be
   configured in the base image, with its keyring committed under
   `docker/keyrings/` rather than fetched at build time. Increment 4.
6. The `infra-init` service is not implemented. Feasibility is validated
   (`infra.js --chroot` renders the full 39-file tree from environment
   variables with no host writes) but `conf.d` provisioning still relies on a
   workaround in the entrypoint. Without it the jitsi/mail/dns profiles remain
   unusable.
