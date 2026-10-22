// Follow-ups to Kelvin's review of 6aa1a41: transactions get scoped to owner/job participants, withdrawal owner writes pinned to a transition.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { setupEnv, seed, user, adminClaim, userProfile, job, withdrawal } from './helpers.mjs';

setupEnv();
const NOW = 1761123600000;
const prep = () => seed({
  'users/poster': userProfile('poster'), 'users/worker': userProfile('worker'),
  'jobs/j1': job('poster', { status: 'Completed', acceptedApplicantId: 'worker' }),
  'transactions/payout_nyx_j1': { uid: 'worker', amount: 696, status: 'Successful', type: 'payout', createdAt: NOW },
  'transactions/fees_emp_j1': { uid: 'poster', amount: 40, status: 'Successful', type: 'fee', createdAt: NOW },
  'transactions/p2p_with_wr1': { uid: 'u1', amount: 500, status: 'PENDING', type: 'withdrawal', createdAt: NOW },
});

describe('FU2-TX: by-id reads the app relies on', () => {
  it('FU2-TX-01 [MUST-ALLOW] employer and worker read both job tx docs (tranyx_app.dart:5176/5243/5549/5614)', async () => {
    await prep();
    for (const who of ['poster', 'worker'])
      for (const id of ['payout_nyx_j1', 'fees_emp_j1']) await assertSucceeds(getDoc(doc(user(who), `transactions/${id}`)));
  });
  it('FU2-TX-02 [MUST-ALLOW] any signed-in user can check a tx id that does not exist yet (existingTx / deductTyxBalanceSafely idempotency)', async () => {
    await prep();
    await assertSucceeds(getDoc(doc(user('u2'), 'transactions/tx_ref_escrow9')));
    await assertSucceeds(getDoc(doc(user('u2'), 'transactions/p2p_dep_notThere')));
  });
  it('FU2-TX-03 [MUST-ALLOW] owner reads own p2p tx; admin/agent reads any (firebase_service.dart p2p_with_/p2p_dep_)', async () => {
    await prep();
    await assertSucceeds(getDoc(doc(user('u1'), 'transactions/p2p_with_wr1')));
    await assertSucceeds(getDoc(doc(adminClaim(), 'transactions/payout_nyx_j1')));
  });
  it('FU2-TX-04 [MEDIUM] non-participant cannot read another user\'s p2p tx by id', async () => {
    await prep();
    await assertFails(getDoc(doc(user('worker'), 'transactions/p2p_with_wr1')));
  });
});

describe('FU2-WR: owner withdrawal fields are tied to the cancel/confirm transition', () => {
  it('FU2-WR-01 [LOW] cancel cannot set p2pStatus to anything but CANCELLED', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'PENDING_REVIEW' }) });
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'CANCELLED', p2pStatus: 'COMPLETED' }));
  });
  it('FU2-WR-02 [LOW] confirm cannot carry a rejectionReason or refund fields', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'PENDING_CONFIRMATION' }) });
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'APPROVED', rejectionReason: 'x' }));
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'APPROVED', balanceDeducted: false }));
  });
  it('FU2-WR-03 [MUST-ALLOW] mobile cancel with a reason (transit_repository.dart cancelP2pWithdrawalRequest merge)', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'PENDING' }) });
    await assertSucceeds(setDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'CANCELLED', rejectionReason: 'wrong account', verifiedAt: NOW }, { merge: true }));
  });
});
