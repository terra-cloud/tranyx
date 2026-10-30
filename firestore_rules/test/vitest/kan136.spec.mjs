// KAN-136 test-first suite (Kelvin, Oct 22 2026, against develop 37bc331 / rules fa46ec61). Emulator only (demo-tranyx).
// Saga implements against these. Conventions (README): it = secure today or must-allow that passes today;
// knownHole = must-deny that SUCCEEDS today (RED once closed -> change to it);
// allowHole = must-allow that is DENIED today for the stated rule line (RED once allowed -> change to it);
// planned / plannedAllow = outcome only a server-side completion (Cloud Function / KAN-126 ledger) can satisfy.
// Closed by Saga on fix/kan136-stopgap: 01/02/05/09 + staff B1–B5 → it(). P1/P2/D3/D7/11 remain planned/knownHole.
//
// A) Mobile completion: packages/tranyx_mobile/lib/features/jobs/providers/job_repository.dart completeJob (:590-839),
//    one runTransaction. Who completes (:626-634): hasTracker -> employer (creatorId); else the hired worker
//    (acceptedApplicantId). Writes: users/<worker> credit (:675), promos/<code> (:696), transactions/payout_nyx_<job>
//    type 'payout' uid worker (:709-725), escrow/<job> delete (:729), escrow_holdbacks/<job> (:733), users/<employer>
//    debit when fees not pre-funded (:767), transactions/fees_emp_<job> type 'fee_deduction' uid employer (:773-795),
//    platform_fees/<job> (:800), jobs/<job> status Completed (:816), notifications/notif_<ms>_<prefix> (:825).
// B) ESC-08/10: admin portal syncEnvAuth (lib/core/providers/environment_provider.dart:81/:161 p2p_agents/{self}
//    {uid,email,role:'agent',isActive:true,updatedAt} merge, then :88/:168 users/{self} {role:'admin',isAdmin,isP2pAgent}
//    merge) and deposits.dart:1158/1166. syncEnvAuth auto-provisions env accounts with createUserWithEmailAndPassword
//    (:126), i.e. email_verified=false, so today the "real" admin bootstrap IS the self-provisioning hole.
import { describe, it as vitIt, expect } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, addDoc, writeBatch } from 'firebase/firestore';
import { env, knownHole, planned, setupEnv, seed, user, adminClaim, userProfile, job } from './helpers.mjs';

const it = vitIt;
setupEnv();
const now = () => Date.now();

// Must-allow that is denied today. Re-throws (= expected failure) only for PERMISSION_DENIED naming the stated
// rule line(s); anything else (seed error, other rule, success) turns the test RED.
function denyToday(name, lineRe, fn) {
  vitIt.fails(name, async () => {
    try { await fn(); } catch (e) {
      const msg = String(e?.message ?? e);
      if (process.env.K136_DEBUG) console.log(`[K136_DEBUG] ${name.slice(0, 40)} :: ${msg.replace(/\s+/g, ' ').slice(0, 400)}`);
      if (/PERMISSION_DENIED|permission-denied|Missing or insufficient permissions/i.test(msg) && lineRe.test(msg)) throw e;
      console.error(`[${name}] not the stated denial, failing loudly: ${msg}`);
      return;
    }
    console.error(`[${name}] request succeeded: hole closed or rule fixed, change to it()`);
  });
}
const allowHole = denyToday;    // KNOWN-HOLE KAN-136 must-allow (rules-fixable)
const plannedAllow = denyToday; // PLANNED must-allow (server-side completion only)

