"use strict";
const fs = require("node:fs"), http = require("node:http"), path = require("node:path");
const { connect, fail } = require("./database");
const { runtime, system_mfs, platform, vendor, Constants, permissionValue, components } = require("./components");
async function start() {
  const db = await connect();
  if (!(await platform.validate({ database: db, domain: process.env.DRUMEE_DOMAIN })).valid) fail("PLATFORM_NOT_READY");
  const { hub_store, mfs_store, yellow_page, sessions } = components(db);
  if (!(await system_mfs.validateInstallation({ store: mfs_store })).valid) fail("MFS_INSTALLATION_NOT_READY");
  const { HostFilesystem, FileIo } = vendor("host-filesystem");
  const { MfsService, MfsPermissionBackend, MfsEventAclAuthorizer, MfsEventPublisher } = vendor("mfs-service");
  const { TransferStaging, MfsTransferService } = vendor("mfs-transfer");
  const staging = new TransferStaging({ root: "/content/transfers" });
  const content_store = new system_mfs.LocalContentStore({ root: "/content", staging });
  const host_filesystem = new HostFilesystem({ root: "/content" });
  const file_io = new FileIo({ host_filesystem });
  const { MediaService, RepresentationManager } = vendor("media-service");
  const representations = new RepresentationManager({ host_filesystem });
  const media_service = new MediaService({ host_filesystem, representations, node_resolver: node => mfs_store.getNode(null, node) });
  const hub_authorizer = new runtime.HubAuthorizer({ resolver: hub_store, permissionValue });
  const permission_backend = new MfsPermissionBackend({ permission_store: mfs_store });
  process.env.credential_dir = "/run/infra";
  const RedisStore = require("../vendor/essentials/redis-store");
  const redis = new RedisStore(); await redis.init();
  const push = new runtime.PushBus({ redisStore: RedisStore, socketStore: yellow_page, logger: null });
  const event_acl = new MfsEventAclAuthorizer({ session_resolver: recipient => sessions.fromSessionId(recipient.session_id), hub_authorizer, permission_backend, permission_contract: Constants.permission, read_permission: permissionValue("read") });
  const events = new MfsEventPublisher({ recipients: () => db.query("SELECT id AS socket_id,session_id,uid FROM socket"), authorize: request => event_acl.authorize(request), transport: { publishRecipient: ({ principal, service, payload }) => push.publish({ service, data: payload, dest: principal.socket_id }) } });
  const mfs_service = new MfsService({ filesystem_factory: principal => new system_mfs.MfsFilesystem({ store: mfs_store, principal: principal.uid, content_store }), events, permission_backend, permission_contract: Constants.permission });
  const mfs_transfer = new MfsTransferService({ mfs_service, staging, host_filesystem, max_upload_chunk_size: 1024 * 1024, upload_chunk_size: 1024 * 1024 });
  permission_backend.transfer_resource = request => request.service === "kernel.original" ? { src: [request.input.node] } : mfs_transfer.resourceFor(request);
  const descriptors = new runtime.DescriptorRegistry({ permissionValue });
  descriptors.registerDirectory(path.join(path.dirname(require.resolve("@drumee/server-runtime/package.json")), "acl"));
  for (const name of ["mfs-service", "mfs-transfer", "media-service"]) descriptors.registerDirectory(path.join(__dirname, "../vendor", name, "server/acl"));
  descriptors.registerDescriptor("kernel", { modules: { private: "worker.js" }, services: { platform_info: { scope: "platform", permission: { src: "PLATFORM_ADMINISTRATOR" } }, context: { scope: "domain", permission: { src: 1 } }, create_hub: { scope: "platform", permission: { src: "PLATFORM_ADMINISTRATOR" } }, original: { scope: "mfs", requires: ["system-mfs"], permission: { src: "read" } } } }, { workdir: __dirname });
  class KernelWorker {
    constructor({ session }) { this.session = session; }
    async create_hub(input) {
      const response = await fetch("http://provisioner:3103/-/svc/hub.create", { method: "POST", headers: { "content-type": "application/json", cookie: runtime.SESSION_COOKIE + "=" + encodeURIComponent(this.session.sid) }, body: JSON.stringify(input), signal: AbortSignal.timeout(120000) });
      const payload = await response.json();
      if (!response.ok || payload.status !== "ok") fail(/^[A-Z0-9_]+$/.test(payload.code || "") ? payload.code : "HUB_PROVISIONING_FAILED");
      return payload.data;
    }
    async platform_info() { return { policy: "PLATFORM_ADMINISTRATOR" }; }
    async context() {
      const hubs = await db.query("SELECT hub_id,public_name FROM hub_lifecycle WHERE creator_uid=? ORDER BY hub_id", this.session.uid());
      return { hubs: await Promise.all(hubs.map(async hub => ({ hub_id: hub.hub_id, name: hub.public_name, root: { hub_id: hub.hub_id, nid: (await system_mfs.validateProvisioning({ store: mfs_store, context: { hub_id: hub.hub_id } })).root_id } }))) };
    }
    async original(input) { const node = await mfs_store.getNode(null, input.node); return file_io.send(this.session.output, host_filesystem.original(node), { name: node.filename, mimetype: node.mimetype }); }
  }
  const dispatcher = new runtime.ServiceDispatcher({ registry: descriptors, authorize: runtime.createAuthorizer({ platformAuthorizer: new runtime.PlatformAuthorizer({ store: yellow_page }), domainAuthorizer: new runtime.DomainAuthorizer({ store: yellow_page }), hubAuthorizer: hub_authorizer, mfsPermissionBackend: permission_backend }), capability_resolver: new runtime.CapabilityResolver({ providers: { "system-mfs": async ({ hub_context, hub_contexts }) => {
    const contexts = Object.values(hub_contexts || (hub_context ? { current: hub_context } : {}));
    if (!contexts.length) return { available: false, status: "hub-required" };
    const reports = await Promise.all(contexts.map(context => system_mfs.capabilityAvailable({ store: mfs_store, context: { hub_id: context.hub_id } })));
    return { available: reports.every(report => report.available), status: "validated-shards" };
  } } }), requireWorker: filename => filename === path.join(__dirname, "worker.js") ? KernelWorker : require(filename), workerOptions: { mfs_service, mfs_transfer, file_io, media_service, pluginResolver: new runtime.FrontendPluginResolver({ roots: [{ directory: "/public/plugins", publicPrefix: "/-/plugins" }] }) } });
  const server = runtime.createServiceServer({ dispatcher, sessionFactory: request => sessions.fromRequest(request), binary_uploads: { "mfs-transfer.upload_chunk": { directory: "/tmp/incoming", max_bytes: 1024 * 1024, before_receive: ({ input, session }) => mfs_transfer.uploadPreflight(input, { uid: session.uid() }) } } });
  const websocket = new runtime.WebSocketPushRouter({ httpServer: server, sessionManager: sessions, socketStore: yellow_page, redisStore: RedisStore, logger: null });
  await websocket.start();
  const page = http.createServer(async (request, response) => {
    if (request.url === "/__ready") {
      try { await db.query("SELECT 1"); await RedisStore.getClient().ping(); response.writeHead(200); response.end("kernel-protocol-ready"); }
      catch (_) { response.writeHead(503); response.end("not-ready"); } return;
    }
    if (request.url !== "/" && request.url !== "/bootstrap.js") { response.writeHead(404); response.end(); return; }
    response.writeHead(200, { "content-type": request.url === "/" ? "text/html" : "application/javascript" });
    response.end(fs.readFileSync(request.url === "/" ? "/public/index.html" : "/public/bootstrap.js"));
  });
  await new Promise(resolve => server.listen(3101, "0.0.0.0", resolve));
  // One listener also carries WebSocket. Page stays independent.
  await new Promise(resolve => page.listen(3102, "0.0.0.0", resolve));
  console.log("KERNEL_HOST_READY");
  async function stop() { await websocket.stop(); mfs_transfer.destroy(); server.close(); page.close(); await db.close(); process.exit(0); }
  process.once("SIGTERM", () => stop().catch(() => process.exit(1)));
  process.once("SIGINT", () => stop().catch(() => process.exit(1)));
}
if (require.main === module) start().catch(() => { console.error("KERNEL_HOST_START_FAILED"); process.exitCode = 1; });
module.exports = { start };
