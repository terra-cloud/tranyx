// Phase 4 money callables against the Firestore emulator (npm run test:emulator).
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { MoneyDeps } from '../src/money';
import { subscribeWithBalance } from '../src/subscribe';
import { bookingAction, bookingRequest, listingFee, rentalExtension } from '../src/booking';
import { jobAction } from '../src/jobs';
import { optimizedBase, promoDiscount, propertyFinancials } from '../src/pricing';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8189';
initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();
let clock = Date.UTC(2026, 9, 30, 4, 0, 0);
const deps = (): MoneyDeps => ({ db, now: () => clock });
const HOUR = 3_600_000;
let n = 0;
const key = () => `key_${Date.now()}_${++n}_abcdef`;
const as = (uid: string, token: Record<string, unknown> = {}) => ({ uid, token });

async function clearAll() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-tranyx/databases/(default)/documents`, { method: 'DELETE' });
}
const bal = async (uid: string) => (await db.doc(`users/${uid}`).get()).get('tyxBalance') as number;
const err = async (p: Promise<unknown>) => p.then(() => null, (e: any) => e);

async function seedUsers() {
  for (const [uid, b] of [['renter', 10000], ['host', 0], ['worker', 0], ['employer', 5000], ['poor', 10], ['other', 100]] as const) {
    await db.doc(`users/${uid}`).set({ tyxBalance: b, reservedBalance: 0 });
  }
}
async function seedVehicle() {
  await db.doc('rentals/v1').set({ hostId: 'host', status: 'Available', acceptingBookings: true, brand: 'Toyota', model: 'Vios', year: '2022', priceDaily: 1000, priceWeekly: 6000, priceMonthly: 20000, price12h: 600 });
}
async function seedProperty() {
  await db.doc('properties/p1').set({ hostId: 'host', status: 'Available', title: 'Loft', priceDaily: 2000, priceWeekly: 12000, securityDepositPolicy: { type: 'fixed', value: 3000 } });
}
const vehicleReq = (k = key(), over: Record<string, unknown> = {}) =>
  bookingRequest(deps(), as('renter'), { idempotencyKey: k, kind: 'vehicle', listingId: 'v1', durationType: 'Daily', multiplier: 3, startDate: clock, endDate: clock + 3 * 24 * HOUR, request: { totalCost: 1, bookingFee: 0, renteeName: 'R', brand: 'FAKE' }, ...over });

beforeAll(async () => { await clearAll(); });
beforeEach(async () => { await clearAll(); await seedUsers(); });

describe('pricing ports', () => {
  it('SmartRateEngine caps days at the weekly rate', () => {
    expect(optimizedBase({ price12h: 0, priceDaily: 1000, priceWeekly: 6000, priceMonthly: 20000 }, 3)).toBe(3000);
    expect(optimizedBase({ price12h: 0, priceDaily: 1000, priceWeekly: 6000, priceMonthly: 20000 }, 6)).toBe(6000);
    expect(optimizedBase({ price12h: 0, priceDaily: 1000, priceWeekly: 6000, priceMonthly: 20000 }, 10)).toBe(9000);
    expect(optimizedBase({ price12h: 600, priceDaily: 1000, priceWeekly: 0, priceMonthly: 0 }, 0, 24)).toBe(1200);
  });
  it('property financials: tiers, fixed deposit, fee, commission', () => {
    const f = propertyFinancials({ priceDaily: 2000, priceWeekly: 12000, securityDepositPolicy: { type: 'fixed', value: 3000 } }, 8, 0.03, 0.07);
    expect(f.baseRent).toBe(14000);
    expect(f.securityDeposit).toBe(3000);
    expect(f.customerPlatformFee).toBe(420);
    expect(f.hostCommission).toBe(980);
  });
  it('promo can only discount the fee and respects limits', () => {
    const o = { base: 1000, fee: 30, uid: 'u', now: 1, module: 'vehicle_rentals' };
    expect(promoDiscount({ isActive: true, discountType: 'flat', discountValue: 500 }, o)).toBe(30);
    expect(promoDiscount({ isActive: true, discountType: 'percentage', discountValue: 50 }, o)).toBe(15);
    expect(promoDiscount({ isActive: false }, o)).toBeNull();
    expect(promoDiscount({ isActive: true, discountType: 'flat', discountValue: 5, usedBy: ['u'], maxUsesPerUser: 1 }, o)).toBeNull();
    expect(promoDiscount({ isActive: true, discountType: 'flat', discountValue: 5, eligibleModules: ['jobs'] }, o)).toBeNull();
  });
});

describe('subscribeWithBalance', () => {
  it('debits the config price, extends premium, writes ledger once on replay', async () => {
    const k = key();
    const r = await subscribeWithBalance(deps(), as('renter'), { idempotencyKey: k, plan: 'monthly' });
    expect(r.amount).toBe(299);
    expect(await bal('renter')).toBe(10000 - 299);
    const again = await subscribeWithBalance(deps(), as('renter'), { idempotencyKey: k, plan: 'monthly' });
    expect(again.replay).toBe(true);
    expect(await bal('renter')).toBe(10000 - 299);
    const u = (await db.doc('users/renter').get()).data()!;
    expect(u.isPremium).toBe(true);
    expect(u.premiumUntil).toBe(clock + 30 * 24 * HOUR);
  });
  it('rejects insufficient balance, bad plan, unauthenticated; ignores client amount', async () => {
    expect((await err(subscribeWithBalance(deps(), as('poor'), { idempotencyKey: key(), plan: 'yearly' })))?.code).toBe('failed-precondition');
    expect((await err(subscribeWithBalance(deps(), as('renter'), { idempotencyKey: key(), plan: 'weekly' })))?.code).toBe('invalid-argument');
    expect((await err(subscribeWithBalance(deps(), undefined, { idempotencyKey: key(), plan: 'monthly' })))?.code).toBe('unauthenticated');
    await subscribeWithBalance(deps(), as('renter'), { idempotencyKey: key(), plan: 'yearly', price: 1, amount: 1 });
    expect(await bal('renter')).toBe(10000 - 2999);
  });
});

describe('vehicle booking', () => {
  beforeEach(seedVehicle);
  it('recomputes price from the listing, ignoring client totals; creates request + server-owned escrow', async () => {
    const r = await vehicleReq();
    expect(r.base).toBe(3000);
    expect(r.totalPaid).toBe(3090);
    expect(await bal('renter')).toBe(10000 - 3090);
    const esc = (await db.doc(`rental_escrows/${r.requestId}`).get()).data()!;
    expect(esc).toMatchObject({ status: 'Held', amount: 3000, totalPaid: 3090, renteeId: 'renter', hostId: 'host' });
    const req = (await db.doc(`rental_requests/${r.requestId}`).get()).data()!;
    expect(req).toMatchObject({ totalCost: 3000, bookingFee: 90, status: 'Pending', renteeId: 'renter', brand: 'Toyota' });
  });
  it('is idempotent, blocks own listing, insufficient funds, unavailable listing', async () => {
    const k = key();
    await vehicleReq(k);
    const again = await vehicleReq(k);
    expect(again.replay).toBe(true);
    expect(await bal('renter')).toBe(10000 - 3090);
    expect((await err(bookingRequest(deps(), as('host'), { idempotencyKey: key(), kind: 'vehicle', listingId: 'v1', durationType: 'Daily', multiplier: 1 })))?.code).toBe('failed-precondition');
    expect((await err(bookingRequest(deps(), as('poor'), { idempotencyKey: key(), kind: 'vehicle', listingId: 'v1', durationType: 'Daily', multiplier: 1 })))?.code).toBe('failed-precondition');
    await db.doc('rentals/v1').update({ status: 'Archived' });
    expect((await err(vehicleReq()))?.code).toBe('failed-precondition');
  });
  it('promo discounts only the fee (host price untouched)', async () => {
    await db.doc('promos/SAVE').set({ isActive: true, discountType: 'flat', discountValue: 40, eligibleModules: ['all'] });
    const r = await vehicleReq(key(), { promoCode: 'SAVE', discountAmount: 99999 });
    expect(r.discount).toBe(40);
    expect(r.totalPaid).toBe(3050);
    expect((await err(vehicleReq(key(), { promoCode: 'NOPE' })))?.code).toBe('failed-precondition');
  });
  it('reject / cancelRequest / revoke refund once and only by the right party', async () => {
    const r = await vehicleReq();
    const base = { kind: 'vehicle', requestId: r.requestId, listingId: 'v1' };
    expect((await err(bookingAction(deps(), as('other'), { ...base, idempotencyKey: key(), action: 'reject' })))?.code).toBe('permission-denied');
    expect((await err(bookingAction(deps(), as('host'), { ...base, idempotencyKey: key(), action: 'cancelRequest' })))?.code).toBe('permission-denied');
    const rej = await bookingAction(deps(), as('host'), { ...base, idempotencyKey: key(), action: 'reject' });
    expect(rej.refund).toBe(3090);
    expect(await bal('renter')).toBe(10000);
    const second = await bookingAction(deps(), as('host'), { ...base, idempotencyKey: key(), action: 'reject' });
    expect(second.alreadyDone).toBe(true);
    const cancelAfter = await bookingAction(deps(), as('renter'), { ...base, idempotencyKey: key(), action: 'cancelRequest' });
    expect(cancelAfter.alreadyDone).toBe(true);
    expect(await bal('renter')).toBe(10000);
    expect((await db.doc(`rental_requests/${r.requestId}`).get()).get('status')).toBe('Rejected');
  });
  it('renter cancelRequest after approval refunds everything once; host revoke too', async () => {
    const a = await vehicleReq();
    await db.doc(`rental_requests/${a.requestId}`).update({ status: 'Awaiting Signature' });
    const base = { kind: 'vehicle', listingId: 'v1' };
    expect((await bookingAction(deps(), as('host'), { ...base, requestId: a.requestId, idempotencyKey: key(), action: 'revoke' })).refund).toBe(3090);
    expect(await bal('renter')).toBe(10000);
    const b = await vehicleReq();
    await db.doc(`rental_requests/${b.requestId}`).update({ status: 'Approved' });
    expect((await bookingAction(deps(), as('renter'), { ...base, requestId: b.requestId, idempotencyKey: key(), action: 'cancelRequest' })).refund).toBe(3090);
    expect(await bal('renter')).toBe(10000);
  });
  it('cancelActive refunds minus the flat fee; complete pays host minus 3% once; no refund after payout', async () => {
    const a = await vehicleReq();
    await db.doc(`rental_requests/${a.requestId}`).update({ status: 'Booked' });
    const base = { kind: 'vehicle', listingId: 'v1' };
    expect((await bookingAction(deps(), as('renter'), { ...base, requestId: a.requestId, idempotencyKey: key(), action: 'cancelActive' })).refund).toBe(3088);
    expect(await bal('renter')).toBe(10000 - 2);

    const b = await vehicleReq();
    await db.doc(`rental_requests/${b.requestId}`).update({ status: 'Booked' });
    const done = await bookingAction(deps(), as('host'), { ...base, requestId: b.requestId, idempotencyKey: key(), action: 'complete' });
    expect(done.payout).toBe(2910);
    expect(await bal('host')).toBe(2910);
    expect((await bookingAction(deps(), as('host'), { ...base, requestId: b.requestId, idempotencyKey: key(), action: 'complete' })).alreadyDone).toBe(true);
    expect(await bal('host')).toBe(2910);
    expect((await err(bookingAction(deps(), as('renter'), { ...base, requestId: b.requestId, idempotencyKey: key(), action: 'cancelActive' })))?.code).toBe('failed-precondition');
    expect(await bal('host')).toBe(2910);
  });
  it('a stranger cannot complete, and a Pending request cannot be completed', async () => {
    const a = await vehicleReq();
    const base = { kind: 'vehicle', listingId: 'v1', requestId: a.requestId };
    expect((await err(bookingAction(deps(), as('other'), { ...base, idempotencyKey: key(), action: 'complete' })))?.code).toBe('permission-denied');
    expect((await err(bookingAction(deps(), as('host'), { ...base, idempotencyKey: key(), action: 'complete' })))?.code).toBe('failed-precondition');
    expect(await bal('host')).toBe(0);
  });
  it('extensions: server fee from listing rate; approve merges, reject refunds once', async () => {
    const a = await vehicleReq();
    await db.doc(`rental_requests/${a.requestId}`).update({ status: 'Booked' });
    await db.doc('rentals/v1').update({ extensionRatePerHour: 100 });
    const ext = await rentalExtension(deps(), as('renter'), { idempotencyKey: key(), action: 'request', rentalId: 'v1', requestId: a.requestId, extendHours: 3, fee: 1 });
    expect(ext.fee).toBe(300);
    expect(await bal('renter')).toBe(10000 - 3090 - 300);
    expect((await err(rentalExtension(deps(), as('other'), { idempotencyKey: key(), action: 'approve', extensionId: ext.extensionId })))?.code).toBe('permission-denied');
    await rentalExtension(deps(), as('host'), { idempotencyKey: key(), action: 'approve', extensionId: ext.extensionId });
    expect((await db.doc(`rental_escrows/${a.requestId}`).get()).get('amount')).toBe(3300);
    expect((await err(rentalExtension(deps(), as('host'), { idempotencyKey: key(), action: 'reject', extensionId: ext.extensionId })))?.code).toBe('failed-precondition');

    const e2 = await rentalExtension(deps(), as('renter'), { idempotencyKey: key(), action: 'autoApprove', rentalId: 'v1', requestId: a.requestId, extendHours: 2 });
    expect(e2.fee).toBe(200);
    expect((await db.doc(`rental_escrows/${a.requestId}`).get()).get('totalPaid')).toBe(3090 + 300 + 200);
    const e3 = await rentalExtension(deps(), as('renter'), { idempotencyKey: key(), action: 'request', rentalId: 'v1', requestId: a.requestId, extendHours: 1 });
    const before = await bal('renter');
    await rentalExtension(deps(), as('host'), { idempotencyKey: key(), action: 'reject', extensionId: e3.extensionId });
    expect(await bal('renter')).toBe(before + 100);
    expect((await err(rentalExtension(deps(), as('host'), { idempotencyKey: key(), action: 'reject', extensionId: e3.extensionId })))?.code).toBe('failed-precondition');
    // payout covers the extended amount: 3000+300+200 = 3500 -> 3395
    const done = await bookingAction(deps(), as('host'), { kind: 'vehicle', listingId: 'v1', requestId: a.requestId, idempotencyKey: key(), action: 'complete' });
    expect(done.payout).toBe(3395);
  });
});

describe('property booking', () => {
  beforeEach(async () => { await seedProperty(); await db.doc('users/renter').update({ tyxBalance: 30000 }); });
  const pr = (k = key()) => bookingRequest(deps(), as('renter'), { idempotencyKey: k, kind: 'property', listingId: 'p1', durationType: 'Daily', multiplier: 8, startDate: clock, endDate: clock + 8 * 24 * HOUR, request: { title: 'x' }, baseRentAmount: 1, securityDepositAmount: 0 });
  it('server computes rent + 3% fee + deposit; complete pays host minus 7% and refunds deposit', async () => {
    const r = await pr();
    expect(r.base).toBe(14000);
    expect(r.securityDeposit).toBe(3000);
    expect(r.totalPaid).toBe(14000 + 420 + 3000);
    await db.doc(`property_requests/${r.requestId}`).update({ status: 'Booked' });
    const done = await bookingAction(deps(), as('renter'), { kind: 'property', requestId: r.requestId, listingId: 'p1', idempotencyKey: key(), action: 'complete' });
    expect(done.payout).toBe(14000 - 980);
    expect(done.deposit).toBe(3000);
    expect(await bal('host')).toBe(13020);
    expect(await bal('renter')).toBe(30000 - 17420 + 3000);
  });
});

describe('listing fee', () => {
  it('is a no-op at rate 0 and charges/refunds once when set', async () => {
    await db.doc('rentals/v1').set({ hostId: 'host', priceDaily: 1000 });
    expect((await listingFee(deps(), as('host'), { idempotencyKey: key(), kind: 'vehicle', listingId: 'v1', op: 'charge' })).amount).toBe(0);
    await db.doc('listing_fees/vehicle_v1').delete();
    await db.doc('settings/platform_fees').set({ listingFeeRate: 0.01 });
    await db.doc('users/host').update({ tyxBalance: 100 });
    expect((await listingFee(deps(), as('host'), { idempotencyKey: key(), kind: 'vehicle', listingId: 'v1', op: 'charge' })).amount).toBe(10);
    expect(await bal('host')).toBe(90);
    expect((await listingFee(deps(), as('host'), { idempotencyKey: key(), kind: 'vehicle', listingId: 'v1', op: 'refund' })).amount).toBe(10);
    expect((await listingFee(deps(), as('host'), { idempotencyKey: key(), kind: 'vehicle', listingId: 'v1', op: 'refund' })).nothingToRefund).toBe(true);
    expect(await bal('host')).toBe(100);
    expect((await err(listingFee(deps(), as('other'), { idempotencyKey: key(), kind: 'vehicle', listingId: 'v1', op: 'charge' })))?.code).toBe('permission-denied');
  });
});

describe('jobs', () => {
  const create = (over: Record<string, unknown> = {}, k = key()) =>
    jobAction(deps(), as('employer'), { idempotencyKey: k, action: 'create', job: { title: 'Fix sink', pricingValue: 1000, status: 'Completed', creatorId: 'worker', totalEscrowed: 1, ...over } });
  const apply = (rate: number, counter: boolean) => db.doc('jobs/job_x/applications/worker').set({ applicantUid: 'worker', applicantName: 'W', proposalRate: rate, isCounterOffer: counter });

  it('create: employer pays price + 10% fees; job + escrow server-built; client status/creator ignored', async () => {
    const r = await create();
    expect(r.total).toBe(1100);
    expect(await bal('employer')).toBe(5000 - 1100);
    const job = (await db.doc(`jobs/${r.jobId}`).get()).data()!;
    expect(job).toMatchObject({ status: 'Open', creatorId: 'employer', pricingValue: 1000, totalEscrowed: 1100 });
    expect((await db.doc(`escrow/${r.jobId}`).get()).data()).toMatchObject({ status: 'held', amount: 1000, employerFees: 100, price: 1000 });
    const k = key();
    await create({}, k);
    const again = await create({}, k);
    expect(again.replay).toBe(true);
    expect(await bal('employer')).toBe(5000 - 2200);
    expect((await err(jobAction(deps(), as('poor'), { idempotencyKey: key(), action: 'create', job: { pricingValue: 1000 } })))?.code).toBe('failed-precondition');
    expect((await err(jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'create', job: { pricingValue: -5 } })))?.code).toBe('invalid-argument');
  });

  it('accept: counter offer adjusts total cost by the fee-inclusive diff; non-creator blocked', async () => {
    const r = await create({}, 'x'.repeat(8));
    expect(r.jobId).toBe('job_xxxxxxxx');
    await db.doc('jobs/job_xxxxxxxx/applications/worker').set({ applicantUid: 'worker', applicantName: 'W', proposalRate: 1200, isCounterOffer: true });
    expect((await err(jobAction(deps(), as('other'), { idempotencyKey: key(), action: 'accept', jobId: r.jobId, applicantUid: 'worker' })))?.code).toBe('permission-denied');
    const a = await jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'accept', jobId: r.jobId, applicantUid: 'worker', jobPatch: { acknowledgmentStatus: 'pending', status: 'Completed', pricingValue: 1 } });
    expect(a.adjustment).toBe(220);
    expect(await bal('employer')).toBe(5000 - 1100 - 220);
    expect((await db.doc(`escrow/${r.jobId}`).get()).data()).toMatchObject({ amount: 1200, employerFees: 120, totalEscrowed: 1320, price: 1200 });
    expect((await db.doc(`jobs/${r.jobId}`).get()).data()).toMatchObject({ status: 'Awaiting Acknowledgment', acceptedApplicantId: 'worker', pricingValue: 1200, acknowledgmentStatus: 'pending' });
    expect((await err(jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'accept', jobId: r.jobId, applicantUid: 'worker' })))?.code).toBe('failed-precondition');
  });

  it('accept rejects an out-of-range counter offer and an applicant who never applied', async () => {
    const r = await create();
    await db.doc(`jobs/${r.jobId}/applications/worker`).set({ applicantUid: 'worker', proposalRate: 5000, isCounterOffer: true });
    expect((await err(jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'accept', jobId: r.jobId, applicantUid: 'worker' })))?.code).toBe('failed-precondition');
    expect((await err(jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'accept', jobId: r.jobId, applicantUid: 'ghost' })))?.code).toBe('failed-precondition');
    void apply;
  });

  async function hired(extra: Record<string, unknown> = {}) {
    const r = await create(extra);
    await db.doc(`jobs/${r.jobId}/applications/worker`).set({ applicantUid: 'worker', proposalRate: 1000, isCounterOffer: false });
    await jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'accept', jobId: r.jobId, applicantUid: 'worker' });
    await db.doc(`jobs/${r.jobId}`).update({ completionCode: '123456', status: 'In Progress' });
    return r.jobId as string;
  }

  it('complete: worker paid price - 3% once from escrow; code and role enforced', async () => {
    const jobId = await hired();
    expect((await err(jobAction(deps(), as('worker'), { idempotencyKey: key(), action: 'complete', jobId, verificationCode: '000000' })))?.code).toBe('failed-precondition');
    expect((await err(jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'complete', jobId, verificationCode: '123456' })))?.code).toBe('permission-denied');
    const done = await jobAction(deps(), as('worker'), { idempotencyKey: key(), action: 'complete', jobId, verificationCode: '123456' });
    expect(done.payout).toBe(970);
    expect(await bal('worker')).toBe(970);
    expect((await db.doc(`jobs/${jobId}`).get()).get('status')).toBe('Completed');
    expect((await db.doc(`platform_fees/${jobId}`).get()).get('totalFees')).toBe(30 + 100);
    expect((await err(jobAction(deps(), as('worker'), { idempotencyKey: key(), action: 'complete', jobId, verificationCode: '123456' })))?.code).toBe('failed-precondition');
    expect(await bal('worker')).toBe(970);
    expect((await err(jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'cancel', jobId })))?.code).toBe('failed-precondition');
  });

  it('complete with inspection holdback pays 90% now, then worker releases the holdback after 48h', async () => {
    const jobId = await hired({ hasInspectionHoldback: true });
    const done = await jobAction(deps(), as('worker'), { idempotencyKey: key(), action: 'complete', jobId, verificationCode: '123456' });
    expect(done.payout).toBe(870);
    expect(done.holdback).toBe(100);
    const early = await jobAction(deps(), as('worker'), { idempotencyKey: key(), action: 'releaseHoldbacks' });
    expect(early.released).toBe(0);
    clock += 49 * HOUR;
    const rel = await jobAction(deps(), as('worker'), { idempotencyKey: key(), action: 'releaseHoldbacks' });
    expect(rel.total).toBe(100);
    expect(await bal('worker')).toBe(970);
    expect((await jobAction(deps(), as('worker'), { idempotencyKey: key(), action: 'releaseHoldbacks' })).released).toBe(0);
    expect(await bal('worker')).toBe(970);
  });

  it('cancel an open gig: full refund (price + fees) once; committed gig cannot be cancelled', async () => {
    const r = await create();
    const c = await jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'cancel', jobId: r.jobId });
    expect(c.refund).toBe(1100);
    expect(await bal('employer')).toBe(5000);
    expect((await err(jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'cancel', jobId: r.jobId })))?.code).toBe('failed-precondition');
    expect(await bal('employer')).toBe(5000);
    const committed = await hired();
    await db.doc(`jobs/${committed}`).update({ acknowledgmentStatus: 'acknowledged' });
    expect((await err(jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'cancel', jobId: committed })))?.code).toBe('failed-precondition');
    expect((await err(jobAction(deps(), as('other'), { idempotencyKey: key(), action: 'cancel', jobId: r.jobId })))?.code).toBe('permission-denied');
  });

  it('reclaim needs 48h of server-visible inactivity; delete only an open gig', async () => {
    const jobId = await hired();
    await db.doc(`jobs/${jobId}`).update({ updatedAt: 0 }); // employer backdating updatedAt must not help
    expect((await err(jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'reclaim', jobId })))?.code).toBe('failed-precondition');
    clock += 49 * HOUR;
    const rc = await jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'reclaim', jobId });
    expect(rc.refund).toBe(1100);
    expect((await db.doc(`jobs/${jobId}`).get()).get('status')).toBe('Abandoned');
    expect((await db.doc('users/worker').get()).get('abandonedJobs')).toBe(1);
    const open = await create();
    const del = await jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'delete', jobId: open.jobId });
    expect(del.refund).toBe(1100);
    expect((await db.doc(`jobs/${open.jobId}`).get()).exists).toBe(false);
    const busy = await hired();
    expect((await err(jobAction(deps(), as('employer'), { idempotencyKey: key(), action: 'delete', jobId: busy })))?.code).toBe('failed-precondition');
  });
});
