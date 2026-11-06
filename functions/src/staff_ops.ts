import { HttpsError } from 'firebase-functions/https';
import type { Firestore, Transaction } from 'firebase-admin/firestore';
import {
  CallerAuth, MoneyDeps, Wallet, ledger, notify, numOf, parseId, parseKey, readOpMeta, requireAuth, round2, str, writeOp,
} from './money';

/**
 * Staff / P2P-agent money operations (TRAD-12, KAN-126/127 blocker "c").
 *
 * Until now the admin portal wrote users/{uid}.tyxBalance from the browser (deposit approval, cashout reject
 * refund, dispute arbitration) and `isAdminOrStaff()` (which includes isP2pAgent) let ANY agent write ANY balance.
 * These actions run server-side instead, one Firestore transaction each:
 *   - identity: server-issued custom claims only, in every real environment. Legacy users-doc flags and an
 *     active p2p_agents doc are ignored unless the Functions emulator is running with STAFF_CLAIMS_ONLY=false.
 *   - role matrix: agents may claim / release / reject cashouts and approve deposits; only admin / staff may arbitrate disputes
 *   - amounts come from the authoritative docs (deposit_requests, withdrawal_requests, escrow), never from the client
 *   - status guards make every refund / credit happen at most once; idempotencyKey replays return the stored result
 *   - every action writes an Admin-SDK-only `staff_audit_log/{opId}` entry (who, what, amounts, before / after)
 */

const ACTIONS = ['claimWithdrawal', 'releaseClaim', 'rejectWithdrawal', 'approveDeposit', 'resolveDispute'] as const;
type Action = (typeof ACTIONS)[number];
type Doc = Record<string, any>;
type Role = 'admin' | 'staff' | 'agent';

/** Statuses a queued P2P cashout can be claimed from. PENDING_REVIEW is written by older clients and shown as "waiting agent" (TRAD-12). */
export const CLAIMABLE = ['WAITING_FOR_AGENT', 'PENDING_REVIEW', 'REQUESTED', 'OPEN', 'PENDING'];
/** Statuses a cashout can be rejected (refunded) from: queued, claimed, or proof submitted. Never APPROVED / REJECTED / CANCELLED. */
export const REJECTABLE = [...CLAIMABLE, 'AWAITING_AGENT_PAYMENT', 'PENDING_CONFIRMATION'];
const ADMIN_ROLES = ['admin', 'super_admin', 'superadmin'];
const STAFF_ROLES = ['staff', 'support'];
const AGENT_ROLES = ['agent', 'p2p_agent'];
const DEPOSIT_PENDING = ['PENDING', 'PENDING_REVIEW', 'WAITING_FOR_AGENT', 'OPEN', 'REQUESTED', 'UNDER_REVIEW'];

/**
 * Claims-only unless this process is the local Functions emulator AND STAFF_CLAIMS_ONLY=false.
 * A deployed function ignores the off switch: user-doc flags cannot grant staffOps.
 */
export function staffClaimsOnly(env: NodeJS.ProcessEnv = process.env): boolean {
  return !(env.FUNCTIONS_EMULATOR === 'true' && env.STAFF_CLAIMS_ONLY === 'false');
}

export function staffRole(token: Record<string, unknown> | undefined, user: Doc | undefined, agent: Doc | undefined, claimsOnly = true): Role | null {
  const tokenRole = typeof token?.role === 'string' ? token.role.toLowerCase() : '';
  if (token?.admin === true || token?.superadmin === true || ADMIN_ROLES.includes(tokenRole)) return 'admin';
  if (STAFF_ROLES.includes(tokenRole)) return 'staff';
  if (AGENT_ROLES.includes(tokenRole) || token?.p2pAgent === true) return 'agent';
  if (claimsOnly) return null;
  const docRole = typeof user?.role === 'string' ? user.role.toLowerCase() : '';
  if (user?.isAdmin === true || user?.isSuperAdmin === true || ADMIN_ROLES.includes(docRole)) return 'admin';
  if (user?.isStaff === true || STAFF_ROLES.includes(docRole)) return 'staff';
  if (user?.isP2pAgent === true || AGENT_ROLES.includes(docRole) || agent?.isActive === true) return 'agent';
  return null;
}