// ---------- fixtures ----------
const PRICE = 800;
const FEE = PRICE * 0.03;           // 24, commission (:637)
const PAYOUT = PRICE - FEE;         // 776, immediatePayout with no promo / no holdback (:672-673)
const EMP_FEES = PRICE * 0.07 + PRICE * 0.03; // 80, txFee + convFee (:757-759)
const base = (jobExtra = {}, extra = {}) => seed({
  'users/poster': userProfile('poster', { tyxBalance: 1000 }),
  'users/worker': userProfile('worker', { tyxBalance: 100, jobsDone: 3, totalEarned: 1200, completedGigsCount: 3 }),
  'users/eve': userProfile('eve'), 'users/w2': userProfile('w2'),
  'jobs/j1': job('poster', { status: 'In Progress', acceptedApplicantId: 'worker', ...jobExtra }),
  'jobs/j2': job('poster', { status: 'In Progress', acceptedApplicantId: 'w2' }),
  'escrow/j1': { amount: PRICE, employerFees: EMP_FEES, totalEscrowed: PRICE + EMP_FEES, employerId: 'poster', status: 'held', createdAt: 1, hasInspectionHoldback: false },
  ...extra,
});
const payoutTx = (o = {}) => ({ uid: 'worker', title: 'Gig Payout Released', desc: 'Payout for completing job j1 (3% commission deducted)',
  amount: PAYOUT, baseAmount: PRICE, commissionFee: FEE, commissionRate: 0.03, holdbackAmount: 0, holdbackRate: 0.1,
  status: 'Successful', method: 'Tranyx Wallet', createdAt: now(), type: 'payout', ...o });
const feeTx = (o = {}) => ({ uid: 'poster', title: 'Job Platform Fees Settled (10%)', desc: 'settled from escrow for job j1',
  amount: EMP_FEES, baseAmount: PRICE, transactionFee: PRICE * 0.07, convenienceFee: PRICE * 0.03, transactionFeeRate: 0.07,
  convenienceFeeRate: 0.03, serviceFeeRate: 0.01, markupRate: 0.03, discountAmount: 0, status: 'Successful',
  method: 'Tranyx Escrow', createdAt: now(), type: 'fee_deduction', ...o });
const platformFees = () => ({ jobId: 'j1', amount: FEE + EMP_FEES, commissionFee: FEE, transactionFee: PRICE * 0.07, convenienceFee: PRICE * 0.03,
  transactionFeeRate: 0.07, convenienceFeeRate: 0.03, employerFees: EMP_FEES, nyxianFee: FEE, totalFees: FEE + EMP_FEES, timestamp: now() });
const workerCredit = (amt = PAYOUT) => ({ tyxBalance: 100 + amt, jobsDone: 4, totalEarned: 1200 + amt, completedGigsCount: 4, repeatHireRate: 0.35 });
const notif = (to, from) => [`notifications/notif_${now()}_${to.slice(0, 5)}`, { uid: to, title: 'Gig Completed', message: `${from} has completed "Fix sink". Click to rate them.`,
  type: 'job_completed', jobId: 'j1', senderUid: from, senderName: from, isRead: false, createdAt: now() }];

// Worker-side writes of completeJob (no tracker, fees pre-funded in escrow): what a rules-only fix must allow.
const workerSide = (db, { payout = payoutTx(), credit = workerCredit() } = {}) => {
  const b = writeBatch(db);
  b.update(doc(db, 'users/worker'), credit);
  b.set(doc(db, 'transactions/payout_nyx_j1'), payout);
  b.delete(doc(db, 'escrow/j1'));
  b.update(doc(db, 'jobs/j1'), { status: 'Completed' });
  const [np, nd] = notif('poster', 'worker'); b.set(doc(db, np), nd);
  return b;
};
// The exact mobile transaction (worker, no tracker, pre-funded): adds the employer's fee record and platform_fees.
const fullMobileWorker = (db) => {
  const b = workerSide(db);
  b.set(doc(db, 'transactions/fees_emp_j1'), feeTx());
  b.set(doc(db, 'platform_fees/j1'), platformFees());
  return b;
};

