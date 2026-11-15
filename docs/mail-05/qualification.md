# MAIL-05 qualification matrix (frozen before recovery execution)

**Final result: MAIL-05_QUALIFIED** for the isolated standalone protocol and the
exact native SHA/digest set recorded below and in the paired Oxymot dossier.
SonarCloud and recovery-contracts pass at Oxymot
`aab4b7cd58d388c69679a533a2907d86a43d0cc9`. Coordinated Oxy-form remains
**SMTP_RECOVERY_UNQUALIFIED**.

Frozen initial decision: MAIL-05_BLOCKED until every native recovery gate below
had evidence. The initial-status column is retained as historical planning data.

Dependencies: Debian PR16 d50cf30a287c829832e6748c5b6ffcd8d976fa9e;
Infra PR39 1b60818f4f60cc6b54976184dbd6f0585b717a68;
Oxymot PR121 db47ccf6f55473e82d90173c69ff1df6ca19822e.
The incremental Infra branch adds explicit offline storage binding and fencing;
the Debian branch adds operator orchestration. Neither changes native images,
quota module, transport rendering or the capture/relay contracts.
The alpha.6 method at Infra PR37 fe35d5198a381184336aeaa9331213744cf1e12c
is a methodological reference, not standalone-profile recovery evidence.

The protocol deliberately retains the canonical logical root on a distinct,
operator-authorized ext4 mount. Source and target UUID/device identities must
be different, and the source stays fenced and preserved. Relocation to a new
logical root, other filesystems, unlisted runtimes and archive migrations require
separate qualification. Archives are private0600 inside0700 directories. Offsite
transport/encryption/retention and decryption-key custody need target decisions.

| ID | Required native evidence | Initial status |
| --- | --- | --- |
| BK-01a | CLI-created mailbox/alias/quota; used boxes with folders, read/unread flags, subscriptions, UIDVALIDITY/UID | BLOCKED |
| BK-01b | Cold services and registry; no Docker or host-process source writers; consistent SQLite checkpoint; complete private manifest/integrities | BLOCKED |
| BK-01c | Distinct authorized replacement storage; exact archive/metadata validation; authoritative and immutable candidate identity rebind; no automatic activation | BLOCKED |
| BK-01d | Alias/local SMTP-LMTP, IMAP metadata, credentials, quotas and sender grants restored together | BLOCKED |
| BK-01e | Real Ghost invitation/reset and synthetic Oxymotion verified STARTTLS/AUTH/DKIM after recovery | BLOCKED |
| BK-02a | Known deferred and partial multi-recipient queue disposition, independently witnessed per recipient | BLOCKED |
| BK-02b | Lost final SMTP acknowledgement: durable receiver copy, queue uncertainty, observed duplicate after explicit retry | BLOCKED |
| BK-02c | Lost final LMTP acknowledgement: durable Maildir copy, queue uncertainty and duplicate possibility | BLOCKED |
| BK-02d | Older checkpoint reintroduces delivery completed after capture; review while held | BLOCKED |
| BK-NEG | Corrupt/incomplete archive, incompatible schema, inconsistent generation, wrong permissions, unauthorized/occupied target refuse before activation and preserve data | BLOCKED |
| TX-01 | Interrupted extraction/promotion/sealing, retry of same checkpoint and rejection of conflicting operation | BLOCKED |
| LIFE-02 | Normal Docker26 VM reboot on replacement mount, fixed storage identity, network protection and client reconnect | BLOCKED |
| OBS-01 | Restore duration and capture scope; sanitized evidence and known-secret disclosure checks | BLOCKED |
| REG | Affected MAIL-02/03/04 native and operator controls; required CI on final SHAs | BLOCKED |

Unit archive tests and rendering checks are supporting evidence, not protocol
qualification. Never infer recipient receipt from an application's HTTP success.
Never promise exactly-once delivery. Coordinated Oxy-form file/ledger/key recovery
remains **SMTP_RECOVERY_UNQUALIFIED**, irrespective of the standalone verdict.

## Recovered campaign on testbox (2026-11-15)

The frozen initial statuses above are retained. Execution is on `testbox`, in
QEMU guest `mail02-qualification` inside outer container `mail02-qualification-vm`;
Docker26.1.5+dfsg1, kernel6.12.116+deb13-amd64. The local workstation only edits
sources and controls SSH. Its reboot is never LIFE-02 proof.

The guest retained `run`, `run2`, `final-run`, private archives/logs and all original
and replacement filesystem images. The final campaign's phase-A PASS and first
reboot, quota checks and checkpoints3/4 survived. After observing the exact queue,
source inventories and source-resume fence, execution resumed at the failed
startup-flush step rather than replaying account/message creation. The failure
receipt remains preserved. The final current-writer roundtrip and second actual
guest reboot pass, with original queue responsibility and IMAP metadata intact.

Tested writer/reader remains7971ff231c1dd5109a973b8e7db24cbdf91f666a, producer
cc33e55f1e30167bc685757b9f66e62539b75483 and archive SHA256
3168ba3e91b696cfac9d6f6d7fbc098379ba69d9b32d6e9657ef388c03c6a365. Driver freeze
is Oxymot487f52cf501f3e0331bd05997e40565f79261414. Final roundtrip payload SHA256
is d2c642913f0f4a3d26aa8cb2573d4c9043d85ca1bfb8b21e8a212b273d43943d,
applied generation16, replacement UUID d41edca7-6c91-4df9-8995-af0f8a4a62a6.
All52 installed consumer members and current-writer/reader inventory equality
are verified in the actual guest.

The paired [Oxymot qualification](https://github.com/somanos/oxymot/blob/feat/mail-05-recovery/docs/mail-05/qualification.md)
contains the mapped native matrix, exact commands/source hashes, safe aggregate
archive identities, SMTP/LMTP lost-ack duplicates, older-checkpoint recipient
replay, final witness/retention and MAIL-06 handoff. The initial native interruption
observation covers the verified stage; extraction/promotion/sealing/hold are
explicitly supplemental, not inferred from it. The initial source security gate
block is subsequently resolved at Oxymot aab4b7c. The supplemental native matrix now passes:
SIGKILL during extraction, partial promotion, sealing and offline hold, exact
checkpoint resume, abort of the never-activated copy, then one original-source
delivery. Its driver is Oxymot4e39d6f2fac38ba243fae3a182d5a7c60641d745;
checkpoint9 SHA25679945069fdeaca0a66d83f32ddaa9862bdee5f509963bca35f24031641223ed3. Oxy-form
stays SMTP_RECOVERY_UNQUALIFIED; no merge/publication/production action follows.


## Final fixture-security closure

The exact tested Debian writer/reader and all 52 producer members remain unchanged.
The paired Oxymot correction removes the five backtracking regexes, validates and
bounds quota rounds, and validates the entire bounded tar before making an
exclusive private copy. GNU tar 1.35 omits the caller-selected entry from that copy;
no input TarInfo object is passed to an archive writer or extracted to disk.
All required source gates pass with zero Sonar new/accepted issues or annotations.
Ten adversarial tests and six read-only controls in the original Docker26 guest
verify all 37 durable witness IDs, observer imports, unchanged 20/2 quota rounds,
byte-identical negative fixture and pinned-client imports. No original service or
queue is changed by these fixture compatibility tests; no full native rerun on the
fixture remediation commit is claimed. Earlier blocked snapshots remain historical.
The paired source/compatibility/gate receipts and MAIL-06 handoff are authoritative
for this final isolated decision. Production installation, release and migration
remain separate authorized work; Oxy-form stays SMTP_RECOVERY_UNQUALIFIED.
