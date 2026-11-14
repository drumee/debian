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
fenced; do not restart it while its copy can assume responsibility.

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
