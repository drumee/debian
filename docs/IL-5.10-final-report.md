# IL-5.10 — canonical integration and alpha.3 decision dossier

Final technical status: **READY_FOR_ALPHA3_PUBLICATION_DECISION**.
No publication is authorized or performed. This status presents the verified
candidate and explicit reservations for an owner decision, not a clean global
security attestation or approval to deploy.

## Stage results and revisions

| Stage | Result | Evidence/action |
| --- | --- | --- |
| A — Debian merge audit | PASS | Merge 1ff957f equals qualified 490c4b0 root tree; source/lock verified; fresh targeted/shared tests pass |
| B — Infra canonical integration | PASS | Expected-head guarded ordinary merge of PR #2 at 9e41666, independently confirmed by GitHub; exact aa9057f tree and tarball preserved |
| C — Debian main convergence | Plan prepared, not integrated | Actual common ancestor, full inventories, one README conflict in isolated merge-tree simulation, main-only behavior and broad test/debt matrix documented |
| D — alpha.3 | RELEASE_CANDIDATE_QUALIFIED | Clean canonical-main clone, two identical packages, types/public exports, isolated actual preparation, negative contracts, quality/audits pass |

- Infra canonical main: `9e4166618ca519e5d9b9e58f5191d37c5fd56462`.
- Infra consumed/qualified source: `aa9057f224f4ae5cf80d777e3cb2fad092193fb1`,
  retained in merge ancestry and its feature reference.
- Infra evidence branch docs/il510-release-evidence:
  `da42c0f3e1ce46419ec4895815a540f592e6b4d8`, documentary PR #10.
- Debian integrated feat/container-distribution:
  `1ff957fac41f158346974d0b290b9396fefb44b6`, PR #7 already merged;
  reviewed HEAD `490c4b0a28ffb35da6ff248402139b5f600c793f` has the same tree.
- Debian main remains `558e4b8561c70897a3383e1ac188e70a2d607892`.
- Debian reports are on docs/il510-integration from the actual integrated branch;
  final documentary SHA is identified by that PR/delivery, without a circular
  self-embedded hash.

Original working directories and pre-existing server/UI changelog edits,
AGENTS.md/.aws are preserved. All work uses isolated clones; there is no reset,
force push, unrelated resource deletion or canonical Debian-main modification.
Server Runtime, Oxy-form and production are not changed.

## Reports

- [A: exact Debian integration audit](IL-5.10-A-debian-integration-audit.md),
  with [merge/archive/test receipt](evidence/IL-5.10/A-debian-audit.json).
