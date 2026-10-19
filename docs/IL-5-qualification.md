# IL-5 qualification ledger

Current IL-5.10 status: **READY_FOR_ALPHA3_PUBLICATION_DECISION**.
See [the final dossier](IL-5.10-final-report.md): Debian's integrated tree is
verified, Infra PR #2 is now canonically merged, the alpha.3 package is qualified
but unpublished, and Debian-main convergence remains a separate plan.
No source-to-npm lock migration or production action is performed.


Historical IL-5.9-B status: **READY_FOR_OWNER_MERGE_DECISION**, with unchanged
historical Debian CI debt. See [consumer realignment](IL-5.9-B-consumer-realignment.md)
and [new integrated qualification](IL-5.9-B-qualification.md): immutable aa9057f
source, 126 actual acceptance assertions, verified images/rebuild receipts,
strict isolated consumer, zero new ShellCheck/packaging findings. The new run
does not replace or relabel historical qualification evidence below.

Historical status after IL-5.7: **READY_FOR_OWNER_MERGE_DECISION**.
See [final integration validation](IL-5.7-final-validation.md),
[proposed debt acceptance](IL-5.7-baseline-debt-acceptance.md) and
[Oxy-form handoff](IL-5.7-oxy-form-handoff.md).

Historical IL-5.6 status: **READY_FOR_MERGE_WITH_BASELINE_DEBT**.
See [CI stabilization](IL-5.6-ci-stabilization.md) and
[baseline comparison](IL-5.6-ci-baseline.md).

Historical IL-5.0–5 status: **READY_FOR_TECHNICAL_REVIEW**. All IL-5.0–5 feature gates below pass;
the unchanged global packaging debt is disclosed separately. Evidence below distinguishes implementation,
executed tests, measured qualification and future consumer acceptance.
No production, Oxy-form or Server Runtime source was modified. No npm package,
image or tag was published, PR merged or Oxymotion D0 executed.

## Source and artifacts

The audited baselines are Infra Layer published alpha.2
`bef9a379754bcf9a46fed8bcb6f88fe1f775c739`, Debian
`3fb32d86ce336c886235c23b9632a140a2dc3045`, Runtime alpha.4
`f961f6214432c2e6dbbcde2b926544c076935950` and read-only Oxy-form
`7f368473d4f350a88e844b841f97a175b53921b8`.
The application contract is additive; neither historical profile guard is
relaxed. Debian's minimal-kernel source and lock remain unchanged.

Debian's final canonical source pin is
`c6ef6e9b8d33921ffa39c289490067adfc63a8b0`, source archive SRI
`sha512-/XFgDPrCJkuk9sEbLf5GGJ1Z55mueK85t77swiB4i/0s6OvdlrGqd9MUE9e8AnyMOi0nBUOl+W2h8FlqDZdX2Q==`.
There is no executable/type/lock difference from implementation checkpoint
`cf4ac5735f7ec0d48e48a9a752951f77f7284c74`; subsequent commits add tests and
candidate documentation/provenance. Final integration source `cfb993dd3979122e4ff7915b8627ff669ef90a96` and images
are recorded in [the cleanroom receipt](evidence/IL-5-distribution-images.json).
Two successive builds of this exact input produced identical receipts/image IDs,
then all 9 groups / 90 assertions passed; ignored outputs leave Git clean.
Application image: `sha256:b98ae69b0a39ce4edb26fefa2a60ba28620ab12fe6ccd28d2f6daade4be6901d`;
native tools: `sha256:d8dab923b53d0eede951c0ad6b1741807ebbfa45944206b577b943045147cee0`.

Local candidate: `@drumee/infra-layer@0.1.0-alpha.3`, unpublished. Registry read
on 2026-10-16 lists stage, alpha.1 and alpha.2 only. The exact locally packed
candidate has 40 allowlisted files, zero production dependencies, 98,007 bytes,
SRI `sha512-+voNVLiQa+Cb9k0M/frJIkejFRqAJPa/d7Z42iqG+waU1oupgDL/r4FrvK09ADhW4pjKfYNlm7FNdc0ixvf5Eg==`.
Its metadata/runtime/capabilities/types/provenance are pinned; reports/tests are
not shipped in the npm archive. This does not authorize publication.

