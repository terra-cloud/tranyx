// Must-allow regressions for the phase-1 rules fixes (fix/firestore-rules-phase1, KAN-128).
// Each models a real client write/read that the tightened rules must keep working; file:line points at the caller.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { setupEnv, seed, user, adminClaim, userProfile, job, withdrawal } from './helpers.mjs';

setupEnv();
const NOW = 1761123600000;

describe('P1-WR: owner withdrawal flows that stay allowed', () => {
  for (const from of ['WAITING_FOR_AGENT', 'PENDING_REVIEW', 'PENDING']) {
    it(`P1-WR-01-${from} [MUST-ALLOW] owner cancels own ${from} request (web firebase_service.dart:7922 full-doc payload)`, async () => {
      await seed({ 'users/u1': userProfile('u1'), 'withdrawal_requests/wr1': withdrawal('u1', { status: from }), 'withdrawalRequests/wr1': withdrawal('u1', { status: from }) });
      const db = user('u1');
      for (const col of ['withdrawal_requests', 'withdrawalRequests'])
        await assertSucceeds(setDoc(doc(db, `${col}/wr1`), { ...withdrawal('u1', { status: from }), status: 'CANCELLED', p2pStatus: 'CANCELLED', balanceDeducted: false, refundedAt: NOW, verifiedAt: NOW, updatedAt: NOW }));
    });
  }
  it('P1-WR-02 [MUST-ALLOW] owner cancels via mobile merge payload (transit_repository.dart:3518)', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'WAITING_FOR_AGENT' }) });
    await assertSucceeds(setDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'CANCELLED', rejectionReason: 'changed mind', verifiedAt: NOW }, { merge: true }));
  });
  it('P1-WR-03 [MUST-ALLOW] owner confirms receipt once agent sent proof (PENDING_CONFIRMATION -> APPROVED; firebase_service.dart:7844, transit_repository.dart:3546)', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'PENDING_CONFIRMATION' }), 'withdrawalRequests/wr1': withdrawal('u1', { status: 'PENDING_CONFIRMATION' }) });
    const db = user('u1');
    await assertSucceeds(setDoc(doc(db, 'withdrawal_requests/wr1'), { ...withdrawal('u1', { status: 'PENDING_CONFIRMATION' }), status: 'APPROVED', p2pStatus: 'COMPLETED', adminUid: 'u1', verifiedAt: NOW, updatedAt: NOW }));
    await assertSucceeds(setDoc(doc(db, 'withdrawalRequests/wr1'), { status: 'APPROVED', adminUid: 'u1', verifiedAt: NOW }, { merge: true }));
  });
  it('P1-WR-04 [HIGH] owner cannot cancel+refund after an agent claimed it (AWAITING_AGENT_PAYMENT)', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'AWAITING_AGENT_PAYMENT', agentId: 'agent1' }) });
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'CANCELLED' }));
  });
  it('P1-WR-05 [HIGH] owner cannot re-point payout account or hand the request to another uid', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { accountNumber: '09171234567' }) });
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { accountNumber: '09998887777' }));
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { uid: 'u2', userId: 'u2' }));
  });
  it('P1-WR-06 [MUST-ALLOW] admin/agent claims, sends proof and rejects (agentClaimP2pWithdrawal, submitWithdrawalProof, rejectP2pWithdrawalOrder)', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1') });
    const db = adminClaim();
    await assertSucceeds(updateDoc(doc(db, 'withdrawal_requests/wr1'), { status: 'AWAITING_AGENT_PAYMENT', agentId: 'realAdmin', claimedAt: NOW }));
    await assertSucceeds(updateDoc(doc(db, 'withdrawal_requests/wr1'), { status: 'PENDING_CONFIRMATION', proofImageUrl: 'https://example.invalid/p.webp' }));
    await assertSucceeds(updateDoc(doc(db, 'withdrawal_requests/wr1'), { status: 'REJECTED', amount: 500 }));
  });
});

