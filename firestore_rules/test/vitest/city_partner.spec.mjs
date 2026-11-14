// TRAD-15: a Calbayog partner cannot read Tagbilaran, and a normal visitor still can.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, query, collection, where, updateDoc } from 'firebase/firestore';
import { setupEnv, seed, user, adminClaim, env } from './helpers.mjs';

setupEnv();
const renewal = Date.now() + 400 * 86_400_000;
const partner = (uid, partnerId) => env.authenticatedContext(uid, {
  email: `${uid}@gmail.com`,
  email_verified: true,
  admin: false,
  role: 'partner',
  partnerId,
  firebase: { sign_in_second_factor: 'totp' },
}).firestore();

describe('city partner area isolation', () => {
  it('lets a Calbayog partner read only Calbayog, and still lets guests read every public listing', async () => {
    await seed({
      'partners/pCal': { uid: 'pCal', status: 'active', areaKeys: ['calbayog'], renewalDate: renewal },
      'rentals/cal': { areaKey: 'calbayog', hostId: 'h1', status: 'Available', plateNumber: 'ABC 123' },
      'rentals/tag': { areaKey: 'tagbilaran', hostId: 'h2', status: 'Available' },
      'jobs/cal': { areaKey: 'calbayog', creatorId: 'h1', status: 'Open', title: 'Errand' },
      'jobs/tag': { areaKey: 'tagbilaran', creatorId: 'h2', status: 'Open', title: 'Other city' },
      'properties/cal': { areaKey: 'calbayog', hostId: 'h1', status: 'Available', title: 'Room' },
      'properties/tag': { areaKey: 'tagbilaran', hostId: 'h2', status: 'Available', title: 'Other room' },
      'rental_requests/cal': { areaKey: 'calbayog', hostId: 'h1', renteeId: 'r1', status: 'Pending' },
      'rental_requests/tag': { areaKey: 'tagbilaran', hostId: 'h2', renteeId: 'r2', status: 'Pending' },
      'tickets/cal': { areaKey: 'calbayog', userId: 'r1', status: 'Open' },
      'tickets/tag': { areaKey: 'tagbilaran', userId: 'r2', status: 'Open' },
      'users/r1': { uid: 'r1', name: 'Maria Santos', email: 'maria@example.com', areaKey: 'calbayog' },
      'settings/platform_fees': { listingFeeRate: 0 },
      'rentals/cal/private/location': { address: '12 Real St, Calbayog' },
    });
    const cal = partner('pCal', 'pCal');
    await assertSucceeds(getDoc(doc(cal, 'rentals/cal')));
    await assertSucceeds(getDocs(query(collection(cal, 'rentals'), where('areaKey', '==', 'calbayog'))));
    await assertFails(getDoc(doc(cal, 'rentals/tag')));
    await assertFails(getDocs(collection(cal, 'rentals')));
    await assertFails(getDoc(doc(cal, 'jobs/tag')));
    await assertFails(getDoc(doc(cal, 'properties/tag')));
    await assertSucceeds(getDoc(doc(cal, 'rental_requests/cal')));
    await assertFails(getDoc(doc(cal, 'rental_requests/tag')));
    await assertSucceeds(getDoc(doc(cal, 'tickets/cal')));
    await assertFails(getDoc(doc(cal, 'tickets/tag')));
    await assertFails(getDoc(doc(cal, 'users/r1')));
    await assertFails(getDoc(doc(cal, 'settings/platform_fees')));
    await assertFails(getDoc(doc(cal, 'rentals/cal/private/location')));
    await assertFails(updateDoc(doc(cal, 'users/r1'), { suspendedUntil: Date.now() + 86_400_000, banned: true }));
    await assertSucceeds(getDoc(doc(user('guest'), 'rentals/tag')));
    await assertSucceeds(getDocs(collection(user('guest'), 'rentals')));
    await assertSucceeds(getDoc(doc(adminClaim(), 'rentals/tag')));
    await assertSucceeds(getDoc(doc(user('guest'), 'settings/platform_fees')));
  });

  it('rejects a partner token that has not completed a second factor', async () => {
    await seed({
      'partners/pCal': { uid: 'pCal', status: 'active', areaKeys: ['calbayog'], renewalDate: renewal },
      'rentals/cal': { areaKey: 'calbayog', hostId: 'h1', status: 'Available' },
    });
    const noMfa = env.authenticatedContext('pCal', {
      email: 'pcal@gmail.com', email_verified: true, admin: false, role: 'partner', partnerId: 'pCal',
    }).firestore();
    await assertFails(getDoc(doc(noMfa, 'rentals/cal')));
  });
});
