// Phase 4 money callables over the real Functions emulator (auth + onCall wrapper + App Check flag).
import { describe, expect, it } from 'vitest';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const FS = '127.0.0.1:8189';
const AUTH = '127.0.0.1:9189';
process.env.FIRESTORE_EMULATOR_HOST = FS;
initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();
const base = 'http://127.0.0.1:5189/demo-tranyx/us-central1';
const APPCHECK_ON = process.env.ENFORCE_APP_CHECK !== 'false';
let n = 0;
const key = () => `e2ekey_${Date.now()}_${++n}`;

async function signUp(email: string) {
  const r = await fetch(`http://${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, password: 'Passw0rd!x', returnSecureToken: true }),
  });
  return (await r.json()) as { idToken: string; localId: string };
}
async function call(fn: string, data: unknown, idToken?: string) {
  const r = await fetch(`${base}/${fn}`, {
    method: 'POST', headers: { 'content-type': 'application/json', ...(idToken ? { authorization: `Bearer ${idToken}` } : {}) }, body: JSON.stringify({ data }),
  });
  return { status: r.status, body: (await r.json()) as any };
}

describe.runIf(APPCHECK_ON)('money callables: App Check enforced by default', () => {
  it('a signed-in caller without an App Check token is rejected for every money callable and nothing moves', async () => {
    const u = await signUp(`m1${Date.now()}@example.com`);
    await db.doc(`users/${u.localId}`).set({ tyxBalance: 5000 });
    for (const fn of ['subscribeWithBalance', 'bookingRequest', 'bookingAction', 'rentalExtension', 'listingFee', 'jobAction']) {
      const r = await call(fn, { idempotencyKey: key(), plan: 'monthly', action: 'create', job: { pricingValue: 100 } }, u.idToken);
      expect(r.status, fn).toBe(401);
    }
    expect((await db.doc(`users/${u.localId}`).get()).get('tyxBalance')).toBe(5000);
  });
});

describe.runIf(!APPCHECK_ON)('money callables over the Functions emulator (App Check off for the test)', () => {
  it('unauthenticated is refused; subscribe, gig lifecycle and booking lifecycle work end to end', async () => {
    expect((await call('subscribeWithBalance', { idempotencyKey: key(), plan: 'monthly' })).status).toBe(401);

    const renter = await signUp(`r${Date.now()}@example.com`);
    const host = await signUp(`h${Date.now()}@example.com`);
    await db.doc(`users/${renter.localId}`).set({ tyxBalance: 10000, name: 'R' });
    await db.doc(`users/${host.localId}`).set({ tyxBalance: 0, name: 'H' });

    // subscribe: price from config, replay safe
    const k = key();
    const s = await call('subscribeWithBalance', { idempotencyKey: k, plan: 'monthly', price: 1 }, renter.idToken);
    expect(s.status).toBe(200);
    expect(s.body.result.amount).toBe(299);
    await call('subscribeWithBalance', { idempotencyKey: k, plan: 'monthly' }, renter.idToken);
    expect((await db.doc(`users/${renter.localId}`).get()).get('tyxBalance')).toBe(10000 - 299);
    const bad = await call('subscribeWithBalance', { idempotencyKey: key(), plan: 'weekly' }, renter.idToken);
    expect(bad.status).toBe(400);

    // vehicle booking: book -> host completes -> payout once
    await db.doc('rentals/ve2e').set({ hostId: host.localId, status: 'Available', acceptingBookings: true, priceDaily: 1000, brand: 'T', model: 'V' });
    const b = await call('bookingRequest', { idempotencyKey: key(), kind: 'vehicle', listingId: 've2e', durationType: 'Daily', multiplier: 2, request: { totalCost: 1 } }, renter.idToken);
    expect(b.status).toBe(200);
    expect(b.body.result.totalPaid).toBe(2060);
    const reqId = b.body.result.requestId as string;
    await db.doc(`rental_requests/${reqId}`).update({ status: 'Booked' });
    const stranger = await signUp(`x${Date.now()}@example.com`);
    const denied = await call('bookingAction', { idempotencyKey: key(), kind: 'vehicle', requestId: reqId, action: 'complete' }, stranger.idToken);
    expect(denied.status).toBe(403);
    const done = await call('bookingAction', { idempotencyKey: key(), kind: 'vehicle', requestId: reqId, action: 'complete' }, host.idToken);
    expect(done.body.result.payout).toBe(1940);
    const again = await call('bookingAction', { idempotencyKey: key(), kind: 'vehicle', requestId: reqId, action: 'complete' }, host.idToken);
    expect(again.body.result.alreadyDone).toBe(true);
    expect((await db.doc(`users/${host.localId}`).get()).get('tyxBalance')).toBe(1940);

    // gig: create -> cancel refunds once
    const j = await call('jobAction', { idempotencyKey: key(), action: 'create', job: { title: 'T', pricingValue: 500 } }, renter.idToken);
    expect(j.body.result.total).toBe(550);
    const jobId = j.body.result.jobId as string;
    const c1 = await call('jobAction', { idempotencyKey: key(), action: 'cancel', jobId }, renter.idToken);
    expect(c1.body.result.refund).toBe(550);
    const c2 = await call('jobAction', { idempotencyKey: key(), action: 'cancel', jobId }, renter.idToken);
    expect(c2.status).toBe(400);
    expect((await db.doc(`users/${renter.localId}`).get()).get('tyxBalance')).toBe(10000 - 299 - 2060);
  });
});
