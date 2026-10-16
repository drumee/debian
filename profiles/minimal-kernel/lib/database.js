"use strict";
const fs = require("node:fs"), path = require("node:path");
const mariadb = require("mariadb");
const fail = code => { throw Object.assign(Error(code), { code }); };
function privateFile(file) {
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.uid !== process.getuid() || (stat.mode & 0o077)) fail("UNSAFE_PRIVATE_RESOURCE");
  return fs.readFileSync(file, "utf8");
}
function identifier(name) { if (!/^[a-z][a-z0-9_]{0,62}$/.test(name)) fail("INVALID_SQL_IDENTIFIER"); return "`" + name + "`"; }
// Narrow mysql-client DELIMITER interpreter for the pinned package manifests.
// SQL remains owned by those packages; parameters never pass through this parser.
function statements(script) {
  let delimiter = ";", buffer = ""; const output = [];
  for (const line of script.split(/\r?\n/)) {
    const directive = /^\s*DELIMITER\s+(\S+)\s*$/i.exec(line);
    if (directive) {
      if (buffer.trim()) fail("INVALID_SCHEMA_DELIMITER"); delimiter = directive[1]; continue;
    }
    if (!buffer && /^\s*(?:--.*)?$/.test(line)) continue;
    buffer += line + "\n";
    if (buffer.trimEnd().endsWith(delimiter)) { output.push(buffer.trimEnd().slice(0, -delimiter.length)); buffer = ""; }
  }
  if (buffer.trim()) fail("INCOMPLETE_SCHEMA_STATEMENT");
  return output;
}
async function connect({ role = process.env.DRUMEE_SQL_ROLE, selected = "yp" } = {}) {
  if (!["schema", "bootstrap", "enrollment", "provisioner", "runtime"].includes(role)) fail("SQL_ROLE_REQUIRED");
  const connection = await mariadb.createConnection({ host: "database", port: 3306, user: "kernel_" + role, password: privateFile("/run/infra/database"), ...(selected ? { database: selected } : {}), bigIntAsNumber: true, multipleStatements: true });
  return {
    connection,
    async query(sql, ...parameters) { return connection.query(sql, parameters); },
    async await_query(sql, ...parameters) { return this.query(sql, ...parameters); },
    async await_proc(name, ...parameters) { return this.query(`CALL ${identifier(name)}(${parameters.map(() => "?").join(",")})`, ...parameters); },
    async await_func(name, ...parameters) { return (await this.query(`SELECT ${identifier(name)}(${parameters.map(() => "?").join(",")}) AS value`, ...parameters))[0]; },
    async executeScript(script, { database = selected } = {}) {
      // Same connection preserves transaction affinity for platform bootstrap.
      await connection.query("USE " + identifier(database));
      try { for (const statement of statements(script)) await connection.query(statement); }
      finally { if (selected) await connection.query("USE " + identifier(selected)); }
    },
    async queryIn(database, sql, ...parameters) {
      identifier(database);
      const shard = await connect({ role, selected: database });
      try { return await shard.query(sql, ...parameters); } finally { await shard.close(); }
    },
    close() { return connection.end(); }
  };
}
function manifestEntries(package_root) {
  const manifest = JSON.parse(fs.readFileSync(path.join(package_root, "schemas/SCHEMA_MANIFEST.json")));
  const pkg = JSON.parse(fs.readFileSync(path.join(package_root, "package.json")));
  if (manifest.owner !== pkg.name || manifest.packageVersion !== pkg.version || manifest.manifestVersion !== 1 || !Array.isArray(manifest.install)) fail("INVALID_RUNTIME_SCHEMA_MANIFEST");
  const orders = new Set();
  return manifest.install.map(entry => {
    if (!Number.isInteger(entry.order) || orders.has(entry.order) || typeof entry.path !== "string" || path.isAbsolute(entry.path) || entry.path.split(/[\\/]/).includes("..")) fail("INVALID_RUNTIME_SCHEMA_MANIFEST");
    orders.add(entry.order); const file = path.resolve(package_root, entry.path);
    if (!fs.realpathSync(file).startsWith(fs.realpathSync(package_root) + path.sep)) fail("UNSAFE_SCHEMA_PATH");
    return { ...entry, file };
  }).sort((a, b) => a.order - b.order);
}
module.exports = { connect, privateFile, identifier, statements, manifestEntries, fail };
