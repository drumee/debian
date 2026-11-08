# Infra Layer alpha.5 distribution convergence

## Frozen scope and acquisition

Target: `feat/container-distribution`, starting at
`175e6fd1c1500a05192ad367dca95ebd1fcecdbb`, unchanged since the known alpha.4
qualification. This does not converge Debian main or minimal-kernel.

Minimal-application selects exact published `@drumee/infra-layer@0.1.0-alpha.5`,
registry URL and SRI through its manifest, npm lock and infra-source-lock.json.
The existing verifier and its missing/extra/changed/symlink refusal tests remain
active. There is no local producer substitution or floating tag resolution.
Runtime stays alpha.4 and every unrelated dependency lock entry is preserved.

- Producer source: `6b04a883484beb5d8ec274bbef75cd1a254ddb54`, PR #33.
- Archive: 43 regular files, 108632 compressed bytes, 386015 unpacked bytes.
- URL: `https://registry.npmjs.org/@drumee/infra-layer/-/infra-layer-0.1.0-alpha.5.tgz`.
- SHA256: `d714ea7fcce17041a4c6c9509add14c52c735169a4d6660d55ff570fc64fc75f`.
- SRI: `sha512-NmHYfb/n83s2iY7MEpqNBU7W6xMGAiUHaUfzcm8C57ooPMR2oQeB6Q9O37ip0/Mb3O+/Oa4vx3n7ONLEcE2IVQ==`.

Downloaded bytes, registry metadata and every qualified Git member agree. Registry
metadata supplies neither gitHead nor an attestation; provenance is the measured
member comparison with the qualified commit, not an invented npm attestation.
The observed next tag points to alpha.5 but is not used for dependency resolution.

## Required new recovery evidence

The canonical real acceptance retains all prior scenarios and adds the missing
mixed application/SMTP/DKIM failed-start recovery. It observes absent roles and
actual repeated Docker mount enumeration with identical records in different
orders, exercises ordinary rollback, fails plugin provenance, verifies
recovery-required, and restores the verified revision through the real operator.
It checks readiness/RPC/SMTP and unchanged durable data, queue IDs and secrets.

Guard probes use copies of real observations against the installed canonical
admission code with the real Docker adapter, without mocks or modified dependency
bytes. Roles, authority, identity, images, revisions, bindings and mount changes
must still refuse. A real extra network must refuse without resource recreation.
Copied-observation probes are distinguished from physical Docker fault injection.
SMTP_RECOVERY_UNQUALIFIED stays mandatory: spool backup/restore is unsupported.

## Qualification and governance

Fresh results, exact image identities, hosted checks and debt comparison are
recorded in the compact evidence receipt after execution. Producer's 173 assertions
and 399 unit tests are supporting historical input evidence, not substituted for
the actual downstream profile campaign.

The pre-existing 91 ShellCheck diagnostics and two global packaging failures must
be compared with this starting distribution revision. They stay failures and are
not waived for main integration, a general release or IL-5.10-C. No CI job, rule,
protection or quality configuration is disabled. No new relevant failure or missing
required result permits the targeted merge.

After validated convergence, consume the final immutable distribution merge commit
for a separate OF-01R replay, not Debian main. Oxy-form PR #3 stays draft; no
backend validation, external SMTP receipt, publication, image push, release tag,
production deployment or public form activation is claimed by this mission.

## Executed local qualification

Node 22.22.0 / npm 11.18.0 / Docker 29.2.0, 2026-11-08 UTC:

| Check | Fresh result |
| --- | --- |
| Locked registry install and installed 43-member verification | PASS |
| Profile contracts / plugin archive boundaries | 8 / 8 PASS |
| Shared suite / unchanged minimal-kernel regression | 331 / 7 PASS |
| Production / development profile audits | zero / zero vulnerabilities |
| Complete real minimal-application acceptance | 11 groups / 226 assertions PASS |
| ShellCheck 0.11.0 | same 91 individual findings: 20 errors, 71 warnings |
| Global packaging | same 10 passes / 2 failures |

The full successful campaign includes every prior acceptance group plus the new
mixed recovery sequence. Real Docker observations proved missing infrastructure
roles and differing SMTP mount-array order with the same complete record multiset.
Ordinary rollback and failed-start rollback both succeed; readiness, native RPC,
authenticated STARTTLS and durable data/queue/secret generations survive recovery.
Negative copied-observation probes use the unmodified installed canonical guard
and real adapter; a physical extra-network injection after recovery refuses without
replacing containers. The previous attempt to inject that network during restart
backoff was unstable and is not counted as a passing campaign. All scenarios were
replayed in the final successful campaign; no failure was skipped or inverted.

Build source: `15723584d96539dd5620026bcb1780e0ea473fee`.
Runner source: `7e033c763ce153d0b1de51aec92dac0227c10d56`.
The profile/build input tree is identical at both commits:
`f3257c57426de0b461718b9bd45e61e3d180214d`.

- Application image: `sha256:232e921c3330de43ab36853456e2dc9de7d8730f2c95b61ebc1daebf7302491e`.
- Native tools: `sha256:9bd904ed25890e994cd8b12782dcdc02c3c9f58aa99d5fe67871c7d54f95362d`.
- Qualification fixture archive SRI:
  `sha512-GPdfP2L6NKtz4qzOgqHsekCjRd7BXTuiPqA+XPxXBGntrMBUQIC0Vv18DEJe/4nryK8mBHGQOC7ajqxFq4kkEA==`.

Both images were built locally through the current profile, which verifies the
published Infra dependency before Docker. Native-tools root filesystem layers
match the previously qualified tools exactly; producer provenance labels changed.
The fixture bytes are unchanged from the frozen starting distribution and all
its scenarios were executed afresh. The images are not Oxy-form backend artifacts
and were not published. Producer recovery/unit evidence is supporting historical
evidence only. New consumer recovery is established by this downstream campaign.

The network client used its own container/network with a pinned SSH host key and
positive nonce route; the application refused non-loopback access. Nginx ran as
an unprivileged host process from a temporary extracted package, with CA/SAN
validation and no system configuration/trust/firewall change. Generated secrets
and private-key markers were absent from both log streams of five containers and
from receipts. These are bounded exercised observations, not a production-host or
Internet-mail qualification. Test deployments were ownership-checked and cleaned.

Compact evidence: [qualification receipt](evidence/infra-layer-alpha5-convergence.json).
PR checks at runner source confirmed profile/shared success and the same individual
hosted lint/packaging failures as the starting distribution. The final documentary
commit and merged distribution revision require their own exact-head hosted and
locked-install verification, recorded in the final handoff.
