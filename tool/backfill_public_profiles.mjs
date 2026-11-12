#!/usr/bin/env node
/**
 * Dry-run by default. Copies the public card from users/{uid} onto
 * public_profiles/{uid}. Email, phone, wallet, balances, KYC, and idVerified
 * are not copied. A second run skips cards that already match.
 *
 * Emulator:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8189 node tool/backfill_public_profiles.mjs --project demo-tranyx
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8189 node tool/backfill_public_profiles.mjs --project demo-tranyx --apply
 *
 * Production write (service account required):
 *   node tool/backfill_public_profiles.mjs --project tranyx-app --allow-prod
 *   node tool/backfill_public_profiles.mjs --project tranyx-app --allow-prod --apply
 */
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { credentialPath, logWrite, refuseLive } from './live_target.mjs';

const require = createRequire(resolve(dirname(fileURLToPath(import.meta.url)), '../functions/package.json'));
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

export const PUBLIC_PROFILE_KEYS = [
  'name', 'displayName', 'photoUrl', 'profile_photo', 'headline', 'about',
  'accountType', 'skills', 'hourlyRate', 'businessName', 'industry',
  'createdAt', 'updatedAt', 'rating', 'ratingCount', 'isPremium',
];

export function projectPublicProfile(uid, user) {
  const out = { uid };
  for (const key of PUBLIC_PROFILE_KEYS) {
    if (user[key] !== undefined && user[key] !== null) out[key] = user[key];
  }
  return out;
}

function canon(value) {
  if (value && typeof value === 'object' && typeof value.toMillis === 'function') return value.toMillis();
  if (Array.isArray(value)) return value.map(canon);
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value).sort()) out[key] = canon(value[key]);
    return out;
  }
  return value ?? null;
}

export function sameCard(left, right) {
  return JSON.stringify(canon(left)) === JSON.stringify(canon(right));
}

export async function planAndApply(db, { apply, project, host }) {
  const users = await db.collection('users').get();
const plan = [];
for (const doc of users.docs) {
  const card = projectPublicProfile(doc.id, doc.data());
  const existing = await db.doc(`public_profiles/${doc.id}`).get();
  const current = existing.exists ? projectPublicProfile(doc.id, existing.data() || {}) : null;
  if (current && sameCard(current, card) && Object.keys(existing.data() || {}).length === Object.keys(card).length) {
    continue;
  }
  plan.push({ uid: doc.id, fields: Object.keys(card).sort() });
}
plan.sort((a, b) => a.uid.localeCompare(b.uid));
  const audit = {
    at: Date.now(),
    apply,
    project,
    emulator: host || null,
    count: plan.length,
    profiles: plan,
  };
  if (!apply) return { dryRun: true, ...audit, wrote: 0 };
  let wrote = 0;
  for (const hit of plan) {
    const user = await db.doc(`users/${hit.uid}`).get();
    if (!user.exists) {
      logWrite({ op: 'skip', project, path: `public_profiles/${hit.uid}`, reason: 'user-missing' });
      continue;
    }
    const card = projectPublicProfile(hit.uid, user.data() || {});
    const ref = db.doc(`public_profiles/${hit.uid}`);
    const existing = await ref.get();
    if (existing.exists) {
      const current = existing.data() || {};
      const projected = projectPublicProfile(hit.uid, current);
      if (sameCard(projected, card) && Object.keys(current).length === Object.keys(card).length) {
        logWrite({ op: 'skip', project, path: ref.path, reason: 'already-matches' });
        continue;
      }
    }
    await ref.set(card);
    logWrite({ op: 'set', project, path: ref.path, fields: Object.keys(card).sort() });
    wrote += 1;
  }
  if (wrote > 0) {
    await db.collection('purge_audit').doc(`public_profiles_${audit.at}`).set({ ...audit, wrote });
    logWrite({ op: 'set', project, path: `purge_audit/public_profiles_${audit.at}`, fields: ['wrote', 'count'] });
  }
  return { dryRun: false, ...audit, wrote };
}

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
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
  const result = await planAndApply(getFirestore(), {
    apply: gate.apply,
    project: projectId,
    host: gate.host,
  });
  console.log(JSON.stringify({ dryRun: result.dryRun, ...result }, null, 2));
  if (result.dryRun) process.exit(0);
  console.log(`Applied. Wrote ${result.wrote} public profile(s).`);
}
