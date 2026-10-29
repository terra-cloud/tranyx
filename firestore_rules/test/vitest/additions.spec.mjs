// Additions requested Oct 22: guest list reads from the admin-panel scratch scripts, system_config/treasury,
// and PLANNED must-deny tests for Saga's tyxBalance ledger design (fix/rules-money-and-escalation:
// "owner can only lower a balance, through a ledger doc that matches the price; ledger IDs are fixed per purpose and create-only").
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, limit, query, setDoc, updateDoc, writeBatch } from 'firebase/firestore';
import { knownHole, planned, setupEnv, seed, user, guest, userProfile, property, withdrawal } from './helpers.mjs';

setupEnv();
const NOW = 1761123600000;

describe('GST: guest list reads copied from tranyx_admin_portal/scratch (unauthenticated SDK, no sign-in)', () => {
  const prep = () => seed({
    'users/victim': userProfile('victim'), 'users/v2': userProfile('v2'),
    'deposit_requests/d1': { ...withdrawal('victim'), type: 'deposit', referenceNo: 'GC-8812345' },
    'wallets/victim': { uid: 'victim', userId: 'victim', balance: 100, solanaAddress: '9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin' },
  });
  knownHole('KNOWN-HOLE GST-01 [HIGH] guest cannot list users with limit(5) (inspect_dev_schema.js:23; 10_...:7 / compiled:117)', async () => {
    await prep();
    await assertFails(getDocs(query(collection(guest(), 'users'), limit(5))));
  });
  knownHole('KNOWN-HOLE GST-02 [HIGH] guest cannot dump the whole users collection (test_firestore.js:18, test_firestore_admin.js:18; compiled:117)', async () => {
    await prep();
    await assertFails(getDocs(collection(guest(), 'users')));
  });
  it('GST-03 [HIGH] guest cannot list deposit_requests with limit(5) (inspect_dev_schema.js:19) — secure today', async () => {
    await prep();
    await assertFails(getDocs(query(collection(guest(), 'deposit_requests'), limit(5))));
  });
  it('GST-04 [HIGH] guest cannot list wallets with limit(5) (inspect_dev_schema.js:28) — secure today', async () => {
    await prep();
    await assertFails(getDocs(query(collection(guest(), 'wallets'), limit(5))));
  });
  it('GST-05 [HIGH] guest cannot get a single wallets/{uid} doc — secure today', async () => {
    await prep();
    await assertFails(getDoc(doc(guest(), 'wallets/victim')));
  });
  it('GST-06 [HIGH] signed-in non-admin cannot run the unfiltered deposit_requests list — secure today', async () => {
    await prep();
    await assertFails(getDocs(query(collection(user('u2'), 'deposit_requests'), limit(5))));
  });
  it('GST-07 [HIGH] signed-in non-admin cannot run the unfiltered wallets list — secure today', async () => {
    await prep();
    await assertFails(getDocs(query(collection(user('u2'), 'wallets'), limit(5))));
  });
});

describe('SYS: system_config/treasury', () => {
  const prep = (extra = {}) => seed({ 'system_config/treasury': { solanaTreasuryPubkey: 'TREASURY_PLACEHOLDER', note: 'fixture, no secret' }, ...extra });
  it('SYS-01 [CRITICAL] ordinary verified Gmail user without claims cannot read treasury — secure today', async () => {
    await prep({ 'users/u1': userProfile('u1') });
    await assertFails(getDoc(doc(user('u1'), 'system_config/treasury')));
  });
  it('SYS-02 [CRITICAL] guest cannot read treasury — secure today', async () => {
    await prep();
    await assertFails(getDoc(doc(guest(), 'system_config/treasury')));
  });
  it('SYS-03 [CRITICAL] verified @tranyx.com email without admin claim cannot read treasury (02_...:27-29 / compiled:78-80)', async () => {
    await prep();
    await assertFails(getDoc(doc(user('emp', { email: 'emp@tranyx.com', email_verified: true }), 'system_config/treasury')));
  });
  knownHole('KNOWN-HOLE SYS-04 [CRITICAL] seed.js "attacker" (unverified attacker@tranyx.com, users doc isAdmin/isP2pAgent/role admin, no claims) cannot read treasury (02_...:34-47 / compiled:85-98)', async () => {
    await prep({ 'users/attacker': { email: 'attacker@tranyx.com', isAdmin: true, isP2pAgent: true, role: 'admin' } });
    await assertFails(getDoc(doc(user('attacker', { email: 'attacker@tranyx.com', email_verified: false }), 'system_config/treasury')));
  });
});

