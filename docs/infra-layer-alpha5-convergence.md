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
