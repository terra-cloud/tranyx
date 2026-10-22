// Added Oct 22 during review of Saga's a65e219 (fix/rules-followups-2): TXE participant reads + WR2-05 pinning.
// Probes are written as the SECURE expectation. knownHole() = finding still open on a65e219.
import { describe, it, expect } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, where, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';
import { knownHole, setupEnv, seed, user, userProfile, job, withdrawal } from './helpers.mjs';

setupEnv();
const NOW = 1761123600000;
const base = () => seed({
  'users/poster': userProfile('poster'), 'users/worker': userProfile('worker'), 'users/eve': userProfile('eve'),
  'jobs/j1': job('poster', { status: 'Completed', acceptedApplicantId: 'worker' }),
  'transactions/payout_nyx_j1': { uid: 'worker', amount: 696, status: 'Successful', type: 'payout', createdAt: NOW },
  'transactions/fees_emp_j1': { uid: 'poster', amount: 40, status: 'Successful', type: 'fee', createdAt: NOW },
  'transactions/refund_prop_p1': { uid: 'poster', amount: 18000, status: 'Successful', type: 'refund', createdAt: NOW },
});

describe('RV-A65-A: existence oracle on predictable tx ids', () => {
  it('RV-A65-A1 non-party is denied on existing job tx / refund docs (content protected)', async () => {
    await base();
    for (const id of ['payout_nyx_j1', 'fees_emp_j1', 'refund_prop_p1'])
      await assertFails(getDoc(doc(user('eve'), `transactions/${id}`)));
  });
  knownHole('KNOWN-HOLE RV-A65-A2 [LOW] non-party cannot tell an existing tx id from a missing one (denied vs allowed-null = existence oracle)', async () => {
    await base();
    // Existing -> PERMISSION_DENIED (A1). Missing -> allowed (resource == null). Secure expectation: missing is also denied for non-parties.
    await assertFails(getDoc(doc(user('eve'), 'transactions/refund_prop_p2')));
    await assertFails(getDoc(doc(user('eve'), 'transactions/payout_nyx_j2')));
  });
});

describe('RV-A65-B: list/query by non-party', () => {
  it('RV-A65-B1 non-party cannot list all transactions or query by another uid', async () => {
    await base();
    await assertFails(getDocs(collection(user('eve'), 'transactions')));
    await assertFails(getDocs(query(collection(user('eve'), 'transactions'), where('uid', '==', 'worker'))));
    await assertFails(getDocs(query(collection(user('eve'), 'transactions'), where('type', '==', 'payout'))));
  });
  it('RV-A65-B2 [MUST-ALLOW] owner query uid == self works', async () => {
    await base();
    await assertSucceeds(getDocs(query(collection(user('worker'), 'transactions'), where('uid', '==', 'worker'))));
  });
});

describe('RV-A65-C: becoming a job party to read someone else\'s payout', () => {
  it('RV-A65-C1 eve cannot overwrite/recreate an existing job (creatorId) or self-assign as hired worker', async () => {
    await base();
    const db = user('eve');
    await assertFails(setDoc(doc(db, 'jobs/j1'), job('eve', { status: 'Completed', acceptedApplicantId: 'eve' })));
    await assertFails(updateDoc(doc(db, 'jobs/j1'), { acceptedApplicantId: 'eve' }));
    await assertFails(updateDoc(doc(db, 'jobs/j1'), { creatorId: 'eve' }));
  });
  it('RV-A65-C2 applicant on an Open job cannot set acceptedApplicantId on themselves', async () => {
    await seed({ 'users/poster': userProfile('poster'), 'users/eve': userProfile('eve'), 'jobs/j3': job('poster', { status: 'Open' }) });
    await assertFails(updateDoc(doc(user('eve'), 'jobs/j3'), { acceptedApplicantId: 'eve', applicantUids: ['worker', 'eve'] }));
  });
  knownHole('KNOWN-HOLE RV-A65-C3 [MEDIUM] orphaned job tx: after a job doc is deleted, re-creating jobs/<sameId> must not grant read on the old payout/fees', async () => {
    // Creator may delete Open/Cancelled jobs (30_...:77); tx docs survive. Anyone can then create jobs/<id> as creator.
    await seed({ 'users/poster': userProfile('poster'), 'users/eve': userProfile('eve'),
      'transactions/fees_emp_j9': { uid: 'poster', amount: 40, status: 'Successful', type: 'fee', createdAt: NOW } });
    const db = user('eve');
    await assertSucceeds(setDoc(doc(db, 'jobs/j9'), job('eve', { acceptedApplicantId: null })));
    await assertFails(getDoc(doc(db, 'transactions/fees_emp_j9')));
  });
  knownHole('KNOWN-HOLE RV-A65-C4 [MEDIUM] non-party cannot pre-create (squat) a job-derived tx id payout_nyx_<publicJobId> / fees_emp_<jobId>', async () => {
    // Job ids are public (jobs allow read: true). The app reads the id first and skips the write if it exists (idempotency).
    await seed({ 'users/poster': userProfile('poster'), 'users/eve': userProfile('eve'), 'jobs/j5': job('poster', { status: 'In Progress', acceptedApplicantId: 'worker' }) });
    await assertFails(setDoc(doc(user('eve'), 'transactions/payout_nyx_j5'), { uid: 'eve', amount: 1, status: 'Successful', type: 'fee', createdAt: NOW }));
  });
});

