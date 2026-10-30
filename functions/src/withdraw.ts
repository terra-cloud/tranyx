import { HttpsError } from 'firebase-functions/https';
import * as logger from 'firebase-functions/logger';
import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { PublicKey } from '@solana/web3.js';
import { loadConfig } from './config';
import type { RateProvider } from './rates';
import type { Coin, SolanaPayer } from './solana';

/**
 * KAN-146: server-side withdrawals. Order of operations for every call:
 *   1. checks   (auth, input, limits, balance, rentals)      \  ONE Firestore transaction
 *   2. effects  (debit tyxBalance, write request + ledger)   /  (status 'pending', doc id = idempotency key)
 *   3. interaction (on-chain transfer) only AFTER the commit, via a guarded state machine:
 *
 *      pending --claim--> submitting --broadcast ok--> sent
 *                              |  \--ambiguous/timeout--> pending_confirmation --reconcile--> sent | failed(refund)
 *                              \--outcome failed/expired--------------------------------------> failed(refund)
 *
 * Refund happens ONLY inside a transaction guarded on payoutState, so it can happen at most once and
 * never after a send that actually landed. P2P (GCash/Maya) stays manual review: debit + request
 * (status WAITING_FOR_AGENT), no on-chain interaction.
 */

export interface Log {
  warn(msg: string, data?: Record<string, unknown>): void;
  error(msg: string, data?: Record<string, unknown>): void;
}

export interface Deps {
  db: Firestore;
  /** Defaults to Cloud Logging. Tests inject a spy. */
  log?: Log;
  /** Min ms between two counted 'not found past expiry' observations (default 60s). */
  expiryGapMs?: number;
  /** Lazily created so a missing secret only affects Solana sends, not P2P. */
  payer: () => SolanaPayer;
  rates: RateProvider;
  now: () => number;
}

export interface CallerAuth {
  uid: string;
  token?: { email?: string; email_verified?: boolean };
}

export type PayoutState =
  | 'manual_review'
  | 'pending'
  | 'submitting'
  | 'pending_confirmation'
  | 'sent'
  | 'failed';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MANILA_OFFSET_MS = 8 * 3600 * 1000;
const IN_FLIGHT: PayoutState[] = ['submitting', 'pending_confirmation'];
/** K4: a transfer is only declared "never landed" after this many separate reconciler observations. */
export const EXPIRY_OBSERVATIONS_REQUIRED = 2;
const DEFAULT_EXPIRY_GAP_MS = 60_000;
/** After an expiry refund, keep watching the signature this long for a late confirm. */
export const LATE_WATCH_MS = 7 * 24 * 3600 * 1000;
const logOf = (deps: Deps): Log => deps.log ?? (logger as unknown as Log);

/**
 * K6: failureReason / lastError are stored in client-readable docs and returned to callers, so they are
 * fixed codes only. The underlying error text goes to Cloud Logging (with URLs, which may carry RPC api
 * keys, stripped).
 */
export type FailureCode = 'PREPARE_FAILED' | 'ONCHAIN_ERROR' | 'EXPIRED_NOT_LANDED' | 'WITHDRAWAL_FAILED';
export const FAILURE_CODES: readonly string[] = ['PREPARE_FAILED', 'ONCHAIN_ERROR', 'EXPIRED_NOT_LANDED', 'WITHDRAWAL_FAILED'];
const AMBIGUOUS_CODE = 'BROADCAST_AMBIGUOUS';
const safeDetail = (v: unknown) =>
  String(v instanceof Error ? v.message : v).replace(/https?:\/\/\S+/gi, '[url]').slice(0, 300);

export interface WithdrawInput {
  key: string;
  method: 'solana' | 'p2p';
  amountCents: number;
  coin?: Coin;
  p2p?: { paymentMethod: 'GCash' | 'Maya'; accountName: string; accountNumber: string; qrUrl: string };
}

function str(v: unknown, max: number): string {
  return typeof v === 'string' ? v.trim().slice(0, max) : '';
}

