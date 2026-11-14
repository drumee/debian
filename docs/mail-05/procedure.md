# Cold checkpoint and replacement-storage operator procedure

Experimental until qualification.md is complete. Laboratory only in this lot.
Use the existing `bin/drumee-ctl --profile mail` dispatcher, an explicitly pinned
producer archive/closed consumer and the images recorded in the private manifest.
The backup worker is the MAIL-04 pinned Python image, network none, read-only
rootfs and bounded memory/PIDs. The source/PID scan runs the canonical read-only worker through non-interactive
host sudo because container /proc visibility refused PID1 even with SYS_PTRACE
and CHECKPOINT_RESTORE in this VM. The separate archive helper has no host PID
namespace and uses only DAC_OVERRIDE/CHOWN/FOWNER. A target needs a reviewed,
root-owned installed scan helper and explicitly approved privilege policy; lack
of access fails closed rather than assuming an absence of writers.
No helper receives a network route, password argument or password environment.

Pause application producers and the owned boot unit before a cold capture.
Keep an independent receiver record and a queue/IMAP metadata observation.
The source must be a dedicated owned ext4 mount; never archive a live shared
filesystem or use a path beneath the source device as the backup destination.

```sh
umask 077
bin/drumee-ctl --profile mail backup --config CONFIG \
  --archive NEW_PRIVATE_CHECKPOINT_DIRECTORY --execute
```

The command holds the same administrative lock, preflights the existing service,
cleanly stops all native roles, verifies no mounted container writer, scans host
process descriptors/mappings on the dedicated source device, rejects incomplete
administrative generations, and checkpoints SQLite/WAL. It captures the complete
service root, including all immutable candidates, durable spool/Maildir/IMAP,
registry/public/private state, SQLite authority/journal, owner markers, quota locks,
policy counters, TLS and DKIM generations. External declarative registry/verifier
inputs and secret-source files are copied into protected recovery-inputs; a
recovery-config points to those restored files. Client plaintext credential
projections, Ghost/MySQL/content and receiver evidence have separate owners and
are not silently included. Preserve their matched generations independently.

Unix sockets/FIFOs are ephemeral. Hard links, xattrs/ACLs and unsafe symlinks refuse
rather than being silently weakened. Numeric UID/GID, modes, mtimes and all regular
file hashes are retained in the private manifest. Public output contains only
aggregate counts and whole-archive/manifest integrity values. The source remains
fenced. To finish a routine cold backup without activating any copy, explicitly
verify/resume that same source:

```sh
bin/drumee-ctl --profile mail recovery-resume-source --config CONFIG \
  --archive PRIVATE_CHECKPOINT_DIRECTORY \
  --manifest-sha256 TRUSTED_MANIFEST_SHA256 --execute
bin/drumee-ctl --profile mail start --config LOGICAL_ROOT/recovery-config.json --execute
```

This verifies the source UUID/device/inode, capture operation, generation,
archive, software and absence of writers, then preflights the original seals.
It does not transplant identities, start daemons or change held-message status.
The source retains responsibility. Before subsequently restoring its archive,
stop/fence and preserve the current source, including messages accepted since
capture. Never resume it while its copy can assume responsibility. Multi-host
fencing is an operator precondition, not a distributed lease supplied by this CLI.

Preserve the original device without modifying its captured files. Stop/remove
only the stopped mail containers if necessary to release old mount references;
never remove durable volumes. Move/unmount the source and mount a distinct, empty,
owned ext4 replacement at the same logical service root. Record its independently
verified UUID. The root must be empty and0700 before allocation.

```sh
bin/drumee-ctl --profile mail restore --config CONFIG \
  --archive PRIVATE_CHECKPOINT_DIRECTORY \
  --manifest-sha256 TRUSTED_MANIFEST_SHA256 --target-uuid REPLACEMENT_UUID --execute
```

