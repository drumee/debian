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
