// Follow-ups to Kelvin's review of 5549b3d: WR-06 allowlist, MON-T6 owner-only listing, jobs rule expression budget.
import { describe, it, expect } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, setDoc, updateDoc, where } from 'firebase/firestore';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { setupEnv, seed, user, adminClaim, userProfile, job, withdrawal } from './helpers.mjs';

setupEnv();
const NOW = 1761123600000;

describe('FU-WR: withdrawal owner updates are an allowlist', () => {
  it('FU-WR-01 [HIGH] owner cannot set agentId, proofImageUrl or solanaTxSignature', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'PENDING_CONFIRMATION' }) });
    const db = user('u1');
    for (const patch of [{ agentId: 'u1' }, { proofImageUrl: 'https://example.invalid/p.webp' }, { solanaTxSignature: 'sig' }])
      await assertFails(updateDoc(doc(db, 'withdrawal_requests/wr1'), patch));
  });
  it('FU-WR-02 [HIGH] owner cannot clear balanceDeducted without cancelling (status unchanged)', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'WAITING_FOR_AGENT' }) });
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { balanceDeducted: false, refundedAt: NOW }));
  });
  it('FU-WR-03 [MEDIUM] owner confirming receipt cannot stamp another uid as adminUid', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'PENDING_CONFIRMATION' }) });
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'APPROVED', adminUid: 'realAdmin' }));
  });
  it('FU-WR-04 [MUST-ALLOW] owner cancels a never-deducted request (balanceDeducted stays false, no refundedAt)', async () => {
    await seed({ 'withdrawalRequests/wr1': withdrawal('u1', { status: 'PENDING_REVIEW', balanceDeducted: false }) });
    await assertSucceeds(setDoc(doc(user('u1'), 'withdrawalRequests/wr1'), { ...withdrawal('u1', { status: 'PENDING_REVIEW', balanceDeducted: false }), status: 'CANCELLED', p2pStatus: 'CANCELLED', rejectionReason: 'typo', verifiedAt: NOW, updatedAt: NOW }));
  });
});

describe('FU-TX: transactions listing is owner-only; single-doc get unchanged', () => {
  const seedTx = () => seed({ 'transactions/tx_v': { uid: 'victim', type: 'deposit', amount: 1500, status: 'Successful' }, 'transactions/tx_u2': { uid: 'u2', type: 'deposit', amount: 10, status: 'Successful' } });
  it('FU-TX-01 [MUST-ALLOW] owner lists own transactions (getMyTransactions: where uid == caller)', async () => {
    await seedTx();
    await assertSucceeds(getDocs(query(collection(user('u2'), 'transactions'), where('uid', '==', 'u2'))));
  });
  it('FU-TX-02 [HIGH] signed-in user cannot query another user\'s transactions', async () => {
    await seedTx();
    await assertFails(getDocs(query(collection(user('u2'), 'transactions'), where('uid', '==', 'victim'))));
  });
  it('FU-TX-03 [MUST-ALLOW] admin lists all transactions (admin panel)', async () => {
    await seedTx();
    await assertSucceeds(getDocs(collection(adminClaim(), 'transactions')));
  });
  it('FU-TX-04 [MUST-ALLOW] signed-in get of a not-yet-written job tx id (existingTx / payout_nyx_* checks)', async () => {
    await assertSucceeds(getDoc(doc(user('poster'), 'transactions/payout_nyx_missing')));
  });
});

describe('FU-JOB: denied job updates stay under the 1,000-expression limit', () => {
  it('FU-JOB-01 no jobs update evaluation hits the expression limit (reads the emulator log)', async () => {
    await seed({ 'users/poster': userProfile('poster'), 'users/worker': userProfile('worker'), 'users/a2': userProfile('a2'),
      'jobs/j1': job('poster', { status: 'In Progress', acceptedApplicantId: 'worker' }), 'jobs/j2': job('poster'),
      'jobs/j3': job('poster', { status: 'Awaiting Acknowledgment', acceptedApplicantId: 'worker' }) });
    await assertFails(updateDoc(doc(user('worker'), 'jobs/j1'), { status: 'Completed', pricingValue: 99999 }));
    await assertFails(updateDoc(doc(user('a2'), 'jobs/j1'), { status: 'Cancelled' }));
    await assertFails(updateDoc(doc(user('a2'), 'jobs/j2'), { applicantCount: 2, title: 'pwned' }));
    await assertFails(updateDoc(doc(user('poster'), 'jobs/j3'), { status: 'Open', acceptedApplicantId: null, pricingValue: 10 }));
    const log = resolve(process.cwd(), 'firestore-debug.log'); // emulators:exec runs from firestore_rules/test
    expect(existsSync(log), `emulator log not found at ${log}`).toBe(true);
    await new Promise((r) => setTimeout(r, 300)); // let the emulator flush
    expect(readFileSync(log, 'utf8')).not.toMatch(/maximum of 1000 expressions/);
  });
});
