// Money & balances. KNOWN-HOLE tests carry the secure assertion inside knownHole().
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { knownHole, setupEnv, seed, user, adminClaim, guest, userProfile, withdrawal } from './helpers.mjs';

setupEnv();

describe('MON: tyxBalance is server-only (regression for 879fd40)', () => {
  it('MON-01 [CRITICAL] owner cannot INCREASE own tyxBalance', async () => {
    await seed({ 'users/u1': userProfile('u1', { tyxBalance: 100 }) });
    await assertFails(updateDoc(doc(user('u1'), 'users/u1'), { tyxBalance: 1000000 }));
  });
  it('MON-02 [HIGH] owner cannot set own tyxBalance to any client-chosen value, incl. decrease', async () => {
    await seed({ 'users/u1': userProfile('u1', { tyxBalance: 100 }) });
    await assertFails(updateDoc(doc(user('u1'), 'users/u1'), { tyxBalance: 40 }));
  });
  it('MON-03 [HIGH] negative tyxBalance rejected (compiled:154) — secure today', async () => {
    await seed({ 'users/u1': userProfile('u1', { tyxBalance: 100 }) });
    await assertFails(updateDoc(doc(user('u1'), 'users/u1'), { tyxBalance: -5 }));
  });
  it('MON-04 [HIGH] another user cannot write victim tyxBalance (no doc role) — secure today', async () => {
    await seed({ 'users/victim': userProfile('victim'), 'users/u2': userProfile('u2') });
    await assertFails(updateDoc(doc(user('u2'), 'users/victim'), { tyxBalance: 0 }));
  });
});

describe('MON: reservedBalance and staff still able to adjust money', () => {
  it('MON-02b [HIGH] owner cannot set own reservedBalance', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    await assertFails(updateDoc(doc(user('u1'), 'users/u1'), { reservedBalance: 50 }));
  });
  it('MON-02c [MUST-ALLOW] owner can still update ordinary profile fields while a tyxBalance is present', async () => {
    await seed({ 'users/u1': userProfile('u1', { tyxBalance: 100 }) });
    await assertSucceeds(updateDoc(doc(user('u1'), 'users/u1'), { headline: 'Plumber', skills: ['plumbing', 'tiling'] }));
  });
  it('MON-02d [MUST-ALLOW] staff can still adjust tyxBalance (support fix)', async () => {
    await seed({ 'users/u1': userProfile('u1', { tyxBalance: 100 }) });
    await assertSucceeds(updateDoc(doc(adminClaim(), 'users/u1'), { tyxBalance: 150 }));
  });
});