Runtime remains published alpha.4 with SRI
`sha512-bOZ/v6/4mQ/FPa8iE21polPx2PjJWFYTKqTz+2duqxI2ljpviemNgOtpwkxF4j/1Xn/1aVIxdvVCc8Tch2ctEQ==`.
No custom dispatcher, session, identity or ACL implementation substitutes for it.

## Selected test counts

Counts describe distinct suites and selected runs; repeated attempts and nested
assertions are not added together. Functional assertions and browser scenarios
are not TAP tests.

| Suite | Result | Unit |
| --- | --- | --- |
| Infra Layer `npm test` | 141 passed, 0 failed/skipped | TAP tests: 127 legacy + 14 additive cases |
| Infra gateway `npm run test:gateway` | 17 passed, 0 failed/skipped | TAP tests, including one actual Chromium case |
| Infra native services `npm run test:services` | 17 passed, 0 failed/skipped | TAP tests, including SMTP/DKIM capture/queue/upstream TLS |
| Infra lifecycle `npm run test:lifecycle` | 16 passed, 0 failed/skipped | TAP tests, selected isolated replay; first run disclosed below |
| Infra `npm run test:lifecycle:gateway` | 4 passed, 0 failed/skipped | Functional HTTPS/job scenarios, contract fixture |
| Infra `npm run test:application` | 11 groups / 86 direct assertions passed | Actual application lifecycle, includes cleanup ownership guards |
| Installed tarball application consumer | 8 assertions passed; strict NodeNext types pass | Real preparation without activation, no checkout imports |
| Debian application `node --test profiles/minimal-application/test/*.test.js` | 5 passed, 0 failed/skipped | TAP tests |
| Debian plugin archive Python suite | 8 passed, 0 failed/skipped | Python cases |
| Debian root JSON Schema check | 3 passed | Structural assertions; canonical nested semantics tested separately |
| Debian `tests/run-all.sh` | 331 passed, 0 failed | Existing shell/config/package/selector aggregate; not TAP |
| Debian `scripts/check-packaging.sh` | 10 passed, 2 pre-existing failures, identical on baseline | Global packaging invariants, unchanged CI debt |
| Runtime read-only `npm test` | 56 passed, 0 failed/skipped | TAP tests |
| Debian unchanged minimal-kernel inventory/profile | 15 passed, 0 failed/skipped | TAP tests |
| Debian cleanroom application acceptance | 9 groups / 90 assertions passed | Real operator, host proxy, independent LAN client, SMTP and recovery |
| Debian retained real minimal-kernel acceptance | 31 stage groups; 260 functional assertions, 24 browser assertions | Fresh 11, restart 10, restored 10; 3 actual Chromium scenarios, 16 SQL negatives |

The gateway's one browser case is included in its 17 TAP tests. The three kernel
browser scenarios are repeated lifecycle checkpoints of the same unchanged
browser scenario, not three new features. Testbox performs two assertions per
application network run: successful nonce control route and refused application
LAN connection. These are already included in the functional reports, not an
additional remote acceptance total. Testbox hosts no IL-5 deployment.

## Real application lifecycle and network

Selected source-aware Infra run: `f0f48aace5331919448a65e91800a3120637261d`;
[`evidence/IL-5-application.json`](evidence/IL-5-application.json).
Public API prepare is persistent/private and does not start daemons. The real
published Runtime accepts the native public RPC and rejects a protected RPC
with 403. Stop/start, compatible config update/rollback, failed startup, real
SIGKILL after Docker startup, explicit journal recovery, unknown-root refusal,
prepared-state tamper refusal and isolated cold no-SMTP restore all pass.
A test-only activation driver hook kills the real process; it does not simulate
Docker, protocol readiness or persisted resources.

Host: isolated development Docker 29.2.0 on Debian, Node 22.22.0, physical
wlp3s0 `192.168.5.201`; independent read-only SSH client `testbox`, wlp2s0
`192.168.5.202`. The test first reaches a nonce-bearing temporary LAN listener,
then receives ECONNREFUSED at the application port on the same host address.
Exact Docker publication is 127.0.0.1, verified by Docker inspection and `ss`;
there is no wildcard/IPv6 publication. Contract negatives reject public/IPv6/
alias bindings before activation. Host-only HTTP success is not the isolation
proof. This qualifies the observed Docker/host topology, not every engine/network
implementation; target operators must repeat these acceptance observations.

