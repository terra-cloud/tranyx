#!/usr/bin/env node
/**
 * Sync Firebase Auth custom claims on a target project from users flagged
 * isAdmin, isStaff, or isSuperAdmin in the admin portal project (default: tranyx-admin).
 *
 * Dry-run is the default. It lists who would gain admin/staff claims and who would
 * lose them. Claims are removed only when both --apply and --revoke are set.
 *
 * A live write against production requires all of:
 *   --project tranyx-app --allow-prod --apply
 *   TARGET_GOOGLE_APPLICATION_CREDENTIALS or GOOGLE_APPLICATION_CREDENTIALS
 *
 *   node tool/sync_staff_claims.mjs --project tranyx-dev
 *   node tool/sync_staff_claims.mjs --project tranyx-app --allow-prod
 *   node tool/sync_staff_claims.mjs --project tranyx-app --allow-prod --apply
 *   node tool/sync_staff_claims.mjs --project tranyx-app --allow-prod --apply --revoke
 *
 * Credentials (never commit these files):
 *   ADMIN_GOOGLE_APPLICATION_CREDENTIALS  read users on tranyx-admin
 *   TARGET_GOOGLE_APPLICATION_CREDENTIALS Firebase Auth Admin on the target
 *
 * firebase-admin is not a root dependency. This script loads the modular
 * entry points from functions/node_modules (firebase-admin 14 has no
 * admin.credential). If that folder is missing, run: npm install --prefix functions
 */
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { credentialPath, logWrite, refuseLive } from './live_target.mjs';

const require = createRequire(resolve(dirname(fileURLToPath(import.meta.url)), '../functions/package.json'));
const { initializeApp, cert } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

const args = process.argv.slice(2);
const revoke = args.includes('--revoke');
const gate = refuseLive(args);
if (gate.message) {
  console.error(gate.message);
  process.exit(2);
}

function creds(envName) {
  const path = process.env[envName] || '';
  if (!path) return undefined;
  return JSON.parse(readFileSync(path, 'utf8'));
}

const sourceProject = process.env.ADMIN_PROJECT_ID || 'tranyx-admin';
const sourceCred = creds('ADMIN_GOOGLE_APPLICATION_CREDENTIALS') || creds('GOOGLE_APPLICATION_CREDENTIALS');
const targetCred = creds('TARGET_GOOGLE_APPLICATION_CREDENTIALS') || creds('GOOGLE_APPLICATION_CREDENTIALS');
if (!sourceCred || !targetCred) {
  console.error('Missing credentials. Set ADMIN_GOOGLE_APPLICATION_CREDENTIALS and TARGET_GOOGLE_APPLICATION_CREDENTIALS.');
  process.exit(2);
}
if (gate.apply && !credentialPath()) {
  console.error('Live --apply requires GOOGLE_APPLICATION_CREDENTIALS or TARGET_GOOGLE_APPLICATION_CREDENTIALS (service account JSON path).');
  process.exit(2);
}

const sourceApp = initializeApp({ credential: cert(sourceCred), projectId: sourceProject }, 'source');
const targetApp = initializeApp({ credential: cert(targetCred), projectId: gate.project }, 'target');
const sourceDb = getFirestore(sourceApp);
const targetAuth = getAuth(targetApp);

const snap = await sourceDb.collection('users').get();
const wanted = new Map();
for (const doc of snap.docs) {
  const data = doc.data();
  if (data.isAdmin === true || data.isStaff === true || data.isSuperAdmin === true) {
    const isAdmin = data.isAdmin === true || data.isSuperAdmin === true;
    wanted.set(doc.id, isAdmin ? { admin: true, role: 'admin' } : { admin: false, role: 'staff' });
  }
}

const grant = [];
const revokeList = [];
let pageToken;
do {
  const page = await targetAuth.listUsers(1000, pageToken);
  for (const user of page.users) {
    const next = wanted.get(user.uid);
    const claims = user.customClaims || {};
    if (next) {
      if (claims.admin !== next.admin || claims.role !== next.role) {
        grant.push({ uid: user.uid, email: user.email || '', ...next });
      }
      wanted.delete(user.uid);
    } else if (claims.admin === true || claims.role === 'admin' || claims.role === 'staff') {
      revokeList.push({ uid: user.uid, email: user.email || '' });
    }
  }
  pageToken = page.pageToken;
} while (pageToken);
for (const [uid, next] of wanted) grant.push({ uid, email: '', missingAuthUser: true, ...next });

console.log(JSON.stringify({
  dryRun: !gate.apply,
  sourceProject,
  targetProject: gate.project,
  allowProd: gate.allowProd,
  grant,
  wouldRevoke: revokeList,
  revokeApplied: gate.apply && revoke,
}, null, 2));

if (!gate.apply) process.exit(0);

const applied = [];
for (const row of grant) {
  if (row.missingAuthUser) {
    logWrite({ op: 'skip', project: gate.project, uid: row.uid, reason: 'missing-auth-user' });
    continue;
  }
  const user = await targetAuth.getUser(row.uid);
  const current = user.customClaims || {};
  if (current.admin === row.admin && current.role === row.role) {
    logWrite({ op: 'skip', project: gate.project, uid: row.uid, reason: 'claims-already-set', admin: row.admin, role: row.role });
    continue;
  }
  await targetAuth.setCustomUserClaims(row.uid, { ...current, admin: row.admin, role: row.role });
  logWrite({ op: 'setCustomUserClaims', project: gate.project, uid: row.uid, admin: row.admin, role: row.role });
  applied.push(row.uid);
}
if (revoke) {
  for (const row of revokeList) {
    const user = await targetAuth.getUser(row.uid);
    const next = { ...(user.customClaims || {}) };
    if (next.admin !== true && next.role !== 'admin' && next.role !== 'staff') {
      logWrite({ op: 'skip', project: gate.project, uid: row.uid, reason: 'claims-already-clear' });
      continue;
    }
    delete next.admin;
    if (next.role === 'admin' || next.role === 'staff') delete next.role;
    await targetAuth.setCustomUserClaims(row.uid, next);
    logWrite({ op: 'revokeCustomUserClaims', project: gate.project, uid: row.uid });
  }
}
console.log(`Applied grants=${applied.length} revoke=${revoke ? revokeList.length : 0}`);
