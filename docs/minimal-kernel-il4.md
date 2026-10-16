# IL-4 minimal kernel distribution qualification

Current resume: see [IL-4R validation ledger](minimal-kernel-il4r-ledger.md).
KB-01B resolves the historical first-human contract described below. The
original inventory and qualification evidence remain preserved verbatim.

Historical status: **IL-4 — INTEGRATION_BLOCKED**. This was an implementation checkpoint,
not a release-qualified installation profile. IL-3's approved disposable profile
remains valid within its documented scope.

## Revisions inspected

| Repository / branch | Revision | Evidence |
|---|---|---|
| debian / feat/container-distribution | `8a236e5d147a55cfd5580dcda0712cd6436ca93c` | Current checkout and remote branch; release 1.0.57 |
| debian / main | `b8b0ebe7082e1ad2366f3a7997712f5da5bba127` | Fetched remote main and inspected renderer/operator assets |
| transient / refactor/mapping | `c5ee4591c87e7be2a7d91398cfcaa277787558e0` | Approved fixture and report 37 |
| infra-layer / main | `6516c70349cc02bacffac565b5e103e660f970aa` | Approved standalone lifecycle |

The developer's original Debian checkout has local changes in the server/UI
changelogs and an untracked AGENTS.md. Work took place in an isolated clone on
the same branch; those local changes were not incorporated or overwritten.

## Delivered inventory

[dependency-manifest.json](../profiles/minimal-kernel/dependency-manifest.json)
records 213 npm artifacts (53 production), exact URLs/versions/SRI, six direct
Drumee source revisions, seven private transitional modules and 71 acquired
files with Git blob and SHA-256 identities. It includes the complete fixture
file inventory rather than relying on an installed sibling checkout.

The read-only generator uses immutable Git objects, not working-tree files.
Eight tests cover missing/wrong artifacts, local/floating sources, digest
changes, duplicate locations, traversal, false readiness claims and archive
symlink/hardlink rejection. A manifest check does not itself fetch tarballs;
archive verification is an explicit separate step. Transitive npm source
commits absent from lock metadata are `null`; their identities are the immutable
npm version and SHA-512 artifact. Missing license fields are explicit open
items, not inferred grants of rights.

Checkpoint inventory commit: `4382c96d3362ed9eadce67cb59b18aaeb5e00ed9`.
This inventories IL-3, not a new candidate runtime dependency lock.

## Blocking kernel/control-plane contract

There is no canonical first-human/operator enrollment operation in the selected
minimal-kernel composition. This is different from platform bootstrap.

At transient source revision `5469b48109dbb20eacbbc9314a6772264b388843`:

- `target/control-plane/bootstrap/lib/index.js::bootstrap()` creates organisation
  1, nobody, guest and system only; its public exports are constants, assessment,
  bootstrap/validation, error and SqlPlatformStore.
- `target/control-plane/bootstrap/lib/store.js::createPrincipal()` creates
  `area='system'`, `status='system'` and an empty credential fingerprint. It is an
  internal system-identity primitive, without enrollment authorization,
  human-credential policy or a first-operator idempotency contract.
- `target/control-plane/hub-lifecycle/lib/index.js::sessionPrincipal()` requires
  an authenticated human and rejects nobody, guest and system. Its public API
  provisions Hubs for existing principals; it does not enroll those principals.
- The selected `@drumee/server-runtime@0.1.0-alpha.3` exposes `yp.signin`, session
  and authorization operations, not account creation. Its intrinsic
  `schemas/yellow-page/phase4-schema.sql::session_signin()` compares a supplied
  password SHA-512 against an already provisioned fingerprint.
- The approved fixture's `lib/initialize.js:27–48` fills this gap **only for
  disposable acceptance** by directly inserting owner/reader/outsider rows and
  credential fingerprints into entity/drumate/privilege. It must not become a
  production installer with renamed default accounts.

Real MariaDB evidence is in transient corrective commit
`96acf364841b7556e4bce34b96be592b6fc94a38`,
`tests/integration/infra-il4/sql-boundary.test.js`: canonical bootstrap creates
exactly three identities with empty fingerprints; repeated bootstrap changes
nothing; actual session sign-in rejects nonempty probe passwords for all three.
The rest of that test explicitly creates a disposable test principal to probe
SQL grants; that is not a successful operator enrollment test.

