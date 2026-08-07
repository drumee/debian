# Version Management

## Authoritative Version Source

**`release-manifest.yaml` is the only authoritative statement of any component
version.** Nothing else in the build may name one — `roles/debian/gen-substvars.py`
resolves the manifest into substvars, and `meta/make-control.sh` pins the metapackage
from it, so a version written by hand elsewhere is drift by construction.

Each package's `debian/changelog` still *carries* the version, because that is what
`get_version` reads at build time:

```
drumee-server-pod (2.9.45) stable; urgency=medium
```

but it is **derived**: bump the manifest, then `scripts/check-versions.sh --sync`
rewrites the changelogs to match.

### A release-train bump touches two keys

The user-facing train version lives in **two** places, and both must move together:

```yaml
release: 1.0.22          # the train: drumee-release, every drumee-role-*, the image tag
components:
  meta:         1.0.22    # the native metapackage, which tracks the train by definition
```

`--sync` rewrites component changelogs but **not** the train's — it only reports
`DRIFT release`. `meta/make-control.sh` writes that entry and re-pins the dependencies.
So the full sequence is:

```bash
# edit release-manifest.yaml
scripts/check-versions.sh --sync    # components
meta/make-control.sh                # the train + the = pins
scripts/check-versions.sh           # must be silent
meta/make-control.sh --check        # must be silent
```

Bumping `release:` alone leaves `check-versions.sh` failing on `DRIFT meta`; bumping
`components.meta` alone leaves it failing on `DRIFT release`.

## Debian Changelog Format

```
<package-name> (<version>) unstable; urgency=medium

  * Change description

 -- Maintainer Name <email>  Day, DD Mon YYYY HH:MM:SS +TZOFF
```

The two-space indent before bullet points and the single-space before `--` are required by `dpkg-parsechangelog`.

## update-changelog.sh

Four packages have an `update-changelog.sh` that auto-syncs the changelog from the upstream source repo's `package.json`:

- `server/update-changelog.sh`
- `ui/update-changelog.sh`
- `static/update-changelog.sh`
- `schemas-patch/update-changelog.sh`

### Usage

```bash
server/update-changelog.sh [--message="Custom message"] [--email=user@example.com]
```

### Version Selection Logic

The script compares two sources:

1. **Current changelog version** — first line of `debian/changelog`
2. **Upstream package.json version** — from the cloned source repo

It picks whichever is **higher** (semver comparison). This means the changelog version will never be downgraded by a `package.json` that lags behind.

### Commit Message

Without `--message`, the script pulls the **last 5 non-merge git commits** from the cloned source repo and formats them as bullet points. With `--message`, uses that string instead.

### Entry Behavior

- If the selected version **already exists** in the changelog, the script **replaces** that entry (updates the message and timestamp).
- If the selected version is **new**, the script **prepends** a new entry.

### When build.sh Calls It Automatically

`server/build.sh`, `ui/build.sh`, and `static/build.sh` call `update-changelog.sh` at the start of the build. `schemas-patch/build.sh` does not — run it manually before building a patch package if needed.

### Two consequences worth knowing before you hand-write a changelog entry

**A rebuild discards prose for the current version.** Because the script *replaces*
the entry for its target version (above) with the last five upstream commit subjects,
any explanation written by hand for the version you are about to build is gone the
moment you build it. `build.sh` calls the script with no `--message`, so there is no
way to keep it short of passing that flag yourself afterwards — at which point the
file no longer matches the `.deb` you shipped. Put the reasoning in the **git commit
message**; keep the changelog for what the tool generates.

**Upstream can outrank the manifest.** The version selection above takes the *higher*
of the changelog and the upstream `package.json`. So if the upstream repo has moved
ahead of `release-manifest.yaml`, the build silently produces the **upstream**
version, not the one the manifest states — and `check-versions.sh` then reports drift
*after* the fact. `drumee-ui-pod` has jumped 24 patch versions (3.3.50 → 3.3.74) in
one build this way, which also invalidates the metapackage's `=` pin until
`meta/make-control.sh` is re-run. Check the upstream version before bumping:

```bash
node -p "require('../ui-team/package.json').version"
```

## Bumping a Version Manually

1. Edit the first entry in `<package>/debian/changelog`:
   ```
   drumee-server-pod (2.9.45) unstable; urgency=medium
   ```
2. Run the build script. It will pick up the new version via `get_version`.

Alternatively, let `update-changelog.sh` do it — if the upstream `package.json` already has the new version, the script will prepend the correct entry.

## Standards-Version in debian/control

`check_version` updates the `Standards-Version:` field in `debian/control` to match the changelog version, keeping `lintian` happy. Note that the main package build scripts no longer call `check_version` — only `admin/build.sh` does — so `Standards-Version` is not auto-synced during a normal `infra`/`schemas`/`server`/`ui`/`static` build.

## Current Package Versions

| Package | Current version |
|---|---|
| `drumee-infra` | 1.2.11 |
| `drumee-schemas` | 2.6.99 |
| `drumee-server-pod` | 2.9.45 |
| `drumee-ui-pod` | 3.3.1 |
| `drumee-static` | 1.0.4 |
| `drumee-patch` | 1.1.6 |
| `drumee-infra` (builder) | 1.2.5 |

> Versions move with every release; treat this table as a snapshot. The authoritative value is always the first line of each `<package>/debian/changelog`.
