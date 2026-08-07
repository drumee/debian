# Build Pipeline

## Prerequisites

- **No root**: all build scripts check `$UID` and abort if run as root.
- **Git SSH access** to `git@github.com:drumee/` — scripts clone private repos.
- **GPG key** matching the maintainer email in `debian/changelog` must be in the local keyring (the main packages build signed).
- **Node.js** required for packages that run `npm install` or webpack during the build.
- **Debian build tools**: `dh_make`, `dpkg-buildpackage`, `debhelper`.

## End to end: from a change to something a client can install

```
  edit code
      │
  1 ─ release-manifest.yaml          the ONLY place a version is stated
      │                              (a release-train bump touches TWO keys)
  2 ─ scripts/check-versions.sh --sync
      │                              rewrites component changelogs
  3 ─ meta/make-control.sh           re-pins the metapackage + writes the train version
      │
  4 ─ unlock the GPG key             the build signs; a locked key fails at the last step
      │
  5 ─ <pkg>/build.sh                 bundle() pulls upstream, dpkg-buildpackage signs
      │
  6 ─ assemble the release set       every pinned package + drumee-node-runtime
      │
  7 ─ scripts/publish-apt.sh         → apt-repo/ : Packages, Release, InRelease, signed
      │
  8 ─ scripts/deploy-apt-repo.sh     → apt.drumee.net
      │
  9 ─ scripts/release-status.sh      local vs live, then a real apt client
      │
 10 ─ commit, tag vX.Y.Z, push
```

The order matters, and so does every note below: each of these has a failure mode
that leaves the build green and ships nothing.

**1 — Version.** `release-manifest.yaml` is authoritative; never write a component
version anywhere else. A **release-train** bump touches **two** keys — the top-level
`release:` *and* `components.meta` — because the metapackage tracks the train by
definition. Bumping only one leaves `check-versions.sh` failing on the other.

**2 — Sync.** `--sync` rewrites each *component* changelog to match the manifest. It
does **not** write the release train's changelog; it only reports `DRIFT release`.
Step 3 writes that one.

**3 — Re-pin.** `meta/make-control.sh` regenerates `meta/debian/control` with exact
`=` pins and prepends the train's changelog entry. Skip it and the metapackage pins
whatever it pinned last — which, if a component moved, is a version that no longer
exists in the repository, making `apt install drumee` unsatisfiable.

**4 — Signing key.** `dpkg-buildpackage -k<email>` needs the key unlocked. From a
non-interactive shell it fails with `No pinentry` at the *end* of a long build. Check
first:

```bash
echo t | gpg --batch --pinentry-mode error -u <maintainer-email> --clearsign -o /dev/null
```

**5 — Build.** Two behaviours that change what you get:

- `DEB_BUILD_TARGET` is honoured by **`infra`, `schemas`, `server` only**. `ui`,
  `static`, `meta`, `schemas-patch` and `builder` leave the `.deb` in
  `<pkg>/build/` and must be collected by hand.
- `update-changelog.sh` (`server`, `ui`, `static`, `schemas-patch`) takes
  **`max(changelog, upstream package.json)`**, so an upstream repo that has moved
  ahead **outranks the manifest and changes the version you are building** — `ui` has
  jumped 24 patch versions this way. It also **replaces** the entry for the target
  version with the last five upstream commit subjects, so hand-written changelog prose
  for the *current* version does not survive a rebuild unless `--message` is passed,
  and `build.sh` does not pass it. Put the reasoning in the git commit message.

