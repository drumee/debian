# MAIL-04 handoff

Use the incremental draft PRs [Debian15](https://github.com/drumee/debian/pull/15)
and [Infra39](https://github.com/drumee/infra-layer/pull/39), based on unmerged
MAIL-02 drafts13/38. Final verdict, artifact receipts and evidence are in
qualification.md; incomplete scenarios are not acceptance evidence.

MAIL-04 owns real application integration: independent Ghost transaction-only and
Oxymotion submission accounts, restricted exact envelope/header grants, protected
client password projections, certificate verification, per-application rotation
gaps and acceptance/uncertainty handling. Never share credentials or give those
principals IMAP privileges. The administrative CLI does not restart applications,
edit their credentials or change DNS, PTR, public ports or production firewalls.

Preserve the Oxy-form ledger and deduplication key. Account password rotation is
server-first, then atomic replacement of that application's private projection;
there is no two-password grace window. Hold new work across the switch and inspect
outcomes before retries. Ghost transactional email delivery must be demonstrated
with its actual qualified configuration in its own integration lot.

Keep native quota and private-network mechanisms intact. No raw Maildir writer
may bypass the common UUID lock and virtual-byte accounting; quota observations
in CLI output are not capacity reservations. New runtimes, image/module bytes,
filesystems, network topology, credential scheme or projection/reconciliation
mechanisms require relevant native requalification.

Runtime quota changes additionally defer local Postfix dispatch and drain old
recipient contexts before publishing a limit. This fixes the observed mail03.6
stale-LMTP admission failure without changing the qualified image/module. Busy
drains retain closed admission and require the same request's reconciliation;
they never kill an active LMTP writer. Include quota-drain intent with the other
operator state in any future restore design. A successful shrink below bytes
already committed by an old transaction reports over_quota:true. Applications
must tolerate graceful SMTP session retirement during this quota maintenance;
unrelated IMAP reads remain usable. Password-only changes retain their scoped
generation-revocation behavior.

`SMTP_RECOVERY_UNQUALIFIED` remains independently for coordinated Oxy-form state
and for autonomous queue/registry/SQLite/verifiers/Maildir/IMAP/TLS/DKIM restore on
replacement storage. Same-storage interruption/reboot and verified purge backup
do not qualify those restores. Preserve accepted queues and receiver evidence;
never infer recipient receipt from an application `accepted` entry or promise
exactly-once delivery. Publication, merge, deployment and DNS/PTR are separate
owner decisions.
