"use strict";
const runtime_api = require("@drumee/ui-runtime/browser");
const finder = require("@drumee/finder");
const manager_api = require("@drumee/window-manager/browser");
const { FinderWindow } = require("@drumee/finder/window");
class Transport {
  async postService(service, input = {}) {
    const response = await fetch("/-/svc/" + service, { method: "POST", credentials: "same-origin", headers: { "content-type": "application/json" }, body: JSON.stringify(input) });
    const payload = await response.json();
    if (!response.ok || payload.status !== "ok") throw Object.assign(Error(payload.code || "SERVICE_FAILED"), { code: payload.code });
    return payload.data;
  }
}
// No credentials in HTML, artifacts or URLs. Acceptance injects a one-shot
// login into this operator-invoked function over a private browser connection.
window.openDrumee = async function ({ uid, password }) {
  const transport = new Transport();
  await transport.postService("yp.signin", { uid, password });
  const context = await transport.postService("kernel.context");
  const websocket = new runtime_api.Websocket({ global: window, url: location.origin.replace(/^http/, "ws") + "/-/websocket/", serviceClient: transport, WebSocket });
  const messages = []; websocket.on("message", message => messages.push(message)); await websocket.connect();
  const runtime = await runtime_api.bootstrap({ serviceClient: transport, websocket });
  finder.registerFinderKinds(runtime);
  const mfs_client = new finder.MfsClient({ transport });
  const mfs_sync = new finder.MfsSync({ websocket });
  const manager = manager_api.createWindowManager({ workspace: document.getElementById("workspace"), runtime, jquery: runtime_api.Backbone.$ });
  if (!context.hubs.length) { document.getElementById("workspace").textContent = "Signed in. Create a Hub to open Finder."; return { ready: true, hubs: 0 }; }
  const view = new FinderWindow({ manager, runtime, finder_options: { finder_id: "minimal-kernel", location: context.hubs[0].root, mfs_client, mfs_sync, title: "Drumee Finder" }, window_options: { window_id: "finder-main", geometry: { left: 20, top: 20, width: 700, height: 500 } } });
  await view.finder.refresh();
  window.kernelAcceptance = { transport, context, runtime, websocket, messages, mfs_client, view };
  document.body.dataset.ready = "true";
  return { ready: true, hubs: context.hubs.length, kind: "finder", item_count: view.finder.item_list.values().length };
};
document.body.dataset.bundle = "loaded";

const form = document.getElementById("login");
form.addEventListener("submit", async event => {
  event.preventDefault();
  const username = form.elements.username.value, password = form.elements.password.value;
  form.elements.password.value = "";
  try { await window.openDrumee({ uid: username, password }); form.hidden = true; }
  catch (_) { document.getElementById("message").textContent = "Sign-in failed."; }
});
