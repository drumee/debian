# MAIL-03 administration qualification

Status: **MAIL-03_BLOCKED pending final-reference CI.**
The results below qualify isolated administration only. No publication, merge,
production operation, public exposure or real-recipient SMTP was performed.
`SMTP_RECOVERY_UNQUALIFIED` remains for coordinated Oxy-form restoration and for
replacement-storage restoration of the autonomous profile.

## References and dependencies

The qualified MAIL-02 parents remain unmodified draft PRs:

| Repository | Parent | MAIL-03 dependency |
| --- | --- | --- |
| Infra Layer | PR38 `465d4e91553edd204b1e3b5ace9ad64791235403` | [Draft PR39](https://github.com/drumee/infra-layer/pull/39), target `feat/mail-02-service` |
| Debian | PR13 `ad1c7be3c0a6860fb1cfa58918d79cd026828a95` | [Draft PR15](https://github.com/drumee/debian/pull/15), target `feat/mail-02-profile`; depends on PR39 |

Both MAIL-03 branches are `feat/mail-03-admin`. No later parent changes were
replaced. The incremental diffs are relative to those parents, not main.
The original 106-file MAIL-02 evidence integrity manifest was checked at startup.
MAIL-01 operations remain the reference; CLI-01/02, ROT-01 and TX-01 are exercised
through the real `bin/drumee-ctl`, not an alternate administration entry point.

Final producer: **`1b60818f4f60cc6b54976184dbd6f0585b717a68`**;
unpublished `@drumee/infra-layer@0.1.0-alpha.7-mail03.8`.
Archive SHA256: `37753b445400cbced8e60fc24ef9b69f9b2eeddc6f5f85ac5e64e0bdb32496fb`.
The [source lock](../../profiles/mail/infra-source-lock.json) records SRI and all
52 members. Production dependencies remain empty. The consumer verifies the
closed installed inventory and never falls back to sibling sources or a registry.
Final Debian tip and its hosted runs are linked in PR15 and the delivery; commits
after the runtime source freeze add only tests/documentation/evidence. Compare
[the source inventory](evidence/artifacts/debian-source-sha256.json).

| Native artifact | Qualified immutable identity |
| --- | --- |
| Native engine image config ID | `sha256:ab41ba434fa20afd54f71f43fc31ad2aaa94260193a4e9b56cc0e5c971fb1a56` |
| Actual Dovecot quota plugin SHA256 | `01fec4a55d42add0d62b939216bec57869513b2dab6b55c83ae51c93dd22f4c5` |
| Node helper image config ID | `sha256:d0a16be756b6ec6658aecb8b7bcf87fa6c7d0d7fcc6ca53ad14bb49a4c90bdd7` |
| Python protocol-client image config ID | `sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8` |
| Native binaries | Postfix 3.10.13; Dovecot 2.4.1-4; OpenDKIM 2.11.0 |

These are measured config IDs, not fabricated registry manifest digests. No image
was published or rebuilt. All Debian native image/module sources are byte-identical
to `ad1c7be`. Host: Docker 29.2.0, Node 22.22.0, CPython 3.11.2/SQLite 3.40.1;
guest: Docker 26.1.5+dfsg1, Node 22.22.0, CPython 3.13.5/SQLite 3.46.1; owned local
ext4 storage. Runtime executable/binding hashes accompany the evidence. The guest profile-source
inventory matches the final host inventory byte for byte. Final identity evidence
is `regression/identity-result.json`; `host/identity-result.json` is a retained
preliminary identity replay.

## Results and reproduction

[Exact commands and preconditions](reproduction.md), [CLI reference](cli.md),
[interruption recovery](recovery.md) and [MAIL-04 handoff](mail-04-handoff.md)
form the operator procedure. Run suites sequentially against one authority.
`PROFILE`, `SOURCE` and `INFRA` below are private roots printed by the harness;
all recipients and credentials are synthetic. Public reports retain command,
exit/status and observed evidence, without credential material.

| Case | Result | Evidence and exact driver after profile preparation |
| --- | --- | --- |
| CLI-01 mailbox/alias/account semantics, pagination, defaults, collision/tombstone reservations, rename alias/reject, retained delete | PASS host + Docker26 guest | `host/mail03-admin-result.json`, `guest/mail03-admin-result.json`; `python3 -B tests/mail/admin/native.py PROFILE SOURCE` |
| CLI-02 masked controlling TTY, confirmation/mismatch/cancel restoration, exact bounded protected FD, unsafe input and sanitized errors | PASS host + guest | `mail03-tty-result.json`, `mail03-errors-result.json`; `admin/terminal.py`, `admin/errors.py` with the same roots |
| ROT-01 active SMTP/IMAP password and grant revocation, unrelated sessions, final DATA acceptance boundary | PASS host + guest | `mail03-session-result.json`, `mail03-rights-result.json`; `admin/sessions.py`, `admin/rights.py` |
| AUTH-03/04 independent Ghost/Oxymotion principals, envelope/header grants, no IMAP, disabled defaults, monitored local DSNs | PASS host + guest | `mail03-accounts-result.json`; `admin/accounts.py` |
| RX/IMAP create/alias/rename metadata and UUID retention, scoped disable, retained deletion and already accepted delivery | PASS host + guest | `mail03-admin-result.json`, `mail03-rights-result.json`; actual SMTP/LMTP and IMAP observations, not JSON alone |
| TX-01 concurrent CAS winner/conflict, request replay/different-content conflict, no-op, journal/authority identity, interrupted validation/staging/apply, exact reconciliation | PASS host + guest | `mail03-tx-result.json`; `admin/transactions.py` |
| TX-01 real syscall cuts before SQL desired commit, between private/public pointers, before native probes, before SQL applied commit | PASS host + guest, 4 cuts each | `mail03-cutpoints-result.json`; `tests/mail/admin-cutpoints.py PROFILE SOURCE` (unmodified CLI traced on Linux/x86_64) |
| QUOTA-01 increase/decrease/below-use, atomic LMTP/IMAP APPEND/COPY/MOVE, process death, two UUIDs, deferred retry after space release | PASS host + guest | `mail03-quota-result.json`, `atomic-quota-result.json`; `admin/quota.py`, `tests/mail/quota-native.py PROFILE SOURCE INFRA/test/mail-service` |
| Quota change with old RCPT/DATA, held APPEND, fitting growth, busy drain/reconcile, unrelated IMAP | PASS host + guest, 6 assertions | `held-quota-result.json`; `tests/mail/quota-transition-native.py PROFILE SOURCE` |
| Foreign Postfix defer setting and unsafe native quota lock refuse without overwriting | PASS host + guest, 3 assertions | `mail03-quota-guards-result.json`; `tests/mail/quota-transition-guards.py PROFILE SOURCE` |
| Separate purge, backup/source verification, unsafe target/writer/queue refusal, retained backup | PASS host + guest | `mail03-purge-result.json`; `admin/purge.py` |
| Purge executing interruption, strict constructed partial subset and same-generation resume | PASS host + guest, 2 assertions each | `mail03-purge-interruption-result.json`; `tests/mail/purge-interruption.py PROFILE SOURCE` |
| Pending operation across guest reboot, barrier/old applied revision, explicit sealed-target reconciliation, held queue/message retention | PASS Docker26 guest, 2 assertions | `guest/mail03-boot-result.json`; `tests/mail/admin-boot.py PROFILE SOURCE stage\|verify` |
| Docker26 private clients, AUTH/TLS/source drops, client recreation, normal reboot with nonempty queue and retained IMAP data | PASS Docker26 guest: private 8 before + 8 after reboot; normal boot 5 | `guest/private-pre-reboot-result.json`, `guest/private-result.json`, `guest/boot-result.json`; `tests/mail/private-network.py`, `tests/mail/boot-native.py`; see exact guest procedure |
| MAIL-02 native transport baseline including delivered multiple/folded Authentication-Results and valid DKIM | PASS final package, 45 controls | `regression/native45-host.json`; `MAIL02_CONSUMER=... MAIL02_RETAIN_RUNTIME=1 python3 -B INFRA/test/mail-service/run.py` |
| Canonical independent lifecycle | PASS, 5 controls | `regression/result.json`; `tests/mail/native-lifecycle.py SOURCE` |
| TLS rotation/mismatch/reload rollback, new/existing sessions; expiration and mandatory STARTTLS | PASS, 5 + 6 controls | `regression/tls-result.json`, `expiry-result.json`; `python3 -B tests/mail/tls-native.py PROFILE SOURCE INFRA/test/mail-service`, `python3 -B tests/mail/tls-extra.py PROFILE SOURCE INFRA/test/mail-service` |
| Complete runtime identity and pre-exposure negatives preserving existing data | PASS, 63 controls | `regression/identity-result.json`; `python3 -B tests/mail/identity-controls.py PROFILE` |
| Native TLS/AUTH/anonymous/network isolation negatives, including the new policy gate port | PASS, 26 controls | `regression/protocol-result.json`; `tests/mail/protocol-native.py PROFILE SOURCE INFRA/test/mail-service` |
| New IMAP authentication during policy outage; same credential recovery | PASS, 3 controls | `regression/auth-gate-result.json`; `tests/mail/auth-gate-native.py PROFILE SOURCE` |
| Debian suite / profile contracts | PASS, 336 / 5 | `checks/debian-suite.log`, `profile-contract.log`; `bash tests/run-all.sh`, `node --test tests/mail/profile.cjs` |
| Infra unit / contracts / lint / audit / packed consumer | PASS, 413 units, no new lint diagnostics or vulnerabilities | `checks/infra-*.log`; unchanged required gates; 52 package members, zero production dependencies |
| ShellCheck 0.11.0 and packaging | PASS at code freeze; final hosted pending | `checks/shellcheck-action-output.txt` (statuscode=0), packaging log; identical workflow thresholds/scopes |
| Final hosted required jobs | BLOCKED pending Debian final tip | Infra [43578050009](https://github.com/drumee/infra-layer/actions/runs/43578050009) PASS; final Debian links recorded at delivery |
| Historical general Infra integration suite | FAIL, same 4 on parent and final | `checks/infra-baseline-integration.log`, `infra-final-integration.log`; explanation below |
| Coordinated Oxy-form and autonomous replacement-storage restore | UNQUALIFIED, separate lot | No restoration claim, ledger/dedup reset or exactly-once delivery claim |

Evidence paths in the table are under `evidence/`; report names repeated in host
and guest directories have the same scope. The main frozen administration replay
contains 51 assertions, recorded with unchanged source hashes and exact engine
receipt in `mail03-final-replay.json`. Supplementary assertions are separate, not
added to that count.

## Observed failures and corrections

The mail03.6 held-DATA test exposed a real stale recipient context: native LMTP
accepted 1,200,435 virtual bytes after the CLI reported a successful shrink to
1,048,576 with used=0. Its failed guest observation is retained in history. The
correction adds a durable quota-drain intent and defers local Postfix dispatch;
it waits for qmgr configuration replacement, every old LMTP context, affected
IMAP writers and the same UUID kernel locks before publishing/probing the limit.
It restores dispatch only after verification. A busy writer returns incomplete,
keeps the old applied revision and closed admission, and resumes the same target.
No image/module changes, forced LMTP kill or Dovecot reload were used. Below-use
success is permitted only after old committed bytes are observed; future growth
refuses. The final six-assertion quota transition replay passes on both runtimes.

A first supplementary TLS run on an already administrated, older-package profile
failed its fixture assumptions: the candidate was from another package version
and bootstrap Ghost credentials had intentionally been rotated/disabled. Keep
`history/tls-on-admin-precondition-failure.json`; do not interpret it as transport
qualification. A distinct fresh final-package profile passes all five rotation
and six expiration/mandatory-TLS checks. Neither profile was reset to hide failure.

The first pending-reboot fixture used a Message-ID that was a prefix of its
queued Message-ID. IMAP HEADER search is a substring search, so its old-message
assertion expected one match where two were legitimate. The failure log and independent native search counts (old search=2, queued
search=1) are kept in `evidence/guest/boot-prefix-*`; the corrected fixture uses disjoint IDs and the complete pending
reboot/reconciliation is replayed. No mailbox or queue was reset.

A single-thread multi-TLS test observer raised BrokenPipe while native logs showed
its unrelated NOOP finished. The final observer uses an independent process and
asserts the same service boundary. An archive acquisition overlapping an operation
was correctly refused with MAIL_INSTALLED_MEMBER_MISMATCH; reconciliation against
the stable verified archive completed without requesting another password. Guest
/tmp (tmpfs) and a group-writable lab ancestor were refused; the successful guest
uses an explicitly owned 0700 ext4 root. These are recorded preconditions, not
waivers or weakened guards.

The four historical Infra general-suite failures are identical on qualified parent
465d4e9 and final producer in the same environment: BIND9 A/SOA/TXT EREFUSED;
BIND9 restart readiness; controlled relay compose setup; changed AAAA readiness.
The foundation portion passes 17, service portion passes 14/fails 4 on both.
The unchanged required hosted Quality jobs all pass. These historical failures
remain explicit FAIL results; none is relabeled PASS or blamed on a runner.

## Guarantees, limits and requalification

SQLite/WAL/FULL plus exact sealed native generations form the authority. The
operator preserves stable Maildir UUIDs and IMAP metadata, retained tombstones,
accepted queue responsibility, protected verifier generations and immutable audit
receipts. Scoped generation revocation preserves unrelated principals. A durable
barrier closes admission before desired-state commit; applied SQL state is durable
before native release. No anonymous stale-lock removal or database re-adoption is
allowed. See recovery.md for exact incomplete/aborted phase behavior.

The Dovecot authentication gate adds only the existing mail-owned control bridge
and bounded HTTP10004 in the existing policy container. No new host port, client
backend, secret attribute or container is added; native protocol/isolation/outage
replays cover it. Private networking retains MAIL-02 amendment B. The CLI never
changes application password files automatically; MAIL-04 owns coordinated client
switches and actual Ghost transactional integration.

Public evidence is whitelisted and checked against protected known synthetic
passwords/verifiers and private-key patterns. Secret-producing hash-command output
fingerprints are omitted; private originals remain protected. No databases/WAL,
keys, passwords, passdb, message content, Maildirs or backup data are published.
Purge partial-erasure recovery uses an explicitly constructed strict crash subset;
it proves guarded same-storage resume, not restoration on replacement storage.
Guest reboots similarly preserve existing storage; SMTP exactly-once is not claimed.

Requalify relevant paths after changing image/module/native writers, virtual-byte
accounting, filesystem/kernel-lock behavior, SQLite/Python binding, authentication
scheme, projection/journal/drain ordering, service topology or TLS configuration.
The future restore lot must include queue, register, SQLite/WAL, verifier/key
references, Maildirs and IMAP metadata coherently, including uncertain accepted
messages and independent receiver evidence. Keep Oxy-form ledger and deduplication
key unchanged. `accepted` is not proof of recipient receipt.
