"use strict";
// Grants derived from the pinned runtime and control-plane source statements.
// No identity DML is implemented here. All SQL runs in an owned engine only.
const read = ["domain", "sys_conf", "organisation", "entity", "drumate", "privilege", "cookie", "authn", "socket", "hub", "hub_lifecycle", "hub_acl", "hub_plan", "hub_capability", "system_mfs_installation", "system_mfs_provisioning"];
const transport = ["cookie", "authn", "socket"];
const hub_tables = ["hub", "hub_lifecycle", "hub_idempotency", "hub_acl", "hub_plan", "hub_capability", "hub_schema_object", "system_mfs_provisioning"];
const roles = ["schema", "bootstrap", "enrollment", "provisioner", "runtime"];
function grants(stage, tables) {
  const output = [], grant = (privileges, object, role) => output.push(`GRANT ${privileges} ON ${object} TO 'kernel_${role}'@'%';`);
  const table = (name, privileges, role) => { if (tables.includes(name)) grant(privileges, "yp.`" + name + "`", role); };
  if (stage === "intrinsic-schema") {
    output.push("CREATE DATABASE IF NOT EXISTS yp CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;");
    grant("CREATE,ALTER,DROP,INDEX,CREATE ROUTINE,ALTER ROUTINE,EXECUTE,SELECT,INSERT,UPDATE,DELETE", "yp.*", "schema");
  }
  // Bootstrap's owning job creates the organisation table if absent.
  if (stage === "platform-bootstrap") {
    grant("CREATE,SELECT,INSERT", "yp.organisation", "bootstrap");
    for (const name of ["domain", "sys_conf", "entity", "drumate", "privilege"]) table(name, "SELECT,INSERT", "bootstrap");
    grant("EXECUTE", "FUNCTION yp.uniqueId", "bootstrap");
  }
  for (const role of ["enrollment", "provisioner", "runtime"]) {
    for (const name of read) table(name, "SELECT", role);
  }
  if (tables.includes("initial_operator_enrollment")) {
    table("initial_operator_enrollment", "SELECT,UPDATE", "enrollment");
    for (const name of ["entity", "drumate", "privilege"]) table(name, "INSERT", "enrollment");
    grant("UPDATE (remit)", "yp.drumate", "enrollment");
    // MariaDB 11.4 exposes routine bodies to their owner or mysql.proc readers.
    // Enrollment's canonical structural validator requires this read-only job grant.
    grant("SELECT", "mysql.proc", "enrollment");
  }
  for (const role of ["enrollment", "provisioner", "runtime"]) {
    for (const name of ["uniqueId", "domain_permission"]) if (tables.includes("drumate")) grant("EXECUTE", "FUNCTION yp." + name, role);
    if (["operator-schema", "kernel-schema", "initial-operator", "operator-authentication"].includes(stage)) grant("EXECUTE", "FUNCTION yp.get_remit", role);
  }
  for (const role of ["provisioner", "runtime"]) {
    for (const name of transport) table(name, "INSERT,UPDATE,DELETE", role);
    if (tables.includes("socket")) for (const name of ["session_signin", "session_ensure", "authn_store", "socket_bind", "socket_get", "socket_free", "socket_list_session", "socket_refresh"]) grant("EXECUTE", "PROCEDURE yp." + name, role);
  }
  if (tables.includes("hub_lifecycle")) {
    for (const name of hub_tables) table(name, "SELECT,INSERT,UPDATE,DELETE", "provisioner");
    table("entity", "INSERT,UPDATE", "provisioner");
    grant("CREATE,ALTER,DROP,INDEX,CREATE ROUTINE,ALTER ROUTINE,EXECUTE,SELECT,INSERT,UPDATE,DELETE", "`hub\\_%`.*", "provisioner");
    output.push("GRANT SELECT,EXECUTE ON `hub\\_%`.* TO 'kernel_provisioner'@'%' WITH GRANT OPTION;");
  }
  return output.join("\n");
}
module.exports = { grants, read, transport, hub_tables, roles };
