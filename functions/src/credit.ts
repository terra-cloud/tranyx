import { HttpsError } from 'firebase-functions/https';
import * as logger from 'firebase-functions/logger';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { PublicKey } from '@solana/web3.js';
import { getAssociatedTokenAddressSync } from '@solana/spl-token';
import bs58 from 'bs58';
import type { RateProvider } from './rates';

/**
 * Server-side crediting of on-chain payments (replaces the client-side marker transactions).
 *
 * The client sends only { signature, kind, plan? }. Everything money-related is derived here:
 *   - the transaction is read from the cluster at FINALIZED commitment (never trusted from the client),
 *   - the payer must be the caller's linked wallet and the destination the treasury (SOL) or the
 *     treasury USDT ATA of the configured mint (USDT); the paid amount is the on-chain amount,
 *   - the PHP value is recomputed from a server-side rate, and
 *   - markers + credit + pending record are written in ONE Admin SDK transaction (create-only markers).
 */

export type CreditKind = 'deposit_sol' | 'deposit_usdt' | 'subscription_sol';
export type Plan = 'monthly' | 'yearly';

export interface Log {
  warn(msg: string, data?: Record<string, unknown>): void;
  error(msg: string, data?: Record<string, unknown>): void;
}

/** Reads a transaction (jsonParsed) at finalized commitment. null = not found / not finalized yet. */
export interface ChainReader {
  getFinalizedTransaction(signature: string): Promise<Record<string, any> | null>;
}

export interface CreditDeps {
  db: Firestore;
  chain: ChainReader;
  rates: RateProvider;
  now: () => number;
  /** Treasury public key (functions param); falls back to system_config/treasury when empty. */
  treasuryPublicKey: string;
  usdtMint: string;
  log?: Log;
}

export interface CallerAuth {
  uid: string;
}

export type CreditStatus =
  | 'credited'
  | 'already_processed'
  | 'held_by_another_account'
  | 'not_finalized'
  | 'rejected';

export interface CreditResult {
  status: CreditStatus;
  kind: CreditKind;
  signature: string;
  /** Fixed reason code for 'rejected' (never internal error text). */
  reason?: RejectReason;
  phpAmount?: number;
  cryptoAmount?: number;
  currency?: 'SOL' | 'USDT';
  plan?: Plan;
  premiumUntil?: number;
}

export type RejectReason =
  | 'WALLET_NOT_LINKED'
  | 'WALLET_LINKED_TO_ANOTHER_ACCOUNT'
  | 'TX_FAILED'
  | 'NOT_SIGNED_BY_LINKED_WALLET'
  | 'NO_MATCHING_TRANSFER'
  | 'AMOUNT_TOO_SMALL'
  | 'AMOUNT_TOO_LARGE'
  | 'PLAN_PRICE_NOT_MET'
  | 'CREDIT_DISABLED';

/**
 * Error message prefix for a deposit from a wallet that was linked without a signature proof. The apps
 * look for this code, send the user through the one-time "Verify wallet" signature, then retry.
 */
export const WALLET_NOT_VERIFIED = 'WALLET_NOT_VERIFIED';

const SIG_RE = /^[1-9A-HJ-NP-Za-km-z]{80,90}$/;
const KINDS: readonly CreditKind[] = ['deposit_sol', 'deposit_usdt', 'subscription_sol'];
const LAMPORTS_PER_SOL = 1e9;
const USDT_DECIMALS = 1e6;
const DAY_MS = 24 * 3600 * 1000;
const HOUR_MS = 3600 * 1000;

/** Optional `config/credit` (admin-only in rules). Every field validated; bad values fall back. */
export interface CreditConfig {
  enabled: boolean;
  minPhp: number;
  maxPhp: number;
  /** Paid value may be this fraction below the plan price (rate movement between quote and send). */
  planTolerance: number;
  monthlyPhp: number;
  yearlyPhp: number;
  hourlyAttempts: number;
  solPhpMin: number;
  solPhpMax: number;
  usdtPhpMin: number;
  usdtPhpMax: number;
}
export const DEFAULT_CREDIT_CONFIG: CreditConfig = {
  enabled: true,
  minPhp: 1,
  maxPhp: 500_000,
  planTolerance: 0.05,
  monthlyPhp: 299,
  yearlyPhp: 2999,
  hourlyAttempts: 30,
  solPhpMin: 100,
  solPhpMax: 1_000_000,
  usdtPhpMin: 40,
  usdtPhpMax: 80,
};
const num = (v: unknown, d: number, min: number, max: number) =>
  typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max ? v : d;

