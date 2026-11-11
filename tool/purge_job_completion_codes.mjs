#!/usr/bin/env node
/**
 * Dry-run by default. Deletes legacy jobs.completionCode and jobs.verificationCode
 * only when FIRESTORE_EMULATOR_HOST is set and --apply is passed.
 *
 * This script refuses to write a live project. Production leftovers stay until an
 * owner runs a reviewed Admin SDK purge against that project on purpose.
 * See functions/src/purge_job_codes.ts for the same guard, covered by
 * functions/test/purge_job_codes.spec.ts on the Functions emulator.
 *
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8189 node tool/purge_job_completion_codes.mjs
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8189 node tool/purge_job_completion_codes.mjs --apply
 */
import { createRequire } from 'node:module';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(resolve(dirname(fileURLToPath(import.meta.url)), '../functions/package.json'));
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const apply = process.argv.includes('--apply');
if (apply && !process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('REFUSING_LIVE_PURGE: set FIRESTORE_EMULATOR_HOST. This tool does not write live projects.');
  process.exit(2);
}
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('No FIRESTORE_EMULATOR_HOST. Refusing to read or write a live project. Pass the emulator host to dry-run.');
  process.exit(2);
}

const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'demo-tranyx';
initializeApp({ projectId });
const db = getFirestore();
const fields = ['completionCode', 'verificationCode'];
const snap = await db.collection('jobs').get();
const hits = [];
for (const doc of snap.docs) {
  const data = doc.data();
  const present = fields.filter((field) => data[field] !== undefined);
  if (present.length) hits.push({ id: doc.id, fields: present, status: data.status ?? null });
}
hits.sort((a, b) => a.id.localeCompare(b.id));
const audit = { at: Date.now(), apply, emulator: process.env.FIRESTORE_EMULATOR_HOST, count: hits.length, jobs: hits };
console.log(JSON.stringify({ dryRun: !apply, ...audit }, null, 2));
if (!apply) process.exit(0);
for (const hit of hits) {
  const patch = {};
  for (const field of hit.fields) patch[field] = FieldValue.delete();
  await db.doc(`jobs/${hit.id}`).update(patch);
}
await db.collection('purge_audit').doc(`job_codes_${audit.at}`).set(audit);
console.log(`Applied. Removed codes from ${hits.length} job(s). Audit purge_audit/job_codes_${audit.at}`);
