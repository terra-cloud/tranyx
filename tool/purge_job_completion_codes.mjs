#!/usr/bin/env node
/**
 * Dry-run by default. Deletes legacy jobs.completionCode and jobs.verificationCode.
 * A second run skips jobs that no longer have those fields. Values are never logged.
 *
 * Emulator:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8189 node tool/purge_job_completion_codes.mjs --project demo-tranyx
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8189 node tool/purge_job_completion_codes.mjs --project demo-tranyx --apply
 *
 * Production write (service account required):
 *   node tool/purge_job_completion_codes.mjs --project tranyx-app --allow-prod
 *   node tool/purge_job_completion_codes.mjs --project tranyx-app --allow-prod --apply
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

const projectId = gate.project || process.env.GCLOUD_PROJECT || 'demo-tranyx';
if (gate.host) {
  initializeApp({ projectId });
} else {
  initializeApp({ credential: cert(JSON.parse(readFileSync(credentialPath(), 'utf8'))), projectId });
}
const db = getFirestore();
const secretFields = ['completionCode', 'verificationCode'];
const snap = await db.collection('jobs').get();
const hits = [];
for (const doc of snap.docs) {
  const data = doc.data();
  const present = secretFields.filter((field) => data[field] !== undefined);
  if (present.length) hits.push({ id: doc.id, fields: present, status: data.status ?? null });
}
hits.sort((a, b) => a.id.localeCompare(b.id));
const audit = {
  at: Date.now(),
  apply: gate.apply,
  project: projectId,
  emulator: gate.host || null,
  count: hits.length,
  jobs: hits,
};
console.log(JSON.stringify({ dryRun: !gate.apply, ...audit }, null, 2));
if (!gate.apply) process.exit(0);

let wrote = 0;
for (const hit of hits) {
  const path = `jobs/${hit.id}`;
  const ref = db.doc(path);
  const fresh = (await ref.get()).data() || {};
  const still = secretFields.filter((field) => fresh[field] !== undefined);
  if (!still.length) {
    logWrite({ op: 'skip', project: projectId, path, reason: 'already-purged' });
    continue;
  }
  const patch = {};
  for (const field of still) patch[field] = FieldValue.delete();
  await ref.update(patch);
  logWrite({ op: 'update', project: projectId, path, fields: still.map((field) => `delete:${field}`) });
  wrote += 1;
}
if (wrote > 0) {
  await db.collection('purge_audit').doc(`job_codes_${audit.at}`).set({ ...audit, wrote });
  logWrite({ op: 'set', project: projectId, path: `purge_audit/job_codes_${audit.at}`, fields: ['wrote', 'count'] });
}
console.log(`Applied. Removed codes from ${wrote} job(s). Audit purge_audit/job_codes_${audit.at}`);
