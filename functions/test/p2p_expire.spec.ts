import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { expireStaleP2p, P2P_EXPIRE_REASON } from '../src/p2p_expire';
import { processWithdrawal, type Deps, type Log } from '../src/withdraw';
import type { SolanaPayer } from '../src/solana';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8189';
initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();

const HOUR = 60 * 60 * 1000;
let clock = Date.UTC(2026, 10, 23, 0, 0, 0);
const log: Log = { warn: () => {}, error: () => {} };
const deps = (): Deps => ({
  db,
  log,
  payer: () => ({ prepare: async () => { throw new Error('no chain'); }, broadcast: async () => {}, outcome: async () => ({ state: 'waiting' }) }) as SolanaPayer,
  rates: async () => ({ solPhp: 8000, usdtPhp: 57 }),
  now: () => clock,
});

async function clearAll() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-tranyx/databases/(default)/documents`, { method: 'DELETE' });
}

beforeAll(async () => { await clearAll(); });
beforeEach(async () => {
  await clearAll();
  clock = Date.UTC(2026, 10, 23, 0, 0, 0);
  await db.doc('users/user1').set({ name: 'Test', tyxBalance: 1000, walletPublicKey: 'W' });
  await db.doc('payout_wallet_state/user1').set({ uid: 'user1', wallet: 'W', since: clock - 3 * 24 * HOUR });
  await db.doc('wallet_verified/W').set({ uid: 'user1', verifiedAt: clock - 10 * 24 * HOUR });
  await db.doc('config/withdrawals').set({ enabled: true });
});

const p2p = (amount: number) => ({
  idempotencyKey: randomUUID(),
  method: 'p2p' as const,
  amount,
  p2p: { paymentMethod: 'GCash' as const, accountName: 'A', accountNumber: '0917', qrUrl: '' },
});

describe('P2P 24h expiry', () => {
  it('expires a pending cashout and deposit older than 24h, refunds once, and leaves fresh and proof-submitted rows', async () => {
    const oldWd = await processWithdrawal(deps(), { uid: 'user1' }, p2p(200)) as { id: string };
    await db.doc('deposit_requests/old-dep').set({
      uid: 'user1', amount: 300, status: 'WAITING_FOR_AGENT', createdAt: clock, paymentMethod: 'GCash',
    });
    await db.doc('transactions/p2p_dep_old-dep').set({ uid: 'user1', status: 'WAITING_FOR_AGENT', amount: 300, createdAt: clock });

    clock += 2 * HOUR;
    const youngWd = await processWithdrawal(deps(), { uid: 'user1' }, p2p(100)) as { id: string };
    await db.doc('deposit_requests/young-dep').set({
      uid: 'user1', amount: 50, status: 'AWAITING_PAYMENT', createdAt: clock, paymentMethod: 'Maya',
    });
    await db.doc('deposit_requests/proof-dep').set({
      uid: 'user1', amount: 80, status: 'PENDING_VERIFICATION', createdAt: clock - 30 * HOUR,
      referenceNumber: 'REF1', proofImageUrl: 'https://example.test/proof.png', proofSubmittedAt: clock - 20 * HOUR,
      paymentMethod: 'GCash',
    });
    await db.doc('deposit_requests/approved-dep').set({
      uid: 'user1', amount: 90, status: 'APPROVED', createdAt: clock - 48 * HOUR, paymentMethod: 'GCash',
    });
    await db.doc('withdrawal_requests/proof-wd').set({
      uid: 'user1', method: 'p2p', amount: 40, status: 'PENDING_CONFIRMATION', balanceDeducted: true,
      createdAt: clock - 30 * HOUR, proofImageUrl: 'https://example.test/pay.png', referenceNumber: 'R2',
    });

    clock += 24 * HOUR;
    const first = await expireStaleP2p(deps());
    expect(first.withdrawalsExpired).toBe(1);
    expect(first.depositsExpired).toBe(1);

    expect((await db.doc(`withdrawal_requests/${oldWd.id}`).get()).get('status')).toBe('CANCELLED');
    expect((await db.doc(`withdrawal_requests/${oldWd.id}`).get()).get('rejectionReason')).toBe(P2P_EXPIRE_REASON);
    expect((await db.doc(`withdrawal_requests/${oldWd.id}`).get()).get('balanceDeducted')).toBe(false);
    expect((await db.doc(`withdrawal_requests/${youngWd.id}`).get()).get('status')).toBe('WAITING_FOR_AGENT');
    expect((await db.doc('withdrawal_requests/proof-wd').get()).get('status')).toBe('PENDING_CONFIRMATION');
    expect((await db.doc('deposit_requests/old-dep').get()).get('status')).toBe('CANCELLED');
    expect((await db.doc('deposit_requests/old-dep').get()).get('rejectionReason')).toBe(P2P_EXPIRE_REASON);
    expect((await db.doc('transactions/p2p_dep_old-dep').get()).get('status')).toBe('CANCELLED');
    expect((await db.doc('deposit_requests/young-dep').get()).get('status')).toBe('AWAITING_PAYMENT');
    expect((await db.doc('deposit_requests/proof-dep').get()).get('status')).toBe('PENDING_VERIFICATION');
    expect((await db.doc('deposit_requests/approved-dep').get()).get('status')).toBe('APPROVED');
    // 1000 - 200 - 100, then the 200 is refunded once.
    expect((await db.doc('users/user1').get()).get('tyxBalance')).toBe(900);
    expect((await db.doc(`staff_audit_log/p2p_expire_wd_${oldWd.id}`).get()).exists).toBe(true);
    expect((await db.doc('staff_audit_log/p2p_expire_dep_old-dep').get()).exists).toBe(true);

    const again = await expireStaleP2p(deps());
    expect(again.withdrawalsExpired).toBe(0);
    expect(again.depositsExpired).toBe(0);
    expect((await db.doc('users/user1').get()).get('tyxBalance')).toBe(900);
  });
});
