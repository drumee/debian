# IL-4R integration validation ledger

Status, 2026-10-16: **IL-4 — READY_FOR_RELEASE_REVIEW**. No publication or
release tag. Qualified implementation source:
`4a0efba6193912ce5b0487db51fb541ca79638d0`. Later evidence-only commits do not
change the built profile. Machine-readable reports, image identities, sanitized
SQL observations and log hashes are in
[`minimal-kernel-il4r-evidence.json`](minimal-kernel-il4r-evidence.json).

## Final checkpoint disposition

| Checkpoint | Result and evidence |
|---|---|
| IL-4R.1 | Original 213 npm/71 source inventory retained; additive lock has 213 npm artifacts/93 verified source files. Runtime alpha.4, exact KB-01B and immutable Infra candidate source verified. |
| IL-4R.2 | Explicit minimal container profile, drumee.lan/local DNS/persistent local CA, physical LAN validation, Nginx/BIND9/MariaDB/Redis, real runtime/control-plane/MFS/FileIo/LETC/Finder/Window Manager. Team remains default. |
| IL-4R.3 | Canonical initialization and credential providers only; automatic and real-PTY interactive enrollment; no implicit Hub. Actual interruption, missing committed resource and concurrent resume preserve canonical state. |
| IL-4R.4 | Six responsibilities separated: infrastructure administration plus schema/bootstrap/enrollment/provisioner/runtime accounts. Real positive and 16 unique negative SQL cases pass fresh and restored. |
| IL-4R.5 | Existing drumee-ctl dispatch: plan/validate/install/status/doctor/start/stop/backup/restore/upgrade/rollback plus private credential retrieval. Explicit execute/ownership guards, JSON codes, canonical lifecycle. |
| IL-4R.6 | Clean GitHub checkout, npm/source integrity verification, image builds, both enrollment modes, restart, cold backup and independent isolated restore pass without siblings or historical identity DBs. |
| IL-4R.7 | testbox physical LAN 192.168.5.202, authoritative TCP/UDP DNS, strict HTTPS CA/SAN, real external Chromium, protocol/ACL/MFS/restart/restore pass. Owned projects cleaned; unrelated resources preserved. |
| IL-4R.8 | Infra alpha.2 candidate packaged, installed-consumer/type/security/lifecycle tests pass; clean-source npm tarball reproduces identical SRI. Registry still has only alpha.1 as latest/next. Nothing published. |

Infra source is `ad8f2baecb65e5e8782bb60fa92f1653bcc9f724`, **not** published
alpha.1. Its candidate tarball has 39 allowlisted files, no production npm
dependencies, and SRI
`sha512-KuNELBJcKBA69RN65qoej4Wxw+lMN5NJO5d50ooHwydZMB90Rq42MyavDgOwpWqG12bPKjJKH0b01tvN17nsnw==`.
See [candidate evidence](minimal-kernel-infra-candidate.md),
[operator/clean installation guide](minimal-kernel-operator.md),
[SQL matrix](minimal-kernel-sql.md) and [recovery guide](minimal-kernel-recovery.md).

## Final validation counts

Counts are separate; **no combined total** is claimed because coverage overlaps.
All final selected runs below passed with zero reported skips.

| TAP suite | Cases passed |
|---|---:|
| Debian profile (includes original inventory eight) | 15 |
| Infra unit/security | 127 |
| Infra gateway | 17 |
| Infra native services | 17 |
| Infra lifecycle | 16 |
| KB-01B units / real MariaDB | 18 / 31 |
| Published runtime source units / KB-01A real MariaDB | 56 / 16 |
| Retained kernel/control-plane/runtime/capability regression | 85 |
| Installed system-mfs units | 7 |
| Exact pinned Finder source | 31 |

The retained capability run of 68 is included in the 85; it is not added again.
SQL TAP counts include their parent cases. Finder's installed npm tarball omits
tests: its zero-test discovery is excluded; source revision
`b46e2c94b615a1993b6162716d9e8965d0029564` actually executes 31 cases.

Other validation: Debian shared suite **331 checks**, OCI archive security
**five Python cases**, Infra HTTPS/jobs **four scenarios**, strict JSON Schema
**three checks**, and strict NodeNext TypeScript installed-consumer compilation.
ShellCheck is unavailable; shell syntax checks and the legacy suite ran. Heavy
historical native/Team/WireGuard suites were not run for this explicit container
profile. SMTP recovery is excluded, not represented by unrelated mail tests.