**6 — The release set.** Whatever you hand to `publish-apt.sh` must contain every
package the metapackage pins, plus `drumee-node-runtime` (`drumee-server-pod`
depends on it — omit it and apt refuses the whole install with *"but it is not
installable"*).

**7 — Stage.** `publish-apt.sh --debs=<dir> --out=apt-repo --key=<email>` copies the
`.deb`s alongside whatever is already in `apt-repo/` and regenerates + signs the
indices. History accumulates deliberately: old versions stay downloadable.

**8 — Deploy.** `deploy-apt-repo.sh --layout=flat` rsyncs `apt-repo/` to the server.
Two traps:

- **It does not publish the installer.** `scripts/debian.sh` is copied into the
  flat repo by **`publish-site.sh` only**, under three names: `debian.sh` plus the
  previous `baremetal.sh` and `install-native.sh`, kept byte-identical because those
  URLs are in circulation. A package-only publish
  leaves the documented `curl … | sudo bash` serving the *previous* installer, which
  can then preseed different answers than the packages now expect.
- The flat root syncs with `--delete`, excluding `dists/` and `pool/`. Dry-run before
  every upload and confirm the deletion count is zero:

  ```bash
  rsync -avzn --delete --exclude='dists/' --exclude='pool/' \
    apt-repo/ debian@apt.drumee.net:/var/www/apt.drumee.net/ | grep '^deleting'
  ```

**9 — Verify.** `scripts/release-status.sh` puts local beside live in one table —
manifest / built / staged on the left, what `apt.drumee.net` actually serves on the
right, plus git, tags, the installer checksum and an rsync dry-run. Then prove it with
a real client, because only that exercises signature verification and dependency
resolution:

```bash
docker run --rm debian:trixie bash -c '
  apt-get update -qq && apt-get install -y -qq curl ca-certificates gnupg >/dev/null
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://apt.drumee.net/drumee-archive-keyring.gpg \
    -o /etc/apt/keyrings/drumee-archive-keyring.gpg
  printf "Types: deb\nURIs: https://apt.drumee.net\nSuites: trixie\nComponents: main\nSigned-By: /etc/apt/keyrings/drumee-archive-keyring.gpg\n" \
    > /etc/apt/sources.list.d/drumee.sources
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
  apt-get update -qq && apt-get install -y --dry-run drumee | grep ^Inst'
```

NodeSource is required in that check, not optional: Trixie ships Node 20 and
`drumee-node-runtime` declares `nodejs (>= 22)`, so `apt install drumee` cannot
resolve from Debian alone.

**10 — Commit and tag.** The packages are built from the working tree, so publishing
before committing leaves artifacts in the wild that no commit describes. Tag the
commit the release was built from, and record in the tag which upstream commits were
bundled — `bundle()` pulls from **origin**, so an unpushed fix in `setup-infra` or
`server-team` is *not* in the package even though it is in your checkout.

## Building a Single Package

```bash
infra/build.sh
schemas/build.sh
server/build.sh
ui/build.sh
static/build.sh
schemas-patch/build.sh --manifest=auto
```

Each script sources `utils/functions.sh` (and `utils/env.sh`), clones or updates the upstream source repo via `bundle()`, assembles a staging directory under `<package>/build/<version>/`, then calls `dh_make` and `dpkg-buildpackage` to produce the `.deb`.

## Building All Main Packages

```bash
./build-all.sh
```

Runs `infra → schemas → ui → server` in sequence. Stops on the first failure (`set -e`). It passes `--force=yes` to each script, but that flag is a harmless no-op for these packages (see below).

## Version and Maintainer

The build scripts read the **version and maintainer email from `<package>/debian/changelog`** (via `get_version` / `get_email`). There is **no `--version` or `--email` flag** wired into the current build scripts — to change a version, edit the changelog first (see [Version Management](version-management.md)).

`get_build_dir` unconditionally removes and recreates the per-version build directory on every run, so there is **no "rebuild existing?" prompt** and `--force` is not needed for the main packages.

## Per-Script Flags

Only these flags actually affect a build:

| Script | Flag | Effect |
|---|---|---|
| `ui/build.sh` | `--compile=yes\|no` | Parsed but **not honoured** — webpack always runs |
| `ui/build.sh` | `--enable-api=yes\|no` | Also compile the `api` webpack target (default `no`) |
| `schemas-patch/build.sh` | `--manifest=auto\|<file>` | **Required** — selects the patch manifest (see [schemas-patch](package-schemas-patch.md)) |
| `schemas-patch/build.sh` | `<N>` (positional) | Commit depth for `--manifest=auto` (default `2`) |
| `builder/build.sh` | `pull` (positional) | Pull the `setup` repo before packaging |

> `utils/functions.sh` defines a generic `parse_args` and interactive `check_version` / `check_email` / `check_build_dir` helpers, but the main package build scripts no longer call them — only `admin/build.sh` still uses the interactive `check_*` flow. `static/build.sh` parses `--version/--force/--email` but then overrides them from the changelog, so they have no effect.

## Environment Variables

| Variable | Effect |
|---|---|
| `DEB_BUILD_TARGET=/path` | After a successful build, the `.deb` is copied there — **only `infra`, `schemas`, and `server`** do this (`ui`, `static`, `schemas-patch`, and `builder` do not) |
| `SEEDS_DIR=/path` | Source directory for the schemas seeds archive (default: `$HOME/docker/data/seeds/`) |
| `REPO_BASE=git@...` | Override the GitHub base URL used by `bundle()` — useful for a local mirror |

## Build Output

`dpkg-buildpackage` builds in the `<package>/build/<version>/` staging tree, so the resulting `.deb` lands in the package's `build/` directory — e.g. `server/build/drumee-server-pod_2.9.45_all.deb`. If `DEB_BUILD_TARGET` is set, `infra`/`schemas`/`server` also copy it there.

## GPG Signing

`dpkg-buildpackage -k<email>` signs the package with the key matching the maintainer email from `debian/changelog`. Ensure the key is imported:

```bash
gpg --list-secret-keys <maintainer-email>
```

To build without signing (testing only):

```bash
dpkg-buildpackage -us -uc
```

The `builder/` package always builds unsigned (`-us -uc`).

## Staged Source Directory

`bundle()` clones each upstream repo into `<package>/src/<repo-name>/`. On subsequent runs it does `git stash` + `git pull` + `git checkout <branch>` instead of a fresh clone. The build staging tree (`<package>/build/<version>/`) is wiped and recreated on every run by `get_build_dir`; it is separate from the `debian/` packaging metadata, which lives in `<package>/debian/`.

## The builder/ Package

`builder/` produces a `drumee-infra` interactive installer — distinct from `infra/` which is a pre-configured package. Key differences:

- Reads pre-built artifacts from the `target/` directory (no upstream compile step).
- Post-install runs `/var/lib/drumee/setup/menu/install.sh` — an interactive setup wizard.
- Uses debconf to prompt for domain name and partition during `dpkg -i`.
- Builds unsigned (`dpkg-buildpackage -us -uc`), no GPG key required.
- Has its own `builder/utils/` with a GitLab fallback in `bundle()` (`git@gitlab.drumee.in:drumee/` when `REPO_BASE` is unset).
- Does not support `--version`, `--force`, or `--email` flags.

```bash
builder/build.sh        # package current target/ artifacts
builder/build.sh pull   # pull setup repo first, then package
```

See [package-builder.md](package-builder.md) for full details.

## Package Dependency Chain

```
drumee-infra
    └── drumee-schemas   (mariadb-server, mariadb-client)
        └── drumee-static
        └── drumee-server-pod  (nginx, redis, ffmpeg, libreoffice, ...)
        └── drumee-ui-pod      (nodejs, git)
            └── drumee-patch   (mariadb-server, mariadb-client)
```
