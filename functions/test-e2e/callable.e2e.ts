// Full-stack local smoke: Auth + Firestore + Functions emulators, real onCall wrapper over HTTP.
// Solana + rates are mocked inside the emulator only (WITHDRAW_MOCK_SOLANA=1, FUNCTIONS_EMULATOR=true).
import { describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { Keypair } from '@solana/web3.js';

const FS = '127.0.0.1:8189';
const AUTH = '127.0.0.1:9189';
process.env.FIRESTORE_EMULATOR_HOST = FS;
initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();
const URL = 'http://127.0.0.1:5189/demo-tranyx/us-central1/requestWithdrawal';

async function signUp(email: string) {
  const r = await fetch(`http://${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password: 'Passw0rd!x', returnSecureToken: true }),
  });
  return (await r.json()) as { idToken: string; localId: string };
}
async function call(data: unknown, idToken?: string) {
  const r = await fetch(URL, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(idToken ? { authorization: `Bearer ${idToken}` } : {}) },
    body: JSON.stringify({ data }),
  });
  return { status: r.status, body: (await r.json()) as any };
}

const APPCHECK_ON = process.env.ENFORCE_APP_CHECK !== 'false';

describe.runIf(APPCHECK_ON)('App Check enforcement (default: enforced)', () => {
  it('a signed-in caller WITHOUT an App Check token is rejected and nothing is debited', async () => {
    const u = await signUp(`ac${Date.now()}@example.com`);
    await db.doc(`users/${u.localId}`).set({ name: 'AC', tyxBalance: 1000, walletPublicKey: Keypair.generate().publicKey.toBase58() });
    const r = await call({ idempotencyKey: randomUUID(), method: 'solana', amount: 500, coin: 'USDT' }, u.idToken);
    expect(r.status).toBe(401);
    expect(String(r.body.error.status).toLowerCase()).toBe('unauthenticated'); expect(r.body.error.message).not.toContain('Sign in to withdraw'); /* framework rejection, handler never ran */ // emulator reports missing App Check as UNAUTHENTICATED
    expect((await db.doc(`users/${u.localId}`).get()).get('tyxBalance')).toBe(1000);
  });
});

describe.runIf(!APPCHECK_ON)('requestWithdrawal over the Functions emulator (App Check off for the test)', () => {
  it('unauthenticated -> 401; signed-in solana + p2p succeed; replay is idempotent; over-balance denied', async () => {
    const un = await call({ idempotencyKey: randomUUID(), method: 'solana', amount: 100, coin: 'USDT' });
    expect(un.status).toBe(401);
    expect(un.body.error.status).toBe('UNAUTHENTICATED');

    const u = await signUp(`e2e${Date.now()}@example.com`);
    const payoutWallet = Keypair.generate().publicKey.toBase58();
    await db.doc(`users/${u.localId}`).set({ name: 'E2E', tyxBalance: 1000, walletPublicKey: payoutWallet });
    // Wallet linked > 24h ago, so the payout-wallet cooldown does not apply.
    await db.doc(`payout_wallet_state/${u.localId}`).set({ uid: u.localId, wallet: payoutWallet, since: Date.now() - 48 * 3600 * 1000 });

    // K1: off by default until staff set config/withdrawals.enabled = true
    const off = await call({ idempotencyKey: randomUUID(), method: 'solana', amount: 500, coin: 'USDT' }, u.idToken);
    expect(off.status).toBe(400);
    expect(off.body.error.status).toBe('FAILED_PRECONDITION');
    expect((await db.doc(`users/${u.localId}`).get()).get('tyxBalance')).toBe(1000);
    await db.doc('config/withdrawals').set({ enabled: true });

    const key = randomUUID();
    const a = await call({ idempotencyKey: key, method: 'solana', amount: 500, coin: 'USDT', feeAmount: 0 }, u.idToken);
    expect(a.status).toBe(200);
    expect(a.body.result.feeAmount).toBe(10);
    expect(a.body.result.payoutState).toBe('sent');
    const b = await call({ idempotencyKey: key, method: 'solana', amount: 500, coin: 'USDT' }, u.idToken);
    expect(b.body.result.idempotentReplay).toBe(true);
    expect((await db.doc(`users/${u.localId}`).get()).get('tyxBalance')).toBe(500);

    const p = await call({ idempotencyKey: randomUUID(), method: 'p2p', amount: 100, p2p: { paymentMethod: 'Maya', accountName: 'J', accountNumber: '0917' } }, u.idToken);
    expect(p.body.result.status).toBe('WAITING_FOR_AGENT');

    const over = await call({ idempotencyKey: randomUUID(), method: 'solana', amount: 5000, coin: 'SOL' }, u.idToken);
    expect(over.status).toBe(400);
    expect(over.body.error.status).toBe('FAILED_PRECONDITION');
  });
});