| Real distribution run | Direct functional assertions | Browser assertions / scenarios | Stage groups | SQL denial cases |
|---|---:|---:|---:|---:|
| Clean automatic, enrollment interruption/concurrency | 260 | 24 / 3 | 11 fresh + 10 restart + 10 restore | 16 unique |
| Clean interactive, real PTY | 254 | 24 / 3 | 11 + 10 + 10 | 16 unique |
| testbox automatic, separate LAN browser client | 258 | external / 3 | 11 + 10 + 10 | 16 unique |

PTY assertions execute in the Python subprocess and are not silently added to
the JavaScript assertion count. SQL denial subprocess assertions are separate;
repeating the same 16 after restore does not make 32 unique cases. Browser
assertions and scenarios are separate measures. Remote acceptance covers the
**14 named requirement criteria** recorded in the evidence JSON; it is not 14
additional TAP cases. Fresh/restart browser access is direct over the physical
LAN; restored access uses a scoped SSH tunnel to the deliberately loopback-only
restoration. No LAN claim is made for that restored binding.

All three final runs preserve administrator UID, operation ID, credential bytes,
remit, reserved identities, Hub/MFS state and CA identity. Real authentication,
authorized Hub creation and reader/outsider/cross-Hub denial pass. Binary chunks,
FileIo/ZIP/Range, OTAK/Redis/WebSocket and normal email/password browser login
pass. SQL metadata confirms no global application privileges, separate schema
and provisioner DEFINERs, and INVOKER get_remit. Runtime cannot write remit,
enrollment metadata, ACLs, SQL accounts, schemas, cookie/socket transport rows or
unrelated databases. The provisioner is intentionally privileged inside the
escaped Hub namespace; its database-level GRANT OPTION is explicitly documented.

## Reproduction commands

Run from a fresh Debian checkout with Node 22 and an authorized Docker account:

```sh
npm ci --ignore-scripts --no-audit --no-fund --prefix profiles/minimal-kernel
node profiles/minimal-kernel/scripts/sources.js
node profiles/minimal-kernel/scripts/verify.js
node profiles/minimal-kernel/scripts/build.js
node --test profiles/minimal-kernel/inventory.test.js profiles/minimal-kernel/test/*.test.js
python3 tests/minimal-kernel/image-archive.test.py
tests/run-all.sh
IL4_INTERFACE=wlp3s0 IL4_LAN_ADDRESS=192.168.5.201 IL4_INTERRUPT=1 node tests/minimal-kernel/run.js
IL4_INTERFACE=wlp3s0 IL4_LAN_ADDRESS=192.168.5.201 IL4_MODE=interactive node tests/minimal-kernel/run.js
node profiles/minimal-kernel/scripts/export.js /owned-artifacts/minimal-kernel.tar.gz
```

The interface/address are explicit acceptance-host observations, not portable
defaults. Archive SHA-256 for the qualified export:
`d177af5c880993cbcc633dbb75d66dccf11400d50c9906f6a9b4b7f6c3f17203`.
The receipt records both classic config IDs and portable OCI manifest references.
Testbox verified that hash before loading; its clean checkout resolved the same
213-artifact graph and 93 source files. Pinned official helper/base digests were
pulled explicitly. No local sibling is needed by those commands.

On the already approved owned testbox workspace, after current port/resource
inspection and image verification:

```sh
IL4_IMAGES=/tmp/drumee-il4-testbox-6555f18/minimal-kernel-4a0efba.tar.gz.json \
IL4_INTERFACE=wlp2s0 IL4_LAN_ADDRESS=192.168.5.202 \
IL4_BIND_ADDRESS=192.168.5.202 IL4_HTTPS_PORT=443 IL4_DNS_PORT=53 \
IL4_EXTERNAL_BROWSER_DIRECTORY=/tmp/drumee-il4-testbox-6555f18/browser \
node tests/minimal-kernel/run.js
# Separate LAN client, during that run:
node tests/minimal-kernel/remote-browser.js /tmp/drumee-il4-testbox-6555f18/browser
```

Supporting repositories, at the revisions above:

```sh
# Infra Layer candidate, including fresh-clone repetition and packed consumer:
npm ci --ignore-scripts --no-audit --no-fund
npm test
npm run test:integration
npm run test:package
npm pack --json
# transient, canonical KB-01B:
npm test --prefix target/control-plane/operator-bootstrap
npm run test:integration --prefix target/control-plane/operator-bootstrap
# Retained transient regression (85, including the earlier subset of 68):
node --test target/control-plane/bootstrap/test/*.test.js target/control-plane/hub-lifecycle/test/*.test.js target/foundation/server-runtime/test/*.test.js target/modules/host-filesystem/test/*.test.js target/modules/mfs-service/test/*.test.js target/modules/mfs-transfer/test/*.test.js target/modules/media-service/test/*.test.js
# Unchanged server-runtime source:
npm test
npm run test:platform:integration
# Exact Finder source checkout:
node --test test/*.test.js
# Installed system-mfs, from the Debian profile:
node --test node_modules/@drumee/system-mfs/test/*.test.js
```