A real unprivileged host Nginx process runs with a private prefix/config/key;
it is not containerized. Debian nginx 1.22.1-9+deb12u10 was downloaded and
unpacked under /tmp only, archive SHA256
`cc7ae36d024f602861eeefe64656d14481b3bd224d81f8d69f789de49f16375a`.
Actual HTTPS CA/SAN validation passes. Infra's fixture records the unchanged
`/-/svc/qualification.ping` path; Debian uses the actual operator-generated
`proxy-config` fragment, with no proxy_pass URI suffix. No system-wide CA,
resolver, firewall, service or production proxy setting was changed.

## SMTP/DKIM and recovery limits

Actual canonical Postfix/OpenDKIM composition shares only its intended private
networks and publishes no SMTP/DKIM host port. The app receives its authorized
submission credential plus public CA only. STARTTLS CA/hostname validation and
SASL succeed; wrong credentials fail EAUTH and an unauthenticated relay attempt
fails EENVELOPE. The fixture trusts only 127.0.0.1/32, so its application-network
client must authenticate. Trusted-CIDR authorization and SASL are distinct
canonical policies, not a claim that every trusted client must use SASL.

Optional mail failure leaves HTTP ready with diagnostics. Explicit required mail
failure makes overall readiness false. Backend failure/recovery preserves queue
ownership and secret/DKIM generations. Canonical service regression separately
checks local capture, DKIM signature and queue recovery, plus verified TLS to a
controlled upstream capture. These are not Internet delivery evidence.

Application mail backup/restore fails `SMTP_RECOVERY_UNQUALIFIED` before copying.
No successful message is sent by the application acceptance fixture. SMTP spool
restore, provider credentials, Internet handoff, recipient delivery, SPF/DKIM/
DMARC deployment and bounce handling remain future controlled Oxy-form acceptance.
The application-only cold backup/restore result is independently qualified;
`kernel_recovery_verified:false` is retained rather than invented business proof.

## Reproduction commands

From the Infra Layer branch (Node 22, Docker/ss/openssl/SSH prerequisites):

```sh
npm ci --ignore-scripts --no-audit --no-fund
npm test
npm run test:integration
IL5_NETWORK_CLIENT=testbox IL5_LAN_ADDRESS=192.168.5.201 \
IL5_HOST_NGINX=/tmp/drumee-il5-host-nginx/usr/sbin/nginx npm run test:application
npm run test:package
IL5_APP_IMAGE=IMMUTABLE_SHA256_IMAGE_ID \
IL5_TSC=/absolute/typescript/bin/tsc node test/application/package-consumer.js
npm pack --json --pack-destination /owned/local-artifacts
```

Run heavy suites sequentially on the qualification host. `npm run test:integration`
sequentially invokes gateway/services/lifecycle/HTTPS-job suites. For the selected
replay only the failed lifecycle suite was repeated with `npm run test:lifecycle`;
passing suites were not counted twice. The archive consumer installs the packed
artifact offline into a new npm project, compiles against that installed package
and invokes public prepare on its new owned root. No sibling checkout is loaded.

From a clean Debian clone on its IL-5 branch:

```sh
npm ci --ignore-scripts --no-audit --no-fund --prefix profiles/minimal-application
npm ci --ignore-scripts --no-audit --no-fund --prefix tests/minimal-application/fixtures/plugin
(cd tests/minimal-application/fixtures/plugin && npm pack --pack-destination /owned/artifacts)
# Build input explicitly binds packed archive SHA512 and source revision; see operator guide.
node profiles/minimal-application/scripts/build.js /owned/artifacts/build-input.json
node --test profiles/minimal-application/test/*.test.js
python3 tests/minimal-application/plugin-artifact.test.py
tests/run-all.sh
IL5_NETWORK_CLIENT=testbox IL5_LAN_ADDRESS=192.168.5.201 \
IL5_HOST_NGINX=/tmp/drumee-il5-host-nginx/usr/sbin/nginx node tests/minimal-application/run.js
```

Cleanroom is a fresh GitHub clone with no source overrides or sibling checkout.
The explicit test plugin bundles locked nodemailer; ordinary builds have no test
plugin. Both runtime and canonical native-tools images are built locally from
verified locked inputs; receipt records immutable IDs and provenance. Docker
build cache is allowed, not an unrecorded source dependency. Git status remains
clean after ignored node_modules/cache generation. Same-host rebuild reproducibility is demonstrated by identical image IDs and
receipts; cross-host bit-for-bit reproducibility is not claimed.
The final [cleanroom report](evidence/IL-5-distribution-cleanroom.json),
[installed consumer](evidence/IL-5-installed-consumer.json) and
[selected counts/log hashes](evidence/IL-5-validation.json) preserve this evidence.

