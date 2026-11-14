# Reproducing MAIL-03 in the isolated laboratory

No production changes, public listener exposure, real-recipient SMTP, publication,
DNS/PTR changes or merge are part of these commands. Use a disposable Linux/x86_64
Docker host/guest, private owned ext4 directories and synthetic credentials only.
Keep every original report, queue, Maildir and authority when a test fails.
Never run two mail projects using the same laboratory CIDR simultaneously.

## Frozen inputs

Acquire producer `1b60818f4f60cc6b54976184dbd6f0585b717a68`, unpublished package
`0.1.0-alpha.7-mail03.8`. Its archive SHA256 is
`37753b445400cbced8e60fc24ef9b69f9b2eeddc6f5f85ac5e64e0bdb32496fb`;
SRI and all 52 members are in profiles/mail/infra-source-lock.json. Checkout the
final PR15 reference recorded with the delivery/CI links. The PRs target their
MAIL-02 parents: Infra `465d4e9` and Debian `ad1c7be`. Do not merge/publish either lot.

Native engine config ID:
`sha256:ab41ba434fa20afd54f71f43fc31ad2aaa94260193a4e9b56cc0e5c971fb1a56`.
Quota module SHA256:
`01fec4a55d42add0d62b939216bec57869513b2dab6b55c83ae51c93dd22f4c5`.
Node helper config ID:
`sha256:d0a16be756b6ec6658aecb8b7bcf87fa6c7d0d7fcc6ca53ad14bb49a4c90bdd7`;
client config ID:
`sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8`.
Use the MAIL-02 qualified images already loaded by immutable ID. Rebuilding any
image/module requires relevant native requalification. There is no mutable tag
or missing-artifact fallback. Runtime/package/member identities are verified.

```sh
umask 077
# In the exact producer worktree; this creates a local archive, not a publication.
npm ci --ignore-scripts --no-audit --no-fund
npm pack --json --pack-destination /absolute/private/artifacts
# In the matching Debian worktree:
node profiles/mail/acquire.cjs /absolute/private/artifacts/drumee-infra-layer-0.1.0-alpha.7-mail03.8.tgz
cp profiles/mail/infra-source-lock.json profiles/mail/.cache/consumer/mail02-receipt.json
node --test tests/mail/profile.cjs
```

The consumer accepts only its exact source lock and closed installed inventory.
An offline guest can receive a tar snapshot of that already-verified consumer,
the original archive and the source lock. Verify it through consumer.cjs before
use. Never replace/acquire a package while an operator invocation is running.
An acquisition/operation overlap was rejected with MAIL_INSTALLED_MEMBER_MISMATCH;
its pending validated request subsequently reconciled without another password.

## Native protocol baseline and canonical CLI profile

In the Infra worktree:

```sh
MAIL02_CONSUMER=/absolute/debian/profiles/mail/.cache/consumer \
MAIL02_RETAIN_RUNTIME=1 python3 -B test/mail-service/run.py
```

If the guest has the qualified Node config ID without its registry name, set
MAIL02_NODE_IMAGE to the immutable Node ID above. The harness prints REPORT and
creates private keys/verifiers, source receipts and independent receiver files.
Its core project owns exactly four services; DNS/MX fixtures use another project.
Both networks are internal and the base run publishes no host ports. It exercises
45 native controls, including delivered Authentication-Results handling and DKIM.
Do not edit its source files during execution. Preserve the printed report root.

Before creating another profile on 10.243.47.0/24, stop/remove only the retained
fixture/core projects using their reported project names and compose files:

```sh
docker compose -p SOURCE_PROJECT-fixtures -f SOURCE/fixtures.json down
docker compose -p SOURCE_PROJECT -f SOURCE/compose.json down
# No -v, prune or deletion of SOURCE/service.
```

In Debian, generate/start the canonical independent profile:

```sh
MAIL02_RETAIN_RUNTIME=1 python3 -B tests/mail/native-lifecycle.py SOURCE
```

This prints the new private PROFILE root. For Docker 26 private-listener/boot
qualification, use MAIL02_PRIVATE_BIND=1 and TMPDIR in an owned 0700 persistent
ext4 directory. Guest /tmp is tmpfs and is unsuitable for the administrative
authority/reboot test. Parent directories must not be group/world writable;
the775 laboratory parent was refused before exposure, then explicitly corrected
to 700. Keep source key fixtures in persistent private storage before reboot.

## Administrative, protocol and storage replay

With all four services healthy, no pending request and no other test mutating the
same authority, run these sequentially. Each script uses the real bin/drumee-ctl,
native protocols, protected input files and controlled local recipients. Reports
and public command/output hashes are written under PROFILE. Protected synthetic
credentials remain in PROFILE/admin-probe and are excluded from evidence export.

```sh
python3 -B tests/mail/admin/run-all.py PROFILE SOURCE /absolute/infra
python3 -B tests/mail/quota-transition-native.py PROFILE SOURCE
python3 -B tests/mail/quota-transition-guards.py PROFILE SOURCE
python3 -B tests/mail/admin-cutpoints.py PROFILE SOURCE
python3 -B tests/mail/purge-interruption.py PROFILE SOURCE
```

The frozen replay has 51 assertions across all verbs, retained deletion/queued UUID,
alias repoint, metadata-preserving rename, terminal/FD input, grants, active
sessions, journal/CAS/idempotency, native dependency failure, quota changes, eight
atomic quota controls and guarded purge. Its source-hash map must remain unchanged.

