# OF-01R external SMTP resumption — alpha.6 handoff

## Distribution identity

Target lineage: `drumee/debian`, `feat/container-distribution`, profile
`profiles/minimal-application`. **Do not use Debian main.**

Consume the exact approved merge SHA recorded in the final receipt on
[distribution PR #11](https://github.com/drumee/debian/pull/11), after its
post-merge verification. Do not resolve a branch or substitute the qualification
build source. The final local handoff supplements this document with that merge
SHA and tree. The qualification image/plugin source is
`70522f033262d469bc1f6252ca8823def819c842`; it is not the final distribution pin.

- Infra: exact published `@drumee/infra-layer@0.1.0-alpha.6`.
- Producer: `09b7f28bce99ba3744e31a0ee5b2dde868a9a86a`, PR #34.
- URL: `https://registry.npmjs.org/@drumee/infra-layer/-/infra-layer-0.1.0-alpha.6.tgz`.
- Inventory: 44 files, 110826 bytes, including required `lib/smtp-auth.js`.
- SHA256: `562a01bf5d8dba6151bf3a1768e56655df9e9302ed2ea6f072a4ed72eb177874`.
- SRI: `sha512-ZuGENEDYE1Ug6FJYzvSR+MG8zzOaBMBkYhgx+5nNR5OKMDBHpOvCfdzDe1XNfNz7fKqRfCHFQZGlxvYQzEm+YQ==`.
- Complete member receipt: `profiles/minimal-application/infra-source-lock.json`.
- Server Runtime remains exact alpha.4 with its unchanged profile lock/SRI.

From a clean detached worktree at the approved merge SHA:

```sh
npm ci --ignore-scripts --no-audit --no-fund --prefix profiles/minimal-application
node -e 'console.log(require("./profiles/minimal-application/scripts/infrastructure-source").verify())'
npm test --prefix profiles/minimal-application
python3 tests/minimal-application/plugin-artifact.test.py
```

## Required Oxy-form changes in the separately authorized resumption

Reverify draft Oxy-form #3 (known HEAD
`0cce3e7869ea08adc991891c00bc69238ca03d62`) and preserve intervening work.
Update **together** the Debian revision, producer revision, Infra version, SHA256
and SRI in `scripts/distribution.cjs`, corresponding tests and active documents.
Retain clean-worktree and every-installed-byte verification. Old-pin refusal is
intentional; no local producer/archive fallback or floating tag is allowed.

Also change **only the upstream descriptor** in `scripts/configure.cjs` from
`smtp-relay-credential` to `smtp-external-credential`, consumers `["mail"]`.
Changing pins alone leaves the old restrictive import type in place. Internal
submission stays `smtp-relay-credential`, with its existing application/mail
consumers. Keep trusted sender/recipient/relay configuration and native transport.

Read the producer's exact byte contract before importing provider data: account
and secret are strict UTF-8 without BOM, 1–255 bytes, no NUL/CR/LF; account colon
or leading ASCII map whitespace and trailing ASCII secret whitespace refuse.
Final LF/CRLF is refused, not trimmed. Preserve accepted bytes in private files;
do not change the provider password, normalize it, expose it in arguments/logs,
or paste it into chat. Use the approved private-file mechanism in that mission.

## New artifacts and campaigns

Build/verify the real forms plugin and application image through the pinned
distribution. Record their source, member inventory, integrity and image IDs.
Prove plugin byte identity if reusing a previous artifact; otherwise issue a new
receipt. Debian's synthetic qualification plugin/images are **not Oxy-form artifacts**.

Replay the complete backend campaign with the actual plugin: validations/abuse,
fixed SMTP envelope, native dispatch/ACLs, `/-/` and `/-/svc/`, private loopback,
candidate Nginx/static/blog/TLS behavior, ledger/idempotency, stop/start, ordinary
rollback and controlled failed-start recovery with application + SMTP + DKIM.
Check data, queue, secrets and ledger preservation and all identity/network refusals.

Then, only with separately authorized real parameters, qualify provider account
and envelope permissions, verified STARTTLS/certificate/peer name, authentication,
timeouts/refusals/uncertain delivery and designated mailbox receipt. The trust
bundle must cover the private relay issuer and actual provider roots; do not alter
system trust or reuse production HTTPS private keys. Distinguish relay acceptance
from mailbox receipt and obtain accessible SPF/DKIM/DMARC evidence separately.

`SMTP_RECOVERY_UNQUALIFIED` remains: no spool backup/restore or exactly-once
delivery guarantee. A 2xx RPC response is not mailbox receipt; do not blindly retry
`CONTACT_DELIVERY_UNCONFIRMED`. No newsletter, prospecting or visitor auto-reply.

## Boundaries

This convergence does not validate OF-01R or a real provider/mailbox. Oxy-form #3
is unchanged/draft; public forms stay disabled. Known Debian debt remains visible:
91 ShellCheck diagnostics and two packaging failures, unchanged from the base.
Profile/shared hosted checks and final exact-SHA receipts must be read separately
from that debt. No quality/protection setting was weakened. Debian main/IL-5.10-C,
publication, production Nginx/DNS/firewall and deployment are outside this lot.
