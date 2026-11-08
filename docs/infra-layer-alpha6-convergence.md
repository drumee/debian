# Infra Layer alpha.6 distribution convergence

## Immutable acquisition

Target lineage: `feat/container-distribution`, starting at
`2d2fd20d7a8116ae5023088cc4129246afe09c24`. Debian main/IL-5.10-C is separate.

The minimal-application operator consumes exact published
`@drumee/infra-layer@0.1.0-alpha.6` through its canonical npm lock, resolved URL,
SRI and closed member receipt. Producer: PR #34, commit
`09b7f28bce99ba3744e31a0ee5b2dde868a9a86a`.

- URL: `https://registry.npmjs.org/@drumee/infra-layer/-/infra-layer-0.1.0-alpha.6.tgz`.
- Archive: 44 regular files, 110826 compressed bytes, 391815 unpacked bytes.
- SHA256: `562a01bf5d8dba6151bf3a1768e56655df9e9302ed2ea6f072a4ed72eb177874`.
- SRI: `sha512-ZuGENEDYE1Ug6FJYzvSR+MG8zzOaBMBkYhgx+5nNR5OKMDBHpOvCfdzDe1XNfNz7fKqRfCHFQZGlxvYQzEm+YQ==`.

Published bytes agree with npm metadata, the producer receipt and every member
of the qualified Git source. The additional `lib/smtp-auth.js` is the required
canonical validator/native serializer; it is explicitly checked in the full
44-member hash receipt, not admitted by changing a count alone. Missing, extra,
modified or linked files still refuse before building. No local archive or
neighboring producer checkout resolves the dependency. Observed next=alpha.6;
the tag does not resolve the lock. Registry signatures are not a Git attestation;
no gitHead/attestation is supplied or invented. Historical alpha.1 is the only
observed producer release tag.

## SMTP contract and qualification boundary

Internal Drumee identifiers and submission credentials are unchanged. External
accounts accept simple names, complete addresses and opaque UTF-8 names within
the producer contract. Upstream secrets must use import-only
`smtp-external-credential` for the expanded byte contract; submission retains
`smtp-relay-credential`. Accounts/secrets are 1–255 UTF-8 bytes without BOM,
NUL, CR or LF. Account colon/leading ASCII map whitespace and trailing ASCII
secret whitespace refuse; final LF/CRLF is refused, never silently stripped.
Accepted punctuation, separators, leading/internal whitespace and Unicode must
reach SASL unchanged. TLS/certificate/peer-name verification remains mandatory.

`tests/minimal-application/relay-auth.js` exercises the installed distribution,
canonical import/projection, generated native Postfix map and native plugin
submission against a separately isolated TLS SMTP fixture. Its pinned test-only
smtp-server dependency does not change the profile or application dependencies.
It distinguishes private relay acceptance, authentication and actual synthetic
sink receipt, and checks refusal, private map permissions and absent shell expansion.

The complete real profile and authenticated mixed application/SMTP/DKIM recovery
campaigns were freshly executed against the installed published dependency and
the rebuilt patched fixture. Producer results do not replace consumer execution.
The compact [receipt](evidence/infra-layer-alpha6-convergence.json) records exact
source/tree/blob/image/artifact identities and deliberately omits raw logs,
credentials and host inventories.

Server Runtime remains alpha.4, minimal-kernel remains unchanged, and no runtime
operator or CI implementation is modified. Known 91 ShellCheck findings and two
packaging failures must be compared with the baseline and retained as failures.
The owner's targeted-merge authorization permits unchanged historical debt;
it does not disable checks, repair IL-5.10-C or converge Debian main.

An additional audit of the existing bundled qualification plugin found three
moderate address-parser advisories affecting its Nodemailer 10.1.1
(GHSA-8c8m-p3m8-cjg8, GHSA-m943-m63m-w62w, GHSA-85x2-q946-cp5h). The same findings
exist on the starting revision. Only that directly related synthetic SMTP client
fixture is updated to exact 10.1.7, already qualified by the producer; its audit
is then clean. Its sender/recipient remain fixed. This changes the test artifact,
so a fresh archive/image receipt and both complete consumer campaigns are required.
The old plugin SRI and prior campaign remain historical evidence, not the final
qualification for the rebuilt fixture. Profile/Runtime dependencies are unchanged.

No actual provider/account, owner secret, external message, production deployment
or public form activation is used. Oxy-form #3 remains draft and unchanged.
`SMTP_RECOVERY_UNQUALIFIED` remains: neither SMTP spool backup/restore nor
exactly-once delivery is provided by this convergence.

## Executed local qualification

Qualified build and runner source: `70522f033262d469bc1f6252ca8823def819c842`.
Subsequent convergence changes are documentary receipts only. Host Node 22.22.0,
npm 11.18.0, Docker 29.2.0; pinned image Node 22.23.3. All runs are isolated,
nonproduction and use synthetic credentials.

