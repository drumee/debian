"use strict";
// Test-only isolated provider. Credentials are compared in memory, never logged.
const fs = require("node:fs"), http = require("node:http"), { SMTPServer } = require("smtp-server");
const cfg = JSON.parse(fs.readFileSync("/fixture/input.json"));
const state = { connections: 0, authentications: 0, account_exact: true, password_exact: true, tls_only: true, deferrals: 0, messages: 0, envelope_exact: true, body_exact: true };
let deliveryAllowed = !cfg.defer;
const server = new SMTPServer({ logger: false, key: fs.readFileSync("/fixture/provider.key"), cert: fs.readFileSync("/fixture/provider.pem"),
  ...(cfg.mode === "no-starttls" ? { disabledCommands: ["STARTTLS"], allowInsecureAuth: true } : {}),
  onConnect(session, done) { state.connections++; done(); },
  onAuth(auth, session, done) {
    state.authentications++; state.account_exact &&= auth.username === cfg.user; state.password_exact &&= auth.password === cfg.password; state.tls_only &&= session.secure === true;
    done(auth.username === cfg.user && auth.password === cfg.password && session.secure ? null : Object.assign(Error("Synthetic authentication refusal"), { responseCode: 535 }), { user: "fixture" });
  },
  onRcptTo(address, session, done) { if (!deliveryAllowed) { state.deferrals++; done(Object.assign(Error("Synthetic controlled deferral"), { responseCode: 451 })); } else done(); },
  onData(stream, session, done) {
    let body = ""; stream.on("data", chunk => body += chunk);
    stream.on("end", () => { state.messages++; state.envelope_exact &&= session.envelope.mailFrom.address === "sender@fixture.invalid" && session.envelope.rcptTo.length === 1 && session.envelope.rcptTo[0].address === "recipient@fixture.invalid"; state.body_exact &&= body.includes("Capture relay only; no Internet delivery"); done(); });
  }
});
server.on("error", () => {}); server.listen(2525, "0.0.0.0");
http.createServer((request, response) => { if (request.method === "POST" && request.url === "/allow") deliveryAllowed = true; response.setHeader("content-type", "application/json"); response.end(JSON.stringify(state)); }).listen(8025, "0.0.0.0");