The missing owner is **minimal-kernel control plane**, presently `transient`,
not Infra Layer or Debian. IL-4 forbids silently changing kernel identity or
provisioning semantics. Implementation stops at this boundary.

## Concrete owner decision requested

Approve a separate, narrow control-plane first-operator capability, for example
`target/control-plane/operator-bootstrap`, before resuming the product profile.
The proposed contract, not implemented here, must define:

1. Explicit operator authorization, organisation/domain and stable operation ID.
2. Human identity attributes and a protected credential resource reference;
   no password on command lines, plans, manifests or public diagnostics.
3. Kernel-owned credential encoding/policy and canonical administrative
   privilege assignment; never distribution-invented ACL bypasses.
4. Transactional entity/drumate/privilege ownership, reserved-identity exclusion,
   conflict rejection and interrupted-operation recovery.
5. Repeating the same operation preserves UID and credentials; a second or
   mismatched request cannot silently replace the operator.
6. A read-only validation result, with no plaintext credential or fingerprint.
7. Positive authentication/Hub provisioning and negative credential,
   unauthorized enrollment, duplicate, recovery and SQL-role tests.

The distribution will supply and invoke the approved job; it will not own its
identity SQL. Standalone extraction/publication of this private control-plane
capability is a separate decision. Pinned source acquisition remains acceptable.

## SQL privilege findings and executed proof

The IL-3 driver grants ALL on `yp.*` and `hub\_%.*` to its single runtime user.
That is acceptance-only policy. The real SQL probe demonstrates a possible
separation without modifying any kernel source:

| Role | Tested scope | Result / limitation |
|---|---|---|
| Infrastructure admin | Disposable engine/account administration | Never projected to ordinary kernel runtime |
| Schema/bootstrap/Hub provisioner | ALL on yp and escaped hub namespace, without global grants or GRANT OPTION | Real manifests, platform bootstrap, authenticated Hub creation and system-mfs provisioning work |
| Runtime | SELECT on named yp tables; DML on cookie/authn/socket; EXECUTE on yp routines; SELECT/EXECUTE on one exact assigned Hub shard | Real authentication/session resumption, ACL resolution, MFS directory creation/read work |
| Future privileged maintenance | Explicit job only | Production role, rotation and recovery transition not qualified |

Runtime is rejected on CREATE DATABASE (including a different hub_* name),
unrelated-schema read/ALTER, CREATE USER, mysql.global_priv mutation, yp DDL,
identity credential/privilege updates and Hub ACL deletion. Anonymous Hub
provisioning is rejected by the real control plane before SQL.

Stored routines retain their actual default SQL SECURITY DEFINER behavior;
the probe installs them under the scoped provisioner, not root. This is a
**tested restricted role proposal**, not proof that every grant is minimal or
that all runtime methods, multi-Hub future grants and restored definers are
qualified. The production account/projection lifecycle and complete browser/
restart/restore suite must follow the first-operator owner decision.

## Intended integration, not a parallel installer

Keep `config/drumee.yaml` as the distribution source of truth, with an explicit
minimal-kernel profile discriminator and profile-specific schema/validation.
Do not silently reinterpret the Team TLS names (`acme|own|self-signed`) or
secrets-generating renderer as Infra Layer v2 contracts. Minimal mode must map
explicitly to `none|local|localhost` DNS and `local|provided|acme` TLS.

Extend existing `bin/drumee-ctl` dispatch with an explicit profile selection;
delegate to a CommonJS operator consuming the qualified versioned Infra Layer
artifact. Plan/validate stay pure. Install/start/stop/backup/isolated restore/
upgrade/rollback/renew require explicit execution authorization and reuse
canonical lifecycle APIs. Do not route minimal backup to the existing legacy
database-only `cmd_backup/cmd_restore` implementation.

Existing role-app entrypoint runs historical server-pod/PM2; schemas entrypoint
and `schemas/populate.js` import Team factory/Organization bootstrap. They are
not suitable minimal init jobs. Preserve these legacy assets and release-manifest
roles, select a separate explicit kernel-host artifact, and share only verified
packaging machinery. `docs/distribution.md`'s .deb/role model remains the legacy
design of record; any minimal artifact packaging extension must be explicit.

The new role must supply real host/frontend artifacts, approved kernel-owned
jobs and restricted SQL projections, while Infra Layer supplies composition,
resources, activation/attestation, recovery and readiness. No Infra Layer
planner/renderer/activation implementation is copied here.