| Check | Result |
|---|---|
| Locked registry install / all installed member hashes | PASS / 44 |
| Profile contracts / plugin archive boundaries | 10 / 8 PASS |
| Shared suite / unchanged minimal-kernel | 331 / 7 PASS |
| Profile production and development audits | zero / zero vulnerabilities |
| Synthetic provider / corrected plugin fixture audits | zero / zero vulnerabilities |
| New real canonical SMTP authentication matrix | 7 cases / 487 assertions PASS |
| Full real minimal-application acceptance | 11 groups / 226 assertions PASS |

The SMTP matrix proves account and password bytes through canonical import,
projection, native map and SASL, for simple/full-address/opaque accounts and
formerly restricted punctuation/separators/UTF-8. Eleven file inputs fail before
connection, including final LF/CRLF, NUL/CR/LF, BOM, malformed UTF-8, trailing map
whitespace and size failures. Map entry count, private file/directory/database
modes, absent shell expansion, all native/provider log streams and redacted
receipts are checked. Bad authentication gives no sink message; untrusted CA,
wrong hostname and no STARTTLS give zero authentication and no sink message.
Private relay acceptance, successful SASL and actual local sink receipt are
separate observations.

The authenticated case deliberately defers the queued message during ordinary
rollback and a real provenance-triggered startup failure. The existing recovery
regression is reused as executable test code: actual missing-role representations,
actual Docker mount-array ordering variation, unauthorized context/identity/image/
revision/port/mount refusals, authorized rollback, restored RPC/SMTP readiness and
data/queue/secret preservation. Copied real-observation admission probes are
distinguished from physical fault injection. A physical extra network refuses
rollback without replacing containers; removal restores readiness. The new map
is rechecked after recovery, then the deferred message reaches the authenticated
TLS sink. This also exercises the additional credential mounts during recovery.

The separate complete profile campaign freshly executes native RPC/ACLs, real
host candidate Nginx TLS with CA/SAN checks, loopback-only exposure and separate
network namespace with a positive route control, stop/start/restart, durable data,
real SIGKILL/explicit recovery, ordinary/failed-plugin rollback, isolated non-SMTP
backup/restore, owner refusals, private SMTP/DKIM and optional/required failure
behavior. Its mixed recovery and SMTP_RECOVERY_UNQUALIFIED checks are retained.
No group is skipped. Earlier runs with the old fixture are retained separately
and are not substituted for these final results.

## Built artifacts and reuse

- Application: `sha256:1a5c9149109bfc5f5a0ba721b788508d9fc99bbeac37c38b6a0186348c081e1b`.
- Native tools: `sha256:a02cc47d0ebca12a55759edb00757b3a8cdd00112ad4afe9a4ff7b5337ffe843`.
- Both were built through the committed canonical profile with installed-byte
  verification. Native rootfs layers equal alpha.5's qualified tools image;
  updated producer provenance labels explain the different image identity.
- Patched qualification plugin: 164 members, 388595 compressed / 1725981 unpacked
  bytes; source `70522f033262d469bc1f6252ca8823def819c842`.
- Plugin SHA256: `adecbceb5045ec284379d54bf7c59c826b16ad368fa8da82fe4352321a00231e`.
- Plugin SRI: `sha512-yjQrN7LCOP6+QCGltSVcW6Il2nHWUfP6uFxc7kliAeEEf4tNAG3gVu2p6fFPKItmoD+fDnjPGeZmN58Ev6l7pw==`.

These are Debian qualification artifacts, not the actual forms backend/plugin.
The producer's exact archive/security evidence supports the verified input, but
its 254/201 assertions are not substituted for either downstream campaign.
Post-merge reuse of real acceptance requires exact profile, runner, CLI, renderer,
fixture, image and registry-byte identity; the final decision distinguishes reuse
from newly executed post-merge installation/contracts/shared checks.

## Hosted debt and handoff

[PR #11](https://github.com/drumee/debian/pull/11) targets only
feat/container-distribution. Initial push and PR checks on 70522f0 have successful
profile/shared jobs; both failed lint and packaging jobs in each run were compared
with the exact starting revision. All 91 ShellCheck records and 14 packaging
records (two failing rules and their locations) are identical. Failures remain
failures, not PASS. Final-head and resulting-merge results must be verified
separately and recorded in the PR/final decision before closure. This repository's
unchanged workflow defines no CodeQL/Sonar job; producer checks are separate proof.

The [OF-01R handoff](OF-01R-distribution-alpha6-handoff.md) identifies the upstream
secret-type migration as well as the coherent immutable pin update. The final
merge SHA/tree and exact post-merge receipt are recorded on PR #11 and in the final
local handoff. Oxy-form remains unchanged and its full actual backend/provider/
designated-mailbox qualification remains a separate mission.
