#!/usr/bin/env node
/**
 * Sync Firebase Auth custom claims on a TARGET project from users flagged
 * isAdmin or isStaff in the admin portal project (default database: tranyx-admin).
 *
 * Dry-run is the default. It prints who would gain admin/staff claims and, only
 * with --revoke, who would lose them. This script does not run itself against
 * a live project.
 *
 * Credentials (never commit these files):
 *   ADMIN_GOOGLE_APPLICATION_CREDENTIALS
 *     Service account on tranyx-admin with Cloud Datastore User (read users).
 *   TARGET_GOOGLE_APPLICATION_CREDENTIALS
 *     Service account on the target project (tranyx-dev) with Firebase Auth Admin
 *     (firebaseauth.admin) so it can set custom user claims.
 *   If only GOOGLE_APPLICATION_CREDENTIALS is set, it is used for both, which
 *   only works when one account can read tranyx-admin and write Auth on the target.
 *
 *   node tool/sync_staff_claims.mjs --project tranyx-dev
 *   node tool/sync_staff_claims.mjs --project tranyx-dev --apply
 *   node tool/sync_staff_claims.mjs --project tranyx-dev --apply --revoke
 *
 * --revoke is opt-in. Without it, users who no longer have isAdmin/isStaff are
 * listed as "would revoke" only when --revoke is present in a dry run? No:
 * a dry run always lists would-revoke, but claims are removed only when both
 * --apply and --revoke are set.
 */
import { createRequire } from 'node:module';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';

const require = createRequire(resolve(dirname(fileURLToPath(import.meta.url)), '../functions/package.json'));
const admin = require('firebase-admin');

const args = process.argv.slice(2);
const apply = args.includes('--apply');
const revoke = args.includes('--revoke');
const projectFlag = args.indexOf('--project');
const targetProject = projectFlag >= 0 ? args[projectFlag + 1] : '';
const sourceProject = process.env.ADMIN_PROJECT_ID || 'tranyx-admin';

if (!targetProject || targetProject === 'tranyx-app' || targetProject === 'tranyx-uat') {
  console.error('Refusing. Pass --project <id>. tranyx-app and tranyx-uat are not targets of this tool.');
  process.exit(2);
}

function creds(envName) {
  const path = process.env[envName] || (!process.env.ADMIN_GOOGLE_APPLICATION_CREDENTIALS && !process.env.TARGET_GOOGLE_APPLICATION_CREDENTIALS
    ? process.env.GOOGLE_APPLICATION_CREDENTIALS
    : '');
  if (!path) return undefined;
  return JSON.parse(readFileSync(path, 'utf8'));
}

const sourceCred = creds('ADMIN_GOOGLE_APPLICATION_CREDENTIALS') || creds('GOOGLE_APPLICATION_CREDENTIALS');
const targetCred = creds('TARGET_GOOGLE_APPLICATION_CREDENTIALS') || creds('GOOGLE_APPLICATION_CREDENTIALS');
if (!sourceCred || !targetCred) {
  console.error('Missing credentials. Set ADMIN_GOOGLE_APPLICATION_CREDENTIALS and TARGET_GOOGLE_APPLICATION_CREDENTIALS.');
  process.exit(2);
}

const sourceApp = admin.initializeApp({ credential: admin.credential.cert(sourceCred), projectId: sourceProject }, 'source');
const targetApp = admin.initializeApp({ credential: admin.credential.cert(targetCred), projectId: targetProject }, 'target');
const sourceDb = sourceApp.firestore();
const targetAuth = targetApp.auth();

const snap = await sourceDb.collection('users').get();
const wanted = new Map();
for (const doc of snap.docs) {
  const data = doc.data();
  if (data.isAdmin === true || data.isStaff === true || data.isSuperAdmin === true) {
    const admin = data.isAdmin === true || data.isSuperAdmin === true;
    wanted.set(doc.id, admin ? { admin: true, role: 'admin' } : { admin: false, role: 'staff' });
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
      if (claims.admin !== next.admin || claims.role !== next.role) grant.push({ uid: user.uid, email: user.email || '', ...next });
      wanted.delete(user.uid);
    } else if (claims.admin === true || claims.role === 'admin' || claims.role === 'staff') {
      revokeList.push({ uid: user.uid, email: user.email || '' });
    }
  }
  pageToken = page.pageToken;
} while (pageToken);
for (const [uid, next] of wanted) grant.push({ uid, email: '', missingAuthUser: true, ...next });

console.log(JSON.stringify({
  dryRun: !apply,
  sourceProject,
  targetProject,
  grant,
  wouldRevoke: revokeList,
  revokeApplied: apply && revoke,
}, null, 2));

if (!apply) process.exit(0);
for (const row of grant) {
  if (row.missingAuthUser) continue;
  const user = await targetAuth.getUser(row.uid);
  await targetAuth.setCustomUserClaims(row.uid, { ...(user.customClaims || {}), admin: row.admin, role: row.role });
}
if (revoke) {
  for (const row of revokeList) {
    const user = await targetAuth.getUser(row.uid);
    const next = { ...(user.customClaims || {}) };
    delete next.admin;
    if (next.role === 'admin' || next.role === 'staff') delete next.role;
    await targetAuth.setCustomUserClaims(row.uid, next);
  }
}
console.log(`Applied grants=${grant.filter((row) => !row.missingAuthUser).length} revoke=${revoke ? revokeList.length : 0}`);
