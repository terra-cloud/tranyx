// Runs against the Firestore emulator (npm run test:emulator). Solana is a controllable fake.
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { Keypair } from '@solana/web3.js';
import { executeSend, processP2pAction, processWithdrawal, reconcileAll, reconcileOne, type Deps, type Log } from '../src/withdraw';
import type { PreparedTransfer, SignatureOutcome, SolanaPayer, TransferRequest } from '../src/solana';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8189';
initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();

class FakePayer implements SolanaPayer {
  prepared: TransferRequest[] = [];
  broadcasts: string[] = [];
  prepareError: Error | null = null;
  broadcastError: Error | null = null;
  outcomeNow: SignatureOutcome = { state: 'confirmed' };
  outcomeQueue: SignatureOutcome[] = []; // consumed first, then falls back to outcomeNow
  landed = false; // did the tx really land (for "timeout but it landed" cases)
  private n = 0;
  async prepare(t: TransferRequest): Promise<PreparedTransfer> {
    if (this.prepareError) throw this.prepareError;
    this.prepared.push(t);
    return { signature: `sig-${++this.n}`, rawBase64: 'AA==', lastValidBlockHeight: 500 };
  }
  async broadcast(p: PreparedTransfer) {
    this.broadcasts.push(p.signature);
    if (this.broadcastError) throw this.broadcastError;
  }
  async outcome(): Promise<SignatureOutcome> {
    return this.outcomeQueue.length ? this.outcomeQueue.shift()! : this.outcomeNow;
  }
}

let payer: FakePayer;
let clock = Date.UTC(2026, 9, 29, 4, 0, 0);
const logged: { level: string; msg: string; data?: Record<string, unknown> }[] = [];
const log: Log = {
  warn: (msg, data) => void logged.push({ level: 'warn', msg, data }),
  error: (msg, data) => void logged.push({ level: 'error', msg, data }),
};
const MIN = 60_000;
const deps = (): Deps => ({
  db,
  log,
  payer: () => payer,
  rates: async () => ({ solPhp: 8000, usdtPhp: 57 }),
  now: () => clock,
});

const wallet = Keypair.generate().publicKey.toBase58();
const attacker = Keypair.generate().publicKey.toBase58();
const UID = 'user1';
const auth = { uid: UID };

