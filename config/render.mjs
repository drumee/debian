#!/usr/bin/env node
// Drumee config renderer — single source of truth -> channel artifacts.
//
//   node config/render.mjs <command> [--config FILE] [--out FILE] [--out-dir DIR]
//
// commands:
//   validate   parse + validate the config, print a normalized summary
//   env        emit the container-channel .env
//   compose    emit docker-compose.yml (optional-service profiles toggled by config)
//   debconf    emit the native-channel debconf preseed (install.conf)
//   all        emit .env, docker-compose.yml and install.conf into --out-dir
//
// Dependency-free: a constrained YAML reader covers the documented config subset.
// The formal contract lives in config/drumee.schema.json.

import { readFileSync, writeFileSync, mkdirSync, chmodSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { execSync } from 'node:child_process';
import { dirname, join } from 'node:path';

// ---------------------------------------------------------------- arg parsing
function parseArgs(argv) {
  const [command, ...rest] = argv;
  const opts = { config: 'config/drumee.yaml', out: null, outDir: 'out' };
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (a === '--config') opts.config = rest[++i];
    else if (a === '--out') opts.out = rest[++i];
    else if (a === '--out-dir') opts.outDir = rest[++i];
    else die(`unknown argument: ${a}`);
  }
  return { command, opts };
}

function die(msg) {
  console.error(`render: ${msg}`);
  process.exit(1);
}