describe('KAN-136-A MUST-ALLOW: mobile job completion (job_repository.dart:590-839)', () => {
  it('KAN-136-A0 [MUST-ALLOW] writes in completeJob that pass today (job status, notification); the escrow delete is Admin-SDK only since Phase 4', async () => {
    await base();
    const db = user('worker');
    await assertSucceeds(updateDoc(doc(db, 'jobs/j1'), { status: 'Completed' }));
    const [np, nd] = notif('poster', 'worker'); await assertSucceeds(setDoc(doc(db, np), nd));
    await assertFails(deleteDoc(doc(db, 'escrow/j1')));
  });
  it('KAN-136-01 [LOCKED, client blocker] hired worker batch that credits own tyxBalance is refused (tyxBalance is server-only; completion must move to a callable): own credit + payout_nyx_<job> (type payout, amount = price - 3%) + escrow delete + job Completed + notification', async () => {
      await base();
      await assertFails(workerSide(user('worker')).commit());
    });
  it('KAN-136-02 [HIGH] payout_nyx_<job> alone, created by the hired worker for themself with the job-consistent amount', async () => {
      await base();
      await assertSucceeds(setDoc(doc(user('worker'), 'transactions/payout_nyx_j1'), payoutTx()));
    });
  plannedAllow('PLANNED KAN-136-P1 [HIGH] the exact mobile transaction as the worker (adds fees_emp_<job> uid=employer type fee_deduction + platform_fees/<job>): needs server-side completion (compiled:291 / platform_fees compiled:1144)',
    /L\d+/, async () => {
      await base();
      await assertSucceeds(fullMobileWorker(user('worker')).commit());
    });
  plannedAllow('PLANNED KAN-136-P2 [HIGH] hasTracker job: employer completes (credits the worker\'s tyxBalance, writes payout for the worker, holdback, job Completed): cross-user money writes, server-side only (users update compiled:185-211 / jobs compiled:645-647 / tx compiled:291)',
    /L\d+/, async () => {
      await base({ hasTracker: true, hasInspectionHoldback: true });
      const db = user('poster');
      const hold = PRICE * 0.10, imm = PAYOUT - hold;
      const b = writeBatch(db);
      b.update(doc(db, 'users/worker'), workerCredit(imm));
      b.set(doc(db, 'transactions/payout_nyx_j1'), payoutTx({ amount: imm, holdbackAmount: hold }));
      b.delete(doc(db, 'escrow/j1'));
      b.set(doc(db, 'escrow_holdbacks/j1'), { jobId: 'j1', amount: hold, nyxianId: 'worker', employerId: 'poster', status: 'held', createdAt: now(), releaseAt: now() + 172800000 });
      b.set(doc(db, 'transactions/fees_emp_j1'), feeTx());
      b.set(doc(db, 'platform_fees/j1'), platformFees());
      b.update(doc(db, 'jobs/j1'), { status: 'Completed' });
      const [np, nd] = notif('worker', 'poster'); b.set(doc(db, np), nd);
      await assertSucceeds(b.commit());
    });
});

