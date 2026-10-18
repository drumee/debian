# IL-5.7 — final integration validation and owner decision dossier

Decision: **READY_FOR_OWNER_MERGE_DECISION**, with the reserves and prerequisites
below. This is not owner acceptance, a green-CI declaration, merge permission,
production authorization or a release. No protection has been changed.

## 1. Exact examined revisions

Audit: 2026-10-18. Both PRs are open, non-draft and unmerged. Their inputs equal
the mission references; no substantive intervening change was found.

| Repository / ref | Exact revision | Role |
| --- | --- | --- |
| Infra Layer feat/il5-external-gateway, PR #2 | `de4b34e99370bf3b9f0d17399db4b2ea3d107677` | Reviewed HEAD, unchanged by this mission |
| Infra Layer main | `bef9a379754bcf9a46fed8bcb6f88fe1f775c739` | Actual PR #2 base |
| Debian feat/il5-minimal-application, PR #7 | `86f68a735096a070aa9aa77bc0d79cf0cd1f47af` | Reviewed HEAD before these documentation-only commits |
| Debian feat/container-distribution | `3fb32d86ce336c886235c23b9632a140a2dc3045` | Actual PR #7 base and IL-5.6 baseline |
| Debian main | `b8b0ebe7082e1ad2366f3a7997712f5da5bba127` | Default branch, not silently substituted as PR #7 base |
| Runtime main / published alpha.4 | `f961f6214432c2e6dbbcde2b926544c076935950` | Unmodified owner |
| Oxy-form feat/of-01-canonical-audit | `7f368473d4f350a88e844b841f97a175b53921b8` | Unmodified blocked consumer evidence |

GitHub reports both PRs MERGEABLE, but mergeStateStatus is UNSTABLE. The latter
reflects failed checks; absence of textual conflicts is not proof that protections
or quality requirements have passed. No local or remote merge was performed.
The original Infra sibling remains clean main; its separate feature checkout
is clean. Debian's pre-existing server/UI changelog diffs and untracked AGENTS.md
are preserved and excluded. These new commits contain only documentation/evidence.

## 2. Branch protections and actual checks

[Policy evidence](evidence/IL-5.7-branch-policy.json) combines independent read-only
sources, rather than relying on mergeable=true:

- Branch metadata returns protected=false and empty required-status contexts for
  Infra main and Debian feat/container-distribution.
- Effective branch-rule endpoints return HTTP 200 and `[]` for both destinations.
- Repository ruleset collections including parent/inherited rulesets return
  HTTP 200 and `[]` for both repositories.
- GraphQL successfully returns branchProtectionRule=null for Infra main, Debian
  feat/container-distribution and Debian main, with no GraphQL errors. Debian
  main's effective rules are also empty.
- Formal PR review collections are empty and reviewDecision=null. No required
  approving-review count, required CI job or required Sonar check is observed
  on these destinations. Owner approval remains a task-level prerequisite.

Detailed classic-protection REST reads returned 403 for the fine-grained CLI
credential; the connector's administration read is also unavailable. Public
unauthenticated reads require authentication. Those failures are retained and
are **not** interpreted as proof of no protection. The successful GraphQL null
rules, branch metadata and active/inherited-rule reads establish the observed
state independently. Reinspect immediately before an owner-authorized merge:
rules can change after this timestamp. No rule or bypass setting is modified.

Accordingly, the currently failing jobs do **not** produce a demonstrated
GitHub branch-policy block. This is not a recommendation to ignore them. If a
required rule is added or the owner has a stricter acceptance policy, integration
must wait for its prerequisites without changing/neutralizing the rules.

| PR / check at examined HEAD | Actual conclusion | Qualification meaning |
| --- | --- | --- |
| Debian minimal-application-contract | SUCCESS | Locked profile contracts and archive cases |
| Debian suite | SUCCESS | Shared checks |
| Debian packaging | FAILURE | Git context now valid; baseline-identical 10 passes / 2 failed invariant categories |
| Debian lint | FAILURE | Shell syntax passes; baseline-identical 91 ShellCheck findings |
| Infra SonarCloud Code Analysis | FAILURE | 26 OPEN annotations, Security D / Reliability D on new code; additional explicit owner/security reserve |

