// rental_requests / property_requests are participant or claim-staff reads.
// terraPoints cannot be self-granted. Public listing docs stay world-readable.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, deleteField, doc, getDoc, getDocs, query, setDoc, updateDoc, where } from 'firebase/firestore';
import { setupEnv, seed, user, guest, adminClaim, userProfile } from './helpers.mjs';

setupEnv();

const request = (over = {}) => ({
  status: 'Pending', hostId: 'host', renteeId: 'ren', rentalId: 'veh1', propertyId: 'prop1',
  totalCost: 1000, createdAt: 1, ...over,
});

describe.each(['rental_requests', 'property_requests'])('%s reads', (col) => {
  const prep = (over = {}) => seed({
    'users/host': userProfile('host'),
    'users/ren': userProfile('ren'),
    'users/other': userProfile('other'),
    'users/flag': userProfile('flag', { isAdmin: true, role: 'admin' }),
    'rentals/veh1': { hostId: 'host', title: 'Vios', status: 'Available' },
    'properties/prop1': { hostId: 'host', title: 'Studio', status: 'Available' },
    [`${col}/r1`]: request(over),
  });

  it('host, renter, and renterId alias can get; stranger, guest, and a doc-flag admin cannot', async () => {
    await prep();
    await assertSucceeds(getDoc(doc(user('host'), `${col}/r1`)));
    await assertSucceeds(getDoc(doc(user('ren'), `${col}/r1`)));
    await assertFails(getDoc(doc(user('other'), `${col}/r1`)));
    await assertFails(getDoc(doc(guest(), `${col}/r1`)));
    await assertFails(getDoc(doc(user('flag'), `${col}/r1`)));
    await prep({ renteeId: 'someone', renterId: 'ren' });
    await assertSucceeds(getDoc(doc(user('ren'), `${col}/r1`)));
    await assertFails(getDoc(doc(user('other'), `${col}/r1`)));
  });

  it('claim staff can get; a role=agent claim can get; an unfiltered list cannot', async () => {
    await prep();
    await assertSucceeds(getDoc(doc(adminClaim(), `${col}/r1`)));
    await assertSucceeds(getDoc(doc(user('desk', { role: 'agent' }), `${col}/r1`)));
    await assertFails(getDocs(collection(user('other'), col)));
    await assertFails(getDocs(collection(user('host'), col)));
  });

  it('hostId and renteeId queries succeed for that party; a listing-id query does not', async () => {
    await prep();
    const host = user('host');
    const ren = user('ren');
    const other = user('other');
    const listingField = col === 'rental_requests' ? 'rentalId' : 'propertyId';
    const listingId = col === 'rental_requests' ? 'veh1' : 'prop1';
    await assertSucceeds(getDocs(query(collection(host, col), where('hostId', '==', 'host'))));
    await assertSucceeds(getDocs(query(collection(host, col), where('hostId', '==', 'host'), where('status', '==', 'Pending'))));
    await assertSucceeds(getDocs(query(collection(ren, col), where('renteeId', '==', 'ren'))));
    await assertSucceeds(getDocs(query(collection(ren, col), where('renteeId', '==', 'ren'), where('status', '==', 'Pending'))));
    await assertFails(getDocs(query(collection(other, col), where(listingField, '==', listingId))));
    await assertFails(getDocs(query(collection(host, col), where(listingField, '==', listingId))));
    await assertFails(getDocs(query(collection(other, col), where('hostId', '==', 'host'))));
    await assertSucceeds(getDocs(query(collection(host, col), where('hostId', '==', 'host'), where(listingField, '==', listingId))));
    await assertFails(getDocs(query(collection(other, col), where('hostId', '==', 'host'), where(listingField, '==', listingId))));
  });
});

describe('public listings stay readable', () => {
  it('a guest can read a rental and a property listing', async () => {
    await seed({
      'rentals/veh1': { hostId: 'host', title: 'Vios', status: 'Available' },
      'properties/prop1': { hostId: 'host', title: 'Studio', status: 'Available' },
    });
    await assertSucceeds(getDoc(doc(guest(), 'rentals/veh1')));
    await assertSucceeds(getDoc(doc(guest(), 'properties/prop1')));
  });
});

describe('terraPoints cannot be self-granted', () => {
  it('signup with zero or omitted points works; a positive create does not', async () => {
    await assertSucceeds(setDoc(doc(user('s0'), 'users/s0'), userProfile('s0', { tyxBalance: 0, reservedBalance: 0, terraPoints: 0 })));
    const omitted = userProfile('s1', { tyxBalance: 0, reservedBalance: 0 });
    delete omitted.terraPoints;
    await assertSucceeds(setDoc(doc(user('s1'), 'users/s1'), omitted));
    await assertFails(setDoc(doc(user('s2'), 'users/s2'), userProfile('s2', { tyxBalance: 0, reservedBalance: 0, terraPoints: 40 })));
  });

  it('an owner can edit a profile field and cannot raise, merge, or clear-and-rewrite points', async () => {
    await seed({ 'users/u1': userProfile('u1', { terraPoints: 0 }) });
    const me = user('u1');
    await assertSucceeds(updateDoc(doc(me, 'users/u1'), { headline: 'Still a handyman' }));
    await assertFails(updateDoc(doc(me, 'users/u1'), { terraPoints: 100 }));
    await assertFails(setDoc(doc(me, 'users/u1'), { terraPoints: 100 }, { merge: true }));
    await assertFails(updateDoc(doc(me, 'users/u1'), { terraPoints: deleteField() }));
    await assertFails(setDoc(doc(me, 'users/u1'), userProfile('u1', { tyxBalance: 100, terraPoints: 100 })));
  });

  it('a doc-flag admin cannot grant points; a claim admin can', async () => {
    await seed({
      'users/u1': userProfile('u1', { terraPoints: 0 }),
      'users/flag': userProfile('flag', { isAdmin: true, role: 'admin' }),
      'points_history/mine': { uid: 'u1', questId: 'register_account', points: 500 },
    });
    await assertFails(updateDoc(doc(user('flag'), 'users/u1'), { terraPoints: 500 }));
    await assertSucceeds(updateDoc(doc(adminClaim(), 'users/u1'), { terraPoints: 15 }));
    await assertFails(setDoc(doc(user('u1'), 'points_history/h1'), { uid: 'u1', questId: 'register_account', points: 500 }));
    await assertSucceeds(getDoc(doc(user('u1'), 'points_history/mine')));
  });
});
