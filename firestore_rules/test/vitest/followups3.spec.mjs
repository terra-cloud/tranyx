// Follow-ups to Kelvin's review of a65e219: structured tx ids pinned to their party, job tx reads, verifiedAt bounds.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';
import { setupEnv, seed, user, adminClaim, userProfile, job, property, withdrawal } from './helpers.mjs';

setupEnv();
const NOW = 1761123600000;
const tx = (uid, type = 'refund') => ({ uid, amount: 10, status: 'Completed', type, createdAt: NOW });
const prep = () => seed({
  'users/poster': userProfile('poster'), 'users/worker': userProfile('worker'), 'users/eve': userProfile('eve'),
  'users/host': userProfile('host'), 'users/u1': userProfile('u1'),
  'jobs/j1': job('poster', { status: 'In Progress', acceptedApplicantId: 'worker' }),
  'properties/p1': property('host'),
  'deposit_requests/d1': { uid: 'u1', amount: 500, status: 'WAITING_FOR_AGENT', createdAt: NOW },
  'withdrawal_requests/w1': withdrawal('u1', { status: 'WAITING_FOR_AGENT' }),
});

describe('FU3-ID: structured transaction ids belong to their party', () => {
  it('FU3-ID-01 [MUST-ALLOW] real writers create their own structured ids (job_repository cancel/delete, deletePropertyRental, transit_repository P2P)', async () => {
    await prep();
    await assertSucceeds(setDoc(doc(user('poster'), 'transactions/refund_job_j1'), tx('poster')));
    await assertSucceeds(setDoc(doc(user('poster'), 'transactions/refund_stale_job_j1'), tx('poster')));
    await assertSucceeds(setDoc(doc(user('host'), 'transactions/refund_prop_p1'), tx('host')));
    await assertSucceeds(setDoc(doc(user('u1'), 'transactions/p2p_dep_d1'), tx('u1', 'deposit')));
    await assertSucceeds(setDoc(doc(user('u1'), 'transactions/p2p_with_w1'), tx('u1', 'withdraw')));
    await assertSucceeds(setDoc(doc(user('eve'), 'transactions/tx_free_form_1'), tx('eve', 'payment')));
    await assertSucceeds(setDoc(doc(adminClaim(), 'transactions/payout_nyx_j1'), tx('worker', 'payout')));
  });
  it('FU3-ID-02 [MEDIUM] non-party cannot squat refund_job_/refund_prop_/p2p_ ids, nor any id whose record is missing', async () => {
    await prep();
    const db = user('eve');
    for (const id of ['refund_job_j1', 'refund_stale_job_j1', 'fees_emp_j1', 'payout_nyx_j1', 'refund_prop_p1', 'p2p_dep_d1', 'p2p_with_w1',
                      'refund_prop_p9', 'p2p_dep_d9', 'p2p_with_w9', 'p2p_other_1', 'payout_nyx_j9'])
      await assertFails(setDoc(doc(db, `transactions/${id}`), tx('eve')));
  });
  it('FU3-ID-03 [MEDIUM] a job party cannot take the other party\'s id (worker -> fees_emp_, employer -> payout_nyx_)', async () => {
    await prep();
    await assertFails(setDoc(doc(user('worker'), 'transactions/fees_emp_j1'), tx('worker')));
    await assertFails(setDoc(doc(user('poster'), 'transactions/payout_nyx_j1'), tx('poster')));
  });
});

