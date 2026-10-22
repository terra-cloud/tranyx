// Added Oct 22 during review of Saga's 6aa1a41 / 9d13fd7: withdrawal allowlist edges and transactions get-by-id enumeration.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { setupEnv, seed, user, guest, userProfile, job, property, withdrawal } from './helpers.mjs';

setupEnv();
const NOW = 1761123600000;

describe('WR2: withdrawal owner allowlist edges', () => {
  for (const from of ['Successful', 'REJECTED', 'APPROVED', 'AWAITING_AGENT_PAYMENT', 'PENDING_CONFIRMATION', 'CANCELLED']) {
    it(`WR2-01-${from} [CRITICAL] owner cannot cancel+refund a ${from} request`, async () => {
      await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: from, balanceDeducted: true }) });
      await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'CANCELLED', balanceDeducted: false, refundedAt: NOW }));
    });
  }
  it('WR2-02 [CRITICAL] owner cannot change amount, cryptoAmount or destinationWallet even inside a legit cancel', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'PENDING' }) });
    const db = user('u1');
    for (const extra of [{ amount: 1 }, { cryptoAmount: 999 }, { destinationWallet: 'AttackerWa11et1111111111111111111111111111111' }])
      await assertFails(updateDoc(doc(db, 'withdrawal_requests/wr1'), { status: 'CANCELLED', ...extra }));
  });
  it('WR2-03 [CRITICAL] owner cannot set balanceDeducted:true (re-arm refund) on any status', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'PENDING', balanceDeducted: false }) });
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'CANCELLED', balanceDeducted: true }));
  });
  it('WR2-04 [HIGH] owner cannot jump PENDING_REVIEW -> APPROVED/Successful', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'PENDING_REVIEW' }) });
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'APPROVED' }));
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'Successful' }));
  });
  it('WR2-05 [LOW] owner cannot rewrite p2pStatus/rejectionReason/verifiedAt without a status change', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'WAITING_FOR_AGENT', p2pStatus: 'WAITING' }) });
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { p2pStatus: 'COMPLETED', verifiedAt: NOW }));
  });
});

describe('TXE: transactions get-by-id with predictable ids (tranyx_app.dart payout_nyx_/fees_emp_<jobId>, firebase_service.dart refund_prop_<propertyId>, p2p_with_<withdraw_<ms>>)', () => {
  const prep = () => seed({
    'users/u2': userProfile('u2'),
    'jobs/j1': job('poster', { status: 'Completed', acceptedApplicantId: 'worker' }),
    'properties/p1': property('host'),
    // payout doc shape from tranyx_app.dart (completion payout): uid, amounts, fee split, status
    'transactions/payout_nyx_j1': { uid: 'worker', title: 'Gig Payout Released', desc: 'Payout for completing job j1', amount: 696, baseAmount: 800, commissionFee: 24, holdbackAmount: 80, status: 'Successful', method: 'Tranyx Wallet', type: 'payout', createdAt: NOW },
    'transactions/fees_emp_j1': { uid: 'poster', title: 'Job fees', amount: 40, status: 'Successful', type: 'fee', createdAt: NOW },
    'transactions/refund_prop_p1': { uid: 'renter', title: 'Lease refund', amount: 18000, status: 'Successful', type: 'refund', createdAt: NOW },
  });
  it('TXE-00 [MUST-ALLOW] guest-readable job id is what the attacker starts from', async () => {
    await prep();
    await assertSucceeds(getDoc(doc(guest(), 'jobs/j1')));
  });
  it('TXE-01 [MEDIUM] unrelated signed-in user cannot get the worker payout tx derived from a public jobId', async () => {
    await prep();
    await assertFails(getDoc(doc(user('u2'), 'transactions/payout_nyx_j1')));
  });
  it('TXE-02 [MEDIUM] unrelated signed-in user cannot get the employer fee tx (fees_emp_<jobId>)', async () => {
    await prep();
    await assertFails(getDoc(doc(user('u2'), 'transactions/fees_emp_j1')));
  });
  it('TXE-03 [MEDIUM] unrelated signed-in user cannot get a renter refund tx derived from a public propertyId', async () => {
    await prep();
    await assertFails(getDoc(doc(user('u2'), 'transactions/refund_prop_p1')));
  });
  it('TXE-04 [HIGH] guest cannot get any tx by id — secure', async () => {
    await prep();
    await assertFails(getDoc(doc(guest(), 'transactions/payout_nyx_j1')));
  });
});