The additional quota matrix has five scenarios/six assertions: RCPT before DATA,
held DATA, fitting old delivery, held APPEND and busy timeout/reconcile. Observe
old public quota while LMTP is held, no success before completion, appropriate
over_quota at success and refusal of future growth. An independent process holds
the unrelated IMAP observer. The single-thread multi-TLS fixture produced a client
BrokenPipe while native logs showed the unrelated NOOP finished; that diagnostic
was retained, and the independent observer replays the actual service boundary.
The historical failing command tests/mail/quota-change-held.py is only a mail03.6
reproduction, not a success criterion for the corrected below-use contract.

The syscall tracer follows the unmodified real CLI on Linux/x86_64 and kills it
after successful rename exits: native barrier before SQL commit, private before
public pointer, public before native probes, native-applied before SQL-applied.
No production fault-injection hook is added. Reconcile must finish the same sealed
target, with old applied reads and new authentication refused until release.

Purge interruption kills at its durable executing receipt. A strict partial subset
of verified synthetic data is constructed/observed with all writers stopped, then
native reconciliation verifies and erases the remaining subset. This is explicitly
a crash-state fixture, not a replacement-storage restore qualification. It verifies
the retained backup is unchanged and leaves services stopped before a separate start.

## Supplementary final-package transport profile

Use a distinct fresh profile created with the final acquired package, before any
administrative credential mutation. TLS fixtures intentionally use bootstrap
credentials and require an unchanged same-version prepared candidate. Preserve
the administration profile separately. In the fresh profile run sequentially:

```sh
python3 -B tests/mail/tls-native.py PROFILE SOURCE INFRA/test/mail-service
python3 -B tests/mail/tls-extra.py PROFILE SOURCE INFRA/test/mail-service
python3 -B tests/mail/identity-controls.py PROFILE
python3 -B tests/mail/protocol-native.py PROFILE SOURCE INFRA/test/mail-service
python3 -B tests/mail/auth-gate-native.py PROFILE SOURCE
```

These assert 5 TLS generation, 6 expiration/mandatory TLS, 63 identity, 26 protocol
and 3 authentication-gate outage/recovery controls with the native services.

## Guest reboot and independent private clients

Only inside the disposable qualification VM, after the native replay:

```sh
python3 -B tests/mail/admin-boot.py PROFILE SOURCE stage
# Reboot the qualification guest, never the physical host.
sudo systemctl reboot --no-block
# After reconnecting to the same guest/storage:
python3 -B tests/mail/admin-boot.py PROFILE SOURCE verify
python3 -B tests/mail/admin-client-reset.py PROFILE SOURCE
python3 -B tests/mail/private-network.py PROFILE SOURCE /absolute/infra/test/mail-service
python3 -B tests/mail/boot-native.py PROFILE SOURCE /absolute/infra/test/mail-service stage
sudo systemctl reboot --no-block
python3 -B tests/mail/boot-native.py PROFILE SOURCE /absolute/infra/test/mail-service verify
python3 -B tests/mail/private-network.py PROFILE SOURCE /absolute/infra/test/mail-service
```

Use disjoint Message-IDs: IMAP HEADER search matches substrings. The first
fixture failed its old-message count because its queued ID extended the old ID;
its failure is retained and the corrected whole reboot scenario was replayed.

The first reboot retains an interrupted operation, closed admission and a held
accepted message. Ordinary startup refuses incomplete security state; explicit
reconcile starts only its sealed target, then the owned unit is restarted. The
second normal reboot must start without network/filter corrections, preserve a
nonempty queue and deliver its original message once observed. Record changed
boot IDs and actual Docker version. Private clients use distinct backend projects,
immutable images, only their CA/credential mounts, verified TLS and mandatory AUTH;
forbidden and unattached clients increment actual namespace drop counters. Client
recreation must preserve mail container/network identities. Disable/stop only the
owned test unit/projects after qualification and retain all persistent data.

## Suites and hosted gates

```sh
# Infra: qualified Node 22.22.0 and immutable lockfile dependencies
npm test
npm run test:contracts
npm run lint
npm audit --include=dev
npm run test:package
npm run test:integration
# Debian
node --test tests/mail/profile.cjs
bash tests/run-all.sh
scripts/check-packaging.sh
```

ShellCheck uses the unchanged CI action 00b27aa7cb85167568cb48a3838b75f4265f2bca,
v0.11.0, severity warning, identical exclusions; assert its emitted statuscode=0,
not only the wrapper exit. Packaging runs in the unchanged pinned Trixie image
020c0d20b9880058cbe785a9db107156c3c75c2ac944a6aa7ab59f2add76a7bd with workflow
tooling, exact tracked inventory and unchanged gate. Use a clean worktree/archive.
The four historical general Infra integration failures must be compared with
465d4e91553edd204b1e3b5ace9ad64791235403 in the same environment; do not waive
required CI jobs. Final hosted runs and exact SHAs are linked in the delivery/PR.

Export only whitelisted nonsecret reports/logs. Exclude inputs, keys, passdb,
verifiers, SQL databases/WAL, credential fixtures, Maildirs and backup contents.
Omit output fingerprints for secret-producing hash commands in public projections;
retain private originals separately. Scan exported bytes against protected known
synthetic passwords/verifiers and private-key patterns before committing evidence.
`SMTP_RECOVERY_UNQUALIFIED` remains for both coordinated Oxy-form and autonomous
replacement-storage restoration; no ledger/dedup reset or exactly-once claim exists.