Debian reference [run 39015907321](https://github.com/drumee/debian/actions/runs/39015907321)
is completed with overall FAILURE on the exact examined HEAD. Its push-triggered
run has the same four outcomes. Infra has no Actions workflow in this branch;
its external [Sonar check](https://sonarcloud.io/dashboard?id=drumee_infra-layer&pullRequest=2)
is check 117199059647. Local tests are not substituted for a passing external
check. New documentation-only push checks are assessed separately in the final
execution/PR handoff; the executable workflow remains the examined one.

## 3. Immutable dependency and artifact inventory

Debian still selects the exact source archive
`https://codeload.github.com/drumee/infra-layer/tar.gz/c6ef6e9b8d33921ffa39c289490067adfc63a8b0`,
SRI `sha512-/XFgDPrCJkuk9sEbLf5GGJ1Z55mueK85t77swiB4i/0s6OvdlrGqd9MUE9e8AnyMOi0nBUOl+W2h8FlqDZdX2Q==`.
It is not alpha.2, latest, a mutable branch or an implicit sibling checkout.
The archive was downloaded afresh and its bytes match the existing lock.

| Artifact | Verified identity |
| --- | --- |
| Runtime npm alpha.4 | Registry gitHead `f961f6214432c2e6dbbcde2b926544c076935950`; SRI `sha512-bOZ/v6/4mQ/FPa8iE21polPx2PjJWFYTKqTz+2duqxI2ljpviemNgOtpwkxF4j/1Xn/1aVIxdvVCc8Tch2ctEQ==` |
| Infra local npm alpha.3 candidate | 98,007 bytes, 40 files, zero production dependencies; SRI `sha512-+voNVLiQa+Cb9k0M/frJIkejFRqAJPa/d7Z42iqG+waU1oupgDL/r4FrvK09ADhW4pjKfYNlm7FNdc0ixvf5Eg==` |
| Qualified application image | `sha256:b98ae69b0a39ce4edb26fefa2a60ba28620ab12fe6ccd28d2f6daade4be6901d`, source label Debian `cfb993dd3979122e4ff7915b8627ff669ef90a96` |
| Qualified native-tools image | `sha256:d8dab923b53d0eede951c0ad6b1741807ebbfa45944206b577b943045147cee0`, source label Infra `c6ef6e9b8d33921ffa39c289490067adfc63a8b0` |
| Qualification plugin archive | SRI `sha512-cCo/f6Aw+RSGCc9M07ZVVLjKNbwfopOMIqrqJUlqmMu2pYgz5WICbCSBAptOGo4EWMY0x6FZwqw/z/lFDRPg4w==`, source cfb993d; explicitly disposable test input, not Oxy-form |

Actual local image IDs and source/plugin-digest labels were inspected, not inferred
from their descriptive tags. The tarball and plugin bytes were rehashed. The
complete allowlist, SHA256/SRI inventory, registry snapshot and log hashes are in
[validation evidence](evidence/IL-5.7-validation.json). Test files are not shipped
in the npm candidate. Candidate package/license/exports/types/provenance are
unchanged from c6ef6e9 through de4b34e; the same npm SRI is obtained at both.

Evidence corresponds to earlier executed commits deliberately, not fictitious
runs of the final documentation HEAD:

- Infra real application: f0f48aace5331919448a65e91800a3120637261d → de4b34e has
  no changes to shipped code/types/lock or executable tests.
- Debian cleanroom: cfb993dd3979122e4ff7915b8627ff669ef90a96 → 86f68a7 has no
  changes to application profile, selector, config or acceptance implementation;
  subsequent changes are workflow/evidence/docs. Minimal-kernel code remains
  unchanged from its qualified distribution baseline.
- All 19 IL-5, 10 comparative IL-5.6 and 9 stabilization IL-5.6 recorded local
  log SHA256 values were checked successfully (38 retained logs). The two
  normalized 91-diagnostic files remain byte-identical. Repetition is not added
  to original test counts.

## 4. Targeted final qualification

Fresh IL-5.7 commands/results, no code changes:

| Command / scope | Result |
| --- | --- |
| Infra npm test | 141 TAP passed, zero failed/skipped |
| Infra npm run test:package | 40-file allowlist, no undeclared production imports/dependencies; isolated installed package check passed |
| Infra test/application/package-consumer.js with the recorded immutable app image and explicit TS compiler | 8 assertions; strict NodeNext types; actual idempotent preparation without activation; zero failure |
| Debian npm test --prefix profiles/minimal-application | 5 TAP passed, zero failed/skipped |
| Python plugin-artifact.test.py | 8 cases passed |
| Unchanged minimal-kernel inventory/alignment/profile tests | 15 TAP passed, zero failed/skipped |

The new installed-consumer result identifies source de4b34e and the exact same
alpha.3 SRI. It installs the packed artifact offline with no checkout imports.
These are targeted confirmations, not a rerun of the real HTTP/LAN acceptance.

| Required property | Retained real proof plus current confirmation |
| --- | --- |
| Loopback only / LAN denied | Prior exact Docker/ss publication and independent testbox nonce control + ECONNREFUSED; current manifest/negative public-binding tests pass; unchanged code and actual image ID verified |
| Native allowed/denied RPC, unchanged prefixes | Actual native public RPC/403 through host Nginx with CA/SAN verification; unchanged runtime/host/proxy fragment; current profile tests pass |
| No implicit Hub/MFS/Finder/SQL/Redis/DNS/gateway | Original actual one-application composition; current public planning/composition has no implicit services or dependencies |
| Canonical legacy Infra contracts | Current 141 units and retained real gateway/services/lifecycle 17/17/16 tests, unchanged source |
| Optional SMTP/DKIM and secrets | Actual STARTTLS/SASL/relay denial, private DKIM network, no host mail ports, authorized projections and optional/required readiness proof; current secret/dependency/public-CA tests pass |
| External-resource adoption denied | Actual unknown-root/owner/tamper refusals; current public negative contracts unchanged; lifecycle preparation remains canonical |
| Rollback and recovery boundaries | Retained real configuration rollback, failed startup, interruption/recovery and isolated no-SMTP restore; artifact/type/lifecycle checks pass |
| SMTP_RECOVERY_UNQUALIFIED | Same canonical application mail backup/restore guard and existing refusal evidence; no alternative spool-copy path introduced |

Heavy real application 86 assertions, cleanroom 90 assertions, minimal-kernel
260 functional assertions/3 Chromium scenarios/16 SQL negatives and Runtime 56
TAP remain prior acquired qualification, not newly claimed runs. No executable
change or provenance drift justified rerunning them. Actual LAN evidence is
specific to the documented Docker 29.2/host topology; another deployment must
repeat it. Secret generation values are never placed in this report.

## 5. Debt and risk decision

[Baseline-debt acceptance dossier](IL-5.7-baseline-debt-acceptance.md) evaluates
both packaging categories and every ShellCheck rule family, with affected scope,
severity, residual risk, compensation, expected owning correction and follow-up
tests. High-risk legacy build/admin/schema findings are not labeled harmless.
The temporary recommendation applies only to the isolated explicit application
installation graph; old Team release/migration commands remain unqualified.
Owner acceptance is pending. Failure records and CI exits stay intact.

The additional Sonar reserve is not baseline debt: 26 OPEN issues, 21 test-only,
five shipped, with all seven VULNERABILITY-class findings in test-only files.
The shipped findings concern deterministic schema-key sorting, an early-return
probe guard, complexity, ternary formatting and push style. The dossier explains
context, including the private real test roots/arguments and non-shipped tests;
it does not close or suppress issues. Sonar's Security/ Reliability D ratings
remain actual failing check results. Infra/security owner must explicitly review
and disposition this reserve or commission a separate correction/requalification.
No production canonical defect requiring a workaround was demonstrated here;
no functional or contract correction is within this mission.

## 6. Integration sequence and conditions

1. **Owner decision first:** assess the characterized Debian debt and separately
   disposition Sonar/security findings. Recheck exact heads, current rules,
   conflicts, reviews and checks. No formal approval is fabricated by this report.
2. **Infra #2 → main:** functionally qualified, conflict-free and with no enforced
   branch checks/review count observed, but external quality gate remains red.
   Integrate only under a separate explicit owner authorization. Prefer preserving
   reviewed ancestry so pinned c6ef6e9 remains reachable in canonical main; a
   different merge strategy must preserve the immutable dependency's availability
   or undergo an explicit verified pin/provenance transition. Do not delete its
   supporting source ref blindly. No merge/tag is performed here.
3. **Debian #7 → feat/container-distribution:** keep its actual 3fb32d8 base and
   c6ef6e9/SRI pin. Infra integration establishes canonical ownership availability;
   it does not publish npm alpha.3, change Debian's pin, pass its failing jobs or
   accept its debt automatically. Reinspect the merge result and immutable
   artifacts before any installation claim. Do not retarget to main silently.
4. **Separate Debian convergence:** main and feat/container-distribution diverge
   from `245c5161ded2452395da7a879bb50853386c933b`: main has 3 unique reachable
   commits, the distribution branch 87 before IL-5 integration. The distribution
   comparison spans 215 files, far beyond this feature. Main-only history includes
   two seed-builder merge commits and b8b0ebe's English-default change. Prepare a
   separately reviewed convergence PR after IL-5, inspect the actual combined
   tree, reconcile those intents and rerun full affected packaging/native/kernel/
   browser/recovery checks. Do not cherry-pick IL-5 onto a main lacking its
   distribution architecture or import unqualified changes automatically.

## 7. Publication preparation, not publication

Registry inspection during this audit lists Infra stage/alpha.1/alpha.2 only
(next=alpha.2, latest=alpha.1). Local metadata alpha.3 is available for preparation;
it is not a published dependency. Recheck registry immediately before a later
owner-authorized publication; never overwrite an occupied version.

The current npm candidate is the 40-file built-in-only production package with
explicit root/lifecycle exports/types, AGPL attribution and source provenance.
The actual packed SRI and isolated-consumer/type/preparation result are verified.
After owner integration/disposition, prepare a clean canonical release checkout,
verify no unreviewed payload/version/license changes, pack/audit/test the exact
archive and record the final source/gitHead and SRI. If bytes change, replace the
receipt and repeat affected qualification; do not reuse the old fingerprint.
Publication identity/access/provenance/release authorization are future owner
operations. No npm/image/tag publication occurs in IL-5.7.

A later Debian source→npm migration is a distinct owned change: explicit
`@drumee/infra-layer@0.1.0-alpha.3`, lockfile registry tarball SRI, release-source
mapping, build receipt/provenance assertions and guide/tests must remain coherent.
GitHub-source SRI and npm SRI are different artifacts, not interchangeable.
Update package/lock and hardcoded build/test provenance only after verifying
package equivalence and installed-consumer/cleanroom contracts. Preserve Runtime
alpha.4 and its integrity; do not use latest or a floating branch. The current
working source dependency is retained until that migration is separately decided.

## 8. Oxy-form and D0 handoff

[Oxy-form handoff](IL-5.7-oxy-form-handoff.md) distinguishes the currently available
immutable canonical source from the consumer's still-pending selection. Oxy-form's
unchanged report remains BLOCKED_DISTRIBUTION. Actual OF-01R resumption requires
its owner to choose the compatible source/package and Debian profile, package its
real plugin, review its existing host Nginx/certificates and repeat native RPC,
private-ingress and controlled SMTP integration. OF-02 is not executed here.

Unresolved inputs remain explicit: verified upstream STARTTLS, separate submission
and relay secrets, authorized sender, controlled qualification inboxes, actual
SPF/DKIM/DMARC receiver results, delivery and bounce evidence. Application SMTP
backup/restore remains SMTP_RECOVERY_UNQUALIFIED; restart/queue persistence does
not qualify spool restoration. No oxymot.fr modification or deployment is made.

Transferable proof covers private application ingress/native dispatch/ownership/
artifact/lifecycle and SMTP composition/trust/isolation only. It is not evidence
that Oxymotion D0, Hub/MFS/Finder/crawling/agentic/business/Internet-mail scenarios
are qualified. D0 is not begun or declared validated.

## 9. Final decision and delivery boundary

READY_FOR_OWNER_MERGE_DECISION is justified by verified functional invariants,
unchanged executables, matched artifacts/evidence, characterized risks and
explicit integration prerequisites. It is **not BLOCKED_BY_BRANCH_POLICY** under
the successfully observed current rules, and it is not an unconditional merge
recommendation while Sonar/debt acceptance remain pending. If the owner rejects
those risks or applies stricter policy, follow that decision without a workaround.

Only documentary commits are pushed on the existing Debian feature branch.
Previous reports are preserved and the IL-5 release handoff links this dossier.
Infra/Runtime/Oxy-form branches remain unchanged. Tests use only owned isolated
resources; no protection change, merge, release or permanent deployment occurs.
