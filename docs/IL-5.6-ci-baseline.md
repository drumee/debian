# IL-5.6-A — comparative CI baseline

Audit performed 2026-10-17 (Europe/Paris). This report precedes the workflow fix;
[stabilization](IL-5.6-ci-stabilization.md) records the corrective CI run.
No baseline, historical script, application contract or dependency is changed.

## Revisions and original CI

- Debian PR #7 HEAD: `6687d7c19f686e15971cd6deec3ba1bfbf8eb0ab`.
- Baseline: `3fb32d86ce336c886235c23b9632a140a2dc3045`.
- CI checks the PR merge `012833fd28cf147114df21ba8776ec157c259a5d`;
  its tracked tree equals HEAD because the base is its ancestor.
- Infra PR #2 remains `de4b34e99370bf3b9f0d17399db4b2ea3d107677`.
- Original Infra sibling remains clean main `bef9a37…`. Runtime/Oxy-form are untouched.
- Debian's existing server/UI changelog edits and untracked AGENTS.md are excluded.

[Original run 38967915038](https://github.com/drumee/debian/actions/runs/38967915038):
packaging FAILURE (exit 2 before scanning), lint FAILURE (ShellCheck), suite
SUCCESS, minimal-application-contract SUCCESS. Full decoded job logs were
retrieved with `gh run view --repo drumee/debian 38967915038 --log` and retained
locally. The [comparison evidence](evidence/IL-5.6-ci-comparison.json) records
hashes and initial job IDs/versions; normalized diagnostics contain no credentials.

## Identical tools and scan settings

| Component | Observed exact version/revision |
| --- | --- |
| Runner | 2.337.0, ubuntu-24.04 image 20261012.334.1 |
| actions/checkout@v4 | `11d5960a326750d5838078e36cf38b85af677262` |
| actions/setup-node@v4 | `49933ea5288caeca8642d1e84afbd3f7d6820020` |
| ludeeus/action-shellcheck@master | `00b27aa7cb85167568cb48a3838b75f4265f2bca` |
| ShellCheck stable observed | 0.11.0 |
| Packaging container | `debian:trixie-slim@sha256:020c0d20b9880058cbe785a9db107156c3c75c2ac944a6aa7ab59f2add76a7bd` |
| Packaging Git, CI and reproduction | 2.47.3, package `1:2.47.3-0+deb13u1` |
| Packaging CA package | 20250419 |
| Lint Git on hosted runner | 2.55.0 (not involved in ShellCheck analysis) |
| Host Git used to make isolated clones | 2.39.5 |
| Host Bash/find used for both ShellCheck replays | 5.2.15 / GNU findutils 4.9.0 |

Both read-only clones use the same Trixie tool image
`sha256:e40111e22399124db7cb569e5769be32eaccf3f8f1415bf31f11ce1f37139fab`.
It applies the workflow's apt install of Git/CA to the exact base digest; measured
Git/package versions match the original job. It is local only, not published.

ShellCheck is the official v0.11.0 Linux x86_64 archive, extracted under /tmp.
Archive SHA256 `8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198`;
binary SHA256 `4da528ddb3a4d1b7b24a59d4e16eb2f5fd960f4bd9a3708a15baddbdf1d5a55b`.
The exact action.yaml source was read at the observed action SHA. Its `Run the
check` block was extracted unchanged except resolving github.action_path to the
private executable directory. Settings match the original job: scandir `.`,
severity `warning`, individual-file checks, no added files/options, and existing
ignore_paths `builder/src target`. File extensions, executable/shebang detection
and default `.git`, `.go`, mvnw exclusions remain exactly those of the action.
No new exclusion, source following, shell override or lowered severity is used.

Clones contain only tracked files and `.git`, matching fresh CI before dependency
installation; the lint job does not install node_modules. Both scans select the
same 121 paths, including extensionless executable `bin/drumee-ctl`.
JSON changes only the output format; a separate gcc-format HEAD replay matches
all 91 original CI diagnostics exactly, including columns/messages. Three JSON
column positions differ from gcc because of tabs; baseline and HEAD JSON are
nevertheless byte-identical and requested file/line/code/level keys agree.

## Measured comparison

| Control | Baseline | IL-5 HEAD | Delta/classification |
| --- | --- | --- | --- |
| Packaging in untrusted mounted CI context | fatal, exit 2 | fatal, exit 2 | Same environment defect; no invariants reached |
| Packaging with exactly workspace trusted | 10 pass, 2 fail; exit 1 | 10 pass, 2 fail; exit 1 | Byte-identical output; historical compliance debt |
| ShellCheck 0.11.0, warning threshold | 91 diagnostics, exit 1 | 91 diagnostics, exit 1 | 0 additions, 0 removals; historical debt |
| New application profile | Not applicable | Original CI SUCCESS | Added feature; revalidation follows in stabilization report |

ShellCheck: 20 errors and 71 warnings across 39 files in both snapshots.
[Baseline JSON](evidence/IL-5.6-shellcheck-baseline.json) and
[HEAD JSON](evidence/IL-5.6-shellcheck-head.json) are sorted by file/line/column/code
with level/message retained. Both SHA256:
`07570bf6645697be3d55940643d76063a84baf512eec1b911f88e6652a4b0c13`.
The scan inventory, grouped codes and zero-delta evidence are in the comparison JSON.

Examples explicitly verified on both trees: tests/config-parity.sh SC1087,
admin/build.sh SC2034/SC2089/SC2090, meta/build.sh SC2045, schemas/build.sh
SC2034/SC2045, schemas-patch/build.sh SC2034/SC2166/SC2045 and
schemas-patch/bin/patch-from-manifest.sh SC2037/SC2046/SC2154/SC2155/SC2164.
Other repeated debt includes missing shell declarations (SC2148), `ls` iteration
(SC2045), word splitting (SC2046), unguarded cd (SC2164), unused variables
(SC2034), array/string confusion and POSIX-local use. No historical script is
refactored or suppressed by IL-5.6; the owning follow-up is identified below.

## Demonstrated packaging cause

CI logs show the correct workdir `/__w/debian/debian`, its runner workspace bind
mount, root container execution, installed `/usr/bin/git` 2.47.3, a successful
`git init`, fetch and checkout, and a valid `git log` inside checkout. This is
not a Git-absent fallback archive or missing-workspace checkout.

Checkout writes safe.directory using a temporary HOME below `/__w/_temp`; the
next shell step instead uses the job's `/github/home`. The runner-owned workspace
is therefore not trusted by Git when the root container runs the guard. The
guard's stderr suppression hides Git's underlying `detected dubious ownership`,
leaving its intentional fatal-context message. The guard itself is unchanged.

The same read-only mount at `/__w/debian/debian` is owned 1000:1000 in local
reproduction, with uid 0 container execution and HOME=/github/home. Both clones
have `.git`. A temporary checkout-style global config permits Git in that
context; the job's independent global config returns Git exit 128 with the
explicit dubious-ownership diagnostic. The packaging guard then returns exit 2.
Adding only `safe.directory=$GITHUB_WORKSPACE` to the job's actual global config
makes Git/listing succeed and reaches all 12 invariants. A separately mounted
neighbor repository remains untrusted (Git exit 128), proving no wildcard trust
or disabled ownership protection. Both corrected outputs are byte-identical.
The corrective hosted job confirms worktree owner 1001:1001, .git owner 0:0
and uid 0 execution; it reaches the same baseline findings. See the stabilization
report for exact logs and job conclusions.

## Reproduction and ownership boundaries

Isolated clones `/tmp/drumee-il56-{baseline,head}` were checked out detached at
exact revisions. No branch reset or baseline write was performed. Context tests
mount both read-only, disable networking, and remove only their own ephemeral
containers with `--rm` and the `org.drumee.il56.owner=ci-stabilization` label.
The same executable and action-derived script run independently from each clone.

Local evidence paths/hashes, argv/settings and exact selected file inventories
are recorded in comparison JSON. Expected nonzero scanner/action statuses are
captured as results; they are not reclassified as success. A reproduction driver
returning zero means that all expected refusal/debt assertions were met, not
that packaging/ShellCheck became green. Full original logs remain unchanged.

Historical packaging debt belongs to the existing Debian container distribution
migration (`AGENT-BRIEF.md`, `docs/distribution.md`, ROADMAP), not Infra Layer:
legacy Team FROM references without digests and `npm install -g pm2`. Historical
ShellCheck debt belongs to a distinct Debian legacy shell/build-script hardening
lot (owner: drumee/debian maintainers). Neither lot is silently included in IL-5.6.
The final merge decision must explicitly accept those known failing checks or
complete their owning follow-ups; no merge/publication is authorized here.
