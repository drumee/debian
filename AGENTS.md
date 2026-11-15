# Repository instructions

Write new project documentation in English.

## Persistent qualification artifacts and retention

This rule applies to all qualification, recovery, release-evidence and delegated
laboratory scripts in this repository, not only MAIL-05.

- Store every artifact needed to resume or qualify an execution under
  `$HOME/artifacts/<project>/<lot>/<execution-id>/` on the execution host. For tests
  delegated to `testbox`, retain the artifacts on `testbox`. When using a VM,
  verify before every reboot that the required evidence is accessible from
  `testbox`; guest-only files or a workstation copy are insufficient.
- Verify persistent storage and write access before starting. Reserve `/tmp` for
  disposable transfers and scratch files whose authoritative originals already
  exist in the persistent run directory. Record evidence, manifests, checksums,
  command results and resume state incrementally, including failures. Use private
  directories 0700 and files 0600 for sensitive artifacts. Report the exact host
  and path in the final handoff. Do not relocate live databases, mounted images
  or qualification roots by changing their logical identity without a reviewed
  cold migration; preserve existing evidence and legacy resources.
- Provide one cleanup command (`artifacts-cleanup`) with preview by default and
  deletion only with explicit `--apply`. The preview reports path, age, size and
  selection reason. Retention must be configurable per project/lot.
- Select only manifest-identified completed runs whose retention has expired.
  Preserve active/resumable runs, pinned runs, required qualification evidence
  and still-required backups. Missing, invalid or unsafe manifests require manual
  review and must never be guessed eligible from age or directory names.
- Revalidate eligibility and path immediately before deletion. Limit deletion to
  execution directories under `$HOME/artifacts/`; do not follow symlinks or cross
  mounts (including same-device bind mounts). Log actual deletions and released
  space. Periodic cleanup, if configured, must use the same protected command.
- Test preview and deletion on unique synthetic runs first. Document pin/unpin,
  retention configuration and cleanup usage. Never test deletion against real
  qualification data or run a broad age-based `find ... -delete`/`rm` job.

Use the canonical implementation in Infra Layer `tooling/artifacts.py` and
`tooling/artifacts-cleanup`, with its source digest pinned for delegated runs.
Do not fork a weaker cleanup implementation in a consumer repository.
