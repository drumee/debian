# Infra Layer alpha.6 distribution convergence

## Immutable acquisition

Target lineage: `feat/container-distribution`, starting at
`2d2fd20d7a8116ae5023088cc4129246afe09c24`. Debian main/IL-5.10-C is separate.

The minimal-application operator consumes exact published
`@drumee/infra-layer@0.1.0-alpha.6` through its canonical npm lock, resolved URL,
SRI and closed member receipt. Producer: PR #34, commit
`09b7f28bce99ba3744e31a0ee5b2dde868a9a86a`.

- URL: `https://registry.npmjs.org/@drumee/infra-layer/-/infra-layer-0.1.0-alpha.6.tgz`.
- Archive: 44 regular files, 110826 compressed bytes, 391815 unpacked bytes.
- SHA256: `562a01bf5d8dba6151bf3a1768e56655df9e9302ed2ea6f072a4ed72eb177874`.
- SRI: `sha512-ZuGENEDYE1Ug6FJYzvSR+MG8zzOaBMBkYhgx+5nNR5OKMDBHpOvCfdzDe1XNfNz7fKqRfCHFQZGlxvYQzEm+YQ==`.

Published bytes agree with npm metadata, the producer receipt and every member
of the qualified Git source. The additional `lib/smtp-auth.js` is the required
canonical validator/native serializer; it is explicitly checked in the full
44-member hash receipt, not admitted by changing a count alone. Missing, extra,
modified or linked files still refuse before building. No local archive or
neighboring producer checkout resolves the dependency. Observed next=alpha.6;
the tag does not resolve the lock. Registry signatures are not a Git attestation;
no gitHead/attestation is supplied or invented. Historical alpha.1 is the only
observed producer release tag.

## SMTP contract and qualification boundary

Internal Drumee identifiers and submission credentials are unchanged. External
accounts accept simple names, complete addresses and opaque UTF-8 names within
the producer contract. Upstream secrets must use import-only
`smtp-external-credential` for the expanded byte contract; submission retains
`smtp-relay-credential`. Accounts/secrets are 1–255 UTF-8 bytes without BOM,
NUL, CR or LF. Account colon/leading ASCII map whitespace and trailing ASCII
secret whitespace refuse; final LF/CRLF is refused, never silently stripped.
Accepted punctuation, separators, leading/internal whitespace and Unicode must
reach SASL unchanged. TLS/certificate/peer-name verification remains mandatory.

`tests/minimal-application/relay-auth.js` exercises the installed distribution,
canonical import/projection, generated native Postfix map and native plugin
submission against a separately isolated TLS SMTP fixture. Its pinned test-only
smtp-server dependency does not change the profile or application dependencies.
It distinguishes private relay acceptance, authentication and actual synthetic
sink receipt, and checks refusal, private map permissions and absent shell expansion.

The existing complete real profile campaign and mixed application/SMTP/DKIM
failed-start recovery must also pass before merge. Producer results do not replace
consumer execution. Qualification results and exact source/image receipts are
added after execution; this initial acquisition commit does not assert completion.

Server Runtime remains alpha.4, minimal-kernel remains unchanged, and no runtime
operator or CI implementation is modified. Known 91 ShellCheck findings and two
packaging failures must be compared with the baseline and retained as failures.
The owner's targeted-merge authorization permits unchanged historical debt;
it does not disable checks, repair IL-5.10-C or converge Debian main.

No actual provider/account, owner secret, external message, production deployment
or public form activation is used. Oxy-form #3 remains draft and unchanged.
`SMTP_RECOVERY_UNQUALIFIED` remains: neither SMTP spool backup/restore nor
exactly-once delivery is provided by this convergence.
