// KAN-143 follow-up: ticket responses and dispute messages. Emulator only (demo-tranyx).
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, setDoc, addDoc, updateDoc, deleteDoc } from 'firebase/firestore';
import { setupEnv, seed, user, guest, adminClaim, userProfile } from './helpers.mjs';

setupEnv();
const NOW = 1761120000000;
const reply = (over = {}) => ({ text: 'We are looking into it', authorName: 'Support', createdAt: NOW, ...over });

for (const col of ['supportTickets', 'support_tickets']) {
  describe(`KAN-143 follow-up ${col}/{id}/responses: owner read, staff write`, () => {
    const seedTicket = () => seed({
      [`${col}/t1`]: { uid: 'u1', subject: 's', status: 'Open', createdAt: NOW },
      [`${col}/t1/responses/r1`]: reply(),
      'users/u1': userProfile('u1'), 'users/u2': userProfile('u2'),
    });
    it('[MUST-ALLOW] ticket owner reads replies; staff (admin claim) reads and writes them', async () => {
      await seedTicket();
      await assertSucceeds(getDoc(doc(user('u1'), `${col}/t1/responses/r1`)));
      await assertSucceeds(getDocs(collection(user('u1'), `${col}/t1/responses`)));
      await assertSucceeds(getDoc(doc(adminClaim(), `${col}/t1/responses/r1`)));
      await assertSucceeds(addDoc(collection(adminClaim(), `${col}/t1/responses`), reply()));
      await assertSucceeds(updateDoc(doc(adminClaim(), `${col}/t1/responses/r1`), { text: 'edited' }));
    });
    it('another signed-in user cannot read replies on someone else\'s ticket', async () => {
      await seedTicket();
      await assertFails(getDoc(doc(user('u2'), `${col}/t1/responses/r1`)));
      await assertFails(getDocs(collection(user('u2'), `${col}/t1/responses`)));
      await assertFails(getDoc(doc(guest(), `${col}/t1/responses/r1`)));
    });
    it('no user (not even the owner) can write, edit or delete replies; reply on a missing ticket is denied', async () => {
      await seedTicket();
      for (const uid of ['u1', 'u2']) {
        await assertFails(addDoc(collection(user(uid), `${col}/t1/responses`), reply({ text: 'forged staff reply' })));
        await assertFails(updateDoc(doc(user(uid), `${col}/t1/responses/r1`), { text: 'tampered' }));
        await assertFails(deleteDoc(doc(user(uid), `${col}/t1/responses/r1`)));
      }
      await assertFails(getDoc(doc(user('u1'), `${col}/ghost/responses/r1`)));
      await assertFails(setDoc(doc(guest(), `${col}/t1/responses/g`), reply()));
    });
  });
}

describe('KAN-143 follow-up disputes/{id}/messages: parties and staff only', () => {
  const D = { openedBy: 'emp', employerId: 'emp', acceptedNyxianId: 'wrk', status: 'OPEN', jobId: 'j1' };
  const msg = (uid, over = {}) => ({ senderId: uid, text: 'evidence attached', createdAt: NOW, ...over });
  const seedDispute = () => seed({
    'disputes/d1': D, 'disputes/d1/messages/m1': msg('emp'),
    'users/emp': userProfile('emp'), 'users/wrk': userProfile('wrk'), 'users/out': userProfile('out'),
  });
  it('[MUST-ALLOW] both parties read; each posts as themselves; staff reads, posts and moderates', async () => {
    await seedDispute();
    await assertSucceeds(getDoc(doc(user('emp'), 'disputes/d1/messages/m1')));
    await assertSucceeds(getDocs(collection(user('wrk'), 'disputes/d1/messages')));
    await assertSucceeds(setDoc(doc(user('wrk'), 'disputes/d1/messages/m2'), msg('wrk')));
    await assertSucceeds(setDoc(doc(user('emp'), 'disputes/d1/messages/m3'), msg('emp')));
    await assertSucceeds(getDoc(doc(adminClaim(), 'disputes/d1/messages/m1')));
    await assertSucceeds(setDoc(doc(adminClaim(), 'disputes/d1/messages/m4'), msg('staff')));
    await assertSucceeds(deleteDoc(doc(adminClaim(), 'disputes/d1/messages/m1')));
  });
  it('outsiders and guests cannot read or post', async () => {
    await seedDispute();
    await assertFails(getDoc(doc(user('out'), 'disputes/d1/messages/m1')));
    await assertFails(getDocs(collection(user('out'), 'disputes/d1/messages')));
    await assertFails(setDoc(doc(user('out'), 'disputes/d1/messages/x'), msg('out')));
    await assertFails(getDoc(doc(guest(), 'disputes/d1/messages/m1')));
    await assertFails(setDoc(doc(guest(), 'disputes/d1/messages/x'), msg('emp')));
  });
  it('a party cannot impersonate the other party, post oversized text, edit or delete messages', async () => {
    await seedDispute();
    await assertFails(setDoc(doc(user('wrk'), 'disputes/d1/messages/f1'), msg('emp')));
    await assertFails(setDoc(doc(user('wrk'), 'disputes/d1/messages/f2'), msg('wrk', { text: 'x'.repeat(2001) })));
    await assertFails(updateDoc(doc(user('emp'), 'disputes/d1/messages/m1'), { text: 'edited' }));
    await assertFails(deleteDoc(doc(user('emp'), 'disputes/d1/messages/m1')));
  });
  it('messages under a missing dispute are denied for users', async () => {
    await seed({ 'users/emp': userProfile('emp') });
    await assertFails(setDoc(doc(user('emp'), 'disputes/ghost/messages/m'), msg('emp')));
    await assertFails(getDoc(doc(user('emp'), 'disputes/ghost/messages/m')));
  });
});