The trusted manifest digest must be retained independently; a digest obtained from
the same untrusted archive provides no authenticity. Verify transport/provenance
and encryption independently before use. Restore verifies the complete archive
before creating payload entries, extracts into a protected stage and verifies
metadata again. It journals the target UUID/device/inode and checkpoint, promotes
without overwriting existing data, explicitly rebinds resource and SQLite identities,
and holds every queued message offline with native postsuper. No daemon starts.
A retry must use the same checkpoint and target. Preserve interrupted extraction
stages rather than deleting them; conflicting target contents/identity refuse.

Reconcile every recipient with receiver/Maildir observations while the queue is
held. SMTP or LMTP final-ack loss is uncertain. An older checkpoint can contain
mail delivered after capture. Retain originals and decide per message; do not
resubmit from Ghost/Oxymotion or reset an Oxy-form ledger/deduplication key.

```sh
bin/drumee-ctl --profile mail recovery-release --config CONFIG \
  --manifest-sha256 TRUSTED_MANIFEST_SHA256 --execute
bin/drumee-ctl --profile mail start --config LOGICAL_ROOT/recovery-config.json --execute
```

Release performs final identity/native preflight; the queue stays held. Restrict
traffic to controlled laboratory clients/receivers, test TLS/AUTH, registry and
IMAP, then explicitly release only reviewed queue IDs using native postsuper.
Never bulk-release uncertain entries. Restore the matched client projection
files and recreate clients to rebind single-file mounts before releasing producers.

Rollback keeps both responsibility sets separate: stop/fence the replacement and
preserve its newly accepted mail before reactivating any original storage. Do not
copy an older queue over either instance, purge held data, or activate both copies.
A rollback implementation and uncertain-message reconciliation need native evidence
before they can be declared qualified. Coordinated Oxy-form recovery remains
SMTP_RECOVERY_UNQUALIFIED.

## Read-only validation of checkpointed WAL databases

SQLite3.46.1 cannot inspect the WAL-mode serialized database with deserialize
(`unable to open database file`), even after a clean TRUNCATE checkpoint. The
validator instead copies the exact database bytes to a protected temporary
directory in the network-less helper’s /dev/shm and opens it read-only. It never
patches the database header or the archive. The helper’s64MiB shared-memory limit
bounds this tested path; larger authority databases require capacity qualification.
The complete writer69ba692310186c3733fc632dc03f48d29afaeb0c file inventory is
explicitly pinned in checkpoint-compatibility.json for format1. Unknown writer
inventories refuse. Current-writer snapshots must match the current inventory.
The observed failure and byte-preserving correction are retained in evidence.

## Non-destructive abort before activation

```sh
bin/drumee-ctl --profile mail recovery-abort --config CONFIG \
  --manifest-sha256 TRUSTED_MANIFEST_SHA256 --target-uuid REPLACEMENT_UUID --execute
```

Abort is available only before the release boundary. It retains every target
entry, marks the target fenced/aborted and preserves the operation receipt. A
retry of that aborted target refuses; use a new authorized empty target for a
new restore. To return to the original source, retain the aborted target, mount
the original storage at its canonical logical root and run recovery-resume-source
against the latest checkpoint matching that source's capture operation. The
aborted operation must identify that exact source UUID/device/inode/owner.
A previously released copy cannot use this shortcut: stop/fence it, preserve its
new accepted responsibility and reconcile per recipient before any rollback.

Recovery errors use structured `drumee.mail-recovery/1` results: exit0 success,
2 invalid usage,5 authorization/target refusal,6 lock/dependency failure,
7 recovery-state conflict and8 integrity/storage/schema refusal. Existing mailbox,
alias/account and lifecycle command contracts remain unchanged. An accepted
start request is not protocol readiness: check native status and verified TLS/AUTH
before releasing producers. The fixture retains the initial premature postqueue
flush exit69 and uses a bounded native-readiness observation on replay.
