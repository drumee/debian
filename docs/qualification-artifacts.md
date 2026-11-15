# Qualification artifacts and retention

Use the repository-wide AGENTS policy and the shared Infra Layer
`tooling/artifacts.py` / `tooling/artifacts-cleanup` implementation. The common
[operations reference](https://github.com/drumee/infra-layer/blob/feat/qualification-artifacts-policy/docs/qualification-artifacts.md)
documents private modes, manifests, pinning, retention, cleanup and the testbox VM
reboot gate. Do not fork the deletion logic into the Debian profile or alter the
locked mail consumer for this tooling change.

```sh
export DRUMEE_ARTIFACTS_TOOL=/absolute/path/to/infra-layer/tooling/artifacts.py
export DRUMEE_ARTIFACTS_TOOL_SHA256=PINNED_SHA256
scripts/qualification-run MAIL-05 execution-001 -- bash tests/run-all.sh
```

The wrapper captures the command in
`$HOME/artifacts/debian/MAIL-05/execution-001/` on the execution host, with a private
log, manifest, SHA256 inventory and resumable status. Store necessary native working
inputs beneath that run's protected `work/`; copy immutable checkpoint evidence
into `evidence/`. Do not put restart-critical artifacts in `/tmp`. This wrapper
captures commands; it does not turn unit tests into native qualification evidence.

For a delegated test, execute on testbox or its designated guest, then use the
canonical host-side sync/reboot gate. Required proofs must be readable and verified
from testbox before every guest reboot. All VM backing data belongs under the
canonical host run. Existing qualified legacy resources remain preserved; any
relocation requires an explicit cold adoption, not seal rewriting or live copying.

`artifacts-cleanup` previews path, age, size and reasons. Completion alone never
releases required backups/qualification evidence. Missing/invalid manifests,
active/resumable/pinned runs, links and mounts require preservation/manual review.
Only expired completed runs with all protections explicitly released may be
selected, and `--apply` rechecks their paths/state before FD-anchored deletion.
No periodic cleanup is enabled by this change.