/** Only these client fields are ever read. Any client-sent fee/net/rate/crypto/wallet/status is ignored. */
export function parseInput(data: unknown): WithdrawInput {
  const d = (data && typeof data === 'object' ? data : {}) as Record<string, any>;
  const key = str(d.idempotencyKey, 64);
  if (!UUID_RE.test(key)) throw new HttpsError('invalid-argument', 'idempotencyKey must be a UUID.');
  const method = d.method === 'p2p' ? 'p2p' : d.method === 'solana' ? 'solana' : null;
  if (!method) throw new HttpsError('invalid-argument', "method must be 'solana' or 'p2p'.");
  const amount = d.amount;
  if (typeof amount !== 'number' || !Number.isFinite(amount) || amount <= 0) {
    throw new HttpsError('invalid-argument', 'amount must be a positive number.');
  }
  const amountCents = Math.round(amount * 100);
  if (Math.abs(amount * 100 - amountCents) > 1e-6 || amountCents <= 0) {
    throw new HttpsError('invalid-argument', 'amount must have at most 2 decimal places.');
  }
  const out: WithdrawInput = { key, method, amountCents };
  if (method === 'solana') {
    if (d.coin !== 'SOL' && d.coin !== 'USDT') throw new HttpsError('invalid-argument', "coin must be 'SOL' or 'USDT'.");
    out.coin = d.coin;
  } else {
    const p = (d.p2p ?? {}) as Record<string, unknown>;
    const pm = p.paymentMethod;
    if (pm !== 'GCash' && pm !== 'Maya') throw new HttpsError('invalid-argument', "paymentMethod must be 'GCash' or 'Maya'.");
    const accountName = str(p.accountName, 100);
    const accountNumber = str(p.accountNumber, 50);
    if (!accountName) throw new HttpsError('invalid-argument', 'Recipient account name is required.');
    if (!accountNumber) throw new HttpsError('invalid-argument', 'Recipient account number is required.');
    const qrUrl = str(p.qrUrl, 500);
    if (qrUrl && !/^https:\/\//i.test(qrUrl)) throw new HttpsError('invalid-argument', 'qrUrl must be https.');
    out.p2p = { paymentMethod: pm, accountName, accountNumber, qrUrl };
  }
  return out;
}

const php = (cents: number) => cents / 100;

function manilaDay(ms: number): string {
  return new Date(ms + MANILA_OFFSET_MS).toISOString().slice(0, 10);
}

const reqRef = (db: Firestore, key: string) => db.doc(`withdrawal_requests/${key}`);
const mirrorRef = (db: Firestore, key: string) => db.doc(`withdrawalRequests/${key}`);

function ledgerRefs(db: Firestore, d: { id: string; uid: string; method: string }) {
  return d.method === 'p2p'
    ? [db.doc(`transactions/p2p_with_${d.id}`), db.doc(`wallets/${d.uid}/transactions/${d.id}`)]
    : [db.doc(`transactions/wd_${d.id}`), db.doc(`wallets/${d.uid}/transactions/${d.id}`)];
}

function publicResult(d: Record<string, any>, replay: boolean, newBalance?: number, mismatch = false) {
  return {
    ok: d.payoutState !== 'failed',
    id: d.id,
    method: d.method,
    status: d.status,
    payoutState: d.payoutState,
    amount: d.amount,
    feeRate: d.feeRate,
    feeAmount: d.feeAmount,
    netAmount: d.netAmount,
    rate: d.rate ?? null,
    coin: d.coin ?? null,
    cryptoAmount: d.cryptoAmount ?? null,
    solanaTxSignature: d.solanaTxSignature ?? null,
    failureReason: d.payoutState === 'failed' ? (FAILURE_CODES.includes(d.failureReason) ? d.failureReason : 'WITHDRAWAL_FAILED') : null,
    idempotentReplay: replay,
    // K10: a replay with the same key but different parameters returns the ORIGINAL record; say so explicitly.
    idempotencyMismatch: mismatch,
    ...(newBalance !== undefined ? { newBalance } : {}),
  };
}

const HOUR_MS = 3600 * 1000;
const walletStateRef = (db: Firestore, uid: string) => db.doc(`payout_wallet_state/${uid}`);

/**
 * Payout-wallet cooldown. `users/{uid}.walletPublicKey` is owner-writable, so an account takeover (or a
 * script) could repoint it and cash out in one request. The server therefore keeps its OWN record,
 * `payout_wallet_state/{uid}` = { wallet, since } (server-only), and a Solana withdrawal is allowed only
 * once the profile wallet has matched that record for `walletCooldownHours`. Any change of wallet restarts
 * the clock, so the first request after a change records it and is refused.
 */
async function observePayoutWallet(deps: Deps, uid: string): Promise<void> {
  const { db } = deps;
  await db.runTransaction(async (tx) => {
    const ref = walletStateRef(db, uid);
    const [u, st] = await Promise.all([tx.get(db.doc(`users/${uid}`)), tx.get(ref)]);
    const w = String(u.get('walletPublicKey') || u.get('solanaWalletAddress') || u.get('walletAddress') || '');
    if (!w) return;
    if (!st.exists || st.get('wallet') !== w) tx.set(ref, { uid, wallet: w, since: deps.now() });
  });
}

function assertWalletCooldown(now: number, cfg: { walletCooldownHours: number }, wallet: string, st: FirebaseFirestore.DocumentSnapshot) {
  if (cfg.walletCooldownHours <= 0) return;
  const since = st.exists && st.get('wallet') === wallet ? Number(st.get('since')) : NaN;
  const unlockAt = Number.isFinite(since) ? since + cfg.walletCooldownHours * HOUR_MS : Infinity;
  if (!(now >= unlockAt)) {
    const hours = Number.isFinite(unlockAt) ? Math.max(1, Math.ceil((unlockAt - now) / HOUR_MS)) : cfg.walletCooldownHours;
    throw new HttpsError(
      'failed-precondition',
      `Your payout wallet was changed recently. For your security you can withdraw to it in about ${hours} hour${hours === 1 ? '' : 's'}.`,
    );
  }
}

const ACTIVE_RENTAL_DONE = ['completed', 'cancelled'];

async function hasActiveRentals(tx: Transaction, db: Firestore, uid: string): Promise<boolean> {
  const [rentals, props] = await Promise.all([
    tx.get(db.collection('rentals').where('renteeId', '==', uid)),
    tx.get(db.collection('properties').where('renteeId', '==', uid)),
  ]);
  const lower = (v: unknown) => String(v ?? '').toLowerCase();
  const veh = rentals.docs.some((r) => !ACTIVE_RENTAL_DONE.includes(lower(r.get('status'))));
  const prop = props.docs.some((r) => ![...ACTIVE_RENTAL_DONE, 'available'].includes(lower(r.get('status'))));
  return veh || prop;
}

export async function processWithdrawal(deps: Deps, auth: CallerAuth | undefined, data: unknown) {
  const { db } = deps;
  if (!auth?.uid) throw new HttpsError('unauthenticated', 'Sign in to withdraw.');
  const uid = auth.uid;
  const input = parseInput(data);
  const { key } = input;
  const primary = reqRef(db, key);

  // Idempotent replay (fast path): same key -> same record, never a second debit or payout.
  const existing = await primary.get();
  if (existing.exists) return replay(deps, uid, key, input);

  const cfg = await loadConfig(db);
  if (!cfg.enabled) throw new HttpsError('failed-precondition', 'Withdrawals are temporarily unavailable.');

  if (input.method === 'solana' && cfg.walletCooldownHours > 0) await observePayoutWallet(deps, uid);

  let rate: number | null = null;
  if (input.method === 'solana') {
    let rates;
    try {
      rates = await deps.rates();
    } catch {
      throw new HttpsError('unavailable', 'Exchange rates are unavailable. Please try again shortly.');
    }
    rate = input.coin === 'SOL' ? rates.solPhp : rates.usdtPhp;
    const [lo, hi] = input.coin === 'SOL' ? [cfg.solPhpMin, cfg.solPhpMax] : [cfg.usdtPhpMin, cfg.usdtPhpMax];
    if (!Number.isFinite(rate) || rate < lo || rate > hi) {
      throw new HttpsError('unavailable', 'Exchange rate failed a sanity check. Please try again later.');
    }
  }

  // ── 1+2. checks and effects in a single transaction ──────────────────────────
  const created = await db.runTransaction(async (tx) => {
    const now = deps.now();
    const userRef = db.doc(`users/${uid}`);
    const usageRef = db.doc(`withdrawal_usage/${uid}_${manilaDay(now)}`);
    const [reqSnap, userSnap, usageSnap, walletStateSnap] = await Promise.all([
      tx.get(primary),
      tx.get(userRef),
      tx.get(usageRef),
      tx.get(walletStateRef(db, uid)),
    ]);
    if (reqSnap.exists) return { replay: true as const };
    if (!userSnap.exists) throw new HttpsError('failed-precondition', 'Profile not found.');
    const u = userSnap.data() ?? {};
    if (u.banned === true || (typeof u.suspendedUntil === 'number' && u.suspendedUntil > now)) {
      throw new HttpsError('permission-denied', 'This account cannot withdraw.');
    }

    if (cfg.requireIdVerified && u.idVerified !== true) {
      throw new HttpsError('failed-precondition', 'Verify your identity (KYC) before withdrawing.');
    }

    const amountCents = input.amountCents;
    if (amountCents < Math.round(cfg.minPhp * 100)) {
      throw new HttpsError('invalid-argument', `Minimum withdrawal is ₱${cfg.minPhp.toFixed(2)}.`);
    }
    if (amountCents > Math.round(cfg.maxPhp * 100)) {
      throw new HttpsError('invalid-argument', `Maximum withdrawal per request is ₱${cfg.maxPhp.toFixed(2)}.`);
    }

    let wallet = '';
    if (input.method === 'solana') {
      // The destination is ALWAYS the wallet linked on the profile, never a client-sent address.
      wallet = String(u.walletPublicKey || u.solanaWalletAddress || u.walletAddress || '');
      try {
        new PublicKey(wallet);
      } catch {
        throw new HttpsError('failed-precondition', 'Link a Solana wallet to your profile before withdrawing.');
      }
      assertWalletCooldown(now, cfg, wallet, walletStateSnap);
      if (await hasActiveRentals(tx, db, uid)) {
        throw new HttpsError('failed-precondition', 'Withdrawals are disabled while you have active/ongoing rentals.');
      }
    }

    const balance = typeof u.tyxBalance === 'number' && Number.isFinite(u.tyxBalance) ? u.tyxBalance : 0;
    const reserved = typeof u.reservedBalance === 'number' && Number.isFinite(u.reservedBalance) ? u.reservedBalance : 0;
    const availableCents = Math.round(Math.max(0, balance - reserved) * 100);
    if (amountCents > availableCents) {
      throw new HttpsError('failed-precondition', 'Requested amount exceeds your available balance.');
    }

    const usage = usageSnap.data() ?? {};
    const usedCount = typeof usage.count === 'number' ? usage.count : 0;
    const usedCents = typeof usage.totalCents === 'number' ? usage.totalCents : 0;
    if (usedCount + 1 > cfg.dailyMaxCount || usedCents + amountCents > Math.round(cfg.dailyMaxPhp * 100)) {
      throw new HttpsError('resource-exhausted', 'Daily withdrawal limit reached. Try again tomorrow.');
    }

    // Fee is computed here and only here.
    const feeRate = input.method === 'solana' ? cfg.solanaFeeRate : cfg.p2pFeeRate;
    const feeCents = Math.round(amountCents * feeRate);
    const netCents = amountCents - feeCents;

    let baseUnits: bigint | null = null;
    let cryptoAmount: number | null = null;
    if (input.method === 'solana') {
      const decimals = input.coin === 'SOL' ? 9 : 6;
      const crypto = php(netCents) / (rate as number);
      baseUnits = BigInt(Math.floor(crypto * 10 ** decimals));
      if (baseUnits <= 0n) throw new HttpsError('invalid-argument', 'Amount is too small to send.');
      cryptoAmount = Number(baseUnits) / 10 ** decimals;
    }

    const newBalance = (Math.round(balance * 100) - amountCents) / 100;

    const base: Record<string, any> = {
      id: key,
      uid,
      userId: uid,
      userName: String(u.name || u.displayName || 'TRANYX User'),
      userEmail: String(u.email || auth.token?.email || ''),
      method: input.method,
      amount: php(amountCents),
      feeRate,
      feeAmount: php(feeCents),
      netAmount: php(netCents),
      currency: 'PHP',
      balanceDeducted: true,
      createdAt: now,
      updatedAt: now,
    };
    let doc: Record<string, any>;
    if (input.method === 'solana') {
      const methodTitle = `Solana (${input.coin})`;
      doc = {
        ...base,
        status: 'Pending',
        payoutState: 'pending' as PayoutState,
        paymentMethod: methodTitle,
        payoutMethod: 'Solana',
        originRail: 'mwa_on_chain',
        coin: input.coin,
        rate,
        cryptoAmount,
        baseUnits: baseUnits!.toString(),
        walletPublicKey: wallet,
      };
    } else {
      const p = input.p2p!;
      doc = {
        ...base,
        status: 'WAITING_FOR_AGENT',
        payoutState: 'manual_review' as PayoutState, // never touched by the Solana state machine / reconciler
        paymentMethod: p.paymentMethod,
        originRail: 'manual_p2p',
        p2pStatus: 'WAITING_FOR_AGENT',
        payoutMethod: p.paymentMethod,
        userAccountName: p.accountName,
        userAccountNumber: p.accountNumber,
        accountName: p.accountName,
        accountNumber: p.accountNumber,
        userQrUrl: p.qrUrl,
        referenceNumber: key.slice(0, 8).toUpperCase(),
        proofImageUrl: '',
      };
    }

    tx.set(userRef, { tyxBalance: newBalance, updatedAt: now }, { merge: true });
    tx.set(usageRef, { uid, day: manilaDay(now), count: usedCount + 1, totalCents: usedCents + amountCents }, { merge: true });
    tx.set(primary, doc);
    tx.set(mirrorRef(db, key), doc); // dual-collection sync (admin portal + clients read both)
    const [txMain, txWallet] = ledgerRefs(db, doc as any);
    const ledger = ledgerEntry(doc);
    tx.set(txMain, ledger.global);
    if (txWallet) tx.set(txWallet, ledger.wallet);
    if (input.method === 'p2p') {
      tx.set(db.doc(`notifications/notif_agent_with_${key}`), {
        title: `New P2P Cashout Request (₱${php(amountCents).toFixed(2)})`,
        message: `${doc.userName} requested a ${doc.paymentMethod} cashout of ₱${php(amountCents).toFixed(2)}. Tap to claim and fulfill payout.`,
        type: 'p2p_cashout_request',
        withdrawalRequestId: key,
        uid,
        userId: uid,
        createdAt: now,
        read: false,
      });
    }
    return { replay: false as const, doc, newBalance };
  });

  if (created.replay) return replay(deps, uid, key, input);

  if (input.method === 'p2p') return publicResult(created.doc, false, created.newBalance);

  // ── 3. interaction, strictly after commit ────────────────────────────────────
  const settled = await executeSend(deps, key);
  return publicResult(settled, false, created.newBalance);
}

function ledgerEntry(d: Record<string, any>) {
  const isP2p = d.method === 'p2p';
  const title = isP2p
    ? `${d.paymentMethod} P2P Cashout Request`
    : `Withdrawal Request (${d.paymentMethod})`;
  const desc = isP2p
    ? `Awaiting Payment Agent fulfillment to ${d.userAccountNumber} (${d.userAccountName})`
    : `Requested ₱${Number(d.amount).toFixed(2)} withdrawal to ${d.walletPublicKey}`;
  const common: Record<string, any> = {
    uid: d.uid,
    userId: d.uid,
    withdrawalRequestId: d.id,
    title,
    desc,
    description: desc,
    type: 'withdraw',
    direction: 'DEBIT',
    originRail: d.originRail,
    method: isP2p ? d.paymentMethod : 'Solana',
    paymentMethod: d.paymentMethod,
    currency: 'PHP',
    feeAmount: d.feeAmount,
    netAmount: d.netAmount,
    status: d.status,
    balanceDeducted: true,
    createdAt: d.createdAt,
    updatedAt: d.updatedAt,
    ...(isP2p
      ? { userAccountName: d.userAccountName, userAccountNumber: d.userAccountNumber, ...(d.userQrUrl ? { userQrUrl: d.userQrUrl } : {}) }
      : { coin: d.coin, rate: d.rate, cryptoAmount: d.cryptoAmount, walletPublicKey: d.walletPublicKey, payoutMethod: 'Solana' }),
  };
  return {
    global: { ...common, id: isP2p ? `p2p_with_${d.id}` : `wd_${d.id}`, amount: -d.amount },
    wallet: { ...common, id: d.id, amount: d.amount },
  };
}

/** True when a replayed request differs from the stored one in anything the caller controls. */
function differsFromStored(d: Record<string, any>, input: WithdrawInput): boolean {
  if (d.method !== input.method || Math.round(Number(d.amount) * 100) !== input.amountCents) return true;
  if (input.method === 'solana') return d.coin !== input.coin;
  const p = input.p2p!;
  return d.paymentMethod !== p.paymentMethod || d.accountName !== p.accountName || d.accountNumber !== p.accountNumber;
}

async function replay(deps: Deps, uid: string, key: string, input: WithdrawInput) {
  const snap = await reqRef(deps.db, key).get();
  const d = snap.data();
  // Do not reveal whether someone else's key exists.
  if (!snap.exists || !d || d.uid !== uid) {
    throw new HttpsError('already-exists', 'This idempotency key cannot be used.');
  }
  let cur: Record<string, any> = d;
  if (d.method === 'solana') {
    if (d.payoutState === 'pending') cur = await executeSend(deps, key);
    else if (IN_FLIGHT.includes(d.payoutState)) cur = await reconcileOne(deps, key);
  }
  return publicResult(cur, true, undefined, differsFromStored(d, input));
}

// ── state machine ──────────────────────────────────────────────────────────────

async function patchDocs(tx: Transaction, db: Firestore, d: Record<string, any>, patch: Record<string, any>) {
  tx.set(reqRef(db, d.id), patch, { merge: true });
  tx.set(mirrorRef(db, d.id), patch, { merge: true });
  const [txMain, txWallet] = ledgerRefs(db, d as any);
  const ledgerPatch = { status: patch.status, updatedAt: patch.updatedAt, ...(patch.solanaTxSignature ? { solanaTxSignature: patch.solanaTxSignature } : {}), ...(patch.ledgerDesc ? { desc: patch.ledgerDesc, description: patch.ledgerDesc } : {}), ...(patch.ledgerTitle ? { title: patch.ledgerTitle } : {}) };
  tx.set(txMain, ledgerPatch, { merge: true });
  if (txWallet) tx.set(txWallet, ledgerPatch, { merge: true });
}

/** Claim + broadcast. Safe to call concurrently / repeatedly: only the claim winner broadcasts. */
export async function executeSend(deps: Deps, key: string): Promise<Record<string, any>> {
  const { db } = deps;
  const snap = await reqRef(db, key).get();
  const d = snap.data();
  if (!snap.exists || !d) throw new HttpsError('not-found', 'Withdrawal not found.');
  if (d.method !== 'solana' || d.payoutState !== 'pending') return d;

  // Build + sign first (no funds move yet), then persist signature BEFORE broadcasting.
  let prepared;
  try {
    prepared = await deps.payer().prepare({
      coin: d.coin,
      recipient: d.walletPublicKey,
      baseUnits: BigInt(d.baseUnits),
    });
  } catch (e) {
    // Nothing was signed or sent: safe to refund immediately.
    logOf(deps).warn('withdrawal prepare failed', { withdrawalId: key, detail: safeDetail(e) });
    return (await refund(deps, key, 'PREPARE_FAILED', ['pending'])) ?? (await getDoc(deps, key));
  }

  const claimed = await db.runTransaction(async (tx) => {
    const s = await tx.get(reqRef(db, key));
    const cur = s.data();
    if (!cur || cur.payoutState !== 'pending') return false;
    await patchDocs(tx, db, cur, {
      payoutState: 'submitting' as PayoutState,
      status: 'Pending',
      solanaTxSignature: prepared.signature,
      lastValidBlockHeight: prepared.lastValidBlockHeight,
      submittingAt: deps.now(),
      updatedAt: deps.now(),
    });
    return true;
  });
  if (!claimed) return getDoc(deps, key);

  try {
    await deps.payer().broadcast(prepared);
    return (await markSent(deps, key)) ?? (await getDoc(deps, key));
  } catch (e) {
    // Ambiguous: it may still have landed. Ask the chain; never refund on a guess.
    logOf(deps).warn('withdrawal broadcast ambiguous', { withdrawalId: key, detail: safeDetail(e) });
    return reconcileOne(deps, key, { hint: AMBIGUOUS_CODE });
  }
}

async function getDoc(deps: Deps, key: string) {
  return ((await reqRef(deps.db, key).get()).data() ?? {}) as Record<string, any>;
}

/**
 * Resolve one in-flight transfer from on-chain truth. Idempotent.
 *  - confirmed/finalized            -> sent
 *  - confirmed with an error        -> refund + failed
 *  - not found, finalized height past lastValidBlockHeight + margin -> only a CANDIDATE expiry. The refund
 *    needs EXPIRY_OBSERVATIONS_REQUIRED observations from separate scheduled reconciler passes
 *    (`countExpiry`); anything else (including a lagging RPC) leaves the funds debited and waits.
 */
export async function reconcileOne(
  deps: Deps,
  key: string,
  opts: { hint?: string; countExpiry?: boolean } = {},
): Promise<Record<string, any>> {
  const { hint, countExpiry = false } = opts;
  const d = await getDoc(deps, key);
  if (!d.id || d.method !== 'solana' || !IN_FLIGHT.includes(d.payoutState)) return d;
  let out;
  try {
    out = await deps.payer().outcome({ signature: d.solanaTxSignature, lastValidBlockHeight: d.lastValidBlockHeight });
  } catch {
    out = { state: 'waiting' as const };
  }
  if (out.state === 'confirmed') return (await markSent(deps, key)) ?? (await getDoc(deps, key));
  if (out.state === 'failed') {
    logOf(deps).warn('withdrawal failed on-chain', { withdrawalId: key, signature: d.solanaTxSignature, detail: safeDetail(out.error) });
    return (await refund(deps, key, 'ONCHAIN_ERROR', IN_FLIGHT)) ?? (await getDoc(deps, key));
  }
  if (out.state === 'expired' && countExpiry) {
    const seen = await observeExpiry(deps, key);
    if (seen !== null && seen >= EXPIRY_OBSERVATIONS_REQUIRED) {
      return (
        (await refund(deps, key, 'EXPIRED_NOT_LANDED', IN_FLIGHT, {
          minExpiryObservations: EXPIRY_OBSERVATIONS_REQUIRED,
          lateWatch: true,
        })) ?? (await getDoc(deps, key))
      );
    }
    return getDoc(deps, key);
  }
  // waiting (or an uncounted expiry candidate): keep funds debited, do not refund, do not resend.
  // A 'waiting' answer breaks the "consecutive" requirement, so the observation counter resets.
  await deps.db.runTransaction(async (tx) => {
    const s = await tx.get(reqRef(deps.db, key));
    const cur = s.data();
    if (!cur || !IN_FLIGHT.includes(cur.payoutState)) return;
    const resetCounter = out.state === 'waiting' && Number(cur.expiryObservations ?? 0) > 0;
    if (cur.payoutState === 'pending_confirmation' && !hint && !resetCounter) return;
    await patchDocs(tx, deps.db, cur, {
      payoutState: 'pending_confirmation' as PayoutState,
      status: 'Pending',
      ...(hint ? { lastError: hint } : {}),
      ...(resetCounter ? { expiryObservations: 0 } : {}),
      updatedAt: deps.now(),
    });
  });
  return getDoc(deps, key);
}

/**
 * Count one "not found past expiry" observation, at most once per `expiryGapMs`, so two overlapping
 * reconciler runs cannot satisfy the two-pass rule in the same instant. Returns the new count, or null
 * if the withdrawal is no longer in flight.
 */
async function observeExpiry(deps: Deps, key: string): Promise<number | null> {
  const gap = deps.expiryGapMs ?? DEFAULT_EXPIRY_GAP_MS;
  return deps.db.runTransaction(async (tx) => {
    const s = await tx.get(reqRef(deps.db, key));
    const cur = s.data();
    if (!cur || !IN_FLIGHT.includes(cur.payoutState)) return null;
    const now = deps.now();
    const count = Number(cur.expiryObservations ?? 0);
    const last = Number(cur.expiryLastObservedAt ?? 0);
    if (count > 0 && now - last < gap) return count;
    await patchDocs(tx, deps.db, cur, {
      payoutState: 'pending_confirmation' as PayoutState,
      status: 'Pending',
      expiryObservations: count + 1,
      expiryLastObservedAt: now,
      updatedAt: now,
    });
    return count + 1;
  });
}

async function markSent(deps: Deps, key: string): Promise<Record<string, any> | null> {
  const { db } = deps;
  return db.runTransaction(async (tx) => {
    const s = await tx.get(reqRef(db, key));
    const cur = s.data();
    if (!cur || !IN_FLIGHT.includes(cur.payoutState)) return null; // already settled
    const patch = {
      payoutState: 'sent' as PayoutState,
      status: 'Successful',
      sentAt: deps.now(),
      updatedAt: deps.now(),
      ledgerTitle: `Withdrawal Successful (${cur.paymentMethod})`,
      ledgerDesc: `Withdrew ₱${Number(cur.amount).toFixed(2)} to ${cur.walletPublicKey} (${cur.cryptoAmount} ${cur.coin}). On-Chain Tx: ${cur.solanaTxSignature}`,
    };
    await patchDocs(tx, db, cur, patch);
    return { ...cur, ...patch };
  });
}

/** Refund exactly once: guarded on the current payoutState inside the transaction. */
async function refund(
  deps: Deps,
  key: string,
  reason: FailureCode,
  allowedFrom: PayoutState[],
  opts: { minExpiryObservations?: number; lateWatch?: boolean } = {},
): Promise<Record<string, any> | null> {
  const { db } = deps;
  return db.runTransaction(async (tx) => {
    const reqSnap = await tx.get(reqRef(db, key));
    const cur = reqSnap.data();
    if (!cur || !allowedFrom.includes(cur.payoutState) || cur.balanceDeducted !== true) return null;
    if (opts.minExpiryObservations && Number(cur.expiryObservations ?? 0) < opts.minExpiryObservations) return null;
    const userRef = db.doc(`users/${cur.uid}`);
    const usageRef = db.doc(`withdrawal_usage/${cur.uid}_${manilaDay(cur.createdAt)}`);
    const [userSnap, usageSnap] = await Promise.all([tx.get(userRef), tx.get(usageRef)]);
    const bal = Math.round(Number(userSnap.get('tyxBalance') ?? 0) * 100);
    const refundCents = Math.round(Number(cur.amount) * 100);
    const now = deps.now();
    tx.set(userRef, { tyxBalance: (bal + refundCents) / 100, updatedAt: now }, { merge: true });
    if (usageSnap.exists) {
      tx.set(usageRef, {
        count: Math.max(0, Number(usageSnap.get('count') ?? 0) - 1),
        totalCents: Math.max(0, Number(usageSnap.get('totalCents') ?? 0) - refundCents),
      }, { merge: true });
    }
    const patch = {
      payoutState: 'failed' as PayoutState,
      status: 'Failed',
      balanceDeducted: false,
      failureReason: reason,
      refundedAt: now,
      updatedAt: now,
      ...(opts.lateWatch ? { lateWatch: true, lateWatchUntil: now + LATE_WATCH_MS } : {}),
      ledgerTitle: `Withdrawal Failed (${cur.paymentMethod}) - refunded`,
      ledgerDesc: `Withdrawal of ₱${Number(cur.amount).toFixed(2)} failed and was refunded to your wallet.`,
    };
    await patchDocs(tx, db, cur, patch);
    return { ...cur, ...patch };
  });
}

/**
 * A refunded (expired) transfer whose signature later confirms means the user was paid twice. Never
 * auto-debit: flag it loudly (Cloud Logging error + admin-only alert doc + flag on the request) for staff.
 */
async function flagLateConfirm(deps: Deps, key: string): Promise<boolean> {
  const { db } = deps;
  const flagged = await db.runTransaction(async (tx) => {
    const s = await tx.get(reqRef(db, key));
    const cur = s.data();
    if (!cur || cur.payoutState !== 'failed' || cur.lateConfirmAfterFailure === true) return null;
    const now = deps.now();
    const patch = { lateConfirmAfterFailure: true, lateConfirmedAt: now, lateWatch: false, needsStaffReview: true, updatedAt: now };
    tx.set(reqRef(db, key), patch, { merge: true });
    tx.set(mirrorRef(db, key), patch, { merge: true });
    tx.set(db.doc(`withdrawal_alerts/${key}`), {
      type: 'late_confirm_after_failure',
      withdrawalId: key,
      uid: cur.uid,
      amount: cur.amount,
      signature: cur.solanaTxSignature,
      refundedAt: cur.refundedAt ?? null,
      createdAt: now,
      resolved: false,
    });
    return cur;
  });
  if (flagged) {
    logOf(deps).error('WITHDRAWAL_LATE_CONFIRM_AFTER_FAILURE', {
      withdrawalId: key,
      uid: flagged.uid,
      amount: flagged.amount,
      signature: flagged.solanaTxSignature,
    });
  }
  return !!flagged;
}

/** Scheduled sweep: settle every in-flight transfer, re-drive stale 'pending' claims, watch refunds for late confirms. */
export async function reconcileAll(deps: Deps, opts: { stalePendingMs?: number } = {}) {
  const stale = opts.stalePendingMs ?? 120_000;
  const { db } = deps;
  const inflight = await db.collection('withdrawal_requests').where('payoutState', 'in', IN_FLIGHT).limit(200).get();
  const pending = await db.collection('withdrawal_requests').where('payoutState', '==', 'pending').limit(200).get();
  const watched = await db.collection('withdrawal_requests').where('lateWatch', '==', true).limit(200).get();
  let settled = 0;
  for (const doc of inflight.docs) {
    if (doc.get('method') !== 'solana') continue;
    const after = await reconcileOne(deps, doc.id, { countExpiry: true });
    if (after.payoutState === 'sent' || after.payoutState === 'failed') settled++;
  }
  for (const doc of pending.docs) {
    if (doc.get('method') !== 'solana') continue; // P2P 'pending' is the manual queue
    if (deps.now() - Number(doc.get('createdAt') ?? 0) < stale) continue;
    const after = await executeSend(deps, doc.id);
    if (after.payoutState === 'sent' || after.payoutState === 'failed') settled++;
  }
  let lateConfirmed = 0;
  for (const doc of watched.docs) {
    if (doc.get('payoutState') !== 'failed' || !doc.get('solanaTxSignature')) continue;
    if (deps.now() > Number(doc.get('lateWatchUntil') ?? 0)) {
      await doc.ref.set({ lateWatch: false }, { merge: true });
      continue;
    }
    let out;
    try {
      out = await deps.payer().outcome({ signature: doc.get('solanaTxSignature'), lastValidBlockHeight: doc.get('lastValidBlockHeight') });
    } catch {
      continue;
    }
    if (out.state === 'confirmed' && (await flagLateConfirm(deps, doc.id))) lateConfirmed++;
  }
  return { inflight: inflight.size, settled, lateConfirmed };
}

// ── P2P owner actions (K11): cancel + confirm run server-side ───────────────────
//
// Until now the owner cancelled a P2P cashout from the client: a plain tyxBalance write plus a status
// write, so a double refund was possible (and unbounded while tyxBalance is client-writable). The owner
// now asks this function, which does the refund in ONE transaction guarded on the request status, and
// the rules deny every owner write to withdrawal docs and their ledger rows.

const CANCELLABLE = ['WAITING_FOR_AGENT', 'PENDING_REVIEW', 'PENDING'];
const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;

export interface P2pActionInput {
  id: string;
  action: 'cancel' | 'confirm';
  reason: string;
}

export function parseP2pAction(data: unknown): P2pActionInput {
  const d = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  const id = str(d.withdrawalId, 128);
  if (!ID_RE.test(id)) throw new HttpsError('invalid-argument', 'withdrawalId is invalid.');
  if (d.action !== 'cancel' && d.action !== 'confirm') {
    throw new HttpsError('invalid-argument', "action must be 'cancel' or 'confirm'.");
  }
  return { id, action: d.action, reason: str(d.reason, 500) };
}

export async function processP2pAction(deps: Deps, auth: CallerAuth | undefined, data: unknown) {
  const { db } = deps;
  if (!auth?.uid) throw new HttpsError('unauthenticated', 'Sign in to continue.');
  const uid = auth.uid;
  const input = parseP2pAction(data);
  // NOTE: deliberately NOT gated by the withdrawal kill switch: users must always be able to cancel + get refunded.

  return db.runTransaction(async (tx) => {
    const reqPath = reqRef(db, input.id);
    const mirror = mirrorRef(db, input.id);
    const txMainRef = db.doc(`transactions/p2p_with_${input.id}`);
    const txWalletRef = db.doc(`wallets/${uid}/transactions/${input.id}`);
    const [reqSnap, mirrorSnap, mainSnap, walletSnap] = await Promise.all([
      tx.get(reqPath), tx.get(mirror), tx.get(txMainRef), tx.get(txWalletRef),
    ]);
    const cur = reqSnap.data();
    // Same answer for "missing" and "someone else's": do not reveal other users' request ids.
    if (!cur || (cur.uid ?? cur.userId) !== uid) throw new HttpsError('not-found', 'Withdrawal request not found.');
    if (cur.method === 'solana') {
      throw new HttpsError('failed-precondition', 'Only P2P cashouts can be changed here.');
    }
    const status = String(cur.status ?? '').toUpperCase();
    const now = deps.now();
    const amount = Number(cur.amount);
    const amountCents = Math.round(amount * 100);

    let patch: Record<string, any>;
    let ledgerPatch: Record<string, any>;
    let userWrite: { balance: number } | null = null;
    let usageWrite: { ref: ReturnType<Firestore['doc']>; count: number; totalCents: number } | null = null;

    if (input.action === 'cancel') {
      if (status === 'CANCELLED') return { ok: true, id: input.id, status: 'CANCELLED', alreadyDone: true };
      if (!CANCELLABLE.includes(status)) {
        throw new HttpsError('failed-precondition', 'This cashout can no longer be cancelled.');
      }
      const refund = cur.balanceDeducted === true;
      if (refund) {
        const usageRef = db.doc(`withdrawal_usage/${uid}_${manilaDay(Number(cur.createdAt ?? now))}`);
        const [userSnap, usageSnap] = await Promise.all([tx.get(db.doc(`users/${uid}`)), tx.get(usageRef)]);
        const bal = Math.round(Number(userSnap.get('tyxBalance') ?? 0) * 100);
        userWrite = { balance: (bal + amountCents) / 100 };
        if (usageSnap.exists) {
          usageWrite = {
            ref: usageRef,
            count: Math.max(0, Number(usageSnap.get('count') ?? 0) - 1),
            totalCents: Math.max(0, Number(usageSnap.get('totalCents') ?? 0) - amountCents),
          };
        }
      }
      const note = refund ? `₱${amount.toFixed(2)} refunded to wallet.` : 'Request cancelled.';
      patch = {
        status: 'CANCELLED',
        p2pStatus: 'CANCELLED',
        payoutState: 'cancelled',
        balanceDeducted: false,
        ...(refund ? { refundedAt: now } : {}),
        ...(input.reason ? { rejectionReason: input.reason } : {}),
        verifiedAt: now,
        updatedAt: now,
      };
      ledgerPatch = { status: 'CANCELLED', desc: `Cashout cancelled. ${note}`, description: `Cashout cancelled. ${note}`, verifiedAt: now, updatedAt: now };
    } else {
      if (status === 'APPROVED') return { ok: true, id: input.id, status: 'APPROVED', alreadyDone: true };
      if (status !== 'PENDING_CONFIRMATION') {
        throw new HttpsError('failed-precondition', 'There is nothing to confirm yet: the agent has not sent proof of payment.');
      }
      const method = String(cur.paymentMethod ?? cur.payoutMethod ?? 'GCash');
      const ref = String(cur.referenceNumber ?? '').trim();
      const desc = ref ? `Cashout completed via ${method} (Ref: #${ref})` : `Cashout completed via ${method}`;
      patch = { status: 'APPROVED', p2pStatus: 'COMPLETED', adminUid: uid, verifiedAt: now, updatedAt: now };
      ledgerPatch = { status: 'COMPLETED', desc, description: desc, verifiedAt: now, adminUid: uid, updatedAt: now };
    }

    // all reads done; writes below
    if (userWrite) tx.set(db.doc(`users/${uid}`), { tyxBalance: userWrite.balance, updatedAt: now }, { merge: true });
    if (usageWrite) tx.set(usageWrite.ref, { count: usageWrite.count, totalCents: usageWrite.totalCents }, { merge: true });
    tx.set(reqPath, patch, { merge: true });
    if (mirrorSnap.exists) tx.set(mirror, patch, { merge: true });
    if (mainSnap.exists) tx.set(txMainRef, ledgerPatch, { merge: true });
    if (walletSnap.exists) tx.set(txWalletRef, ledgerPatch, { merge: true });
    if (input.action === 'confirm') {
      tx.set(db.doc(`notifications/notif_with_success_${input.id}_${now}`), {
        uid,
        userId: uid,
        title: 'Withdrawal Completed!',
        message: `Your ${cur.paymentMethod ?? 'P2P'} cashout of ₱${amount.toFixed(2)} has been completed successfully.`,
        type: 'withdrawal_completed',
        createdAt: now,
        read: false,
      });
    }
    return {
      ok: true,
      id: input.id,
      status: patch.status as string,
      alreadyDone: false,
      ...(userWrite ? { newBalance: userWrite.balance } : {}),
    };
  });
}
