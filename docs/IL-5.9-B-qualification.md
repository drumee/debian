# IL-5.9-B — integrated consumer qualification

Decision: **READY_FOR_OWNER_MERGE_DECISION**, with the unchanged Debian baseline
debt visible. This is a technical dossier, not merge/publication authorization.
The final delivery SHA is the existing PR #7 head; executable qualification and
image labels identify `ccaa839bf13ab163025e868b21f16516c87d1ff9` explicitly.

## Source and environment

See [source selection](IL-5.9-B-source-selection.md) and
[realignment](IL-5.9-B-consumer-realignment.md). Infra PR #2 remains open at
`aa9057f224f4ae5cf80d777e3cb2fad092193fb1` into main `bef9a379…`.
Debian PR #7 remains targeted at `feat/container-distribution` `3fb32d86…`.
Only Debian is changed. The server/UI changelog edits and untracked local files
pre-existing in the main working directory are excluded from all commits.

Qualification uses a separate `git clone --no-hardlinks` of committed Debian
into `/tmp/drumee-il59b-debian-clean`, initially clean at ccaa839. Dependencies
are acquired by npm from the committed locks; neither sibling Infra sources nor
historical local node_modules are build inputs. npm ci downloads the exact
codeload source with the newly calculated archive SRI. The read-only owning
Infra checkout supplies only the canonical independent package-consumer test;
its packed artifact matches the freshly extracted archive's candidate exactly.

Host: Node 22.22.0, npm 11.18.0, Git 2.39.5, Docker 29.2.0. Native unprivileged
Nginx 1.22.1 is `/tmp/drumee-il5-host-nginx/usr/sbin/nginx` (Debian package
1.22.1-9+deb12u10, archive SHA256
`cc7ae36d024f602861eeefe64656d14481b3bd224d81f8d69f789de49f16375a`).
TypeScript 5.9.3 is used only for isolated strict NodeNext compilation.
LAN addresses are re-observed: qualification host wlp3s0 `192.168.5.201`,
independent `ssh testbox` wlp2s0 `192.168.5.202`. Existing unrelated Docker
containers are inspected and left untouched. Ports are dynamically acquired;
no host firewall, resolver, trust store or permanent service is modified.

## Commands and results

Commands are run from the clean clone unless another directory is given.
Logs and hashes are indexed by [log receipt](evidence/IL-5.9-B/log-receipt.json).

```sh
npm ci --prefix profiles/minimal-application --ignore-scripts --no-audit --no-fund
npm ci --prefix tests/minimal-application/fixtures/plugin --ignore-scripts --no-audit --no-fund
npm test --prefix profiles/minimal-application
python3 tests/minimal-application/plugin-artifact.test.py
npm ci --prefix profiles/minimal-kernel --ignore-scripts --no-audit --no-fund
node --test profiles/minimal-kernel/inventory.test.js profiles/minimal-kernel/test/*.test.js
tests/run-all.sh
scripts/check-packaging.sh
```

| Check | Measured result |
| --- | --- |
| Application TAP (selection/config/manifest/network negatives/source integrity) | 8 passed, 0 failed, 0 skipped |
| Plugin artifact Python tests | 8 passed, 0 failed |
| Minimal-kernel TAP (inventory/alignment/profile/CLI) | 15 passed, 0 failed, 0 skipped |
| Shared Debian suite | 331 checks passed, 0 failed; no emitted skip |
| Packaging | 10 passed, 2 historical failures, exit 1 |
| ShellCheck 0.11.0 | 91 historical diagnostics: 20 errors, 71 warnings; exit 1; no delta |
| Clean-clone integrated acceptance | 126 functional assertions, 10 groups, passed, no skip |
| npm isolated consumer | 8 functional assertions, strict NodeNext types passed |
| New Chromium scenarios | 0; historical kernel browser evidence retained, not rerun |
| Independent LAN checks | 2 observations: nonce route succeeds; runtime TCP connection refused |

Counts are separate. Repeated runs, the two LAN observations and constituent
checks are not added to an inflated aggregate total. The 126 counter includes
ownership/cleanup assertions, not 126 independent scenarios.

Initial test attempts are retained rather than hidden: a restricted sandbox
Node invocation could not run the complete profile worker; the authorized replay
passed 8/8. The first clean-clone kernel invocation ran 11 tests successfully and
failed to load the profile because its own dependencies had not yet been
installed. Its log is retained; installation from its unchanged lock followed by
the full targeted replay passed 15/15. Neither requires a code correction or skip.
The final integrated run has no failure. Expected negative assertions are not
reported as failed tests. Historical packaging and lint remain actual failures.

