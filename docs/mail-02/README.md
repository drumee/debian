# MAIL-02 independent mail profile

**MAIL-02_QUALIFIED for isolated transport.** All20 native transport rows pass,
including both45-control replays on the rebuilt image. Required Debian lint,
packaging, suite and minimal-application-contract jobs pass with unchanged gates.
The exact base comparison and rebuilt-image impact analysis are in
[the closure addendum](https://github.com/drumee/infra-layer/blob/feat/mail-02-service/docs/mail-02/ci-closure.md).
The qualification and its exact PASS/FAIL/BLOCKED disposition are in
[Infra's final dossier](https://github.com/drumee/infra-layer/blob/feat/mail-02-service/docs/mail-02/qualification.md).
Draft [Debian13](https://github.com/drumee/debian/pull/13) and
[Infra38](https://github.com/drumee/infra-layer/pull/38) remain unmerged.
[Reproduction commands](https://github.com/drumee/infra-layer/blob/feat/mail-02-service/docs/mail-02/reproduction.md)
and the [MAIL03 handoff](https://github.com/drumee/infra-layer/blob/feat/mail-02-service/docs/mail-02/mail-03-handoff.md)
cover the full native matrix, faults and boundaries. No publication, deployment,
public-port/firewall, DNS/PTR or merge permission is implied.

## Exact inputs and corrected mechanisms

Requested Debian `0fc183eabc8e6634a355689d9c129b8fbbd4ac38` remains an ancestor;
the distribution base is `ff6e6b399128e6332c984fc2e8e60f660bd5f881`. MAIL01 remains
Debian PR12 `3c91036f95528e3f9baa04cb78b2b74ae96f63a1` and Infra PR36
`2328b28b126355e40f18815e74c20e203ca6388f`. No later branch changes were discarded.

The [consumer lock](../../profiles/mail/infra-source-lock.json) identifies producer
`de5ea272fe40c77dded529d03ef3ce1f174472ab`, unpublished package
`0.1.0-alpha.7-mail02.15`, SHA256
`03a1402e447015e20b41900b05edfda00ea0ea01ae3b5e7b358b7d88d071aa99`, SRI and all50
member hashes. Installation disables scripts; import verifies closed inventory;
there is no registry/sibling-source fallback. Existing capture/relay bytes remain
unchanged. For a local frozen archive:

```sh
node profiles/mail/acquire.cjs /absolute/private/drumee-infra-layer-0.1.0-alpha.7-mail02.15.tgz
node --test tests/mail/profile.cjs
bash tests/run-all.sh
```

Native image config ID:
`sha256:ab41ba434fa20afd54f71f43fc31ad2aaa94260193a4e9b56cc0e5c971fb1a56`.
Its quota module SHA256 is
`01fec4a55d42add0d62b939216bec57869513b2dab6b55c83ae51c93dd22f4c5`.
Postfix3.10.13, Dovecot2.4.1-4, OpenDKIM2.11.0; these are measured local config IDs,
not fabricated registry digests. The [native source lock](../../profiles/mail/native/source-lock.json)
pins Dovecot2.4.1 commit `7d8c0e57599636cff365373ca1ce34e92aac0e25` and15 sources,
verified against Debian's original source and patch set. `node profiles/mail/build.cjs`
builds a new receipt; changed module/image bytes require requalification.

Stock zero-grace quota was reproduced overflowing across LMTP/IMAP. The replacement
holds a UUID-home kernel lock through native commit/rollback, synchronizes native
counts, serializes folder mutations, refuses count/write/lock errors and recovers
without a durable reservation counter. COPY/MOVE headroom, worker death, flags/
folder races, queued retry, other-box isolation and restart counters are exercised.
The rejected raw-directory prototype is not qualified. Read
[native invariants](../../profiles/mail/native/DESIGN.md) before changing writers.

Docker26 suppressed the original internal-edge publication; gateway NAT then hid
sources, and no-masquerade alone hit bridge isolation. The documented
[amendment B](../../profiles/mail/native/NETWORK-AMENDMENT.md) uses a stable
mail-owned external frontend. Client projects keep separate backends and own
credentials plus CA only. Namespace packet filtering drops unknown frontal and
masqueraded-gateway sources; startup NET_ADMIN/SETPCAP are removed before Postfix.
TLS hostname verification, AUTH and sender grants remain mandatory.

Rapid equal-size private userdb generations exposed Dovecot's whole-second
mtime/size cache. Apply now fsyncs distinct increasing timestamps before pointer
publication and verifies native observations before lifting its admission barrier.
Preserve this step in MAIL03; do not reset generations after a failed apply.

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


## Qualification, administration and recovery

The central dossier contains the original45 native checks on workstation and
Docker26 guest, expanded quota/TLS/session/resource/MX proofs, native versions,
source/packed-file hashes and observed failures corrected during this continuation.
The guest uses a NEW bounded filesystem for pressure/missing-mount tests, then
boots normally with an accepted nonempty queue on existing storage. Private
positive/negative/recreated projects are repeated after boot without rule repairs.

The read-only `profiles/mail/private-client.cjs CONFIG ADDRESS` emits the canonical
external network attachment and verified endpoint. It creates nothing. The
administrative `drumee-ctl mail` mailbox/alias/account interface remains MAIL03.
Qualification helpers are not production administrative commands. Use protected
TTY/FD password input in that lot, stable mailbox UUIDs, retained-delete tombstones,
expected-generation CAS and an authoritative request journal.

Local suites:409 Infra units,24 contracts,50-member dependency-free package,
TypeScript5.9.3,331 Debian checks and5 locked-profile tests. Hosted Infra checks pass;
Debian suite/contract pass while ShellCheck/packaging failures are unchanged from
the initial baseline (91/15 normalized diagnostics, no additions/removals). Do not
waive their protections: the parametric FROM remains a static release-acquisition
gate even though the local builder checks the exact base config ID.

**SMTP_RECOVERY_UNQUALIFIED** remains independently for coordinated Oxy-form
restoration and this profile's queue/registry/Maildir/IMAP/secrets/keys restore.
Same-storage reboot is not backup restoration. Preserve accepted queues, the Oxy
ledger and deduplication key. An `accepted` entry is not recipient receipt; no
exactly-once guarantee is made. Alpha.6 cold queue qualification does not cover
this new combined profile. Real app integration, public/DNS/PTR work, publication
and release/deployment are later lots.

## CI closure and immutable build input

The exact base of PR13 is `ff6e6b399128e6332c984fc2e8e60f660bd5f881`.
It has91 ShellCheck diagnostics,11 mutable FROM instructions and one global npm
install. The starting mail head5477306 adds its parametric native FROM failure.
The earlier b5a9c70 comparison was an earlier PR checkpoint, not the PR base.
Inherited fixes are separately reviewable in draft [PR14](https://github.com/drumee/debian/pull/14)
and carried here by cherry-pick. The workflow and packaging script are unchanged.

The native Dockerfile has a literal manifest-pinned FROM. `build.cjs` reconstructs
and verifies a closed OCI layout from expected base config `a02cc47…`, with real
manifest `c9d6b4d5a69d7c53272ff13a4b90679422d61428a6f868a0463e3bdcfbe58236`.
A pinned BuildKit container binds the complete FROM name to that verified local
layout. This is a local build/import, without publication or mutable fallback.
Missing/corrupt blobs, changed/absent/mutable FROM and populated layout targets
are rejected. Six tests are included in `tests/run-all.sh` (333 checks); eight
maintenance regression tests cover inherited shell/build guards. Run:

```sh
python3 tests/mail/native-base.test.py
python3 tests/ci-baseline-regression.py
node profiles/mail/build.cjs
```

The new image differs in build-generated account dates, unused snakeoil defaults,
ldconfig cache and apt/dpkg logs. Runtime configuration, native module, frozen
package and generated service configuration are unchanged. Because the image ID
changed, the native matrix was replayed on it, including concurrent LMTP/IMAP quota,
Docker26 private filtering/client recreation/reboot and disk/mount recovery.
See the closure evidence for byte comparisons and the final hosted job links.
`SMTP_RECOVERY_UNQUALIFIED` is retained for coordinated/new-profile restoration.
