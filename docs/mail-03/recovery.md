# Interrupted administration and guarded purge

## Normal generation protocol

The administrative database is under `durable/operator-state/admin`. SQLite WAL,
synchronous FULL and foreign keys are mandatory on the pinned local ext4 runtime.
The protected allocation intent and owner marker pin the directory/database
device+inode. Never remove them or resnapshot bootstrap JSON to repair a failure.
Back up SQLite consistently with its operation and revision manifest; never copy
live database/WAL files independently. A replacement-storage restore remains
`SMTP_RECOVERY_UNQUALIFIED`.

One service-root lock uses a live Linux flock descriptor, inherited by children;
lifecycle mutations use the same lock. The engine has its own crash-released
descriptor lock. Do not unlink locks or infer staleness from a PID file. Readers
take a coherent applied snapshot. CAS permits one concurrent winner; a loser
must read the new revision before planning a new intent.

1. Validate public intent and known revision under lock. Read/confirm bounded
   password input, if required, without logging it. Reserve a strictly increasing
   generation high-water value and journal `validated` durably.
2. Hash with the native bounded helper; store immutable verifier references
   separately. Prepare and native-check the sealed candidate; journal `staged`.
3. Verify the complete owned runtime/storage and static configuration match.
   Write the native recovery intent, then close SMTP/LMTP and authentication
   admission **before** committing desired SQLite state. Journal `committed`.
4. Journal `applying`, resume only the sealed target on existing guarded storage,
   publish complete private/public projections, flush/probe native caches, revoke
   affected sessions and verify the effective generation. Unrelated reads may
   continue. Never reuse a reserved generation after a failed attempt.
5. Commit the applied SQLite snapshot, revision and result receipt durably while
   admission is still closed. Verify/release admission, then journal terminal
   `applied`. A crash after the SQLite commit only resumes release/receipt.

The native intent precedes admission closure, so a crash cannot leave an anonymous
barrier with no sealed recovery target. Dovecot's authentication policy gate uses
the existing mail control network, sends no login/hash/password attributes and
fails closed on barrier or policy unavailability. Static configuration changes
require an explicit runtime upgrade; registry activation cannot silently claim
new templates over an older running container.

## Operator recovery

Keep the exact acquired engine, sealed candidates, owner markers, verifier
generations, SQL database/WAL, queue and all UUID Maildirs intact. Preserve logs
privately; do not print passdb files. Read:

```sh
bin/drumee-ctl --profile mail mail status --config /absolute/private/mail.json --json
bin/drumee-ctl --profile mail status --config /absolute/private/mail.json
bin/drumee-ctl --profile mail doctor --config /absolute/private/mail.json
bin/drumee-ctl --profile mail mail reconcile --config /absolute/private/mail.json --execute --json
```

Status distinguishes desired/applied revisions, pending request, native generation
and admission. Doctor flags an incomplete journal as MAIL_GENERATION_INCOMPLETE.
An unavailable or missing administrative authority is an error, not an invitation
to recreate it. Repair only the reported dependency/identity issue, then reconcile
the same request. Do not roll back security grants, reset counters, delete a
candidate, recreate a Maildir, reset a ledger or supply a replacement password to
the old request ID. If the password was lost before protected staging, recovery
records terminal `aborted`, returns MAIL_CANCELLED and leaves the applied state
unchanged. Use a new ID and newly entered password. Prepared empty resources and
reserved generations are retained for audit, never adopted as another object.

After a normal reboot, the mail-owned boot unit recreates only guarded existing
resources. Admission stays closed for an interrupted generation until reconcile
succeeds. A damaged runtime or candidate remains closed for repair. This is
same-storage recovery, not backup restoration. Accepted queues remain owned by
the accepting instance; pending/uncertain deliveries require receiver evidence,
not automatic resubmission. Exactly-once delivery is not promised.

## Quota changes with active writers

