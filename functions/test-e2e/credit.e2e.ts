// Full-stack local smoke: Auth + Firestore + Functions emulators, real onCall wrapper over HTTP.
// The chain and rates are mocked inside the emulator only (CREDIT_MOCK_SOLANA=1, FUNCTIONS_EMULATOR=true);
// the mock chain reads the transaction JSON from the emulator's Firestore `__mock_chain/{signature}`.
import { describe, expect, it } from 'vitest';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { Keypair } from '@solana/web3.js';
import bs58 from 'bs58';

const FS = '127.0.0.1:8189';
const AUTH = '127.0.0.1:9189';
process.env.FIRESTORE_EMULATOR_HOST = FS;
initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();
const URL = 'http://127.0.0.1:5189/demo-tranyx/us-central1/creditOnchainPayment';
const TREASURY = '11111111111111111111111111111112';
const newSig = () => bs58.encode(Uint8Array.from({ length: 64 }, () => Math.floor(Math.random() * 256)));

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
const solTx = (wallet: string, lamports: number) => JSON.stringify({
  meta: { err: null },
  transaction: { message: {
    accountKeys: [{ pubkey: wallet, signer: true, writable: true }, { pubkey: TREASURY, signer: false, writable: true }],
    instructions: [{ program: 'system', parsed: { type: 'transfer', info: { source: wallet, destination: TREASURY, lamports } } }],
  } },
});

const APPCHECK_ON = process.env.ENFORCE_APP_CHECK !== 'false';

describe.runIf(APPCHECK_ON)('App Check enforcement (default: enforced)', () => {
  it('a signed-in caller WITHOUT an App Check token is rejected and nothing is credited', async () => {
    const u = await signUp(`ac${Date.now()}@example.com`);
    const wallet = Keypair.generate().publicKey.toBase58();
    await db.doc(`users/${u.localId}`).set({ tyxBalance: 10, walletPublicKey: wallet });
    const sig = newSig();
    await db.doc(`__mock_chain/${sig}`).set({ tx: solTx(wallet, 500_000_000) });
    const r = await call({ signature: sig, kind: 'deposit_sol' }, u.idToken);
    expect(r.status).toBe(401);
    expect((await db.doc(`users/${u.localId}`).get()).get('tyxBalance')).toBe(10);
  });
});

describe.runIf(!APPCHECK_ON)('creditOnchainPayment over the Functions emulator (App Check off for the test)', () => {
  it('unauthenticated -> 401; signed-in deposit credits once; replay is already_processed; unfinalized is retryable', async () => {
    const sig = newSig();
    const un = await call({ signature: sig, kind: 'deposit_sol' });
    expect(un.status).toBe(401);
    expect(un.body.error.status).toBe('UNAUTHENTICATED');

    const u = await signUp(`cr${Date.now()}@example.com`);
    const wallet = Keypair.generate().publicKey.toBase58();
    await db.doc(`users/${u.localId}`).set({ tyxBalance: 10, walletPublicKey: wallet });

    // linked but never proven (client-written link only): refused before anything is read from chain
    const unverified = await call({ signature: sig, kind: 'deposit_sol' }, u.idToken);
    expect(unverified.status).toBe(400);
    expect(unverified.body.error.status).toBe('FAILED_PRECONDITION');
    expect(unverified.body.error.message).toContain('WALLET_NOT_VERIFIED');
    await db.doc(`wallet_verified/${wallet}`).set({ uid: u.localId, verifiedAt: 1 }); // walletAuthLink does this

    const early = await call({ signature: sig, kind: 'deposit_sol' }, u.idToken);
    expect(early.status).toBe(200);
    expect(early.body.result.status).toBe('not_finalized');

    await db.doc(`__mock_chain/${sig}`).set({ tx: solTx(wallet, 500_000_000) }); // 0.5 SOL x 8000 (mock rate)
    const ok = await call({ signature: sig, kind: 'deposit_sol', phpAmount: 99999999 }, u.idToken);
    expect(ok.body.result).toMatchObject({ status: 'credited', phpAmount: 4000 });
    expect((await db.doc(`users/${u.localId}`).get()).get('tyxBalance')).toBe(4010);
    const again = await call({ signature: sig, kind: 'deposit_sol' }, u.idToken);
    expect(again.body.result.status).toBe('already_processed');
    expect((await db.doc(`users/${u.localId}`).get()).get('tyxBalance')).toBe(4010);

    const bad = await call({ signature: 'x', kind: 'deposit_sol' }, u.idToken);
    expect(bad.status).toBe(400);
  });
});