function requireRole(role: Role | null, allowed: Role[]): Role {
  if (!role) throw new HttpsError('permission-denied', 'Staff access required.');
  if (!allowed.includes(role)) throw new HttpsError('permission-denied', 'Your role cannot do this.');
  return role;
}

function audit(tx: Transaction, db: Firestore, opId: string, now: number, entry: Doc) {
  tx.set(db.doc(`staff_audit_log/${opId}`), { ...entry, createdAt: now });
}

const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const OWNER_KEYS = ['uid', 'userId', 'user_id', 'ownerId', 'ownerUid', 'owner', 'accountId', 'accountUid', 'walletOwnerId'];

/** Trim, and unwrap a `users/{id}` or `wallets/{id}` path so a prefixed alias cannot dodge the self check. */
export function canonicalOwnerId(v: unknown): string {
  if (typeof v !== 'string') return '';
  const t = v.trim();
  const m = t.match(/^(?:users|wallets)\/([A-Za-z0-9_-]{1,128})$/);
  return m ? m[1] : t;
}

function ownerAliases(doc: Doc): string[] {
  const out: string[] = [];
  for (const [k, v] of Object.entries(doc)) {
    if (!OWNER_KEYS.includes(k)) continue;
    const id = canonicalOwnerId(v);
    if (id) out.push(id);
  }
  return out;
}

/**
 * One authoritative owner. Any alias that is the actor is a self-money action.
 * Disagreeing aliases are rejected rather than picking the one that is not the actor.
 */
export function authoritativeOwner(doc: Doc, actorUid: string): string {
  const aliases = ownerAliases(doc);
  if (aliases.length === 0) throw new HttpsError('failed-precondition', 'The request has no owner on record.');
  const actor = canonicalOwnerId(actorUid);
  if (aliases.some((a) => a === actor)) {
    throw new HttpsError('permission-denied', 'You cannot act on your own money request.', { code: 'SELF_ACTION' });
  }
  if (new Set(aliases).size !== 1) {
    throw new HttpsError('failed-precondition', 'The request owner is inconsistent.', { code: 'OWNER_MISMATCH' });
  }
  return aliases[0];
}

function actionTarget(action: Action, d: Doc): string {
  if (action === 'approveDeposit') return `deposit:${parseId(d.depositId, 'depositId')}`;
  if (action === 'resolveDispute') return `dispute:${parseId(d.disputeId, 'disputeId')}`;
  const id = parseId(d.withdrawalId, 'withdrawalId');
  if (!ID_RE.test(id)) throw new HttpsError('invalid-argument', 'withdrawalId is invalid.');
  return `withdrawal:${id}`;
}

export interface StaffOpsOptions { claimsOnly?: boolean }

