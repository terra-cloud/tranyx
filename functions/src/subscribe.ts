import { HttpsError } from 'firebase-functions/https';
import { loadCreditConfig, nextPremiumUntilMs } from './credit';
import { ledger, parseKey, readOp, requireAuth, Wallet, writeOp, type CallerAuth, type MoneyDeps } from './money';

/**
 * subscribeWithBalance: Hybrid PRO paid from the wallet balance. Price comes from config/credit
 * (same source as the on-chain subscription), never from the client. Extends from the current expiry.
 */
export async function subscribeWithBalance(deps: MoneyDeps, auth: CallerAuth | undefined, data: unknown) {
  const uid = requireAuth(auth);
  const d = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  const key = parseKey(d.idempotencyKey);
  if (d.plan !== 'monthly' && d.plan !== 'yearly') throw new HttpsError('invalid-argument', "plan must be 'monthly' or 'yearly'.");
  const plan = d.plan;
  const { db } = deps;
  const cfg = await loadCreditConfig(db);
  const price = plan === 'yearly' ? cfg.yearlyPhp : cfg.monthlyPhp;
  const now = deps.now();

  return db.runTransaction(async (tx) => {
    const replay = await readOp(tx, db, uid, key);
    if (replay) return { ...replay, replay: true };
    const w = new Wallet(tx, db);
    const u = await w.load(uid);
    if (!w.exists(uid)) throw new HttpsError('failed-precondition', 'Profile not found.');
    w.debit(uid, price);
    const premiumUntil = nextPremiumUntilMs(typeof u.premiumUntil === 'number' ? u.premiumUntil : null, now, plan);
    const txId = `sub_bal_${uid}_${key}`;
    ledger(tx, db, txId, uid, now, {
      type: 'payment', category: 'subscription', kind: 'subscription', amount: price, subscriptionPlan: plan,
      title: `Hybrid PRO Subscription (${plan === 'yearly' ? 'Yearly' : 'Monthly'})`,
      desc: `Subscribed via Tyxbit Balance (₱${price.toFixed(0)})`, status: 'Successful', method: 'Tyxbit',
    });
    w.flush({
      [uid]: {
        isPremium: true, premiumUntil, accountType: 'hybrid', subscriptionPlan: plan, subscriptionStartedAt: now,
        subscriptionPaymentMethod: 'Tyxbit Balance', subscriptionPaymentAmount: price, subscriptionTxId: txId,
        subscriptionStatus: 'active', pendingSubscription: null,
      },
    });
    const result = { ok: true, plan, amount: price, premiumUntil, newBalance: w.balance(uid) };
    writeOp(tx, db, uid, key, 'subscribeWithBalance', result, now);
    return result;
  });
}