async function clearAll() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-tranyx/databases/(default)/documents`, { method: 'DELETE' });
}
async function seedUser(over: Record<string, unknown> = {}, uid = UID) {
  await db.doc(`users/${uid}`).set({ name: 'Test', email: 't@example.com', tyxBalance: 1000, walletPublicKey: wallet, ...over });
  // The payout-wallet cooldown is satisfied by default (wallet unchanged for 2 days); its own tests override this.
  await db.doc(`payout_wallet_state/${uid}`).set({ uid, wallet: (over.walletPublicKey as string | undefined) ?? wallet, since: Date.UTC(2026, 9, 27, 4, 0, 0) });
}
const bal = async (uid = UID) => (await db.doc(`users/${uid}`).get()).get('tyxBalance') as number;
const reqDoc = async (key: string) => (await db.doc(`withdrawal_requests/${key}`).get()).data()!;
const sol = (over: Record<string, unknown> = {}) => ({
  idempotencyKey: randomUUID(), method: 'solana', amount: 500, coin: 'USDT', ...over,
});
/** Withdrawals are OFF by default (K1); tests that exercise them turn the kill switch off explicitly. */
const enable = (over: Record<string, unknown> = {}) => db.doc('config/withdrawals').set({ enabled: true, ...over });
const err = async (p: Promise<unknown>) => p.then(() => null, (e) => e as { code: string; message: string });

beforeAll(async () => { await clearAll(); });
beforeEach(async () => {
  await clearAll();
  payer = new FakePayer();
  logged.length = 0;
  clock = Date.UTC(2026, 9, 29, 4, 0, 0);
  await seedUser();
  await enable();
});

describe('KAN-146 withdraw callable core', () => {
  it('denies unauthenticated callers and never touches the payer', async () => {
    const e = await err(processWithdrawal(deps(), undefined, sol()));
    expect(e?.code).toBe('unauthenticated');
    expect(payer.prepared).toHaveLength(0);
  });

  it('denies amount > balance with no debit and no send', async () => {
    const e = await err(processWithdrawal(deps(), auth, sol({ amount: 1000.01 })));
    expect(e?.code).toBe('failed-precondition');
    expect(await bal()).toBe(1000);
    expect(payer.broadcasts).toHaveLength(0);
  });

  it('respects reservedBalance (spendable = tyxBalance - reservedBalance)', async () => {
    await seedUser({ reservedBalance: 800 });
    const e = await err(processWithdrawal(deps(), auth, sol({ amount: 300 })));
    expect(e?.code).toBe('failed-precondition');
  });

  it('rejects bad input (non-uuid key, 3 decimals, negative, unknown coin, below min)', async () => {
    for (const bad of [
      sol({ idempotencyKey: 'abc' }), sol({ amount: 100.123 }), sol({ amount: -5 }),
      sol({ coin: 'DOGE' }), sol({ amount: '500' }), sol({ method: 'wire' }),
    ]) {
      expect((await err(processWithdrawal(deps(), auth, bad)))?.code).toBe('invalid-argument');
    }
    expect((await err(processWithdrawal(deps(), auth, sol({ amount: 99 }))))?.code).toBe('invalid-argument');
    expect(await bal()).toBe(1000);
  });

  it('ignores client-sent fee/net/rate/crypto/wallet/status: server computes 2% and pays the linked wallet', async () => {
    const r = await processWithdrawal(deps(), auth, sol({
      amount: 500, coin: 'USDT', feeAmount: 0, netAmount: 500, rate: 1, cryptoAmount: 999999,
      walletPublicKey: attacker, recipient: attacker, status: 'Successful', fee: 0, tyxBalance: 99999,
    }));
    expect(r.feeAmount).toBe(10);
    expect(r.netAmount).toBe(490);
    expect(r.rate).toBe(57);
    expect(r.cryptoAmount).toBeCloseTo(490 / 57, 5);
    expect(r.payoutState).toBe('sent');
    expect(payer.prepared[0].recipient).toBe(wallet);
    expect(payer.prepared[0].baseUnits).toBe(BigInt(Math.floor((490 / 57) * 1e6)));
    expect(await bal()).toBe(500); // exactly the gross amount debited
    const d = await reqDoc(r.id);
    expect(d.walletPublicKey).toBe(wallet);
    expect(d.status).toBe('Successful');
    expect((await db.doc(`withdrawalRequests/${r.id}`).get()).get('payoutState')).toBe('sent'); // mirror
    expect((await db.doc(`transactions/wd_${r.id}`).get()).get('amount')).toBe(-500);
  });

  it('SOL uses lamports (9 decimals) and the SOL rate', async () => {
    const r = await processWithdrawal(deps(), auth, sol({ amount: 800, coin: 'SOL' }));
    expect(payer.prepared[0].coin).toBe('SOL');
    expect(payer.prepared[0].baseUnits).toBe(BigInt(Math.floor((784 / 8000) * 1e9)));
    expect(r.rate).toBe(8000);
  });

  it('idempotent retry pays once (same key sequentially and in parallel)', async () => {
    const body = sol();
    const a = await processWithdrawal(deps(), auth, body);
    const b = await processWithdrawal(deps(), auth, body);
    expect(a.idempotentReplay).toBe(false);
    expect(b.idempotentReplay).toBe(true);
    expect(b.payoutState).toBe('sent');
    expect(payer.broadcasts).toHaveLength(1);
    expect(await bal()).toBe(500);

    const body2 = sol();
    const [c, d] = await Promise.all([
      processWithdrawal(deps(), auth, body2), processWithdrawal(deps(), auth, body2),
    ]);
    expect(c.id).toBe(d.id);
    expect(payer.broadcasts).toHaveLength(2); // one more, not two
    expect(await bal()).toBe(0);
  });

  it('K10: replay with the same key and different parameters returns the original and flags the mismatch', async () => {
    const key = randomUUID();
    const a = await processWithdrawal(deps(), auth, sol({ idempotencyKey: key, amount: 100 }));
    expect(a.idempotencyMismatch).toBe(false);
    const same = await processWithdrawal(deps(), auth, sol({ idempotencyKey: key, amount: 100 }));
    expect(same.idempotentReplay).toBe(true);
    expect(same.idempotencyMismatch).toBe(false);
    for (const change of [{ amount: 900 }, { coin: 'SOL' }, { method: 'p2p', p2p: { paymentMethod: 'GCash', accountName: 'A', accountNumber: '1' } }]) {
      const b = await processWithdrawal(deps(), auth, { ...sol({ idempotencyKey: key, amount: 100 }), ...change });
      expect(b.idempotentReplay).toBe(true);
      expect(b.idempotencyMismatch).toBe(true);
      expect(b.amount).toBe(100); // the ORIGINAL
      expect(b.id).toBe(a.id);
    }
    expect(await bal()).toBe(900); // one debit only
    expect(payer.prepared).toHaveLength(1);
  });

  it('K13: optional KYC gate (config requireIdVerified) applies to Solana and P2P; off by default', async () => {
    const p2p = () => ({ idempotencyKey: randomUUID(), method: 'p2p', amount: 200, p2p: { paymentMethod: 'Maya', accountName: 'A', accountNumber: '0917' } });
    expect((await processWithdrawal(deps(), auth, sol({ amount: 100 }))).ok).toBe(true); // default: no KYC needed
    await enable({ requireIdVerified: true });
    for (const input of [sol({ amount: 100 }), p2p()]) {
      expect((await err(processWithdrawal(deps(), auth, input)))?.code).toBe('failed-precondition');
    }
    await seedUser({ idVerified: 'true', tyxBalance: 900 }); // only boolean true counts
    expect((await err(processWithdrawal(deps(), auth, sol({ amount: 100 }))))?.code).toBe('failed-precondition');
    await seedUser({ idVerified: true, tyxBalance: 900 });
    expect((await processWithdrawal(deps(), auth, sol({ amount: 100 }))).ok).toBe(true);
    expect((await processWithdrawal(deps(), auth, p2p())).status).toBe('WAITING_FOR_AGENT');
  });

  it("someone else's idempotency key is rejected without leaking", async () => {
    await seedUser({}, 'user2');
    const body = sol();
    await processWithdrawal(deps(), auth, body);
    const e = await err(processWithdrawal(deps(), { uid: 'user2' }, body));
    expect(e?.code).toBe('already-exists');
    expect(await bal('user2')).toBe(1000);
  });

  it('two parallel calls whose total exceeds balance: exactly one succeeds', async () => {
    await seedUser({ tyxBalance: 700 });
    const results = await Promise.allSettled([
      processWithdrawal(deps(), auth, sol({ amount: 500 })),
      processWithdrawal(deps(), auth, sol({ amount: 500 })),
    ]);
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    const rejected = results.find((r) => r.status === 'rejected') as PromiseRejectedResult;
    expect((rejected.reason as { code: string }).code).toBe('failed-precondition');
    expect(await bal()).toBe(200);
    expect(payer.broadcasts).toHaveLength(1);
  });

  it('five parallel calls of 300 on a 1000 balance: at most three succeed, never negative', async () => {
    const results = await Promise.allSettled(Array.from({ length: 5 }, () => processWithdrawal(deps(), auth, sol({ amount: 300 }))));
    const ok = results.filter((r) => r.status === 'fulfilled').length;
    expect(ok).toBe(3);
    expect(await bal()).toBe(100);
    expect(payer.broadcasts).toHaveLength(3);
  });

  it('daily count limit (3/day) and daily amount limit', async () => {
    for (let i = 0; i < 3; i++) await processWithdrawal(deps(), auth, sol({ amount: 100 }));
    const e = await err(processWithdrawal(deps(), auth, sol({ amount: 100 })));
    expect(e?.code).toBe('resource-exhausted');
    expect(await bal()).toBe(700);
    // next Manila day resets
    clock += 24 * 3600 * 1000;
    await processWithdrawal(deps(), auth, sol({ amount: 100 }));

    await enable({ dailyMaxPhp: 250, dailyMaxCount: 10, maxPhp: 1000 });
    await seedUser({ tyxBalance: 5000 });
    clock += 24 * 3600 * 1000;
    await processWithdrawal(deps(), auth, sol({ amount: 200 }));
    const e2 = await err(processWithdrawal(deps(), auth, sol({ amount: 100 })));
    expect(e2?.code).toBe('resource-exhausted');
  });

  it('config/withdrawals min/max and kill switch', async () => {
    await enable({ minPhp: 200, maxPhp: 600 });
    expect((await err(processWithdrawal(deps(), auth, sol({ amount: 150 }))))?.code).toBe('invalid-argument');
    expect((await err(processWithdrawal(deps(), auth, sol({ amount: 700 }))))?.code).toBe('invalid-argument');
    await db.doc('config/withdrawals').set({ enabled: false });
    expect((await err(processWithdrawal(deps(), auth, sol())))?.code).toBe('failed-precondition');
  });

  it('K1: DISABLED BY DEFAULT: no config doc, or anything other than boolean true, rejects Solana and P2P with no debit', async () => {
    const p2p = { idempotencyKey: randomUUID(), method: 'p2p', amount: 500, p2p: { paymentMethod: 'GCash', accountName: 'A', accountNumber: '0917' } };
    await db.doc('config/withdrawals').delete();
    for (const cfg of [null, {}, { minPhp: 100 }, { enabled: 'true' }, { enabled: 1 }, { enabled: null }, { enabled: false }]) {
      if (cfg) await db.doc('config/withdrawals').set(cfg);
      for (const input of [sol(), p2p]) {
        const e = await err(processWithdrawal(deps(), auth, { ...input, idempotencyKey: randomUUID() }));
        expect(e?.code).toBe('failed-precondition');
      }
    }
    expect(await bal()).toBe(1000);
    expect(payer.prepared).toHaveLength(0);
    await enable();
    expect((await processWithdrawal(deps(), auth, sol({ amount: 100 }))).ok).toBe(true);
  });

  it('blocks banned users, users without a linked wallet, and users with active rentals', async () => {
    await seedUser({ banned: true });
    expect((await err(processWithdrawal(deps(), auth, sol())))?.code).toBe('permission-denied');
    await seedUser({ walletPublicKey: '' });
    expect((await err(processWithdrawal(deps(), auth, sol())))?.code).toBe('failed-precondition');
    await seedUser();
    await db.doc('rentals/r1').set({ renteeId: UID, status: 'Active' });
    expect((await err(processWithdrawal(deps(), auth, sol())))?.code).toBe('failed-precondition');
    await db.doc('rentals/r1').set({ renteeId: UID, status: 'Completed' });
    expect((await processWithdrawal(deps(), auth, sol())).payoutState).toBe('sent');
  });

  it('rate failure or insane rate rejects before any debit', async () => {
    const d = deps();
    d.rates = async () => { throw new Error('down'); };
    expect((await err(processWithdrawal(d, auth, sol())))?.code).toBe('unavailable');
    d.rates = async () => ({ solPhp: 8000, usdtPhp: 0.5 });
    expect((await err(processWithdrawal(d, auth, sol())))?.code).toBe('unavailable');
    expect(await bal()).toBe(1000);
  });

  describe('send failure handling (debit committed first, then interaction)', () => {
    it('could not build/sign tx: refunded immediately, nothing sent', async () => {
      payer.prepareError = new Error('rpc down');
      const r = await processWithdrawal(deps(), auth, sol());
      expect(r.payoutState).toBe('failed');
      expect(r.ok).toBe(false);
      expect(r.failureReason).toBe('PREPARE_FAILED');
      expect(await bal()).toBe(1000);
      expect(payer.broadcasts).toHaveLength(0);
    });

    it('debit is committed BEFORE broadcast (pending doc + signature persisted first)', async () => {
      let seen: Record<string, any> | null = null;
      const orig = payer.broadcast.bind(payer);
      payer.broadcast = async (p) => {
        const q = await db.collection('withdrawal_requests').get();
        seen = q.docs[0].data();
        return orig(p);
      };
      await processWithdrawal(deps(), auth, sol());
      expect(seen!.payoutState).toBe('submitting');
      expect(seen!.solanaTxSignature).toBe('sig-1');
      expect(seen!.lastValidBlockHeight).toBe(500);
      expect(await bal()).toBe(500);
    });

    it('broadcast timeout but tx LANDED -> sent, no refund', async () => {
      payer.broadcastError = new Error('timeout');
      payer.outcomeNow = { state: 'confirmed' };
      const r = await processWithdrawal(deps(), auth, sol());
      expect(r.payoutState).toBe('sent');
      expect(await bal()).toBe(500);
      expect((await reqDoc(r.id)).refundedAt).toBeUndefined();
    });

    it('broadcast timeout and blockhash EXPIRED -> NOT refunded at request time; refunded exactly once after 2 reconciler passes', async () => {
      payer.broadcastError = new Error('timeout');
      payer.outcomeNow = { state: 'expired' };
      const r = await processWithdrawal(deps(), auth, sol());
      expect(r.payoutState).toBe('pending_confirmation'); // the request itself never refunds on a candidate expiry
      expect(await bal()).toBe(500);
      await reconcileAll(deps()); // pass 1 (observation 1)
      expect(await bal()).toBe(500);
      clock += 5 * MIN;
      await reconcileAll(deps()); // pass 2 (observation 2) -> refund
      expect(await bal()).toBe(1000);
      clock += 5 * MIN;
      await reconcileAll(deps()); await reconcileAll(deps());
      await processWithdrawal(deps(), auth, { ...sol(), idempotencyKey: r.id }); // replay of the failed key
      expect(await bal()).toBe(1000);
      expect((await reqDoc(r.id)).payoutState).toBe('failed');
      const usage = await db.collection('withdrawal_usage').get();
      expect(usage.docs[0].get('count')).toBe(0);
    });

    it('on-chain error -> refunded exactly once', async () => {
      payer.broadcastError = new Error('boom');
      payer.outcomeNow = { state: 'failed', error: '{"InstructionError":[0,"Custom"]}' };
      const r = await processWithdrawal(deps(), auth, sol());
      expect(r.payoutState).toBe('failed');
      expect(r.failureReason).toBe('ONCHAIN_ERROR');
      await reconcileAll(deps()); await reconcileAll(deps());
      expect(await bal()).toBe(1000);
      expect((await db.doc(`transactions/wd_${r.id}`).get()).get('status')).toBe('Failed');
    });

    it('ambiguous (still within validity window) -> pending_confirmation, NO refund; later confirmed -> sent', async () => {
      payer.broadcastError = new Error('timeout');
      payer.outcomeNow = { state: 'waiting' };
      const r = await processWithdrawal(deps(), auth, sol());
      expect(r.payoutState).toBe('pending_confirmation');
      expect(await bal()).toBe(500);
      await reconcileAll(deps());
      expect((await reqDoc(r.id)).payoutState).toBe('pending_confirmation');
      expect(await bal()).toBe(500);
      // a retry with the same key must not resend either
      await processWithdrawal(deps(), auth, { ...sol(), idempotencyKey: r.id });
      expect(payer.broadcasts).toHaveLength(1);
      payer.outcomeNow = { state: 'confirmed' };
      await reconcileAll(deps());
      expect((await reqDoc(r.id)).payoutState).toBe('sent');
      await reconcileAll(deps());
      expect(await bal()).toBe(500);
    });

    it('ambiguous then expired -> refunded once; reconciler run repeatedly does not double refund', async () => {
      payer.broadcastError = new Error('timeout');
      payer.outcomeNow = { state: 'waiting' };
      const r = await processWithdrawal(deps(), auth, sol());
      payer.outcomeNow = { state: 'expired' };
      const a = await reconcileAll(deps());
      clock += 5 * MIN;
      const b = await reconcileAll(deps());
      clock += 5 * MIN;
      const c = await reconcileAll(deps());
      expect(a.settled).toBe(0);
      expect(b.settled).toBe(1);
      expect(c.settled).toBe(0);
      expect(await bal()).toBe(1000);
      expect((await reqDoc(r.id)).payoutState).toBe('failed');
    });

    it('sent withdrawals are never refunded by a late reconcile / expired outcome', async () => {
      const r = await processWithdrawal(deps(), auth, sol());
      payer.outcomeNow = { state: 'expired' };
      await reconcileAll(deps());
      expect(await bal()).toBe(500);
      expect((await reqDoc(r.id)).payoutState).toBe('sent');
    });

    it('crash after commit but before claim: reconciler re-drives stale pending exactly once', async () => {
      await db.runTransaction(async (tx) => {
        // simulate: committed pending doc, function died before sending
        tx.set(db.doc('users/user1'), { tyxBalance: 500 }, { merge: true });
        tx.set(db.doc('withdrawal_requests/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), {
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', uid: UID, method: 'solana', payoutState: 'pending', status: 'Pending',
          amount: 500, coin: 'USDT', baseUnits: '8596491', walletPublicKey: wallet, paymentMethod: 'Solana (USDT)',
          balanceDeducted: true, createdAt: clock - 10 * 60_000,
        });
      });
      await reconcileAll(deps());
      await reconcileAll(deps());
      expect(payer.broadcasts).toHaveLength(1);
      expect((await reqDoc('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).payoutState).toBe('sent');
    });
  });


  describe('payout wallet cooldown (a repointed profile wallet cannot be cashed out immediately)', () => {
    const newWallet = Keypair.generate().publicKey.toBase58();
    const H = 3600_000;
    const state = async () => (await db.doc(`payout_wallet_state/${UID}`).get()).data();

    it('a changed wallet is refused, recorded, and unlocks after 24h; nothing is debited meanwhile', async () => {
      await db.doc(`users/${UID}`).update({ walletPublicKey: newWallet });
      const e1 = await err(processWithdrawal(deps(), auth, sol()));
      expect(e1?.code).toBe('failed-precondition');
      expect(e1?.message).toMatch(/payout wallet was changed recently/);
      expect(await bal()).toBe(1000);
      expect(payer.broadcasts).toHaveLength(0);
      expect(await state()).toMatchObject({ wallet: newWallet, since: clock });

      clock += 23 * H;
      expect((await err(processWithdrawal(deps(), auth, sol())))?.code).toBe('failed-precondition');
      expect((await state())!.since).toBe(Date.UTC(2026, 9, 29, 4, 0, 0)); // the clock did not restart
      expect(await bal()).toBe(1000);

      clock += 1 * H;
      const ok = await processWithdrawal(deps(), auth, sol());
      expect(ok.ok).toBe(true);
      expect(payer.prepared[0].recipient).toBe(newWallet);
    });

    it('changing the wallet again restarts the clock', async () => {
      await db.doc(`users/${UID}`).update({ walletPublicKey: newWallet });
      await err(processWithdrawal(deps(), auth, sol()));
      clock += 30 * H;
      const third = Keypair.generate().publicKey.toBase58();
      await db.doc(`users/${UID}`).update({ walletPublicKey: third });
      expect((await err(processWithdrawal(deps(), auth, sol())))?.code).toBe('failed-precondition');
      expect(await state()).toMatchObject({ wallet: third, since: clock });
    });

    it('with no server record yet (first request after rollout) the clock starts at that request', async () => {
      await db.doc(`payout_wallet_state/${UID}`).delete();
      expect((await err(processWithdrawal(deps(), auth, sol())))?.code).toBe('failed-precondition');
      expect((await state())!.since).toBe(clock);
      clock += 24 * H;
      expect((await processWithdrawal(deps(), auth, sol())).ok).toBe(true);
    });

    it('walletCooldownHours 0 disables it; P2P is not affected', async () => {
      await db.doc(`users/${UID}`).update({ walletPublicKey: newWallet });
      const p2p = { idempotencyKey: randomUUID(), method: 'p2p', amount: 200, p2p: { paymentMethod: 'GCash', accountName: 'A', accountNumber: '09171234567', qrUrl: '' } };
      expect((await processWithdrawal(deps(), auth, p2p)).ok).toBe(true);
      await enable({ walletCooldownHours: 0 });
      expect((await processWithdrawal(deps(), auth, sol())).ok).toBe(true);
    });
  });

  describe('K6: callers and client-readable docs only ever see generic failure codes', () => {
    const SECRET = 'https://rpc.example.test/v1?api-key=SECRETISH-123 connect ECONNREFUSED 10.0.0.7:8899';
    const everything = async (id: string) => {
      const docs = [
        `withdrawal_requests/${id}`, `withdrawalRequests/${id}`, `transactions/wd_${id}`, `wallets/${UID}/transactions/${id}`,
      ];
      return JSON.stringify(await Promise.all(docs.map(async (d) => (await db.doc(d).get()).data() ?? null)));
    };
    const leaks = (s: string) => /SECRETISH|api-key|rpc\.example|ECONNREFUSED|10\.0\.0\.7/.test(s);

    it('prepare failure: code only in the response and in every stored doc; detail only in logs (URL stripped)', async () => {
      payer.prepareError = new Error(SECRET);
      const r = await processWithdrawal(deps(), auth, sol());
      expect(r.failureReason).toBe('PREPARE_FAILED');
      expect(leaks(JSON.stringify(r))).toBe(false);
      expect(leaks(await everything(r.id))).toBe(false);
      const l = logged.find((x) => x.msg === 'withdrawal prepare failed')!;
      expect(l).toBeDefined();
      expect(String(l.data!.detail)).toContain('[url]');
      expect(String(l.data!.detail)).not.toContain('SECRETISH');
    });

    it('ambiguous broadcast: lastError is a code; on-chain error and expiry refunds carry codes only', async () => {
      payer.broadcastError = new Error(SECRET);
      payer.outcomeNow = { state: 'waiting' };
      const r = await processWithdrawal(deps(), auth, sol());
      expect(r.payoutState).toBe('pending_confirmation');
      expect((await reqDoc(r.id)).lastError).toBe('BROADCAST_AMBIGUOUS');
      expect(leaks(JSON.stringify(r)) || leaks(await everything(r.id))).toBe(false);
      payer.outcomeNow = { state: 'expired' };
      await reconcileAll(deps());
      clock += 5 * MIN;
      await reconcileAll(deps());
      const d = await reqDoc(r.id);
      expect(d.failureReason).toBe('EXPIRED_NOT_LANDED');
      expect(leaks(await everything(r.id))).toBe(false);
    });

    it('on-chain error text never reaches the caller or the docs', async () => {
      payer.broadcastError = new Error('x');
      payer.outcomeNow = { state: 'failed', error: SECRET };
      const r = await processWithdrawal(deps(), auth, sol());
      expect(r.failureReason).toBe('ONCHAIN_ERROR');
      expect(leaks(JSON.stringify(r)) || leaks(await everything(r.id))).toBe(false);
    });

    it('a legacy/free-text failureReason in a stored doc is mapped to a code on replay', async () => {
      payer.prepareError = new Error('x');
      const r = await processWithdrawal(deps(), auth, sol());
      await db.doc(`withdrawal_requests/${r.id}`).set({ failureReason: 'fetch failed https://x?api-key=SECRETISH' }, { merge: true });
      const again = await processWithdrawal(deps(), auth, { ...sol(), idempotencyKey: r.id });
      expect(again.failureReason).toBe('WITHDRAWAL_FAILED');
    });
  });

  describe('K7: concurrency on the refund / settle status guards', () => {
    const inflight = async (amount = 500) => {
      payer.broadcastError = new Error('timeout');
      payer.outcomeNow = { state: 'waiting' };
      const r = await processWithdrawal(deps(), auth, sol({ amount }));
      return r.id as string;
    };
    /** Makes N concurrent callers all read the in-flight doc and the chain answer BEFORE any of them writes. */
    const gated = (n: number, answer: SignatureOutcome) => {
      let arrived = 0;
      let open!: () => void;
      const gate = new Promise<void>((r) => (open = r));
      payer.outcome = async () => {
        if (++arrived >= n) open();
        await Promise.race([gate, new Promise((r) => setTimeout(r, 2000))]); // never hang if fewer callers show up
        return answer;
      };
    };
    const usageCount = async () => (await db.collection('withdrawal_usage').get()).docs[0].get('count') as number;

    it('five parallel reconciler runs on an expired in-flight transfer: exactly ONE refund (balance, usage, ledger)', async () => {
      const id = await inflight();
      payer.outcomeNow = { state: 'expired' };
      await Promise.all(Array.from({ length: 5 }, () => reconcileAll(deps()))); // observation 1
      expect(await bal()).toBe(500);
      clock += 5 * MIN;
      gated(5, { state: 'expired' });
      await Promise.all(Array.from({ length: 5 }, () => reconcileAll(deps()))); // observation 2 + refund race
      expect(await bal()).toBe(1000); // not 1500 / 2000 / ...
      expect((await reqDoc(id)).payoutState).toBe('failed');
      expect(await usageCount()).toBe(0);
      clock += 5 * MIN;
      await Promise.all(Array.from({ length: 5 }, () => reconcileAll(deps())));
      expect(await bal()).toBe(1000);
    });

    it('five parallel reconcileOne calls with the expiry threshold already met: exactly ONE refund', async () => {
      const id = await inflight(300);
      payer.outcomeNow = { state: 'expired' };
      await db.doc(`withdrawal_requests/${id}`).set({ expiryObservations: 2, expiryLastObservedAt: clock - 10 * MIN }, { merge: true });
      gated(5, { state: 'expired' });
      await Promise.all(Array.from({ length: 5 }, () => reconcileOne(deps(), id, { countExpiry: true })));
      expect(await bal()).toBe(1000);
      expect(await usageCount()).toBe(0);
    });

    it('race: one caller sees "confirmed", another "expired" (threshold met): never both sent AND refunded', async () => {
      for (let round = 0; round < 3; round++) {
        await clearAll();
        await enable();
        await seedUser();
        clock += 86_400_000;
        const id = await inflight();
        await db.doc(`withdrawal_requests/${id}`).set({ expiryObservations: 2, expiryLastObservedAt: clock - 10 * MIN }, { merge: true });
        payer.outcomeQueue = [{ state: 'confirmed' }, { state: 'expired' }];
        await Promise.all([reconcileOne(deps(), id, { countExpiry: true }), reconcileOne(deps(), id, { countExpiry: true })]);
        const d = await reqDoc(id);
        expect(['sent', 'failed']).toContain(d.payoutState);
        expect(await bal()).toBe(d.payoutState === 'sent' ? 500 : 1000); // exactly one outcome, funds consistent
      }
    });

    it('stale "confirmed" answer arriving AFTER the refund committed cannot flip failed -> sent (markSent guard)', async () => {
      const id = await inflight();
      await db.doc(`withdrawal_requests/${id}`).set({ expiryObservations: 2, expiryLastObservedAt: clock - 10 * MIN }, { merge: true });
      let calls = 0;
      let release!: () => void;
      const gateA = new Promise<void>((r) => (release = r));
      payer.outcome = async () => {
        if (++calls === 1) { await gateA; return { state: 'confirmed' }; } // A: slow answer
        return { state: 'expired' }; // B: fast answer
      };
      const a = reconcileOne(deps(), id);
      while (calls < 1) await new Promise((r) => setTimeout(r, 5));
      const b = await reconcileOne(deps(), id, { countExpiry: true });
      expect(b.payoutState).toBe('failed');
      release();
      const aRes = await a;
      expect(aRes.payoutState).toBe('failed');
      expect((await reqDoc(id)).payoutState).toBe('failed');
      expect((await reqDoc(id)).sentAt).toBeUndefined();
      expect(await bal()).toBe(1000);
    });

    it('five parallel executeSend on one pending request: exactly one broadcast', async () => {
      const key = randomUUID();
      await db.doc(`withdrawal_requests/${key}`).set({
        id: key, uid: UID, method: 'solana', payoutState: 'pending', status: 'Pending', coin: 'USDT', baseUnits: '1000000',
        walletPublicKey: wallet, amount: 100, paymentMethod: 'Solana (USDT)', balanceDeducted: true, createdAt: clock,
      });
      await Promise.all(Array.from({ length: 5 }, () => executeSend(deps(), key)));
      expect(payer.broadcasts).toHaveLength(1);
    });

    it('five parallel calls of 600 on a 1000 balance: EXACTLY one succeeds, balance 400, one transfer', async () => {
      const results = await Promise.allSettled(Array.from({ length: 5 }, () => processWithdrawal(deps(), auth, sol({ amount: 600 }))));
      expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
      expect(await bal()).toBe(400);
      expect(payer.prepared).toHaveLength(1);
    });

    it('five parallel calls of the FULL balance: exactly one succeeds, balance 0 (never negative)', async () => {
      const results = await Promise.allSettled(Array.from({ length: 5 }, () => processWithdrawal(deps(), auth, sol({ amount: 1000 }))));
      expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
      expect(await bal()).toBe(0);
    });
  });

  describe('K11: P2P cancel / confirm run server-side (one guarded transaction)', () => {
    const p2pReq = async (amount = 400) => {
      const r = await processWithdrawal(deps(), auth, { idempotencyKey: randomUUID(), method: 'p2p', amount, p2p: { paymentMethod: 'GCash', accountName: 'A', accountNumber: '0917' } });
      return r.id as string;
    };
    const act = (id: string, action: string, over: Record<string, unknown> = {}, a: { uid: string } | null = auth) =>
      processP2pAction(deps(), a ?? undefined, { withdrawalId: id, action, ...over });
    const setReq = (id: string, patch: Record<string, unknown>) => db.doc(`withdrawal_requests/${id}`).set(patch, { merge: true });

    it('cancel refunds exactly the held amount, restores the daily usage, updates every record', async () => {
      const id = await p2pReq(400);
      expect(await bal()).toBe(600);
      const r: any = await act(id, 'cancel', { reason: 'changed my mind' });
      expect(r).toMatchObject({ ok: true, status: 'CANCELLED', alreadyDone: false, newBalance: 1000 });
      expect(await bal()).toBe(1000);
      const d = await reqDoc(id);
      expect(d).toMatchObject({ status: 'CANCELLED', p2pStatus: 'CANCELLED', balanceDeducted: false, rejectionReason: 'changed my mind' });
      expect(d.refundedAt).toBeDefined();
      expect((await db.doc(`withdrawalRequests/${id}`).get()).get('status')).toBe('CANCELLED');
      expect((await db.doc(`transactions/p2p_with_${id}`).get()).get('status')).toBe('CANCELLED');
      expect((await db.doc(`wallets/${UID}/transactions/${id}`).get()).get('desc')).toContain('refunded');
      expect((await db.collection('withdrawal_usage').get()).docs[0].get('count')).toBe(0);
    });

    it('five parallel cancels, then more sequential ones: exactly ONE refund', async () => {
      const id = await p2pReq(400);
      const res = await Promise.all(Array.from({ length: 5 }, () => act(id, 'cancel')));
      expect(res.filter((r: any) => !r.alreadyDone)).toHaveLength(1);
      await act(id, 'cancel'); await act(id, 'cancel');
      expect(await bal()).toBe(1000);
    });

    it('cancel is only possible before an agent claims: claimed / proof sent / approved / rejected are refused, no refund', async () => {
      await enable({ dailyMaxCount: 10 });
      for (const status of ['AWAITING_AGENT_PAYMENT', 'PENDING_CONFIRMATION', 'APPROVED', 'REJECTED']) {
        const id = await p2pReq(100);
        await setReq(id, { status });
        const e = await err(act(id, 'cancel'));
        expect(e?.code).toBe('failed-precondition');
      }
      expect(await bal()).toBe(600); // all four holds still in place
    });

    it('a request whose balance was already refunded (balanceDeducted=false) cancels without a second refund', async () => {
      const id = await p2pReq(400);
      await setReq(id, { balanceDeducted: false });
      await act(id, 'cancel');
      expect(await bal()).toBe(600);
      expect((await reqDoc(id)).status).toBe('CANCELLED');
    });

    it('only the owner can act; unauthenticated, other users, unknown ids and Solana requests are refused', async () => {
      const id = await p2pReq(100);
      await seedUser({}, 'user2');
      expect((await err(act(id, 'cancel', {}, null)))?.code).toBe('unauthenticated');
      expect((await err(act(id, 'cancel', {}, { uid: 'user2' })))?.code).toBe('not-found');
      expect((await err(act('does-not-exist', 'cancel')))?.code).toBe('not-found');
      expect((await err(act('bad/id', 'cancel')))?.code).toBe('invalid-argument');
      expect((await err(act(id, 'delete')))?.code).toBe('invalid-argument');
      const s = await processWithdrawal(deps(), auth, sol({ amount: 100 }));
      expect((await err(act(s.id, 'cancel')))?.code).toBe('failed-precondition');
      expect(await bal()).toBe(800);
      expect((await reqDoc(id)).status).toBe('WAITING_FOR_AGENT');
    });

    it('works while withdrawals are switched off (users can always cancel and get refunded)', async () => {
      const id = await p2pReq(100);
      await db.doc('config/withdrawals').set({ enabled: false });
      expect(((await act(id, 'cancel')) as any).newBalance).toBe(1000);
    });

    it('confirm: only after the agent sent proof; idempotent; cannot cancel afterwards; notifies', async () => {
      const id = await p2pReq(100);
      expect((await err(act(id, 'confirm')))?.code).toBe('failed-precondition');
      await setReq(id, { status: 'PENDING_CONFIRMATION', referenceNumber: 'ABC123' });
      const r: any = await act(id, 'confirm');
      expect(r).toMatchObject({ ok: true, status: 'APPROVED', alreadyDone: false });
      const d = await reqDoc(id);
      expect(d).toMatchObject({ status: 'APPROVED', p2pStatus: 'COMPLETED', adminUid: UID });
      expect((await db.doc(`transactions/p2p_with_${id}`).get()).get('desc')).toContain('#ABC123');
      expect(((await act(id, 'confirm')) as any).alreadyDone).toBe(true);
      expect((await err(act(id, 'cancel')))?.code).toBe('failed-precondition');
      expect(await bal()).toBe(900); // no refund
      const notes = await db.collection('notifications').where('type', '==', 'withdrawal_completed').get();
      expect(notes.size).toBe(1);
    });
  });

  describe('K4: reconciler never refunds on a lagging or single observation', () => {
    const inflight = async () => {
      payer.broadcastError = new Error('timeout');
      payer.outcomeNow = { state: 'waiting' };
      const r = await processWithdrawal(deps(), auth, sol());
      payer.outcomeNow = { state: 'expired' };
      return r.id as string;
    };

    it('a single "not found past expiry" pass does not refund (one pass, even many calls in the same minute)', async () => {
      const id = await inflight();
      await reconcileAll(deps());
      await reconcileAll(deps());
      await Promise.all([reconcileAll(deps()), reconcileAll(deps()), reconcileAll(deps())]);
      const d = await reqDoc(id);
      expect(d.payoutState).toBe('pending_confirmation');
      expect(d.expiryObservations).toBe(1); // overlapping runs inside the gap count once
      expect(await bal()).toBe(500);
    });

    it('idempotent retries and the request itself never count toward the two-pass rule', async () => {
      const id = await inflight();
      for (let i = 0; i < 4; i++) {
        clock += 5 * MIN;
        await processWithdrawal(deps(), auth, { ...sol(), idempotencyKey: id });
      }
      expect((await reqDoc(id)).payoutState).toBe('pending_confirmation');
      expect((await reqDoc(id)).expiryObservations ?? 0).toBe(0);
      expect(await bal()).toBe(500);
    });

    it('lagging node: expired on pass 1, then the node catches up and the tx is CONFIRMED -> sent, never refunded', async () => {
      const id = await inflight();
      await reconcileAll(deps());
      clock += 5 * MIN;
      payer.outcomeNow = { state: 'confirmed' };
      await reconcileAll(deps());
      expect((await reqDoc(id)).payoutState).toBe('sent');
      clock += 5 * MIN;
      payer.outcomeNow = { state: 'expired' };
      await reconcileAll(deps());
      expect(await bal()).toBe(500);
      expect(logged.filter((l) => l.level === 'error')).toHaveLength(0);
    });

    it('a "waiting" answer between two expiries resets the counter (passes must be consecutive)', async () => {
      const id = await inflight();
      await reconcileAll(deps());
      expect((await reqDoc(id)).expiryObservations).toBe(1);
      clock += 5 * MIN;
      payer.outcomeNow = { state: 'waiting' }; // e.g. a different node in the pool is still behind
      await reconcileAll(deps());
      expect((await reqDoc(id)).expiryObservations).toBe(0);
      clock += 5 * MIN;
      payer.outcomeNow = { state: 'expired' };
      await reconcileAll(deps());
      expect((await reqDoc(id)).payoutState).toBe('pending_confirmation');
      expect(await bal()).toBe(500);
      clock += 5 * MIN;
      await reconcileAll(deps());
      expect((await reqDoc(id)).payoutState).toBe('failed');
      expect(await bal()).toBe(1000);
    });

    it('an RPC outage during a pass is "waiting", never a refund', async () => {
      const id = await inflight();
      payer.outcome = async () => { throw new Error('rpc 503'); };
      for (let i = 0; i < 3; i++) { clock += 5 * MIN; await reconcileAll(deps()); }
      expect((await reqDoc(id)).payoutState).toBe('pending_confirmation');
      expect(await bal()).toBe(500);
    });

    it('LATE CONFIRM after failure is flagged (error log + admin alert + staff-review flag) and never auto-debits', async () => {
      const id = await inflight();
      await reconcileAll(deps());
      clock += 5 * MIN;
      await reconcileAll(deps());
      let d = await reqDoc(id);
      expect(d.payoutState).toBe('failed');
      expect(d.lateWatch).toBe(true);
      expect(await bal()).toBe(1000);
      // a pass while it still has not landed: nothing to flag
      clock += 5 * MIN;
      expect((await reconcileAll(deps())).lateConfirmed).toBe(0);
      // the signature confirms after the refund
      payer.outcomeNow = { state: 'confirmed' };
      clock += 5 * MIN;
      const res = await reconcileAll(deps());
      expect(res.lateConfirmed).toBe(1);
      d = await reqDoc(id);
      expect(d.payoutState).toBe('failed'); // untouched: staff decide
      expect(d.lateConfirmAfterFailure).toBe(true);
      expect(d.needsStaffReview).toBe(true);
      expect(d.lateWatch).toBe(false);
      expect(await bal()).toBe(1000);
      const alert = (await db.doc(`withdrawal_alerts/${id}`).get()).data()!;
      expect(alert.type).toBe('late_confirm_after_failure');
      expect(alert.signature).toBe(d.solanaTxSignature);
      expect(alert.uid).toBe(UID);
      const errs = logged.filter((l) => l.level === 'error');
      expect(errs).toHaveLength(1);
      expect(errs[0].msg).toBe('WITHDRAWAL_LATE_CONFIRM_AFTER_FAILURE');
      // flagged once only
      clock += 5 * MIN;
      expect((await reconcileAll(deps())).lateConfirmed).toBe(0);
      expect(logged.filter((l) => l.level === 'error')).toHaveLength(1);
    });

    it('stops watching a refunded signature after the late-watch window', async () => {
      const id = await inflight();
      await reconcileAll(deps());
      clock += 5 * MIN;
      await reconcileAll(deps());
      expect((await reqDoc(id)).lateWatch).toBe(true);
      clock += 8 * 24 * 3600 * 1000;
      payer.outcomeNow = { state: 'confirmed' };
      expect((await reconcileAll(deps())).lateConfirmed).toBe(0);
      expect((await reqDoc(id)).lateWatch).toBe(false);
    });

    it('on-chain error (confirmed with err) still refunds immediately and is not late-watched', async () => {
      payer.broadcastError = new Error('boom');
      payer.outcomeNow = { state: 'failed', error: '{"InstructionError":[0,"Custom"]}' };
      const r = await processWithdrawal(deps(), auth, sol());
      expect(r.payoutState).toBe('failed');
      expect((await reqDoc(r.id)).lateWatch).toBeUndefined();
    });
  });

  describe('P2P (GCash/Maya) manual review', () => {
    const p2p = (over: Record<string, unknown> = {}) => ({
      idempotencyKey: randomUUID(), method: 'p2p', amount: 300,
      p2p: { paymentMethod: 'GCash', accountName: 'Juan', accountNumber: '09171234567' }, ...over,
    });
    it('debits server-side, fee 0, stays WAITING_FOR_AGENT, never touches Solana; client fee ignored', async () => {
      const r = await processWithdrawal(deps(), auth, p2p({ feeAmount: 0, netAmount: 9999, status: 'APPROVED' }));
      expect(r.status).toBe('WAITING_FOR_AGENT');
      expect(r.feeAmount).toBe(0);
      expect(r.netAmount).toBe(300);
      expect(await bal()).toBe(700);
      expect(payer.prepared).toHaveLength(0);
      const d = await reqDoc(r.id);
      expect(d.originRail).toBe('manual_p2p');
      expect(d.userAccountNumber).toBe('09171234567');
      expect((await db.doc(`transactions/p2p_with_${r.id}`).get()).get('amount')).toBe(-300);
      expect((await db.doc(`withdrawalRequests/${r.id}`).get()).get('feeAmount')).toBe(0); // dual-collection mirror
      expect((await db.doc(`wallets/${UID}/transactions/${r.id}`).get()).get('amount')).toBe(300);
      expect((await db.doc(`notifications/notif_agent_with_${r.id}`).get()).get('type')).toBe('p2p_cashout_request');
      expect(d.p2pStatus).toBe('WAITING_FOR_AGENT');
      expect(d.balanceDeducted).toBe(true);
    });
    it('uses p2pFeeRate from config when staff set one; idempotent; balance checked; reconciler ignores it', async () => {
      await enable({ p2pFeeRate: 0.01 });
      const body = p2p();
      const a = await processWithdrawal(deps(), auth, body);
      const b = await processWithdrawal(deps(), auth, body);
      expect(a.feeAmount).toBe(3);
      expect(b.idempotentReplay).toBe(true);
      expect(await bal()).toBe(700);
      await reconcileAll(deps());
      expect(payer.prepared).toHaveLength(0);
      expect((await err(processWithdrawal(deps(), auth, p2p({ amount: 5000 }))))?.code).toBe('failed-precondition');
    });
    it('validates destination fields', async () => {
      expect((await err(processWithdrawal(deps(), auth, p2p({ p2p: { paymentMethod: 'Venmo', accountName: 'a', accountNumber: '1' } }))))?.code).toBe('invalid-argument');
      expect((await err(processWithdrawal(deps(), auth, p2p({ p2p: { paymentMethod: 'Maya', accountName: '', accountNumber: '1' } }))))?.code).toBe('invalid-argument');
    });
  });
});