export async function loadCreditConfig(db: Firestore): Promise<CreditConfig> {
  const snap = await db.doc('config/credit').get();
  const d = (snap.exists ? snap.data() : {}) ?? {};
  const c = DEFAULT_CREDIT_CONFIG;
  return {
    enabled: d.enabled !== false,
    minPhp: num(d.minPhp, c.minPhp, 0.01, 1e9),
    maxPhp: num(d.maxPhp, c.maxPhp, 1, 1e10),
    planTolerance: num(d.planTolerance, c.planTolerance, 0, 0.5),
    monthlyPhp: num(d.monthlyPhp, c.monthlyPhp, 1, 1e9),
    yearlyPhp: num(d.yearlyPhp, c.yearlyPhp, 1, 1e9),
    hourlyAttempts: num(d.hourlyAttempts, c.hourlyAttempts, 1, 10_000),
    solPhpMin: num(d.solPhpMin, c.solPhpMin, 0.0001, 1e12),
    solPhpMax: num(d.solPhpMax, c.solPhpMax, 0.0001, 1e12),
    usdtPhpMin: num(d.usdtPhpMin, c.usdtPhpMin, 0.0001, 1e9),
    usdtPhpMax: num(d.usdtPhpMax, c.usdtPhpMax, 0.0001, 1e9),
  };
}

// ── ids and shapes (kept identical to packages/shared/lib/src/onchain_credit.dart) ──────────────
export const onchainMarkerId = (sig: string) => `onchain_${sig}`;
export const pendingOnchainId = (uid: string, sig: string) => `pending_onchain_${uid}_${sig}`;
export const perFlowMarkerId = (kind: CreditKind, sig: string) =>
  `${kind === 'deposit_sol' ? 'deposit_sol_' : kind === 'deposit_usdt' ? 'deposit_usdt_' : 'sub_sol_'}${sig}`;
export const MARKER_HELD_NOTE = 'marker held by another account';
const rejectedNote = (r: RejectReason | typeof WALLET_NOT_VERIFIED) => `rejected by server: ${r}`;

/** Subscription expiry extends from max(now, current premiumUntil). */
export function nextPremiumUntilMs(currentMs: number | null | undefined, nowMs: number, plan: Plan): number {
  const days = plan === 'yearly' ? 365 : 30;
  const cur = typeof currentMs === 'number' && Number.isFinite(currentMs) ? currentMs : 0;
  return Math.max(cur, nowMs) + days * DAY_MS;
}

export interface CreditInput {
  signature: string;
  kind: CreditKind;
  plan?: Plan;
}

/** Only these client fields are read. Client-sent amounts, wallets, rates or markers are ignored. */
export function parseCreditInput(data: unknown): CreditInput {
  const d = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  const signature = typeof d.signature === 'string' ? d.signature.trim() : '';
  if (!SIG_RE.test(signature)) throw new HttpsError('invalid-argument', 'signature is not a valid Solana signature.');
  try {
    if (bs58.decode(signature).length !== 64) throw new Error('len');
  } catch {
    throw new HttpsError('invalid-argument', 'signature is not a valid Solana signature.');
  }
  const kind = d.kind as CreditKind;
  if (!KINDS.includes(kind)) throw new HttpsError('invalid-argument', 'kind must be deposit_sol, deposit_usdt or subscription_sol.');
  const out: CreditInput = { signature, kind };
  if (kind === 'subscription_sol') {
    if (d.plan !== 'monthly' && d.plan !== 'yearly') throw new HttpsError('invalid-argument', "plan must be 'monthly' or 'yearly'.");
    out.plan = d.plan;
  }
  return out;
}

// ── on-chain verification ──────────────────────────────────────────────────────────────────────
export type Verified =
  | { ok: true; baseUnits: number }
  | { ok: false; reason: RejectReason };

const asInt = (v: unknown): number | null => {
  if (typeof v === 'number' && Number.isSafeInteger(v)) return v;
  if (typeof v === 'string' && /^\d+$/.test(v)) {
    const n = Number(v);
    return Number.isSafeInteger(n) ? n : null;
  }
  return null;
};

/**
 * Checks a jsonParsed `getTransaction` result. Sums every top-level transfer from `wallet` to the
 * treasury (SOL: system transfer to the treasury; USDT: spl-token transfer / transferChecked to the
 * treasury's ATA for `mint`, authority = wallet). The tx must have succeeded and `wallet` must have signed.
 */
