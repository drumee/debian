# Minimal kernel profile — IL-4 qualification inputs

Status: **INTEGRATION_BLOCKED**, inventory and SQL investigation only.
This directory is not an installer or an activated release channel. Existing
Team configuration, role packages and `drumee-ctl` behavior are unchanged.

`dependency-manifest.json` inventories the approved transient fixture at
`c5ee4591c87e7be2a7d91398cfcaa277787558e0`: all 213 locked npm artifacts
(53 production artifacts), 71 acquired source files and fixture-owned glue.
Optional platform-specific npm artifacts are inventoried even if npm does not
install them on the current platform. Source files have both Git blob IDs and
SHA-256 digests. Tarballs have SHA-512 SRI. The direct Drumee registry `gitHead`
values were checked against the pinned revisions on 2026-10-15.

Regenerate without executing imported code, from any explicit clone containing
the immutable commits:

```sh
node profiles/minimal-kernel/inventory.js create /path/to/transient > /tmp/inventory.json
cmp /tmp/inventory.json profiles/minimal-kernel/dependency-manifest.json
node profiles/minimal-kernel/inventory.js validate
node --test profiles/minimal-kernel/inventory.test.js
```

No sibling checkout is a deployed runtime dependency. This inventory tooling
reads a caller-selected Git object database; a future acquisition/build command
must fetch the same commits independently and verify every artifact. `verifyArchive`
checks an explicit regular tarball against its recorded SRI; merely validating
the JSON manifest does not download or verify archive bytes.

The source archive named `@drumee/infra-layer@0.1.0-alpha.1` in the fixture is
**not** registry alpha.1. It is unpublished IL-3 commit `95db6c7…`, with a
different integrity. The registry release lacks lifecycle APIs. A qualified
candidate must replace that source reference explicitly; do not resolve this
profile against npm alpha.1.

Private transitional module package manifests omit a license field. Their
provenance is retained and the omission is recorded rather than guessed.
`backbone.radio` also lacks license metadata in the npm lockfile. Release
qualification must resolve these metadata omissions using the original notices.

See [the IL-4 integration report](../../docs/minimal-kernel-il4.md) for the missing
first-operator contract, SQL evidence and proposed integration boundary.
