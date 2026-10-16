# Minimal kernel operator and clean installation

The profile is explicitly selected with `drumee-ctl --profile minimal-kernel`.
Team remains the default. This is the IL-4R qualification channel, not a published
release. Installation uses the canonical Infra Layer lifecycle and KB-01B jobs.

## Acquire and build

Use Node 22, Git/network access, Docker/Compose, and a normal Docker-authorized
operator account. No existing installation, identity dump or sibling checkout
is required. From a clean checkout on `feat/container-distribution`:

```sh
npm ci --ignore-scripts --no-audit --no-fund --prefix profiles/minimal-kernel
node profiles/minimal-kernel/scripts/sources.js
node profiles/minimal-kernel/scripts/verify.js
bash scripts/build-minimal-kernel.sh
```

The additive dependency manifest preserves the 213-artifact/71-file IL-3
inventory and pins runtime alpha.4, the exact KB-01B source/schema and the
unpublished Infra Layer development candidate. npm checks SRI; acquisition
checks immutable Git blobs and per-file SHA-256. Never replace the infrastructure
source URL with registry alpha.1: it lacks lifecycle APIs.

Images use digest-pinned bases and exact Debian/npm package versions. The build
requires committed profile source and emits immutable image IDs, source revision
and alignment digest in `profiles/minimal-kernel/.cache/images.json`. This is
dependency/provenance reproducibility; byte-for-byte Docker filesystem/timestamp
reproducibility is not asserted. No image is published by this command.

## Configure and install

Copy `config/drumee.minimal-kernel.example.yaml` to the deployment's
`config/drumee.yaml` (or pass its path explicitly). Set every deployment identity,
UID/GID, physical network interface, observed LAN address, binding/ports, owned
persistent root, backup directory and retention period intentionally. Set the
kernel/tools image IDs and exact provenance from the build receipt. Placeholder
image IDs cannot activate. The storage/backup parents must be writable by the
operator, with no unsafe symlink or shared writable ancestors.

The profile uses `instance.domain: drumee.lan`, `dns.mode: local` and
`tls.provider: local`. Infra Layer creates and preserves the private CA. No
public ACME request, host trust-store installation, firewall change or system
resolver change is performed. LAN address validation reads the named physical
interface; a Docker/container address is never discovered or substituted.

```sh
bin/drumee-ctl --profile minimal-kernel validate --config config/drumee.yaml
bin/drumee-ctl --profile minimal-kernel plan --config config/drumee.yaml
bin/drumee-ctl --profile minimal-kernel install --execute --config config/drumee.yaml
```

Plan/validate are pure. Shared renderer `validate` uses the profile validator;
`compose`/`all` emit Infra Layer composition JSON. Team `.env`, Caddy and native
debconf outputs are explicitly unsupported for the minimal profile. The native
Team package channel is unchanged.

Every mutation requires `--execute`, matching UID/GID and canonical deployment
ownership. Unknown nonempty roots, resource adoption and unrelated Docker
resources are refused. Installation explicitly runs intrinsic schema, platform
bootstrap, KB-01A authority, KB-01B schema, kernel-owned Hub/MFS schema, enrollment,
and real-runtime authentication jobs before private provisioner/kernel/gateway
readiness. Enrollment creates no Hub. A protected configuration snapshot is
included among the distribution's persistent backup resources.

## Initial administrator and credentials

Specify an explicit lowercase Drumee username and email. The account is a human
drumate in organisation 1, personal/active, Domain membership 1 and independent
PLATFORM_ADMINISTRATOR remit 15. It is authenticated by published runtime alpha.4.
Normal sign-in uses the canonical email or UID contract. Platform authority
does not bypass Hub or MFS ACLs.

`operator.mode: interactive` uses KB-01B's non-echoing TTY prompt and confirmation.
Without a secure TTY it fails explicitly. A protected owned 0600 regular-file
descriptor can instead be passed as `--password-fd 3`; no password argument or
environment variable is accepted. The canonical provider validates that descriptor
and persists the bound resource before the enrollment transaction.

`operator.mode: automatic` generates credentials once using KB-01B's canonical
provider, after prerequisites and schema validation. The private resource is
`<storage.root>/durable/operator-state/credential.json`: parent 0700, file 0600,
operator-owned, atomically committed and fsynced. Installation prints its location
and retrieval procedure, never the password. At a private controlling TTY:

```sh
bin/drumee-ctl --profile minimal-kernel credential --execute --config config/drumee.yaml
```

The canonical retrieval command authorizes delivery to `/dev/tty`, never ordinary
stdout. Do not terminal-record that session. Keep the protected resource and its
backup: it is not a password-reset or account-recovery API. Ordinary kernel,
provisioner and gateway services cannot read it. Test mode requires explicit
`deployment.acceptance: true`; acceptance-only users are created only by the
isolated test harness, never installation jobs.

## Lifecycle commands

```sh
bin/drumee-ctl --profile minimal-kernel status --config config/drumee.yaml
bin/drumee-ctl --profile minimal-kernel doctor --config config/drumee.yaml
bin/drumee-ctl --profile minimal-kernel stop --execute --config config/drumee.yaml
bin/drumee-ctl --profile minimal-kernel start --execute --config config/drumee.yaml
bin/drumee-ctl --profile minimal-kernel install --execute --recover --config config/drumee.yaml
```

Commands emit JSON state/diagnostic codes and actionable resource locations.
Starting an existing deployment requires configuration agreement. Canonical
initialization replay preserves UID, operation ID, credentials, remit, reserved
identities and existing Hub/MFS state. Drift, malformed enrollment metadata,
missing credential resources, revoked remit and unexpected grants fail closed;
no administrator or password is recreated or repaired automatically.

`--recover` acknowledges a known interrupted activation. A genuinely crashed
writer can leave an exclusive lifecycle lock. The product never steals it based
on elapsed time or PID guesses: establish the exact writer has exited, inspect
the owned state and journal, then perform explicit operator recovery. Acceptance
tests remove only the empty lock of the exact child they killed and reaped.

Use `kernel.create_hub` through the normal authenticated service dispatcher for
an explicit platform-authorized Hub operation. The private provisioner repeats
canonical session/platform policy and delegates to HubLifecycle/system-mfs.
The ordinary runtime never receives its SQL credential. Subsequent Finder,
FileIo and transfer operations retain canonical Hub/MFS checks.

## Backup, isolated restoration and upgrades

See [recovery guide](minimal-kernel-recovery.md) and [SQL matrix](minimal-kernel-sql.md).
SMTP is optional infrastructure and remains excluded from this profile's fully
qualified recovery scope. Automatic renewal scheduling and automatic host trust
or resolver management remain uninstalled.
