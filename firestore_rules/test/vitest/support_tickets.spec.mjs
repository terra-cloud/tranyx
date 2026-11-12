// Support tickets: supportTickets/{id} and support_tickets/{id}. Emulator only (demo-tranyx).
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, query, where, setDoc, updateDoc, deleteDoc, addDoc } from 'firebase/firestore';
import { setupEnv, seed, user, guest, adminClaim, userProfile } from './helpers.mjs';

setupEnv();
// Exactly what web profile_view.dart submitTicket writes (createdAt = DateTime.now() epoch ms).
const ticket = (uid, over = {}) => ({
  uid, userEmail: `${uid}@example.org`, userName: 'U', subject: 'Help', description: 'My withdrawal is stuck',
  category: 'General', status: 'Open', createdAt: Date.now(), ...over,
});

for (const col of ['supportTickets', 'support_tickets']) {
  describe(`${col}: owner and staff only`, () => {
    const base = () => seed({
      [`${col}/t1`]: ticket('u1', { createdAt: 1761120000000 }),
      'users/u1': userProfile('u1'), 'users/u2': userProfile('u2'),
    });
    it('[MUST-ALLOW] owner creates (web shape) and reads own ticket; filtered list by uid works', async () => {
      await base();
      await assertSucceeds(setDoc(doc(user('u1'), `${col}/${Date.now()}`), ticket('u1')));
      await assertSucceeds(getDoc(doc(user('u1'), `${col}/t1`)));
      await assertSucceeds(getDocs(query(collection(user('u1'), col), where('uid', '==', 'u1'))));
    });
    it('[MUST-ALLOW] staff (admin claim) lists, reads, updates, creates and deletes', async () => {
      await base();
      const a = adminClaim();
      await assertSucceeds(getDocs(collection(a, col)));
      await assertSucceeds(getDoc(doc(a, `${col}/t1`)));
      await assertSucceeds(updateDoc(doc(a, `${col}/t1`), { status: 'Resolved', assignedTo: 'agent1' }));
      await assertSucceeds(setDoc(doc(a, `${col}/inbound1`), { subject: 'from email', email: 'x@example.org', status: 'Open' }));
      await assertSucceeds(deleteDoc(doc(a, `${col}/t1`)));
    });
    it('a stranger cannot read, list, update, overwrite or delete someone else\'s ticket', async () => {
      await base();
      const s = user('u2');
      await assertFails(getDoc(doc(s, `${col}/t1`)));
      await assertFails(getDocs(collection(s, col)));
      await assertFails(getDocs(query(collection(s, col), where('uid', '==', 'u1'))));
      await assertFails(updateDoc(doc(s, `${col}/t1`), { status: 'Resolved' }));
      await assertFails(setDoc(doc(s, `${col}/t1`), ticket('u2')));
      await assertFails(setDoc(doc(s, `${col}/t1`), ticket('u1')));
      await assertFails(deleteDoc(doc(s, `${col}/t1`)));
      await assertFails(getDoc(doc(guest(), `${col}/t1`)));
      await assertFails(setDoc(doc(guest(), `${col}/g`), ticket('u1')));
    });
    it('the owner cannot update, escalate status, change uid or delete their own ticket', async () => {
      await base();
      const o = user('u1');
      await assertFails(updateDoc(doc(o, `${col}/t1`), { status: 'Resolved' }));
      await assertFails(updateDoc(doc(o, `${col}/t1`), { uid: 'u2' }));
      await assertFails(updateDoc(doc(o, `${col}/t1`), { description: 'edited' }));
      await assertFails(deleteDoc(doc(o, `${col}/t1`)));
    });
    it('create denies forged uid, extra fields, other status, missing/oversized fields, stale createdAt', async () => {
      await base();
      const c = user('u1');
      const id = () => `${col}/${Math.random().toString(36).slice(2)}`;
      await assertFails(setDoc(doc(c, id()), ticket('u2')));
      await assertFails(setDoc(doc(c, id()), ticket('u1', { isAdmin: true })));
      await assertFails(setDoc(doc(c, id()), ticket('u1', { assignedTo: 'agent1' })));
      await assertFails(setDoc(doc(c, id()), ticket('u1', { status: 'Resolved' })));
      await assertFails(setDoc(doc(c, id()), ticket('u1', { subject: '' })));
      await assertFails(setDoc(doc(c, id()), ticket('u1', { subject: 'x'.repeat(201) })));
      await assertFails(setDoc(doc(c, id()), ticket('u1', { description: 'x'.repeat(5001) })));
      await assertFails(setDoc(doc(c, id()), ticket('u1', { category: 'x'.repeat(51) })));
      await assertFails(setDoc(doc(c, id()), ticket('u1', { createdAt: 1 })));
      await assertFails(setDoc(doc(c, id()), ticket('u1', { createdAt: 'now' })));
      await assertFails(addDoc(collection(c, col), (({ uid, ...r }) => r)(ticket('u1'))));
    });
  });
}
