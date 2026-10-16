# IL-4R integration validation ledger

Status: in progress; no release qualification or publication claimed.

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