The intended qualification configuration remains domain `drumee.lan`, local
BIND9, persistent local CA, Nginx, MariaDB/Redis and narrow MFS mounts. LAN address
and occupied ports must be reobserved before remote activation. No acceptance
accounts, password defaults, Team factory, historical volume adoption or broad
runtime SQL grants are permitted. SMTP is excluded from the qualified recovery
profile until spool recovery is independently tested. Automatic renewal remains
disabled until an explicit scheduler/activation policy is qualified.

## Validation and release status

Executed from the isolated Debian clone:

```sh
node profiles/minimal-kernel/inventory.js create /path/to/transient > /tmp/inventory.json
node profiles/minimal-kernel/inventory.js validate
node --test profiles/minimal-kernel/inventory.test.js
bash tests/run-all.sh
```

Results: 8/8 inventory TAP tests, zero failures/skips; 330/330 existing Debian
checks, zero failures, no reported skips. SQL probe: 7/7 TAP including its parent,
zero failures/skips, on disposable MariaDB 11.4 with dynamic loopback-only port
and tmpfs data; owned container and secret file removed afterward.

No minimal install/upgrade/restore operator was shipped, no clean production
install or remote IL-4 profile was claimed, and no testbox state was changed.
Existing IL-3 LAN/browser/recovery evidence is retained as prior evidence, not
relabelled IL-4 acceptance.

The real IL-3 fixture was also rerun locally from a fresh clone at transient
`96acf364841b7556e4bce34b96be592b6fc94a38` against a **local packed artifact**
of corrected Infra Layer `2d1f6aa6774f70f1d3cfc00f47a94ecf4133e314`:
`sha512-epjbLJrHxjAT+7ayv1h0BDSlhU8p6KKuotsvgbQZxB+aOa1/sdn/VN1eSDLRA4zZVZQcplwH53Z0IOShLf2wIQ==`.
The archive is development alpha.1 metadata, not registry alpha.1 or a qualified
alpha.2 release. Installation used `npm install --no-save --package-lock=false`
of that explicit archive in the disposable checkout after npm ci; no dependency
file in an owning repository was changed. All 25 grouped checks (9 fresh, 8
restart, 8 restore), three Chromium runs and actual interrupted Redis rotation
recovery pass. Project `drumee-il3-kernel-498823b7` published only loopback high
ports 46345/38657, and its restored project used separate high ports. Owned
containers, networks, images and deployment/backup roots were cleaned. This
retains regression coverage; it does not qualify production first-user policy.

Registry inspection on 2026-10-15: versions `0.0.0-stage`, `0.1.0-alpha.1`;
next/latest both alpha.1. Alpha.2 remains available as a proposed candidate
version. Full distribution/SQL/recovery qualification blocks candidate release
readiness; no tag, npm/dist-tag change or image publication was performed.

Final Infra Layer checkpoint:
`35fe3d0e6b6311d43940338b65a7e5ae74c0d222`, runtime implementation
`adf56e04961c3974e0bd0ad481b1700a15d99c09`. A final guard validates malformed
resource records before sorting so diagnostics remain stable. Its complete
clean standalone sequence passed again. The final development tarball has SRI
`sha512-yQD6QsmHoI0sMtqCJvbPGwf5Nc527kpEJwsEbZkHwwAugfKqQnE5O/58yXSPfHmHLLxhbRyBXWZbeg2xnuxD1A==`;
it remains private alpha.1 metadata, not registry alpha.1 or a release candidate.

The real fixture's first run against this guard stopped after nine groups with
`DOCKER_LIFECYCLE_COMMAND_FAILED`; cause unestablished. Its sequential diagnostic
retry passed all 25 groups, actual interrupted Redis rotation, three Chromium
stages and isolated recovery. Successful project `drumee-il3-kernel-6faacb7e`
used loopback HTTPS 45625/DNS 36623; all owned resources were cleaned. No test
failure is concealed or attributed to concurrency without proof. Exact final
artifacts and attempted-run evidence live in Infra Layer
`docs/IL-4-validation-evidence.json`. This still tests acceptance identities,
not the absent production first-operator enrollment operation.

Resume checkpoints IL-4.2 through IL-4.6 after the owner supplies/approves the
first-operator contract. Keep the IL-3 fixture until Debian demonstrates
equivalent or stronger real-kernel acceptance. Oxymotion D0 remains gated.
