# IL-5.9-B — Debian consumer realignment

## Change and provenance

Debian now acquires Infra Layer from the immutable qualified source
`aa9057f224f4ae5cf80d777e3cb2fad092193fb1`, replacing
`c6ef6e9b8d33921ffa39c289490067adfc63a8b0`. Selection, archive inspection and
separate source/npm checksums are in [source selection](IL-5.9-B-source-selection.md).
No registry alpha.3 dependency is assumed or selected.

| Identity | Previous active value | New active value |
| --- | --- | --- |
| Git revision | `c6ef6e9b8d33921ffa39c289490067adfc63a8b0` | `aa9057f224f4ae5cf80d777e3cb2fad092193fb1` |
| Archive SRI | `sha512-/XFgDPrCJkuk9sEbLf5GGJ1Z55mueK85t77swiB4i/0s6OvdlrGqd9MUE9e8AnyMOi0nBUOl+W2h8FlqDZdX2Q==` | `sha512-faoNlMWBO05FM+ozsuGu9tqFgq/IYc9WJwb4KCyZcZiTlEIrgJ9QLqLxslTADdipaItg02r2f6qFG07HDxhVqA==` |
| Server Runtime | `0.1.0-alpha.4` | Unchanged, including npm SRI and transitive lock entries |

Commit `a7a756f` contains the source/lock change. Acceptance additions are in
`ccaa839bf13ab163025e868b21f16516c87d1ff9`; clean images and execution receipts
refer to this exact source revision. Evidence commit `8d9ffd0` adds reports only.
Subsequent documentation commits preserve those executable bytes; they are not
claimed as separate image builds or repeated acceptance runs.

## Exact changed paths and purpose

Paths relative to the repository:

- `profiles/minimal-application/package.json`: exact GitHub source URL.
- `profiles/minimal-application/package-lock.json`: only the root development
  source URL and Infra entry's resolved URL/source SRI change.
- `profiles/minimal-application/infra-source-lock.json`: source SHA256/SRI,
  rebuilt npm identity and SHA256 of every one of its 40 allowed members.
- `profiles/minimal-application/scripts/infrastructure-source.js`: before Docker,
  verify manifest/root lock/resolved URL/SRI/version agreement and installed file
  hashes. npm ci verifies source acquisition; installed-byte checks detect later
  alteration. This is build verification, not a second Infra implementation.
- `profiles/minimal-application/scripts/build.js`: use verified provenance for
  the tools label and receipt; add Infra revision/source SRI application labels.
  Canonical native tools still use the owning Infra Dockerfile.
- `profiles/minimal-application/test/profile.test.js`: expected qualified URL.
- `profiles/minimal-application/test/source.test.js`: reject floating/incorrect
  locks, npm-SRI/source-SRI confusion and installed source tampering.
- `tests/minimal-application/run.js`: additional real preparation, SIGKILL and
  explicit recovery, invalid TLS server-name refusal, DKIM network/mount
  observations, queued-message/secret preservation and required SMTP readiness.
  Activation, backup, restore and rollback still use public Infra lifecycle APIs.
  Docker calls observe/fault-inject/clean only the explicitly owned test project.
- `tests/minimal-application/fixtures/plugin/server/worker.js`: acceptance-only
  TLS-name negative input and a queued `.invalid` message in capture mode.
  There is no production mail delivery or authentication implementation change.
- `docs/IL-5.9-B-source-selection.md`, this report,
  `docs/IL-5.9-B-qualification.md`, `docs/IL-5-release-handoff.md`,
  `docs/IL-5.7-oxy-form-handoff.md`, `docs/IL-5-qualification.md`,
  `docs/IL-5.7-final-validation.md`, `docs/IL-5-distribution.md` and
  `docs/IL-5-contract.md`: provenance, results, current operator references and
  future consumer inputs; old ledger entries are retained as history.
- `docs/evidence/IL-5.9-B-artifact.json` and `docs/evidence/IL-5.9-B/` (including
  `ci-documentary-summary.json` from closing readback): artifact,
  image, acceptance, isolated-consumer and CI evidence; no secret values.

Earlier reports retain their original c6ef6e9 source and checksums as historical
observations. No old qualification is relabelled as a run of the new lock.

## Preserved boundaries

`profiles/minimal-kernel`, shared configuration/renderer, `bin/drumee-ctl`,
workflows, runtime host/health scripts, schema and historical Dockerfiles are
identical to starting Debian `0d936b8`. No Infra Layer, Server Runtime or Oxy-form
checkout is modified. No Hub/MFS/Finder/database/Redis/DNS/gateway service is
implicit; the basic live deployment has only `application`. The optional native
tools image contains the canonical capability binaries (including BIND), but
only explicitly composed mail/DKIM services are started by the SMTP variant.

The application image contains Server Runtime and verified plugins. Infra Layer
runs in the host-side operator's installed dependency; it is not copied into the
application image. Its source identity is verified before construction and is
recorded by the image label/receipt. No ESLint or Infra development package is
installed in the production application image.

The route `/-/`, native RPC `/-/svc/`, loopback-only ingress, normal dispatcher
permission denial, canonical secret projections and ownership rules remain in
force. SMTP spool recovery still fails with `SMTP_RECOVERY_UNQUALIFIED`.