Retained minimal-kernel (existing qualified IL-4 immutable image receipt):

```sh
node --test profiles/minimal-kernel/inventory.test.js profiles/minimal-kernel/test/*.test.js
IL4_IMAGES=/tmp/drumee-il4-cleanroom/profiles/minimal-kernel/.cache/images.json \
IL4_INTERFACE=wlp3s0 IL4_LAN_ADDRESS=192.168.5.201 IL4_INTERRUPT=1 \
node tests/minimal-kernel/run.js
```

The current Debian selector/shared renderer/harness runs against unchanged IL-4
images source `4a0efba6193912ce5b0487db51fb541ca79638d0`. Exact kernel/tools IDs
are in [`evidence/IL-5-kernel-regression.json`](evidence/IL-5-kernel-regression.json).
Canonical enrollment interruption/concurrency, missing-credential refusal,
credential/UID/operation/CA preservation, real authentication/Hub/MFS/FileIo/
ZIP/Range/OTAK/Finder, 16 SQL denials and isolated restoration pass. This is
regression evidence, not a claim that IL-5 rebuilt the historical kernel image.

## Failures, corrections and skips

No selected passing suite skips required application/network evidence. Restricted-sandbox Node test
workers and ownership-dependent tests initially failed; reruns with the authorized
real host privileges pass. The sandbox wizard returned 330/331 overall; real
host replay returns 331/331. These failed attempts are excluded from pass totals.

The first combined historical Infra integration run passed gateway 17/17 and
services 17/17, then failed lifecycle case 15 at `checkPorts` Docker observation
with `DOCKER_LIFECYCLE_COMMAND_FAILED`; lifecycle ended 15/16. Other isolated
stacks were concurrently creating/removing helper containers. Its loop takes a
running-container snapshot then inspects each ID, so disappearance is a plausible
race, not a proven diagnostic (the safe Docker wrapper suppresses stderr).
No conflicting/public resource was adopted and the guard failed closed. Final
isolated lifecycle replay passes all 16 unchanged tests, zero skips; no
production guard is relaxed.

Early application fixture corrections: public npm self-reference resolution,
forbidden `/data` changed to `/app/state`, host Nginx temporary paths confined to
its prefix, and a 0700 unknown-root fixture reaching the intended ownership
negative. The Debian observer initially checked the wrong owner label; corrected
to existing `org.drumee.infra.owner`, then the exact failed test project was
cleaned. A cleanroom npm pack invocation incorrectly used --prefix; it failed
without packaging, then packing from the actual fixture directory succeeded.
The global packaging gate reports historical Team FROM entries lacking digests
and `npm install -g pm2`. An isolated detached worktree at baseline `3fb32d8`
returns byte-identical findings (apart from its root header): 10 checks pass,
2 fail in both trees. The new application Dockerfile is pinned and introduces
neither failure. This pre-existing CI debt remains visible; it is not fixed by
changing the historical Team profile or suppressing the gate. A separate Node 22
CI job now executes the new application contracts and archive security cases.
ShellCheck is not installed locally and was not executed here; the existing
GitHub ShellCheck job is retained and must be assessed in PR checks.

No canonical behavior or negative test was weakened. All failed owned projects
were removed without touching unrelated resources.

## Scope remaining outside this qualification

Only strict IPv4 loopback publication is supported. External TLS ownership and
Nginx installation/renewal remain external operator responsibilities. The
reference host provides public RPC and canonical fail-closed authorization;
application-specific identity/session adapters and business acceptance belong
to their consumers. Secret rotation is the existing explicit Infra contract,
not an automatically inferred password reset. Backup retention is recorded;
pruning remains an explicit owner operation. Image/schema/engine downgrade is
unsupported and fails closed.

Publication, release tags, image registry delivery, merge, production deployment,
Internet SMTP integration, Oxy-form OF-01R resumption and Oxymotion D0 remain
separate decisions. The implementation PRs and integration order are in
[release handoff](IL-5-release-handoff.md).

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
