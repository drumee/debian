"use strict";
// Distribution composition only: the published Runtime owns the HTTP adapter,
// descriptors, anonymous default context, authorization and RPC dispatcher.
const fs = require("node:fs"), path = require("node:path");
const runtime = require("@drumee/server-runtime");
if (require("@drumee/server-runtime/package.json").version !== "0.1.0-alpha.4") throw Error("APPLICATION_RUNTIME_VERSION_MISMATCH");
const intent = JSON.parse(process.env.DRUMEE_APP_CONFIG || "null");
const inventory = JSON.parse(fs.readFileSync("/app/plugins-manifest.json"));
if (!intent || !Number.isInteger(intent.port) || intent.port < 1024 || intent.port > 65535 || JSON.stringify(intent.plugins) !== JSON.stringify(inventory)) throw Error("APPLICATION_IMAGE_PLUGIN_MISMATCH");
const registry = new runtime.DescriptorRegistry();
registry.registerDescriptor("health", { modules: { public: "health" }, services: { ready: { scope: "domain", permission: { src: 0, fast_check: "public-api" } } } }, { workdir: "/app" });
for (const plugin of inventory) {
  if (plugin.root !== "/app/plugins/" + plugin.id + "/server") throw Error("APPLICATION_PLUGIN_ROOT_INVALID");
  const artifact = JSON.parse(fs.readFileSync(path.dirname(plugin.root) + "/.drumee-artifact.json"));
  if (artifact.id !== plugin.id || artifact.revision !== plugin.revision) throw Error("APPLICATION_PLUGIN_PROVENANCE_MISMATCH");
  registry.registerDirectory(path.join(plugin.root, "acl"));
}
const dispatcher = new runtime.ServiceDispatcher({ registry, authorize: runtime.createAuthorizer() });
const server = runtime.createServiceServer({ dispatcher });
server.listen(intent.port, "0.0.0.0");
for (const signal of ["SIGTERM", "SIGINT"]) process.once(signal, () => server.close(() => process.exit(0)));
