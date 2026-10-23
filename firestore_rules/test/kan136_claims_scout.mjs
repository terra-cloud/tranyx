#!/usr/bin/env node
/**
 * KAN-136 admin-claims dry-run / scout.
 * Loads compiled firestore.rules into the rules unit-testing harness and checks that
 * an auth context with `{ admin: true }` can create payout / fee_deduction txs
 * (the admin portal / CF path), while a normal user still needs the stopgap shape.
 *
 * Usage (from repo root, emulator up via npm test:rules or):
 *   cd firestore_rules/test && FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node kan136_claims_scout.mjs
 * Or from repo root: node tool/kan136_claims_scout.mjs (with emulator host set)
 *
 * Or: dart run tool/build_rules.dart && cd firestore_rules/test && npm run test:rules -- kan136
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '../..');
const RULES = resolve(ROOT, 'firestore.rules');
const PROJECT_ID = 'demo-tranyx-kan136-scout';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('Set FIRESTORE_EMULATOR_HOST (e.g. 127.0.0.1:8080) or run via firebase emulators:exec.');
  process.exit(2);
}

const NOW = Date.now();
const env = await initializeTestEnvironment({
  projectId: PROJECT_ID,
  firestore: { rules: readFileSync(RULES, 'utf8') },
});

await env.clearFirestore();
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await db.doc('config/app_config').set({
    commissionRate: 0.03, holdbackRate: 0.10, transactionFeeRate: 0.07, convenienceFeeRate: 0.03,
  });
  await db.doc('jobs/j1').set({
    creatorId: 'poster', acceptedApplicantId: 'worker', status: 'In Progress', pricingValue: 800,
    commissionRate: 0.03, holdbackRate: 0.10, transactionFeeRate: 0.07, convenienceFeeRate: 0.03,
  });
  await db.doc('users/worker').set({ uid: 'worker', tyxBalance: 0, email: 'w@gmail.com' });
});

const adminDb = env.authenticatedContext('ops', {
  email: 'ops@example.org', email_verified: true, admin: true,
}).firestore();
const userDb = env.authenticatedContext('worker', {
  email: 'worker@gmail.com', email_verified: true,
}).firestore();

const payout = {
  uid: 'worker', amount: 100, status: 'Successful', type: 'payout', createdAt: NOW,
  commissionRate: 0.03, holdbackRate: 0.10, baseAmount: 800,
};

let failed = 0;
try {
  await assertSucceeds(setDoc(doc(adminDb, 'transactions/payout_nyx_j1'), payout));
  console.log('PASS  adminClaim create payout_nyx_ (type=payout)');
} catch (e) {
  failed++;
  console.error('FAIL  adminClaim create payout_nyx_:', e.message || e);
}

try {
  // Fresh id so we don't collide with the admin write above
  await assertSucceeds(setDoc(doc(adminDb, 'transactions/fees_emp_j1'), {
    uid: 'poster', amount: 10, status: 'Successful', type: 'fee_deduction', createdAt: NOW,
    transactionFeeRate: 0.07, convenienceFeeRate: 0.03, baseAmount: 800,
  }));
  console.log('PASS  adminClaim create fees_emp_ (type=fee_deduction)');
} catch (e) {
  failed++;
  console.error('FAIL  adminClaim create fees_emp_:', e.message || e);
}

try {
  await assertFails(setDoc(doc(userDb, 'transactions/random_x'), {
    uid: 'worker', amount: 1, status: 'Successful', type: 'payout', createdAt: NOW,
  }));
  console.log('PASS  regular user denied free type=payout on non-job id');
} catch (e) {
  failed++;
  console.error('FAIL  regular user free payout deny:', e.message || e);
}

await env.cleanup();
console.log(failed ? `\nSCOUT FAILED (${failed})` : '\nSCOUT OK — admin claims path alive; free payout still denied');
process.exit(failed ? 1 : 0);
