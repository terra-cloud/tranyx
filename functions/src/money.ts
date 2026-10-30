import { HttpsError } from 'firebase-functions/https';
import type { DocumentReference, Firestore, Transaction } from 'firebase-admin/firestore';

/**
 * Phase 4 shared helpers: every client-side balance write for subscriptions, rentals, properties and
 * jobs now goes through callables built on these. Rules (ad3ec01): users/{uid}.tyxBalance and
 * reservedBalance are Admin-SDK / staff only, and so are the escrow docs these callables own.
 *
 * Contract for every money callable:
 *  - the client sends ids + an idempotencyKey + intent only; amounts, fees, rates come from authoritative docs here
 *  - ONE Firestore transaction: reads first, checks, then all writes (balance, escrow, ledger, op record)
 *  - status guards (escrow Held -> Released | Refunded) so a refund / payout can happen at most once
 *  - replay of the same idempotencyKey returns the stored result without touching money again
 *  - errors to the client are generic HttpsError codes; detail goes to Cloud Logging
 */

export interface MoneyDeps {
  db: Firestore;
  now: () => number;
}

export interface CallerAuth {
  uid: string;
  token?: Record<string, unknown>;
}

export const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

export function numOf(v: unknown, fallback = 0): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}

export function str(v: unknown, max = 200): string {
  return typeof v === 'string' ? v.trim().slice(0, max) : '';
}

const KEY_RE = /^[A-Za-z0-9_-]{8,64}$/;

export function requireAuth(auth: CallerAuth | undefined): string {
  if (!auth?.uid) throw new HttpsError('unauthenticated', 'Sign in to continue.');
  return auth.uid;
}

export function parseKey(v: unknown): string {
  const k = str(v, 64);
  if (!KEY_RE.test(k)) throw new HttpsError('invalid-argument', 'idempotencyKey must be 8-64 characters (letters, digits, _ or -).');
  return k;
}

export function parseId(v: unknown, label: string): string {
  const s = str(v, 128);
  if (!s || s.includes('/')) throw new HttpsError('invalid-argument', `${label} is invalid.`);
  return s;
}

const STAFF_ROLES = ['admin', 'staff', 'support', 'agent', 'p2p_agent', 'super_admin', 'superadmin'];

export function tokenIsStaff(token: Record<string, unknown> | undefined): boolean {
  if (!token) return false;
  if (token.admin === true || token.superadmin === true) return true;
  return typeof token.role === 'string' && STAFF_ROLES.includes(token.role.toLowerCase());
}

/** Staff = admin/staff token claim, or the same flags the rules read from users/{uid}. */
export function userDocIsStaff(u: Record<string, unknown> | undefined): boolean {
  if (!u) return false;
  if (u.isAdmin === true || u.isStaff === true || u.isSuperAdmin === true || u.isP2pAgent === true) return true;
  return typeof u.role === 'string' && STAFF_ROLES.includes(u.role.toLowerCase());
}

// ── idempotency ────────────────────────────────────────────────────────────────────────────────
const opRef = (db: Firestore, uid: string, key: string) => db.doc(`money_ops/${uid}_${key}`);

export async function readOp(tx: Transaction, db: Firestore, uid: string, key: string): Promise<Record<string, unknown> | null> {
  const s = await tx.get(opRef(db, uid, key));
  return s.exists ? ((s.get('result') as Record<string, unknown>) ?? { ok: true }) : null;
}

export function writeOp(tx: Transaction, db: Firestore, uid: string, key: string, action: string, result: Record<string, unknown>, now: number) {
  tx.create(opRef(db, uid, key), { uid, action, result, createdAt: now });
}

// ── wallet accumulator ─────────────────────────────────────────────────────────────────────────
interface Slot {
  ref: DocumentReference;
  exists: boolean;
  balance: number;
  reserved: number;
  start: number;
  data: Record<string, unknown>;
}

/**
 * Loads users in the read phase, applies credits / debits in memory, writes once in flush().
 * Debits respect reservedBalance (available = balance - reserved) and can never go negative.
 */
export class Wallet {
  private slots = new Map<string, Slot>();
  constructor(private tx: Transaction, private db: Firestore) {}

  async load(uid: string): Promise<Record<string, unknown>> {
    const hit = this.slots.get(uid);
    if (hit) return hit.data;
    const ref = this.db.doc(`users/${uid}`);
    const snap = await this.tx.get(ref);
    const data = (snap.exists ? snap.data() : {}) as Record<string, unknown>;
    const balance = numOf(data.tyxBalance);
    this.slots.set(uid, { ref, exists: snap.exists, balance, reserved: numOf(data.reservedBalance), start: balance, data });
    return data;
  }

  private slot(uid: string): Slot {
    const s = this.slots.get(uid);
    if (!s) throw new Error(`wallet ${uid} not loaded`);
    return s;
  }

  exists(uid: string) { return this.slot(uid).exists; }
  balance(uid: string) { return this.slot(uid).balance; }
  available(uid: string) { const s = this.slot(uid); return Math.max(0, round2(s.balance - s.reserved)); }

  debit(uid: string, amount: number) {
    const s = this.slot(uid);
    if (!s.exists) throw new HttpsError('failed-precondition', 'Profile not found.');
    if (!(amount >= 0) || !Number.isFinite(amount)) throw new HttpsError('invalid-argument', 'Invalid amount.');
    if (round2(s.balance - s.reserved) + 1e-9 < amount) {
      throw new HttpsError('failed-precondition', 'Insufficient available balance.', { code: 'INSUFFICIENT_BALANCE' });
    }
    s.balance = round2(s.balance - amount);
  }

  credit(uid: string, amount: number) {
    const s = this.slot(uid);
    if (!s.exists) throw new HttpsError('failed-precondition', 'Recipient profile not found.');
    if (!(amount >= 0) || !Number.isFinite(amount)) throw new HttpsError('invalid-argument', 'Invalid amount.');
    s.balance = round2(s.balance + amount);
  }

  flush(extra?: Record<string, Record<string, unknown>>) {
    for (const [uid, s] of this.slots) {
      const patch = extra?.[uid];
      if (s.balance !== s.start || patch) this.tx.update(s.ref, { ...(s.balance !== s.start ? { tyxBalance: s.balance } : {}), ...(patch ?? {}) });
    }
  }
}

/** Ledger entry in `transactions/{id}` (what clients list). Deterministic ids keep replays single-write. */
export function ledger(tx: Transaction, db: Firestore, id: string, uid: string, now: number, body: Record<string, unknown>) {
  tx.set(db.doc(`transactions/${id}`), { id, uid, method: 'Tranyx Wallet', status: 'Completed', createdAt: now, ...body });
}

export function notify(tx: Transaction, db: Firestore, uid: string, now: number, title: string, message: string, tag: string) {
  const id = `notif_${now}_${tag}_${uid.slice(0, 6)}`;
  tx.set(db.doc(`notifications/${id}`), { id, uid, userId: uid, title, message, read: false, isRead: false, createdAt: now, timestamp: now });
}