export function verifyTransfer(
  tx: Record<string, any>,
  kind: CreditKind,
  wallet: string,
  treasury: string,
  treasuryUsdtAta: string,
  mint: string,
): Verified {
  if (!tx.meta || tx.meta.err != null) return { ok: false, reason: 'TX_FAILED' };
  const message = tx.transaction?.message;
  if (!message) return { ok: false, reason: 'NO_MATCHING_TRANSFER' };
  const keys: any[] = Array.isArray(message.accountKeys) ? message.accountKeys : [];
  if (!keys.some((k) => k && k.pubkey === wallet && k.signer === true)) {
    return { ok: false, reason: 'NOT_SIGNED_BY_LINKED_WALLET' };
  }
  let total = 0;
  for (const ix of Array.isArray(message.instructions) ? message.instructions : []) {
    const info = ix?.parsed?.info;
    const type = ix?.parsed?.type;
    if (!info || typeof info !== 'object') continue;
    if (kind !== 'deposit_usdt') {
      if (ix.program === 'system' && type === 'transfer' && info.source === wallet && info.destination === treasury) {
        const l = asInt(info.lamports);
        if (l !== null && l > 0) total += l;
      }
    } else if (ix.program === 'spl-token' && (type === 'transfer' || type === 'transferChecked')) {
      const authority = info.authority ?? info.multisigAuthority;
      const amount = type === 'transferChecked' ? asInt(info.tokenAmount?.amount) : asInt(info.amount);
      // The destination is pinned to the treasury's ATA for `mint`, which also pins the mint of a plain
      // `transfer`; transferChecked must additionally name the mint.
      if (
        authority === wallet &&
        info.destination === treasuryUsdtAta &&
        amount !== null &&
        amount > 0 &&
        (type === 'transfer' || info.mint === mint)
      ) {
        total += amount;
      }
    }
  }
  return total > 0 ? { ok: true, baseUnits: total } : { ok: false, reason: 'NO_MATCHING_TRANSFER' };
}

/** Treasury public key: functions param first, then system_config/treasury (Admin SDK only). */
export async function resolveTreasury(db: Firestore, param: string): Promise<string> {
  const candidates: string[] = [param];
  if (!param) {
    const s = await db.doc('system_config/treasury').get();
    const d = s.data() ?? {};
    candidates.push(d.publicKey, d.solanaTreasuryPubkey);
  }
  for (const c of candidates) {
    if (typeof c === 'string' && c) {
      try {
        return new PublicKey(c).toBase58();
      } catch {
        /* try next */
      }
    }
  }
  throw new HttpsError('failed-precondition', 'Treasury wallet is not configured.');
}

const logOf = (d: CreditDeps): Log => d.log ?? (logger as unknown as Log);
const safeDetail = (v: unknown) => String(v instanceof Error ? v.message : v).replace(/https?:\/\/\S+/gi, '[url]').slice(0, 300);

/** Leaves the caller's pending record open with a note (creates a minimal one when missing). Never touches `done`. */
async function notePending(deps: CreditDeps, uid: string, sig: string, kind: CreditKind, note: string) {
  try {
    const ref = deps.db.doc(`transactions/${pendingOnchainId(uid, sig)}`);
    await deps.db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      if (!s.exists) {
        tx.set(ref, {
          uid,
          type: 'onchain_pending',
          kind: kind === 'subscription_sol' ? 'subscription' : 'deposit',
          status: 'pending',
          solanaTxSignature: sig,
          startedAt: deps.now(),
          note,
        });
      } else if (s.get('status') !== 'done') {
        tx.update(ref, { note });
      }
    });
  } catch (e) {
    logOf(deps).warn('credit: could not note pending record', { detail: safeDetail(e) });
  }
}

/** Per-uid hourly attempt budget so the callable cannot be used to burn RPC quota. */
async function takeAttempt(deps: CreditDeps, uid: string, cfg: CreditConfig) {
  const bucket = Math.floor(deps.now() / HOUR_MS);
  const ref = deps.db.doc(`credit_usage/${uid}_${bucket}`);
  await deps.db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const n = s.exists ? Number(s.get('count') ?? 0) : 0;
    if (n + 1 > cfg.hourlyAttempts) throw new HttpsError('resource-exhausted', 'Too many attempts. Try again later.');
    tx.set(ref, { uid, count: n + 1, bucket });
  });
}