// ----------------------------------------------------------- minimal YAML read
// Supports: 2-space indentation (any depth), `key:` sections, `key: scalar`,
// inline lists `[a, b]`, comments, and scalar types string/int/bool/null.
function parseYaml(text) {
  const root = {};
  const stack = [{ indent: -1, container: root }];
  const lines = text.split('\n');
  for (let n = 0; n < lines.length; n++) {
    const raw = lines[n];
    if (/^\s*$/.test(raw) || /^\s*#/.test(raw)) continue;
    if (raw.includes('\t')) die(`line ${n + 1}: tabs are not allowed, use spaces`);
    const indent = raw.length - raw.trimStart().length;
    const m = raw.trimStart().match(/^([\w-]+):\s*(.*)$/);
    if (!m) die(`line ${n + 1}: expected "key: value", got: ${raw.trim()}`);
    const [, key, rhs] = m;
    while (stack.length && stack[stack.length - 1].indent >= indent) stack.pop();
    if (!stack.length) die(`line ${n + 1}: indentation error`);
    const parent = stack[stack.length - 1].container;
    if (rhs === '') {
      const obj = {};
      parent[key] = obj;
      stack.push({ indent, container: obj });
    } else {
      parent[key] = parseScalar(rhs, n + 1);
    }
  }
  return root;
}

function parseScalar(s, line) {
  s = s.trim();
  if (s[0] === '"' || s[0] === "'") {
    const q = s[0];
    const end = s.indexOf(q, 1);
    if (end === -1) die(`line ${line}: unterminated quote`);
    return s.slice(1, end);
  }
  s = s.split(/\s+#/)[0].trim(); // strip inline comment
  if (s.startsWith('[') && s.endsWith(']')) {
    const inner = s.slice(1, -1).trim();
    if (inner === '') return [];
    return inner.split(',').map((x) => parseScalar(x, line));
  }
  if (s === 'true') return true;
  if (s === 'false') return false;
  if (s === 'null' || s === '~' || s === '') return null;
  if (/^-?\d+$/.test(s)) return parseInt(s, 10);
  return s;
}

// --------------------------------------------------------- defaults + validate
const SCHEMA = JSON.parse(
  readFileSync(new URL('./drumee.schema.json', import.meta.url), 'utf8'),
);
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

function applyDefaults(cfg) {
  const out = {};
  for (const [section, spec] of Object.entries(SCHEMA.properties)) {
    const given = cfg[section] ?? {};
    if (typeof given !== 'object' || Array.isArray(given)) {
      die(`section "${section}" must be a mapping`);
    }
    out[section] = {};
    for (const [key, kspec] of Object.entries(spec.properties ?? {})) {
      out[section][key] = key in given ? given[key]
        : 'default' in kspec ? structuredClone(kspec.default)
        : undefined;
    }
    for (const key of Object.keys(given)) {
      if (!(key in (spec.properties ?? {}))) die(`unknown key "${section}.${key}"`);
    }
  }
  for (const section of Object.keys(cfg)) {
    if (!(section in SCHEMA.properties)) die(`unknown section "${section}"`);
  }
  return out;
}

function validate(cfg) {
  const errs = [];
  const i = cfg.instance;
  if (!i.description) errs.push('instance.description is required');
  if (!i.domain) errs.push('instance.domain is required');
  if (!i.admin_email || !EMAIL_RE.test(i.admin_email))
    errs.push('instance.admin_email must be a valid email');

  const mode = cfg.tls.mode;
  if (!['acme', 'own', 'self-signed'].includes(mode))
    errs.push(`tls.mode must be one of acme|own|self-signed (got ${mode})`);
  if (mode === 'acme' && (!cfg.tls.acme_email || !EMAIL_RE.test(cfg.tls.acme_email)))
    errs.push('tls.acme_email must be a valid email when tls.mode=acme');
  if (mode === 'own' && !cfg.tls.own_cert_path)
    errs.push('tls.own_cert_path is required when tls.mode=own');

  for (const [s, k] of [['database', 'port'], ['redis', 'port'], ['email', 'port']])
    if (cfg[s][k] != null && !Number.isInteger(cfg[s][k]))
      errs.push(`${s}.${k} must be an integer`);

  if (errs.length) die('config invalid:\n  - ' + errs.join('\n  - '));
}

function genSecret() {
  return randomBytes(24).toString('base64url');
}

// Fill generated secrets; returns list of which were generated (for warnings).
function fillSecrets(cfg) {
  const generated = [];
  // Redis runs on the internal compose network only; we do NOT auto-generate a
  // password because the app currently has a secondary Redis client that doesn't
  // authenticate (NOAUTH). Set redis.password explicitly once that's fixed upstream.
  for (const path of ['database.password', 'database.root_password']) {
    const [s, k] = path.split('.');
    if (cfg[s][k] == null) { cfg[s][k] = genSecret(); generated.push(path); }
  }
  return generated;
}

// --------------------------------------------------------------- env rendering
function envValue(v) {
  if (v == null) return '';
  const str = String(v);
  return /[\s"'#$]/.test(str) ? `"${str.replace(/"/g, '\\"')}"` : str;
}

function renderEnv(cfg) {
  const profiles = Object.entries(cfg.optional_services)
    .filter(([, on]) => on).map(([name]) => name);
  // Variable names intentionally match what setup-infra's wizard already writes,
  // so existing scripts consume this file unchanged.
  const pairs = {
    DRUMEE_DESCRIPTION: cfg.instance.description,
    DRUMEE_DOMAIN_NAME: cfg.instance.domain,
    LOCAL_MODE: cfg.instance.local_mode,
    ADMIN_EMAIL: cfg.instance.admin_email,
    PUBLIC_IP4: cfg.network.ip4,
    PUBLIC_IP6: cfg.network.ip6,
    SERVICES: cfg.network.services.join(','),
    TLS_MODE: cfg.tls.mode,
    ACME_EMAIL_ACCOUNT: cfg.tls.acme_email ?? '',
    OWN_SSL: cfg.tls.mode === 'own',
    OWN_SSL_PATH: cfg.tls.own_cert_path ?? '',
    DRUMEE_DATA_DIR: cfg.storage.data_dir,
    DRUMEE_DB_DIR: cfg.storage.db_dir,
    BACKUP_LOCATION: cfg.storage.backup_location ?? '',
    EXCHANGE_LOCATION: cfg.storage.exchange_location,
    DB_HOST: cfg.database.host,
    DB_PORT: cfg.database.port,
    DB_NAME: cfg.database.name,
    DB_USER: cfg.database.user,
    DB_PASSWORD: cfg.database.password,
    DB_ROOT_PASSWORD: cfg.database.root_password,
    REDIS_HOST: cfg.redis.host,
    REDIS_PORT: cfg.redis.port,
    REDIS_PASSWORD: cfg.redis.password ?? '',
    SMTP_HOST: cfg.email.host ?? '',
    SMTP_PORT: cfg.email.port,
    SMTP_SECURE: cfg.email.secure,
    SMTP_USER: cfg.email.user ?? '',
    SMTP_PASSWORD: cfg.email.password ?? '',
    API_PORT: cfg.ports.api,
    UI_PORT: cfg.ports.ui,
    IMAGE_REGISTRY: cfg.images.registry,
    SERVER_TAG: cfg.versions.server,
    UI_TAG: cfg.versions.ui,
    SCHEMAS_TAG: cfg.versions.schemas,
    STATIC_TAG: cfg.versions.static,
    PLUGIN_TAG: cfg.plugins.tag,
    PLUGINS_SERVER: cfg.plugins.server.join(','),
    PLUGINS_UI: cfg.plugins.ui.join(','),
    COMPOSE_PROFILES: profiles.join(','),
  };
  const header = '# Generated by config/render.mjs — do not edit by hand.\n'
    + '# Edit config/drumee.yaml and re-render.\n';
  return header + Object.entries(pairs)
    .map(([k, v]) => `${k}=${envValue(v)}`).join('\n') + '\n';
}

// --------------------------------------------------------- debconf preseed
function dc(key, type, value) {
  return `drumee-infra\tdrumee-infra/${key}\t${type}\t${value ?? ''}`;
}

function renderDebconf(cfg) {
  const lines = [
    '# Generated by config/render.mjs — feed to: debconf-set-selections < install.conf',
    dc('description', 'string', cfg.instance.description),
    dc('domain', 'string', cfg.instance.domain),
    dc('local_mode', 'boolean', cfg.instance.local_mode),
    dc('service', 'string', cfg.network.services.join(',')),
    dc('admin_email', 'string', cfg.instance.admin_email),
    dc('acme_email', 'string', cfg.tls.acme_email ?? ''),
    dc('db_dir', 'string', cfg.storage.db_dir),
    dc('data_dir', 'string', cfg.storage.data_dir),
    dc('backup_location', 'string', cfg.storage.backup_location ?? ''),
    dc('exchange_location', 'string', cfg.storage.exchange_location),
    dc('own_ssl', 'boolean', cfg.tls.mode === 'own'),
    dc('own_ssl_path', 'string', cfg.tls.own_cert_path ?? ''),
  ];
  // Only preseed an explicit IP; 'auto' leaves detection to the installer.
  if (cfg.network.ip4 && cfg.network.ip4 !== 'auto') {
    lines.push(dc('ip4', 'select', 'other'));
    lines.push(dc('public_ip4', 'string', cfg.network.ip4));
  }
  if (cfg.network.ip6 && cfg.network.ip6 !== 'auto') {
    lines.push(dc('ip6', 'select', 'other'));
    lines.push(dc('public_ip6', 'string', cfg.network.ip6));
  }
  return lines.join('\n') + '\n';
}

// --------------------------------------------------------- caddyfile
// Rendered from tls.mode + domain so dev (localhost -> HTTP) and prod (real
// domain -> automatic HTTPS) share one source. Routing is identical across modes:
// static bundles/assets from disk, /-/svc -> REST, everything else -> pages.
function renderCaddyfile(cfg) {
  const dom = cfg.instance.domain;
  const local = cfg.instance.local_mode || dom === 'localhost' || dom === 'local';
  // UI plugin bundles: bootstrap.plugin returns /-/plugins/<name>/<entry>; serve
  // them as static files from the shared plugins volume (published by plugin-ui-*).
  const pluginRoute = cfg.plugins.ui.length
    ? `	handle_path /-/plugins/* {
		root * /srv/plugins/ui/main
		file_server
	}
` : '';
  const body =
`	handle_path /-/app/* {
		root * /srv/ui/main/app
		file_server
	}
	handle_path /-/static/* {
		root * /srv/static
		file_server
	}
	handle_path /-/images/* {
		root * /srv/static/images
		file_server
	}
${pluginRoute}	handle /-/svc/* {
		reverse_proxy server-pod:{$API_PORT:24000}
	}
	reverse_proxy server-pod:{$UI_PORT:23000}
`;
  // Security headers for real deployments (skipped on local HTTP where HSTS
  // would poison the browser for localhost).
  const secHeaders =
`	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains"
		X-Content-Type-Options "nosniff"
		X-Frame-Options "SAMEORIGIN"
		Referrer-Policy "strict-origin-when-cross-origin"
		-Server
	}
`;
  let header = '';
  let site = dom;
  let tls = '';
  if (local) {
    site = ':80';                                  // plain HTTP for local dev
  } else if (cfg.tls.mode === 'acme') {
    header = `{\n\temail ${cfg.tls.acme_email || ''}\n}\n\n`;   // auto HTTPS
  } else if (cfg.tls.mode === 'self-signed') {
    tls = '\ttls internal\n';                      // Caddy local CA
  } else if (cfg.tls.mode === 'own') {
    const p = cfg.tls.own_cert_path;
    tls = `\ttls ${p}/cert.pem ${p}/key.pem\n`;     // bring-your-own certs
  }
  return `# Generated by config/render.mjs from drumee.yaml — do not edit by hand.\n`
    + `${header}${site} {\n${tls}${local ? '' : secHeaders}${body}}\n`;
}

// --------------------------------------------------------- compose
// Source-accurate topology (confirmed against server-team/ui-team):
//   - server-pod runs index.js (pages + WebSocket) and service.js (REST) via pm2
//   - the UI is a build artifact, not a service: ui-build runs once, publishes
//     assets into a shared volume that server-pod serves from $DRUMEE_UI_HOME
//   - the proxy routes everything to server-pod (/-/* = REST, else = pages)
function renderCompose(cfg) {
  const redisCmd = cfg.redis.password
    ? `command: ["redis-server", "--requirepass", "$\{REDIS_PASSWORD}"]` : 'command: ["redis-server"]';

  // ----- plugins -----
  // Each plugin is its own one-shot image that publishes its payload into the
  // shared `plugins` volume (like ui-build does for ui_assets). A server plugin
  // also loads its schema into the DB and registers itself in conf.d/plugins;
  // a UI plugin only drops its built bundle for the proxy to serve. server-pod
  // waits for them, then Acl.loadPlugins()/bootstrap.plugin pick them up.
  const sPlugins = cfg.plugins.server;
  const uPlugins = cfg.plugins.ui;
  const hasPlugins = sPlugins.length || uPlugins.length;

  const pluginVolumes = hasPlugins ? '  plugins: {}\n  confd_plugins: {}\n' : '';

  const serverPluginSvc = (name) =>
`  plugin-${name}:
    image: \${IMAGE_REGISTRY}/${name}:\${PLUGIN_TAG}
    networks: [drumee]
    depends_on:
      mariadb:
        condition: service_healthy
      schemas-populate:
        condition: service_completed_successfully
    env_file: [.env]
    environment:
      PLUGIN_NAME: "${name}"
      PLUGIN_ENDPOINT: "\${PLUGIN_ENDPOINT:-main}"
    volumes:
      - plugins:/srv/drumee/runtime/plugins
      - confd_plugins:/etc/drumee/conf.d/plugins
    restart: "no"
`;
  const uiPluginSvc = (name) =>
`  plugin-ui-${name}:
    image: \${IMAGE_REGISTRY}/${name}-ui:\${PLUGIN_TAG}
    environment:
      PLUGIN_NAME: "${name}"
      PLUGIN_ENDPOINT: "\${PLUGIN_ENDPOINT:-main}"
    volumes:
      - plugins:/srv/drumee/runtime/plugins
    restart: "no"
`;
  // Auto-detected plugin workers. A server plugin's image may carry a
  // `drumee.worker` label (set at build time from the plugin's OWN package.json,
  // drumee.worker) naming a long-running worker script. For each such plugin we
  // emit a "<name>-worker" service that runs that script FROM THE PLUGIN's OWN
  // IMAGE — which carries the plugin's own deps (e.g. restic). The renderer never
  // names a plugin and the generic server-pod image stays clean; loading the
  // plugin is enough for its worker to run. Best-effort: if the image is not
  // built / docker is unavailable, the plugin simply gets no worker.
  const pluginWorkerSvc = (name, script) =>
`  ${name}-worker:
    image: \${IMAGE_REGISTRY}/${name}:\${PLUGIN_TAG}
    restart: unless-stopped
    networks: [drumee]
    working_dir: /srv/drumee/runtime/plugins/server/\${PLUGIN_ENDPOINT:-main}/${name}
    entrypoint: ["node"]
    command: ["${script}"]
    depends_on:
      mariadb:
        condition: service_healthy
      redis:
        condition: service_started
      plugin-${name}:
        condition: service_completed_successfully
    env_file: [.env]
    environment:
      DRUMEE_DATA_DIR: /data
      WORKER_NAME: "${name}-worker-1"
    volumes:
      - \${DRUMEE_DATA_DIR}:/data
      - drumee_cred:/etc/drumee/credential
      - plugins:/srv/drumee/runtime/plugins
      - confd_plugins:/etc/drumee/conf.d/plugins
`;
  const workerOf = (name) => {
    try {
      return execSync(
        `docker image inspect --format '{{index .Config.Labels "drumee.worker"}}' ${cfg.images.registry}/${name}:${cfg.plugins.tag}`,
        { stdio: ['ignore', 'pipe', 'ignore'] },
      ).toString().trim();
    } catch { return ''; }
  };
  const pluginWorkerServices = sPlugins
    .map((name) => [name, workerOf(name)])
    .filter(([, w]) => w)
    .map(([name, w]) => pluginWorkerSvc(name, w))
    .join('');

  const pluginServices =
    sPlugins.map(serverPluginSvc).join('') + uPlugins.map(uiPluginSvc).join('') +
    pluginWorkerServices;

  // server-pod must wait for every plugin publisher and mount the plugin volumes.
  const podPluginDeps =
    sPlugins.map((n) => `      plugin-${n}:\n        condition: service_completed_successfully\n`).join('') +
    uPlugins.map((n) => `      plugin-ui-${n}:\n        condition: service_completed_successfully\n`).join('');
  const podPluginVolumes = hasPlugins
    ? '      - plugins:/srv/drumee/runtime/plugins\n      - confd_plugins:/etc/drumee/conf.d/plugins\n' : '';
  const proxyPluginVolume = uPlugins.length ? '      - plugins:/srv/plugins:ro\n' : '';

  return `# Generated by config/render.mjs from drumee.yaml — do not edit by hand.
# Reads values from the sibling .env. Bring up with:
#   docker compose --env-file .env up -d
# Optional services are gated by COMPOSE_PROFILES in .env.
networks:
  drumee: {}

volumes:
  caddy_data: {}
  caddy_config: {}
  ui_assets: {}
  static_assets: {}
  drumee_cred: {}
  infra_jitsi: {}
  infra_mail: {}
  infra_dns: {}
${pluginVolumes}
services:
  mariadb:
    image: mariadb:11
    restart: unless-stopped
    networks: [drumee]
    # Known root password so schemas-init can create DBs + grant the app user.
    # The app user (drumee-app) and the yp/utils/mailserver/template/trash DBs are
    # created by schemas-init, NOT here — Drumee is multi-DB with runtime CREATE
    # DATABASE, so the scoped MARIADB_USER/MARIADB_DATABASE model does not fit.
    environment:
      MARIADB_ROOT_PASSWORD: \${DB_ROOT_PASSWORD}
    volumes:
      - \${DRUMEE_DB_DIR}:/var/lib/mysql
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 10

  redis:
    image: redis:7
    restart: unless-stopped
    networks: [drumee]
    ${redisCmd}

  # Run-once: restore the database schema, then exit.
  schemas-init:
    image: \${IMAGE_REGISTRY}/schemas:\${SCHEMAS_TAG}
    networks: [drumee]
    depends_on:
      mariadb:
        condition: service_healthy
    env_file: [.env]
    restart: "no"

  # Run-once: publish the webpack-built UI assets into the shared volume.
  ui-build:
    image: \${IMAGE_REGISTRY}/ui-build:\${UI_TAG}
    volumes:
      - ui_assets:/ui-assets
    restart: "no"

  # Run-once: publish static assets (splash CSS, fonts, logo) into the shared
  # volume the proxy serves at /-/static and /-/images. Opt-in (needs the static
  # image built from the 'static' source repo): enable via COMPOSE_PROFILES=static.
  static:
    profiles: ["static"]
    image: \${IMAGE_REGISTRY}/static:\${STATIC_TAG}
    volumes:
      - static_assets:/static-assets
    restart: "no"

  # Run-once: stock the entity pool + create system accounts (nobody/guest/system)
  # + the RSA keypair (into the shared credential volume). Runs after the schema
  # is loaded and Redis is up.
  schemas-populate:
    image: \${IMAGE_REGISTRY}/schemas-populate:\${SERVER_TAG}
    networks: [drumee]
    depends_on:
      mariadb:
        condition: service_healthy
      redis:
        condition: service_started
      schemas-init:
        condition: service_completed_successfully
    env_file: [.env]
    # CREATE_ADMIN=1 also provisions the admin account + a password-reset link
    # (printed in this service's logs). Default off — first-run can use the wizard.
    environment:
      # DRUMEE_DATA_DIR is the HOST path in .env (used for the bind mount below);
      # inside every container the data tree is always /data. Pin it so the
      # env_file's host value can't leak in and make sysEnv() resolve mfs_dir to
      # a path that doesn't exist in the container.
      DRUMEE_DATA_DIR: /data
      CREATE_ADMIN: "\${CREATE_ADMIN:-0}"
      POOL_COUNT: "\${POOL_COUNT:-10}"
      ADMIN_PASSWORD: "\${ADMIN_PASSWORD:-}"
    volumes:
      - \${DRUMEE_DATA_DIR}:/data
      - drumee_cred:/etc/drumee/credential
    restart: "no"

  # Pool replenisher daemon: keeps the hub/drumate entity pool at a watermark so
  # signups/hub creation never hit EMPTY_FACTORY (upstream runs offline/factory
  # natively). Same image as schemas-populate; the entrypoint provides DB config.
  factory:
    image: \${IMAGE_REGISTRY}/schemas-populate:\${SERVER_TAG}
    command: ["node", "/srv/drumee/runtime/server/main/container-factory.js"]
    restart: unless-stopped
    networks: [drumee]
    depends_on:
      schemas-populate:
        condition: service_completed_successfully
    env_file: [.env]
    environment:
      DRUMEE_DATA_DIR: /data
      POOL_WATERMARK: "\${POOL_WATERMARK:-10}"
      POOL_INTERVAL: "\${POOL_INTERVAL:-30}"
    volumes:
      - \${DRUMEE_DATA_DIR}:/data
      - drumee_cred:/etc/drumee/credential
    # Override the HTTP healthcheck inherited from the server-pod base image:
    # the factory is a headless daemon with no listening port, so probe that the
    # daemon process is alive instead (node:20-slim has no pgrep — scan /proc).
    healthcheck:
      test: ["CMD-SHELL", "grep -slae container-factory /proc/[0-9]*/cmdline >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s

  server-pod:
    image: \${IMAGE_REGISTRY}/server-pod:\${SERVER_TAG}
    restart: unless-stopped
    networks: [drumee]
    depends_on:
      mariadb:
        condition: service_healthy
      redis:
        condition: service_started
      schemas-init:
        condition: service_completed_successfully
      schemas-populate:
        condition: service_completed_successfully
      ui-build:
        condition: service_completed_successfully
${podPluginDeps}    env_file: [.env]
    environment:
      DRUMEE_DATA_DIR: /data
    volumes:
      - \${DRUMEE_DATA_DIR}:/data
      - ui_assets:/srv/drumee/runtime/ui:ro
      - drumee_cred:/etc/drumee/credential
${podPluginVolumes}
  proxy:
    image: caddy:2
    restart: unless-stopped
    networks: [drumee]
    depends_on:
      server-pod:
        condition: service_started
    ports:
      - "80:80"
      - "443:443"
    env_file: [.env]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
      # UI bundles served as static files by the proxy (like nginx in prod),
      # NOT proxied to node. Published by ui-build into this shared volume.
      - ui_assets:/srv/ui:ro
      # Static assets (splash/fonts/logo); empty unless the 'static' profile ran.
      - static_assets:/srv/static:ro
      # UI plugin bundles served at /-/plugins/* (empty unless ui plugins declared).
${proxyPluginVolume}
${pluginServices}  # Run-once: render the canonical optional-service configs (Jitsi/Prosody/Coturn,
  # Postfix/OpenDKIM, BIND) with setup-infra's own engine into the infra_* volumes
  # the service containers below consume. Runs if any optional profile is active.
  infra-init:
    profiles: ["jitsi", "mail", "dns"]
    image: \${IMAGE_REGISTRY}/infra-init:\${SERVER_TAG}
    networks: [drumee]
    env_file: [.env]
    environment:
      INFRA_PARTS: "jitsi mail dns"
      WITH_JITSI: "1"
    volumes:
      - infra_jitsi:/out/jitsi
      - infra_mail:/out/mail
      - infra_dns:/out/dns
    restart: "no"

  jitsi:
    profiles: ["jitsi"]
    image: jitsi/web:stable
    restart: unless-stopped
    networks: [drumee]
    depends_on:
      infra-init:
        condition: service_completed_successfully
    # consumes infra_jitsi (conference.json + prosody/jicofo/jvb/web configs);
    # mount paths depend on the upstream image layout — see docs/infra-init.md TODO.
    volumes:
      - infra_jitsi:/drumee-infra:ro

  prosody:
    profiles: ["prosody"]
    image: prosody/prosody:latest
    restart: unless-stopped
    networks: [drumee]

  coturn:
    profiles: ["coturn"]
    image: coturn/coturn:latest
    restart: unless-stopped
    networks: [drumee]
`;
}

// ------------------------------------------------------------------------ main
function load(opts) {
  let text;
  try { text = readFileSync(opts.config, 'utf8'); }
  catch { die(`cannot read config: ${opts.config}`); }
  const cfg = applyDefaults(parseYaml(text));
  validate(cfg);
  return cfg;
}

function emit(content, out) {
  if (out) {
    mkdirSync(dirname(out) || '.', { recursive: true });
    writeFileSync(out, content);
    console.error(`wrote ${out}`);
  } else {
    process.stdout.write(content);
  }
}

const { command, opts } = parseArgs(process.argv.slice(2));

switch (command) {
  case 'validate': {
    const cfg = load(opts);
    console.error('config OK');
    console.log(JSON.stringify(cfg, null, 2));
    break;
  }
  case 'env': { emit(renderEnv(withSecrets(load(opts))), opts.out); break; }
  case 'compose': { emit(renderCompose(load(opts)), opts.out); break; }
  case 'caddyfile': { emit(renderCaddyfile(load(opts)), opts.out); break; }
  case 'debconf': { emit(renderDebconf(load(opts)), opts.out); break; }
  case 'all': {
    const cfg = withSecrets(load(opts));
    emit(renderEnv(cfg), join(opts.outDir, '.env'));
    chmodSync(join(opts.outDir, '.env'), 0o600);  // holds DB root credentials
    emit(renderCompose(cfg), join(opts.outDir, 'docker-compose.yml'));
    emit(renderCaddyfile(cfg), join(opts.outDir, 'Caddyfile'));
    emit(renderDebconf(cfg), join(opts.outDir, 'install.conf'));
    break;
  }
  default:
    die(`unknown command: ${command ?? '(none)'}\n` +
        'usage: render.mjs validate|env|compose|caddyfile|debconf|all [--config FILE] [--out FILE] [--out-dir DIR]');
}

function withSecrets(cfg) {
  const generated = fillSecrets(cfg);
  if (generated.length) {
    console.error(`note: generated random secrets for: ${generated.join(', ')}`);
    console.error('      pin them in drumee.yaml for reproducible re-renders.');
  }
  return cfg;
}
