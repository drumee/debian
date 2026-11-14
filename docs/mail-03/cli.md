# MAIL-03 administrative CLI reference

The only public entry point is `bin/drumee-ctl`. Select both the lifecycle owner
and the administrative namespace explicitly:

```sh
bin/drumee-ctl --profile mail mail status --config /absolute/private/mail.json --json
bin/drumee-ctl --profile mail mail mailbox show contact@oxymot.fr --config /absolute/private/mail.json --json
```

The configuration, bootstrap registry and verifier inputs remain MAIL-02 private
files. Initial administration adopts the verified running projection exactly
once. After initialization, SQLite is authoritative: editing bootstrap JSON does
not administer the service. Missing/replaced databases, foreign directories and
ownership markers refuse automatic adoption. The profile is experimental; these
commands do not authorize production installation or exposure.

## Commands

All mutations require `--execute`. Automation additionally supplies a fresh UUID
`--request-id` and the known applied `--if-revision`. Every invocation accepts
`--config FILE` and `--json`. `--help` requires neither configuration nor secrets.

| Namespace and verb | Object / options | Result |
| --- | --- | --- |
| `mailbox list` | `--limit 1..1000` (100), `--cursor TOKEN`, `--include-deleted` | UUID-ordered applied snapshot; revision-bound cursor |
| `mailbox show` | UUID or primary address; optional `--include-deleted` | Flags, aliases, quota, exact observed virtual bytes/messages and observation time; no message contents |
| `mailbox create` | Address, optional `--quota-bytes N`, protected password input | Random stable UUID; receive/IMAP enabled, submission disabled |
| `mailbox update` | UUID/address; one or more `--receive true\|false`, `--imap true\|false`, `--submission true\|false` | Explicit flag assignment |
| `mailbox rename` | UUID/address, `--to ADDRESS`, `--old-address alias\|reject` (alias) | Same UUID, Maildir, home, quota, verifier and IMAP metadata; old login invalidated |
| `mailbox enable`, `disable` | UUID/address, required `--scope receive\|imap\|submission\|all` | Set selected scopes; no implicit toggle |
| `mailbox delete` | UUID/address | Tombstone, all scopes off, aliases/grants retired; messages and verifier recovery material retained |
| `mailbox quota` | UUID/address, `--bytes N` | Hard quota 1 MiB..1 TiB in virtual RFC822 bytes; below-use success reports `over_quota:true`, no deletion |
| `mailbox password` | UUID/address, protected input | New salted verifier and credential generation |
| `mailbox purge` | Deleted UUID, `--confirm-mailbox UUID --backup-id ID` | Separate guarded maintenance operation; see recovery procedure |
| `alias list` | Optional `--mailbox UUID\|ADDRESS`, paging/deleted options | Applied aliases and target UUIDs |
| `alias create` | Address, `--mailbox UUID\|ADDRESS` | One live mailbox target; no credentials |
| `alias update` | Address, `--mailbox UUID\|ADDRESS` and/or `--receive true\|false` | Repoint reports old/new UUID; revokes previous sender grants |
| `alias delete` | Address | Retires address and explicit sender grants; no mailbox deletion |
| `account list`, `show` | Paging options / immutable account ID | SMTP grants, enabled flag and generation, never a verifier |
| `account create` | ID, repeatable `--envelope-from ADDRESS --header-from ADDRESS`, `--dsn-mailbox UUID\|ADDRESS`, protected input | SMTP-only principal, disabled by default |
| `account update` | ID; one or more complete grant sets or DSN destination | Each supplied set replaces its previous set; credential generation increases |
| `account enable`, `disable`, `delete` | ID | Explicit state change; delete retains a reserved ID and audit tombstone |
| `account password` | ID, protected input | Rotate only that principal; no two-password grace period |
| `reconcile` | `--execute` | Resume the pending sealed request, or successful no-op |

Addresses are lower-case ASCII in declared domains. Collisions are case-insensitive;
quoted local parts, wildcards, forwards, implicit plus addressing, alias chains
and loops refuse. Deleted/retired addresses and account IDs remain reserved.
Aliases cannot override target receive disable. Postmaster/abuse routes that were
available cannot be removed while public MX admission is enabled.

Receive disable refuses new RCPT to primary and aliases. Existing accepted mail
retains its immutable internal UUID and can still complete LMTP delivery. IMAP
disable rejects new authentication and kicks the affected sessions. Submission
disable revokes new AUTH and cached SMTP identities at the next MAIL/DATA (421).
Unrelated mailbox sessions remain usable. Application accounts never gain IMAP
access. An unavailable monitored DSN route temporarily refuses new submissions.
Envelope grants resolve to the chosen live DSN mailbox; header-only local grants
need not be receiving addresses, but cannot reuse a tombstone. An alias repoint
or deletion removes its prior explicit grants instead of transferring privileges.