- [B: canonical Infra integration](https://github.com/drumee/infra-layer/blob/da42c0f3e1ce46419ec4895815a540f592e6b4d8/docs/IL-5.10-B-infra-integration.md),
  including the preflight, guarded merge and broader Sonar scope.
- [C: convergence plan](IL-5.10-C-debian-convergence-plan.md), with the
  [complete commit/path inventory](evidence/IL-5.10/C-convergence.json).
- [D: clean-main release candidate](https://github.com/drumee/infra-layer/blob/da42c0f3e1ce46419ec4895815a540f592e6b4d8/docs/IL-5.10-D-alpha3-release-candidate.md),
  with the source/npm allowlist, integrity, audits, consumer and CI evidence.
- [Oxy-form resumption inputs and unqualified operations](IL-5.10-oxy-form-handoff.md).

## Tests actually executed

| Scope | Result and counting boundary |
| --- | --- |
| A application TAP | 8 passed |
| A minimal-kernel TAP | 15 passed |
| A plugin archive Python cases | 8 passed |
| A shared Debian checks | 331 passed |
| D Infra unit TAP | 161 passed |
| D public contract TAP | 24 passed, overlapping subset; not added to 161 |
| D ESLint | 0 errors, 65 visible historical warnings, 0 new findings |
| D package guard | 40-member allowlist/secret/import/dependency/offline-consumer checks passed |
| D npm audits | Production 0, development 0 reported vulnerabilities |
| D installed consumer | 8 assertions, real private idempotent preparation, strict TS 5.9.3 NodeNext passed |
| Extra isolated contract negatives | 6 refused; private binding/RPC/image/dependency/secret checks passed |
| Candidate reproducibility | Two packs byte-identical; all 40 members equal the Debian receipt |

All final canonical commands pass with no skip. B pre/post-merge unit/contract
runs also pass but are not added again to the totals. The extra consumer's first
absence check used the wrong working directory and failed; the test was corrected
to use its own directory, then passed, without changing production source or
weakening a rule. The report/evidence retains that initial harness error.

No new heavy LAN/SMTP/HTTPS/application activation/Chromium run is asserted.
Earlier Infra 87 and Debian 126 real assertions are retained by demonstrated
source/package/consumer input identity. Previous kernel 260 functional assertions,
3 Chromium scenarios and 16 SQL negatives remain their historical records.
This mission's real private preparation is not presented as a browser/LAN test.

## Candidate and acquisition identities

@drumee/infra-layer@0.1.0-alpha.3: 98,808 bytes packed, 353,683 unpacked, 40 files,
AGPL-3.0-only, Node >=22, CommonJS/public declarations, zero production dependencies.

```text
npm SHA256:
7385ee7acbc6582746b2f8d8713ce174f7136e7531e7e57221df06a15c906a75
npm SRI:
sha512-ZZIxqtHsFA0tCwAR6vcGa3iOttFYTkHCS4rKN4UtPApLPDkq41FJ0xJWKfWLEWVUlvM3JZldb1aGrhyKMiM9Pw==
```

The canonical main source archive has SHA256
8bacfbc856cbf49d3722b1a22e78d5c520fdb45215bf96831e6e3326f7513468
and source SRI
sha512-avsnkxzQulvLzyG7JNtXvvDygm0HTTtxdsv82TTEjx9RrIfQfut7xLwFmX7XGQDMa4Ht7g02tc9ENpPWrGEgyw==.
Its 225 files equal aa9057f, but archive metadata/root differ. Debian deliberately
keeps its exact aa9057f URL and source SRI faoNlMWB…hVqA==. Never substitute either
source SRI for the npm SRI or silently rewrite a consumer lock.

The canonical-main tarball is retained locally at
/tmp/drumee-il510-evidence/release-candidate/drumee-infra-layer-0.1.0-alpha.3.tgz.
It is not committed/uploaded as a release. A fresh pack after the documentary
Infra additions still yields the exact same integrity and no new lint finding;
no shipped member changes. Recreate from canonical 9e41666 if temporary files
expire. The observed npm registry still has alpha.1/alpha.2, with next=alpha.2;
alpha.3 remains unpublished. Registry availability must be rechecked at release.

## CI/security and explicit reservations

Canonical-main [Quality 39254718852](https://github.com/drumee/infra-layer/actions/runs/39254718852)
has all five jobs successful. Native
[CodeQL 39254717741](https://github.com/drumee/infra-layer/actions/runs/39254717741)
executes and publishes successfully. PR aa9057f reports no new changed-code alert;
global Security/Dependabot inventories remain HTTP 403. Dependabot config/update
jobs succeed; the visible runner migration notice is not a vulnerability alert.
No protection, scanner, rule, severity or annotation disposition is modified.

External Sonar remains ERROR. Its complete main inventory contains 227 historical
open records, broader than the three mapped IL-5 logical cases. Of 23 vulnerability
classifications, one is the reviewed mandatory STARTTLS fixture; the 22 others
point to pre-existing base statements and are not accepted automatically. The
remaining 224 records are a separate repository-security triage scope. New
operational Quality/CodeQL governance is not a blanket false-positive decision.
The owner must take this broader inventory and alert-access limits into account
before publication; this dossier does not claim all historical risks are resolved.

Debian retains its two historical packaging failures and 91 ShellCheck diagnostics
(20 errors/71 warnings). A PASS does not turn those jobs green. The original
acceptance was limited to the minimal application profile and does not authorize
all of main's Team/native/release behavior. The convergence plan exposes 5 versus
103 unique commits, 284 path differences, one actual README conflict, the retained
LICENSE/English defaults and the required broader tests. No combined candidate
is declared qualified or merged into Debian main.

## Owner decisions and next operations

Review/merge the documentary reports separately if desired; no new docs PR is
merged automatically. Decide publication only after reviewing the canonical
source/receipt, broader historical security/debt reservations, full Security alert
snapshot or access limitation, publisher/version access and the desired next
channel. Publication/npm/image/tag operations still require a distinct explicit
authorization. No artifact is published by this mission.

Keep Debian's source acquisition until a distinct post-publication consumer
migration verifies the registry tarball/source mapping and repeats required
installed/build/acceptance tests. Approve the wider Debian-main convergence
scope and complete its matrix in a separate mission. Neither integration implies
that old Team packages or native installer transitions are globally approved.

Oxy-form needs explicit distribution/plugin selection and authorized target,
existing host Nginx/HTTPS/static site preserved, native /-/ and /-/svc/, verified
private Runtime ingress and real SMTP upstream/secrets/mailbox/DNS/reception/
bounce qualification. Forms stay disabled until its own acceptance passes.
Its repository/status is not changed; OF-02 and Oxymotion D0 are not executed.
No production host, resolver, firewall, system trust or secret is modified.


## Documentary closing checks

The [Infra evidence PR #10](https://github.com/drumee/infra-layer/pull/10) and
[Debian reports PR #8](https://github.com/drumee/debian/pull/8) remain open for
review, not automatically merged. On documented heads da42c0f/f154c47, Infra's
five Quality jobs and CodeQL succeed; its documentation-only Sonar gate also
passes without clearing the canonical-main historical inventory. Debian's
application-contract and shared-suite jobs succeed; packaging/lint still fail
with exactly 10/2 checks and the identical 91 baseline diagnostics. Direct job
log comparison confirms no addition. [Debian check snapshot](evidence/IL-5.10/closing-documentary-ci.json).
Closing ledger/evidence additions change no profile, lock or shipped module;
actual latest PR-head checks remain available from the linked PRs.