const floorCents = (v: number) => Math.floor(v * 100 + 1e-9) / 100;

export async function processCredit(deps: CreditDeps, auth: CallerAuth | undefined, data: unknown): Promise<CreditResult> {
  if (!auth?.uid) throw new HttpsError('unauthenticated', 'Sign in to continue.');
  const uid = auth.uid;
  const input = parseCreditInput(data);
  const { signature: sig, kind } = input;
  const db = deps.db;
  const base = { kind, signature: sig };
  const cfg = await loadCreditConfig(db);
  if (!cfg.enabled) throw new HttpsError('failed-precondition', 'Crediting is temporarily disabled.');

  // Cheap replay answer before any RPC: this account already holds the shared marker.
  const early = await db.doc(`transactions/${onchainMarkerId(sig)}`).get();
  if (early.exists) {
    return { ...base, status: early.get('uid') === uid ? 'already_processed' : 'held_by_another_account' } as CreditResult;
  }

  await takeAttempt(deps, uid, cfg);

  const userSnap = await db.doc(`users/${uid}`).get();
  if (!userSnap.exists) throw new HttpsError('failed-precondition', 'Profile not found.');
  const u = userSnap.data() ?? {};
  if (u.banned === true || (typeof u.suspendedUntil === 'number' && u.suspendedUntil > deps.now())) {
    throw new HttpsError('permission-denied', 'This account cannot be credited.');
  }
  const wallet = String(u.walletPublicKey || '');
  try {
    new PublicKey(wallet);
  } catch {
    return reject(deps, uid, base, 'WALLET_NOT_LINKED');
  }
  // The wallet index (one wallet per account) must not name a different owner.
  const link = await db.doc(`walletLinks/${wallet}`).get();
  if (link.exists && link.get('uid') !== uid) return reject(deps, uid, base, 'WALLET_LINKED_TO_ANOTHER_ACCOUNT');

  // Only a wallet the caller PROVED (signed the walletAuth challenge) may be credited. `walletLinks` and
  // `users.walletPublicKey` are client-writable claims; `wallet_verified` is written by walletAuthLink only.
  const verified = await db.doc(`wallet_verified/${wallet}`).get();
  if (!verified.exists || verified.get('uid') !== uid) {
    await notePending(deps, uid, sig, kind, rejectedNote(WALLET_NOT_VERIFIED));
    throw new HttpsError('failed-precondition', `${WALLET_NOT_VERIFIED}: Verify your wallet once in Profile (one signature, no fee), then your payment will be credited.`);
  }

  const treasury = await resolveTreasury(db, deps.treasuryPublicKey);
  const treasuryAta = getAssociatedTokenAddressSync(new PublicKey(deps.usdtMint), new PublicKey(treasury), true).toBase58();

  const tx = await deps.chain.getFinalizedTransaction(sig);
  if (!tx) return { ...base, status: 'not_finalized' };

  const v = verifyTransfer(tx, kind, wallet, treasury, treasuryAta, deps.usdtMint);
  if (!v.ok) return reject(deps, uid, base, v.reason);

  // Server-side rate (same sources the apps used), sanity-banded.
  const rates = await deps.rates();
  const isUsdt = kind === 'deposit_usdt';
  const rate = isUsdt ? rates.usdtPhp : rates.solPhp;
  const [lo, hi] = isUsdt ? [cfg.usdtPhpMin, cfg.usdtPhpMax] : [cfg.solPhpMin, cfg.solPhpMax];
  if (!(rate >= lo && rate <= hi)) {
    logOf(deps).error('credit: rate outside sanity band', { kind, rate });
    throw new HttpsError('unavailable', 'Exchange rate unavailable. Try again shortly.');
  }
  const cryptoAmount = isUsdt ? v.baseUnits / USDT_DECIMALS : v.baseUnits / LAMPORTS_PER_SOL;
  const phpAmount = floorCents(cryptoAmount * rate);
  if (phpAmount < cfg.minPhp) return reject(deps, uid, base, 'AMOUNT_TOO_SMALL');
  if (phpAmount > cfg.maxPhp) return reject(deps, uid, base, 'AMOUNT_TOO_LARGE');
  const currency = isUsdt ? 'USDT' : 'SOL';

  let plan: Plan | undefined;
  if (kind === 'subscription_sol') {
    plan = input.plan!;
    const price = plan === 'yearly' ? cfg.yearlyPhp : cfg.monthlyPhp;
    if (phpAmount < price * (1 - cfg.planTolerance)) return reject(deps, uid, base, 'PLAN_PRICE_NOT_MET');
  }

  const markerId = perFlowMarkerId(kind, sig);
  const onchainRef = db.doc(`transactions/${onchainMarkerId(sig)}`);
  const markerRef = db.doc(`transactions/${markerId}`);
  const pendingRef = db.doc(`transactions/${pendingOnchainId(uid, sig)}`);
  const userRef = db.doc(`users/${uid}`);

  return db.runTransaction(async (t) => {
    const now = deps.now();
    // Reads first, shared marker before anything else.
    const [onchainSnap, markerSnap, userNow, pendingSnap] = await Promise.all([
      t.get(onchainRef),
      t.get(markerRef),
      t.get(userRef),
      t.get(pendingRef),
    ]);
    const heldNote = () => {
      if (!pendingSnap.exists) {
        t.set(pendingRef, {
          uid, type: 'onchain_pending', kind: kind === 'subscription_sol' ? 'subscription' : 'deposit',
          status: 'pending', solanaTxSignature: sig, startedAt: now, note: MARKER_HELD_NOTE,
        });
      } else if (pendingSnap.get('status') !== 'done') {
        t.update(pendingRef, { note: MARKER_HELD_NOTE });
      }
      return { ...base, status: 'held_by_another_account' as const };
    };
    if (onchainSnap.exists) {
      return onchainSnap.get('uid') === uid ? { ...base, status: 'already_processed' as const } : heldNote();
    }
    if (markerSnap.exists) {
      return markerSnap.get('uid') === uid ? { ...base, status: 'already_processed' as const } : heldNote();
    }
    if (!userNow.exists) throw new HttpsError('failed-precondition', 'Profile not found.');

    let premiumUntil: number | undefined;
    if (kind === 'subscription_sol') {
      premiumUntil = nextPremiumUntilMs(userNow.get('premiumUntil'), now, plan!);
      t.update(userRef, {
        isPremium: true,
        premiumUntil,
        accountType: 'hybrid',
        subscriptionPlan: plan,
        subscriptionStartedAt: now,
        subscriptionPaymentMethod: 'Solana (SOL)',
        subscriptionPaymentAmount: phpAmount,
        subscriptionTxId: sig,
        subscriptionStatus: 'active',
        pendingSubscription: null,
      });
      t.create(markerRef, {
        uid,
        type: 'subscription',
        amount: phpAmount,
        title: `Hybrid PRO Subscription (${plan === 'yearly' ? 'Yearly' : 'Monthly'})`,
        desc: `Subscribed via Solana (${cryptoAmount.toFixed(4)} SOL), verified on-chain`,
        method: 'Solana',
        status: 'Successful',
        solanaTxSignature: sig,
        verifiedOnChain: true,
        createdAt: now,
      });
    } else {
      t.update(userRef, { tyxBalance: FieldValue.increment(phpAmount) });
      t.create(markerRef, {
        uid,
        type: 'deposit',
        amount: phpAmount,
        title: `Wallet Top-Up (${currency} via Solana)`,
        desc: isUsdt
          ? `Crypto deposit of $${cryptoAmount.toFixed(2)} USDT, verified on-chain`
          : `Crypto deposit of ${cryptoAmount.toFixed(4)} SOL, verified on-chain`,
        method: 'Solana',
        status: 'Successful',
        solanaTxSignature: sig,
        ...(isUsdt ? { currency: 'USDT' } : {}),
        verifiedOnChain: true,
        createdAt: now,
      });
    }
    // Exactly the five keys the rules/clients know on onchain_<sig>.
    t.create(onchainRef, {
      uid,
      type: 'onchain_marker',
      solanaTxSignature: sig,
      markerId,
      markedAt: now,
    });
    if (pendingSnap.exists) t.update(pendingRef, { status: 'done', completedAt: now });
    return {
      ...base,
      status: 'credited' as const,
      phpAmount,
      cryptoAmount,
      currency: currency as 'SOL' | 'USDT',
      ...(plan ? { plan } : {}),
      ...(premiumUntil ? { premiumUntil } : {}),
    };
  });
}

async function reject(deps: CreditDeps, uid: string, base: { kind: CreditKind; signature: string }, reason: RejectReason): Promise<CreditResult> {
  await notePending(deps, uid, base.signature, base.kind, rejectedNote(reason));
  return { ...base, status: 'rejected', reason };
}
