#!/usr/bin/env node
/**
 * Sync Firebase Auth custom claims on a target project from users flagged
 * isAdmin, isStaff, or isSuperAdmin in the admin portal project
 * (default: tranyx-admin-portal).
 *
 * Admin-portal users live in a separate Firebase project. Their uids are not
 * tranyx-app uids. Each flagged user is matched by email: the Firestore
 * document email, or admin-portal Auth (getUser) when the document has none.
 * Claims are granted only to the tranyx-app user returned by getUserByEmail.
 * People who cannot be matched are listed under `unmatched` and are not granted.
 *
 * Dry-run is the default. It lists who would gain admin/staff claims and who would
 * lose them. Claims are removed only when both --apply and --revoke are set.
 * Revocation looks at target-project users, not admin-portal uids.
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
 *   ADMIN_GOOGLE_APPLICATION_CREDENTIALS  read users and Auth on tranyx-admin-portal
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
import { DEFAULT_ADMIN_PROJECT_ID, normalizeEmail, planStaffClaims, staffClaimsFor } from './staff_claims_plan.mjs';

const require = createRequire(resolve(dirname(fileURLToPath(import.meta.url)), '../functions/package.json'));
const { initializeApp, cert } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

function isUserNotFound(error) {
  const code = error?.code || error?.errorInfo?.code;
  return code === 'auth/user-not-found';
}

async function listAllUsers(auth) {
  const users = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);
  return users;
}

export async function collectStaffClaimPlan({ sourceDb, sourceAuth, targetAuth }) {
  const snap = await sourceDb.collection('users').get();
  const flagged = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    const claims = staffClaimsFor(data);
    if (!claims) continue;
    flagged.push({
      sourceUid: doc.id,
      docEmail: typeof data.email === 'string' ? data.email : '',
      claims,
    });
  }

  const sourceAuthEmailByUid = new Map();
  for (const row of flagged) {
    if (normalizeEmail(row.docEmail)) continue;
    try {
      const user = await sourceAuth.getUser(row.sourceUid);
      sourceAuthEmailByUid.set(row.sourceUid, user.email || '');
    } catch (error) {
      if (isUserNotFound(error)) {
        sourceAuthEmailByUid.set(row.sourceUid, '');
        continue;
      }
      throw error;
    }
  }

  const targetByEmail = new Map();
  for (const row of flagged) {
    const email = normalizeEmail(row.docEmail) || normalizeEmail(sourceAuthEmailByUid.get(row.sourceUid));
    if (!email || targetByEmail.has(email)) continue;
    try {
      const user = await targetAuth.getUserByEmail(email);
      targetByEmail.set(email, {
        uid: user.uid,
        email: user.email || email,
        customClaims: user.customClaims || {},
      });
    } catch (error) {
      if (isUserNotFound(error)) continue;
      throw error;
    }
  }

  const listed = await listAllUsers(targetAuth);
  const targetUsers = listed.map((user) => ({
    uid: user.uid,
    email: user.email || '',
    customClaims: user.customClaims || {},
  }));
  const seen = new Set(targetUsers.map((user) => user.uid));
  for (const user of targetByEmail.values()) {
    if (seen.has(user.uid)) continue;
    targetUsers.push(user);
  }

  return planStaffClaims({ flagged, sourceAuthEmailByUid, targetByEmail, targetUsers });
}

export async function applyStaffClaimPlan({ targetAuth, plan, revoke, project }) {
  const applied = [];
  for (const row of plan.grant) {
    let user;
    try {
      user = await targetAuth.getUser(row.uid);
    } catch (error) {
      if (isUserNotFound(error)) {
        logWrite({ op: 'skip', project, uid: row.uid, email: row.email, reason: 'no-target-user' });
        continue;
      }
      throw error;
    }
    const current = user.customClaims || {};
    if (current.admin === row.admin && current.role === row.role) {
      logWrite({ op: 'skip', project, uid: user.uid, email: row.email, reason: 'claims-already-set', admin: row.admin, role: row.role });
      continue;
    }
    await targetAuth.setCustomUserClaims(user.uid, { ...current, admin: row.admin, role: row.role });
    logWrite({ op: 'setCustomUserClaims', project, uid: user.uid, email: row.email, admin: row.admin, role: row.role });
    applied.push(user.uid);
  }
  let revoked = 0;
  if (revoke) {
    for (const row of plan.wouldRevoke) {
      let user;
      try {
        user = await targetAuth.getUser(row.uid);
      } catch (error) {
        if (isUserNotFound(error)) {
          logWrite({ op: 'skip', project, uid: row.uid, email: row.email, reason: 'no-target-user' });
          continue;
        }
        throw error;
      }
      const next = { ...(user.customClaims || {}) };
      if (next.admin !== true && next.role !== 'admin' && next.role !== 'staff') {
        logWrite({ op: 'skip', project, uid: user.uid, email: row.email, reason: 'claims-already-clear' });
        continue;
      }
      delete next.admin;
      if (next.role === 'admin' || next.role === 'staff') delete next.role;
      await targetAuth.setCustomUserClaims(user.uid, next);
      logWrite({ op: 'revokeCustomUserClaims', project, uid: user.uid, email: row.email });
      revoked += 1;
    }
  }
  return { applied, revoked };
}

async function main() {
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

  const sourceProject = process.env.ADMIN_PROJECT_ID || DEFAULT_ADMIN_PROJECT_ID;
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
  const plan = await collectStaffClaimPlan({
    sourceDb: getFirestore(sourceApp),
    sourceAuth: getAuth(sourceApp),
    targetAuth: getAuth(targetApp),
  });

  console.log(JSON.stringify({
    dryRun: !gate.apply,
    sourceProject,
    targetProject: gate.project,
    allowProd: gate.allowProd,
    grant: plan.grant,
    unmatched: plan.unmatched,
    wouldRevoke: plan.wouldRevoke,
    revokeApplied: gate.apply && revoke,
  }, null, 2));

  if (!gate.apply) process.exit(0);

  const result = await applyStaffClaimPlan({
    targetAuth: getAuth(targetApp),
    plan,
    revoke,
    project: gate.project,
  });
  console.log(`Applied grants=${result.applied.length} revoke=${revoke ? result.revoked : 0}`);
}

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) await main();
