// Must-allow regressions modelled on the real client writes from the Oct 9-15 commits. Plain it(): must PASS now and forever.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { knownHole, setupEnv, seed, user, guest, userProfile, job, property, vehicle } from './helpers.mjs';

setupEnv();
const NOW = 1761123600000;

describe('MA-44527aa accept applicant (tranyx_app.dart jobPatch via setDocument)', () => {
  for (const status of ['Open', 'Reviewing']) {
    it(`MA-01-${status} [MUST-ALLOW] poster accepts applicant on a ${status} job`, async () => {
      await seed({ 'users/poster': userProfile('poster'), 'jobs/j1': job('poster', { status }) });
      await assertSucceeds(updateDoc(doc(user('poster'), 'jobs/j1'), {
        status: 'Awaiting Acknowledgment', acceptedApplicantId: 'worker', acceptedApplicantName: 'Juan',
        hiredAt: NOW, acknowledgmentDeadline: NOW + 30 * 60000, acknowledgmentSlaMinutes: 30,
        acknowledgmentCategory: 'homeServices', acknowledgmentStatus: 'pending', acknowledgmentReminderSent: false,
        updatedAt: NOW, pricingValue: 900, pricingType: 'Fixed Task',
      }));
    });
  }
  it('MA-01-neg [HIGH] non-poster cannot accept an applicant (secure counterpart)', async () => {
    await seed({ 'users/u2': userProfile('u2'), 'jobs/j1': job('poster') });
    await assertFails(updateDoc(doc(user('u2'), 'jobs/j1'), { status: 'Awaiting Acknowledgment', acceptedApplicantId: 'u2' }));
  });
  it('MA-02 [MUST-ALLOW] assigned worker acknowledges the job', async () => {
    await seed({ 'users/worker': userProfile('worker'), 'jobs/j1': job('poster', { status: 'Awaiting Acknowledgment', acceptedApplicantId: 'worker' }) });
    await assertSucceeds(updateDoc(doc(user('worker'), 'jobs/j1'), { status: 'In Progress', acknowledgmentStatus: 'acknowledged', acknowledgedAt: NOW, updatedAt: NOW }));
  });
  it('MA-03 [MUST-ALLOW] applicant applies to an open job (count/uids/photos)', async () => {
    await seed({ 'users/a2': userProfile('a2'), 'jobs/j1': job('poster') });
    await assertSucceeds(updateDoc(doc(user('a2'), 'jobs/j1'), { applicantCount: 2, applicantUids: ['worker', 'a2'], recentApplicantPhotos: [''] }));
  });
});

describe('MA-f5d33f3 listing editable fields', () => {
  it('MA-04 [MUST-ALLOW] host edits vehicle listing fields while Not Accepting Bookings', async () => {
    await seed({ 'users/host': userProfile('host'), 'rentals/r1': vehicle('host', { status: 'Not Accepting Bookings', acceptingBookings: false }) });
    await assertSucceeds(updateDoc(doc(user('host'), 'rentals/r1'), {
      description: 'Freshly detailed', features: ['dashcam', 'bluetooth'], seatingCapacity: 5, fuelPolicy: 'full-to-full',
      pickupAddress: '50 Kalayaan Ave, QC', pickupLat: 14.649, pickupLng: 121.051, priceDaily: 2200, price12h: 1300,
      priceWeekly: 13000, priceMonthly: 42000, extraPhotos: ['https://example.invalid/a.webp'], status: 'Available',
      acceptingBookings: true, updatedAt: NOW,
    }));
  });
  it('MA-04-neg [HIGH] host cannot set invalid vehicle pricing (12h > daily)', async () => {
    await seed({ 'users/host': userProfile('host'), 'rentals/r1': vehicle('host') });
    await assertFails(updateDoc(doc(user('host'), 'rentals/r1'), { price12h: 5000 }));
  });
  it('MA-05 [MUST-ALLOW] host edits property listing fields while Not Accepting Bookings', async () => {
    await seed({ 'users/host': userProfile('host'), 'properties/p1': property('host', { status: 'Not Accepting Bookings', acceptingBookings: false }) });
    await assertSucceeds(updateDoc(doc(user('host'), 'properties/p1'), {
      title: 'Bright studio near BGC', description: 'Newly furnished', priceMonthly: 19000, depositMonths: 2,
      securityDepositAmount: 38000, photoUrls: ['https://example.invalid/p.webp'], latitude: 14.5504, longitude: 121.0502,
      furnishing: 'fully', sqft: 280, status: 'Available', acceptingBookings: true, updatedAt: NOW,
    }));
  });
  it('MA-05-neg [HIGH] host cannot reprice an actively Booked property', async () => {
    await seed({ 'users/host': userProfile('host'), 'properties/p1': property('host', { status: 'Booked', renteeId: 'renter' }) });
    await assertFails(updateDoc(doc(user('host'), 'properties/p1'), { priceMonthly: 99000 }));
  });
});

