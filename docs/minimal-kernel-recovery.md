# Minimal kernel recovery

Recovery delegates to Infra Layer. The legacy Team database-only backup path
is never used for an explicitly selected minimal profile.

```sh
bin/drumee-ctl --profile minimal-kernel backup --execute \
  --config config/drumee.yaml --backup /owned-backup-root/manual-20261016
```

The target must be a new empty directory below the configured backup location.
The command records the explicit retention period; pruning requires a separate
explicit owner operation. It never deletes unrelated backups to enforce a quota.

Canonical backup stops the owned kernel, private provisioner and other writers,
checks database event quiescence, takes a locked logical dump, then stops the
engines and copies cold persistent state. The inventory covers SQL data/accounts/
DEFINER identities, MFS bytes and ACLs, initial enrollment marker/credential
resource, configuration snapshot, frontend assets, CA/leaf/key state, infrastructure
secret generations, ownership and lifecycle metadata. Backup is private and
contains credentials; it must remain outside source control and public storage.
All checksums and schema versions are validated before restoration.

For isolated restoration, copy the configuration to a new file, choose a new
project name, new empty owned storage root and unoccupied explicit ports. Preserve
the logical instance ID, initial username/email, mode and operation ID. Do not
point at customer databases or reuse existing deployment resources.

```sh
bin/drumee-ctl --profile minimal-kernel restore --execute \
  --config restored.yaml --backup /owned-backup-root/manual-20261016
```

Restore preserves identities, credentials, grants, MFS content and CA identity.
It then explicitly activates the restored composition, reruns canonical job
validation and real administrator authentication, and checks protocol readiness.
The operator must additionally verify application/ACL/browser behavior before
using the restored deployment. The validation ledger records acceptance evidence;
infrastructure attestation alone is not full kernel recovery qualification.

An interrupted initialization must resume from its credential resource, canonical
SQL guard and lifecycle journal. Never delete the marker, rename another human
as administrator, regenerate a missing successful-enrollment credential, reset a
password, or import an old direct-SQL owner fixture. A malformed/partial KB-01B DDL
installation deliberately requires investigation rather than automatic repair.

```sh
bin/drumee-ctl --profile minimal-kernel upgrade --execute \
  --config candidate.yaml --backup /owned-backup-root/preupgrade
bin/drumee-ctl --profile minimal-kernel rollback --execute \
  --config config/drumee.yaml --revision VERIFIED_PREPARED_REVISION
```

Upgrade delegates canonical compatibility checks and requires verified backup
evidence. Supported Infra Layer transitions remain deliberately narrow: compatible
same-engine-version rebuilds and classified configuration transitions. Unqualified
kernel-image changes, schema changes, database engine transitions/downgrades and
secret-generation mismatches fail closed. Rollback never claims that switching
an image also reverses a SQL migration. Use an isolated matching-schema backup
restore when a compatible in-place rollback is unavailable. Additional SQL-account
secret rotation has no qualified consumer transition and is unsupported.
