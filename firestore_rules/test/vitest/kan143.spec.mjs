// KAN-143 lockdown: mail/emails, tickets, audit_logs, users read scope. Emulator only (demo-tranyx).
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, query, where, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';
import { setupEnv, seed, user, guest, adminClaim, userProfile } from './helpers.mjs';

setupEnv();
const NOW = 1761120000000;
// Exactly what web index.html and the mobile chat views write.
const ticket = (uid, over = {}) => ({
  id: `ticket_ban_${uid}`, subject: 'Subject for Ban', title: 'Subject for Ban', userId: uid, userName: 'U', chatId: 'c1',
  reason: 'Repeated attempt to share contact numbers', lastOffendingMessage: 'call me 0917', violationType: 'phone',
  status: 'flagged_for_ban', priority: 'urgent', createdAt: NOW, updatedAt: NOW, ...over,
});

describe('KAN-143 mail / emails: staff only', () => {
  for (const col of ['mail', 'emails']) {
    it(`${col}: signed-in user cannot create (mail relay) or read`, async () => {
      await seed({ [`${col}/m1`]: { to: ['v@example.org'], message: { subject: 's' } } });
      await assertFails(setDoc(doc(user('u1'), `${col}/x`), { to: ['victim@example.org'], message: { subject: 'phish', html: 'x' } }));
      await assertFails(getDoc(doc(user('u1'), `${col}/m1`)));
      await assertFails(getDoc(doc(guest(), `${col}/m1`)));
    });
    it(`${col}: [MUST-ALLOW] admin claim (admin panel ticket_email_service) can create and read`, async () => {
      await assertSucceeds(setDoc(doc(adminClaim(), `${col}/x`), { to: ['u@example.org'], message: { subject: 's' } }));
      await assertSucceeds(getDoc(doc(adminClaim(), `${col}/x`)));
    });
  }
});

describe('KAN-143 tickets: owner create with allowlist, owner/staff read', () => {
  it('[MUST-ALLOW] user creates own flagged_for_ban ticket (web/mobile shape)', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    await assertSucceeds(setDoc(doc(user('u1'), 'tickets/t1'), ticket('u1')));
  });
  it('cannot create a ticket for another user, with extra fields, or with another status', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    await assertFails(setDoc(doc(user('u1'), 'tickets/t2'), ticket('victim')));
    await assertFails(setDoc(doc(user('u1'), 'tickets/t3'), ticket('u1', { isStaff: true })));
    await assertFails(setDoc(doc(user('u1'), 'tickets/t4'), ticket('u1', { status: 'resolved' })));
    await assertFails(setDoc(doc(user('u1'), 'tickets/t5'), ticket('u1', { lastOffendingMessage: 'x'.repeat(2001) })));
  });
  it('guest cannot create or read tickets', async () => {
    await seed({ 'tickets/t1': ticket('u1') });
    await assertFails(setDoc(doc(guest(), 'tickets/g'), ticket('u1')));
    await assertFails(getDoc(doc(guest(), 'tickets/t1')));
  });
  it('another user cannot read, list-all, update or delete someone else\'s ticket; owner can read own', async () => {
    await seed({ 'tickets/t1': ticket('u1') });
    await assertSucceeds(getDoc(doc(user('u1'), 'tickets/t1')));
    await assertFails(getDoc(doc(user('u2'), 'tickets/t1')));
    await assertFails(getDocs(collection(user('u2'), 'tickets')));
    await assertSucceeds(getDocs(query(collection(user('u1'), 'tickets'), where('userId', '==', 'u1'))));
    await assertFails(updateDoc(doc(user('u1'), 'tickets/t1'), { status: 'resolved' }));
    await assertFails(deleteDoc(doc(user('u1'), 'tickets/t1')));
  });
  it('[MUST-ALLOW] staff (admin claim) reads and updates tickets', async () => {
    await seed({ 'tickets/t1': ticket('u1') });
    await assertSucceeds(getDoc(doc(adminClaim(), 'tickets/t1')));
    await assertSucceeds(updateDoc(doc(adminClaim(), 'tickets/t1'), { status: 'banned' }));
  });
});

describe('KAN-143 audit_logs / auditLogs: staff only', () => {
  for (const col of ['audit_logs', 'auditLogs']) {
    it(`${col}: user cannot create, tamper or read; staff can`, async () => {
      await seed({ [`${col}/a1`]: { uid: 'u1', action: 'login' } });
      await assertFails(setDoc(doc(user('u1'), `${col}/x`), { uid: 'u1', action: 'forged' }));
      await assertFails(updateDoc(doc(user('u1'), `${col}/a1`), { action: 'tampered' }));
      await assertFails(getDoc(doc(user('u1'), `${col}/a1`)));
      await assertSucceeds(getDoc(doc(adminClaim(), `${col}/a1`)));
    });
  }
});

describe('KAN-143 users read scope', () => {
  it('guest cannot get or list users', async () => {
    await seed({ 'users/v': userProfile('v') });
    await assertFails(getDoc(doc(guest(), 'users/v')));
    await assertFails(getDocs(collection(guest(), 'users')));
  });
  it('[MUST-ALLOW] signed-in user can get a counterparty profile by uid, but cannot list or query users', async () => {
    await seed({ 'users/v': userProfile('v') });
    await assertSucceeds(getDoc(doc(user('u1'), 'users/v')));
    await assertFails(getDocs(collection(user('u1'), 'users')));
    await assertFails(getDocs(query(collection(user('u1'), 'users'), where('email', '==', 'v@gmail.com'))));
  });
  it('[MUST-ALLOW] staff (admin claim) can list/query users (admin panel)', async () => {
    await seed({ 'users/v': userProfile('v') });
    await assertSucceeds(getDocs(collection(adminClaim(), 'users')));
    await assertSucceeds(getDocs(query(collection(adminClaim(), 'users'), where('email', '==', 'v@gmail.com'))));
  });
});
