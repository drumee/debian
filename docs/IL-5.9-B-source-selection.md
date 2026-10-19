# IL-5.9-B — immutable source selection

Observed 2026-10-18. Infra Layer PR #2 is open, unmerged, mergeable, from
`feat/il5-external-gateway` at `aa9057f224f4ae5cf80d777e3cb2fad092193fb1`
into main `bef9a379754bcf9a46fed8bcb6f88fe1f775c739`.
Debian starts at `0d936b870bd634bac44939066f4a0e526e1b02ea`, PR #7 into
`feat/container-distribution` at `3fb32d86ce336c886235c23b9632a140a2dc3045`.
Both live heads match the mission references. Existing server/UI changelog edits,
untracked AGENTS.md and .aws are preserved outside the commits.

Selected source is the exact Infra PR head, whose IL-5.9-A qualification includes
the fixed qualification network client. It is acquired from:

`https://codeload.github.com/drumee/infra-layer/tar.gz/aa9057f224f4ae5cf80d777e3cb2fad092193fb1`

| Artifact | Freshly measured identity |
| --- | --- |
| Source SHA256 | `b33e5ba7946b73701b05365c637f5153e9ddb860efe0074821d86161dd1466d2` |
| Source SRI | `sha512-faoNlMWBO05FM+ozsuGu9tqFgq/IYc9WJwb4KCyZcZiTlEIrgJ9QLqLxslTADdipaItg02r2f6qFG07HDxhVqA==` |
| npm candidate | `@drumee/infra-layer@0.1.0-alpha.3`, locally packed, not published |
| npm SHA256 | `7385ee7acbc6582746b2f8d8713ce174f7136e7531e7e57221df06a15c906a75` |
| npm SRI | `sha512-ZZIxqtHsFA0tCwAR6vcGa3iOttFYTkHCS4rKN4UtPApLPDkq41FJ0xJWKfWLEWVUlvM3JZldb1aGrhyKMiM9Pw==` |

The source archive has 260 members, all under its exact commit directory;
only ordinary files/directories are accepted, with no links or path traversal.
All tracked file bytes were compared with Git objects at the selected revision.
`npm pack --ignore-scripts --json` from the extraction produces the qualified
98,808-byte tarball, 40 allowed files, 353,683 bytes unpacked. No production
dependency is introduced. The package inventory is retained in
[evidence](evidence/IL-5.9-B-artifact.json); the active per-file hash receipt is
[infra-source-lock.json](../profiles/minimal-application/infra-source-lock.json).

Compared with the IL-5.8 executable qualification at
`f91253c1d034270af3c7815f514b1e8c91f78020`, 39 of 40 packaged files are identical.
Only package.json changed (development tooling and npm scripts). Exports,
allowlist, version, engine, entry points and declarations are identical. Later
IL-5.9-A changes affect tests, tooling, CI and documentation, including the fixed
network qualification program; no application/runtime contract is changed.
The earlier IL-5 source `c6ef6e9b8d33921ffa39c289490067adfc63a8b0` and IL-5.8
package/source identities remain historical evidence, not interchangeable SRIs.

The source archive integrity is used for npm's GitHub acquisition; the npm
candidate integrity describes different bytes and is never substituted into
that lock. A future registry migration requires separate explicit selection and
qualification. No release, tag, image push or merge is performed.
