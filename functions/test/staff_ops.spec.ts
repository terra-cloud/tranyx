// Staff / P2P-agent money callables against the Firestore emulator (npm run test:emulator).
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { MoneyDeps } from '../src/money';
import { staffClaimsOnly, staffOps, staffRole } from '../src/staff_ops';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8189';
initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();
let clock = Date.UTC(2026, 10, 3, 4, 0, 0);
const deps = (): MoneyDeps => ({ db, now: () => clock });
let n = 0;
const key = () => `key_${Date.now()}_${++n}_abcdef`;
const as = (uid: string, token: Record<string, unknown> = {}) => ({ uid, token });
const admin = as('adm', { admin: true });
const agent = as('agt', { role: 'agent' });
const agent2 = as('agt2', { role: 'agent' });
const nobody = as('user1');
const err = async (p: Promise<unknown>) => p.then(() => null, (e: any) => e);
const bal = async (uid: string) => (await db.doc(`users/${uid}`).get()).get('tyxBalance') as number;
const op = (a: ReturnType<typeof as>, body: Record<string, unknown>) => staffOps(deps(), a, { idempotencyKey: key(), ...body });

async function clearAll() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-tranyx/databases/(default)/documents`, { method: 'DELETE' });
}
const withdrawal = (over: Record<string, unknown> = {}) => ({
  id: 'w1', uid: 'user1', userId: 'user1', method: 'p2p', status: 'WAITING_FOR_AGENT', amount: 500, paymentMethod: 'GCash', balanceDeducted: true, ...over,
});

beforeAll(async () => { await clearAll(); });
beforeEach(async () => {
  await clearAll();
  for (const [uid, b] of [['user1', 100], ['emp', 0], ['wrk', 0], ['agt', 0], ['agt2', 0]] as const) await db.doc(`users/${uid}`).set({ tyxBalance: b, reservedBalance: 0, name: uid });
});

describe('staffRole', () => {
  it('custom claims grant the role; user-doc and p2p_agents flags do not by default', () => {
    expect(staffRole({ admin: true }, undefined, undefined)).toBe('admin');
    expect(staffRole({ role: 'support' }, undefined, undefined)).toBe('staff');
    expect(staffRole({ role: 'p2p_agent' }, undefined, undefined)).toBe('agent');
    expect(staffRole({}, { isAdmin: true }, undefined)).toBeNull();
    expect(staffRole({}, { role: 'admin' }, { isActive: true })).toBeNull();
    expect(staffRole({}, { isAdmin: true }, undefined, false)).toBe('admin');
    expect(staffRole({}, {}, { isActive: true }, false)).toBe('agent');
    expect(staffRole({}, { name: 'x' }, { isActive: false })).toBeNull();
    expect(staffClaimsOnly()).toBe(true);
    expect(staffClaimsOnly({ FUNCTIONS_EMULATOR: 'true', STAFF_CLAIMS_ONLY: 'false' } as NodeJS.ProcessEnv)).toBe(false);
    expect(staffClaimsOnly({ FUNCTIONS_EMULATOR: 'true' } as NodeJS.ProcessEnv)).toBe(true);
    expect(staffClaimsOnly({ STAFF_CLAIMS_ONLY: 'false' } as NodeJS.ProcessEnv)).toBe(true);
  });
});

describe('claim / release', () => {
  it('claims a PENDING_REVIEW cashout (TRAD-12: shown as waiting, old code rejected it); a second agent is blocked; replay is idempotent', async () => {
    await db.doc('withdrawal_requests/w1').set(withdrawal({ status: 'PENDING_REVIEW' }));
    await db.doc('transactions/p2p_with_w1').set({ status: 'PENDING_REVIEW' });
    const k = key();
    const r = await staffOps(deps(), agent, { idempotencyKey: k, action: 'claimWithdrawal', withdrawalId: 'w1' });
    expect(r.status).toBe('AWAITING_AGENT_PAYMENT');
    expect((await staffOps(deps(), agent, { idempotencyKey: k, action: 'claimWithdrawal', withdrawalId: 'w1' })).replay).toBe(true);
    expect((await db.doc('withdrawal_requests/w1').get()).data()).toMatchObject({ agentId: 'agt', status: 'AWAITING_AGENT_PAYMENT' });
    expect((await db.doc('transactions/p2p_with_w1').get()).get('agentId')).toBe('agt');
    const other = await err(op(agent2, { action: 'claimWithdrawal', withdrawalId: 'w1' }));
    expect(other?.code).toBe('failed-precondition');
    expect(other?.details?.code).toBe('CLAIMED_BY_OTHER');
    expect((await err(op(agent2, { action: 'releaseClaim', withdrawalId: 'w1' })))?.code).toBe('permission-denied');
    await op(agent, { action: 'releaseClaim', withdrawalId: 'w1' });
    expect((await db.doc('withdrawal_requests/w1').get()).get('agentId')).toBe('');
    expect((await op(agent2, { action: 'claimWithdrawal', withdrawalId: 'w1' })).status).toBe('AWAITING_AGENT_PAYMENT');
  });
  it('plain users and unknown ids are refused; approved cashouts are not claimable', async () => {
    await db.doc('withdrawal_requests/w1').set(withdrawal());
    expect((await err(op(nobody, { action: 'claimWithdrawal', withdrawalId: 'w1' })))?.code).toBe('permission-denied');
    expect((await err(op(agent, { action: 'claimWithdrawal', withdrawalId: 'nope' })))?.code).toBe('not-found');
    await db.doc('withdrawal_requests/w1').set({ status: 'APPROVED' }, { merge: true });
    expect((await err(op(agent, { action: 'claimWithdrawal', withdrawalId: 'w1' })))?.details?.code).toBe('NOT_CLAIMABLE');
  });
});

describe('rejectWithdrawal', () => {
  it('refunds the held amount exactly once and writes an audit entry', async () => {
    await db.doc('withdrawal_requests/w1').set(withdrawal({ status: 'AWAITING_AGENT_PAYMENT', agentId: 'agt' }));
    await db.doc('withdrawals/w1').set({ status: 'AWAITING_AGENT_PAYMENT' });
    const r = await op(agent, { action: 'rejectWithdrawal', withdrawalId: 'w1', reason: 'Wrong account number' });
    expect(r.refunded).toBe(500);
    expect(await bal('user1')).toBe(600);
    expect((await db.doc('withdrawals/w1').get()).get('status')).toBe('REJECTED');
    const again = await op(admin, { action: 'rejectWithdrawal', withdrawalId: 'w1' });
    expect(again.alreadyDone).toBe(true);
    expect(await bal('user1')).toBe(600);
    const logs = await db.collection('staff_audit_log').get();
    expect(logs.docs.map((d) => d.get('action')).filter((a) => a === 'rejectWithdrawal').length).toBe(2);
    expect(logs.docs.every((d) => !!d.get('actorUid') && !!d.get('createdAt'))).toBe(true);
  });
  it('another agent cannot reject a claimed order; unfunded requests refund nothing', async () => {
    await db.doc('withdrawal_requests/w1').set(withdrawal({ status: 'AWAITING_AGENT_PAYMENT', agentId: 'agt' }));
    expect((await err(op(agent2, { action: 'rejectWithdrawal', withdrawalId: 'w1' })))?.code).toBe('permission-denied');
    await db.doc('withdrawal_requests/w2').set(withdrawal({ id: 'w2', balanceDeducted: false }));
    expect((await op(agent, { action: 'rejectWithdrawal', withdrawalId: 'w2' })).refunded).toBe(0);
    expect(await bal('user1')).toBe(100);
  });
  it('solana withdrawals are not handled here', async () => {
    await db.doc('withdrawal_requests/w3').set(withdrawal({ id: 'w3', method: 'solana' }));
    expect((await err(op(agent, { action: 'rejectWithdrawal', withdrawalId: 'w3' })))?.code).toBe('failed-precondition');
  });
});

describe('approveDeposit', () => {
  const dep = (over: Record<string, unknown> = {}) => ({ userId: 'user1', userName: 'U', amount: 250, referenceNumber: 'ab-123', paymentMethod: 'GCash', status: 'PENDING', ...over });
  it('credits the amount from the doc once, claims the reference, ignores any client amount', async () => {
    await db.doc('deposit_requests/d1').set(dep());
    const r = await op(agent, { action: 'approveDeposit', depositId: 'd1', amount: 99999 });
    expect(r.credited).toBe(250);
    expect(await bal('user1')).toBe(350);
    expect((await db.doc('claimed_p2p_references/AB-123').get()).get('depositRequestId')).toBe('d1');
    expect((await op(agent, { action: 'approveDeposit', depositId: 'd1' })).alreadyDone).toBe(true);
    expect(await bal('user1')).toBe(350);
    expect((await db.doc('transactions/p2p_dep_d1').get()).get('amount')).toBe(250);
  });
  it('a reference already claimed by another deposit blocks approval; rejected deposits cannot be approved; plain users refused', async () => {
    await db.doc('claimed_p2p_references/AB-123').set({ depositRequestId: 'other', userName: 'Someone' });
    await db.doc('deposit_requests/d1').set(dep());
    expect((await err(op(agent, { action: 'approveDeposit', depositId: 'd1' })))?.details?.code).toBe('REFERENCE_CLAIMED');
    await db.doc('deposit_requests/d2').set(dep({ referenceNumber: 'zz-9', status: 'REJECTED' }));
    expect((await err(op(agent, { action: 'approveDeposit', depositId: 'd2' })))?.code).toBe('failed-precondition');
    await db.doc('deposit_requests/d3').set(dep({ referenceNumber: 'yy-8' }));
    expect((await err(op(nobody, { action: 'approveDeposit', depositId: 'd3' })))?.code).toBe('permission-denied');
    expect(await bal('user1')).toBe(100);
  });
});

describe('resolveDispute', () => {
  async function seed() {
    await db.doc('jobs/j1').set({ creatorId: 'emp', acceptedApplicantId: 'wrk', status: 'Disputed' });
    await db.doc('escrow/j1').set({ status: 'held', amount: 1000, employerId: 'emp' });
    // dispute doc is client-created: its employerId / escrowAmount must be ignored
    await db.doc('disputes/x1').set({ jobId: 'j1', status: 'OPEN', employerId: 'user1', acceptedNyxianId: 'user1', escrowAmount: 999999 });
  }
  it('split: amounts come from escrow, parties from escrow / job, once', async () => {
    await seed();
    const r = await op(admin, { action: 'resolveDispute', disputeId: 'x1', resolutionType: 'SPLIT_ESCROW', employerPercent: 30, nyxianPercent: 70, notes: 'Split 30/70 after review' });
    expect(r).toMatchObject({ employerRefund: 300, nyxianPayout: 700 });
    expect(await bal('emp')).toBe(300);
    expect(await bal('wrk')).toBe(700);
    expect(await bal('user1')).toBe(100);
    expect((await db.doc('escrow/j1').get()).get('status')).toBe('split_resolved');
    expect((await db.doc('disputes/x1').get()).get('status')).toBe('RESOLVED');
    expect((await op(admin, { action: 'resolveDispute', disputeId: 'x1', resolutionType: 'REFUND_EMPLOYER', notes: 'Second attempt here' })).alreadyDone).toBe(true);
    expect(await bal('emp')).toBe(300);
  });
  it('agents cannot arbitrate; bad splits and short notes are rejected; refund path cancels the job', async () => {
    await seed();
    const body = { action: 'resolveDispute', disputeId: 'x1', resolutionType: 'REFUND_EMPLOYER', notes: 'Employer wins, no work done' };
    expect((await err(op(agent, body)))?.code).toBe('permission-denied');
    expect((await err(op(admin, { ...body, notes: 'short' })))?.code).toBe('invalid-argument');
    expect((await err(op(admin, { ...body, resolutionType: 'SPLIT_ESCROW', employerPercent: 80, nyxianPercent: 80 })))?.code).toBe('invalid-argument');
    await op(admin, body);
    expect(await bal('emp')).toBe(1000);
    expect((await db.doc('jobs/j1').get()).get('status')).toBe('Cancelled');
  });
  it('an escrow that is not held cannot be paid out again', async () => {
    await seed();
    await db.doc('escrow/j1').set({ status: 'released' }, { merge: true });
    expect((await err(op(admin, { action: 'resolveDispute', disputeId: 'x1', resolutionType: 'PAY_NYXIAN', notes: 'Worker did the work' })))?.code).toBe('failed-precondition');
    expect(await bal('wrk')).toBe(0);
  });
});

describe('self-money denial', () => {
  const dep = (over: Record<string, unknown> = {}) => ({ userId: 'user1', uid: 'user1', userName: 'U', amount: 250, referenceNumber: 'ab-123', paymentMethod: 'GCash', status: 'PENDING', ...over });
  const quiet = async (uid: string, expected: number) => {
    expect(await bal(uid)).toBe(expected);
    expect((await db.collection('staff_audit_log').get()).size).toBe(0);
    expect((await db.collection('money_ops').get()).size).toBe(0);
    expect((await db.collection('claimed_p2p_references').get()).size).toBe(0);
  };

  it('approveDeposit, claimWithdrawal and rejectWithdrawal refuse every owner alias that is the actor', async () => {
    await db.doc('users/agt').set({ tyxBalance: 40, name: 'agt' }, { merge: true });
    await db.doc('users/adm').set({ tyxBalance: 40, name: 'adm' });
    const cases: Array<[ReturnType<typeof as>, Record<string, unknown>, string]> = [
      [agent, { userId: 'agt', uid: 'agt' }, 'agt'],
      [agent, { userId: '  agt  ' }, 'pad'],
      [agent, { uid: 'users/agt' }, 'path'],
      [agent, { uid: 'user1', userId: 'agt' }, 'split'],
      [agent, { user_id: 'agt', ownerId: 'user1' }, 'alias'],
      [admin, { userId: 'adm', uid: 'adm' }, 'adm'],
    ];
    for (const [who, over, ref] of cases) {
      const id = `self_${ref}`;
      await db.doc(`deposit_requests/${id}`).set(dep({ ...over, referenceNumber: `ref-${ref}` }));
      const e = await err(op(who, { action: 'approveDeposit', depositId: id }));
      expect(e?.code).toBe('permission-denied');
      expect(e?.details?.code).toBe('SELF_ACTION');
      expect((await db.doc(`deposit_requests/${id}`).get()).get('status')).toBe('PENDING');
    }
    await db.doc('withdrawal_requests/wself').set(withdrawal({ id: 'wself', uid: 'agt', userId: 'wallets/agt' }));
    expect((await err(op(agent, { action: 'claimWithdrawal', withdrawalId: 'wself' })))?.details?.code).toBe('SELF_ACTION');
    expect((await err(op(agent, { action: 'rejectWithdrawal', withdrawalId: 'wself' })))?.details?.code).toBe('SELF_ACTION');
    expect((await db.doc('withdrawal_requests/wself').get()).get('status')).toBe('WAITING_FOR_AGENT');
    await quiet('agt', 40);
    await quiet('user1', 100);
    expect(await bal('adm')).toBe(40);
  });

  it('disagreeing owners that are not the actor are refused, and a padded other-user id still credits once', async () => {
    await db.doc('deposit_requests/mix').set(dep({ uid: 'user1', userId: 'emp', referenceNumber: 'mix-1' }));
    expect((await err(op(agent, { action: 'approveDeposit', depositId: 'mix' })))?.details?.code).toBe('OWNER_MISMATCH');
    expect(await bal('user1')).toBe(100);
    expect(await bal('emp')).toBe(0);
    await db.doc('deposit_requests/padok').set(dep({ uid: ' user1 ', userId: 'users/user1', referenceNumber: 'pad-ok' }));
    const r = await op(agent, { action: 'approveDeposit', depositId: 'padok' });
    expect(r.credited).toBe(250);
    expect(await bal('user1')).toBe(350);
  });

  it('an active p2p_agents doc or users.isAdmin does not authorize staffOps', async () => {
    await db.doc('users/docagt').set({ name: 'docagt', tyxBalance: 0, isP2pAgent: true });
    await db.doc('p2p_agents/docagt').set({ isActive: true });
    await db.doc('users/flag').set({ name: 'flag', tyxBalance: 0, isAdmin: true, role: 'admin' });
    await db.doc('withdrawal_requests/w1').set(withdrawal());
    for (const uid of ['docagt', 'flag']) {
      const e = await err(op(as(uid), { action: 'claimWithdrawal', withdrawalId: 'w1' }));
      expect(e?.code).toBe('permission-denied');
    }
    expect((await db.doc('withdrawal_requests/w1').get()).get('status')).toBe('WAITING_FOR_AGENT');
    expect((await db.collection('staff_audit_log').get()).size).toBe(0);
  });
});

describe('idempotency is bound to actor, action and target', () => {
  const dep = (id: string, ref: string, over: Record<string, unknown> = {}) =>
    db.doc(`deposit_requests/${id}`).set({ userId: 'user1', uid: 'user1', userName: 'U', amount: 250, referenceNumber: ref, paymentMethod: 'GCash', status: 'PENDING', ...over });

  it('the same key replays; a different action or target is rejected with no second effect', async () => {
    await dep('d1', 'ab-123');
    await dep('d2', 'cd-456');
    await db.doc('withdrawal_requests/w1').set(withdrawal());
    const k = key();
    const first = await staffOps(deps(), agent, { idempotencyKey: k, action: 'approveDeposit', depositId: 'd1' });
    expect(first.credited).toBe(250);
    const again = await staffOps(deps(), agent, { idempotencyKey: k, action: 'approveDeposit', depositId: 'd1' });
    expect(again.replay).toBe(true);
    expect(again.credited).toBe(250);
    const otherAction = await err(staffOps(deps(), agent, { idempotencyKey: k, action: 'claimWithdrawal', withdrawalId: 'w1' }));
    expect(otherAction?.code).toBe('already-exists');
    expect(otherAction?.details?.code).toBe('IDEMPOTENCY_MISMATCH');
    const otherTarget = await err(staffOps(deps(), agent, { idempotencyKey: k, action: 'approveDeposit', depositId: 'd2' }));
    expect(otherTarget?.details?.code).toBe('IDEMPOTENCY_MISMATCH');
    const otherActor = await staffOps(deps(), agent2, { idempotencyKey: k, action: 'approveDeposit', depositId: 'd1' });
    expect(otherActor.replay).toBeUndefined();
    expect(otherActor.alreadyDone).toBe(true);
    expect(await bal('user1')).toBe(350);
    expect((await db.doc('deposit_requests/d2').get()).get('status')).toBe('PENDING');
    expect((await db.doc('withdrawal_requests/w1').get()).get('status')).toBe('WAITING_FOR_AGENT');
    expect((await db.collection('staff_audit_log').get()).size).toBe(2);
  });

  it('two concurrent retries of the same operation credit once', async () => {
    await dep('d1', 'ab-123');
    const k = key();
    const [a, b] = await Promise.all([
      staffOps(deps(), agent, { idempotencyKey: k, action: 'approveDeposit', depositId: 'd1' }),
      staffOps(deps(), agent, { idempotencyKey: k, action: 'approveDeposit', depositId: 'd1' }),
    ]);
    expect([a.replay, b.replay].sort()).toEqual([true, undefined]);
    expect(await bal('user1')).toBe(350);
    expect((await db.collection('staff_audit_log').get()).size).toBe(1);
  });
});

describe('web staff money contracts', () => {
  const dep = (over: Record<string, unknown> = {}) => ({ userId: 'user1', uid: 'user1', userName: 'U', amount: 250, referenceNumber: 'pv-1', paymentMethod: 'GCash', status: 'PENDING_VERIFICATION', ...over });

  it('approveDeposit accepts PENDING_VERIFICATION and credits the doc amount once', async () => {
    await db.doc('deposit_requests/dv').set(dep());
    const r = await op(agent, { action: 'approveDeposit', depositId: 'dv', amount: 1 });
    expect(r.credited).toBe(250);
    expect(await bal('user1')).toBe(350);
    expect((await op(agent, { action: 'approveDeposit', depositId: 'dv' })).alreadyDone).toBe(true);
    expect(await bal('user1')).toBe(350);
  });

  it('adminCancelJob refunds the held escrow amount only, not employer fees, and not twice', async () => {
    await db.doc('jobs/j9').set({ creatorId: 'emp', acceptedApplicantId: 'wrk', status: 'In Progress', title: 'Fix sink' });
    await db.doc('escrow/j9').set({ status: 'held', amount: 800, employerFees: 80, employerId: 'emp' });
    const reason = 'Worker never showed up after hire';
    expect((await err(op(admin, { action: 'adminCancelJob', jobId: 'j9', reason: 'too short' })))?.code).toBe('invalid-argument');
    expect(await bal('emp')).toBe(0);
    expect((await db.collection('staff_audit_log').get()).size).toBe(0);
    const r = await op(admin, { action: 'adminCancelJob', jobId: 'j9', reason });
    expect(r.refunded).toBe(800);
    expect(await bal('emp')).toBe(800);
    expect((await db.doc('jobs/j9').get()).get('status')).toBe('ADMIN_CANCELLED');
    expect((await db.doc('escrow/j9').get()).data()).toMatchObject({ status: 'refunded', refundAmount: 800 });
    expect((await db.doc('transactions/refund_job_j9').get()).get('amount')).toBe(800);
    const again = await op(admin, { action: 'adminCancelJob', jobId: 'j9', reason });
    expect(again.alreadyDone).toBe(true);
    expect(await bal('emp')).toBe(800);
    expect((await err(op(agent, { action: 'adminCancelJob', jobId: 'j9', reason })))?.code).toBe('permission-denied');
  });

  it('the employer cannot admin-cancel their own gig, and a party cannot arbitrate their own dispute', async () => {
    await db.doc('users/adm').set({ tyxBalance: 10, name: 'adm' });
    await db.doc('jobs/jself').set({ creatorId: 'adm', status: 'In Progress', title: 'Mine' });
    await db.doc('escrow/jself').set({ status: 'held', amount: 100, employerFees: 20, employerId: 'adm' });
    const selfCancel = await err(op(admin, { action: 'adminCancelJob', jobId: 'jself', reason: 'This is my own gig and must not refund me' }));
    expect(selfCancel?.details?.code).toBe('SELF_ACTION');
    expect(await bal('adm')).toBe(10);
    expect((await db.doc('jobs/jself').get()).get('status')).toBe('In Progress');
    await db.doc('jobs/j1').set({ creatorId: 'emp', acceptedApplicantId: 'wrk', status: 'Disputed' });
    await db.doc('escrow/j1').set({ status: 'held', amount: 1000, employerId: 'emp' });
    await db.doc('disputes/xself').set({ jobId: 'j1', status: 'OPEN', employerId: 'adm', escrowAmount: 1 });
    const party = as('emp', { admin: true });
    const selfDispute = await err(op(party, { action: 'resolveDispute', disputeId: 'xself', resolutionType: 'REFUND_EMPLOYER', notes: 'Employer is also the admin' }));
    expect(selfDispute?.details?.code).toBe('SELF_ACTION');
    expect(await bal('emp')).toBe(0);
    expect((await db.doc('disputes/xself').get()).get('status')).toBe('OPEN');
    expect((await db.collection('staff_audit_log').get()).size).toBe(0);
  });

  it('an unfunded gig can still be admin-cancelled without a balance write', async () => {
    await db.doc('jobs/j0').set({ creatorId: 'emp', status: 'Open', title: 'No funds' });
    const r = await op(admin, { action: 'adminCancelJob', jobId: 'j0', reason: 'Posted in error before anyone was hired' });
    expect(r.refunded).toBe(0);
    expect(await bal('emp')).toBe(0);
    expect((await db.doc('jobs/j0').get()).get('status')).toBe('ADMIN_CANCELLED');
  });
});