describe('P1-MON: legacy money + reference collections (admin panel only writes)', () => {
  const cols = ['withdrawals', 'cashout_requests', 'deposits', 'deposit_references', 'claimed_references', 'claimedReferences', 'claimed_p2p_references'];
  const rec = { uid: 'u1', userId: 'u1', amount: 1500, referenceNumber: 'GC-8812345', status: 'PENDING', createdAt: NOW };
  for (const col of cols) {
    it(`P1-MON-01-${col} [MUST-ALLOW] owner reads own ${col} doc; admin reads and writes (admin panel withdrawals/deposits/subscriptions pages)`, async () => {
      await seed({ [`${col}/r1`]: rec });
      await assertSucceeds(getDoc(doc(user('u1'), `${col}/r1`)));
      await assertSucceeds(getDoc(doc(adminClaim(), `${col}/r1`)));
      await assertSucceeds(setDoc(doc(adminClaim(), `${col}/r2`), { ...rec, approvedBy: 'realAdmin' }));
      await assertSucceeds(setDoc(doc(adminClaim(), `${col}/r1`), { status: 'APPROVED' }, { merge: true }));
    });
    it(`P1-MON-02-${col} [HIGH] ordinary user cannot create a ${col} doc, even for themselves`, async () => {
      await assertFails(setDoc(doc(user('u1'), `${col}/new1`), rec));
    });
  }
});

describe('P1-SUB: subscriptions + transactions', () => {
  const sub = { uid: 'u1', userId: 'u1', userName: 'User u1', plan: 'monthly', amount: 299, status: 'PENDING_VERIFICATION', method: 'GCash', referenceNumber: 'GC-1', createdAt: NOW, txId: 'tx1' };
  it('P1-SUB-01 [MUST-ALLOW] owner creates own subscriptions doc and reads it back (tranyx_app.dart:3632)', async () => {
    const db = user('u1');
    await assertSucceeds(setDoc(doc(db, 'subscriptions/tx1'), sub));
    await assertSucceeds(getDoc(doc(db, 'subscriptions/tx1')));
  });
  it('P1-SUB-02 [HIGH] user cannot create a subscriptions doc for another uid', async () => {
    await assertFails(setDoc(doc(user('u2'), 'subscriptions/tx9'), sub));
  });
  it('P1-SUB-03 [MUST-ALLOW] admin reads and verifies subscriptions (admin panel subscriptions.dart)', async () => {
    await seed({ 'subscriptions/tx1': sub });
    await assertSucceeds(getDoc(doc(adminClaim(), 'subscriptions/tx1')));
    await assertSucceeds(updateDoc(doc(adminClaim(), 'subscriptions/tx1'), { status: 'VERIFIED' }));
  });
  it('P1-TX-01 [MUST-ALLOW] owner records own pending subscription tx and later updates it (tranyx_app.dart:3612)', async () => {
    const db = user('u1');
    await seed({ 'users/u1': userProfile('u1') });
    await assertSucceeds(setDoc(doc(db, 'transactions/tx1'), { uid: 'u1', amount: 299, status: 'Pending', type: 'subscription', kind: 'subscription', createdAt: NOW }));
    await assertSucceeds(updateDoc(doc(db, 'transactions/tx1'), { receiptUrl: 'https://example.invalid/r.webp' }));
  });
  it('P1-TX-02 [MUST-ALLOW] signed-in employer reads the worker payout tx doc (tranyx_app.dart:5183 getDocument)', async () => {
    // The real call runs on a loaded job, so the job doc (poster hired worker) exists.
    await seed({ 'jobs/j1': job('poster', { status: 'In Progress', acceptedApplicantId: 'worker' }), 'transactions/payout_nyx_j1': { uid: 'worker', type: 'payout', amount: 800, status: 'Successful' } });
    await assertSucceeds(getDoc(doc(user('poster'), 'transactions/payout_nyx_j1')));
  });
  it('P1-TX-03 [MUST-ALLOW] admin marks a subscription tx Successful (admin panel subscriptions.dart:494)', async () => {
    await seed({ 'transactions/tx2': { uid: 'victim', type: 'subscription', amount: 299, status: 'Pending' } });
    await assertSucceeds(updateDoc(doc(adminClaim(), 'transactions/tx2'), { status: 'Successful', verifiedAt: NOW }));
  });
});