describe('KAN-136-D MUST-DENY: forged / foreign / replayed completions', () => {
  it('KAN-136-D1 [CRITICAL] a non-party cannot complete: job status, payout_nyx_<job> (for self or the worker), escrow delete, full batch', async () => {
    await base();
    const db = user('eve');
    await assertFails(updateDoc(doc(db, 'jobs/j1'), { status: 'Completed' }));
    await assertFails(setDoc(doc(db, 'transactions/payout_nyx_j1'), payoutTx({ uid: 'eve' })));
    await assertFails(setDoc(doc(db, 'transactions/payout_nyx_j1'), payoutTx()));
    await assertFails(deleteDoc(doc(db, 'escrow/j1')));
    await assertFails(workerSide(db).commit());
  });
  it('KAN-136-D2 [CRITICAL] payout_nyx_<job> with an amount not matching the job (1,000,000; > price; 0; negative) is denied', async () => {
    await base();
    for (const amount of [1000000, PRICE + 1, 0, -5])
      await assertFails(setDoc(doc(user('worker'), 'transactions/payout_nyx_j1'), payoutTx({ amount })));
  });
  it('KAN-136-D3 [CRITICAL] worker cannot credit own tyxBalance by more than the payout in the completion batch (own-doc update has no balance bound, compiled:187-189; =MON-01, needs KAN-126 ledger or server completion)', async () => {
    await base();
    const db = user('worker');
    const b = writeBatch(db);
    b.update(doc(db, 'users/worker'), workerCredit(1000000));
    b.update(doc(db, 'jobs/j1'), { status: 'Completed' });
    await assertFails(b.commit());
  });
  it('KAN-136-D4 [CRITICAL] payout to a third uid is denied (payout_nyx_<job> with uid eve; also non-banned type)', async () => {
    await base();
    const db = user('worker');
    await assertFails(setDoc(doc(db, 'transactions/payout_nyx_j1'), payoutTx({ uid: 'eve' })));
    await assertFails(setDoc(doc(db, 'transactions/payout_nyx_j1'), payoutTx({ uid: 'eve', type: 'fee' })));
    await assertFails(workerSide(db, { payout: payoutTx({ uid: 'eve' }) }).commit());
  });
  it('KAN-136-05 [CRITICAL] replay: on a Completed job the worker cannot rewrite the existing payout_nyx_<job> (amount 1,000,000)', async () => {
    await base({ status: 'Completed' }, { 'transactions/payout_nyx_j1': payoutTx() });
    await assertFails(setDoc(doc(user('worker'), 'transactions/payout_nyx_j1'), payoutTx({ amount: 1000000 })));
  });
  it('KAN-136-D6 [HIGH] replay: the employer cannot overwrite the worker\'s existing payout_nyx_<job> on a Completed job', async () => {
    await base({ status: 'Completed' }, { 'transactions/payout_nyx_j1': payoutTx() });
    await assertFails(setDoc(doc(user('poster'), 'transactions/payout_nyx_j1'), payoutTx({ amount: 1000000 })));
  });
  it('KAN-136-D7 [HIGH] replay: a second completion on a Completed job cannot credit the worker again (status Completed->Completed is allowed, compiled:620-628; balance credit unbounded, compiled:187-189)', async () => {
    await base({ status: 'Completed' }, { 'transactions/payout_nyx_j1': payoutTx() });
    const db = user('worker');
    const b = writeBatch(db);
    b.update(doc(db, 'users/worker'), workerCredit());
    b.update(doc(db, 'jobs/j1'), { status: 'Completed' });
    await assertFails(b.commit());
  });
  it('KAN-136-D8 [HIGH] wrong job id / prefix: payout_nyx_<other job>, payout_nyx_<missing job>, fees_emp_<job> by the worker, unstructured id with type payout', async () => {
    await base();
    const db = user('worker');
    await assertFails(setDoc(doc(db, 'transactions/payout_nyx_j2'), payoutTx()));        // j2 hired w2
    await assertFails(setDoc(doc(db, 'transactions/payout_nyx_j1x'), payoutTx()));       // no such job
    await assertFails(setDoc(doc(db, 'transactions/fees_emp_j1'), feeTx({ uid: 'worker' })));
    await assertFails(setDoc(doc(db, 'transactions/payout_j1'), payoutTx()));
    await assertFails(setDoc(doc(db, 'transactions/payout_nyx_j1'), payoutTx({ type: 'fee_deduction' })));
  });
  knownHole('KNOWN-HOLE KAN-136-11 [MEDIUM] worker cannot create payout_nyx_<job> with a forged amount by changing the type string (type ban is exact-match only, compiled:291)', async () => {
    await base();
    for (const type of ['Payout', 'fee', 'payment']) {
      try { await assertFails(setDoc(doc(user('worker'), 'transactions/payout_nyx_j1'), payoutTx({ amount: 1000000, type }))); }
      finally { await env.clearFirestore(); await base(); }
    }
  });
  it('KAN-136-09 [HIGH] hired worker cannot delete the job escrow unless the same write completes the job', async () => {
    await base();
    await assertFails(deleteDoc(doc(user('worker'), 'escrow/j1')));
  });
  it('KAN-136-D10 [HIGH] worker cannot write platform_fees or the employer\'s fee record, and cannot debit the employer (compiled:1144, :291, :185-211)', async () => {
    await base({}, { 'escrow/j1': { amount: PRICE, employerFees: 0, employerId: 'poster', status: 'held', createdAt: 1 } });
    const db = user('worker');
    await assertFails(setDoc(doc(db, 'platform_fees/j1'), platformFees()));
    await assertFails(setDoc(doc(db, 'transactions/fees_emp_j1'), feeTx()));
    await assertFails(updateDoc(doc(db, 'users/poster'), { tyxBalance: 1000 - EMP_FEES }));
  });
});

