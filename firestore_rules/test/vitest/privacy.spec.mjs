// Privacy & guest access.
import { describe, expect, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { knownHole, setupEnv, seed, user, guest, adminClaim, userProfile, job, property, vehicle } from './helpers.mjs';

setupEnv();

const seedListings = () => seed({
  'users/poster': userProfile('poster'), 'users/host': userProfile('host'),
  'jobs/j1': job('poster'), 'properties/p1': property('host'), 'rentals/r1': vehicle('host'),
  'jobs/j1/questions/q1': { authorId: 'u2', text: 'Is parking available?', createdAt: 1 },
  'jobs/j1/qna/q1': { authorId: 'u2', question: 'Tools provided?', createdAt: 1 },
  'properties/p1/questions/q1': { authorId: 'u2', text: 'Pets allowed?', createdAt: 1 },
  'rentals/r1/qna/q1': { authorId: 'u2', question: 'Dashcam included?', createdAt: 1 },
});

describe('PRV: guest must-allow reads', () => {
  it('PRV-01 [MUST-ALLOW] guest can read a job', async () => { await seedListings(); await assertSucceeds(getDoc(doc(guest(), 'jobs/j1'))); });
  it('PRV-02 [MUST-ALLOW] guest can read a vehicle rental', async () => { await seedListings(); await assertSucceeds(getDoc(doc(guest(), 'rentals/r1'))); });
  it('PRV-03 [MUST-ALLOW] guest can read a property', async () => { await seedListings(); await assertSucceeds(getDoc(doc(guest(), 'properties/p1'))); });
  it('PRV-04 [MUST-ALLOW] guest can read Q&A on jobs, properties, rentals', async () => {
    await seedListings();
    for (const p of ['jobs/j1/questions/q1', 'jobs/j1/qna/q1', 'properties/p1/questions/q1', 'rentals/r1/qna/q1'])
      await assertSucceeds(getDoc(doc(guest(), p)));
  });
});

describe('PRV: guest denied all writes', () => {
  const targets = {
    'users/g1': userProfile('g1'), 'jobs/jg': job('g1'), 'properties/pg': property('g1'), 'rentals/rg': vehicle('g1'),
    'jobs/j1/questions/qg': { authorId: 'g1', text: 'spam' }, 'properties/p1/qna/qg': { authorId: 'g1', question: 'spam' },
    'transactions/tg': { uid: 'g1', type: 'deposit', amount: 1 }, 'withdrawals/wg': { uid: 'g1', amount: 1 },
    'deposits/dg': { uid: 'g1', amount: 1 }, 'claimed_p2p_references/cg': { uid: 'g1' }, 'p2p_agents/g1': { uid: 'g1' },
    'config/app_config': { maintenance: true }, 'system_config/treasury': { x: 1 }, 'subscriptions/sg': { uid: 'g1' },
    'requests/rq': { status: 'PENDING' }, 'mail/m1': { to: 'x@example.org' }, 'presence/g1': { online: true },
  };
  for (const [path, data] of Object.entries(targets)) {
    it(`PRV-05 [HIGH] guest cannot write ${path}`, async () => {
      await seedListings();
      await assertFails(setDoc(doc(guest(), path), data));
    });
  }
});

describe('PRV: users/{id} private fields (Firestore has no field-level read; whole-doc read tested)', () => {
  it('PRV-06 [HIGH] guest cannot read users/{id} containing email/phone/wallet/balance (10_...:7 / compiled:117)', async () => {
    await seed({ 'users/victim': userProfile('victim') });
    await assertFails(getDoc(doc(guest(), 'users/victim')));
  });
  it('PRV-07 [HIGH] another signed-in user cannot read users/{id} private fields', async () => {
    await seed({ 'users/victim': userProfile('victim') });
    await assertFails(getDoc(doc(user('u2'), 'users/victim')));
  });
  it('PRV-08 [MUST-ALLOW] owner can read own users doc', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    await assertSucceeds(getDoc(doc(user('u1'), 'users/u1')));
  });
  it('PRV-09 [HIGH] another user cannot read kyc_submissions — secure today', async () => {
    await seed({ 'kyc_submissions/victim': { uid: 'victim', govtIdUrl: 'https://example.invalid/id.jpg', status: 'pending' } });
    await assertFails(getDoc(doc(user('u2'), 'kyc_submissions/victim')));
  });
});

