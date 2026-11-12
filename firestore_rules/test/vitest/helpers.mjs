// Shared harness. Project id is demo-* so the SDK can only ever talk to the local emulator.
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { beforeAll, afterAll, beforeEach } from 'vitest';

export const PROJECT_ID = 'demo-tranyx';
export let env;

// Default: the repo's compiled rules (firestore_rules/test/vitest/ -> repo root /firestore.rules).
// Override: RULES_FILE=/abs/or/relative/firestore.rules (relative to the cwd).
export const RULES_PATH = process.env.RULES_FILE
  ? resolve(process.cwd(), process.env.RULES_FILE)
  : fileURLToPath(new URL('../../../firestore.rules', import.meta.url));

export function setupEnv() {
  beforeAll(async () => {
    if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run via `npm test` (firebase emulators:exec); no emulator host set.');
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { rules: readFileSync(RULES_PATH, 'utf8') },
    });
  });
  beforeEach(async () => { await env.clearFirestore(); });
  afterAll(async () => { await env?.cleanup(); });
}

// Default identity: an ordinary verified Gmail signup with NO custom claims.
export const user = (uid, token = {}) =>
  env.authenticatedContext(uid, { email: `${uid}@gmail.com`, email_verified: true, ...token }).firestore();
export const guest = () => env.unauthenticatedContext().firestore();
export const adminClaim = (uid = 'realAdmin') =>
  env.authenticatedContext(uid, { email: 'ops@example.org', email_verified: true, admin: true }).firestore();

export async function seed(docs) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [path, data] of Object.entries(docs)) await db.doc(path).set(data);
  });
}

const NOW = 1761120000000; // fixed epoch ms, 2025-10-22
// Payload shapes follow packages/shared/lib/src/models.dart toMap().
export const userProfile = (uid, extra = {}) => ({
  uid, name: `User ${uid}`, email: `${uid}@gmail.com`, photoUrl: '', phoneNumber: '+639171234567',
  accountType: 'nyxian', headline: 'Handyman', hourlyRate: 250, skills: ['plumbing'], rating: 4.8,
  createdAt: NOW, walletPublicKey: '9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin', tyxBalance: 100,
  reservedBalance: 0, jobsDone: 3, totalEarned: 1200, verificationLevel: 1, emailVerified: true,
  phoneVerified: true, idVerified: false, bgChecked: false, isPremium: false, premiumUntil: null,
  isBonded: false, terraPoints: 0, abandonedJobs: 0, ...extra,
});
export const job = (creatorId, extra = {}) => ({
  creatorId, creatorName: 'Employer', creatorPhotoUrl: '', creatorType: 'individual', title: 'Fix sink',
  description: 'Leaking kitchen sink', category: 'homeServices', categoryGroup: 'home', employmentType: 'Gig',
  dateRequirement: 'ASAP', jobDate: NOW, timePreference: 'Morning', pricingType: 'Fixed Task', pricingValue: 800,
  locationType: 'Onsite', address: '12 Mabini St, Brgy. San Antonio, Makati', landmark: 'near 7-Eleven',
  createdAt: NOW, status: 'Open', applicantCount: 1, recentApplicantPhotos: [], applicantUids: ['worker'],
  pickupAddress: '12 Mabini St, Makati', pickupLat: 14.5547, pickupLng: 121.0244,
  destinationAddress: null, destinationLat: null, destinationLng: null, hasTracker: false,
  acceptedApplicantId: null, completionCode: '482913', receiptUrl: null, employerRated: false,
  nyxianRated: false, promoCode: null, discountAmount: 0, imageUrls: [], acknowledgmentReminderSent: false, ...extra,
});
export const property = (hostId, extra = {}) => ({
  id: 'prop1', hostId, hostName: 'Host', hostPhotoUrl: '', title: 'Studio near BGC', description: 'Cozy studio',
  type: 'condo', category: 'residential', priceMonthly: 18000, priceWeekly: 5000, priceDaily: 900,
  depositMonths: 1, securityDepositAmount: 18000, advanceAmount: 18000, depositType: 'months', depositValue: 1,
  securityDepositPolicy: { type: 'months', value: 1 }, isListingFeeWaived: false, allowedDurations: ['monthly'],
  address: 'Unit 12B, 8 Forbes Town Rd, Taguig', latitude: 14.5503, longitude: 121.0501, photoUrls: [],
  amenities: ['wifi'], status: 'Available', acceptingBookings: true, isDeleted: false, contractType: 'standard',
  contractTerms: '', createdAt: NOW, allowChat: true, renteeId: null, renteeName: null, ...extra,
});
export const vehicle = (hostId, extra = {}) => ({
  id: 'veh1', hostId, hostName: 'Host', brand: 'Toyota', model: 'Vios', year: 2022, type: 'sedan',
  plateNumber: 'NAB 1234', transmission: 'Automatic', fuelType: 'Gasoline', seatingCapacity: 5,
  price12h: 1200, priceDaily: 2000, priceWeekly: 12000, priceMonthly: 40000, status: 'Available',
  acceptingBookings: true, pickupAddress: '45 Kalayaan Ave, Quezon City', pickupLat: 14.6488, pickupLng: 121.0509,
  description: 'Clean unit', features: ['dashcam'], createdAt: NOW, ...extra,
});
export const withdrawal = (uid, extra = {}) => ({
  uid, userId: uid, amount: 500, cryptoAmount: 8.9, currency: 'TYX', destinationWallet: '7YttLkHDoNj9wyDur5pM1ejNaAvT9X4eqaYcHQqtj2G5',
  originRail: 'mwa_on_chain', paymentMethod: 'Solana Wallet', payoutMethod: 'Solana', balanceDeducted: true,
  status: 'PENDING_REVIEW', createdAt: NOW, updatedAt: NOW, ...extra,
});

// KNOWN-HOLE wrapper: vitest it.fails() with the secure assertion inside.
// Only a genuine "hole" signal (assertFails saw the request SUCCEED, or the ESC-AGG expectation mismatch)
// is re-thrown as the expected failure. Any other error (seed/setup/emulator) is swallowed so it.fails turns RED,
// which stops a broken test from hiding as a "known hole".
import { it as vitIt } from 'vitest';
export function knownHole(name, fn) { holeOrPlanned(name, fn); }
// PLANNED: must-deny tests written against a design that isn't built yet (Saga's tyxBalance ledger design).
export function planned(name, fn) { holeOrPlanned(name, fn); }
function holeOrPlanned(name, fn) {
  vitIt.fails(name, async () => {
    try { await fn(); } catch (e) {
      const msg = String(e?.message ?? e);
      if (/Expected request to fail, but it succeeded|expected \[.*\] to deeply equal \[\]/s.test(msg)) throw e;
      console.error(`[${name}] non-hole error, failing loudly: ${msg}`);
      return;
    }
  });
}
