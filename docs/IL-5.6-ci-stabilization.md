# IL-5.6 — CI stabilization and final merge qualification

Decision: **READY_FOR_MERGE_WITH_BASELINE_DEBT**.
This is readiness for the maintainers' merge decision, not merge authorization.
Infra Layer must be integrated first, then Debian. Neither PR is merged here.

## Starting revisions and scope

Debian PR [#7](https://github.com/drumee/debian/pull/7) starts at
`6687d7c19f686e15971cd6deec3ba1bfbf8eb0ab`, on `feat/il5-minimal-application`,
base `feat/container-distribution`, audited baseline
`3fb32d86ce336c886235c23b9632a140a2dc3045`.
Infra Layer PR [#2](https://github.com/drumee/infra-layer/pull/2) remains exactly
`de4b34e99370bf3b9f0d17399db4b2ea3d107677` with a clean feature checkout.
Runtime and Oxy-form source/branches remain untouched. Existing Debian server/UI
changelog edits and untracked AGENTS.md remain outside these commits; their
original diff was saved and compared byte-for-byte after validation.

IL-5 implementation is retained. IL-5.6 changes only workflow environment/tool
selection and documentation/evidence. No historical script, packaging invariant,
profile, dependency, runtime image, route, secret or capability contract changes.

## Exact environment and diagnosis

The [comparative baseline report](IL-5.6-ci-baseline.md) contains measured
reproduction and normalized per-file diagnostics. Both detached clones use
identical commands, tools and read-only mounts. They remain clean.

Original [run 38967915038](https://github.com/drumee/debian/actions/runs/38967915038)
ran checkout `11d5960a326750d5838078e36cf38b85af677262`, setup-node
`49933ea5288caeca8642d1e84afbd3f7d6820020`, ShellCheck action
`00b27aa7cb85167568cb48a3838b75f4265f2bca`, ShellCheck 0.11.0 and packaging Git
2.47.3 (`1:2.47.3-0+deb13u1`). The corrected run resolves the same action SHAs
and executable versions. Hosted lint Git is 2.55.0; local clone Git is 2.39.5.

Packaging uses the unchanged Trixie digest
`sha256:020c0d20b9880058cbe785a9db107156c3c75c2ac944a6aa7ab59f2add76a7bd`.
Local reproduction installs the same Git/CA packages into that base, producing
explicit local-only tooling image
`sha256:e40111e22399124db7cb569e5769be32eaccf3f8f1415bf31f11ce1f37139fab`.
No local host package or global trust configuration is changed.

The original CI really has Git and `.git`. Checkout succeeds at
`/__w/debian/debian`; it trusts the repository using its own temporary HOME.
The root job's later shell uses `/github/home`, without that temporary trust.
Git rejects the runner-owned worktree as dubious. The guard intentionally hides
Git stderr and emits its fatal context diagnostic, exit 2 before any invariant.

The corrective hosted job now records the actual mount:

```text
git version 2.47.3
/__w/debian/debian
uid=0(root) gid=0(root) groups=0(root)
1001:1001 /__w/debian/debian
0:0 /__w/debian/debian/.git
```

This confirms the ownership mismatch at the correct workspace, not a missing
checkout. Local reproduction uses foreign owner 1000:1000 versus container uid 0;
that reproduces the same Git trust boundary. Both baseline and HEAD initially
return Git 128 / guard 2. After trusting only the exact workspace, both reach
10 successful invariants and the same 2 historical failures, exit 1. A separate
mounted neighbor remains untrusted (Git 128), excluding wildcard trust.

## Correction and commits

- Diagnostic comparison: `8a64533be404f4375e578695c6e952ced8a64c99` (`docs(il5.6): reproduce CI packaging and ShellCheck against baseline`).
- Workflow correction: `1b1480dd8ec15c92442ed2208d36c3904ec36b4f`
  (`fix(ci): trust only the packaging workspace and pin qualified ShellCheck`).
- The closing qualification/documentation commit follows these without rewriting
  history; exact final review HEAD is available in the PR commits and final report.

`.github/workflows/ci.yml` now:

1. Sets the packaging step's working-directory explicitly to github.workspace.
2. Records bounded Git/pwd/id/stat context, without credentials.
3. Adds only `safe.directory=$GITHUB_WORKSPACE` to the isolated job's actual
   global Git config. No `*` trust or disabled Git safety is introduced.
4. Verifies the Git root and that the guard is a tracked file, then invokes the
   unchanged guard as the last command. Its nonzero exit is still propagated.
5. Pins the ShellCheck action to the exact already-used commit and executable
   input to v0.11.0. Severity warning, scan scope, exclusions and exit semantics
   are unchanged. No ShellCheck script correction is required: there is zero
   IL-5 diagnostic delta.

The actual corrected run block was extracted from the workflow and executed
under `sh -e` against both read-only snapshots. Both return exit 1 with 10/2 and
no fatal context. This is a negative/debt result, not a simulated success.

## Comparative results

| Control | Baseline 3fb32d8 | IL-5 / correction | Classification |
| --- | --- | --- | --- |
| Packaging with untrusted mounted root context | fatal exit 2 | same fatal exit 2 | Demonstrated environment defect, corrected |
| Packaging with scoped workspace trust | 10 pass / 2 fail, exit 1 | identical output, exit 1 | Historical distribution compliance debt |
| ShellCheck 0.11.0 | 91 findings, exit 1 | identical 91 findings, exit 1 | Historical shell-script debt; zero additions/removals |
| Application profile contracts | Not present | 5 TAP + 8 archive cases pass locally and in hosted CI | Added feature remains qualified |

ShellCheck analyzes the same 121 paths. The 91 findings comprise 20 errors and
71 warnings in 39 files. Baseline and HEAD JSON are byte-identical after sorting
file/line/column/code with level/message retained. A gcc replay matches all
original CI messages, including columns. The corrected hosted run also matches
all 91 original gcc messages exactly. No claim relies on assuming a diagnostic
is historical; both revisions were scanned with the same actual action logic
and executable. All detailed findings remain in the two normalized evidence files.

## Revalidation commands and results

Commands run with Node 22.22.0 and authorized local test access:

```sh
npm test --prefix profiles/minimal-application
python3 tests/minimal-application/plugin-artifact.test.py
node --test profiles/minimal-kernel/inventory.test.js profiles/minimal-kernel/test/*.test.js
tests/run-all.sh
```

Selected results: 5 application TAP tests; 8 Python archive cases; 15 unchanged
minimal-kernel TAP tests; 331 shared checks. All pass with zero failures/skips.
The 331 aggregate includes renderer/configuration/CLI selection/wizard/version
and native dependency checks; it is not added to TAP totals. Shell syntax also
passes as a separate hosted lint step. ShellCheck and packaging nonzero results
remain explicitly reported, not counted among these successes.

Packaging comparison uses the exact workflow Trixie base and Git packages;
ShellCheck uses the exact upstream action `Run the check` block with original
settings. The action version is frozen rather than changing diagnostics to
obtain a pass. Machine evidence with settings, normalized findings, tool/log
hashes and selected final results is in
[comparison JSON](evidence/IL-5.6-ci-comparison.json) and
[stabilization JSON](evidence/IL-5.6-ci-stabilization.json).

`git diff 6687d7c HEAD -- profiles config bin deploy tests scripts/check-packaging.sh release-manifest.yaml`
is empty for the corrective code. This proves no changes to `/-/`, `/-/svc/`,
strict 127.0.0.1 publication, public ports, implicit capabilities, minimal-kernel,
SMTP/DKIM, permissions or secrets. Public manifest/selector and minimal-kernel
tests revalidate those interfaces. Immutable Infra source remains
`c6ef6e9b8d33921ffa39c289490067adfc63a8b0`, source archive SRI
`sha512-/XFgDPrCJkuk9sEbLf5GGJ1Z55mueK85t77swiB4i/0s6OvdlrGqd9MUE9e8AnyMOi0nBUOl+W2h8FlqDZdX2Q==`;
Runtime remains published alpha.4. Pins were asserted against the unchanged lock.

No contract/distribution file changed, so the already recorded heavy IL-5 runs
are reused: Infra units 141, gateway/services/lifecycle 17/17/16, application 86
assertions; Debian cleanroom 90 assertions; real minimal-kernel 260 functional
assertions/3 Chromium scenarios/16 SQL negatives; Runtime 56 tests. They were not
rerun or inflated into new IL-5.6 totals. Infra PR #2 needs no correction.

## Hosted corrective CI: exact results

[Run 39013263757](https://github.com/drumee/debian/actions/runs/39013263757),
code HEAD `1b1480dd8ec15c92442ed2208d36c3904ec36b4f`, completed with overall
**FAILURE**, intentionally retained as the true GitHub result:

| Job | GitHub conclusion | Measured meaning |
| --- | --- | --- |
| minimal-application-contract | SUCCESS | Locked acquisition, 5 tests and 8 archive cases pass |
| suite | SUCCESS | Shared checks pass |
| packaging | FAILURE | Git context valid; exactly baseline 10 pass / 2 fail; exit 1, no FATAL |
| lint | FAILURE | Shell syntax passes; exactly baseline 91 ShellCheck findings |

The complete corrective logs were downloaded and compared. Its packaging output
from the invariant header through the footer is byte-identical to the baseline
container output. Its gcc ShellCheck diagnostics equal the original CI and local
replay. GitHub status has not been made green by suppression or exit-code masking.
The closing documentation commit does not alter this tested workflow; its latest
CI run is checked separately in the execution handoff/final PR description.

## Historical debt owners and merge conditions

| Follow-up | Owner / boundary | Completion criterion |
| --- | --- | --- |
| DEB-CI-DEBT-01: legacy image packaging compliance | drumee/debian maintainers; existing container-distribution migration in AGENT-BRIEF.md/docs/distribution.md | Fix exact-source/base-image/global-runtime-install provenance in the legacy Dockerfiles; all 12 unchanged packaging checks pass with retained runtime behavior |
| DEB-CI-DEBT-02: legacy shell/build hardening | drumee/debian maintainers; separate historical build/admin/schema-script lot | Resolve the 91 diagnostics at the same severity/scope, with behavior-specific build/install tests; no global exclusions or weakened threshold |

These are identified follow-up work packages in this report, not newly opened
issues or automatically authorized refactors. Packaging findings include 11 FROM
lines across legacy recipes (including parameterized SERVER_IMAGE lines) and
one global PM2 install; they are two failing invariant categories, not twelve
separate test failures. Shell debt affects the explicitly listed 39 files in the
normalized evidence, including the scripts mentioned in the mission.

Before actual integration, maintainers must review/accept this reproduced debt
or complete its owning follow-ups, and respect Infra Layer → Debian order. If
branch protections require both failing jobs to be green, those policy-required
prerequisites still need resolution before an effective merge. No branch rule,
CI gate or failure record is changed to bypass them. Technical readiness with
baseline debt does not mean a green repository-wide CI or publication approval.

## Changed files and attempt history

IL-5.6 changes the CI workflow, creates this report, the comparative report and
normalized evidence JSON, and appends the current qualification/handoff status.
The exact committed file list is:

- `.github/workflows/ci.yml`
- `docs/IL-5.6-ci-baseline.md`
- `docs/IL-5.6-ci-stabilization.md`
- `docs/IL-5-qualification.md`
- `docs/IL-5-release-handoff.md`
- `docs/evidence/IL-5.6-ci-comparison.json`
- `docs/evidence/IL-5.6-ci-stabilization.json`
- `docs/evidence/IL-5.6-shellcheck-baseline.json`
- `docs/evidence/IL-5.6-shellcheck-head.json`

No historical implementation script is changed. Original IL-5 failed attempts/results remain in their ledger;
the new reports supplement them rather than overwrite them.

The initial hosted fatal-context and ShellCheck failures are preserved. An early
local invocation of the actual workflow block omitted GitHub's mounted HOME and
failed to create `/github/home/.gitconfig`; adding a private tmpfs HOME mount to
match the runner corrected the harness, without changing the workflow further.
An initial upstream source URL used action.yml instead of action.yaml (404);
the immutable action.yaml was then fetched and inspected. The local gh version
lacks `run list --event`; the run was retrieved using its REST event/head filter.
None of these acquisition/harness attempts is counted as a passing gate.

All reproduction containers are removed via --rm and operate only on private
clones/read-only mounts. No production/testbox deployment, npm/image/tag release,
merge, Runtime/Oxy-form modification, secret change or Oxymotion D0 operation
occurs in IL-5.6. Debian's unrelated edits are preserved.
