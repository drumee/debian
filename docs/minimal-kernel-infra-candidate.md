# Infra Layer alpha.2 candidate evidence

Version: `0.1.0-alpha.2`, unpublished. Registry inspection confirms alpha.2 is
available; published latest/next remain alpha.1. No release tag, npm publication
or image publication is performed.

Candidate source: `ad8f2baecb65e5e8782bb60fa92f1653bcc9f724`, branch
`feat/il4-release-candidate`, based on IL-4 checkpoint `35fe3d0…`. Debian's
lock/alignment record the immutable source archive URL and SRI independently
from the npm-packed release-candidate artifact. Runtime compatibility remains
explicitly `@drumee/server-runtime@0.1.0-alpha.4` (KB-01A) with KB-01B source
`59985d4a78e142b64f5976cc7460a723cca29a79`.

The candidate includes lifecycle APIs absent from registry alpha.1, corrected
resource normalization, independent infrastructure-owned SQL account resources,
private distribution services, public declarations, explicit lifecycle exports,
changelog, license and source provenance. It has zero production npm dependencies.

Package audit passes with 39 allowlisted files. Production source/license/type
inventory excludes tests, development trees, generated resources, credentials
and private keys. An offline isolated installed consumer imports the unchanged
five root functions and lifecycle/secret subpaths and successfully plans native
capabilities. Packed artifact SRI:

`sha512-KuNELBJcKBA69RN65qoej4Wxw+lMN5NJO5d50ooHwydZMB90Rq42MyavDgOwpWqG12bPKjJKH0b01tvN17nsnw==`

Executed candidate regression: 127 unit/security TAP cases, 17 gateway TAP cases,
17 native-service TAP cases, 16 lifecycle TAP cases and four HTTPS/job scenarios,
all passing without skips. Counts are per-suite; the four scenarios are not TAP
cases. Native SMTP/DKIM tests do not qualify SMTP spool backup/restoration for
the Debian minimal profile, which deliberately excludes SMTP recovery.

Final distribution, real-PTY, clean-checkout and testbox qualification passed at
Debian `4a0efba6193912ce5b0487db51fb541ca79638d0`; see the
[IL-4R validation ledger](minimal-kernel-il4r-ledger.md) and its machine-readable
evidence. Both local enrollment modes completed real authentication, Hub/MFS,
Chromium, restart and isolated restore. The separate LAN client verified remote
TCP/UDP authoritative DNS, CA/SAN HTTPS and three browser stages. Runtime alpha.4
and the exact KB-01B source remain explicit; no compatibility with alpha.1
lifecycle APIs is claimed.

A fresh GitHub clone of candidate source reproduces the same npm tarball SRI.
The installed tarball passes standalone planning/import checks and strict
TypeScript 5.9.3 NodeNext consumer compilation, including managed accounts and
private supplied services. Shipped files are unchanged by later evidence-only
documentation commits. The candidate is ready for release review within this
documented scope; publication still requires explicit approval and a fresh npm
version-availability check. One unreproduced local Docker restart failure and
the qualified profile's operational limits are disclosed in the ledger.

Infra evidence-only branch HEAD is
`94216fb59c83114ab97fff51dbfa36f63e2316f2`; the pinned shipped artifact remains
the identical `ad8f2ba…` source/tarball above. The supporting original main
checkout remains clean at `35fe3d0…`.
