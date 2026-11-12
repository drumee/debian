# MAIL-02 independent mail profile candidate

Draft delivery: [Debian PR #13](https://github.com/drumee/debian/pull/13) and
[Infra PR #38](https://github.com/drumee/infra-layer/pull/38). The complete
[qualification matrix](https://github.com/drumee/infra-layer/blob/feat/mail-02-service/docs/mail-02/qualification.md)
and [reproduction steps](https://github.com/drumee/infra-layer/blob/feat/mail-02-service/docs/mail-02/reproduction.md)
include the blocking failures and MAIL-03 handoff.

This profile is an unpublished isolated candidate, not a qualified production
mail service. Its exact producer is locked in
[`profiles/mail/infra-source-lock.json`](../../profiles/mail/infra-source-lock.json):
Infra source `c2552ac7b57771d72e61901582563112e2c3c26d`, package
`0.1.0-alpha.7-mail02.0`, archive SHA256
`635926f7a51c276cf3ce28c93954dcabfb07d3c1451c8e0991752240688f75c1`.
The implementation base is `feat/container-distribution` at
`ff6e6b399128e6332c984fc2e8e60f660bd5f881`, not Debian main.

Design references are Debian MAIL-01 PR [#12](https://github.com/drumee/debian/pull/12)
at `3c91036f95528e3f9baa04cb78b2b74ae96f63a1` and Infra MAIL-01 PR
[#36](https://github.com/drumee/infra-layer/pull/36) at
`2328b28b126355e40f18815e74c20e203ca6388f`. Alpha.6 cold queue recovery PR
[#37](https://github.com/drumee/infra-layer/pull/37), source
`6cc3483991b95d0f0c68e46ef9d62d1ca917c5f5`, supplies future recovery scenarios;
it does not qualify restoration of this new profile.

## Acquisition and boundaries

```sh
# The unpublished archive must be supplied locally. No npm-registry fallback.
node profiles/mail/acquire.cjs /absolute/path/drumee-infra-layer-0.1.0-alpha.7-mail02.0.tgz
node profiles/mail/build.cjs
node --test tests/mail/profile.cjs
bash tests/run-all.sh
```

Acquisition checks SHA256 and SRI before npm installation with scripts disabled.
Every invocation validates a closed installed inventory, rejects altered/extra
files and symlinks, and imports only the locked consumer. The native image builder
requires the exact alpha.6 tools base config ID before using its local tag. The
APT snapshot inherited from that base and all Dovecot 2.4 package versions are
pinned. The local native image tested is
`sha256:f3fe9dc4eeb6cb8b1ba3efd61c6743159ba8313e2901983e9300ca6e4a5d733b`.
No image or package publication is performed by these commands.

The existing `bin/drumee-ctl` dispatches `--profile mail` before legacy detection.
It does not reuse the Team mail role or minimal-application project. Four owned
services, separate edge/control networks, persistent spool, UUID Maildirs,
public/private registry projections and operator state live under the mail root.
Application lifecycles do not own them. Secrets are imported from protected files;
the registry projection never contains plaintext passwords. The versioned wrapper
schema and disabled example are in `config/drumee.mail.schema.json` and
`config/drumee.mail.example.json`. Render supports validate/compose only for mail;
Team outputs are refused. It does not generate secrets for this profile.

```sh
bin/drumee-ctl --profile mail validate --config /absolute/private/mail.json
bin/drumee-ctl --profile mail plan --config /absolute/private/mail.json
node config/render.mjs compose --config /absolute/private/mail.json
bin/drumee-ctl --profile mail install --config /absolute/private/mail.json --execute
bin/drumee-ctl --profile mail status --config /absolute/private/mail.json
bin/drumee-ctl --profile mail stop --config /absolute/private/mail.json --execute
```

Only a synthetic config with `acceptance:true`, protected registry/verifier files,
real immutable local image IDs and synthetic TLS/DKIM files may start. The API
refuses target activation. The example's zero image IDs cannot activate anything.
Repeated same-candidate install preserves container identities; changed prepared
state conflicts rather than silently replacing an active revision. `status` and
`doctor` are currently runtime summaries, not completed operational monitoring.
`backup` and `restore` explicitly return `SMTP_RECOVERY_UNQUALIFIED`.

`drumee-ctl mail` administrative mailbox/alias/account/password verbs remain
MAIL-03. This candidate reserves that namespace and returns
`MAIL_ADMINISTRATION_RESERVED_FOR_MAIL03`; it does not implement them early.

## Results and blocking gates

The Infra MAIL-02 dossier contains the complete receipts and PASS/FAIL/BLOCKED
matrix. The tested package passes 42 native transport/storage/security checks on
the workstation and repeats the same checks in a real isolated VM. Reboot with a
nonempty quota-deferred queue, registry/key/body persistence and missing/wrong spool
negative controls pass. Eight synthetic independent application lifecycle controls
pass. These are account fixtures, not a real Ghost application compatibility claim.

Debian's general suite passes 331 checks; the locked-profile suite passes 3 tests.
The explicit native lifecycle test passes 5 checks against the same installed
archive, including repeated install and undeclared network refusal:

```sh
# SOURCE is a retained private run directory created by Infra's native harness.
python3 tests/mail/native-lifecycle.py /absolute/private/SOURCE
```

The receiver also proves a security failure: locally authoritative client
Authentication-Results headers are not removed. Other MAIL-02 blockers include
private source CIDR enforcement, full runtime image/mount ownership checks,
certificate renewal/rollback, remaining MX/TLS/recipient faults, quota concurrency
and changes, disk-pressure/abuse controls, whole-service pre-Docker storage guards
and operational alerts. Keep these drafts unmerged and unpublished.

MAIL-03 must implement the authoritative registry, protected password input,
transaction journal, revisions/request-id idempotency and retained deletion/rename
semantics after the transport gates are fixed. The current JSON projection is
not an authoritative administration database. The complete new-profile recovery
and coordinated Oxy-form recovery remain `SMTP_RECOVERY_UNQUALIFIED`; preserve
all existing queues, Oxy ledger and deduplication key.

**MAIL-02_BLOCKED**
