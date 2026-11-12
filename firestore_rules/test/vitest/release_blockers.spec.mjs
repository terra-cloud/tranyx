// Public-release blockers: job_secrets, rental_requests / property_requests guard. Emulator only (demo-tranyx).
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';
import { setupEnv, seed, user, guest, adminClaim, userProfile, job } from './helpers.mjs';

setupEnv();
const profiles = { 'users/host': userProfile('host'), 'users/ren': userProfile('ren'), 'users/other': userProfile('other') };
const req = (over = {}) => ({ id: 'r1', status: 'Pending', renteeId: 'ren', renterId: 'ren', hostId: 'host', totalCost: 1000, bookingFee: 30, promoCode: null, createdAt: 1, ...over });
const held = (col) => ({ [`${col}/r1`]: { status: 'Held', renteeId: 'ren', hostId: 'host', amount: 1000 } });

describe('job_secrets + completionCode', () => {
  it('nobody reads or writes job_secrets from a client (employer, worker, other, guest)', async () => {
    await seed({ ...profiles, 'jobs/j1': job('host', { status: 'In Progress', acceptedApplicantId: 'ren' }), 'job_secrets/j1': { code: '123456' } });
    for (const c of [user('host'), user('ren'), user('other'), guest()]) {
      await assertFails(getDoc(doc(c, 'job_secrets/j1')));
      await assertFails(setDoc(doc(c, 'job_secrets/j1'), { code: '000000' }));
    }
    await assertFails(setDoc(doc(user('host'), 'job_secrets/j2'), { code: '111111' }));
  });
  it('neither employer nor worker can write completionCode on the job doc any more', async () => {
    await seed({ ...profiles, 'jobs/j1': job('host', { status: 'Open' }), 'jobs/j2': job('host', { status: 'In Progress', acceptedApplicantId: 'ren' }) });
    await assertFails(updateDoc(doc(user('host'), 'jobs/j1'), { completionCode: '111111' }));
    await assertFails(updateDoc(doc(user('ren'), 'jobs/j2'), { completionCode: '111111' }));
    await assertFails(updateDoc(doc(user('ren'), 'jobs/j2'), { status: 'Done', completionCode: '111111' }));
    await assertSucceeds(updateDoc(doc(user('ren'), 'jobs/j2'), { status: 'Done' }));
  });
});

describe.each([['rental_requests', 'rental_escrows'], ['property_requests', 'property_escrows']])('%s guard', (col, esc) => {
  const seedReq = (over = {}, withEscrow = true) => seed({ ...profiles, [`${col}/r1`]: req(over), ...(withEscrow ? held(esc) : {}) });
  const as = (uid) => doc(user(uid), `${col}/r1`);

  it('clients cannot create or delete requests', async () => {
    await seed(profiles);
    await assertFails(setDoc(doc(user('ren'), `${col}/new`), req({ status: 'Booked' })));
    await seedReq();
    await assertFails(deleteDoc(as('ren')));
    await assertFails(deleteDoc(as('host')));
    await assertSucceeds(setDoc(doc(adminClaim(), `${col}/new`), req()));
  });
  it('a stranger cannot touch the request', async () => {
    await seedReq();
    await assertFails(updateDoc(as('other'), { status: 'Approved' }));
    await assertFails(updateDoc(as('other'), { allowChat: true }));
  });
  it('host approves Pending only; renter cannot approve; no re-approve', async () => {
    await seedReq();
    await assertFails(updateDoc(as('ren'), { status: 'Approved' }));
    await assertSucceeds(updateDoc(as('host'), { status: 'Approved', allowChat: true, approvedAt: 5 }));
    await assertFails(updateDoc(as('host'), { status: 'Pending' }));
  });
  it('renter signs (Booked) only after approval, and the host cannot sign for them', async () => {
    await seedReq({ status: 'Pending' });
    await assertFails(updateDoc(as('ren'), { status: 'Booked' }));
    await seedReq({ status: 'Approved' });
    await assertFails(updateDoc(as('host'), { status: 'Booked' }));
    await assertSucceeds(updateDoc(as('ren'), { status: 'Booked', signedAt: 5, contractId: 'c1' }));
  });
  it('with an escrow held, no party can write Cancelled / Rejected / Completed (that would block the refund or payout)', async () => {
    for (const st of ['Cancelled', 'Rejected', 'Completed']) {
      await seedReq({ status: 'Booked' });
      await assertFails(updateDoc(as('ren'), { status: st }));
      await assertFails(updateDoc(as('host'), { status: st }));
    }
  });
  it('echoing a status the callable already set stays allowed (client writes after the callable)', async () => {
    await seedReq({ status: 'Cancelled' });
    await assertSucceeds(updateDoc(as('ren'), { status: 'Cancelled' }));
    await assertSucceeds(updateDoc(as('host'), { cancelledAt: 5 }));
    await assertFails(updateDoc(as('ren'), { status: 'Booked' }));
  });
  it('legacy request with no escrow can still be closed by a party', async () => {
    await seedReq({ status: 'Pending' }, false);
    await assertSucceeds(updateDoc(as('host'), { status: 'Rejected', rejectedAt: 5 }));
    await seedReq({ status: 'Pending' }, false);
    await assertSucceeds(updateDoc(as('ren'), { status: 'Cancelled', cancelledAt: 5 }));
  });
  it('money / identity fields are immutable for clients; extension rewrite (endDate, totalCost) works', async () => {
    await seedReq({ status: 'Booked', endDate: 10 });
    await assertFails(updateDoc(as('ren'), { bookingFee: 0 }));
    await assertFails(updateDoc(as('ren'), { hostId: 'ren' }));
    await assertFails(updateDoc(as('host'), { renteeId: 'host' }));
    await assertFails(updateDoc(as('ren'), { promoCode: 'FREE' }));
    await assertSucceeds(updateDoc(as('ren'), { endDate: 20, totalCost: 1100 }));
    await assertSucceeds(updateDoc(as('host'), { status: 'Active' }));
  });
  it('[MUST-ALLOW] staff can still repair any request', async () => {
    await seedReq({ status: 'Booked' });
    await assertSucceeds(updateDoc(doc(adminClaim(), `${col}/r1`), { status: 'Cancelled' }));
  });
});
