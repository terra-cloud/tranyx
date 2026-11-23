import type { Firestore } from 'firebase-admin/firestore';
import { CANCELLABLE, cancelP2pCashout, type Deps } from './withdraw';

/** Pending P2P rows older than this are cancelled. Proof-submitted and settled rows are not. */
export const P2P_EXPIRE_MS = 24 * 60 * 60 * 1000;
export const P2P_EXPIRE_REASON = 'expired_24h';

/** Unclaimed / unpaid deposit statuses. No wallet credit has happened yet. */
export const DEPOSIT_EXPIRE_STATUSES = ['WAITING_FOR_AGENT', 'AWAITING_PAYMENT', 'PENDING', 'PENDING_REVIEW', 'OPEN', 'REQUESTED'];

const BATCH = 40;

function createdMs(value: unknown): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (value && typeof value === 'object' && 'toMillis' in value && typeof (value as { toMillis: () => number }).toMillis === 'function') {
    return (value as { toMillis: () => number }).toMillis();
  }
  return 0;
}

function httpsProof(data: Record<string, unknown>): boolean {
  return /^https:\/\//i.test(String(data.proofImageUrl ?? '').trim());
}

/** A deposit the user already paid against: proof, a reference, or a proof timestamp. */
export function depositHasProof(data: Record<string, unknown>): boolean {
  const ref = String(data.referenceNumber ?? '').trim();
  const submitted = createdMs(data.proofSubmittedAt);
  return httpsProof(data) || ref.length > 0 || submitted > 0;
}

async function stale(db: Firestore, collection: string, statuses: string[], cutoff: number, limit: number) {
  const snap = await db.collection(collection)
    .where('status', 'in', statuses)
    .where('createdAt', '<', cutoff)
    .orderBy('createdAt', 'asc')
    .limit(limit)
    .get();
  return snap.docs;
}

async function expireDeposit(deps: Deps, id: string, cutoff: number) {
  const { db } = deps;
  return db.runTransaction(async (tx) => {
    const ref = db.doc(`deposit_requests/${id}`);
    const mirror = db.doc(`depositRequests/${id}`);
    const ledger = db.doc(`transactions/p2p_dep_${id}`);
    const [snap, mirrorSnap, ledgerSnap] = await Promise.all([tx.get(ref), tx.get(mirror), tx.get(ledger)]);
    const cur = snap.data();
    if (!cur) return { skipped: true as const };
    const status = String(cur.status ?? '').toUpperCase();
    if (status === 'CANCELLED') return { alreadyDone: true as const };
    const created = createdMs(cur.createdAt);
    if (!DEPOSIT_EXPIRE_STATUSES.includes(status) || depositHasProof(cur) || !created || created >= cutoff) {
      return { skipped: true as const };
    }
    const now = deps.now();
    const owner = String(cur.uid ?? cur.userId ?? '');
    const patch = { status: 'CANCELLED', rejectionReason: P2P_EXPIRE_REASON, verifiedAt: now, updatedAt: now };
    tx.set(ref, patch, { merge: true });
    if (mirrorSnap.exists) tx.set(mirror, patch, { merge: true });
    if (ledgerSnap.exists) {
      tx.set(ledger, {
        status: 'CANCELLED',
        rejectionReason: P2P_EXPIRE_REASON,
        desc: 'Deposit cancelled. expired_24h',
        verifiedAt: now,
        updatedAt: now,
      }, { merge: true });
    }
    if (owner) {
      tx.set(db.doc(`notifications/notif_dep_expire_${id}`), {
        uid: owner,
        userId: owner,
        title: 'Deposit request expired',
        message: 'Your P2P deposit request was cancelled because it was still open after 24 hours.',
        type: 'deposit_expired',
        createdAt: now,
        read: false,
      });
    }
    tx.set(db.doc(`staff_audit_log/p2p_expire_dep_${id}`), {
      action: 'expireP2pDeposit',
      actorUid: 'system',
      actorRole: 'system',
      depositId: id,
      owner,
      amount: Number(cur.amount ?? 0),
      reason: P2P_EXPIRE_REASON,
      refunded: 0,
      createdAt: now,
    });
    return { ok: true as const };
  });
}

/**
 * Cancels P2P deposits and withdrawals still waiting after 24h.
 * Withdrawals use the owner-cancel transaction (refund once when balanceDeducted).
 * Deposits never credited a wallet, so expiry only closes the request, ledger row, and audit log.
 * Skips proof-submitted, confirmed, and already-cancelled rows.
 */
export async function expireStaleP2p(deps: Deps, opts: { limit?: number; maxAgeMs?: number } = {}) {
  const limit = opts.limit ?? BATCH;
  const maxAge = opts.maxAgeMs ?? P2P_EXPIRE_MS;
  const cutoff = deps.now() - maxAge;
  const { db } = deps;
  const [withdrawals, deposits] = await Promise.all([
    stale(db, 'withdrawal_requests', CANCELLABLE, cutoff, limit),
    stale(db, 'deposit_requests', DEPOSIT_EXPIRE_STATUSES, cutoff, limit),
  ]);

  let withdrawalsExpired = 0;
  let depositsExpired = 0;
  for (const doc of withdrawals) {
    const data = doc.data();
    if (String(data.method ?? '').toLowerCase() === 'solana' || data.payoutMethod === 'Solana') continue;
    if (httpsProof(data)) continue;
    if (data.payoutState === 'sent' || data.payoutState === 'failed') continue;
    try {
      const res = await cancelP2pCashout(deps, { id: doc.id, reason: P2P_EXPIRE_REASON, enforceOwner: false, audit: true });
      if (!res.alreadyDone) withdrawalsExpired += 1;
    } catch {
      // Claimed, confirmed, or already settled between the query and the transaction.
    }
  }
  for (const doc of deposits) {
    const res = await expireDeposit(deps, doc.id, cutoff);
    if ('ok' in res && res.ok) depositsExpired += 1;
  }
  return { withdrawalsExpired, depositsExpired, scannedWithdrawals: withdrawals.length, scannedDeposits: deposits.length };
}