describe('PRV: public profile projection', () => {
  const card = {
    uid: 'victim', name: 'User victim', photoUrl: '', headline: 'Handyman', accountType: 'nyxian',
    skills: ['plumbing'], hourlyRate: 250, rating: 4.8, isPremium: false,
  };
  it('PRV-07b [MUST-ALLOW] a signed-in user can read a public profile and not the private user doc', async () => {
    await seed({ 'users/victim': userProfile('victim'), 'public_profiles/victim': card });
    const snap = await assertSucceeds(getDoc(doc(user('u2'), 'public_profiles/victim')));
    expect(snap.data().email).toBeUndefined();
    expect(snap.data().phoneNumber).toBeUndefined();
    expect(snap.data().walletPublicKey).toBeUndefined();
    expect(snap.data().idVerified).toBeUndefined();
    expect(snap.data().name).toBe('User victim');
    await assertFails(getDoc(doc(user('u2'), 'users/victim')));
  });
  it('PRV-07c [HIGH] owner cannot publish email, phone, wallet, balance, or idVerified on the public profile', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    const db = user('u1');
    for (const extra of [
      { email: 'u1@gmail.com' },
      { phoneNumber: '+639171234567' },
      { walletPublicKey: '9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin' },
      { tyxBalance: 100 },
      { idVerified: true },
      { verificationLevel: 2 },
    ]) {
      await assertFails(setDoc(doc(db, 'public_profiles/u1'), { ...card, uid: 'u1', ...extra }));
    }
  });
  it('PRV-07d [HIGH] owner cannot publish a rating or premium flag that the user doc does not have', async () => {
    await seed({ 'users/u1': userProfile('u1', { rating: 4.8, isPremium: false }) });
    const db = user('u1');
    await assertFails(setDoc(doc(db, 'public_profiles/u1'), { ...card, uid: 'u1', rating: 5 }));
    await assertFails(setDoc(doc(db, 'public_profiles/u1'), { ...card, uid: 'u1', isPremium: true }));
    await assertSucceeds(setDoc(doc(db, 'public_profiles/u1'), { ...card, uid: 'u1' }));
  });
  it('PRV-07e [MUST-ALLOW] claim staff can still read the private user doc', async () => {
    await seed({ 'users/victim': userProfile('victim') });
    await assertSucceeds(getDoc(doc(adminClaim(), 'users/victim')));
  });
});

describe('PRV: completion codes are not a client field on a public job', () => {
  it('PRV-10 [CRITICAL] a guest can read a job that has no completion code', async () => {
    const clean = job('poster');
    delete clean.completionCode;
    await seed({ 'users/poster': userProfile('poster'), 'jobs/clean': clean });
    const snap = await assertSucceeds(getDoc(doc(guest(), 'jobs/clean')));
    expect(snap.data().completionCode).toBeUndefined();
    expect(snap.data().verificationCode).toBeUndefined();
    expect(snap.data().title).toBe('Fix sink');
  });
  it('PRV-11 [CRITICAL] clients cannot write completionCode or verificationCode onto a job', async () => {
    const clean = job('poster', { status: 'In Progress', acceptedApplicantId: 'worker' });
    delete clean.completionCode;
    await seed({ 'users/poster': userProfile('poster'), 'users/worker': userProfile('worker'), 'jobs/j1': clean });
    await assertFails(setDoc(doc(user('poster'), 'jobs/new'), job('poster')));
    await assertFails(updateDoc(doc(user('poster'), 'jobs/j1'), { completionCode: '111111' }));
    await assertFails(updateDoc(doc(user('worker'), 'jobs/j1'), { verificationCode: '222222' }));
    await assertFails(updateDoc(doc(adminClaim('poster'), 'jobs/j1'), { completionCode: '333333' }));
    const snap = await assertSucceeds(getDoc(doc(user('worker'), 'jobs/j1')));
    expect(snap.data().completionCode).toBeUndefined();
  });
});

