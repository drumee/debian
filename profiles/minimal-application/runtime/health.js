"use strict";
module.exports = class Health { ready() { return { ready: true, runtime: "0.1.0-alpha.4" }; } };
if (require.main === module) {
  const cfg = JSON.parse(process.env.DRUMEE_APP_CONFIG);
  const req = require("node:http").get({ hostname: "127.0.0.1", port: cfg.port, path: "/-/svc/health.ready" }, res => { const bytes = []; let length = 0; res.on("data", chunk => { length += chunk.length; if (length > 4096) req.destroy(); else bytes.push(chunk); }); res.on("end", () => { try { process.exit(res.statusCode === 200 && JSON.parse(Buffer.concat(bytes)).status === "ok" ? 0 : 1); } catch (_) { process.exit(1); } }); });
  req.setTimeout(2000, () => req.destroy()); req.on("error", () => process.exit(1));
}
