# IL-5 release and integration handoff

Current status after IL-5.7: **READY_FOR_OWNER_MERGE_DECISION**.
See [final integration validation](IL-5.7-final-validation.md),
[proposed debt acceptance](IL-5.7-baseline-debt-acceptance.md) and
[Oxy-form handoff](IL-5.7-oxy-form-handoff.md).

Historical IL-5.6 status: **READY_FOR_MERGE_WITH_BASELINE_DEBT**.
See [CI stabilization](IL-5.6-ci-stabilization.md) and
[baseline comparison](IL-5.6-ci-baseline.md).

Historical IL-5.0–5 status: **READY_FOR_TECHNICAL_REVIEW**. No merge or publication authorization is
implied. The selected evidence is in [qualification](IL-5-qualification.md).

## Review branches and integration order

1. Review Infra Layer `feat/il5-external-gateway` against `main`. It owns additive
   application/external-gateway contracts, consumer-selected secrets and public
   CA projection, composition/observation/recovery policy, types and tests.
2. Review Debian `feat/il5-minimal-application` against
   `feat/container-distribution`, the audited IL-4 baseline. It owns the explicit
   operator profile, shared selector/JSON reader/schema extension, immutable
   Runtime/plugin images, public API operator and acceptance/runbooks.
3. Integrate the canonical Infra change first. Debian already uses immutable
   source `c6ef6e9b8d33921ffa39c289490067adfc63a8b0` plus archive SRI, so it requires
   neither a sibling checkout nor unpublished npm resolution. A future approved
   registry release can replace that source pin through a distinct lock/provenance
   change and installed-consumer/cleanroom validation. Published alpha.2 cannot
   substitute for the IL-5 contract.
4. Integrate Debian only after both reviews and dependency agreement. Do not
   merge either PR automatically. The feature branches retain ordinary additive
   commits; no history rewrite or release tag is created.