## Construction, inventory and reproducibility

The disposable fixture is packed from its own working directory after npm ci:

```sh
# cwd tests/minimal-application/fixtures/plugin
npm pack --ignore-scripts --json --pack-destination /tmp/drumee-il59b-evidence
# cwd clean Debian clone; input descriptor is outside the checkout
node profiles/minimal-application/scripts/build.js /tmp/drumee-il59b-evidence/build-input.json
# Save .cache/images.json, repeat the same build, compare the two receipts.
```

The input is `{tools:true,plugins:[{id:"qualification",archive:ABSOLUTE_ARCHIVE,
integrity:PLUGIN_SRI,revision:COMMITTED_DEBIAN_SHA}]}`. Each archive is checked
by the existing safe extractor. The fixture is acceptance-only, with bundled
Nodemailer; it is never installed as an ordinary deployment identity or plugin.
Both full build receipts are byte-identical on this host:

- Application: `sha256:d44327e37d37c612257822684a870d05d7f90fdae649b2dcbfb8e9f0566e7955`.
- Native tools: `sha256:075a3c53d14f9a71c827f285564518dde41e29faa0cc9e58f4cc126cd3dda4cd`.
- Plugin: `sha512-GPdfP2L6NKtz4qzOgqHsekCjRd7BXTuiPqA+XPxXBGntrMBUQIC0Vv18DEJe/4nryK8mBHGQOC7ajqxFq4kkEA==`.

[First](evidence/IL-5.9-B/images-first.json) and
[second](evidence/IL-5.9-B/images-second.json) inventories retain full identities.
The builds use the pinned Node digest, exact lock and plugin artifact. The native
image uses Infra's digest/version-pinned Dockerfile. This is repeatability with
Docker's cache on the qualified host; no cache-free, cross-machine or future
APT mirror reproducibility is asserted. No artifact is published.

[Image inspection](evidence/IL-5.9-B/image-verification.json) verifies actual image
labels, UID 1000:1000, all 35 Runtime package files, host/health bytes, plugin
worker/metadata and production module absence of Infra/ESLint. Native binary
versions are measured with dpkg-query. The recorded
[verification driver](evidence/IL-5.9-B/verify-images.py) uses network-disabled
containers and the documented local evidence/clone paths; adapt those paths for
another qualification root. Infra's 40 allowed installed members are checked
before Docker against the recorded SHA256 inventory.

The canonical independent package consumer is also rerun, read-only, from the
Infra checkout at aa9057f:

```sh
IL5_APP_IMAGE=sha256:d44327e37d37c612257822684a870d05d7f90fdae649b2dcbfb8e9f0566e7955 \
IL5_TSC=/tmp/drumee-il4-typescript/node_modules/typescript/bin/tsc \
node test/application/package-consumer.js
```

Its temporary installed consumer imports only the packed npm artifact; it
checks exports, types, composition and actual private idempotent preparation
without activation. [Result](evidence/IL-5.9-B/packed-consumer.json): matching npm
SRI, 40 members, no production dependencies, 8 assertions and strict types pass.

## Actual acceptance

```sh
IL5_NETWORK_CLIENT=testbox IL5_LAN_ADDRESS=192.168.5.201 \
IL5_HOST_NGINX=/tmp/drumee-il5-host-nginx/usr/sbin/nginx \
node tests/minimal-application/run.js
```

[Run receipt](evidence/IL-5.9-B/acceptance.json): project
`drumee-il5-debian-41791db3`, 126 assertions, passed. The private runtime is
published on dynamically selected `127.0.0.1:45591`; Docker port inspection and
host socket inspection agree. testbox first reads a nonce from an actual LAN
control listener, then receives ECONNREFUSED connecting to the runtime over LAN.
Thus the negative is not inferred from the YAML or a host-only HTTP request.

The actual external Nginx process consumes the operator's `location /-/`
fragment with no URI suffix/rewrite. HTTPS requests verify the supplied CA and
`application.test` SAN, returning native RPC success and canonical 403 denial.
No system-wide CA or external proxy configuration is installed. Health is the
native runtime endpoint; there is no competing dispatcher/session mechanism.