// ---------- B: staff self-provisioning ----------
const agentDoc = (uid, email, o = {}) => ({ uid, email, role: 'agent', isActive: true, updatedAt: now(), ...o });
const adminUserDoc = (uid, email) => ({ uid, email, role: 'admin', isAdmin: true, isP2pAgent: true, name: 'Staff Admin', updatedAt: now() });
const UNVERIFIED = ['imp@tranyx.app', 'imp@tranyx.com', 'imp@tranyx.ph', 'imp@tranyx.dev', 'imp@agents.tranyx.app', 'imp.staff@tranyx.app'];
const unverified = (email = 'imp@tranyx.app') => user('imp', { email, email_verified: false });
const deskSeed = (extra = {}) => seed({
  'users/victim': userProfile('victim'), 'users/poster': userProfile('poster'), 'users/worker': userProfile('worker'),
  'users/imp': userProfile('imp', { email: 'imp@tranyx.app' }), 'users/p2p': userProfile('p2p'),
  'jobs/j1': job('poster', { status: 'In Progress', acceptedApplicantId: 'worker', applicantUids: ['worker'] }),
  'support_chats/victim': { userIds: ['victim'], userName: 'Victim', lastMessage: 'my ID card', status: 'assigned', assignedAgentId: 'p2p', requestedAt: 1, updatedAt: 1 },
  'support_chats/victim/messages/s1': { senderId: 'victim', senderName: 'Victim', content: 'my ID card', createdAt: 1 },
  'chats/job_j1_worker': { userIds: ['poster', 'worker'], jobId: 'j1', applicantId: 'worker', type: 'job', updatedAt: 1 },
  'chats/job_j1_worker/messages/m1': { senderId: 'poster', senderName: 'Employer', text: 'gate code 1234', type: 'text', createdAt: 1 },
  'notifications/notif_1_victi': { uid: 'victim', title: 'Withdrawal approved', message: 'ok', type: 'withdrawal', isRead: false, createdAt: 1 },
  'p2p_agents/p2p': agentDoc('p2p', 'p2p@gmail.com'),
  ...extra,
});
// Try the real syncEnvAuth self-provision through the rules (ignored if a fix denies it), then probe.
const selfProvision = async (db) => {
  try { await setDoc(doc(db, 'p2p_agents/imp'), agentDoc('imp', 'imp@tranyx.app'), { merge: true }); } catch {}
  try { await setDoc(doc(db, 'users/imp'), adminUserDoc('imp', 'imp@tranyx.app'), { merge: true }); } catch {}
};
const READS = {
  "get another user's support_chats doc": (db) => getDoc(doc(db, 'support_chats/victim')),
  "read another user's support messages": (db) => getDocs(collection(db, 'support_chats/victim/messages')),
  'list all support_chats': (db) => getDocs(collection(db, 'support_chats')),
  "get a chat they are not in": (db) => getDoc(doc(db, 'chats/job_j1_worker')),
  "read that chat's messages": (db) => getDocs(collection(db, 'chats/job_j1_worker/messages')),
  "read another user's notification": (db) => getDoc(doc(db, 'notifications/notif_1_victi')),
};

describe('KAN-136-B MUST-DENY: unverified staff-domain self-provisioning (ESC-08/10)', () => {
  for (const email of UNVERIFIED) {
    it(`KAN-136-B1 [CRITICAL] unverified ${email} cannot create p2p_agents/{self} (syncEnvAuth payload; requires verified staff email)`, async () => {
      await assertFails(setDoc(doc(unverified(email), 'p2p_agents/imp'), agentDoc('imp', email), { merge: true }));
    });
  }
  it('KAN-136-B2 [CRITICAL] unverified @tranyx.app cannot update an existing p2p_agents/{self} (re-activate after an admin set isActive:false)', async () => {
    await deskSeed({ 'p2p_agents/imp': agentDoc('imp', 'imp@tranyx.app', { isActive: false }) });
    await assertFails(setDoc(doc(unverified(), 'p2p_agents/imp'), { isActive: true, updatedAt: now() }, { merge: true }));
  });
  it('KAN-136-B3 [CRITICAL] unverified @tranyx.app cannot merge role:admin/isAdmin/isP2pAgent into users/{self}', async () => {
    await deskSeed();
    await assertFails(setDoc(doc(unverified(), 'users/imp'), adminUserDoc('imp', 'imp@tranyx.app'), { merge: true }));
  });
  for (const [op, fn] of Object.entries(READS)) {
    it(`KAN-136-B4 [CRITICAL] after attempting self-provision, unverified @tranyx.app cannot ${op}`, async () => {
      await deskSeed();
      const db = unverified();
      await selfProvision(db);
      await assertFails(fn(db));
    });
  }
  it('KAN-136-B5 [HIGH] a deactivated agent (p2p_agents isActive:false, set by admin) loses desk access', async () => {
    await deskSeed({ 'p2p_agents/p2p': agentDoc('p2p', 'p2p@gmail.com', { isActive: false }) });
    await assertFails(getDoc(doc(user('p2p'), 'support_chats/victim')));
  });
  it('KAN-136-B6 [CRITICAL] unverified @tranyx.app with no self-written docs gets no desk reads (secure today)', async () => {
    await deskSeed();
    for (const [op, fn] of Object.entries(READS)) {
      try { await assertFails(fn(unverified())); } catch (e) { throw new Error(`${op}: ${e.message}`); }
    }
  });
  it('KAN-136-B7 [CRITICAL] gmail user cannot create p2p_agents/{self} (secure today)', async () => {
    await assertFails(setDoc(doc(user('g1'), 'p2p_agents/g1'), agentDoc('g1', 'g1@gmail.com'), { merge: true }));
  });
});