[Infra Layer PR #2](https://github.com/drumee/infra-layer/pull/2) and
[Debian PR #7](https://github.com/drumee/debian/pull/7) are open and mutually linked.
The PR commits tabs and final execution report identify exact review HEADs; the immutable implementation/artifact pins
below do not change when evidence-only commits are appended.

## Checkpoint commits

Infra Layer:

- Audit: `d0b53e8fd170864544b4723f8c933e4d9cf69bcb`.
- Public contract: `11cd32c4f456a17d80818b98be4ea7d908bec677`.
- Real lifecycle/SMTP: `cf4ac5735f7ec0d48e48a9a752951f77f7284c74`.
- Source-aware acceptance: `d4a883a847bae84e560f1385c0775bd12c18379a`.
- Installed consumer: `f0f48aace5331919448a65e91800a3120637261d`.
- Candidate metadata/provenance: `c6ef6e9b8d33921ffa39c289490067adfc63a8b0`.

Debian:

- Audit: `5f727f784971ae9511a8749dbb861bd460932ec2`.
- Operator/image/profile: `9ffb273ba428cea88134740bb99d241e8da5b4a5`.
- Actual operator acceptance: `d3d85a51a50964950e6a685675b7a36a260e5065`.
- Final immutable Infra alignment: `cfb993dd3979122e4ff7915b8627ff669ef90a96`.

Server Runtime remains read-only at
`f961f6214432c2e6dbbcde2b926544c076935950`, published alpha.4. Oxy-form remains
read-only at `7f368473d4f350a88e844b841f97a175b53921b8`. The original Infra sibling
checkout remains clean on alpha.2; IL-5 is in its separately cloned feature
branch. Debian's two pre-existing changelog edits and untracked AGENTS.md remain
untouched and uncommitted by this work.

## Candidate package and provenance

Local-only `@drumee/infra-layer@0.1.0-alpha.3` tarball:

- Filename: `drumee-infra-layer-0.1.0-alpha.3.tgz`.
- Size: 98,007 bytes; unpacked 351,221 bytes; 40 allowlisted files.
- SRI: `sha512-+voNVLiQa+Cb9k0M/frJIkejFRqAJPa/d7Z42iqG+waU1oupgDL/r4FrvK09ADhW4pjKfYNlm7FNdc0ixvf5Eg==`.
- SHA1: `a039a39ae9bb77bf2a9b7a5b89e7e771388ba491`.
- Source: `c6ef6e9b8d33921ffa39c289490067adfc63a8b0`.
- Empty production dependency set; AGPL-3.0-only and historical attribution retained.
- Root public API unchanged; lifecycle exports/types include the opt-in addition.
- Installed offline consumer: strict NodeNext type checks and real idempotent
  preparation without activation, no checkout imports.

The source archive has a distinct SRI from `npm pack`, because GitHub and npm
contain different allowlisted metadata/layout. Debian locks the source archive
SRI in its new profile lock. The Runtime version/SRI remains explicit and is
validated before image assembly. Plugin inputs use immutable archive SHA512,
ID/source revision and a generated image inventory; dependencies must be bundled.
No mutable tag, historical factory database or hidden development checkout is
needed. Actual image IDs and selected source are in the cleanroom evidence.

## Delivered operator behavior

Select `drumee-ctl --profile minimal-application` explicitly. Team remains the
default; minimal-kernel source/locks are unchanged. The profile provides plan,
validate, install, status, doctor, stop, start, restart, proxy-config, cold backup,
isolated restore and compatible rollback through public Infra APIs. Mutations
require explicit execution and owner-bound identity/resource policy. Unknown
installations are never adopted, and unrelated Docker resources are never
removed. Protected snapshots preserve revision-bound non-secret configuration.

The reference image composes the published native Runtime registry, dispatcher,
service server and authorizer. Default anonymous public RPC works; protected RPC
is denied without its canonical adapters. Plugin inventory must agree with the
immutable image. There is no second authentication/password/session/ACL system.
The default profile installs no Hub/MFS/Finder/SQL/Redis/DNS/container gateway.

The external proxy uses an explicitly private 127.0.0.1 TCP publication with
preserved `/-/` and `/-/svc/` routes. HTTPS/certificates/renewal remain its owner's
responsibility. Infra readiness proves native private ingress, not external TLS;
actual host Nginx/CA/SAN and independent LAN denial were separately qualified.

Optional SMTP/DKIM composes the existing native stack. Application trust contains
only public CA and authorized submission secret. Queue and key ownership survive
backend failure; optional/required mail readiness is explicit. No-SMTP cold
backup/isolated restore is qualified. SMTP spool backup/restore fails closed with
`SMTP_RECOVERY_UNQUALIFIED`, with no invented preservation claim.

## Review reservation: existing global packaging CI debt

`scripts/check-packaging.sh` returns 10 passes and 2 failures on both the final
IL-5 tree and isolated baseline `3fb32d8`, with identical findings: legacy Team
image FROM entries without digests and global PM2 installation. IL-5 does not
introduce either failure or weaken that gate. The new profile has pinned images.
This technical feature review does not claim that repository-wide packaging CI
is fully green; the existing debt requires its owning distribution follow-up.

## Decisions still separate from technical review

- npm publication, release tagging, container registry publication and PR merges
  require their separate authorized release operation; none is performed here.
- Production proxy configuration, production credentials, target host binding
  verification and permanent deployment remain operator/consumer decisions.
- Oxy-form may resume OF-01R only through its own approved work, selecting the
  reviewed artifact/source and providing actual application plugins/config and
  controlled SMTP upstream credentials/recipient acceptance. Internet delivery,
  SPF/DKIM/DMARC deployment and bounce behavior are not IL-5 proof.
- SMTP spool restoration remains unsupported. No automatic secret reset,
  resource adoption, pruning, image/schema/engine downgrade is authorized.
- IPv6 publication is unsupported; actual isolation evidence is Docker 29.2 on
  the documented host topology and must be repeated on another target.
- Oxymotion D0 is neither started nor qualified. This application distribution
  does not replace Hub/MFS/Finder/crawling/agentic distribution acceptance.

## GitHub submission and environment observations

Both feature branches and evidence commits were pushed without rewriting history.
CLI creation initially returned `Resource not accessible by personal access token
(createPullRequest)`; the already-authorized GitHub connector created both PRs.
No credential was changed or additional user permission required. Neither PR is
merged. Existing CI reservations above remain visible.

Final resource inspection shows no IL-5-owned container or network remaining.
Testbox still has only the three previously observed stopped historical
initialization containers; no IL-5 service/resource was installed there. Build
images and the local npm archive are retained as explicitly identified review
artifacts. The cleanroom worktree remains clean.

## IL-5.6 CI follow-up (2026-10-17)

The earlier local qualification and failed-attempt evidence above remain intact.
The initial hosted run exposed a packaging Git ownership/context failure and
91 ShellCheck findings. Identical-tool baseline comparison now proves zero IL-5
ShellCheck regressions (20 errors/71 warnings, 39 files, 121 paths). The minimal
workflow correction trusts only its exact mounted workspace in the actual job
HOME and pins the already-qualified ShellCheck action/version without changing
severity, scope or exits. Packaging itself is unchanged.

Corrective CI [39013263757](https://github.com/drumee/debian/actions/runs/39013263757)
on `1b1480dd8ec15c92442ed2208d36c3904ec36b4f` completes: application-contract and
suite SUCCESS; packaging FAILURE with exactly baseline 10 passes/2 failures and
no fatal Git context; lint FAILURE with exactly the baseline diagnostics. These
are actual failing GitHub conclusions, not waived successes. Local revalidation
passes 5 application TAP, 8 Python archive cases, 15 minimal-kernel TAP and 331
shared checks. Infra Layer HEAD remains de4b34e and its previous qualification is
reused; no contract/distribution/secret/network/SMTP behavior changed.

The two remaining historical debt packages belong to drumee/debian maintainers:
DEB-CI-DEBT-01 (legacy image packaging compliance) and DEB-CI-DEBT-02 (legacy
shell/build hardening), defined in the stabilization report. Maintainers must
explicitly assess that debt and any required branch checks before integration.
Infra Layer precedes Debian; no automatic merge, publication or D0 is performed.

## IL-5.7 final owner-decision audit (2026-10-18)

The expected Infra de4b34e / Debian 86f68a7 HEADs and actual bases were verified,
with no executable drift. Immutable source/package/plugin/image integrity and
38 prior log hashes match their evidence. Targeted confirmations pass: 141 Infra
TAP, 5 application TAP, 8 archive cases, 15 minimal-kernel TAP, package allowlist
and a fresh installed consumer with strict types/8 real-preparation assertions.
Heavy unchanged integration evidence is reused without inflating totals.

The branch-policy audit goes beyond mergeable=true: protected=false, successful
GraphQL branchProtectionRule=null, no active/inherited rulesets or effective
branch rules, and no required review count/check observed. Detailed classic REST
reads returned 403 and were not interpreted as absence; independent authorized
reads establish the snapshot. No protection is changed. Reinspect before merge.

The Debian CI failures stay characterized baseline debt, proposed for temporary
acceptance only for the explicit new profile; owner acceptance remains pending.
The broader audit additionally records Infra SonarCloud FAILURE (26 OPEN issues,
Security D/Reliability D), separately from Debian debt. Its test-only/shipped
contexts and residual risks require explicit Infra/security owner disposition;
no finding or gate was suppressed or silently accepted. The actual check remains
red. No production canonical defect requiring a workaround was demonstrated.

Integration remains owner-authorized Infra #2 → Debian #7 on its current
feat/container-distribution base, followed by a distinct reviewed main-convergence
lot. Alpha.3 remains unpublished; source→npm migration requires explicit new
lock/provenance validation. Oxy-form has not selected a compatible replacement
and is not declared unblocked. SMTP Internet/provider/DNS/recipient and spool
recovery conditions remain pending; OF-02, production and D0 are not executed.

## IL-5.9-B — new Debian consumer qualification (2026-10-18)

This additive update supersedes the **active consumer pin** above; historical
source/package identities and qualification attempts remain unchanged evidence.
Infra PR #2 is now `aa9057f224f4ae5cf80d777e3cb2fad092193fb1`. Debian consumes
that exact GitHub archive, whose newly measured source SRI is
`sha512-faoNlMWBO05FM+ozsuGu9tqFgq/IYc9WJwb4KCyZcZiTlEIrgJ9QLqLxslTADdipaItg02r2f6qFG07HDxhVqA==`.
The rebuilt, unpublished npm alpha.3 SRI is separately
`sha512-ZZIxqtHsFA0tCwAR6vcGa3iOttFYTkHCS4rKN4UtPApLPDkq41FJ0xJWKfWLEWVUlvM3JZldb1aGrhyKMiM9Pw==`.
The source lock never substitutes that npm SRI for the GitHub archive.

[Source selection](IL-5.9-B-source-selection.md),
[consumer change inventory](IL-5.9-B-consumer-realignment.md) and
[qualification](IL-5.9-B-qualification.md) record source/lock commit a7a756f,
clean-build/acceptance source `ccaa839bf13ab163025e868b21f16516c87d1ff9`, two
identical same-host build receipts, actual image inspection, 126 real acceptance
assertions, 8 application TAP, 8 plugin archive cases, 15 historical-kernel TAP,
331 shared checks and 8 isolated npm-consumer assertions with strict types.
The 260/3-Chromium/16-SQL historical kernel evidence is retained, not rerun.
Packaging/lint still fail on the identical two/91 historical findings.

Application image:
`sha256:d44327e37d37c612257822684a870d05d7f90fdae649b2dcbfb8e9f0566e7955`.
Native tools image:
`sha256:075a3c53d14f9a71c827f285564518dde41e29faa0cc9e58f4cc126cd3dda4cd`.
These local images contain a disposable acceptance plugin; they are not a
published application-specific distribution or Oxy-form deployment.
Runtime alpha.4, native HTTP/RPC prefixes, loopback publication and public Infra
lifecycle APIs remain fixed. SMTP queue/secret persistence is observed;
SMTP_RECOVERY_UNQUALIFIED still refuses spool recovery. No Internet delivery is
qualified. Infra's GitHub security chain is observed; external Sonar cleanup
remains an independent owner task, with no annotation disposition in this mission.

Status: READY_FOR_OWNER_MERGE_DECISION, subject to current checks, explicit owner
acceptance of historical debt/security reservations and the separate merge
operation. Order remains Infra #2 → Debian #7 into feat/container-distribution;
convergence to Debian main and future registry migration require separate review.
No publication, merge, Oxy-form resumption, production operation or D0 occurred.

## IL-5.10 — canonical integration and alpha.3 decision dossier

[Final IL-5.10 report](IL-5.10-final-report.md) records A PASS after the actual
Debian merge, confirmed Infra #2 merge at
`9e4166618ca519e5d9b9e58f5191d37c5fd56462`, the unexecuted
[Debian-main convergence plan](IL-5.10-C-debian-convergence-plan.md) and the
clean-main qualified, still-unpublished alpha.3 candidate. Debian continues to
pin aa9057f/source SRI unchanged; Runtime alpha.4 and minimal-kernel are untouched.
Source and npm SRI remain separate. Canonical package bytes retain
ZZIxqtHs…9Pw== after two identical clean-main packs and isolated-consumer/types
qualification. No migration to a presumed npm alpha.3 dependency is made.

Technical status is READY_FOR_ALPHA3_PUBLICATION_DECISION, not publication
permission. The broader 227-record legacy Sonar main inventory, partial global
Security/Dependabot visibility, 65 visible ESLint warnings and Debian's two/91
historical debt remain explicit owner-review inputs. New Quality/CodeQL passes
are not a blanket acceptance of those records. No Debian-main merge, release tag,
image/npm publication, production action or D0 occurs.

[Oxy-form handoff](IL-5.10-oxy-form-handoff.md) supplies exact integrated sources,
existing profile/CLI, artifact mapping and remaining target/SMTP qualification.
It leaves the static site/forms and Oxy-form repository untouched; the consumer
is not declared accepted or resumed.
