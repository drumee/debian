# IL-5.10-A — Debian integration audit

Status: **PASS**, observed 2026-10-19 before any Infra Layer merge operation.

## Examined revisions

PR #7 is already merged, at 2026-10-19 08:31:59 UTC, into
`feat/container-distribution`. Actual merge commit:
`1ff957fac41f158346974d0b290b9396fefb44b6`, parents
`3fb32d86ce336c886235c23b9632a140a2dc3045` and qualified HEAD
`490c4b0a28ffb35da6ff248402139b5f600c793f`.

Both merge and qualified HEAD have exact root tree
`8e922e649f7612ddf352fefa69d570b5b4452536`. `git diff 490c4b0 1ff957f`
is empty: no conflict resolution, transformation, dropped profile file or extra
change is introduced by the merge. The complete minimal-kernel tree also equals
the pre-IL-5 baseline 3fb32d8. Shared renderer/schema/CLI changes are precisely
the already qualified IL-5 additions, not new merge edits.

The original working directory remains on its feature branch with pre-existing
server/UI changelog edits and untracked AGENTS.md/.aws preserved. All new work
uses an independent clean clone under /tmp, on `docs/il510-integration` from the
actual integrated destination. Debian main is not modified or merged.
Repository guidance and ROADMAP/distribution boundaries were read.

## Lock and artifact verification

The active application lock still selects
`aa9057f224f4ae5cf80d777e3cb2fad092193fb1` from its exact codeload URL.
A fresh archive download has SHA256
`b33e5ba7946b73701b05365c637f5153e9ddb860efe0074821d86161dd1466d2`
and source SRI
`sha512-faoNlMWBO05FM+ozsuGu9tqFgq/IYc9WJwb4KCyZcZiTlEIrgJ9QLqLxslTADdipaItg02r2f6qFG07HDxhVqA==`.
All 260 members stay within the immutable root and are ordinary files/directories;
links/path traversal are refused. All 40 allowed package-member hashes equal
`profiles/minimal-application/infra-source-lock.json`. The separate npm candidate
SRI is not used for source acquisition. Runtime alpha.4/version/integrity and
minimal-kernel locks remain unchanged.

## Executed checks

From the clean integrated clone:

```sh
npm ci --prefix profiles/minimal-application --ignore-scripts --no-audit --no-fund
npm test --prefix profiles/minimal-application
python3 tests/minimal-application/plugin-artifact.test.py
npm ci --prefix profiles/minimal-kernel --ignore-scripts --no-audit --no-fund
node --test profiles/minimal-kernel/inventory.test.js profiles/minimal-kernel/test/*.test.js
tests/run-all.sh
```

Results: application 8 TAP, minimal-kernel 15 TAP, archive 8 Python cases,
shared suite 331 checks; all passed, zero final failures/skips. These are separate
counts, not an aggregate. The application tests cover selector/manifest/ownership,
private-network parameter rejection, public lifecycle-only imports, Runtime/source
pins, wrong SRI/floating reference and installed-byte tampering refusal. The
shared suite checks configuration rendering, native/container parity and guards.

The earlier 126-assertion actual application acceptance is reused by exact
whole-tree identity. No new LAN/SMTP/Chromium run is claimed here; the heavy-run
inputs and owning records are unchanged. The two historical packaging failures
and 91 ShellCheck diagnostics remain visible in the IL-5.9-B CI record; this audit
neither fixes them nor extends their limited acceptance to Debian main.

[Machine-readable evidence and log hashes](evidence/IL-5.10/A-debian-audit.json).
This PASS permits beginning IL-5.10-B preflight. It does not itself authorize an
unconditional merge or any publication.