describe('MON: premium / subscription fields', () => {
  it('MON-05 [HIGH] owner cannot self-grant isPremium + premiumUntil', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    await assertFails(updateDoc(doc(user('u1'), 'users/u1'), { isPremium: true, premiumUntil: 1893456000000 }));
  });
  it('MON-06 [HIGH] owner cannot self-set subscriptionPlan/subscriptionStatus/accountType hybrid', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    await assertFails(updateDoc(doc(user('u1'), 'users/u1'), { subscriptionPlan: 'pro_yearly', subscriptionStatus: 'active', accountType: 'premium' }));
  });
  for (const [name, patch] of [
    ['accountType hybrid alone', { accountType: 'hybrid' }],
    ['subscriptionStatus alone', { subscriptionStatus: 'active' }],
    ['subscriptionPlan alone', { subscriptionPlan: 'yearly' }],
    ['subscriptionTxId alone', { subscriptionTxId: 'sub_sol_x' }],
    ['subscriptionPaymentAmount alone', { subscriptionPaymentAmount: 0 }],
    ['isPremium alone', { isPremium: true }],
    ['premiumUntil alone', { premiumUntil: 1893456000000 }],
    ['the whole grant incl. pendingSubscription/updatedAt (old rule 3 shape)', { isPremium: true, premiumUntil: 1893456000000, accountType: 'hybrid', subscriptionStatus: 'active', pendingSubscription: null, updatedAt: 1 }],
  ]) {
    it(`MON-05b [HIGH] owner cannot self-grant: ${name}`, async () => {
      await seed({ 'users/u1': userProfile('u1') });
      await assertFails(updateDoc(doc(user('u1'), 'users/u1'), patch));
    });
  }
  it('MON-05c [HIGH] owner cannot extend an existing premiumUntil or flip a lapsed isPremium back on', async () => {
    await seed({ 'users/u1': userProfile('u1', { isPremium: true, premiumUntil: 1000, accountType: 'hybrid' }), 'users/u2': userProfile('u2', { isPremium: false, premiumUntil: null }) });
    await assertFails(updateDoc(doc(user('u1'), 'users/u1'), { premiumUntil: 1893456000000 }));
    await assertFails(updateDoc(doc(user('u2'), 'users/u2'), { isPremium: true }));
  });
  it('MON-05d [MUST-ALLOW] owner can still downgrade (expiry): isPremium false, accountType nyxian, premiumUntil null', async () => {
    await seed({ 'users/u1': userProfile('u1', { isPremium: true, premiumUntil: 1000, accountType: 'hybrid' }) });
    await assertSucceeds(updateDoc(doc(user('u1'), 'users/u1'), { isPremium: false, accountType: 'nyxian', premiumUntil: null }));
  });
  it('MON-05e [HIGH] new signup cannot create a profile that is already premium/hybrid or carries subscription fields', async () => {
    const base = (extra) => userProfile('n1', { tyxBalance: 0, ...extra });
    await assertFails(setDoc(doc(user('n1'), 'users/n1'), base({ isPremium: true, premiumUntil: 1893456000000 })));
    await assertFails(setDoc(doc(user('n1'), 'users/n1'), base({ accountType: 'hybrid' })));
    await assertFails(setDoc(doc(user('n1'), 'users/n1'), base({ subscriptionStatus: 'active' })));
    await assertSucceeds(setDoc(doc(user('n1'), 'users/n1'), base({})));
  });
  it('MON-05f [MUST-ALLOW] staff can still grant premium and subscription fields', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    await assertSucceeds(updateDoc(doc(adminClaim(), 'users/u1'), { isPremium: true, premiumUntil: 1893456000000, accountType: 'hybrid', subscriptionStatus: 'active', subscriptionPlan: 'yearly' }));
  });
  it('MON-07 [CRITICAL] any signed-in user cannot change ANOTHER user\'s premium fields (branch 4 has no owner check, compiled:141)', async () => {
    await seed({ 'users/victim': userProfile('victim', { isPremium: true, premiumUntil: 1893456000000 }), 'users/u2': userProfile('u2') });
    await assertFails(updateDoc(doc(user('u2'), 'users/victim'), { isPremium: false, premiumUntil: 0, subscriptionStatus: 'revoked' }));
  });
});

describe('MON: other users\' money records', () => {
  const ref = { uid: 'victim', userId: 'victim', amount: 1500, referenceNo: 'GC-8812345', status: 'PENDING', createdAt: 1761120000000 };
  const holes = [
    ['withdrawals', 259], ['cashout_requests', 263], ['deposits', 240], ['deposit_references', 268],
    ['claimed_references', 272], ['claimedReferences', 281],
  ];
  for (const [col, line] of holes) {
    it(`MON-R-${col} [HIGH] signed-in user cannot READ another user's ${col} (compiled:${line}, 10_...:${line - 110})`, async () => {
      await seed({ [`${col}/v1`]: ref });
      await assertFails(getDoc(doc(user('u2'), `${col}/v1`)));
    });
    it(`MON-W-${col} [CRITICAL] signed-in user cannot OVERWRITE another user's ${col} (compiled:${line})`, async () => {
      await seed({ [`${col}/v1`]: ref });
      await assertFails(setDoc(doc(user('u2'), `${col}/v1`), { ...ref, uid: 'u2', userId: 'u2', status: 'CLAIMED' }));
    });
  }
  it('MON-R-claimed_p2p_references [MEDIUM] another user/guest cannot READ claimed_p2p_references (compiled:276)', async () => {
    await seed({ 'claimed_p2p_references/v1': ref });
    await assertFails(getDoc(doc(guest(), 'claimed_p2p_references/v1')));
  });
  it('MON-W-claimed_p2p_references [CRITICAL] another user cannot OVERWRITE claimed_p2p_references (compiled:277)', async () => {
    await seed({ 'claimed_p2p_references/v1': ref });
    await assertFails(setDoc(doc(user('u2'), 'claimed_p2p_references/v1'), { ...ref, uid: 'u2', userId: 'u2' }));
  });
  for (const col of ['withdrawal_requests', 'withdrawalRequests', 'deposit_requests', 'depositRequests']) {
    it(`MON-R-${col} [HIGH] another user cannot read victim ${col} — secure today`, async () => {
      await seed({ [`${col}/v1`]: withdrawal('victim') });
      await assertFails(getDoc(doc(user('u2'), `${col}/v1`)));
    });
  }
});

