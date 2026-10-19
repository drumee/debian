# IL-5.10-C — Debian main convergence plan

Status: **PLAN_PREPARED_NOT_INTEGRATED**. Audit completed 2026-10-19 after A PASS
and confirmed B PASS. This is a decision plan, not authorization to merge Debian
main. No canonical Debian branch or release is changed.

## Exact histories and simulated merge

- Main: `558e4b8561c70897a3383e1ac188e70a2d607892`.
- Distribution: `1ff957fac41f158346974d0b290b9396fefb44b6`.
- Actual merge-base: `245c5161ded2452395da7a879bb50853386c933b`.
- Unique commits: 5 on main, 103 on the distribution branch; neither is a simple
  fast-forward of the other. There is a real common ancestor; an unrelated-history
  workaround is unnecessary and must not be inferred from earlier observations.
- Endpoint tree difference: 284 paths. The complete changed-path and commit
  inventories are in [evidence](evidence/IL-5.10/C-convergence.json).

Main's five unique commits are merge #6/558e4b8, license commit d52fc82,
English-default behavior b8b0ebe, and merges #5/9c5b180 and #4/7b7d8d1.
Relative to the common ancestor, its actual tree changes are LICENSE, README.md,
deploy/docker/entrypoint.sh, infra/etc/drumee/conf.d/drumee.json and
target/etc/drumee/conf.d/drumee.json. The last three set
forceDefaultLanguage=true and must be preserved.

`git merge-tree --write-tree --messages origin/main origin/feat/container-distribution`
was executed only in the isolated clone. It returned 1 with one content conflict,
README.md, and object tree `8eba687e8f52aee02634616906448cb60c0a4e8e`.
It creates no commit/ref/index/worktree mutation on a canonical branch. The
unresolved tree is not published or claimed qualified. Its difference from the
distribution endpoint consists only of LICENSE, README and the three English
changes; both minimal-profile subtree objects equal the qualified distribution.
This is merge mechanics evidence, not behavioral acceptance of the whole result.

## Recommended strategy and conflict resolution

Create a new integration branch **from the reviewed main SHA**, then perform a
normal no-commit, no-fast-forward merge of the exact distribution SHA in a fresh
owned worktree. Keep both parent histories. Do not rebase/rewrite the 103 commits,
force an unrelated merge or replace main's entire tree with a checkout. This
future operation requires separate owner authorization and drift checks.

Resolve README by retaining the license link/section and the distribution
instructions together. Its current feature-side IL-4 INTEGRATION_BLOCKED text is
stale: replace it with links/statuses from the current IL-4 and IL-5 evidence.
Do not choose ours/theirs for the whole file. Preserve the main-added root LICENSE.
The entrypoint and two pod configuration files auto-merge, but inspect/test
forceDefaultLanguage=true in all three. These are semantic main behaviors, not
optional whitespace resolutions. Other concurrent paths are README plus those
three files; the package/license addition has no two-sided content conflict.

Freeze and compare the resolved profile subtrees, source locks, plugin acquisition,
SQL roles/bootstrap jobs and operator dispatch against the reviewed distribution
commit. Any intentional difference needs its own rationale and focused tests.
Use ordinary explicit Team/default selection; neither minimal profile may become
the implicit default. Keep main's existing behavior unless a separately reviewed
migration explicitly supersedes it.

## Scope beyond IL-5

The distribution-only range also introduces the seven-role container/packaging
migration, bootstrap and node-runtime packages, role metapackages and substvars,
container/native shared configuration and credentials, infrastructure DNS/TLS
changes, seed/schema initialization, runtime service lifecycle and incremental
schema-patch mechanics. It includes IL-3 inventory/IL-4 canonical enrollment,
SQL privilege separation, portable OCI handling and both minimal profiles.
These cannot be accepted as a small IL-5 cherry-pick.

