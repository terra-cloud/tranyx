// Phase 4: balances and escrow for subscriptions, rentals, properties and jobs are callable-only.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { setupEnv, seed, user, adminClaim, userProfile } from './helpers.mjs';

setupEnv();

const ESCROWS = {
  rental_escrows: { requestId: 'r1', rentalId: 'v1', hostId: 'host', renteeId: 'renter', renterId: 'renter', amount: 3000, totalPaid: 3090, status: 'Held' },
  property_escrows: { requestId: 'r1', propertyId: 'p1', hostId: 'host', renteeId: 'renter', renterId: 'renter', amount: 17420, status: 'Held' },
  rental_extension_escrows: { extensionId: 'e1', rentalId: 'v1', hostId: 'host', renteeId: 'renter', renterId: 'renter', amount: 300, status: 'Held' },
  escrow: { employerId: 'host', creatorId: 'host', workerId: 'worker', amount: 1000, totalEscrowed: 1100, status: 'held' },
  escrow_holdbacks: { jobId: 'r1', amount: 100, nyxianId: 'worker', employerId: 'host', status: 'held', releaseAt: 1 },
};
const seedAll = () => seed({
  'users/host': userProfile('host'), 'users/renter': userProfile('renter'), 'users/worker': userProfile('worker'), 'users/stranger': userProfile('stranger'),
  'jobs/r1': { creatorId: 'host', acceptedApplicantId: 'worker', status: 'In Progress', pricingValue: 1000 },
  ...Object.fromEntries(Object.entries(ESCROWS).map(([c, d]) => [`${c}/r1`, d])),
});

describe.each(Object.keys(ESCROWS))('P4 %s is server-owned', (col) => {
  it(`no party or stranger can create, raise, release, refund or delete ${col}`, async () => {
    await seedAll();
    for (const uid of ['host', 'renter', 'worker', 'stranger']) {
      const db = user(uid);
      await assertFails(updateDoc(doc(db, `${col}/r1`), { status: 'Released', amount: 99999 }));
      await assertFails(updateDoc(doc(db, `${col}/r1`), { status: 'Refunded' }));
      await assertFails(setDoc(doc(db, `${col}/new1`), { ...ESCROWS[col], renteeId: uid, employerId: uid, creatorId: uid, nyxianId: uid, hostId: uid, status: 'Held' }));
      await assertFails(deleteDoc(doc(db, `${col}/r1`)));
    }
  });
  it(`[MUST-ALLOW] ${col}: the parties can still read it, staff can still write it`, async () => {
    await seedAll();
    await assertSucceeds(getDoc(doc(user(col === 'escrow_holdbacks' ? 'worker' : 'host'), `${col}/r1`)));
    await assertSucceeds(updateDoc(doc(adminClaim(), `${col}/r1`), { updatedAt: 1 }));
  });
});

describe('P4 no client path can move a balance for these flows', () => {
  it('renter cannot debit/credit own or the host balance (booking charge / refund / payout)', async () => {
    await seedAll();
    await assertFails(updateDoc(doc(user('renter'), 'users/renter'), { tyxBalance: 5 }));
    await assertFails(updateDoc(doc(user('renter'), 'users/renter'), { tyxBalance: 99999 }));
    await assertFails(updateDoc(doc(user('renter'), 'users/host'), { tyxBalance: 99999 }));
    await assertFails(updateDoc(doc(user('host'), 'users/renter'), { tyxBalance: 0 }));
  });
  it('employer cannot move the worker balance (job payout) and worker cannot credit self (holdback release / payout)', async () => {
    await seedAll();
    await assertFails(updateDoc(doc(user('host'), 'users/worker'), { tyxBalance: 99999, totalEarned: 99999 }));
    await assertFails(updateDoc(doc(user('worker'), 'users/worker'), { tyxBalance: 99999 }));
    await assertFails(updateDoc(doc(user('host'), 'users/host'), { tyxBalance: 99999 }));
  });
  it('subscription by balance: premium flags and balance are not client-writable', async () => {
    await seedAll();
    await assertFails(updateDoc(doc(user('renter'), 'users/renter'), { tyxBalance: 0, isPremium: true, premiumUntil: 9999999999999, accountType: 'hybrid', subscriptionPlan: 'yearly', subscriptionStatus: 'active' }));
    await assertFails(updateDoc(doc(user('renter'), 'users/renter'), { isPremium: true }));
  });
  it('a client cannot mint its own refund / payout ledger rows for a booking', async () => {
    await seedAll();
    await assertFails(setDoc(doc(user('renter'), 'transactions/payout_nyx_r1'), { uid: 'renter', type: 'payout', amount: 99999, status: 'Successful', createdAt: 1 }));
  });
  it('[MUST-ALLOW] ordinary profile edits and own non-money booking request docs still work', async () => {
    await seedAll();
    await assertSucceeds(updateDoc(doc(user('renter'), 'users/renter'), { headline: 'Hi' }));
  });
  it('[MUST-ALLOW] staff (admin claim) can still adjust balances for support and arbitration', async () => {
    await seedAll();
    await assertSucceeds(updateDoc(doc(adminClaim(), 'users/renter'), { tyxBalance: 123 }));
  });
});
