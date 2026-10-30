// Runs against the Firestore emulator (npm run test:emulator). Solana RPC and rates are controllable fakes.
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { Keypair, PublicKey } from '@solana/web3.js';
import { getAssociatedTokenAddressSync } from '@solana/spl-token';
import bs58 from 'bs58';
import {
  nextPremiumUntilMs,
  parseCreditInput,
  processCredit,
  resolveTreasury,
  verifyTransfer,
  type ChainReader,
  type CreditDeps,
} from '../src/credit';
import { RpcChainReader } from '../src/solana_chain';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8189';
initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();

const wallet = Keypair.generate().publicKey.toBase58();
const otherWallet = Keypair.generate().publicKey.toBase58();
const treasury = Keypair.generate().publicKey.toBase58();
const MINT = '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU';
const treasuryAta = getAssociatedTokenAddressSync(new PublicKey(MINT), new PublicKey(treasury), true).toBase58();
const otherAta = getAssociatedTokenAddressSync(new PublicKey(MINT), new PublicKey(otherWallet), true).toBase58();
const newSig = () => bs58.encode(Uint8Array.from({ length: 64 }, () => Math.floor(Math.random() * 256)));

const sysIx = (source: string, destination: string, lamports: number) => ({
  program: 'system', parsed: { type: 'transfer', info: { source, destination, lamports } },
});
const splIx = (authority: string, destination: string, amount: number, checked?: string) => ({
  program: 'spl-token',
  parsed: checked
    ? { type: 'transferChecked', info: { authority, destination, mint: checked, tokenAmount: { amount: String(amount) } } }
    : { type: 'transfer', info: { authority, destination, amount: String(amount) } },
});
const mkTx = (ixs: unknown[], over: { err?: unknown; signer?: string; signed?: boolean } = {}) => ({
  meta: { err: over.err ?? null },
  transaction: {
    message: {
      accountKeys: [{ pubkey: over.signer ?? wallet, signer: over.signed !== false, writable: true }, { pubkey: treasury, signer: false, writable: true }],
      instructions: ixs,
    },
  },
});

class FakeChain implements ChainReader {
  txs = new Map<string, Record<string, any>>();
  calls = 0;
  async getFinalizedTransaction(sig: string) {
    this.calls++;
    return this.txs.get(sig) ?? null;
  }
}
let chain: FakeChain;
let clock = Date.UTC(2026, 9, 30, 4, 0, 0);
let rates = { solPhp: 8000, usdtPhp: 57 };
const logged: string[] = [];
const deps = (): CreditDeps => ({
  db, chain, rates: async () => rates, now: () => clock, treasuryPublicKey: treasury, usdtMint: MINT,
  log: { warn: (m) => void logged.push(m), error: (m) => void logged.push(m) },
});