describe('MA-406b37c config read', () => {
  it('MA-06 [MUST-ALLOW] signed-in user reads config/app_config', async () => {
    await seed({ 'config/app_config': { minAppVersion: '1.4.0', maintenance: false } });
    await assertSucceeds(getDoc(doc(user('u1'), 'config/app_config')));
  });
  it('MA-06-neg-guest [MEDIUM] guest cannot read config', async () => {
    await seed({ 'config/app_config': { minAppVersion: '1.4.0' } });
    await assertFails(getDoc(doc(guest(), 'config/app_config')));
  });
  it('MA-06-neg-write [HIGH] ordinary user cannot write config', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    await assertFails(setDoc(doc(user('u1'), 'config/app_config'), { maintenance: true }));
  });
  knownHole('KNOWN-HOLE MA-06-hole [HIGH] ordinary user cannot read third-party API config docs (config/{docId} widened in 406b37c: 60_...:82-85 / compiled:993-996)', async () => {
    await seed({ 'config/imgbb': { apiKey: 'FIXTURE_NOT_A_SECRET' } });
    await assertFails(getDoc(doc(user('u1'), 'config/imgbb')));
  });
});

describe('MA-68b6c86 host lease reset (completePropertyRental payload, firebase_service.dart)', () => {
  const booked = (status) => property('host', {
    status, renteeId: 'renter', renteeName: 'Ana', renteePhotoUrl: '', rentalDurationType: 'monthly', rentalMultiplier: 1,
    startDate: NOW - 86400000 * 30, endDate: NOW, totalCost: 18000, baseRentAmount: 18000, securityDepositAmount: 18000,
    bookingFee: 50, renteeSignatureName: 'Ana Cruz', signedAt: NOW - 86400000 * 31, currentRequestId: 'req1', licenseNumber: 'N01-23-456789',
  });
  for (const status of ['Booked', 'Active']) {
    it(`MA-07-${status} [MUST-ALLOW] host resets ${status} property to Available after completion`, async () => {
      await seed({ 'users/host': userProfile('host'), 'properties/p1': booked(status) });
      await assertSucceeds(updateDoc(doc(user('host'), 'properties/p1'), {
        status: 'Available', renteeId: '', renteeName: '', renteePhotoUrl: '', rentalDurationType: '', rentalMultiplier: 0,
        startDate: 0, endDate: 0, totalCost: 0.0, baseRentAmount: 0.0, securityDepositAmount: 0.0, bookingFee: 0.0,
        renteeSignatureName: '', signedAt: 0, currentRequestId: '', licenseNumber: '',
      }));
    });
  }
  it('MA-07-neg [HIGH] non-host cannot reset the lease', async () => {
    await seed({ 'users/renter': userProfile('renter'), 'properties/p1': booked('Active') });
    await assertFails(updateDoc(doc(user('renter'), 'properties/p1'), { status: 'Available', renteeId: '', currentRequestId: '' }));
  });
});

describe('MA: baseline profile', () => {
  it('MA-08 [MUST-ALLOW] fresh signup creates a normal profile', async () => {
    await assertSucceeds(setDoc(doc(user('new1'), 'users/new1'), userProfile('new1', { tyxBalance: 0 })));
  });
  it('MA-09 [MUST-ALLOW] owner edits own name/headline/photo', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    await assertSucceeds(updateDoc(doc(user('u1'), 'users/u1'), { name: 'Juan D.', headline: 'Electrician', photoUrl: 'https://example.invalid/a.webp' }));
  });
});