export async function staffOps(deps: MoneyDeps, auth: CallerAuth | undefined, data: unknown, opts: StaffOpsOptions = {}) {
  const uid = requireAuth(auth);
  const d = (data && typeof data === 'object' ? data : {}) as Doc;
  const key = parseKey(d.idempotencyKey);
  const action = d.action as Action;
  if (!ACTIONS.includes(action)) throw new HttpsError('invalid-argument', 'Unknown action.');
  const target = actionTarget(action, d);
  const { db } = deps;
  const now = deps.now();
  const opId = `${uid}_${key}`;
  const claimsOnly = opts.claimsOnly ?? true;

  return db.runTransaction(async (tx) => {
    const replay = await readOpMeta(tx, db, uid, key);
    if (replay) {
      if (replay.uid !== uid || replay.action !== `staff:${action}` || replay.target !== target) {
        throw new HttpsError('already-exists', 'This idempotency key was already used for a different operation.', { code: 'IDEMPOTENCY_MISMATCH' });
      }
      return { ...replay.result, replay: true };
    }
    const [userSnap, agentSnap] = await Promise.all([tx.get(db.doc(`users/${uid}`)), tx.get(db.doc(`p2p_agents/${uid}`))]);
    const role = staffRole(auth?.token, userSnap.data(), agentSnap.data(), claimsOnly);
    const staffName = str(userSnap.get('name'), 80) || str(auth?.token?.email, 80) || uid;
    const done = (result: Record<string, unknown>, entry: Doc) => {
      writeOp(tx, db, uid, key, `staff:${action}`, result, now, target);
      audit(tx, db, opId, now, { action, actorUid: uid, actorName: staffName, actorRole: role, ...entry, result });
      return result;
    };

    // ── P2P cashout: claim / release / reject ───────────────────────────────────────────────
    if (action === 'claimWithdrawal' || action === 'releaseClaim' || action === 'rejectWithdrawal') {
      requireRole(role, ['admin', 'staff', 'agent']);
      const id = parseId(d.withdrawalId, 'withdrawalId');
      if (!ID_RE.test(id)) throw new HttpsError('invalid-argument', 'withdrawalId is invalid.');
      const reqRef = db.doc(`withdrawal_requests/${id}`);
      const mirrors = [db.doc(`withdrawalRequests/${id}`), db.doc(`withdrawals/${id}`)];
      const [reqSnap, ...mirrorSnaps] = await Promise.all([tx.get(reqRef), ...mirrors.map((m) => tx.get(m))]);
      const cur = reqSnap.data();
      if (!cur) throw new HttpsError('not-found', 'Withdrawal request not found.');
      if (String(cur.method ?? '').toLowerCase() === 'solana' || cur.payoutMethod === 'Solana') {
        throw new HttpsError('failed-precondition', 'Solana withdrawals are processed automatically.');
      }
      const status = String(cur.status ?? '').toUpperCase();
      // Claim and reject move or refund the owner's money. Release does not. Self is denied before any write.
      const owner = action === 'releaseClaim' ? str(cur.uid ?? cur.userId, 128) : authoritativeOwner(cur, uid);
      const agentId = str(cur.agentId, 128);
      const amount = numOf(cur.amount);
      const txMain = db.doc(`transactions/p2p_with_${id}`);
      const txWallet = db.doc(`wallets/${owner}/transactions/${id}`);
      const [txMainSnap, txWalletSnap] = await Promise.all([tx.get(txMain), owner ? tx.get(txWallet) : Promise.resolve(null)]);
      const writeAll = (patch: Doc, ledgerPatch: Doc) => {
        tx.set(reqRef, patch, { merge: true });
        mirrorSnaps.forEach((s, i) => { if (s.exists) tx.set(mirrors[i], patch, { merge: true }); });
        if (txMainSnap.exists) tx.set(txMain, ledgerPatch, { merge: true });
        if (txWalletSnap?.exists) tx.set(txWallet, ledgerPatch, { merge: true });
      };

      if (action === 'claimWithdrawal') {
        if (agentId && agentId !== uid) throw new HttpsError('failed-precondition', `Already claimed by ${str(cur.agentName, 80) || 'another agent'}.`, { code: 'CLAIMED_BY_OTHER' });
        if (status === 'AWAITING_AGENT_PAYMENT' && agentId === uid) return done({ ok: true, id, status, alreadyDone: true }, { withdrawalId: id, owner, amount });
        if (!CLAIMABLE.includes(status)) throw new HttpsError('failed-precondition', `This cashout is no longer available (status ${status || 'unknown'}).`, { code: 'NOT_CLAIMABLE', status });
        const patch = { status: 'AWAITING_AGENT_PAYMENT', p2pStatus: 'AWAITING_AGENT_PAYMENT', agentId: uid, agentName: staffName, claimedAt: now, updatedAt: now };
        writeAll(patch, { status: 'AWAITING_AGENT_PAYMENT', agentId: uid, agentName: staffName, updatedAt: now,
          desc: `Agent ${staffName} claimed your order and is transferring ₱${amount.toFixed(2)} to your ${cur.paymentMethod ?? 'account'}.` });
        if (owner) notify(tx, db, owner, now, 'Agent Claimed Cashout Request', `Agent ${staffName} is now sending ₱${amount.toFixed(2)} to your ${cur.paymentMethod ?? 'account'}.`, 'p2p_claim');
        return done({ ok: true, id, status: 'AWAITING_AGENT_PAYMENT' }, { withdrawalId: id, owner, amount });
      }

      if (action === 'releaseClaim') {
        if (status === 'WAITING_FOR_AGENT') return done({ ok: true, id, status, alreadyDone: true }, { withdrawalId: id, owner, amount });
        if (status !== 'AWAITING_AGENT_PAYMENT') throw new HttpsError('failed-precondition', 'Only a claimed cashout can be released.');
        if (agentId !== uid && role !== 'admin') throw new HttpsError('permission-denied', 'Only the claiming agent or an admin can release this claim.');
        const clear = { status: 'WAITING_FOR_AGENT', p2pStatus: 'WAITING_FOR_AGENT', agentId: '', agentName: '', claimedAt: null, updatedAt: now };
        writeAll(clear, { status: 'WAITING_FOR_AGENT', agentId: '', agentName: '', updatedAt: now });
        return done({ ok: true, id, status: 'WAITING_FOR_AGENT' }, { withdrawalId: id, owner, amount, previousAgentId: agentId });
      }

      // rejectWithdrawal: refund once, guarded on status. Only the claiming agent (or admin / staff) may reject a claimed order.
      if (status === 'REJECTED') return done({ ok: true, id, status, alreadyDone: true }, { withdrawalId: id, owner, amount });
      if (!REJECTABLE.includes(status)) throw new HttpsError('failed-precondition', 'This cashout can no longer be rejected.');
      if (role === 'agent' && agentId && agentId !== uid) throw new HttpsError('permission-denied', 'This order is claimed by another agent.');
      if (!owner) throw new HttpsError('failed-precondition', 'The request has no owner on record.');
      const reason = str(d.reason, 500) || 'Rejected by staff';
      const refund = cur.balanceDeducted === true && amount > 0;
      const w = new Wallet(tx, db);
      let before = 0;
      let after = 0;
      if (refund) {
        await w.load(owner);
        before = w.balance(owner);
        w.credit(owner, round2(amount));
        after = w.balance(owner);
        w.flush({ [owner]: { updatedAt: now } });
      }
      const note = refund ? `₱${amount.toFixed(2)} refunded to wallet.` : 'Request rejected.';
      writeAll(
        { status: 'REJECTED', p2pStatus: 'REJECTED', payoutState: 'cancelled', balanceDeducted: false, ...(refund ? { refundedAt: now } : {}), rejectionReason: reason, adminUid: uid, reviewedByAdminId: uid, reviewedByAdminName: staffName, reviewedAt: now, updatedAt: now },
        { status: 'REJECTED', desc: `Cashout rejected: ${reason}. ${note}`, description: `Cashout rejected: ${reason}. ${note}`, updatedAt: now },
      );
      notify(tx, db, owner, now, 'Cashout Request Rejected', `Your ₱${amount.toFixed(2)} cashout was rejected: ${reason}. ${note}`, 'p2p_reject');
      return done({ ok: true, id, status: 'REJECTED', refunded: refund ? round2(amount) : 0 }, { withdrawalId: id, owner, amount, reason, balanceBefore: before, balanceAfter: after, refunded: refund });
    }

    // ── manual P2P deposit approval ─────────────────────────────────────────────────────────
    if (action === 'approveDeposit') {
      requireRole(role, ['admin', 'staff', 'agent']);
      const id = parseId(d.depositId, 'depositId');
      const depRef = db.doc(`deposit_requests/${id}`);
      const depSnap = await tx.get(depRef);
      const dep = depSnap.data();
      if (!dep) throw new HttpsError('not-found', 'Deposit request not found.');
      const status = String(dep.status ?? '').toUpperCase();
      const owner = authoritativeOwner(dep, uid);
      const amount = round2(numOf(dep.amount));
      if (status === 'APPROVED') return done({ ok: true, id, status, alreadyDone: true }, { depositId: id, owner, amount });
      if (!DEPOSIT_PENDING.includes(status)) throw new HttpsError('failed-precondition', 'This deposit can no longer be approved.');
      if (!owner || !(amount > 0) || amount > 1_000_000) throw new HttpsError('failed-precondition', 'This deposit has no valid owner or amount.');
      const ref = str(dep.referenceNumber, 64).toUpperCase().replace(/[^A-Z0-9_-]/g, '');
      if (!ref) throw new HttpsError('failed-precondition', 'This deposit has no reference number.');
      const claimRef = db.doc(`claimed_p2p_references/${ref}`);
      const claimSnap = await tx.get(claimRef);
      if (claimSnap.exists && claimSnap.get('depositRequestId') !== id) {
        throw new HttpsError('already-exists', `Reference #${ref} was already claimed by ${str(claimSnap.get('userName'), 60) || 'another user'}.`, { code: 'REFERENCE_CLAIMED' });
      }
      const w = new Wallet(tx, db);
      await w.load(owner);
      if (!w.exists(owner)) throw new HttpsError('failed-precondition', 'The depositor has no profile.');
      const before = w.balance(owner);
      w.credit(owner, amount);
      const after = w.balance(owner);
      w.flush({ [owner]: { updatedAt: now } });
      tx.set(depRef, { status: 'APPROVED', action: 'APPROVED', reviewedByAdminId: uid, reviewedByAdminName: staffName, reviewedAt: now, updatedAt: now }, { merge: true });
      tx.set(claimRef, { referenceNumber: ref, depositRequestId: id, userId: owner, userName: str(dep.userName, 80), amount, paymentMethod: str(dep.paymentMethod, 40), approvedAt: now, approvedByAdminId: uid, approvedByAdminName: staffName, createdAt: now });
      ledger(tx, db, `p2p_dep_${id}`, owner, now, {
        type: 'deposit', category: 'p2p_deposit', amount, status: 'COMPLETED', paymentMethod: str(dep.paymentMethod, 40), referenceNumber: ref, depositRequestId: id,
        signature: `P2P-${ref}`, title: `Deposit via ${str(dep.paymentMethod, 40) || 'P2P'}`, description: `Reference #${ref} approved by ${staffName}`, timestamp: now,
      });
      notify(tx, db, owner, now, `Deposit Approved! ₱${amount.toFixed(2)} Added`, `Your ₱${amount.toFixed(2)} top-up (Ref #${ref}) has been approved and credited to your wallet.`, 'dep_ok');
      return done({ ok: true, id, status: 'APPROVED', credited: amount, newBalance: after }, { depositId: id, owner, amount, referenceNumber: ref, balanceBefore: before, balanceAfter: after });
    }

    // ── dispute arbitration (admin / staff only) ────────────────────────────────────────────
    requireRole(role, ['admin', 'staff']);
    const id = parseId(d.disputeId, 'disputeId');
    const resolution = str(d.resolutionType, 30);
    if (!['REFUND_EMPLOYER', 'PAY_NYXIAN', 'SPLIT_ESCROW'].includes(resolution)) throw new HttpsError('invalid-argument', 'resolutionType is invalid.');
    const notes = str(d.notes, 1000);
    if (notes.length < 10) throw new HttpsError('invalid-argument', 'Enter at least 10 characters explaining the ruling.');
    const dispRef = db.doc(`disputes/${id}`);
    const dispSnap = await tx.get(dispRef);
    const disp = dispSnap.data();
    if (!disp) throw new HttpsError('not-found', 'Dispute not found.');
    const jobId = parseId(disp.jobId, 'jobId');
    const jobRef = db.doc(`jobs/${jobId}`);
    const escRef = db.doc(`escrow/${jobId}`);
    const [jobSnap, escSnap] = await Promise.all([tx.get(jobRef), tx.get(escRef)]);
    if (String(disp.status ?? '').toUpperCase() === 'RESOLVED') return done({ ok: true, id, alreadyDone: true }, { disputeId: id, jobId });
    if (!escSnap.exists || String(escSnap.get('status') ?? '').toLowerCase() !== 'held') throw new HttpsError('failed-precondition', 'No funds are held for this gig.');
    // Parties and amount come from the escrow + job docs: the dispute doc is client-created and not trusted.
    const employerId = str(escSnap.get('employerId') ?? escSnap.get('creatorId'), 128);
    const nyxianId = str(jobSnap.get('acceptedApplicantId'), 128);
    const escrowAmount = round2(numOf(escSnap.get('amount')));
    let refundToEmployer = 0;
    let payoutToNyxian = 0;
    if (resolution === 'REFUND_EMPLOYER') refundToEmployer = escrowAmount;
    else if (resolution === 'PAY_NYXIAN') payoutToNyxian = escrowAmount;
    else {
      const ep = numOf(d.employerPercent, -1);
      const np = numOf(d.nyxianPercent, -1);
      if (ep < 0 || np < 0 || ep > 100 || np > 100 || ep + np > 100 + 1e-9) throw new HttpsError('invalid-argument', 'Split percentages must be between 0 and 100 and total at most 100.');
      refundToEmployer = round2(escrowAmount * (ep / 100));
      payoutToNyxian = round2(escrowAmount * (np / 100));
    }
    if (refundToEmployer > 0 && !employerId) throw new HttpsError('failed-precondition', 'The gig has no employer on record.');
    if (payoutToNyxian > 0 && !nyxianId) throw new HttpsError('failed-precondition', 'The gig has no hired worker on record.');
    const w = new Wallet(tx, db);
    if (refundToEmployer > 0) await w.load(employerId);
    if (payoutToNyxian > 0) await w.load(nyxianId);
    if (refundToEmployer > 0) w.credit(employerId, refundToEmployer);
    if (payoutToNyxian > 0) w.credit(nyxianId, payoutToNyxian);
    w.flush();
    if (refundToEmployer > 0) {
      ledger(tx, db, `refund_dispute_${id}`, employerId, now, { jobId, disputeId: id, type: 'refund', category: 'refund', amount: refundToEmployer, title: 'Dispute Arbitration Refund', desc: `Escrow refund of ₱${refundToEmployer.toFixed(2)} via admin arbitration.`, method: 'Tranyx Escrow', originRail: 'internal_balance' });
      notify(tx, db, employerId, now, 'Dispute resolved', `Ruling: ${resolution.replace(/_/g, ' ')}. ₱${refundToEmployer.toFixed(2)} was refunded to your wallet.`, 'disp_emp');
    }
    if (payoutToNyxian > 0) {
      ledger(tx, db, `payout_dispute_${id}`, nyxianId, now, { jobId, disputeId: id, type: 'payout', category: 'earnings', amount: payoutToNyxian, title: 'Dispute Arbitration Payout', desc: `Escrow payout of ₱${payoutToNyxian.toFixed(2)} via admin arbitration.`, method: 'Tranyx Escrow', originRail: 'internal_balance' });
      notify(tx, db, nyxianId, now, 'Dispute resolved', `Ruling: ${resolution.replace(/_/g, ' ')}. ₱${payoutToNyxian.toFixed(2)} was paid to your wallet.`, 'disp_nyx');
    }
    const escrowStatus = resolution === 'REFUND_EMPLOYER' ? 'refunded' : resolution === 'PAY_NYXIAN' ? 'released' : 'split_resolved';
    tx.set(escRef, { status: escrowStatus, resolvedViaDispute: true, disputeId: id, employerRefund: refundToEmployer, nyxianPayout: payoutToNyxian, resolvedAt: now, resolvedBy: uid }, { merge: true });
    tx.set(jobRef, { status: resolution === 'REFUND_EMPLOYER' ? 'Cancelled' : 'Completed', resolvedDisputeId: id, updatedAt: now }, { merge: true });
    tx.set(dispRef, { status: 'RESOLVED', resolvedAt: now, resolvedBy: uid, resolutionType: resolution, resolutionNotes: notes, employerRefund: refundToEmployer, nyxianPayout: payoutToNyxian, updatedAt: now }, { merge: true });
    tx.set(db.doc(`chats/${jobId}/messages/msg_res_${id}`), {
      senderId: 'system', senderName: 'Tranyx Arbitration', type: 'dispute_resolved', disputeId: id, resolutionType: resolution,
      text: `Dispute resolved by Admin. Ruling: ${resolution.replace(/_/g, ' ')}. Refund: ₱${refundToEmployer.toFixed(2)}, Payout: ₱${payoutToNyxian.toFixed(2)}. Notes: "${notes}"`, createdAt: now,
    });
    return done({ ok: true, id, resolutionType: resolution, employerRefund: refundToEmployer, nyxianPayout: payoutToNyxian }, { disputeId: id, jobId, employerId, nyxianId, escrowAmount, refundToEmployer, payoutToNyxian, notes });
  });
}

