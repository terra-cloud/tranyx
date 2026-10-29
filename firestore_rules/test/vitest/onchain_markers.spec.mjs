// On-chain credit records: deposit_<sig>, sub_sol_<sig> and the shared onchain_<sig> marker are create-only for clients;
// deposit_*/sub_sol_* can only be created by the account that holds onchain_<sig> (same commit), are owner/staff-readable
// only, while onchain_<sig> (exact keys, type onchain_marker, uid == caller) is the only one any signed-in user may get;
// pending_onchain_<uid>_<sig> (bookkeeping before finalization) is bound to the uid in its id and stays owner-updatable; admin/staff can still edit anything.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, runTransaction, setDoc, updateDoc, writeBatch } from 'firebase/firestore';
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
    const isMarker = id === ONCHAIN;
    // Creates `id` the way the app does: credit record + shared marker in one commit.
    const createAs = async (db) => {
      if (isMarker) return setDoc(doc(db, `transactions/${id}`), data);
      const batch = writeBatch(db);
      batch.set(doc(db, `transactions/${ONCHAIN}`), marker('u1'));
      batch.set(doc(db, `transactions/${id}`), data);
      return batch.commit();
    };
    it(`OC [MUST-ALLOW] owner creates ${id.slice(0, 14)}…`, async () => {
      await seedUser();
      await assertSucceeds(createAs(user('u1')));
    });
    it(`OC [HIGH] owner cannot rewrite/replay own ${id.slice(0, 14)}…`, async () => {
      await seedUser();
      await seed({ [`transactions/${id}`]: data, [`transactions/${ONCHAIN}`]: marker('u1') });
      await assertFails(updateDoc(doc(user('u1'), `transactions/${id}`), { amount: 999999 }));
      await assertFails(setDoc(doc(user('u1'), `transactions/${id}`), { ...data, amount: 999999 }));
    });
    it(`OC [MUST-ALLOW] admin can still update ${id.slice(0, 14)}…`, async () => {
      await seedUser();
      await seed({ [`transactions/${id}`]: data });
      await assertSucceeds(updateDoc(doc(adminClaim(), `transactions/${id}`), { note: 'support fix' }));
    });
    it(`OC [HIGH] another user cannot create ${id.slice(0, 14)}… for someone else`, async () => {
      await seedUser();
      await assertFails(setDoc(doc(user('u2'), `transactions/${id}`), data));
    });
  }

  for (const [id, data] of [
    [`deposit_sol_${SIG}`, { uid: 'u2', type: 'deposit', amount: 50, solanaTxSignature: SIG }],
    [`deposit_usdt_${SIG}`, { uid: 'u2', type: 'deposit', amount: 50, solanaTxSignature: SIG }],
    [`sub_sol_${SIG}`, { uid: 'u2', type: 'subscription', amount: 199, solanaTxSignature: SIG }],
  ]) {
    it(`OC [HIGH] B cannot create ${id.slice(0, 14)}… without holding onchain_<sig>`, async () => {
      await seedUser();
      await assertFails(setDoc(doc(user('u2'), `transactions/${id}`), data));
    });
    it(`OC [HIGH] B cannot create ${id.slice(0, 14)}… while A holds onchain_<sig> (even in the same batch)`, async () => {
      await seedUser();
      await seed({ [`transactions/${ONCHAIN}`]: marker('u1') });
      await assertFails(setDoc(doc(user('u2'), `transactions/${id}`), data));
      const db2 = user('u2');
      const batch = writeBatch(db2);
      batch.set(doc(db2, `transactions/${ONCHAIN}`), marker('u2'));
      batch.set(doc(db2, `transactions/${id}`), data);
      await assertFails(batch.commit());
    });
    it(`OC [MUST-ALLOW] owner creates ${id.slice(0, 14)}… later when already holding onchain_<sig>`, async () => {
      await seedUser();
      await seed({ [`transactions/${ONCHAIN}`]: marker('u2') });
      await assertSucceeds(setDoc(doc(user('u2'), `transactions/${id}`), data));
    });
    it(`OC [HIGH] B cannot get A's ${id.slice(0, 14)}…`, async () => {
      await seedUser();
      await seed({ [`transactions/${id}`]: { ...data, uid: 'u1' } });
      await assertFails(getDoc(doc(user('u2'), `transactions/${id}`)));
    });
    it(`OC [MUST-ALLOW] owner and staff can get ${id.slice(0, 14)}…`, async () => {
      await seedUser();
      await seed({ [`transactions/${id}`]: { ...data, uid: 'u1' } });
      await assertSucceeds(getDoc(doc(user('u1'), `transactions/${id}`)));
      await assertSucceeds(getDoc(doc(adminClaim(), `transactions/${id}`)));
    });
  }

  it('OC [MUST-ALLOW] B can get A\'s onchain_<sig>', async () => {
    await seedUser();
    await seed({ [`transactions/${ONCHAIN}`]: marker('u1') });
    await assertSucceeds(getDoc(doc(user('u2'), `transactions/${ONCHAIN}`)));
  });

  it('OC [HIGH] B cannot list or query onchain markers', async () => {
    await seedUser();
    await seed({ [`transactions/${ONCHAIN}`]: marker('u1') });
    const { getDocs, query, collection, where } = await import('firebase/firestore');
    await assertFails(getDocs(query(collection(user('u2'), 'transactions'), where('uid', '==', 'u1'))));
  });

  it('OC [HIGH] onchain_<sig> create is limited to the exact keys, type and the caller\'s uid', async () => {
    await seedUser();
    const ref = (db) => doc(db, `transactions/${ONCHAIN}`);
    await assertFails(setDoc(ref(user('u2')), { ...marker('u2'), extra: 'x' }));
    await assertFails(setDoc(ref(user('u2')), { ...marker('u2'), createdAt: 1 }));
    await assertFails(setDoc(ref(user('u2')), { ...marker('u2'), type: 'deposit' }));
    const { type: _omit, ...noType } = marker('u2');
    await assertFails(setDoc(ref(user('u2')), noType));
    await assertFails(setDoc(ref(user('u2')), marker('u1')));
    await assertSucceeds(setDoc(ref(user('u2')), marker('u2')));
  });

  it('OC [HIGH] B cannot add fields to, or replace, A\'s onchain_<sig>', async () => {
    await seedUser();
    await seed({ [`transactions/${ONCHAIN}`]: marker('u1') });
    await assertFails(updateDoc(doc(user('u2'), `transactions/${ONCHAIN}`), { extra: 'x' }));
    await assertFails(setDoc(doc(user('u2'), `transactions/${ONCHAIN}`), marker('u2')));
    await assertFails(updateDoc(doc(user('u1'), `transactions/${ONCHAIN}`), { extra: 'x' }));
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

  // Mirrors commitOnceByMarker: onchain_<sig> is read first; a foreign holder ends the transaction
  // before the per-flow marker (owner-only) is read.
  const creditAttempt = (db) =>
    runTransaction(db, async (tx) => {
      const onchain = await tx.get(doc(db, `transactions/${ONCHAIN}`));
      const pendingRef = doc(db, `transactions/${pendingA}`);
      if (onchain.exists() && onchain.data().uid !== 'u1') {
        const pending = await tx.get(pendingRef);
        if (pending.exists()) tx.update(pendingRef, { note: 'marker held by another account' });
        else tx.set(pendingRef, { ...pendingData('u1'), note: 'marker held by another account' });
        return 'held';
      }
      if (onchain.exists()) return 'processed';
      const perFlow = await tx.get(doc(db, `transactions/deposit_sol_${SIG}`));
      return perFlow.exists() ? 'dup' : 'credit';
    });

  it('OC [MUST-ALLOW] A\'s credit transaction returns "held" (not permission-denied) when B holds onchain_<sig>, even with B\'s deposit_sol_<sig> present', async () => {
    await seedUser();
    await seed({
      [`transactions/${ONCHAIN}`]: marker('u2'),
      [`transactions/deposit_sol_${SIG}`]: { uid: 'u2', type: 'deposit', amount: 5, solanaTxSignature: SIG },
    });
    const db = user('u1');
    const result = await assertSucceeds(creditAttempt(db));
    if (result !== 'held') throw new Error(`unexpected result ${result}`);
    const snap = await assertSucceeds(getDoc(doc(db, `transactions/${pendingA}`)));
    if (snap.data().note !== 'marker held by another account') throw new Error('note missing');
  });

  it('OC [MUST-ALLOW] A\'s credit transaction proceeds to "credit" when nothing holds the signature', async () => {
    await seedUser();
    const result = await assertSucceeds(creditAttempt(user('u1')));
    if (result !== 'credit') throw new Error(`unexpected result ${result}`);
  });

  it('OC [HIGH] reading B\'s deposit_sol_<sig> inside a transaction IS denied, which is why onchain_ is read first', async () => {
    await seedUser();
    await seed({ [`transactions/deposit_sol_${SIG}`]: { uid: 'u2', type: 'deposit', amount: 5, solanaTxSignature: SIG } });
    const db = user('u1');
    await assertFails(runTransaction(db, async (tx) => tx.get(doc(db, `transactions/deposit_sol_${SIG}`))));
  });
});