describe('FU3-DEL: job deletes cannot orphan payout/fee records', () => {
  it('FU3-DEL-01 [MUST-ALLOW] creator deletes an Open/Cancelled job with no payout/fee records (deleteJob / tranyx_app.dart:6278)', async () => {
    await prep();
    await seed({ 'jobs/j2': job('poster', { status: 'Open' }), 'jobs/j3': job('poster', { status: 'Cancelled' }), 'transactions/refund_job_j3': tx('poster') });
    await assertSucceeds(deleteDoc(doc(user('poster'), 'jobs/j2')));
    await assertSucceeds(deleteDoc(doc(user('poster'), 'jobs/j3')));
  });
  it('FU3-DEL-02 [MEDIUM] creator cannot delete a job that has a payout_nyx_/fees_emp_ record; admin still can', async () => {
    await prep();
    await seed({ 'jobs/j4': job('poster', { status: 'Cancelled' }), 'transactions/fees_emp_j4': tx('poster', 'fee'),
                 'jobs/j5': job('poster', { status: 'Open' }), 'transactions/payout_nyx_j5': tx('worker', 'payout') });
    await assertFails(deleteDoc(doc(user('poster'), 'jobs/j4')));
    await assertFails(deleteDoc(doc(user('poster'), 'jobs/j5')));
    await assertSucceeds(deleteDoc(doc(adminClaim(), 'jobs/j4')));
  });
  it('FU3-DEL-03 [MEDIUM] re-created job id with the old worker as hired does not expose the old employer fees', async () => {
    await seed({ 'users/eve': userProfile('eve'), 'transactions/fees_emp_j9': tx('poster', 'fee'),
                 'jobs/j9': job('eve', { status: 'Open', acceptedApplicantId: 'poster' }) });
    await assertFails(getDoc(doc(user('eve'), 'transactions/fees_emp_j9')));
  });
});

describe('FU3-RD: missing job/property tx ids are only checkable by their parties', () => {
  it('FU3-RD-01 [MUST-ALLOW] job participants check not-yet-created payout/fee ids (tranyx_app.dart:5176/5243, deductTyxBalanceSafely); host checks refund_prop_', async () => {
    await prep();
    for (const who of ['poster', 'worker'])
      for (const id of ['payout_nyx_j1', 'fees_emp_j1']) await assertSucceeds(getDoc(doc(user(who), `transactions/${id}`)));
    await assertSucceeds(getDoc(doc(user('host'), 'transactions/refund_prop_p1')));
    await assertSucceeds(getDoc(doc(adminClaim(), 'transactions/payout_nyx_j8')));
  });
  it('FU3-RD-02 [LOW] non-party gets PERMISSION_DENIED for missing payout/fee/refund_prop ids, existing job or not', async () => {
    await prep();
    for (const id of ['payout_nyx_j1', 'fees_emp_j1', 'refund_prop_p1', 'payout_nyx_j8', 'refund_prop_p8'])
      await assertFails(getDoc(doc(user('eve'), `transactions/${id}`)));
  });
});

describe('FU3-WR: owner verifiedAt is bounded by the request and request.time', () => {
  const wr = (status, extra = {}) => seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status, ...extra }) });
  it('FU3-WR-01 [MUST-ALLOW] confirm and cancel with verifiedAt = now (transit_repository.dart / firebase_service.dart)', async () => {
    await wr('PENDING_CONFIRMATION');
    await assertSucceeds(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'APPROVED', p2pStatus: 'COMPLETED', adminUid: 'u1', verifiedAt: Date.now() }));
    await wr('WAITING_FOR_AGENT');
    await assertSucceeds(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'CANCELLED', verifiedAt: Date.now() }));
  });
  it('FU3-WR-02 [LOW] verifiedAt before the request was created, or > 5 min in the future, is denied', async () => {
    const db = user('u1');
    for (const v of [1, NOW - 7200000, Date.now() + 3600000]) {
      await wr('PENDING_CONFIRMATION');
      await assertFails(updateDoc(doc(db, 'withdrawal_requests/wr1'), { status: 'APPROVED', p2pStatus: 'COMPLETED', verifiedAt: v }));
      await wr('PENDING_REVIEW');
      await assertFails(updateDoc(doc(db, 'withdrawal_requests/wr1'), { status: 'CANCELLED', verifiedAt: v }));
    }
  });
  it('FU3-WR-03 [LOW] a request with no createdAt only accepts verifiedAt within 5 min of request.time', async () => {
    const db = user('u1');
    await seed({ 'withdrawal_requests/wr2': { uid: 'u1', userId: 'u1', amount: 5, status: 'PENDING_CONFIRMATION' } });
    await assertFails(updateDoc(doc(db, 'withdrawal_requests/wr2'), { status: 'APPROVED', verifiedAt: Date.now() - 3600000 }));
    await assertSucceeds(updateDoc(doc(db, 'withdrawal_requests/wr2'), { status: 'APPROVED', verifiedAt: Date.now() }));
  });
});