describe('PRV: listing address is masked for guests', () => {
  const mask = 'Brgy. *****, ****';
  it('PRV-12 [MEDIUM] a guest can read a job but not its exact address or coordinates', async () => {
    const clean = job('poster');
    for (const key of ['address', 'landmark', 'pickupAddress', 'pickupLat', 'pickupLng', 'destinationAddress', 'destinationLat', 'destinationLng']) delete clean[key];
    clean.addressPublic = mask;
    await seed({
      'users/poster': userProfile('poster'),
      'jobs/j1': clean,
      'jobs/j1/private/location': { address: '12 Mabini St', pickupLat: 14.55, pickupLng: 121.02 },
    });
    const snap = await assertSucceeds(getDoc(doc(guest(), 'jobs/j1')));
    expect(snap.data().addressPublic).toBe(mask);
    expect(snap.data().address).toBeUndefined();
    expect(snap.data().pickupLat).toBeUndefined();
    expect(snap.data().pickupLng).toBeUndefined();
    await assertFails(getDoc(doc(guest(), 'jobs/j1/private/location')));
    const exact = await assertSucceeds(getDoc(doc(user('reader'), 'jobs/j1/private/location')));
    expect(exact.data().address).toBe('12 Mabini St');
    expect(exact.data().pickupLat).toBe(14.55);
    await assertFails(setDoc(doc(user('poster'), 'jobs/j2'), job('poster')));
  });
  it('PRV-13 [MEDIUM] a guest can read a property but not its exact address or coordinates', async () => {
    const clean = property('host');
    for (const key of ['address', 'location', 'landmark', 'lat', 'lng', 'latitude', 'longitude']) delete clean[key];
    clean.addressPublic = mask;
    await seed({
      'users/host': userProfile('host'),
      'properties/p1': clean,
      'properties/p1/private/location': { address: 'Unit 12B', latitude: 14.55, longitude: 121.05 },
    });
    const snap = await assertSucceeds(getDoc(doc(guest(), 'properties/p1')));
    expect(snap.data().address).toBeUndefined();
    expect(snap.data().latitude).toBeUndefined();
    expect(snap.data().longitude).toBeUndefined();
    await assertFails(getDoc(doc(guest(), 'properties/p1/private/location')));
    const exact = await assertSucceeds(getDoc(doc(user('reader'), 'properties/p1/private/location')));
    expect(exact.data().address).toBe('Unit 12B');
    await assertFails(setDoc(doc(user('host'), 'properties/p2'), property('host')));
  });
  it('PRV-14 [MEDIUM] a guest can read a vehicle but not its exact pickup address or coordinates', async () => {
    const clean = vehicle('host');
    for (const key of ['location', 'pickupAddress', 'pickupLat', 'pickupLng']) delete clean[key];
    clean.addressPublic = mask;
    await seed({
      'users/host': userProfile('host'),
      'rentals/r1': clean,
      'rentals/r1/private/location': { pickupAddress: '45 Kalayaan Ave', pickupLat: 14.64, pickupLng: 121.05 },
    });
    const snap = await assertSucceeds(getDoc(doc(guest(), 'rentals/r1')));
    expect(snap.data().pickupAddress).toBeUndefined();
    expect(snap.data().pickupLat).toBeUndefined();
    expect(snap.data().pickupLng).toBeUndefined();
    await assertFails(getDoc(doc(guest(), 'rentals/r1/private/location')));
    const exact = await assertSucceeds(getDoc(doc(user('reader'), 'rentals/r1/private/location')));
    expect(exact.data().pickupAddress).toBe('45 Kalayaan Ave');
    await assertFails(setDoc(doc(user('host'), 'rentals/r2'), vehicle('host')));
  });
});
