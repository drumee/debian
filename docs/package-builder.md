# Package: builder (drumee-installer interactive installer)

**Directory:** `builder/`
**Debian package:** `drumee-installer`
**Current version:** 1.2.6

## Purpose

The `builder/` package produces a `drumee-bootstrap` `.deb` that is an **interactive first-time installer** for a bare-metal or fresh VM deployment. Unlike the canonical `drumee-infra` package (built from `infra/`, pre-configured), this variant prompts via debconf during `dpkg -i` and then runs an interactive setup menu. It was renamed from `drumee-infra` to `drumee-bootstrap` to end the collision where both `builder/` and `infra/` built the same package name, and again to `drumee-installer` at 1.2.7 because the container distribution needs `drumee-bootstrap` for the per-role entrypoints package (docs/distribution.md §9.2).

> Note: the two still build from different sources (`infra/` clones and compiles
> `setup-infra`; `builder/` packages prebuilt `target/` artifacts). A full
> build-level merge into one package with an install mode flag is a tracked
> follow-up; the rename resolves the immediate ambiguity.

Post-install, it invokes `/var/lib/drumee/setup/menu/install.sh` — a guided setup wizard that configures the full Drumee stack from scratch.

## How It Differs from infra/

| Aspect | `infra/` | `builder/` |
|---|---|---|
| Source | Clones `setup-infra` from GitHub | Pre-built artifacts from `target/` |
| Config | Pre-configured | Interactive debconf prompts (domain, partition) |
| Post-install | Runs `setup-infra/bin/install` | Runs `setup/menu/install.sh` (full wizard) |
| Signing | GPG-signed | Unsigned (`-us -uc`) |
| Runtime deps | nginx, nodejs, npm, git, … | debconf only |
| Default REPO_BASE | GitHub | GitLab (`git@gitlab.drumee.in:drumee/`) |

## Source

Content comes from two places:

1. **`target/`** (repo root) — pre-built `etc/`, `usr/`, `var/` trees rsynced directly into the package
2. **`builder/src/setup`** — the `setup` repo (branch `somanos/wip`), installed to `/var/lib/drumee/setup/`

## Build

```bash
# Package what's already in target/ (no source pull)
builder/build.sh

# Pull the setup repo first, then package
builder/build.sh pull
```

No `--version`, `--force`, or `--email` flags — `builder/` has its own simplified `utils/functions.sh` that does not call `parse_args`.

## Installed Paths

```
/etc/drumee/           # from target/etc/
/usr/                  # from target/usr/ (includes acme.sh)
/var/lib/drumee/
└── setup/             # from builder/src/setup (setup wizard)
    └── menu/
        └── install.sh # interactive setup entry point
```

## Debconf Prompts

During install, the wizard (`setup/menu/install.sh`) drives a series of debconf
prompts, all under the `drumee-infra/*` namespace. The full set is defined in
`builder/debian/templates` (mirrored from `setup/menu/templates`):

| Template | Default | Description |
|---|---|---|
| `drumee-infra/description` | `My Great Drumee Team` | Human-friendly label for the instance |
| `drumee-infra/domain` | `example.com` | Domain name for the Drumee instance |
| `drumee-infra/local_mode` | `true` | Confirm local-only (not Internet-reachable) when domain is `local` |
| `drumee-infra/service` | — | Comma-separated list of optional services to enable |
| `drumee-infra/ip4` / `public_ip4` | `other` | Server IPv4 address (select or enter) |
| `drumee-infra/ip6` / `public_ip6` | `other` | Server IPv6 address (select or enter) |
| `drumee-infra/admin_email` | `admin@example.com` | Administrator login + notification address |
| `drumee-infra/acme_email` | — | ACME/ZeroSSL account email |
| `drumee-infra/db_dir` | `/srv/db` | Database storage path |
| `drumee-infra/data_dir` | `/data` | Filesystem (MFS) storage path |
| `drumee-infra/backup_location` | — | Backup location (different partition) |
| `drumee-infra/exchange_location` | `/exchangearea` | Host↔Drumee file exchange directory |
| `drumee-infra/own_ssl` / `own_ssl_path` | `false` | Use own wildcard SSL certs instead of ACME |

> Note: at build time `builder/build.sh` copies `setup/menu/templates` over
> `builder/debian/templates` (`cp -u`). Both must stay in sync until Phase 1
> establishes a single source of truth for configuration.

## Shared Utilities

`builder/` no longer carries its own `utils/` fork — it sources the root
`utils/env.sh` and `utils/functions.sh` (single source of truth). Builder-specific
behaviour is selected by environment variables set in `builder/build.sh` before
sourcing:

| Variable | Set by `builder/build.sh` | Effect |
|---|---|---|
| `REPO_BASE_DEFAULT` | `git@gitlab.drumee.in:drumee` | Fallback base used by `bundle()` when `REPO_BASE` is unset (GitLab instead of GitHub) |
| `NPM_AUDIT_FIX` | `no` | Skip `npm audit fix` during `bundle()` (avoids lockfile rewrites) |

`builder/build.sh` still explicitly sets `REPO_BASE=git@github.com:drumee`, so it
uses GitHub by default; unsetting `REPO_BASE` falls back to the GitLab default above.