describe('PLN: tyxBalance ledger design (assumed shape users/{uid}/ledger/{purpose}_{refId} = {purpose, refPath, amount, balanceBefore, balanceAfter})', () => {
  const ledgerId = 'property_booking_req1';
  const entry = (extra = {}) => ({ purpose: 'property_booking', refPath: 'property_requests/req1', amount: 18050, balanceBefore: 20000, balanceAfter: 1950, createdAt: NOW, ...extra });
  const prep = (extra = {}) => seed({
    'users/u1': userProfile('u1', { tyxBalance: 20000 }), 'users/host': userProfile('host', { tyxBalance: 500, escrowBalance: 0 }),
    'properties/p1': property('host'),
    'property_requests/req1': { propertyId: 'p1', hostId: 'host', renteeId: 'u1', totalCost: 18000, bookingFee: 50, status: 'Approved', createdAt: NOW },
    'property_requests/req2': { propertyId: 'p1', hostId: 'host', renteeId: 'u1', totalCost: 18000, bookingFee: 50, status: 'Approved', createdAt: NOW },
    ...extra,
  });

  it('PLN-A1 [MUST-ALLOW design] owner lowers own balance by exactly the stored price with a matching create-only ledger doc', async () => {
    await prep();
    const db = user('u1'); const b = writeBatch(db);
    b.update(doc(db, 'users/u1'), { tyxBalance: 1950 });
    b.set(doc(db, `users/u1/ledger/${ledgerId}`), entry());
    await assertSucceeds(b.commit());
  });
  planned('PLANNED PLN-01 [CRITICAL] owner cannot pay less than the stored price (balance -100 for an 18,050 booking)', async () => {
    await prep();
    const db = user('u1'); const b = writeBatch(db);
    b.update(doc(db, 'users/u1'), { tyxBalance: 19900 });
    b.set(doc(db, `users/u1/ledger/${ledgerId}`), entry({ amount: 100, balanceAfter: 19900 }));
    await assertFails(b.commit());
  });
  planned('PLANNED PLN-02a [CRITICAL] one ledger doc cannot be reused for a second booking (overwrite existing entry to point at req2)', async () => {
    await prep({ [`users/u1/ledger/${ledgerId}`]: entry() });
    const db = user('u1'); const b = writeBatch(db);
    b.update(doc(db, 'users/u1'), { tyxBalance: 20000 - 18050 });
    b.set(doc(db, `users/u1/ledger/${ledgerId}`), entry({ refPath: 'property_requests/req2' }));
    await assertFails(b.commit());
  });
  planned('PLANNED PLN-02b [HIGH] ledger id must match purpose+ref (id for req1 cannot cite req2)', async () => {
    await prep();
    await assertFails(setDoc(doc(user('u1'), `users/u1/ledger/${ledgerId}`), entry({ refPath: 'property_requests/req2' })));
  });
  planned('PLANNED PLN-03 [CRITICAL] owner cannot update an existing ledger doc (e.g. shrink amount)', async () => {
    await prep({ [`users/u1/ledger/${ledgerId}`]: entry() });
    await assertFails(updateDoc(doc(user('u1'), `users/u1/ledger/${ledgerId}`), { amount: 1 }));
  });
  planned('PLANNED PLN-04 [HIGH] owner cannot delete a ledger doc', async () => {
    await prep({ [`users/u1/ledger/${ledgerId}`]: entry() });
    await assertFails(deleteDoc(doc(user('u1'), `users/u1/ledger/${ledgerId}`)));
  });
  it('PLN-05 [HIGH] another user cannot read someone else\'s ledger doc — secure today (10_...:56 / compiled:166)', async () => {
    await prep({ [`users/u1/ledger/${ledgerId}`]: entry() });
    await assertFails(getDoc(doc(user('u2'), `users/u1/ledger/${ledgerId}`)));
  });
  it('PLN-06 [CRITICAL] client cannot raise the other party\'s tyxBalance (employer -> worker, firebase_service.dart:2100 pattern) — secure today', async () => {
    await prep();
    await assertFails(updateDoc(doc(user('u1'), 'users/host'), { tyxBalance: 18550 }));
  });
  it('PLN-07 [CRITICAL] client cannot raise the other party\'s escrowBalance — secure today', async () => {
    await prep();
    await assertFails(updateDoc(doc(user('u1'), 'users/host'), { escrowBalance: 18050 }));
  });
  planned('PLANNED PLN-08 [CRITICAL] rentee cannot raise/release the host\'s rental escrow (20_...:160-163 / compiled:450-453)', async () => {
    await prep({ 'rental_escrows/r1': { rentalId: 'r1', hostId: 'host', renteeId: 'u1', amount: 2000, status: 'Held', createdAt: NOW } });
    await assertFails(updateDoc(doc(user('u1'), 'rental_escrows/r1'), { amount: 99999, status: 'Released' }));
  });
  planned('PLANNED PLN-09 [CRITICAL] rentee cannot raise/release the host\'s property escrow (40_...:117-120 / compiled:807-810)', async () => {
    await prep({ 'property_escrows/req1': { requestId: 'req1', hostId: 'host', renteeId: 'u1', amount: 18050, status: 'Held', createdAt: NOW } });
    await assertFails(updateDoc(doc(user('u1'), 'property_escrows/req1'), { amount: 99999, status: 'Released' }));
  });
  it('PLN-10 [HIGH] assigned worker cannot raise the job escrow amount — secure today (30_...:171-175 / compiled:656-660)', async () => {
    await prep({ 'jobs/j1': { creatorId: 'host', acceptedApplicantId: 'u1', status: 'In Progress', pricingValue: 800 },
      'escrow/j1': { jobId: 'j1', employerId: 'host', creatorId: 'host', workerId: 'u1', amount: 800, status: 'Held' } });
    await assertFails(updateDoc(doc(user('u1'), 'escrow/j1'), { amount: 8000 }));
  });
});