describe('P1-USR: premium fields', () => {
  it('P1-USR-01 [MUST-ALLOW] owner expires own subscription (tranyx_app.dart:1664 checkAndExpireSubscription)', async () => {
    await seed({ 'users/u1': userProfile('u1', { isPremium: true, premiumUntil: 1, accountType: 'hybrid' }) });
    await assertSucceeds(setDoc(doc(user('u1'), 'users/u1'), userProfile('u1', { isPremium: false, accountType: 'nyxian', premiumUntil: null })));
  });
  it('P1-USR-02 [MUST-ALLOW] owner records pendingSubscription (tranyx_app.dart:3606)', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    await assertSucceeds(updateDoc(doc(user('u1'), 'users/u1'), { pendingSubscription: { plan: 'monthly', amount: 299, txId: 'tx1' }, updatedAt: NOW }));
  });
  it('P1-USR-03 [MUST-ALLOW] admin activates another user\'s premium (approveCashSubscription / admin panel)', async () => {
    await seed({ 'users/victim': userProfile('victim') });
    await assertSucceeds(updateDoc(doc(adminClaim(), 'users/victim'), { isPremium: true, premiumUntil: NOW + 30 * 86400000, accountType: 'hybrid', subscriptionStatus: 'active', pendingSubscription: null }));
  });
});

describe('P1-CFG: config docs', () => {
  it('P1-CFG-01 [MUST-ALLOW] admin reads config/imgbb (admin panel imgbb_service.dart:21)', async () => {
    await seed({ 'config/imgbb': { apiKey: 'FIXTURE_NOT_A_SECRET' } });
    await assertSucceeds(getDoc(doc(adminClaim(), 'config/imgbb')));
  });
});

describe('P1-JOB: split jobs update rule keeps every action', () => {
  const hired = (extra = {}) => job('poster', { status: 'Awaiting Acknowledgment', acceptedApplicantId: 'worker', ...extra });
  const prep = (j) => seed({ 'users/poster': userProfile('poster'), 'users/worker': userProfile('worker'), 'users/u2': userProfile('u2'), 'jobs/j1': j });
  it('P1-JOB-1b [MUST-ALLOW] employer re-opens an unacknowledged job', async () => {
    await prep(hired());
    await assertSucceeds(updateDoc(doc(user('poster'), 'jobs/j1'), { status: 'Open', acceptedApplicantId: null, acceptedApplicantName: null, acknowledgmentStatus: 'expired', updatedAt: NOW }));
  });
  it('P1-JOB-1c [MUST-ALLOW] employer rates a completed job', async () => {
    await prep(hired({ status: 'Completed' }));
    await assertSucceeds(updateDoc(doc(user('poster'), 'jobs/j1'), { employerRated: true }));
  });
  it('P1-JOB-1d [MUST-ALLOW] employer marks a stalled job Abandoned', async () => {
    await prep(hired({ status: 'In Progress' }));
    await assertSucceeds(updateDoc(doc(user('poster'), 'jobs/j1'), { status: 'Abandoned', abandonedAt: NOW, abandonReason: 'no show', updatedAt: NOW }));
  });
  it('P1-JOB-1e [MUST-ALLOW] worker raises a dispute; stranger cannot', async () => {
    await prep(hired({ status: 'In Progress' }));
    await assertSucceeds(updateDoc(doc(user('worker'), 'jobs/j1'), { status: 'Disputed', disputeId: 'd1', disputedAt: NOW, disputedBy: 'worker', updatedAt: NOW }));
    await assertFails(updateDoc(doc(user('u2'), 'jobs/j1'), { status: 'Disputed', disputeId: 'd2' }));
  });
  it('P1-JOB-act [MUST-ALLOW] participant touches lastActivityAt', async () => {
    await prep(hired({ status: 'In Progress' }));
    await assertSucceeds(updateDoc(doc(user('worker'), 'jobs/j1'), { lastActivityAt: NOW }));
  });
  it('P1-JOB-2 [MUST-ALLOW] worker completes the job; cannot touch pricing', async () => {
    await prep(hired({ status: 'In Progress' }));
    await assertSucceeds(updateDoc(doc(user('worker'), 'jobs/j1'), { status: 'Completed', receiptUrl: 'https://example.invalid/r.webp', updatedAt: NOW }));
    await assertFails(updateDoc(doc(user('worker'), 'jobs/j1'), { pricingValue: 99999 }));
  });
  it('P1-JOB-2b [MUST-ALLOW] participant records the SLA reminder', async () => {
    await prep(hired());
    await assertSucceeds(updateDoc(doc(user('poster'), 'jobs/j1'), { acknowledgmentReminderSent: true, updatedAt: NOW }));
  });
  it('P1-JOB-4 [MUST-ALLOW] admin can update any job field', async () => {
    await prep(hired({ status: 'In Progress' }));
    await assertSucceeds(updateDoc(doc(adminClaim(), 'jobs/j1'), { status: 'Cancelled', adminNote: 'refunded' }));
  });
});
