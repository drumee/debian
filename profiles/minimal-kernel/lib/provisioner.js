"use strict";
const path = require("node:path");
const { connect, identifier, fail } = require("./database");
const { runtime, components, system_mfs, permissionValue } = require("./components");
async function grantRuntime(database, hub) {
  if (!/^hub_[a-f0-9]{16}$/.test(hub.database_name)) fail("HUB_SHARD_IDENTIFIER_INVALID");
  const root = path.dirname(require.resolve("@drumee/system-mfs/package.json"));
  const manifest = require(path.join(root, "server/schemas/SCHEMA_MANIFEST.json"));
  // Only the exact canonical objects in this successfully provisioned shard.
  for (const table of manifest.objects.common.tables) await database.query(`GRANT SELECT ON ${identifier(hub.database_name)}.${identifier(table)} TO 'kernel_runtime'@'%'`);
  for (const [kind, names] of [["FUNCTION", manifest.objects.common.functions], ["PROCEDURE", manifest.objects.common.procedures]]) for (const name of names) await database.query(`GRANT EXECUTE ON ${kind} ${identifier(hub.database_name)}.${identifier(name)} TO 'kernel_runtime'@'%'`);
}
async function start() {
  const db = await connect(), { lifecycle, hub_store, mfs_store, yellow_page, sessions } = components(db);
  if (!(await system_mfs.validateInstallation({ store: mfs_store })).valid) fail("SYSTEM_MFS_SCHEMA_INVALID");
  const descriptors = new runtime.DescriptorRegistry({ permissionValue });
  descriptors.registerDescriptor("hub", { modules: { private: "provisioner-worker.js" }, services: { create: { scope: "platform", permission: { src: "PLATFORM_ADMINISTRATOR" } } } }, { workdir: __dirname });
  descriptors.registerDescriptor("health", { modules: { public: "provisioner-worker.js" }, services: { ready: { scope: "kernel", permission: { src: "anonymous", fast_check: "public-api" } } } }, { workdir: __dirname });
  class Worker {
    constructor({ session }) { this.session = session; }
    async ready() { await db.query("SELECT 1"); return { ready: true }; }
    async create(input) {
      // No caller-selected principal, SQL account, creator module or grant policy.
      if (!input || Object.keys(input).some(key => !["name", "idempotency_key"].includes(key))) fail("HUB_SPECIFICATION_INVALID");
      const dedicated = await connect();
      try {
        const cp = components(dedicated);
        const result = await cp.lifecycle.createPrivateHub({ session: this.session, creator_module: "system-mfs", specification: input });
        const hub = await cp.hub_store.getHub(result.hub_id);
        if (result.status !== "ready" || hub.creator_uid !== this.session.uid() || !(await system_mfs.validateProvisioning({ store: cp.mfs_store, context: { hub_id: hub.hub_id } })).valid) fail("HUB_NOT_READY");
        await grantRuntime(dedicated, hub); return result;
      } finally { await dedicated.close(); }
    }
  }
  const dispatcher = new runtime.ServiceDispatcher({ registry: descriptors, authorize: runtime.createAuthorizer({ platformAuthorizer: new runtime.PlatformAuthorizer({ store: yellow_page }) }), requireWorker: () => Worker });
  const server = runtime.createServiceServer({ dispatcher, sessionFactory: request => sessions.fromRequest(request) });
  await new Promise(resolve => server.listen(3103, "0.0.0.0", resolve));
  console.log("PROVISIONER_READY");
  for (const signal of ["SIGTERM", "SIGINT"]) process.once(signal, () => server.close(() => db.close().finally(() => process.exit(0))));
  return server;
}
if (require.main === module) start().catch(error => { console.error(/^[A-Z0-9_]+$/.test(error.code || "") ? error.code : "PROVISIONER_START_FAILED"); process.exit(1); });
module.exports = { start, grantRuntime };