async function clearAll() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-tranyx/databases/(default)/documents`, { method: 'DELETE' });
}
const UID = 'user1';
const auth = { uid: UID };
// Users are seeded with a PROVEN wallet (wallet_verified, written by walletAuthLink in production).
const seedUser = async (over: Record<string, unknown> = {}, uid = UID, w = wallet, verified = true) => {
  await db.doc(`users/${uid}`).set({ name: 'T', tyxBalance: 100, walletPublicKey: w, ...over });
  if (verified) await db.doc(`wallet_verified/${w}`).set({ uid, verifiedAt: 1 });
};
const bal = async (uid = UID) => (await db.doc(`users/${uid}`).get()).get('tyxBalance') as number;
const tx = (id: string) => db.doc(`transactions/${id}`).get();
const err = async (p: Promise<unknown>) => p.then(() => null, (e) => e as { code: string; message: string });
/** 0.5 SOL at 8000 = 4000 PHP */
const paySol = (sig: string, lamports = 500_000_000, over = {}) => chain.txs.set(sig, mkTx([sysIx(wallet, treasury, lamports)], over));

beforeAll(async () => { await clearAll(); });
beforeEach(async () => {
  await clearAll();
  chain = new FakeChain();
  logged.length = 0;
  rates = { solPhp: 8000, usdtPhp: 57 };
  clock = Date.UTC(2026, 9, 30, 4, 0, 0);
  await seedUser();
});

describe('verifyTransfer (pure)', () => {
  const v = (t: any, kind: any = 'deposit_sol', w = wallet) => verifyTransfer(t, kind, w, treasury, treasuryAta, MINT);
  it('sums every SOL transfer from the signer to the treasury', () => {
    expect(v(mkTx([sysIx(wallet, treasury, 100), sysIx(wallet, treasury, 250)]))).toEqual({ ok: true, baseUnits: 350 });
  });
  it('ignores transfers to other destinations or from other sources', () => {
    expect(v(mkTx([sysIx(wallet, otherWallet, 100)]))).toEqual({ ok: false, reason: 'NO_MATCHING_TRANSFER' });
    expect(v(mkTx([sysIx(otherWallet, treasury, 100)]))).toEqual({ ok: false, reason: 'NO_MATCHING_TRANSFER' });
  });
  it('a failed or unsigned transaction is refused', () => {
    expect(v(mkTx([sysIx(wallet, treasury, 100)], { err: { InstructionError: [0, 'x'] } }))).toEqual({ ok: false, reason: 'TX_FAILED' });
    expect(v(mkTx([sysIx(wallet, treasury, 100)], { signed: false }))).toEqual({ ok: false, reason: 'NOT_SIGNED_BY_LINKED_WALLET' });
    expect(v({ transaction: { message: { accountKeys: [], instructions: [] } } })).toEqual({ ok: false, reason: 'TX_FAILED' });
  });
  it('a SOL kind does not accept a token transfer, and a USDT kind does not accept SOL', () => {
    expect(v(mkTx([splIx(wallet, treasuryAta, 5_000_000)]), 'deposit_sol')).toEqual({ ok: false, reason: 'NO_MATCHING_TRANSFER' });
    expect(v(mkTx([sysIx(wallet, treasury, 100)]), 'deposit_usdt')).toEqual({ ok: false, reason: 'NO_MATCHING_TRANSFER' });
  });
  it('USDT: transfer and transferChecked to the treasury ATA; wrong mint / destination / authority refused', () => {
    expect(v(mkTx([splIx(wallet, treasuryAta, 5_000_000), splIx(wallet, treasuryAta, 1_000_000, MINT)]), 'deposit_usdt')).toEqual({ ok: true, baseUnits: 6_000_000 });
    expect(v(mkTx([splIx(wallet, treasuryAta, 5_000_000, 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v')]), 'deposit_usdt')).toEqual({ ok: false, reason: 'NO_MATCHING_TRANSFER' });
    expect(v(mkTx([splIx(wallet, otherAta, 5_000_000)]), 'deposit_usdt')).toEqual({ ok: false, reason: 'NO_MATCHING_TRANSFER' });
    expect(v(mkTx([splIx(otherWallet, treasuryAta, 5_000_000)]), 'deposit_usdt')).toEqual({ ok: false, reason: 'NO_MATCHING_TRANSFER' });
  });
});

describe('parseCreditInput / helpers', () => {
  it('rejects malformed signatures, kinds and plans; ignores client money fields', () => {
    const sig = newSig();
    expect(() => parseCreditInput({ signature: 'abc', kind: 'deposit_sol' })).toThrow();
    expect(() => parseCreditInput({ signature: sig, kind: 'withdraw' })).toThrow();
    expect(() => parseCreditInput({ signature: sig, kind: 'subscription_sol' })).toThrow();
    expect(parseCreditInput({ signature: sig, kind: 'deposit_sol', amount: 9e9, phpAmount: 9e9, wallet: 'x', rate: 1 })).toEqual({ signature: sig, kind: 'deposit_sol' });
    expect(parseCreditInput({ signature: sig, kind: 'subscription_sol', plan: 'yearly' })).toEqual({ signature: sig, kind: 'subscription_sol', plan: 'yearly' });
  });
  it('premium extends from max(now, premiumUntil)', () => {
    const D = 24 * 3600 * 1000;
    expect(nextPremiumUntilMs(null, 1000, 'monthly')).toBe(1000 + 30 * D);
    expect(nextPremiumUntilMs(1000 + 10 * D, 1000, 'yearly')).toBe(1000 + 10 * D + 365 * D);
    expect(nextPremiumUntilMs(5, 1000, 'monthly')).toBe(1000 + 30 * D);
  });
  it('resolveTreasury: param first, then system_config/treasury, else failed-precondition', async () => {
    expect(await resolveTreasury(db, treasury)).toBe(treasury);
    expect((await err(resolveTreasury(db, '')))?.code).toBe('failed-precondition');
    await db.doc('system_config/treasury').set({ publicKey: treasury });
    expect(await resolveTreasury(db, '')).toBe(treasury);
  });
  it('RpcChainReader asks for finalized jsonParsed and maps null / rpc errors', async () => {
    const seen: any[] = [];
    const mk = (body: unknown, ok = true) => new RpcChainReader('http://rpc.invalid', (async (_u: any, init: any) => {
      seen.push(JSON.parse(init.body));
      return { ok, status: ok ? 200 : 500, json: async () => body };
    }) as any);
    expect(await mk({ result: null }).getFinalizedTransaction('s')).toBeNull();
    expect(seen[0].params[1]).toMatchObject({ commitment: 'finalized', encoding: 'jsonParsed' });
    expect(await mk({ result: { meta: {} } }).getFinalizedTransaction('s')).toEqual({ meta: {} });
    await expect(mk({ error: { code: -32005 } }).getFinalizedTransaction('s')).rejects.toThrow();
    await expect(mk({}, false).getFinalizedTransaction('s')).rejects.toThrow();
  });
});

describe('creditOnchainPayment: deposits', () => {
  it('credits the on-chain amount at the server rate, writes both markers (5 keys on onchain_), closes pending', async () => {
    const sig = newSig();
    paySol(sig);
    await db.doc(`transactions/pending_onchain_${UID}_${sig}`).set({ uid: UID, type: 'onchain_pending', status: 'pending', solanaTxSignature: sig, startedAt: 1 });
    const r = await processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' });
    expect(r).toMatchObject({ status: 'credited', phpAmount: 4000, cryptoAmount: 0.5, currency: 'SOL' });
    expect(await bal()).toBe(4100);
    const on = (await tx(`onchain_${sig}`)).data()!;
    expect(Object.keys(on).sort()).toEqual(['markedAt', 'markerId', 'solanaTxSignature', 'type', 'uid']);
    expect(on).toMatchObject({ uid: UID, type: 'onchain_marker', solanaTxSignature: sig, markerId: `deposit_sol_${sig}` });
    expect((await tx(`deposit_sol_${sig}`)).data()).toMatchObject({ uid: UID, type: 'deposit', amount: 4000, solanaTxSignature: sig });
    expect((await tx(`pending_onchain_${UID}_${sig}`)).data()).toMatchObject({ status: 'done', completedAt: clock });
  });

  it('ignores client-sent amounts: the credited value comes from the chain and the server rate', async () => {
    const sig = newSig();
    paySol(sig, 10_000_000); // 0.01 SOL = 80 PHP
    const r = await processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol', phpAmount: 1_000_000, amount: 1e9 } as any);
    expect(r).toMatchObject({ status: 'credited', phpAmount: 80 });
    expect(await bal()).toBe(180);
  });

  it('USDT: converts base units with the USDT rate and writes deposit_usdt_ marker', async () => {
    const sig = newSig();
    chain.txs.set(sig, mkTx([splIx(wallet, treasuryAta, 10_000_000, MINT)]));
    const r = await processCredit(deps(), auth, { signature: sig, kind: 'deposit_usdt' });
    expect(r).toMatchObject({ status: 'credited', phpAmount: 570, currency: 'USDT' });
    expect((await tx(`deposit_usdt_${sig}`)).data()).toMatchObject({ currency: 'USDT', amount: 570 });
    expect((await tx(`onchain_${sig}`)).get('markerId')).toBe(`deposit_usdt_${sig}`);
  });

  it('replay and double tap credit once (sequential and parallel)', async () => {
    const sig = newSig();
    paySol(sig);
    const first = await processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' });
    expect(first.status).toBe('credited');
    expect((await processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' })).status).toBe('already_processed');
    expect(await bal()).toBe(4100);

    const sig2 = newSig();
    paySol(sig2);
    const rs = await Promise.all([1, 2, 3, 4].map(() => processCredit(deps(), auth, { signature: sig2, kind: 'deposit_sol' })));
    expect(rs.filter((x) => x.status === 'credited')).toHaveLength(1);
    expect(rs.filter((x) => x.status === 'already_processed')).toHaveLength(3);
    expect(await bal()).toBe(8100);
  });

  it('the same signature cannot be credited under a different kind', async () => {
    const sig = newSig();
    paySol(sig);
    await processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' });
    expect((await processCredit(deps(), auth, { signature: sig, kind: 'subscription_sol', plan: 'monthly' })).status).toBe('already_processed');
    expect(await bal()).toBe(4100);
  });

  it('another account claiming a credited signature gets held_by_another_account, a pending note, and nothing', async () => {
    const sig = newSig();
    paySol(sig);
    await processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' });
    await seedUser({}, 'user2', otherWallet);
    chain.txs.set(sig, mkTx([sysIx(otherWallet, treasury, 500_000_000)], { signer: otherWallet }));
    const r = await processCredit(deps(), { uid: 'user2' }, { signature: sig, kind: 'deposit_sol' });
    expect(r.status).toBe('held_by_another_account');
    expect(await bal('user2')).toBe(100);
    expect(chain.calls).toBe(1); // answered from the marker, no RPC
  });

  it('a squatter who is not the payer cannot take a signature: payer wallet must be the caller\'s linked wallet', async () => {
    const sig = newSig();
    paySol(sig); // paid by `wallet` (user1)
    await seedUser({}, 'attacker', otherWallet);
    const r = await processCredit(deps(), { uid: 'attacker' }, { signature: sig, kind: 'deposit_sol' });
    expect(r).toMatchObject({ status: 'rejected', reason: 'NOT_SIGNED_BY_LINKED_WALLET' });
    expect(await bal('attacker')).toBe(100);
    expect((await tx(`onchain_${sig}`)).exists).toBe(false);
    expect((await tx(`pending_onchain_attacker_${sig}`)).get('note')).toContain('NOT_SIGNED_BY_LINKED_WALLET');
    // the real payer can still claim it
    expect((await processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' })).status).toBe('credited');
  });

  it('not finalized: nothing is written and the caller can retry', async () => {
    const sig = newSig();
    const r = await processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' });
    expect(r.status).toBe('not_finalized');
    expect(await bal()).toBe(100);
    expect((await tx(`onchain_${sig}`)).exists).toBe(false);
    paySol(sig);
    expect((await processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' })).status).toBe('credited');
  });

  it('refuses a failed tx, wrong destination, wrong kind, tiny/huge amounts; notes the pending record', async () => {
    const a = newSig(); paySol(a, 500_000_000, { err: { InstructionError: [0, 'x'] } });
    const b = newSig(); chain.txs.set(b, mkTx([sysIx(wallet, otherWallet, 500_000_000)]));
    const c = newSig(); chain.txs.set(c, mkTx([splIx(wallet, treasuryAta, 5_000_000)]));
    const d = newSig(); paySol(d, 1_000); // 0.008 PHP
    const e = newSig(); paySol(e, 100_000_000_000); // 100 SOL = 800k PHP > max 500k
    expect((await processCredit(deps(), auth, { signature: a, kind: 'deposit_sol' })).reason).toBe('TX_FAILED');
    expect((await processCredit(deps(), auth, { signature: b, kind: 'deposit_sol' })).reason).toBe('NO_MATCHING_TRANSFER');
    expect((await processCredit(deps(), auth, { signature: c, kind: 'deposit_sol' })).reason).toBe('NO_MATCHING_TRANSFER');
    expect((await processCredit(deps(), auth, { signature: d, kind: 'deposit_sol' })).reason).toBe('AMOUNT_TOO_SMALL');
    expect((await processCredit(deps(), auth, { signature: e, kind: 'deposit_sol' })).reason).toBe('AMOUNT_TOO_LARGE');
    expect(await bal()).toBe(100);
    expect((await tx(`pending_onchain_${UID}_${a}`)).data()).toMatchObject({ status: 'pending', note: 'rejected by server: TX_FAILED' });
    for (const s of [a, b, c, d, e]) expect((await tx(`onchain_${s}`)).exists).toBe(false);
  });

  it('wallet checks: no linked wallet; walletLinks owned by someone else', async () => {
    const sig = newSig(); paySol(sig);
    await seedUser({ walletPublicKey: '' });
    expect((await processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' })).reason).toBe('WALLET_NOT_LINKED');
    await seedUser();
    await db.doc(`walletLinks/${wallet}`).set({ uid: 'someone-else', linkedAt: 1 });
    expect((await processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' })).reason).toBe('WALLET_LINKED_TO_ANOTHER_ACCOUNT');
    await db.doc(`walletLinks/${wallet}`).set({ uid: UID, linkedAt: 1 });
    expect((await processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' })).status).toBe('credited');
  });

  it('an unverified wallet (client-written link only) is refused with failed-precondition WALLET_NOT_VERIFIED, then credits once verified', async () => {
    const sig = newSig(); paySol(sig);
    await db.doc(`wallet_verified/${wallet}`).delete();
    await db.doc(`walletLinks/${wallet}`).set({ uid: UID, linkedAt: 1 }); // what a client can write on its own
    for (const kind of ['deposit_sol', 'subscription_sol'] as const) {
      const e = await err(processCredit(deps(), auth, { signature: sig, kind, plan: 'monthly' }));
      expect(e?.code).toBe('failed-precondition');
      expect(e?.message).toContain('WALLET_NOT_VERIFIED');
    }
    expect(await bal()).toBe(100);
    expect((await tx(`onchain_${sig}`)).exists).toBe(false);
    expect((await tx(`pending_onchain_${UID}_${sig}`)).data()).toMatchObject({ status: 'pending', note: 'rejected by server: WALLET_NOT_VERIFIED' });
    // proof bound to somebody else does not count either
    await db.doc(`wallet_verified/${wallet}`).set({ uid: 'someone-else', verifiedAt: 1 });
    expect((await err(processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' })))?.message).toContain('WALLET_NOT_VERIFIED');
    // the user verifies (walletAuthLink) and the same signature is credited
    await db.doc(`wallet_verified/${wallet}`).set({ uid: UID, verifiedAt: 2 });
    expect((await processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' })).status).toBe('credited');
    expect(await bal()).toBeGreaterThan(100);
  });

  it('unauthenticated, banned/suspended, bad input, kill switch, rate band, hourly budget', async () => {
    const sig = newSig(); paySol(sig);
    expect((await err(processCredit(deps(), undefined, { signature: sig, kind: 'deposit_sol' })))?.code).toBe('unauthenticated');
    expect((await err(processCredit(deps(), auth, { signature: 'nope', kind: 'deposit_sol' })))?.code).toBe('invalid-argument');
    await seedUser({ banned: true });
    expect((await err(processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' })))?.code).toBe('permission-denied');
    await seedUser({ suspendedUntil: clock + 1000 });
    expect((await err(processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' })))?.code).toBe('permission-denied');
    await seedUser();
    rates = { solPhp: 5, usdtPhp: 57 };
    expect((await err(processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' })))?.code).toBe('unavailable');
    expect(await bal()).toBe(100);
    rates = { solPhp: 8000, usdtPhp: 57 };
    await db.doc('config/credit').set({ enabled: false });
    expect((await err(processCredit(deps(), auth, { signature: sig, kind: 'deposit_sol' })))?.code).toBe('failed-precondition');
    await db.doc(`credit_usage/${UID}_${Math.floor(clock / 3_600_000)}`).delete();
    await db.doc('config/credit').set({ hourlyAttempts: 2 });
    await processCredit(deps(), auth, { signature: newSig(), kind: 'deposit_sol' });
    await processCredit(deps(), auth, { signature: newSig(), kind: 'deposit_sol' });
    expect((await err(processCredit(deps(), auth, { signature: newSig(), kind: 'deposit_sol' })))?.code).toBe('resource-exhausted');
  });
});

describe('creditOnchainPayment: subscriptions', () => {
  const D = 24 * 3600 * 1000;
  it('monthly: activates from now, writes sub_sol_ marker, sets plan fields; amount recorded is the on-chain value', async () => {
    const sig = newSig();
    paySol(sig, 37_375_000); // 0.037375 SOL = 299 PHP
    const r = await processCredit(deps(), auth, { signature: sig, kind: 'subscription_sol', plan: 'monthly' });
    expect(r).toMatchObject({ status: 'credited', plan: 'monthly', premiumUntil: clock + 30 * D });
    const u = (await db.doc(`users/${UID}`).get()).data()!;
    expect(u).toMatchObject({ isPremium: true, premiumUntil: clock + 30 * D, accountType: 'hybrid', subscriptionPlan: 'monthly', subscriptionTxId: sig, tyxBalance: 100 });
    expect((await tx(`sub_sol_${sig}`)).data()).toMatchObject({ type: 'subscription', amount: 299 });
    expect((await tx(`onchain_${sig}`)).get('markerId')).toBe(`sub_sol_${sig}`);
  });
  it('yearly while already subscribed extends from premiumUntil, never shortens', async () => {
    await seedUser({ isPremium: true, premiumUntil: clock + 10 * D });
    const sig = newSig();
    paySol(sig, 375_000_000); // 3000 PHP
    const r = await processCredit(deps(), auth, { signature: sig, kind: 'subscription_sol', plan: 'yearly' });
    expect(r.premiumUntil).toBe(clock + 10 * D + 365 * D);
  });
  it('underpaying the plan (beyond tolerance) is refused; within tolerance is accepted; replay is a no-op', async () => {
    const lo = newSig(); paySol(lo, 30_000_000); // 240 PHP < 299*0.95
    expect((await processCredit(deps(), auth, { signature: lo, kind: 'subscription_sol', plan: 'monthly' })).reason).toBe('PLAN_PRICE_NOT_MET');
    expect((await db.doc(`users/${UID}`).get()).get('isPremium')).toBeUndefined();
    const ok = newSig(); paySol(ok, 36_000_000); // 288 PHP, within 5%
    expect((await processCredit(deps(), auth, { signature: ok, kind: 'subscription_sol', plan: 'monthly' })).status).toBe('credited');
    expect((await processCredit(deps(), auth, { signature: ok, kind: 'subscription_sol', plan: 'monthly' })).status).toBe('already_processed');
    expect((await db.doc(`users/${UID}`).get()).get('premiumUntil')).toBe(clock + 30 * D);
  });
  it('a monthly-priced payment cannot be claimed as yearly', async () => {
    const sig = newSig(); paySol(sig, 37_375_000);
    expect((await processCredit(deps(), auth, { signature: sig, kind: 'subscription_sol', plan: 'yearly' })).reason).toBe('PLAN_PRICE_NOT_MET');
  });
});