The npm candidate reproduces byte-for-byte from a fresh remote source clone.
Both image recipes also build without Docker cache. Pinned dependency/image
inputs and integrity are established; Docker filesystem timestamp identity is
not asserted across rebuilds.

## Failures, exclusions and operational limits

Earlier progress entries below remain historical evidence and are superseded
by the final runs. They are not added into final counts. Corrected attempts
include the schema import, canonical email sign-in, permission conversion,
Team default rendering, immutable cross-store image references, isolated remote
restore binding and MariaDB upsert column privileges. No runtime/control-plane
identity or authorization workaround was added.

One final local PTY attempt failed with DOCKER_LIFECYCLE_COMMAND_FAILED after
Redis rotation at restart. The lifecycle returned no underlying child detail;
historical Docker events were unavailable, so its cause is **unconfirmed**.
Owned resources were cleaned. A credential-free diagnostic rerun of unchanged
source completed all stages, as did independent final automatic and remote runs.
This failed attempt remains disclosed; it is not counted as a passing run or
hidden by weakening tests. An optional metadata observer missed a cleaned-up
deployment; a separate canonical owned SQL probe captured the published grant
observation without credentials or authentication hashes.

Review limitations: explicit experimental container profile; no native minimal
package claim; SMTP recovery excluded; no host trust/resolver/firewall changes;
no automatic backup deletion scheduler or additional-account secret rotation;
unqualified engine/schema/kernel transitions fail closed. Same-revision upgrade
and rollback were exercised. Crashed exclusive locks and partial canonical DDL
require explicit owner investigation; no stale-lock stealing, administrator
repair or password recreation is implemented. No publication, permanent testbox
installation or Oxymotion work occurred.

The alignment manifest retains its inventory-only `release_qualified: false`
contract; executed readiness is recorded here, not inferred from an inventory.
Private transitional modules' absent license declarations are preserved rather
than guessed; notice/rights review remains a prerequisite before public
distribution. backbone.radio's installed LICENSE supplies its MIT notice despite
the missing lock metadata. This is independent of the AGPL-licensed Infra
candidate's verified package allowlist and license.

## Historical progress entries (superseded by final qualification above)

## Inspected baseline, 2026-10-15/16

- Debian `feat/container-distribution`: `d035f9ed5af437c323d364dfbd732673f24f6c3e`.
- Transient `refactor/mapping`: `59985d4a78e142b64f5976cc7460a723cca29a79`.
- Infra Layer `main`: `35fe3d0e6b6311d43940338b65a7e5ae74c0d222`.
- Runtime `main`: `f961f6214432c2e6dbbcde2b926544c076935950`.

Local/remote branches and current metadata inspected. Supporting checkouts are
clean; Debian's existing server/UI changelog edits and untracked AGENTS.md are
excluded from this work. No reset or history rewrite was performed.

## IL-4R.1 dependency alignment

The original 213-artifact/71-file dependency inventory is unchanged. The additive
`profiles/minimal-kernel/dependency-alignment.json` records the current locked
213-artifact graph and 93 verified source files, including the exact KB-01B
module, durable credential provider and schema manifest. Source acquisition
uses immutable remote Git objects, with blob and SHA-256 checks. npm ci verifies
locked artifact SRI. No sibling source is required by the acquisition workflow.

Runtime alpha.4 registry gitHead and SRI match KB-01B's recorded release:
`sha512-bOZ/v6/4mQ/FPa8iE21polPx2PjJWFYTKqTz+2duqxI2ljpviemNgOtpwkxF4j/1Xn/1aVIxdvVCc8Tch2ctEQ==`.
Installed API checks confirm PLATFORM_ADMINISTRATOR remit 15, KB-01A schema
identity and all canonical enrollment APIs. Infra Layer comes from immutable
development revision `35fe3d0…`, with archive SRI recorded in the lock/alignment;
published alpha.1 is not substituted. Installed lifecycle imports are checked.

Registry inspection: Infra Layer versions `0.0.0-stage`, `0.1.0-alpha.1`;
latest/next both alpha.1. Alpha.2 remains a proposed, unpublished candidate.

Executed:

```sh
npm ci --ignore-scripts --no-audit --no-fund --prefix profiles/minimal-kernel
node profiles/minimal-kernel/scripts/sources.js
node profiles/minimal-kernel/scripts/verify.js
node profiles/minimal-kernel/inventory.js validate
node --test profiles/minimal-kernel/test/alignment.test.js profiles/minimal-kernel/inventory.test.js
```

