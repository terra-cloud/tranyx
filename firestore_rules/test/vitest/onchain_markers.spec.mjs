// On-chain credit records: deposit_sol_<sig>, deposit_usdt_<sig>, sub_sol_<sig> and the shared onchain_<sig> marker are
// written by the creditOnchainPayment Cloud Function (Admin SDK) only. Owners and other users can neither create nor
// edit them (a client could otherwise plant onchain_<sig> to block the real owner, or forge a credit record); the owner
// can still read their own credit records, other accounts cannot read anyone else's.
// pending_onchain_<uid>_<sig> (client bookkeeping, grants nothing) stays bound to the uid in its id and owner-updatable;
// admin/staff can still edit anything.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, writeBatch } from 'firebase/firestore';
import { setupEnv, seed, user, adminClaim, userProfile } from './helpers.mjs';

setupEnv();
const SIG = '5VERv8NMvzbJMEkV8xnrLkEaWRtSz9CosKDYjCJjBRnbJLgp8uirBgmQpjKhoR4tjF3ZpRzrFmBV6UjKdiSZkQUW';
const seedUser = () => seed({ 'users/u1': userProfile('u1'), 'users/u2': userProfile('u2') });

describe('on-chain credit markers (transactions)', () => {
  const marker = (uid) => ({ uid, type: 'onchain_marker', solanaTxSignature: SIG, markerId: `deposit_sol_${SIG}`, markedAt: 1 });
  const ONCHAIN = `onchain_${SIG}`;

  for (const [id, data] of [
    [`deposit_sol_${SIG}`, { uid: 'u1', type: 'deposit', amount: 50, solanaTxSignature: SIG }],
    [`deposit_usdt_${SIG}`, { uid: 'u1', type: 'deposit', amount: 50, solanaTxSignature: SIG }],
    [`sub_sol_${SIG}`, { uid: 'u1', type: 'subscription', amount: 199, solanaTxSignature: SIG }],
    [ONCHAIN, marker('u1')],
  ]) {
    const short = id.slice(0, 14);
    it(`OC [CRITICAL] owner cannot create ${short}… (Admin SDK only), alone or in a batch with the marker`, async () => {
      await seedUser();
      await assertFails(setDoc(doc(user('u1'), `transactions/${id}`), data));
      const db = user('u1');
      const batch = writeBatch(db);
      batch.set(doc(db, `transactions/${ONCHAIN}`), marker('u1'));
      batch.set(doc(db, `transactions/${id}`), data);
      await assertFails(batch.commit());
    });
    it(`OC [CRITICAL] another user cannot create ${short}… (squatting) for anyone`, async () => {
      await seedUser();
      await assertFails(setDoc(doc(user('u2'), `transactions/${id}`), data));
      await assertFails(setDoc(doc(user('u2'), `transactions/${id}`), { ...data, uid: 'u2' }));
    });
    it(`OC [HIGH] owner cannot rewrite/replay own ${short}…`, async () => {
      await seedUser();
      await seed({ [`transactions/${id}`]: data, [`transactions/${ONCHAIN}`]: marker('u1') });
      await assertFails(updateDoc(doc(user('u1'), `transactions/${id}`), { amount: 999999 }));
      await assertFails(setDoc(doc(user('u1'), `transactions/${id}`), { ...data, amount: 999999 }));
    });
    it(`OC [MUST-ALLOW] admin/staff can still create and update ${short}…`, async () => {
      await seedUser();
      await assertSucceeds(setDoc(doc(adminClaim(), `transactions/${id}`), data));
      await assertSucceeds(updateDoc(doc(adminClaim(), `transactions/${id}`), { note: 'support fix' }));
    });
    it(`OC [HIGH] B cannot get A's ${short}…`, async () => {
      await seedUser();
      await seed({ [`transactions/${id}`]: { ...data, uid: 'u1' } });
      await assertFails(getDoc(doc(user('u2'), `transactions/${id}`)));
    });
    it(`OC [MUST-ALLOW] owner and staff can get ${short}…`, async () => {
      await seedUser();
      await seed({ [`transactions/${id}`]: { ...data, uid: 'u1' } });
      await assertSucceeds(getDoc(doc(user('u1'), `transactions/${id}`)));
      await assertSucceeds(getDoc(doc(adminClaim(), `transactions/${id}`)));
    });
  }

  it('OC [HIGH] B cannot list or query onchain markers', async () => {
    await seedUser();
    await seed({ [`transactions/${ONCHAIN}`]: marker('u1') });
    const { getDocs, query, collection, where } = await import('firebase/firestore');
    await assertFails(getDocs(query(collection(user('u2'), 'transactions'), where('uid', '==', 'u1'))));
  });

  const pendingA = `pending_onchain_u1_${SIG}`;
  const pendingData = (uid) => ({ uid, type: 'onchain_pending', status: 'pending', solanaTxSignature: SIG });

  it('OC [MUST-ALLOW] owner creates then updates pending_onchain_<uid>_<sig> (pending -> done)', async () => {
    await seedUser();
    const ref = doc(user('u1'), `transactions/${pendingA}`);
    await assertSucceeds(setDoc(ref, pendingData('u1')));
    await assertSucceeds(updateDoc(ref, { status: 'done' }));
  });

  it('OC [HIGH] user B cannot create pending_onchain_<A>_<sig> (squatting), whatever uid the doc claims', async () => {
    await seedUser();
    await assertFails(setDoc(doc(user('u2'), `transactions/${pendingA}`), pendingData('u2')));
    await assertFails(setDoc(doc(user('u2'), `transactions/${pendingA}`), pendingData('u1')));
  });

  it('OC [HIGH] a pending id without a uid prefix of the caller is refused', async () => {
    await seedUser();
    await assertFails(setDoc(doc(user('u1'), `transactions/pending_onchain_${SIG}`), pendingData('u1')));
    await assertFails(setDoc(doc(user('u1'), 'transactions/pending_onchain_u1'), pendingData('u1')));
  });

  it('OC [MUST-ALLOW] both accounts keep their own pending record for the same signature', async () => {
    await seedUser();
    await assertSucceeds(setDoc(doc(user('u1'), `transactions/${pendingA}`), pendingData('u1')));
    await assertSucceeds(setDoc(doc(user('u2'), `transactions/pending_onchain_u2_${SIG}`), pendingData('u2')));
  });

  it('OC [HIGH] user B cannot update or read A\'s pending record; staff can update it', async () => {
    await seedUser();
    await seed({ [`transactions/${pendingA}`]: pendingData('u1') });
    await assertFails(updateDoc(doc(user('u2'), `transactions/${pendingA}`), { status: 'done' }));
    await assertFails(getDoc(doc(user('u2'), `transactions/${pendingA}`)));
    await assertSucceeds(updateDoc(doc(adminClaim(), `transactions/${pendingA}`), { note: 'support' }));
  });

  it('OC [HIGH] the owner cannot hand the pending record to another uid', async () => {
    await seedUser();
    await seed({ [`transactions/${pendingA}`]: pendingData('u1') });
    await assertFails(updateDoc(doc(user('u1'), `transactions/${pendingA}`), { uid: 'u2' }));
  });

  it('OC [HIGH] other accounts\' normal transactions stay unreadable', async () => {
    await seedUser();
    await seed({ 'transactions/dep_other': { uid: 'u2', type: 'deposit', amount: 5 } });
    await assertFails(getDoc(doc(user('u1'), 'transactions/dep_other')));
  });
});