Version management changes materially: main uses product 1.0.0 and a flat component
manifest; the distribution branch uses release 1.0.57, channel trixie and nested
components. Component changelogs, dependencies, roles and version readers must be
reviewed as one coherent workflow. Do not hand-copy generated version pins.
Review changed schemas/build.sh, schemas/debian/postinst, schemas-patch,
container-populate/schemas-init and native/server postinst/service handling for
upgrade and data-preservation semantics. No customer database is a test fixture.

Installer scripts move from install-native.sh/get-drumee.sh to debian.sh/
containers.sh. APT pool/suites, signing keyring and publish scripts are a separate
release/operations migration; review compatibility aliases and rollback plans.
WireGuard's shared implementation and fixed-port/concurrency invariants remain
required. No host resolver/firewall/CA or production installation is changed here.
Release workflows differ substantially; keep secret gating and review any default
publish target before future execution. No release workflow is run in IL-5.10.

## Debt scope and required test matrix

The simulation preserves all 39 files with historical ShellCheck diagnostics
byte-for-byte from the distribution branch. Existing legacy Dockerfiles/global
PM2 packaging statements also stay on that path. The expected two packaging
failures and 91 lint diagnostics therefore remain visible; remeasure the resolved
candidate rather than assume a green pipeline. The one changed shell heredoc
preserves main's English flag and still needs syntax/parity coverage.

The earlier debt acceptance was limited to minimal-application. It does **not**
authorize adoption of those defects across Debian main, Team, native packaging
or a new release. Owner must explicitly choose separate debt-remediation work or
broader documented risk decisions before main integration/release.

| Area | Required verification of the future resolved candidate |
| --- | --- |
| Merge/provenance | Exact parents, conflict resolution diff, LICENSE retained, profile subtree/locks equal frozen inputs, no generated/src edits |
| Shared configuration | tests/run-all.sh; smoke-config/config-parity/wizard; selector/default Team; schema/example/env/Compose/debconf bridge; English flag in all three sources |
| Version/package metadata | check-versions, meta/make-control --check, native/control-deps, role substvars/package architecture/lint; no automatic version pin rewrite |
| Team container | Real clean seed/role build, container smoke/E2E/demo, explicit owner/resources, TLS/DNS/credentials, native dispatcher and legacy operator/plugin behavior |
| Native channel | Isolated install/verify-debconf/reconfigure/upgrade/lifecycle tests, systemd/init/process shutdown/restart, seed/schema/patch upgrades and preserved config/data |
| Minimal-kernel | 15 targeted TAP, exact 213-artifact inventory/additive acquisition, real enrollment/authentication/Hub/MFS/FileIo/HTTPS/DNS, SQL negative matrix, restart/isolated backup/restore and Chromium |
| Minimal-application | 8 TAP + archive tests, source byte verification, clean image/rebuild inspection, real Nginx/HTTPS/native RPC/ACL/loopback/LAN/interruption/recovery/rollback/isolated no-SMTP restore; optional/required SMTP trust/isolation/recovery refusal |
| Network/security | WireGuard real probe/races and owning coordinator tests when shared files change; no public ports/secrets/account escalation; foreign-resource refusals |
| CI/release boundary | Full resolved-tree packaging and ShellCheck diagnostics, merge required-check policy, release gates; dry checks/build only, no registry/APT/Pages/image/tag publication |

Heavy tests require authorized owned disposable environments. Do not treat a
self-SKIP as successful acceptance. The existing IL-4/IL-5 heavy proofs do not
replace this broader cross-branch qualification. No such complete combined
candidate is tested or claimed in the present planning stage.

## Owner decision prerequisites

Review the complete 103-commit migration and the five main-only commits; approve
the exact proposed parents and README/English/license resolutions. Allocate the
isolated native/container/network/browser test environments, decide whole-repo
historical debt scope and review version/upgrade/publishing policy. Rerun the
matrix and inspect all nonzero/skipped outputs. Recheck branch protection and
required reviews without altering them to force integration. Only a later
explicit decision may merge the qualified candidate into main.

This complete plan permits the distinct Infra alpha.3 candidate qualification
stage. It does not merge Debian main or claim a release-ready combined tree.
