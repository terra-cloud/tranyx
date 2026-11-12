#!/usr/bin/env node
/**
 * Dry-run by default. Moves exact listing address and coordinate fields from public
 * jobs, properties, and rentals onto {collection}/{id}/private/location and sets
 * addressPublic to "Brgy. *****, ****". Repeating the run skips listings that no
 * longer have those public fields.
 *
 * Emulator:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8189 node tool/migrate_listing_locations.mjs --project demo-tranyx
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8189 node tool/migrate_listing_locations.mjs --project demo-tranyx --apply
 *
 * Production write (service account required):
 *   node tool/migrate_listing_locations.mjs --project tranyx-app --allow-prod
 *   node tool/migrate_listing_locations.mjs --project tranyx-app --allow-prod --apply
 */
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { credentialPath, logWrite, refuseLive } from './live_target.mjs';

const require = createRequire(resolve(dirname(fileURLToPath(import.meta.url)), '../functions/package.json'));
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const gate = refuseLive(process.argv.slice(2));
if (gate.message) {
  console.error(gate.message);
  process.exit(2);
}

const fields = [
  'address', 'landmark', 'location', 'pickupAddress', 'pickupLat', 'pickupLng',
  'destinationAddress', 'destinationLat', 'destinationLng', 'latitude', 'longitude', 'lat', 'lng',
  'nyxianLat', 'nyxianLng', 'currentLocationLat', 'currentLocationLng', 'trackingLat', 'trackingLng',
  'routeHistory',
];
const mask = 'Brgy. *****, ****';
const projectId = gate.project || process.env.GCLOUD_PROJECT || 'demo-tranyx';

if (gate.host) {
  initializeApp({ projectId });
} else {
  const path = credentialPath();
  initializeApp({ credential: cert(JSON.parse(readFileSync(path, 'utf8'))), projectId });
}
const db = getFirestore();
const hits = [];
for (const collection of ['jobs', 'properties', 'rentals']) {
  const snap = await db.collection(collection).get();
  for (const doc of snap.docs) {
    const data = doc.data();
    const present = fields.filter((field) => data[field] !== undefined);
    if (present.length) hits.push({ collection, id: doc.id, fields: present });
  }
}
hits.sort((a, b) => `${a.collection}/${a.id}`.localeCompare(`${b.collection}/${b.id}`));
const audit = {
  at: Date.now(),
  apply: gate.apply,
  project: projectId,
  emulator: gate.host || null,
  count: hits.length,
  listings: hits,
};
console.log(JSON.stringify({ dryRun: !gate.apply, ...audit }, null, 2));
if (!gate.apply) process.exit(0);

let wrote = 0;
for (const hit of hits) {
  const path = `${hit.collection}/${hit.id}`;
  const ref = db.doc(path);
  const fresh = (await ref.get()).data() || {};
  const still = fields.filter((field) => fresh[field] !== undefined);
  if (!still.length) {
    logWrite({ op: 'skip', project: projectId, path, reason: 'already-migrated' });
    continue;
  }
  const location = {};
  const patch = { addressPublic: mask };
  for (const field of still) {
    location[field] = fresh[field];
    patch[field] = FieldValue.delete();
  }
  const privatePath = `${path}/private/location`;
  await db.doc(privatePath).set(location, { merge: true });
  logWrite({ op: 'set', project: projectId, path: privatePath, fields: still });
  await ref.update(patch);
  logWrite({ op: 'update', project: projectId, path, fields: ['addressPublic', ...still.map((field) => `delete:${field}`)] });
  wrote += 1;
}
if (wrote > 0) {
  await db.collection('purge_audit').doc(`listing_locations_${audit.at}`).set({ ...audit, wrote });
  logWrite({ op: 'set', project: projectId, path: `purge_audit/listing_locations_${audit.at}`, fields: ['wrote', 'count'] });
}
console.log(`Applied. Moved exact location fields on ${wrote} listing(s).`);
