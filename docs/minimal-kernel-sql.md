# Minimal kernel SQL privilege matrix

Policy source: `profiles/minimal-kernel/lib/sql-policy.js`, derived from the pinned
runtime, platform bootstrap, KB-01B, HubLifecycle and system-mfs statements.
All accounts and passwords are created/projected by Infra Layer. Debian supplies
application grants through the verified owned engine's local root socket. No root
credential or socket is mounted in the ordinary kernel or private provisioner.

| Principal | Actual scope | Projection and boundary |
|---|---|---|
| Infrastructure administrator | Engine/account administration, scoped grant installation, cold backup | Infra Layer owned database socket only; no published SQL port |
| `kernel_schema` | CREATE/ALTER/DROP/INDEX, CREATE/ALTER ROUTINE, EXECUTE and table SELECT/INSERT/UPDATE/DELETE on `yp.*`; no global administrative grant | Schema initialization/migration jobs only; owns Yellow Page routine DEFINERs |
| `kernel_bootstrap` | CREATE/SELECT/INSERT on organisation; SELECT/INSERT on domain/sys_conf/entity/drumate/privilege; EXECUTE uniqueId | Canonical reserved-platform bootstrap job only |
| `kernel_enrollment` | Named-table SELECT; INSERT entity/drumate/privilege; UPDATE drumate(remit); SELECT/UPDATE initial_operator_enrollment; named-function EXECUTE; read-only mysql.proc | KB-01B enrollment job only; no schema/account creation |
| `kernel_provisioner` | Named-table observation/session transport; Hub lifecycle, plan, capability and system-mfs provisioning DML; entity INSERT/UPDATE; DDL/DML/routine privileges on escaped `hub\_%` namespace | Separate private service. No drumate/privilege/enrollment writes; no infrastructure-account creation |
| `kernel_runtime` | SELECT on the named Yellow Page runtime/ACL/MFS registry tables; INSERT/UPDATE/DELETE on cookie/authn/socket; exact intrinsic function/procedure EXECUTE; exact provisioned-shard media/permission SELECT and manifest routine EXECUTE | Ordinary kernel only; no DBA, schema-install, remit, enrollment or ACL-write privilege |

Runtime's exact Yellow Page read tables are domain, sys_conf, organisation, entity,
drumate, privilege, cookie, authn, socket, hub, hub_lifecycle, hub_acl, hub_plan,
hub_capability, system_mfs_installation and system_mfs_provisioning. Its function
EXECUTEs are uniqueId/domain_permission/get_remit, and procedure EXECUTEs are
session_signin/session_ensure/authn_store/socket_bind/socket_get/socket_free/
socket_list_session/socket_refresh. No EXECUTE wildcard on `yp.*` is granted.

After authorized HubLifecycle creation and system-mfs validation, the provisioner
grants runtime SELECT on that exact shard's manifest tables and EXECUTE on its
manifest functions/procedures. The provisioner has GRANT OPTION only for SELECT
and EXECUTE in the escaped Hub namespace, not global/account/identity grants.
It is an intentionally privileged control-plane account, never described as an
ordinary least-privileged runtime. The canonical SqlHubStore's optional broad
`runtime_user` GRANT ALL path is not enabled.

MariaDB's actual SQL SECURITY DEFINER behavior remains explicit: intrinsic
session/transport routines run with their scoped schema-job owner; MFS routines
run with their scoped shard-provisioner owner; KB-01A get_remit is SQL SECURITY
INVOKER. Runtime cannot replace those routines. Enrollment's canonical structural
validator requires routine-body visibility; MariaDB 11.4 supplies it through the
job-only mysql.proc SELECT grant. That metadata grant is never given to runtime.
Cold recovery preserves SQL accounts, definers and matching secret generations.

Acceptance exercises real enrollment, authentication, authorized Hub provisioning,
MFS/FileIo/browser operations and negative CREATE DATABASE (including another
Hub name), unrelated-schema SELECT/ALTER, SQL-account creation, global grant,
runtime DDL, platform-remit writes, enrollment metadata access/modification and
Hub ACL deletion. Separate HTTP tests verify readers/outsiders cannot provision
Hubs and platform remit/Hub administration do not bypass unrelated MFS grants.
See the IL-4R ledger for executed counts and remaining qualifications.