describe('KAN-136-B MUST-ALLOW: real admin provisioning keeps working', () => {
  it('KAN-136-M1 [MUST-ALLOW] admin claim creates p2p_agents for another uid (syncEnvAuth payload, merge)', async () => {
    await deskSeed();
    await assertSucceeds(setDoc(doc(adminClaim(), 'p2p_agents/newAgent'), agentDoc('newAgent', 'new@gmail.com'), { merge: true }));
  });
  it('KAN-136-M2 [MUST-ALLOW] admin claim self-provisions like syncEnvAuth :81/:88 and deposits.dart:1158/1166 (p2p_agents/{self} + users/{self})', async () => {
    await deskSeed({ 'users/realAdmin': userProfile('realAdmin') });
    const db = adminClaim('realAdmin');
    await assertSucceeds(setDoc(doc(db, 'p2p_agents/realAdmin'), agentDoc('realAdmin', 'ops@example.org'), { merge: true }));
    await assertSucceeds(setDoc(doc(db, 'users/realAdmin'), adminUserDoc('realAdmin', 'ops@example.org'), { merge: true }));
  });
  it('KAN-136-M3 (KAN-144: path removed) verified @tranyx.app email WITHOUT admin claim can no longer self-provision p2p_agents/{self} + users/{self}', async () => {
    await deskSeed({ 'users/staff1': userProfile('staff1', { email: 'staff1@tranyx.app' }) });
    const db = user('staff1', { email: 'staff1@tranyx.app', email_verified: true });
    await assertFails(setDoc(doc(db, 'p2p_agents/staff1'), agentDoc('staff1', 'staff1@tranyx.app'), { merge: true }));
    await assertFails(setDoc(doc(db, 'users/staff1'), adminUserDoc('staff1', 'staff1@tranyx.app'), { merge: true }));
  });
  it('KAN-136-M4 [MUST-ALLOW] admin claim deactivates an agent (isActive:false merge)', async () => {
    await deskSeed();
    await assertSucceeds(setDoc(doc(adminClaim(), 'p2p_agents/p2p'), { isActive: false, updatedAt: now() }, { merge: true }));
  });
  it('KAN-136-M5 [MUST-ALLOW] properly provisioned agent (admin-written p2p_agents doc, gmail login) keeps desk access: reads, list, reply, desk-field merge, notifications', async () => {
    await deskSeed();
    const db = user('p2p');
    for (const [op, fn] of Object.entries(READS)) {
      try { await assertSucceeds(fn(db)); } catch (e) { throw new Error(`${op}: ${e.message}`); }
    }
    await assertSucceeds(addDoc(collection(db, 'support_chats/victim/messages'), { senderId: 'p2p', senderName: 'Agent', content: 'hi', createdAt: now(), isStaff: true, agentEmail: 'p2p@gmail.com' }));
    await assertSucceeds(setDoc(doc(db, 'support_chats/victim'), { status: 'active', assignedAgentId: 'p2p', assignedAgentName: 'Agent', updatedAt: now() }, { merge: true }));
  });
  it('KAN-136-M6 [MUST-ALLOW] admin-claim agent created via M1 then has desk access', async () => {
    await deskSeed();
    await setDoc(doc(adminClaim(), 'p2p_agents/newAgent'), agentDoc('newAgent', 'new@gmail.com'), { merge: true });
    await assertSucceeds(getDoc(doc(user('newAgent'), 'support_chats/victim')));
  });
});
