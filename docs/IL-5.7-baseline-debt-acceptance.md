# IL-5.7 — proposed acceptance of Debian baseline debt

Technical recommendation: **temporary, scope-limited acceptance for the IL-5
owner merge decision**. Owner acceptance is **pending**, not recorded as granted.
A failed check remains failed. This document grants no merge or publication right.

Scope: Infra PR #2 `de4b34e99370bf3b9f0d17399db4b2ea3d107677` then Debian PR #7
`86f68a735096a070aa9aa77bc0d79cf0cd1f47af`, using only the explicitly selected
minimal-application profile and its recorded immutable inputs. The recommendation
does not certify historical Team images, native installers, schema patching,
future main convergence, SMTP Internet delivery or production readiness.

## Evidence and decision rule

[IL-5.6 baseline](IL-5.6-ci-baseline.md) used identical ShellCheck 0.11.0/action
settings and identical Trixie/Git tooling on detached baseline 3fb32d8 and IL-5.
The two normalized 91-finding files are byte-identical. Packaging output after
scoped Git trust is identical: 10 passes, 2 failed invariant categories, exit 1.
The hosted final IL-5.6 run [39015907321](https://github.com/drumee/debian/actions/runs/39015907321)
reproduces those results. The original Git-context exit 2 was fixed without
weakening the guard; it is not treated as an accepted packaging violation.

IL-5.7 reverified all 38 locally retained log hashes referenced by the original
IL-5/IL-5.6 manifests, normalized diagnostic identity, artifact integrity and
source-to-evidence correspondence. New sources introduce no executable delta
since qualification. Old defects are evaluated by their reachable effects,
not accepted simply because they predate IL-5.

The builder/operator graph for minimal-application uses its own digest-pinned
Dockerfile, locked Runtime alpha.4, verified bundled plugins and public Infra
APIs. It invokes none of the legacy recipes or schema/admin scripts listed
below. Explicit profile selection prevents the legacy CLI branch from being
used by this installation path. The reference runtime has no PM2 or implicit
SQL/Redis/DNS/Hub/MFS/Finder. Actual cleanroom evidence contains only declared
containers and private ingress. Existing shared renderer/selector tests and
independent RPC/ACL/network/recovery observations reduce reliance on a single
possibly imperfect historical shell test.

This demonstrates no observed effect of these debts on this exact IL-5
composition and same-host rebuild evidence. It does not prove that legacy code
is safe, that static findings are harmless, or that every platform/consumer is
qualified. Existing failing CI remains a compensating visibility control.

## DEB-CI-DEBT-01A — legacy FROM provenance

- **Affected scope:** 11 FROM instructions across deploy/docker's infra-init,
  populate, schemas, server, static, ui and wireguard recipes, plus the two seed
  recipes under scripts. Nine literal references lack a digest; two use
  `${SERVER_IMAGE}`, whose immutable value is not established by the static gate.
  A parameterized reference is not proof that every actual caller uses a mutable
  image, but the required source evidence is absent from the recipe.
- **Contextual severity:** high for rebuilding/releasing those historical images.
  Tags can change and transitively change binaries, security updates and behavior;
  a successful earlier build cannot establish the identity of a later rebuild.
- **Residual risk:** supply-chain substitution, drift and non-reproducible
  legacy releases. These risks remain real outside the qualified new profile.
- **Temporary acceptance rationale:** none of these recipes is reachable from
  the reviewed minimal-application assembly path. Its Node base uses an exact
  digest, runtime/plugin acquisition is integrity-bound, and the optional native
  tools recipe comes from the pinned Infra source with pinned base/packages.
  The two repeated image builds produced identical receipts/IDs on the qualified
  host; source/archive/image hashes were reverified in IL-5.7.
- **Compensation:** explicit profile/build entry point, immutable image-ID
  manifests, source receipt, plugin SRI checks, canonical activation image checks,
  negative mutable-image tests, unchanged failing CI guard. No cross-host
  bit-for-bit guarantee is inferred from same-host rebuilds.
- **Canonical correction:** Debian container-distribution maintainers bind every
  legacy base and caller-supplied SERVER_IMAGE to verified immutable provenance
  through the owning build/release manifests, without bypassing static checks.
- **Required follow-up tests:** all unchanged packaging invariants, clean/offline
  acquisition where supported, repeated image identity, image inventory/SBOM,
  architecture-specific builds and the corresponding Team/seed/native lifecycle
  acceptance. This IL-5 decision does not qualify those builders.

## DEB-CI-DEBT-01B — global unversioned PM2 installation

- **Affected scope:** `deploy/docker/Dockerfile.server`, `npm install -g pm2`.
- **Contextual severity:** high for historical server image supply-chain and
  reproducibility. Global package selection is not locked by this recipe.
- **Residual risk:** a later registry version/transitive dependency changes the
  process manager, startup, permissions or failure/restart behavior.
- **Temporary acceptance rationale:** the new reference application image installs
  only locked Runtime production dependencies and runs `node /app/host.js`
  directly. It never invokes the legacy server recipe or PM2. Canonical supplied
  services provide the qualified process/lifecycle supervision boundaries.
- **Compensation:** locked npm integrity, non-root/read-only/capability-dropped
  runtime, native healthcheck and RPC readiness, restart/failure/rollback tests,
  and the still-failing global packaging check. These do not fix legacy PM2.
- **Canonical correction:** the owning Debian runtime packaging lot replaces the
  unrecorded global acquisition with its canonical versioned runtime package or
  equivalently approved locked artifact. Do not add another installer in IL-5.
- **Required follow-up tests:** package provenance and dependency audit; all
  three historical main/service/factory process modes, native/container start,
  stop/restart/logging, schema job ordering, privilege and recovery regressions.

## DEB-CI-DEBT-02 — historical shell/build diagnostics

Owner: drumee/debian maintainers, in a separate legacy shell/build hardening lot.
Measured scope: 121 selected files, 91 findings in 39 files (20 error-level,
71 warning-level). The exact file, line, code, level and message for every finding
remain in [baseline JSON](evidence/IL-5.6-shellcheck-baseline.json) and
[IL-5 JSON](evidence/IL-5.6-shellcheck-head.json). No global exclusion, lowered
threshold or shell override is proposed. Tool severity is distinct from the
contextual operational risk assessed below.

| Code / occurrences | Contextual risk and expected correction/validation |
| --- | --- |
| SC1087 / 1 | Medium assurance/readability risk in the shared parity-test regex (`$key[[:space:]]`). Scalar expansion plus the literal class works in the inspected Bash path; do not infer a production defect from the diagnostic alone. Use explicit braces preserving the regex and test positive/missing-key parity fixtures. Independent profile/real acceptance reduces sole reliance on this shell test. |
| SC1090 / 3 | Medium/high risk if dynamic source paths become untrusted; also incomplete static analysis. Establish owning source roots and declared shell/source contracts. Test absent/untrusted paths and spaces without executing foreign code. |
| SC2034 / 15 | Low to medium risk: genuinely unused metadata or accepted CLI flags with no effect. Remove only genuinely dead variables or honor documented flags; prove each flag's behavior and preserve external exports. |
| SC2037 / 1 | High legacy schema-operation risk: malformed `opt=... --orphan=...` command in patch-from-manifest. Do not execute it as a qualification workaround. Correct argument construction in its owning SQL patch lot; use disposable DBs to test exact options, manifest errors and no unintended changes. |
| SC2045 / 11 | Medium/high fragility when iterating ls output for copy/build/rotation. Use owning glob/array logic, retaining empty-set semantics; test whitespace, leading dashes, empty directories and generated package contents. |
| SC2046 / 20 | Medium/high argument splitting/globbing risk in historical build/admin scripts. Preserve arguments with quoting/arrays; test spaces, glob characters, missing files and option-like names before any mutation. |
| SC2048 / 1 | Medium/high argument-boundary loss in the historical service wrapper. Forward a true argument vector and test multiple/empty/space-containing arguments. |
| SC2089 / 1; SC2090 / 5 | Medium/high builder command-string quoting risk. Replace quote-containing strings with an explicit argv representation in the owning builder and verify exact flags/values. |
| SC2128 / 2; SC2178 / 1 | Medium diagnostic correctness risk from array/scalar reuse in release-status. Preserve intended reporting types and test zero/one/multiple records using controlled local fixtures. Do not mistake status reporting for release verification. |
| SC2148 / 7 | Medium portability/analysis-assurance risk where a sourced template/library has no declared shell. Establish whether each file is sourced or executed, declare its actual contract locally, and test the intended shells; no global suppression. |
| SC2154 / 2 | High when an unset variable selects build or schema-patch arguments. Validate initialization and required inputs; test failures before filesystem/DB mutations in disposable fixtures. |
| SC2155 / 1 | Medium failure-propagation risk from declaration/export masking command failure. Separate the owning operations and test propagated failures. |
| SC2164 / 11 | High for mutating scripts: a failed cd can redirect later work to the wrong directory. Fail before mutation and test absent/unreadable work directories. |
| SC2166 / 3 | Medium ambiguous compound-test behavior. Preserve intended truth tables with explicit tests/operators and exercise all branches. |
| SC2215 / 1 | Medium/high offline seed-builder invocation risk from a standalone flag. Verify the exact owning command/continuation and rerun disposable canonical seed construction and schema checks. This path is not used by the new profile. |
| SC2221 / 2; SC2222 / 2 | Medium plugin-source dispatch risk from overlapping patterns in historical plugin CLIs. Reconcile their canonical implementation and test every source form plus unsupported/ambiguous inputs. |
| SC3043 / 1 | Medium portability risk from local in a declared POSIX shell. Resolve the owning shell contract or implementation and test it without changing shared variable behavior. |

Some findings affect shared diagnostics/tests, while the most dangerous examples
are legacy administrative/build/SQL operations. Consequently the recommendation
is conditional, not a blanket assertion that all 91 are cosmetic. The new
operator/manifest is independently validated; legacy patch, builder, seed and
release-publication paths remain outside the approved installation graph.

**Residual risk:** historical commands can still fail or operate with unexpected
arguments/working directories when invoked separately. Static findings do not
prove complete coverage. The shared-test warning could obscure future regressions
if that test alone were trusted. Maintain the independent tests and visible CI;
reassess immediately if IL-5 starts calling one of these paths.

**Canonical follow-up:** incremental owner-approved corrections, each with tests
for the affected behavior, followed by the same ShellCheck version/settings over
all 121 paths and full affected build/install/lifecycle checks. A changed
exclusion/threshold is not a correction. No legacy refactor is performed here.

## Additional Infra Layer reserve: not Debian baseline debt

The branch-policy audit discovered existing check
[SonarCloud 117199059647](https://sonarcloud.io/dashboard?id=drumee_infra-layer&pullRequest=2)
on Infra #2: **FAILURE**, Security D and Reliability D on new code (A required).
There are 26 OPEN annotations: 21 in non-shipped test files, five in shipped code;
three CRITICAL, seven MAJOR and sixteen MINOR in Sonar's classification.
This is neither one of the Debian baseline debts nor a passing quality gate.
Full normalized evidence is [retained separately](evidence/IL-5.7-infra-sonar.json).

| Findings | Contextual assessment and required owner disposition |
| --- | --- |
| Seven VULNERABILITY findings, all test-only | Four PATH lookup findings, a CLI prepared-file path finding, a default /tmp fixture root and a generic insecure-protocol finding at the SMTP relay-negative fixture. The latter uses STARTTLS `requireTLS:true` with explicit CA/servername and `rejectUnauthorized:true`; actual TLS/auth/relay-denial tests pass. Do not mistake `secure:false` (STARTTLS rather than implicit TLS) for an authorized plaintext credential transport. These test files are absent from the 40-file npm allowlist. The real runner creates a random private root, supplies its own private prepared file, runs with trusted operator inputs/tools and preserves actual ownership validation. Reuse of these privileged tests with untrusted PATH/arguments is a genuine residual developer-environment risk. Infra/security owner must review/disposition each finding; do not feed arbitrary agent/user-controlled paths into them. No production remote exploit or authorization bypass was demonstrated by this audit. |
| S2871 in shipped external-gateway validator | The default sort intentionally compares a finite schema key set against the exact ASCII `id,revision,root`. Locale-aware human alphabetization is not its semantic task. Public positive/negative plugin-contract tests pass. This supports a contextual false-positive recommendation, not an automatic Sonar resolution. |
| S2681 in shipped probe | The compact early-return guard intentionally makes subsequent statements run only when the callback is not already settled. Actual failure/readiness evidence remains valid. Owner should review the control flow/readability; no edit or issue closure is performed here. |
| Shipped S3776/S3358/S7778 | Complexity, nested ternary and adjacent push maintainability findings in composition/planning. These increase future-review risk; canonical contract/unit and lifecycle evidence is retained. Any owner-selected refactor requires its own targeted/full corresponding regressions and new artifact provenance. |
| Remaining test BUG/code-smell findings | Test nullability, Error construction, polling, formatting and image tag-plus-digest style. Prior actual scenarios pass; SHA256 digest identity remains authoritative even with a descriptive tag. Owner must assess them in the test-harness context, rather than weakening immutable-image policy to silence a style rule. |

No production canonical defect requiring a workaround was demonstrated. Equally,
this audit does not pronounce Sonar's open security issues closed or accepted.
The Infra owner must explicitly disposition this additional reserve before the
merge/publication decision, or commission a separate correction/requalification
lot. No Sonar rule, finding state, quality gate or source code is modified here.

## Proposed acceptance record and expiry

| Field | Proposed record |
| --- | --- |
| Technical recommendation | Accept the three characterized Debian debt entries temporarily for review/integration of this exact explicit IL-5 profile only |
| Owner acceptance | Pending explicit decision; no approval is manufactured by this report |
| Additional Infra reserve | Separate explicit Sonar/security disposition required; not covered by the Debian baseline comparison |
| Scope boundary | No historical Team rebuild/release, production/Oxy-form deployment or SMTP spool recovery certification |
| Invalidating event | Executable/dependency/resource/entry-point change, drift/new diagnostic, changed host-engine topology, or a consumer selecting different artifacts |
| Reassessment | Re-run affected contracts/integration and compare static results; update immutable receipts and owner risk decision |
| Tracking | DEB-CI-DEBT-01A/01B under Debian packaging migration; DEB-CI-DEBT-02 under Debian shell/build hardening; Sonar findings stay with Infra/security owners |

Branch rules currently impose neither these checks nor a human-review count;
that absence is not owner acceptance. Current technical output is
**READY_FOR_OWNER_MERGE_DECISION**, subject to the explicit conditions in
[final validation](IL-5.7-final-validation.md). Existing CI failures stay visible.
