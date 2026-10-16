"use strict";
const fs = require("node:fs"), path = require("node:path");
const root = path.resolve(__dirname, "..");
async function build() {
  const { createConfig } = require("../vendor/ui-build/lib");
  const output = path.join(root, "public");
  const plugin = path.join(output, "plugins/finder");
  const config = createConfig({ root, name: "finder", type: "minimal-kernel", entry: "./browser/entry.js", outputPath: plugin, publicPath: "/-/plugins/finder/", version: "0.0.0-il4", rev: require("../sources.lock.json").revision, loaderRoots: [path.join(root, "node_modules")] });
  await new Promise((resolve, reject) => require("webpack")(config, (error, stats) => {
    if (error || stats.hasErrors()) reject(Error("BROWSER_BUILD_FAILED: " + (error?.message || stats.toString({ all: false, errors: true })))); else resolve();
  }));
  const metadata = JSON.parse(fs.readFileSync(path.join(plugin, "index.json")));
  // Runtime plugin resolution consumes the actual ui-build entry metadata.
  fs.writeFileSync(path.join(output, "index.html"), '<!doctype html><meta charset="utf-8"><title>Drumee</title><form id="login"><label>Username <input name="username" autocomplete="username" required></label><label>Password <input name="password" type="password" autocomplete="current-password" required></label><button>Sign in</button></form><p id="message"></p><div id="workspace"></div><script src="/bootstrap.js"></script>');
  fs.writeFileSync(path.join(output, "bootstrap.js"), `(async()=>{const r=await fetch('/-/svc/bootstrap.plugin?name=finder');const p=await r.json();if(!r.ok)throw Error('PLUGIN_RESOLUTION_FAILED');const s=document.createElement('script');s.src=p.data.path;document.head.append(s)})().catch(()=>{document.body.dataset.error='BOOTSTRAP_FAILED'});\n`);
  console.log("BROWSER_BUILD_VALID " + metadata.hash);
}
if (require.main === module) build().catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = { build };
