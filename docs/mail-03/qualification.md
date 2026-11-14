# MAIL-03 isolated administration qualification

Status: **MAIL-03_BLOCKED — implementation and qualification in progress.**
No incomplete case below is counted as PASS. This lot does not qualify coordinated
Oxy-form or autonomous-service replacement-storage restoration:
`SMTP_RECOVERY_UNQUALIFIED` remains in force.

## Starting identities and PR dependencies

Infra starts at MAIL-02 PR38 `465d4e91553edd204b1e3b5ace9ad64791235403`;
Debian starts at PR13 `ad1c7be3c0a6860fb1cfa58918d79cd026828a95`. Both parent
PRs are drafts. MAIL-03 branches are `feat/mail-03-admin` in each repository.
The MAIL-03 PRs target their MAIL-02 branches so the incremental diff is visible;
none may be merged, published or deployed by this lot. Compare the eventual
final package inventory and image receipts with these frozen parents.

The native engine image remains
`sha256:ab41ba434fa20afd54f71f43fc31ad2aaa94260193a4e9b56cc0e5c971fb1a56`, with
quota module `01fec4a55d42add0d62b939216bec57869513b2dab6b55c83ae51c93dd22f4c5`.
The original106-file MAIL-02 evidence manifest was verified before work. New
unpublished Infra snapshots are acquired by closed archive/member integrity;
there is no sibling-source or registry fallback.

## Frozen acceptance cases

| ID | Required evidence | Current disposition |
| --- | --- | --- |
| CLI-01 | Every mailbox/alias/account verb, defaults, structured outputs, codes, collisions, reserved addresses, retained delete and guarded purge | BLOCKED — native coverage incomplete |
| CLI-02 | Real masked TTY/confirmation/cancel restoration; bounded exact FD input and unsafe-descriptor negatives; no credential in public surfaces | BLOCKED — TTY and full leakage audit pending |
| ROT-01 | Credential/grant changes on new and active SMTP/IMAP sessions; before/after final acceptance; unrelated reads preserved | BLOCKED — CLI session tests pending |
| TX-01 | CAS winner/conflict, request replay/content conflict/no-op; live descriptor locks; death at every journal/apply boundary, reconciliation and guest reboot | BLOCKED — crash/reboot matrix pending |
| RX-02/RX-04/IMAP-01 | Create/alias/rename/disable/delete: exact SMTP RCPT, immutable delivery UUID, Maildir/UIDVALIDITY/UID/flags/subscriptions retained and isolated IMAP | BLOCKED — final-artifact replay pending |
| AUTH-03/AUTH-04 | Distinct Ghost/Oxymotion SMTP-only principals and explicit envelope/header grants, revoked tokens and healthy local DSNs | BLOCKED — account CLI matrix pending |
| QUOTA-01 | Runtime increase/decrease, below-use report, atomic concurrent growth, deferred LMTP and space release, two UUIDs | BLOCKED — CLI quota driver pending |
| Regression | Affected MAIL-02 native cases, exact engines/configs, Debian/Infra suites, ShellCheck, packaging and final hosted jobs | BLOCKED — final references not frozen |

## Mechanism amendments to qualify

SQLite (CPython stdlib binding, exact runtime recorded per host) is the
administrative authority with WAL, synchronous FULL, foreign keys and a public
operation-event journal. Verifiers are stored separately in immutable0600 files;
no password or verifier is part of a public operation intent or receipt. One
live-descriptor lock serializes CLI/lifecycle mutations; the engine also replaces
its stale-directory mail lock with a crash-released Linux flock.

Registry activation can close admission before committing desired state and resume
its exact sealed target after private/public pointer interruption. A guarded
existing-storage restart keeps admission closed while reconciliation runs; it is
not a restore API or an ownership bypass. Optional mailbox credential generations
preserve unrelated principals across revisions; legacy projections keep their
MAIL-02 global-generation behavior. Optional account DSN UUIDs make an unavailable
monitored mailbox reject new submissions without dropping accepted mail.

Dovecot additionally joins the existing mail control bridge to consume the bounded
HTTP authentication gate in the existing policy container. No client joins that
bridge, no new host port is published, and no application backend is adopted.
Dovecot's request attributes are empty: the gate receives no password, verifier,
password hash or login. It refuses new authentication on a registry barrier or
policy outage; sender/header policy still enforces the final SMTP acceptance
boundary. This configuration/network amendment requires native isolation replay.
The upstream auth-policy interface is documented by
[Dovecot2.4.1](https://doc.dovecot.org/2.4.1/core/config/auth/policy.html);
actual behavior must be demonstrated with the pinned native binaries.

Preliminary evidence is retained separately from the final verdict. The initial
MAIL-03 snapshot passed45 MAIL-02 controls and nine real CLI/protocol/storage
scenarios. Those runs do not qualify later snapshots automatically.
