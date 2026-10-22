// Privacy & guest access.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { knownHole, setupEnv, seed, user, guest, userProfile, job, property, vehicle } from './helpers.mjs';

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
  knownHole('KNOWN-HOLE PRV-06 [HIGH] guest cannot read users/{id} containing email/phone/wallet/balance (10_...:7 / compiled:117)', async () => {
    await seed({ 'users/victim': userProfile('victim') });
    await assertFails(getDoc(doc(guest(), 'users/victim')));
  });
  knownHole('KNOWN-HOLE PRV-07 [HIGH] another signed-in user cannot read users/{id} private fields (compiled:117)', async () => {
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

describe('PRV: listing secrets & exact locations', () => {
  knownHole('KNOWN-HOLE PRV-10 [CRITICAL] non-poster (guest) cannot read job completionCode (30_workspace_jobs.rules:7 / compiled:492)', async () => {
    await seedListings();
    await assertFails(getDoc(doc(guest(), 'jobs/j1')));
  });
  knownHole('KNOWN-HOLE PRV-11 [CRITICAL] non-poster signed-in user (incl. assigned worker before completion) cannot read completionCode (compiled:492)', async () => {
    await seed({ 'jobs/j1': job('poster', { status: 'In Progress', acceptedApplicantId: 'worker' }) });
    await assertFails(getDoc(doc(user('worker'), 'jobs/j1')));
  });
  knownHole('KNOWN-HOLE PRV-12 [MEDIUM] guest cannot read exact job address/pickupLat/pickupLng (compiled:492; split public/private doc needed)', async () => {
    await seedListings();
    await assertFails(getDoc(doc(guest(), 'jobs/j1')));
  });
  knownHole('KNOWN-HOLE PRV-13 [MEDIUM] guest cannot read exact property address/latitude/longitude (40_...:7 / compiled:697)', async () => {
    await seedListings();
    await assertFails(getDoc(doc(guest(), 'properties/p1')));
  });
  knownHole('KNOWN-HOLE PRV-14 [MEDIUM] guest cannot read exact vehicle pickupAddress/pickupLat/pickupLng (20_...:26 / compiled:316)', async () => {
    await seedListings();
    await assertFails(getDoc(doc(guest(), 'rentals/r1')));
  });
});
