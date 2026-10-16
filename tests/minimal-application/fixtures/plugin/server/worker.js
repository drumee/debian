"use strict";
const fs = require("node:fs");
module.exports = class Qualification {
  ping() { return { message: "native-distribution-rpc", banner: process.env.APP_BANNER || "first" }; }
  write() { const file = "/app/state/preserved", count = fs.existsSync(file) ? Number(fs.readFileSync(file, "utf8")) : 0; fs.writeFileSync(file, String(count + 1), { mode: 0o600 }); return { count: count + 1 }; }
  async smtp_probe(input = {}) {
    const cfg = JSON.parse(process.env.APP_SMTP_CONFIG);
    const transport = require("nodemailer").createTransport({ host: cfg.host, port: cfg.port, secure: false, requireTLS: true, connectionTimeout: 3000, greetingTimeout: 3000, socketTimeout: 5000, ...(!input.unauthenticated ? { auth: { user: cfg.user, pass: input.bad_auth ? "deliberately-wrong" : fs.readFileSync(cfg.password_file, "utf8") } } : {}), tls: { servername: cfg.servername, ca: fs.readFileSync(cfg.ca_file), rejectUnauthorized: true } });
    try { if (input.unauthenticated) { await transport.sendMail({ from: "sender@fixture.invalid", to: "recipient@fixture.invalid", subject: "IL5 refusal", text: "Disposable test only" }); return { relay_accepted: true }; } await transport.verify(); return { starttls_authenticated: true }; } finally { transport.close(); }
  }
  denied() { throw Error("UNAUTHORIZED_WORKER_MUST_NOT_EXECUTE"); }
};
