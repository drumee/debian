#!/usr/bin/env node
// Container populate — reuses setup-schemas' REAL bootstrap code (lib/organization)
// to create the system config + accounts + RSA keypair, adapted for containers:
//   * skips prepare()/create_user (the app user is created by schemas-init over TCP;
//     setup-schemas' version assumes a local socket as the OS user)
//   * skips Mfs.importContent/importTutorial (those fetch from content.drumee.com)
//
// Resolves @drumee/* from the server-pod image's node_modules, so it must run with
// SS_DIR placed under the server source tree (see Dockerfile.populate / the test).
//
// Env: DRUMEE_DOMAIN_NAME, ADMIN_EMAIL (+ /etc/drumee/drumee.json, credential/*.json)
const path = require('path');
const fs = require('fs');

const SS_DIR = process.env.SS_DIR || path.join(__dirname, 'setup-schemas');
const SERVER_MAIN = process.env.SERVER_MAIN || '/srv/drumee/runtime/server/main';
// GENESIS_DIR holds the schemas repo's templates/factory/{hub,drumate}.sql — the
// first pool entities are seeded from these (the running factory later self-maintains).
const GENESIS_DIR = process.env.GENESIS_DIR || '/factory';
// Enough to bootstrap the system accounts + admin (each regular user consumes a
// drumate + several hubs: wicket + internal/external shareboxes) with headroom.
// In production the offline factory daemon keeps the pool topped up to a watermark.
const POOL_COUNT = parseInt(process.env.POOL_COUNT || '10', 10);

const { randomBytes } = require('node:crypto');
const { Cache, subtleCrypto, Mariadb } = require('@drumee/server-essentials');
const Organization = require(path.join(SS_DIR, 'lib', 'organization'));

const CRYPTO_DIR = '/etc/drumee/credential/crypto';

async function rsaKeys() {
  fs.mkdirSync(CRYPTO_DIR, { recursive: true });
  if (fs.existsSync(path.join(CRYPTO_DIR, 'public.pem'))) {
    console.log('RSA keypair already present — skipping');
    return;
  }
  const { publicKey, privateKey } = await subtleCrypto.generateKeysPair();
  fs.writeFileSync(path.join(CRYPTO_DIR, 'public.pem'), publicKey);
  fs.writeFileSync(path.join(CRYPTO_DIR, 'private.pem'), privateKey);
  console.log('RSA keypair generated');
}

// Stock the entity pool from the schemas genesis templates so drumate_create's
// pickupEntity() has clean entities to draw from (otherwise: EMPTY_FACTORY).
// Reuses server-team's real offline/factory Schema (entity_create + load template
// + MFS root + pool_state='clean'). Needs: mariadb-client (DB_CLI), USER unset so
// the DB connection uses the app creds, and a writable data_dir for MFS roots.
async function stockFactory(yp) {
  const Schema = require(path.join(SERVER_MAIN, 'offline', 'factory', 'schema'));
  for (const type of ['drumate', 'hub']) {
    // Idempotent: top up to POOL_COUNT, don't blindly add (this one-shot re-runs
    // on every `compose up` after a config change/upgrade).
    const free = Number(await yp.await_func('pool_free', type));
    const need = Math.max(0, POOL_COUNT - free);
    if (!need) { console.log(`   '${type}' pool already at ${free} — skipping`); continue; }
    const script = path.join(GENESIS_DIR, `${type}.sql`);
    for (let i = 0; i < need; i++) {
      const s = new Schema({ type, script, folders: [], lang: 'en', verbose: 0, yp });
      await s.create_entity();
      s.destroy();
    }
    console.log(`   stocked ${need} '${type}' pool entities (now ${free + need})`);
  }
}

async function main() {
  new Cache();
  await Cache.load();

  const org = new Organization();
  console.log('==> populate() — sys_conf, domain, organisation, settings, vhosts, mail');
  await org.populate();
  console.log('==> stockFactory() — seed entity pool from genesis templates');
  await stockFactory(org.yp);
  console.log('==> createNobody()');
  await org.createNobody();
  console.log('==> createGuest()');
  await org.createGuest();
  console.log('==> createSystemUser()');
  const sys = await org.createSystemUser();
  if (process.env.CREATE_ADMIN === '1') {
    console.log('==> createAdmin()');
    const admin = await org.createAdmin(sys.media);
    // No-SMTP self-host can't receive the emailed reset link, so set a usable
    // password directly (ADMIN_PASSWORD if provided, else generated) via the
    // app's own set_password proc, and print the credentials.
    const email = process.env.ADMIN_EMAIL || admin.email;
    const password = process.env.ADMIN_PASSWORD || randomBytes(9).toString('base64url');
    await org.yp.await_proc('set_password', admin.id, password);
    console.log('\n========================================================');
    console.log('  ADMIN LOGIN');
    console.log(`  email:     ${email}`);
    console.log(`  password:  ${password}`);
    console.log(`  (reset link, if mail is configured: ${admin.reset_link})`);
    console.log('========================================================\n');
  }
  await rsaKeys();
  console.log('container-populate complete');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
