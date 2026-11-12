# MAIL-02 independent mail profile candidate

**MAIL-02_BLOCKED.** This unpublished isolated candidate is delivered in draft
[Debian PR13](https://github.com/drumee/debian/pull/13) and
[Infra PR38](https://github.com/drumee/infra-layer/pull/38). The authoritative
[qualification matrix and evidence](https://github.com/drumee/infra-layer/blob/feat/mail-02-service/docs/mail-02/qualification.md),
[reproduction procedure](https://github.com/drumee/infra-layer/blob/feat/mail-02-service/docs/mail-02/reproduction.md)
and [MAIL-03 handoff](https://github.com/drumee/infra-layer/blob/feat/mail-02-service/docs/mail-02/mail-03-handoff.md)
record both completed corrections and remaining failures. Do not infer deployment,
publication or merge approval from passing native subsets.

## References and acquisition

The requested Debian `b5a9c70369be9bbf0deaffbb21e1c794eb598059` and subsequent
`e29df56df1a253dc14c814e65918707764526a0b` remain ancestors. The runtime/consumer/test
checkpoint is `47634b1c4c1b882f3c9fc11e997cde7cfd8e2bec`; later dossier commits do
not change the locked archive. The base remains container-distribution
`ff6e6b399128e6332c984fc2e8e60f660bd5f881`, not stale main. MAIL01 references are
Debian PR12 `3c91036f95528e3f9baa04cb78b2b74ae96f63a1` and Infra PR36
`2328b28b126355e40f18815e74c20e203ca6388f`.

[`infra-source-lock.json`](../../profiles/mail/infra-source-lock.json) locks producer
`4a73f8984fc1c0f884a8735d741551d8721d31d9`, unpublished package
`0.1.0-alpha.7-mail02.4`, archive SHA256
`3332f762399dc9a482447ca1e021ba197c733ff83502ce9f99eb1ea4c8fea1a8` and50 exact
member hashes. It verifies SHA256/SRI before script-disabled installation and a
closed installed inventory on every API import. No registry/sibling-source fallback.

```sh
node profiles/mail/acquire.cjs /absolute/private/drumee-infra-layer-0.1.0-alpha.7-mail02.4.tgz
node --test tests/mail/profile.cjs
bash tests/run-all.sh
```

Native image config ID is
`sha256:f3fe9dc4eeb6cb8b1ba3efd61c6743159ba8313e2901983e9300ca6e4a5d733b`:
Postfix3.10.13, OpenDKIM2.11.0, Dovecot2.4.1-4. Node/Python helper and retained guest
image identities are in the Infra dossier. These are verified local config IDs,
not fabricated registry manifest digests. The existing native builder checks its
alpha.6 tools base config ID, but its parametric FROM still fails the repository
static packaging gate. Resolve the build/acquisition recipe before a release;
do not weaken the gate or publish an artifact in this lot.

## Runtime and operator boundary

The existing bin/drumee-ctl dispatches `--profile mail` independently from Team and
minimal-application. Mail owns four services, edge/control networks, spool, UUID
Maildirs, registry/verifiers, policy counters, TLS generations, DKIM keys and a
Unix socket volume. Ghost/Oxy/Oxymotion do not own their lifecycle. The bounded
policy helper receives no password verifier or TLS/DKIM private key and sees only
storage marker binds for disk admission.

```sh
bin/drumee-ctl --profile mail validate --config /absolute/private/mail.json
bin/drumee-ctl --profile mail install --config /absolute/private/mail.json --execute
bin/drumee-ctl --profile mail preflight --config /absolute/private/mail.json
bin/drumee-ctl --profile mail status --config /absolute/private/mail.json
bin/drumee-ctl --profile mail doctor --config /absolute/private/mail.json
bin/drumee-ctl --profile mail boot-unit --config /absolute/private/mail.json
bin/drumee-ctl --profile mail stop --config /absolute/private/mail.json --execute
```

Only synthetic `acceptance:true` config may start. The zero-image example cannot
activate; target activation stays refused. Preparation enforces UID/GID, protected
inputs, numeric mailbox ownership, closed config/secret inventories, immutable
candidate seals and storage marker/device/inode identities. Preflight checks every
runtime image/command/user/env/network/interface/mount/restart setting before
starting any role. Negative activation checks preserve existing source and target
data. Core restart=no prevents automatic Docker startup from bypassing preflight.

`boot-unit` renders only: guest/target installation is a separate operation. The
mail-owned unit requires all durable mount paths, runs preflight then guarded
start and stops its own services. It was installed only inside the dedicated
qualification guest. Real reboot retained a nonempty queue and prior Maildir
content; it is not replacement-storage restoration.

`doctor` now uses structured nonsecret queue/disk/quota/auth/cert/generation/TLS/rate
observations. Disk admission is64MiB or10% free; per-account MAIL limit60/minute
persists across policy restart. Independent SMTP1587 has mandatory TLS/auth/grants
and source CIDRs, but the qualified internal Docker26 edge suppresses the host
port publication. Authorized independent clients receive ECONNREFUSED before and
after recreation/reboot. Universal denial is a failed positive control.

The package TLS rotation API stages protected material, checks SAN/key/chain,
seals immutable generations, reloads and verifies all five native fingerprints.
A failed reload rolls back or holds admission closed until explicit reconciliation.
Do not rotate material by rewriting a sealed prepare generation. Administrative
mailbox/alias/account/password verbs remain reserved MAIL03; no early CLI admin
implementation is included. Backup/restore refuse `SMTP_RECOVERY_UNQUALIFIED`.

## Qualification and residual work

The installed archive passes45 native checks on workstation and VM, retaining the
original42 as non-regression. Delivered Authentication-Results filtering and DKIM
now pass. Additional results: MX6, independent client lifecycles8, operator
lifecycle5, TLS5, activation identity16, protocol negatives25, registry transitions8,
rate persistence, bounded256MiB disk/alerts/recovery, signer-outage4xx, local
postmaster/abuse routes and guarded VM reboot. Exact commands, hashes and per-case
observations are in Infra's dossier; a test process exit0 is not an overall verdict.

Two native failures remain: concurrent LMTP+IMAP count quota accepts1,150,509 RFC
bytes against1,048,576, and the authorized private host endpoint is unreachable.
The native count backend needs a reviewed atomic enforcement method across all
write paths; lmtp concurrency1 does not serialize IMAP. Private ingress needs a
supported service-owned route preserving source policy/TLS/auth and independent
clients. Neither is fixed by weakening the acceptance contract.

Additional BLOCKED matrix rows enumerate combined disable/deletion, grant-only
existing sessions/in-flight rotation, expired/missing TLS, exhaustive durable mount
and pre-existing network/volume failures, and full expiry-alert windows. Do not
silently mark these PASS. Actual Ghost/Oxy integration remains MAIL04.

Local suites:331 general and3 locked-profile PASS. Infra408 unit,24 contracts,
package50/no production dependencies, strict TypeScript and lint0 new findings
pass. Hosted Infra passes; Debian suite/minimal-application-contract pass but
ShellCheck and packaging remain FAIL. Comparing requested b5a9c70 baseline yields
the same91 ShellCheck and15 selected packaging diagnostic lines, zero additions or
removals. This includes the profile's FROM diagnostic and is not a runner waiver.

MAIL03 must preserve stable UUID/retained deletion, independent flags, aliases
without credentials, protected password input, CAS/request-id journal and
crash-reconcilable apply. Failed staged generation numbers cannot be reused.
Keep credential high-water marks and targeted IMAP invalidation. No generic
barrier removal or secret-bearing journal/output is acceptable.

`SMTP_RECOVERY_UNQUALIFIED` remains for complete new-profile and coordinated Oxy
recovery. Alpha.6 cold restore PR37 `6cc3483991b95d0f0c68e46ef9d62d1ca917c5f5`
does not cover these artifacts. Preserve each accepted queue, Oxy ledger and dedup
key; `accepted` is not recipient receipt. All trials used synthetic data and
controlled destinations; production, DNS/PTR, firewall, publication and deployment
were untouched.

**MAIL-02_BLOCKED**