describe('MON: world-readable money collections', () => {
  it('MON-T1 [HIGH] guest cannot read global transactions (10_...:99 / compiled:209-210)', async () => {
    await seed({ 'transactions/tx1': { uid: 'victim', type: 'deposit', amount: 1500, walletAddress: '9xQeWvG8...', createdAt: 1761120000000 } });
    await assertFails(getDoc(doc(guest(), 'transactions/tx1')));
  });
  it('MON-T2 [MEDIUM] guest cannot read subscriptions (compiled:218)', async () => {
    await seed({ 'subscriptions/s1': { uid: 'victim', plan: 'pro_monthly', paymentAmount: 299, txId: 'abc', status: 'active' } });
    await assertFails(getDoc(doc(guest(), 'subscriptions/s1')));
  });
  it('MON-T3 [MEDIUM] guest cannot read walletLinks (wallet->uid map)', async () => {
    await seed({ 'walletLinks/9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin': { uid: 'victim', linkedAt: 1761120000000 } });
    await assertFails(getDoc(doc(guest(), 'walletLinks/9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin')));
  });
  it('MON-T4 [HIGH] any signed-in user cannot UPDATE someone else\'s subscription transaction (compiled:212)', async () => {
    await seed({ 'transactions/tx2': { uid: 'victim', type: 'subscription', amount: 299, status: 'PENDING' } });
    await assertFails(updateDoc(doc(user('u2'), 'transactions/tx2'), { status: 'VERIFIED' }));
  });
  it('MON-T5 [HIGH] any signed-in user cannot UPDATE someone else\'s subscriptions doc (compiled:220)', async () => {
    await seed({ 'subscriptions/s1': { uid: 'victim', plan: 'pro_monthly', status: 'pending' } });
    await assertFails(updateDoc(doc(user('u2'), 'subscriptions/s1'), { status: 'active' }));
  });
});

describe('MON: withdrawal request lock after create', () => {
  const prep = () => seed({ 'users/u1': userProfile('u1'), 'withdrawal_requests/wr1': withdrawal('u1'), 'withdrawalRequests/wr1': withdrawal('u1') });
  it('MON-WR0 [MUST-ALLOW] owner can create own withdrawal request (withdraw_modal.dart payload)', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    await assertSucceeds(setDoc(doc(user('u1'), 'withdrawal_requests/wrNew'), withdrawal('u1')));
    await assertSucceeds(setDoc(doc(user('u1'), 'withdrawalRequests/wrNew'), withdrawal('u1')));
  });
  it('MON-WR0b [MUST-ALLOW] owner can read own withdrawal request', async () => {
    await prep();
    await assertSucceeds(getDoc(doc(user('u1'), 'withdrawal_requests/wr1')));
  });
  it('MON-WR1 [CRITICAL] owner cannot change amount after create (compiled:247)', async () => {
    await prep();
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { amount: 50000 }));
  });
  it('MON-WR2 [CRITICAL] owner cannot self-approve status (compiled:247)', async () => {
    await prep();
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { status: 'APPROVED' }));
  });
  it('MON-WR3 [CRITICAL] owner cannot change destination wallet after create (compiled:247)', async () => {
    await prep();
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { destinationWallet: 'AttackerWa11et1111111111111111111111111111111' }));
  });
  it('MON-WR4 [CRITICAL] same lock on mirror collection withdrawalRequests (compiled:254)', async () => {
    await prep();
    await assertFails(updateDoc(doc(user('u1'), 'withdrawalRequests/wr1'), { amount: 50000, status: 'APPROVED' }));
  });
  knownHole('KNOWN-HOLE MON-WR5 [HIGH] user cannot create a withdrawal request already in a terminal status (compiled:246)', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    await assertFails(setDoc(doc(user('u1'), 'withdrawal_requests/wrX'), withdrawal('u1', { status: 'Successful', solanaTxSignature: 'fake' })));
  });
});
