#!/usr/bin/env node
/**
 * Dry-run by default. Moves exact listing address and coordinate fields from public
 * jobs, properties, and rentals onto {collection}/{id}/private/location and sets
 * addressPublic to "Brgy. *****, ****".
 *
 * Refuses to write unless FIRESTORE_EMULATOR_HOST is set and --apply is passed.
 * Do not point this at tranyx-dev, tranyx-uat, or tranyx-app.
 *
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8189 node tool/migrate_listing_locations.mjs
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8189 node tool/migrate_listing_locations.mjs --apply
 */
import { createRequire } from 'node:module';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(resolve(dirname(fileURLToPath(import.meta.url)), '../functions/package.json'));
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const apply = process.argv.includes('--apply');
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('REFUSING_LIVE_MIGRATION: set FIRESTORE_EMULATOR_HOST. This tool does not write live projects.');
  process.exit(2);
}
if (apply && !process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('REFUSING_LIVE_MIGRATION: --apply is emulator-only.');
  process.exit(2);
}

const fields = [
  'address', 'landmark', 'location', 'pickupAddress', 'pickupLat', 'pickupLng',
  'destinationAddress', 'destinationLat', 'destinationLng', 'latitude', 'longitude', 'lat', 'lng',
  'nyxianLat', 'nyxianLng', 'currentLocationLat', 'currentLocationLng', 'trackingLat', 'trackingLng',
  'routeHistory',
];
const mask = 'Brgy. *****, ****';
initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-tranyx' });
const db = getFirestore();
const hits = [];
for (const collection of ['jobs', 'properties', 'rentals']) {
  const snap = await db.collection(collection).get();
  for (const doc of snap.docs) {
    const data = doc.data();
    const present = fields.filter((field) => data[field] !== undefined);
    if (present.length) hits.push({ collection, id: doc.id, fields: present, data });
  }
}
console.log(JSON.stringify({ dryRun: !apply, count: hits.length, listings: hits.map(({ collection, id, fields: f }) => ({ collection, id, fields: f })) }, null, 2));
if (!apply) process.exit(0);
for (const hit of hits) {
  const location = {};
  const patch = { addressPublic: mask };
  for (const field of hit.fields) {
    location[field] = hit.data[field];
    patch[field] = FieldValue.delete();
  }
  await db.doc(`${hit.collection}/${hit.id}/private/location`).set(location, { merge: true });
  await db.doc(`${hit.collection}/${hit.id}`).update(patch);
}
console.log(`Applied. Moved exact location fields on ${hits.length} listing(s).`);