Quota changes additionally write a protected `quota-drain.json` intent under
operator-state. Postfix temporarily defers LMTP dispatch and gracefully retires
its old queue manager and delivery agents. Affected IMAP sessions are revoked;
unrelated IMAP reads remain usable. The engine waits for old LMTP recipient
contexts to finish and verifies the native UUID writer locks are free before
changing the complete userdb projection. It then probes both primary/internal
UUID limits and restores local dispatch before reporting native apply complete.
There is no Dovecot reload or forced termination of an active LMTP writer.

A slow existing LMTP transaction produces bounded MAIL_APPLY_INCOMPLETE (7),
closed admission and a retained pending request. The old applied quota remains
in force. Allow that accepted transaction to complete, then reconcile the same
request. Its final successful receipt can report over_quota:true if the now
committed data exceeds the newly requested smaller limit; it must already include
those bytes. Future growth refuses until space is available. Never cancel a queue
item or reset accounting to make the change succeed. Postfix sessions may retire
gracefully during this quota maintenance; password-only changes do not use it.

For operator investigation, inspect only these nonsecret fields:

```sh
jq '{contract,phase,from,to,mailbox_ids}' \
  /absolute/owned/service/durable/operator-state/quota-drain.json
```

Phases are draining, waiting, restoring and released. A foreign defer_transports
setting or unsafe native quota-lock inode refuses without repairing/overwriting
it. Repair only the proven owned lab/target resource, preserve all data and the
pending intent, then use `mail reconcile`. Reboot may clear the temporary runtime
defer setting; the persistent barrier/intent still requires the same guarded drain
on reconciliation. This is same-storage recovery, not backup restoration.

## Explicit purge maintenance

Delete first and retain messages by default. Purge is a separate single-UUID
operation with exact confirmation, known revision and request ID. Stop all four
mail services; no other running container may reference the mail root/storage or
socket volume. The entire local queue (including hold/defer/bounce/trace) must be
empty and unresolved-deliveries metadata absent/empty. Resolve responsibility
before maintenance; never delete queue items to satisfy this prerequisite.

The retained backup catalog uses `service.deployment.backup_root`, outside live
Maildirs and owned by the same operator:

* backup_root/owner.json (0600): drumee.mail-backup-owner/1, service_id, uid, gid.
* backup_root/mailboxes/UUID/BACKUP_ID (0700): independent `data` copy of that
  quiesced UUID subtree and manifest.json (0600).
* Manifest contract drumee.mailbox-purge-backup/1, mailbox_id, backup_id,
  service_id and exact snapshot inventory: every path/type/UID/GID/mode/nanosecond
  mtime/size/SHA256 and internal hardlink group. Preserve numeric5000:5000 owners,
  permissions, timestamps and hardlinks. Never hardlink backup to the source.

The qualification fixture `tests/mail/admin/purge.py` provides the exact catalog
construction and native independent-copy/inventory commands. Backup qualification
and coordinated restore are separate lots. A manifest alone is insufficient:
the engine checks every copied byte and all source metadata before activation.
Symlinks, special files, external hardlinks, unsafe modes, wrong owners, foreign
writers, wrong backup identity, changed content or queued responsibility refuse.
An invalid precheck is not journaled as a pending mutation and preserves both
copies. Stop-state checks occur again before each erasure/resume.

```sh
bin/drumee-ctl --profile mail stop --config /absolute/private/mail.json --execute
bin/drumee-ctl --profile mail mail mailbox purge UUID --confirm-mailbox UUID \
  --backup-id verified-backup-id --if-revision 23 --request-id REQUEST_UUID \
  --config /absolute/private/mail.json --execute --json
```

Purge journals a verified inventory before erasure. A partial erasure may resume
only if every remaining entry matches the retained backup; unexpected data closes
the operation for investigation. It preserves the six canonical UUID/home/Maildir
directory inodes and the existing empty quota-lock inode, while removing messages,
folder and IMAP metadata. The tombstone, verifier recovery material, audit and
reserved address remain; it does not enable address reuse. Native services are
temporarily verified behind closed admission and the operation leaves them
**stopped** on success. Start separately after reviewing the receipt. The backup
is never erased. There is no bulk purge or automatic retention expiry.
