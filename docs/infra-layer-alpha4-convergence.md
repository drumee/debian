# Infra Layer alpha.4 registry convergence

## Scope and source selection

This targeted migration starts from Debian `feat/container-distribution` at
`1ff957fac41f158346974d0b290b9396fefb44b6`. It does not integrate the 103-commit
IL-5.10-C migration into Debian main. Existing main behavior and the separate
IL-5.10 documentary PR are outside this change. OF-01R is not started.

The minimal-application operator now acquires exact npm version
`@drumee/infra-layer@0.1.0-alpha.4`, replacing the GitHub source archive at
`aa9057f224f4ae5cf80d777e3cb2fad092193fb1` (whose locally packed candidate was
alpha.3). Server Runtime remains `@drumee/server-runtime@0.1.0-alpha.4`, with its
existing lock entries and transitive dependency resolution unchanged.

| Published Infra Layer identity | Verified value |
| --- | --- |
| Qualified producer source | `a8037dd62a50ae4bcb8ab0b36f6a8e1b5f23a0a6` |
| Registry archive | `https://registry.npmjs.org/@drumee/infra-layer/-/infra-layer-0.1.0-alpha.4.tgz` |
| Archive bytes / members | 107774 / 43 |
| SHA256 | `e9ceff871f45331c9f3308c5efa20ab4308b8c59a5b511485be1426645431023` |
| SRI | `sha512-8R0syrXk74veTYi9AogxGNEOUX6djiLkVIj4DIJ26owR45o8BT9vqI5Bu9Ffuqf1upu80o9/d4ZfnTqvVS2Mqg==` |

The registry's `next` tag points to alpha.4, but installation uses the exact
version and locked URL/integrity, never the tag. Registry metadata has no gitHead
and no alpha.4 Git release tag was observed. Provenance was instead established
by comparing every published member byte-for-byte with the qualified source.
No tag or published artifact was changed.

## Reproducible consumer boundary

`profiles/minimal-application/package.json` and package-lock.json select the exact
registry version. The existing infra-source-lock.json now explicitly records
`acquisition: npm-registry`: acquisition and npm integrity identify the same
published archive, not two interchangeable source/npm artifacts. Its 43 member
hashes bind installed files to the independently verified published artifact.
The build verifier refuses floating references, old source SRI, mismatched
versions and modified/missing/additional/linked installed members before Docker
builds. There is no fallback to a neighboring producer checkout.

Infra Layer remains a host-side development/operator dependency. The application
image installs only the profile's production dependencies (Server Runtime) and
verified plugin artifacts. Image labels and build receipts distinguish the
producer Git revision, npm version and package integrity. The canonical Infra
services Dockerfile still owns optional native tools construction.

## Qualification and debt boundary

Final acceptance and CI results are recorded below after execution. Counts must
not be inferred from historical IL-5.9-B acceptance. Security negative controls,
public lifecycle calls and the existing real acceptance runner remain intact.

The distribution branch has historical global packaging failures (unqualified
legacy FROM references and global PM2 installation), plus 91 ShellCheck findings.
These stay visible. Their reproduction and comparison are required; this targeted
migration does not waive them for main, Team/native packaging or release. No CI
configuration, rule, protection or quality gate is weakened.

## OF-01R handoff boundary

A validated downstream consumer must freeze the resulting Debian distribution
commit, exact Infra alpha.4 registry URL/SRI above, and the unchanged Runtime
alpha.4 SRI from its lockfile. Qualification plugin images are not Oxy-form
artifacts. OF-01R must separately select and integrity-check the real forms plugin
and dependencies, build its actual image, preserve existing host Nginx/HTTPS and
static site, use private loopback ingress with native `/-/` and `/-/svc/`, and
qualify actual SMTP upstream/credentials/mailbox/DNS/reception and error cases.
Forms remain disabled until that mission passes. No Oxymot access, deployment,
registry publication, release tag or OF-01R execution occurs here.