11/11 individual TAP cases pass, zero failures/skips (eight retained inventory,
three additive alignment). A sandboxed initial run reported only two file-level
wrappers; that run is excluded. The normal-permission rerun executed all cases.
Functional assertions: none yet. Browser scenarios: none yet. Remote acceptance
checks: none yet; host inventory is not functional acceptance.

## Testbox observation

Read-only `ssh testbox` confirms host minis, UID/GID 1000, LAN
`wlp2s0=192.168.5.202/24`. TCP 22/631 and unrelated UDP listeners observed.
Stopped legacy project `drumee` has three existing init/migration containers;
these are unrelated and must remain untouched. No test deployment, host
resolver, firewall or trust-store change was made.

## Remaining qualification

IL-4R.2–8 require explicit normal-install configuration and jobs, separate SQL
roles, lifecycle operator integration, clean installation/recovery, interactive
PTY/concurrency/interruption tests, LAN/browser acceptance and candidate package
qualification. Prior IL-3/KB-01B results are retained evidence, not newly executed
IL-4R acceptance. SMTP recovery and automatic trust/resolver changes remain out
of scope. No permanent testbox installation or Oxymotion work is authorized here.

## IL-4R.2–5 implementation checkpoints

- `7823e0a`: explicit minimal profile, shared YAML parser/schema selection,
  canonical Infra Layer composition, kernel/frontend assembly.
- `15f75fe`: intrinsic/platform/KB-01A/KB-01B initialization, canonical enrollment
  and real-runtime authentication jobs.
- `237016b`: named SQL role policy and separate private Hub provisioner.
- `2c9f603`: existing drumee-ctl profile dispatch and canonical lifecycle commands.
- `2c7a006`, `664f752`, `3e7a654`: demonstrated installation corrections, retained
  acceptance suite and stable image-build provenance.

Infra Layer correction `9d8462b428db8c8421579067e7cb53b46630d39e` reproduces and
fixes the single-account/private-service integration limitation. Separate managed
accounts use its secret store; private supplied services use its lifecycle. No
distribution planner, credential hash, session or ACL implementation was added.
127/127 Infra Layer unit/security cases pass, zero failures/skips.

Normal distribution initialization contains no direct-SQL owner fixture and
creates no Hub. Canonical alpha.4 sign-in uses UID/email; the distribution's
email sign-in correction follows that existing contract. Ordinary runtime gets
no schema, bootstrap, enrollment, provisioner or infrastructure-admin credential.

## Preliminary complete automatic installation

At Debian `3e7a6547e9d7626fcbf54881894a6388541d7e69`, owned project
`drumee-il4-fbe29923`, HTTPS 43609 / DNS 33425 on loopback, explicit physical LAN
`wlp3s0=192.168.5.201`:

```sh
IL4_INTERFACE=wlp3s0 IL4_LAN_ADDRESS=192.168.5.201 node tests/minimal-kernel/run.js
```

28 grouped functional checks pass (10 fresh, nine restart, nine isolated restore),
including three real Chromium LETC/Finder/WebSocket scenarios. Ten SQL negative
cases pass both fresh and restored; these repeated executions are ten distinct
cases, not twenty unique tests. Canonical identity/ACL/MFS digests, credential
resource bytes and CA identity are preserved. Actual Redis rotation interruption
and recovery pass. All owned project/restoration resources are cleaned.

This run predates the candidate metadata pin, configuration-backup extension,
additional foreign-Hub/unrelated-schema assertions and real-PTY mode. Those
changes require the final acceptance rerun; this preliminary result is not
silently promoted to full final qualification.

## Regression and failure disclosure

- Canonical KB-01B units: 18 passed, zero failures/skips.
- Unchanged published runtime source units: 56 passed, zero failures/skips.
- Retained platform/Hub/runtime/FileIo/MFS/transfer/media units: 85 passed,
  zero failures/skips (17 platform/Hub plus the retained 68 runtime/capability).
- Legacy Debian clean checkout: 331 checks passed, zero failures/no reported
  skips. The original eight-check inventory remains included in profile units.

Early real-install explorations found an unexported runtime schema import,
username-vs-email sign-in mismatch and missing provisioner permission converter;
all were corrected without changing runtime/control-plane source. The schema
wrapper also exposed a Team default-rendering regression: nine aggregate checks
failed before the correction, followed by 331/331 passing. A failed-install
retry across changed frontend artifacts refused an asset conflict; it did not
replace identities or credentials. Failed smoke projects were inspected and
cleaned by exact ownership. These attempts are excluded from successful counts.