Rename keeps the original address as a receiving-only alias by default; `reject`
retires it. The new primary is the only IMAP login. Old sender grants are removed
until explicitly granted again. There is no filesystem move or message copy.

Quota transitions wait for old local-delivery contexts and revoke affected IMAP
writers before publishing the limit. A busy writer returns incomplete with the
old applied revision; reconcile after it completes. A smaller quota can already
be below the bytes committed by that old transaction, which success reports as
over_quota:true. It must not report success before those bytes are accounted.
Postfix may retire existing SMTP sessions gracefully during this maintenance;
unrelated IMAP sessions remain usable. See the quota section in recovery.md.

## Protected input

Interactive mode presents the public change at the locked revision and asks for
`yes`. Password input uses the controlling terminal twice with echo disabled;
cancel/mismatch restores terminal settings. Automation reads exactly one entry
to EOF from `--password-fd N` (3..128), never from an argument or environment.
The FD must be read-only, blocking, owner-matched, mode0600, a single-link regular
file or a private pipe. Devices, TTYs, sockets, O_PATH, unsafe modes and replaced
targets refuse. The caller must open a trusted path without following symlinks
and own the pipe writer; the CLI can verify the open inode and resolved target,
not reconstruct a caller's historical pathname traversal.

Input is exact UTF-8, 16..1024 bytes, no NUL/CR/LF/BOM; no trim or normalization.
No password option, password-file option or generated-secret output exists.
RLIMIT_CORE is zero; inherited unrelated FDs are closed, child environments are
scrubbed, and child stdout/stderr are captured and never relayed. The pinned native
Dovecot produces Argon2id v19 m=65536,t=3,p=1 with random salts in a bounded,
network-free helper; weaker/unrecognized parameters refuse.

```sh
# Populate this private single-link file out of band, without a trailing newline.
exec 3</protected/mail/ghost-password
bin/drumee-ctl --profile mail mail account password ghost \
  --config /absolute/private/mail.json --password-fd 3 --if-revision 17 \
  --request-id 9651d3d7-d35e-4cb9-8eaf-9512bbdd6336 --execute --json
exec 3<&-
```

The service stores only verifiers in immutable0600 generations. Application
operators separately stage/switch their own private password projection after
server activation. Hold/reconcile requests across this gap. Preserve Oxy-form's
pending/uncertain ledger and deduplication key; `accepted` is not recipient receipt.
Ghost and Oxymotion use distinct IDs and grants. No application configuration,
restart or production credential is changed by this CLI.

## JSON and errors

One stdout object uses `drumee.mail-cli/1`, `ok`, `code`, desired/applied revisions,
and `data`. Mutations also return operation_id and changed. Lists contain items,
next_cursor and snapshot_revision. Usage is an advisory exact observation, not a
capacity reservation; unavailable observation returns null counts. No verifier,
secret reference, native passdb or message body is projected.

| Exit | Codes | Action |
| --- | --- | --- |
| 0 | OK, including changed:false | Preserve receipt |
| 2 | MAIL_USAGE, MAIL_VALIDATION, MAIL_PASSWORD_INVALID, MAIL_SECRET_INPUT_UNSAFE | Correct input |
| 3 | MAIL_NOT_FOUND | Re-read identity |
| 4 | MAIL_ADDRESS_CONFLICT, MAIL_REVISION_CONFLICT, MAIL_REQUEST_CONFLICT, MAIL_DOMAIN_IN_USE, MAIL_PURGE_REFERENCED | Inspect current state; no blind retry |
| 5 | MAIL_NOT_AUTHORIZED, MAIL_RESOURCE_IDENTITY_MISMATCH | Repair authorization/identity, never adopt foreign resources |
| 6 | MAIL_LOCK_BUSY, MAIL_DEPENDENCY_UNAVAILABLE | Bounded retry same request |
| 7 | MAIL_APPLY_INCOMPLETE, MAIL_RECOVERY_REQUIRED | Inspect pending operation, reconcile |
| 8 | MAIL_STORAGE_UNSAFE, MAIL_INTEGRITY_FAILURE, SMTP_RECOVERY_UNQUALIFIED | Operator investigation; no destructive fallback |
| 130 | MAIL_CANCELLED | Inspect receipt; use a new ID for a new password |

Errors expose only sanitized codes, optional native dependency_code and recovery
phase. A nonzero result does not prove a message was never accepted. Same UUID
and same public intent replay the stored receipt without reading another FD;
changed intent conflicts. No password-derived idempotency hash is exposed.
