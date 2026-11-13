"use strict";
const path = require("node:path");
// Rendering is read-only. Installation is a separate, lab/target-owned operation.
function render(config, cfg) {
  const quote = value => {
    if (/[\r\n\0]/.test(value)) throw Error("MAIL_BOOT_UNIT_PATH_INVALID");
    return '"' + value.replace(/%/g, "%%").replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
  };
  const args = operation => [process.execPath, path.join(__dirname, "operator.js"), operation, "--config", config, "--execute"].map(quote).join(" ");
  return `[Unit]
Description=Drumee independent mail ${cfg.service.deployment.project}
Requires=docker.service
After=docker.service local-fs.target
RequiresMountsFor=${["spool", "mailboxes", "registry", "operator-state", "policy-state", "tls"].map(name => quote(cfg.service.deployment.root + "/durable/" + name)).join(" ")}

[Service]
Type=oneshot
RemainAfterExit=yes
User=${cfg.service.deployment.owner_uid}
Group=${cfg.service.deployment.owner_gid}
SupplementaryGroups=docker
ExecStartPre=${args("preflight")}
ExecStart=${args("start")}
ExecStop=${args("stop")}
TimeoutStartSec=180
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
`;
}
module.exports = { render };
