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
    const trimmed = raw.trimStart();

    // -------- sequence item:  "- scalar"  or  "- key: value" (mapping item)
    if (trimmed === '-' || trimmed.startsWith('- ')) {
      while (stack.length && stack[stack.length - 1].indent >= indent) stack.pop();
      if (!stack.length) die(`line ${n + 1}: indentation error`);
      const frame = stack[stack.length - 1];
      let arr = frame.container;
      if (!Array.isArray(arr)) {
        // the parent key was created as an object placeholder — make it a list
        if (frame.key === undefined) die(`line ${n + 1}: unexpected list item`);
        arr = []; frame.parent[frame.key] = arr; frame.container = arr;
      }
      const itemStr = trimmed === '-' ? '' : trimmed.slice(2);
      const mm = itemStr.match(/^([\w-]+):\s*(.*)$/);
      if (mm) {                                   // "- key: value" → mapping item
        const itemObj = {}; arr.push(itemObj);
        stack.push({ indent, container: itemObj }); // continuation keys attach here
        const [, k, rhs] = mm;
        if (rhs === '') {
          const obj = {}; itemObj[k] = obj;
          stack.push({ indent: indent + 1, container: obj, key: k, parent: itemObj });
        } else itemObj[k] = parseScalar(rhs, n + 1);
      } else if (itemStr === '') {                // bare "-" → nested mapping follows
        const itemObj = {}; arr.push(itemObj);
        stack.push({ indent, container: itemObj });
      } else arr.push(parseScalar(itemStr, n + 1)); // "- scalar"
      continue;
    }

    // -------- mapping entry:  "key: value"  or  "key:" (nested block)
    const m = trimmed.match(/^([\w-]+):\s*(.*)$/);
    if (!m) die(`line ${n + 1}: expected "key: value", got: ${raw.trim()}`);
    const [, key, rhs] = m;
    while (stack.length && stack[stack.length - 1].indent >= indent) stack.pop();
    if (!stack.length) die(`line ${n + 1}: indentation error`);
    const parent = stack[stack.length - 1].container;
    if (Array.isArray(parent)) die(`line ${n + 1}: mapping key in a sequence`);
    if (rhs === '') {
      const obj = {};
      parent[key] = obj;
      stack.push({ indent, container: obj, key, parent });
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
  // `plugins` is a top-level list (not a section mapping) — carry it through so it
  // can be installed with `drumee[-ctl] plugin apply`. Validated lightly here.
  if ('plugins' in cfg) {
    if (!Array.isArray(cfg.plugins)) die('"plugins" must be a list');
    for (const p of cfg.plugins) {
      if (!p || typeof p !== 'object' || !p.source) die('each plugin needs at least a "source"');
    }
    out.plugins = cfg.plugins;
  }
  for (const section of Object.keys(cfg)) {
    if (section === 'plugins') continue;
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
  // Native-channel DNS-01 detail. setup-infra issues a wildcard, so there is no
  // HTTP-01 path at all; the only choice is how the DNS record gets written.
  if (!['nsupdate', 'api'].includes(cfg.tls.dns_challenge))
    errs.push(`tls.dns_challenge must be nsupdate or api (got ${cfg.tls.dns_challenge})`);
  if (cfg.tls.dns_challenge === 'api') {
    if (mode !== 'acme') errs.push('tls.dns_challenge=api only applies when tls.mode=acme');
    else if (!cfg.tls.acme_env_file)
      errs.push('tls.acme_env_file is required when tls.dns_challenge=api');
  }
  if (!['nginx', 'caddy'].includes(cfg.tls.terminator))
    errs.push(`tls.terminator must be nginx or caddy (got ${cfg.tls.terminator})`);
  if (cfg.tls.terminator === 'caddy') {
    // Caddy does its own ACME with a compiled-in DNS module, so it needs the
    // provider name — and the acme.sh knobs describe a mechanism it replaces.
    if (mode !== 'acme') errs.push('tls.terminator=caddy requires tls.mode=acme');
    if (!cfg.tls.dns_provider) errs.push('tls.dns_provider is required when tls.terminator=caddy');
    if (cfg.tls.dns_challenge === 'api' || cfg.tls.acme_env_file)
      errs.push('tls.dns_challenge/acme_env_file configure acme.sh — omit them with tls.terminator=caddy');
  } else if (cfg.tls.dns_provider) {
    errs.push('tls.dns_provider only applies when tls.terminator=caddy');
  }

  for (const [s, k] of [['database', 'port'], ['redis', 'port'], ['email', 'port']])
    if (cfg[s][k] != null && !Number.isInteger(cfg[s][k]))
      errs.push(`${s}.${k} must be an integer`);

  const wg = cfg.wireguard;
  for (const k of ['listen_port', 'reflector_port']) {
    if (!Number.isInteger(wg[k]) || wg[k] < 1 || wg[k] > 65535)
      errs.push(`wireguard.${k} must be an integer between 1 and 65535`);
  }
  if (wg.enabled) {
    if (!wg.coordinator) errs.push('wireguard.coordinator is required when wireguard.enabled');
    // Coordination exists to traverse NAT from the public Internet; on a
    // LAN-only instance it can never pair with anything.
    if (i.local_mode) errs.push('wireguard.enabled cannot be combined with instance.local_mode');
  }

  // The roles stack has no TLS terminator in front of the web role: nginx inside it
  // owns 80/443 and reads the certificates infra-init rendered. There is no caddy role,
  // so accepting terminator=caddy here would emit a stack with nothing on those ports —
  // the same failure the native postinst refuses for the same reason.
  if (cfg.images?.stack === 'roles' && cfg.tls?.terminator === 'caddy') {
    errs.push('images.stack=roles does not support tls.terminator=caddy — no caddy role image exists; the web role terminates TLS itself');
  }

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
  // WireGuard is not in optional_services (it is its own config section, shared
  // with the native channel) but it gates a compose service the same way.
  if (cfg.wireguard.enabled) profiles.push('wireguard');
  // Variable names intentionally match what setup-infra's wizard already writes,
  // so existing scripts consume this file unchanged.
  //
  // ---------------------------------------------------------------------------------
  // Which facts belong in this file depends on the stack, and the rule is not "what
  // compose needs" — it is: NO CONTAINER MAY LEARN A DRUMEE-SEMANTIC FACT FROM HERE.
  //
  // On the roles stack the deployment's settings reach the containers through the debconf
  // preseed and the package's own postinst (docs/channel-parity.md change 1). Leaving them
  // here as well would restore the second vocabulary that produced a BIND zone named
  // `auto`, "domain_name": "localhost" beside the real domain, and DRUMEE_HTTP_PORT
  // meaning two different things. So they are dropped.
  //
  // Three survive that look semantic and are not: DRUMEE_DOMAIN_NAME, DRUMEE_DATA_DIR and
  // DB_ROOT_PASSWORD are read by bin/drumee-ctl, which runs on the HOST and is not a
  // container — stripping them would break `drumee-ctl doctor` and `backup`. Keeping them
  // does not reintroduce the problem, because nothing inside a container reads them.
  //
  // The credentials (DB_*, REDIS_*, SMTP_*) also stay, and deliberately: in a compose
  // deployment the database is initialised from this file, so these are the authoritative
  // values and infra-init's generated ones are not. entrypoint/app writes them into
  // /etc/drumee/credential. Unifying that is change 3's remaining half.
  // ---------------------------------------------------------------------------------
  const roles = cfg.images?.stack === 'roles';
  const pairs = {
    DRUMEE_DOMAIN_NAME: cfg.instance.domain,
    ...(roles ? {} : {
    DRUMEE_DESCRIPTION: cfg.instance.description,
    LOCAL_MODE: cfg.instance.local_mode,
    ADMIN_EMAIL: cfg.instance.admin_email,
    // 'auto' is a SENTINEL meaning "detect at install time", not a value. renderDebconf
    // already strips it; renderEnv did not, and infra.js reads PUBLIC_IP4 straight from
    // the environment — so a stack rendered with the default produced a BIND zone file
    // literally named `auto` and a public vhost built from it. Observed in a running
    // stack. Empty means "not declared", which every consumer already handles.
    PUBLIC_IP4: cfg.network.ip4 === 'auto' ? '' : cfg.network.ip4,
    PUBLIC_IP6: cfg.network.ip6 === 'auto' ? '' : cfg.network.ip6,
    SERVICES: cfg.network.services.join(','),
    TLS_MODE: cfg.tls.mode,
    ACME_EMAIL_ACCOUNT: cfg.tls.acme_email ?? '',
    OWN_SSL: cfg.tls.mode === 'own',
    OWN_SSL_PATH: cfg.tls.own_cert_path ?? '',
    BACKUP_LOCATION: cfg.storage.backup_location ?? '',
    EXCHANGE_LOCATION: cfg.storage.exchange_location,
    }),
    // Bind-mount sources for the source stack, and read by bin/drumee-ctl on the host.
    DRUMEE_DATA_DIR: cfg.storage.data_dir,
    DRUMEE_DB_DIR: cfg.storage.db_dir,
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
    // Host ports the web role publishes. Same names the native channel uses, where they
    // move to 8080/8443 when drumee-caddy takes 80/443 — one vocabulary for both
    // channels rather than two.
    DRUMEE_HTTP_PORT: cfg.ports.http,
    DRUMEE_HTTPS_PORT: cfg.ports.https,
    // Consumed by the SOURCE stack's wireguard service entrypoint, which renders the same
    // conf.d/wireguard.json the native postinst writes. The roles stack has no wireguard
    // service, and if it grows one the values will come from the preseed like everything
    // else — wireguard_* keys are already in it.
    ...(roles ? {} : {
    WIREGUARD_ENABLED: cfg.wireguard.enabled,
    WIREGUARD_COORDINATOR: cfg.wireguard.coordinator ?? '',
    WIREGUARD_LISTEN_PORT: cfg.wireguard.listen_port,
    WIREGUARD_REFLECTOR_PORT: cfg.wireguard.reflector_port,
    }),
    IMAGE_REGISTRY: cfg.images.registry,
    // ONE tag for every role, not one per component. drumee-release pins the release
    // train and every role Depends on it at strict equality, so roles from two trains
    // cannot be assembled — a per-role tag would invite exactly the mix the anchor
    // exists to prevent. Read only by the roles stack.
    ROLES_TAG: cfg.versions.product,
    MARIADB_TAG: cfg.images.mariadb_tag,
    REDIS_TAG: cfg.images.redis_tag,
    // Per-component tags exist only because the source stack builds one image per
    // component. The roles stack has a single tag for the whole train, so these would be
    // dead keys there — and a dead key is one someone eventually wires up.
    ...(roles ? {} : {
    SERVER_TAG: cfg.versions.server ?? cfg.versions.product,
    UI_TAG: cfg.versions.ui ?? cfg.versions.product,
    SCHEMAS_TAG: cfg.versions.schemas ?? cfg.versions.product,
    STATIC_TAG: cfg.versions.static ?? cfg.versions.product,
    }),
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

// The debconf choice matching this config. Mirrors drumee-infra/tls_method:
// acme-dns-server (BIND9 here) | acme-dns-api (provider API) | own | self-signed.
function tlsMethod(cfg) {
  if (cfg.tls.mode === 'own') return 'own';
  if (cfg.tls.mode === 'self-signed') return 'self-signed';
  if (cfg.tls.terminator === 'caddy') return 'caddy';
  return cfg.tls.dns_challenge === 'api' ? 'acme-dns-api' : 'acme-dns-server';
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
    // TLS. tls_method is the question the operator sees; own_ssl is kept in the
    // preseed so a package predating tls_method still selects the same path.
    dc('tls_method', 'select', tlsMethod(cfg)),
    dc('own_ssl', 'boolean', cfg.tls.mode === 'own'),
    dc('own_ssl_path', 'string', cfg.tls.own_cert_path ?? ''),
    dc('acme_env_file', 'string', cfg.tls.acme_env_file ?? ''),
    // Caddy path. The DNS API token is deliberately absent: it is a secret, so it
    // is asked by debconf (password type) or preseeded separately by the operator
    // — never written into a rendered artifact.
    dc('caddy_domain', 'string', cfg.tls.terminator === 'caddy' ? cfg.instance.domain : ''),
    dc('caddy_dns_provider', 'string', cfg.tls.dns_provider ?? ''),
    // WireGuard peer coordination. Always preseeded, so an unattended install
    // never stops on the question. (The container channel reads the same values
    // from .env — see WIREGUARD_* in renderEnv.)
    dc('wireguard_enabled', 'boolean', cfg.wireguard.enabled),
    dc('wireguard_coordinator', 'string', cfg.wireguard.coordinator),
    dc('wireguard_listen_port', 'string', cfg.wireguard.listen_port),
    dc('wireguard_reflector_port', 'string', cfg.wireguard.reflector_port),
    // The ports nginx binds. In the preseed rather than only in .env because the container
    // channel takes its settings from here: without them infra-init rendered nginx on the
    // 80/443 default while compose published something else, and the web role answered on
    // neither port while reporting healthy.
    dc('http_port', 'string', cfg.ports.http),
    dc('https_port', 'string', cfg.ports.https),
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
	handle /-/svc/* {
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
    env_file: [.env]
    volumes:
      - \${DRUMEE_DATA_DIR}:/data
      - ui_assets:/srv/drumee/runtime/ui:ro
      - drumee_cred:/etc/drumee/credential
      # Server plugins — host-mounted so they persist across image upgrades and
      # are managed with: drumee-ctl plugin add|list|remove
      - ./plugins:/srv/drumee/runtime/plugins/server

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

  # WireGuard peer coordination — lets this instance be reached without opening a
  # port on the router. Gated by the 'wireguard' profile, which .env enables from
  # wireguard.enabled. Runs the SAME bootstrap.sh + agent.js the native package
  # ships (see deploy/docker/Dockerfile.wireguard).
  wireguard:
    profiles: ["wireguard"]
    image: \${IMAGE_REGISTRY}/wireguard:\${SERVER_TAG}
    restart: unless-stopped
    # wg0 has to be created in the HOST network namespace: the tunnel must reach
    # the ports the proxy publishes there, and the NAT mapping the agent probes
    # must be the host's own. network_mode and 'networks:' are mutually exclusive,
    # hence no drumee network here — the agent talks only to the coordinator.
    network_mode: host
    cap_add: [NET_ADMIN]
    # Requires the wireguard kernel module on the HOST: sudo modprobe wireguard.
    # Deliberately no depends_on: coordination is how the box becomes reachable
    # at all, so it should come up even when the app stack is still starting.
    env_file: [.env]
    volumes:
      # Persists the node keypair (generated on first start, never leaves here).
      - drumee_cred:/etc/drumee/credential

  # Run-once: render the canonical optional-service configs (Jitsi/Prosody/Coturn,
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

// --------------------------------------------------------------- compose (roles)
// The package-based stack of docs/distribution.md §2: one role per container, each
// installing ONE metapackage at an exact version, with dpkg resolving the rest.
//
// Selected by `images.stack: roles`. It is not yet the default because only two of the
// seven role images exist (web and infra) — emitting it by default would hand every
// existing caller a stack that cannot pull. The source-based branch above stays until
// the other five are built, which is criterion 1 of deploy/docker/DEPRECATED.md.
//
// Four differences from the source stack that are the whole point of the exercise:
//
//   * no ui-build. drumee-ui-pod already contains the webpack output, produced once
//     when the package was built. Nothing compiles in a running deployment.
//   * one tag for every role, not one per component. drumee-release pins the train and
//     every role Depends on it at strict equality, so two roles from different trains
//     cannot be assembled — a per-role tag would invite exactly that.
//   * configuration comes from a volume that infra-init renders, not from packages
//     configuring hosts. Consumers mount SUBPATHS of it read-only, so each role sees
//     only the part of the tree it needs and cannot rewrite it.
//   * mariadb and redis are the official images. mariadb:11.8 is what Trixie ships, so
//     the 130 tables and 645 routines are validated against one branch.
function renderComposeRoles(cfg) {
  const redisCmd = cfg.redis.password
    ? `command: ["redis-server", "--requirepass", "$\{REDIS_PASSWORD}"]` : 'command: ["redis-server"]';
  // Mount a subtree of the rendered configuration volume at its real path. Requires
  // Compose >= 2.26 / Engine >= 25 for `volume.subpath`; the alternative is an
  // entrypoint in every role that copies or symlinks, which is logic in five places
  // instead of a declaration in one.
  const conf = (target, sub) => `      - type: volume
        source: drumee_conf
        target: ${target}
        read_only: true
        volume:
          subpath: ${sub}`;
  return `# Generated by config/render.mjs from drumee.yaml — do not edit by hand.
# Package-based role stack (images.stack: roles). One role per container; each image
# installs a single drumee-role-* metapackage at an exact version.
#   docker compose --env-file .env up -d
networks:
  drumee: {}

volumes:
  # Rendered once by infra-init and read-only everywhere else. This is the only place
  # configuration is produced, which is what lets the roles carry no host state.
  drumee_conf: {}
  db_data: {}
  cache_data: {}
  mfs_data: {}
  # nginx's proxy cache. A named volume rather than the container filesystem so it
  # survives a restart and does not grow inside the image layer.
  web_cache: {}
  # The converter's scratch space. LibreOffice, ffmpeg and 7z all write large
  # intermediates, and a headless soffice additionally insists on a writable profile
  # directory; keeping that off the container filesystem means the role can run with a
  # read-only rootfs later without any of it moving.
  converter_tmp: {}
  # There is deliberately NO credential volume.
  #
  # There was one, mounted writable at /etc/drumee/credential so the app and schemas roles
  # could write db.json and redis.json from .env. Two problems, the second measured with a
  # two-volume mount test: it made two writers for one credential, and a mount REPLACES
  # what is underneath it — so the email.json and postfix.json infra-init rendered were
  # invisible to every role that mounted it.
  #
  # One writer now: infra.js renders db.json honouring DB_HOST/DB_USER/DB_PORT/DB_PASSWORD,
  # and the infra job writes redis.json. Everyone else reads the shared tree read-only.

services:
  # --- stateful services on their upstream images ----------------------------
  db:
    image: mariadb:\${MARIADB_TAG}
    restart: unless-stopped
    # An ALIAS from the configured hostname, not a renamed service. database.host is what
    # the application actually dials — it is written into /etc/drumee/credential/db.json
    # by the app entrypoint — and it defaults to 'mariadb'. The §2 service name is 'db',
    # so without this the app resolved nothing: measured as
    # "getaddrinfo ENOTFOUND redis" on the cache side, with the app crash-looping inside
    # a container that pm2 reported as running. (No backticks in comments inside this
    # template literal — one closes the string and breaks every render.mjs command.)
    #
    # An alias rather than a rename keeps both vocabularies true: the topology uses the
    # design's names and the deployment keeps whatever hostname its config declares.
    networks:
      drumee:
        aliases: ["\${DB_HOST}"]
    # The app user and the yp/utils/mailserver/template/trash databases are created by
    # the schemas role, not here: Drumee creates a database per entity at runtime, so
    # the scoped MARIADB_USER/MARIADB_DATABASE model does not fit.
    environment:
      MARIADB_ROOT_PASSWORD: \${DB_ROOT_PASSWORD}
    volumes:
      - db_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 10

  cache:
    image: redis:\${REDIS_TAG}
    restart: unless-stopped
    networks:
      drumee:
        aliases: ["\${REDIS_HOST}"]
    volumes:
      - cache_data:/data
    ${redisCmd}

  # --- run-once jobs ---------------------------------------------------------
  # Renders the configuration tree into drumee_conf and exits. Every other role waits
  # for it, because without it they have no configuration at all.
  #
  # Mounted read-WRITE at /out and it is the only service that is: everything else
  # mounts subpaths of the same volume read-only.
  infra-init:
    image: \${IMAGE_REGISTRY}/role-infra:\${ROLES_TAG}
    networks: [drumee]
    restart: "no"
    # Deliberately NO env_file. This job learns the deployment's SETTINGS from the preseed
    # below and from nothing else — that is the point of channel-parity change 1, and an
    # env_file here would quietly re-open the second channel for them to arrive by.
    #
    # The credentials are listed explicitly instead, which is a different category and not a
    # loophole: these are secrets shared with the official mariadb and redis images, which
    # compose initialises from the same .env, so .env is their authority. Putting them in
    # the preseed would also write them in plaintext into debconf's config.dat. infra.js
    # honours DB_* when rendering db.json; the entrypoint writes redis.json.
    environment:
      # Where the application tier is, for the nginx upstreams infra.js renders. Topology,
      # like DB_HOST — the deployment's own shape, not a Drumee setting — so it travels the
      # same narrow path. Without it the rendered nginx proxies to 127.0.0.1 and the web
      # role answers 502 while proxying to itself.
      APP_HOST: app
      DB_HOST: \${DB_HOST}
      DB_PORT: \${DB_PORT}
      DB_USER: \${DB_USER}
      DB_PASSWORD: \${DB_PASSWORD}
      REDIS_HOST: \${REDIS_HOST}
      REDIS_PORT: \${REDIS_PORT}
      REDIS_PASSWORD: \${REDIS_PASSWORD}
    volumes:
      - drumee_conf:/out
      # The DEBCONF PRESEED, which is how this job learns the deployment's settings — the
      # same file the native channel installs from (render.mjs debconf). It preseeds it and
      # runs dpkg-reconfigure drumee-infra, so both channels drive the same postinst,
      # the same bridge and the same renderers. See docs/channel-parity.md; the previous
      # arrangement hand-mapped .env onto infra.js flags and every container-side
      # configuration bug came from that second mapping.
      - ./install.conf:/etc/drumee/install.conf:ro

  # Schema restore, then migrations, as two ordered run-once jobs rather than one:
  # docs/distribution.md §6 requires migrate to be separately re-runnable, and an
  # upgrade runs it against a database schemas-init will never touch again.
  schemas-init:
    image: \${IMAGE_REGISTRY}/role-schemas:\${ROLES_TAG}
    networks: [drumee]
    restart: "no"
    command: ["init"]
    # DB_ROOT_PASSWORD only, and explicitly — creating the databases and granting the
    # application user is the one thing that needs root, and compose initialises the
    # mariadb container from this same value. Everything else this job needs it reads from
    # the rendered volume: the domain from drumee.sh, the application credentials from
    # db.json. No env_file, for the reason infra-init has none.
    environment:
      DB_ROOT_PASSWORD: \${DB_ROOT_PASSWORD}
    depends_on:
      db:
        condition: service_healthy
      infra-init:
        condition: service_completed_successfully
    # The config tree read-WRITE here, and the storage volume: this job provisions the
    # instance, which means creating the MFS roots and writing the RSA keypair. Every
    # long-running role still mounts the same tree read-only — provisioning is a job, and a
    # job that has to write is not the same as a service that must not.
    volumes:
      - type: volume
        source: drumee_conf
        target: /etc/drumee
        volume:
          subpath: etc/drumee
      - mfs_data:/data/mfs

  migrate:
    image: \${IMAGE_REGISTRY}/role-schemas:\${ROLES_TAG}
    networks: [drumee]
    restart: "no"
    command: ["migrate"]
    environment:
      DB_ROOT_PASSWORD: \${DB_ROOT_PASSWORD}
    depends_on:
      schemas-init:
        condition: service_completed_successfully
    volumes:
${conf('/etc/drumee', 'etc/drumee')}

  # --- long-running roles ----------------------------------------------------
  app:
    image: \${IMAGE_REGISTRY}/role-app:\${ROLES_TAG}
    restart: unless-stopped
    networks: [drumee]
    depends_on:
      cache:
        condition: service_started
      migrate:
        condition: service_completed_successfully
    env_file: [.env]
    volumes:
      - mfs_data:/data/mfs
${conf('/etc/drumee', 'etc/drumee')}
      # Plugins are host-mounted so they survive an image upgrade and stay managed by
      # drumee-plugin rather than baked into a layer.
      - ./plugins:/srv/drumee/runtime/plugins/server

  web:
    image: \${IMAGE_REGISTRY}/role-web:\${ROLES_TAG}
    restart: unless-stopped
    networks: [drumee]
    depends_on:
      app:
        condition: service_started
    # The SAME number on both sides, deliberately. DRUMEE_HTTP_PORT is the port
    # setup-infra renders into nginx's listen directive, so it is what nginx binds
    # INSIDE the container — mapping it to 80 published a port nothing was listening on,
    # and curl got connection-refused against a healthy container. Measured.
    #
    # (No backticks in this comment: it lives inside a JS template literal, and one
    # closed the string, which broke every render.mjs command until it was found.)
    #
    # One name, one meaning: the config says which port Drumee serves on, and the
    # container publishes exactly that.
    ports:
      - "\${DRUMEE_HTTP_PORT}:\${DRUMEE_HTTP_PORT}"
      - "\${DRUMEE_HTTPS_PORT}:\${DRUMEE_HTTPS_PORT}"
    env_file: [.env]
    volumes:
      - web_cache:/srv/drumee/cache
${conf('/etc/nginx/sites-enabled', 'etc/nginx/sites-enabled')}
${conf('/etc/drumee', 'etc/drumee')}

  # Deliberately separate, and not negotiable per §2: this is the only component that
  # parses untrusted documents, and it carries the heaviest dependencies in the
  # platform. File in, file out — no database credentials, no published port.
  #
  # It reaches the browser the same way every other progress report does, over the
  # Redis live-update channel, so it needs the cache service and nothing else. The
  # WebSocket sessions live in the app role, and a short-lived converter process could
  # not hold one open anyway.
  converter:
    # Profile-gated, and this is temporary rather than a change of mind about §2's
    # topology. The role is real and its toolchain self-tests, but HOW a job reaches it is
    # still a server-team question, so entrypoint/converter refuses to start until
    # DRUMEE_CONVERTER_CMD names a worker. Combined with restart: unless-stopped that is a
    # crash loop, measured: every deployment would ship a container retrying forever.
    # A container that cannot start is not a topology. Enable with:
    #   COMPOSE_PROFILES=converter  (and DRUMEE_CONVERTER_CMD set)
    profiles: ["converter"]
    image: \${IMAGE_REGISTRY}/role-converter:\${ROLES_TAG}
    restart: unless-stopped
    networks: [drumee]
    depends_on:
      cache:
        condition: service_started
      # Not for ordering alone: it mounts a subpath of the rendered tree, and a subpath
      # that does not exist yet fails the mount rather than starting empty.
      infra-init:
        condition: service_completed_successfully
    # NO env_file, deliberately. .env carries DB_PASSWORD, and handing it to this role
    # would undo the one property it exists for.
    environment:
      # server-essentials resolves its Redis credential from this directory. It is the
      # ONLY credential the converter can see: infra-init writes a scoped copy holding
      # redis.json and nothing else, because a volume subpath mounts directories and
      # there is no way to mount one file out of the shared credential dir.
      credential_dir: /etc/drumee/credential/converter
      DRUMEE_TMP_DIR: /data/tmp
    volumes:
      - mfs_data:/data/mfs
      - converter_tmp:/data/tmp
${conf('/etc/drumee/credential/converter', 'etc/drumee/credential/converter')}

  # --- optional roles --------------------------------------------------------
  # bind9 serving the zone infra-init rendered. Host networking because a nameserver
  # answering on udp/53 for the LAN must be reachable at the host's own address.
  dns:
    profiles: ["dns"]
    image: \${IMAGE_REGISTRY}/role-dns:\${ROLES_TAG}
    restart: unless-stopped
    network_mode: host
    cap_add: [NET_BIND_SERVICE]
    depends_on:
      infra-init:
        condition: service_completed_successfully
    # A SIDE path, not /etc/bind. bind9 ships /etc/bind/named.conf — the top-level file that
    # includes the rendered ones — and a mount replaces what is underneath it, so mounting
    # the volume there hid it. Mounting the three files individually is not an option
    # either: Docker's volume subpath mounts directories only. entrypoint/dns places them.
    volumes:
${conf('/etc/drumee/bind', 'etc/bind')}
${conf('/var/lib/bind', 'var/lib/bind')}

  mail:
    profiles: ["mail"]
    image: \${IMAGE_REGISTRY}/role-mail:\${ROLES_TAG}
    restart: unless-stopped
    networks: [drumee]
    ports:
      - "25:25"
      - "587:587"
    depends_on:
      infra-init:
        condition: service_completed_successfully
    volumes:
${conf('/etc/postfix', 'etc/postfix')}
${conf('/etc/opendkim', 'etc/opendkim')}
`;
}

// One place decides which stack is emitted, so `compose` and `all` cannot disagree —
// they did in an earlier draft, and a stack that differs depending on which command
// produced it is worse than either stack.
function composeFor(cfg) {
  return (cfg.images?.stack === 'roles') ? renderComposeRoles(cfg) : renderCompose(cfg);
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
  case 'compose': { const c = load(opts); emit(composeFor(c), opts.out); break; }
  case 'caddyfile': { emit(renderCaddyfile(load(opts)), opts.out); break; }
  case 'debconf': { emit(renderDebconf(load(opts)), opts.out); break; }
  case 'all': {
    const cfg = withSecrets(load(opts));
    emit(renderEnv(cfg), join(opts.outDir, '.env'));
    chmodSync(join(opts.outDir, '.env'), 0o600);  // holds DB root credentials
    emit(composeFor(cfg), join(opts.outDir, 'docker-compose.yml'));
    emit(renderCaddyfile(cfg), join(opts.outDir, 'Caddyfile'));
    emit(renderDebconf(cfg), join(opts.outDir, 'install.conf'));
    if (Array.isArray(cfg.plugins) && cfg.plugins.length) {
      // operator/installer applies it: drumee[-ctl] plugin apply plugins.json
      emit(JSON.stringify(cfg.plugins, null, 2) + '\n', join(opts.outDir, 'plugins.json'));
    }
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
