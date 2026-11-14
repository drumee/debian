# MAIL-05 qualification matrix (frozen before recovery execution)

**MAIL-05_BLOCKED** until every native recovery gate below has evidence.

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