describe('RV-A65-D: WR2-05 owner cannot forge verification state', () => {
  const base2 = (status, extra = {}) => seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status, p2pStatus: 'WAITING', ...extra }) });
  it('RV-A65-D1 no status change -> no p2pStatus/verifiedAt/rejectionReason write', async () => {
    await base2('WAITING_FOR_AGENT');
    const db = user('u1');
    for (const w of [{ p2pStatus: 'COMPLETED' }, { p2pStatus: 'VERIFIED' }, { verifiedAt: NOW }, { rejectionReason: 'x' }, { updatedAt: NOW }])
      await assertFails(updateDoc(doc(db, 'withdrawal_requests/wr1'), w));
  });
  it('RV-A65-D2 owner cannot set p2pStatus to a verified/approved value in any transition', async () => {
    const db = user('u1');
    for (const v of ['VERIFIED', 'APPROVED', 'PAID', 'SENT', 'AWAITING_CONFIRMATION']) {
      await base2('PENDING_REVIEW');
      await assertFails(updateDoc(doc(db, 'withdrawal_requests/wr1'), { status: 'CANCELLED', p2pStatus: v }));
      await base2('PENDING_CONFIRMATION');
      await assertFails(updateDoc(doc(db, 'withdrawal_requests/wr1'), { status: 'APPROVED', p2pStatus: v }));
    }
  });
  it('RV-A65-D3 owner cannot jump to APPROVED from any non-PENDING_CONFIRMATION state even with pinned fields', async () => {
    for (const from of ['WAITING_FOR_AGENT', 'PENDING_REVIEW', 'PENDING', 'AWAITING_AGENT_PAYMENT', 'REJECTED']) {
      await base2(from);
      await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'APPROVED', p2pStatus: 'COMPLETED', verifiedAt: NOW }));
    }
  });
  it('RV-A65-D4 non-owner cannot cancel/confirm', async () => {
    await base2('PENDING_CONFIRMATION');
    await assertFails(updateDoc(doc(user('eve'), 'withdrawal_requests/wr1'), { status: 'APPROVED', p2pStatus: 'COMPLETED' }));
  });
  knownHole('KNOWN-HOLE RV-A65-D5 [LOW] verifiedAt is not pinned: owner can backdate/future-date it, and set it on a cancel (10_...:37 only checks `is number`)', async () => {
    await base2('PENDING_CONFIRMATION');
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'APPROVED', p2pStatus: 'COMPLETED', verifiedAt: 1 }));
  });
  it('RV-A65-D6 [MUST-ALLOW] legit confirm-receipt', async () => {
    await base2('PENDING_CONFIRMATION');
    await assertSucceeds(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'APPROVED', p2pStatus: 'COMPLETED', verifiedAt: NOW, adminUid: 'u1', updatedAt: NOW }));
  });
});

describe('RV-A65-E: expression-limit probe (denied paths evaluate every branch)', () => {
  it('RV-A65-E1 a heavy denied tx get and a heavy denied withdrawal update return PERMISSION_DENIED, not an evaluation error', async () => {
    await base();
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'REJECTED' }) });
    for (const p of [
      getDoc(doc(user('eve'), 'transactions/payout_nyx_j1')),
      updateDoc(doc(user('eve'), 'withdrawal_requests/wr1'), { status: 'CANCELLED', p2pStatus: 'CANCELLED', balanceDeducted: false, refundedAt: NOW, rejectionReason: 'x', verifiedAt: NOW, adminUid: 'eve', updatedAt: NOW }),
      updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'CANCELLED', p2pStatus: 'CANCELLED', balanceDeducted: false, refundedAt: NOW, rejectionReason: 'x', verifiedAt: NOW, updatedAt: NOW }),
    ]) {
      const err = await p.then(() => null, (e) => e);
      expect(err?.code).toBe('permission-denied');
      expect(String(err?.message)).not.toMatch(/limit|maximum|exceed/i);
    }
  });
});