Public lifecycle APIs prepare without starting a process, activate, inspect,
stop/start/restart, preserve durable data through idempotent install, reject a
bad plugin revision, roll back configuration, back up with writer quiescence and
restore into another isolated project. A real operator process group is killed
with SIGKILL after a new durable activation-intent is observed. Readiness stays
false; only that known-dead owned process's empty exclusive lock is removed after
owner/type/content checks. Start without recovery fails
ACTIVATION_RECOVERY_REQUIRED; explicit `--recover` succeeds and preserves data.
No unknown deployment lock is stolen. Unknown nonempty storage and wrong owner
are refused without modifying the sentinel resource.

Optional SMTP uses canonical capture-mode Postfix/DKIM resources, with no host
SMTP/DKIM publication. Docker inspection observes one private internal DKIM
network, inaccessible to the application; only submission credential and CA
bundle projections are mounted into it. STARTTLS/certificate trust, SASL,
invalid server-name refusal and unauthenticated relay denial are exercised.
A message to reserved `.invalid` addresses is queued in capture mode, with no
Internet delivery: its queue ID survives application failure/restart and secret
fingerprints remain identical. Optional SMTP failure leaves HTTP ready; required
SMTP failure makes readiness false while the native HTTP endpoint still answers.
Application backup is explicitly refused with SMTP_RECOVERY_UNQUALIFIED and the
running application remains ready. No spool restore or real deliverability is
claimed. All owned test containers/networks and private temporary resources are
cleaned; the two local immutable image references remain available for review.

## Historical non-regression and CI debt

No minimal-kernel lock or execution path changed. Its 15 targeted TAP tests pass;
prior 260 functional assertions, 3 Chromium scenarios and 16 SQL negative cases
remain historical evidence only. No new Chromium or SQL acceptance run is claimed.
Infra 161 TAP and the historical gateway/services/lifecycle qualifications are
retained from IL-5.9-A/IL-5.8 because its executable bytes/public contracts are
unchanged by this Debian-only mission; they are not added to new test counts.

ShellCheck uses the exact action-derived scan, v0.11.0, warning severity,
individual-file mode and original exclusions, selecting the same 121 paths.
Normalized 91-diagnostic JSON is byte-identical to IL-5.6/IL-5.7 baseline, SHA256
`07570bf6645697be3d55940643d76063a84baf512eec1b911f88e6652a4b0c13`.
[Comparison](evidence/IL-5.9-B/shellcheck-comparison.json) records zero additions.
The hosted gcc diagnostics also match all baseline paths/lines/columns/messages.

Packaging is reproduced both locally and inside the qualified Trixie/Git 2.47.3
image `sha256:e40111e22399124db7cb569e5769be32eaccf3f8f1415bf31f11ce1f37139fab`,
with the checkout mounted read-only and only its exact path trusted. The 12-check
output equals the corrected baseline output after the context preamble:
10 pass, 2 fail. Legacy Team images lack digests and globally install PM2.
No scope, check, severity, exclusion or return code is weakened.
Their owner/remediation remain the distinct Debian historical distribution and
shell-hardening lots described in [debt acceptance](IL-5.7-baseline-debt-acceptance.md).

[Code-head PR CI](https://github.com/drumee/debian/actions/runs/39137350279)
completed on ccaa839: minimal-application-contract SUCCESS (8 TAP and 8 archive
tests), suite SUCCESS (331 checks), packaging FAILURE (same two debt findings),
lint FAILURE (same 91 diagnostics). [Summary](evidence/IL-5.9-B/ci-code-summary.json)
retains job IDs. The workflow file is unchanged. Delivery-head CI is recorded
below after the documentary push.

## Integration conditions and limits

Recheck after push: exact PR heads/base, mergeability, checks and protection
observations. The destination Debian branch reports protected=false and effective
branch rules `[]`; the classic protection-detail endpoint returns HTTP 403.
This limited admin visibility is explicit, not treated as proof that all future
rules or owner review requirements are absent. No policy change is made.
Infra main also reports protected=false, effective rules `[]`. Its current CodeQL
result says no new alerts in changed PR code and all five Quality jobs succeed;
external Sonar still publishes FAILURE. Sonar administration/cleanup is a separate
owner operation and is not performed by this mission.

The owner must review/accept the visible baseline debt and current security
handoff, integrate Infra #2 first, then Debian #7 into its existing feature base.
Later convergence from feat/container-distribution to main requires its own
review; the PR base is not silently changed. Any source-to-npm migration is a new
explicit lock/provenance qualification after a real publication decision.
Oxy-form still needs separate selection and OF-01R acceptance with its real plugin,
existing proxy/certificates and controlled upstream SMTP/DNS/mailbox inputs.
It is not declared unblocked. Production, OF-02, Oxymotion D0, merges, npm/image
publication and release tags are outside this execution and are not performed.
