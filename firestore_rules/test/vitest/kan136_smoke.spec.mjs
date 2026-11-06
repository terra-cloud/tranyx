// Optional Saga smoke (non-colliding IDs). Kelvin's full suite is kan136.spec.mjs.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, writeBatch, updateDoc } from 'firebase/firestore';
import { setupEnv, seed, user, adminClaim, userProfile, job } from './helpers.mjs';

setupEnv();
const NOW = 1761120000000;
const PRICE = 800;
const PAYOUT = PRICE - PRICE * 0.03;

describe('KAN-136 smoke (Saga)', () => {
  it('SMOKE-Payout [HIGH] worker cannot client-create payout_nyx_ even with the job-bound amount', async () => {
    await seed({
      'users/worker': userProfile('worker'),
      'jobs/j1': job('poster', { status: 'In Progress', acceptedApplicantId: 'worker', pricingValue: PRICE }),
    });
    await assertFails(setDoc(doc(user('worker'), 'transactions/payout_nyx_j1'), {
      uid: 'worker', amount: PAYOUT, baseAmount: PRICE, commissionRate: 0.03, holdbackRate: 0.10,
      status: 'Successful', type: 'payout', createdAt: NOW,
    }));
  });
  it('SMOKE-D2 [CRITICAL] over-price payout amount denied', async () => {
    await seed({
      'users/worker': userProfile('worker'),
      'jobs/j1': job('poster', { status: 'In Progress', acceptedApplicantId: 'worker', pricingValue: PRICE }),
    });
    await assertFails(setDoc(doc(user('worker'), 'transactions/payout_nyx_j1'), {
      uid: 'worker', amount: 1000000, baseAmount: PRICE, commissionRate: 0.03, holdbackRate: 0.10,
      status: 'Successful', type: 'payout', createdAt: NOW,
    }));
  });
  it('SMOKE-Admin [HIGH] a staff client cannot create payout_nyx_', async () => {
    await seed({
      'jobs/j1': job('poster', { status: 'In Progress', acceptedApplicantId: 'worker', pricingValue: PRICE }),
    });
    await assertFails(setDoc(doc(adminClaim(), 'transactions/payout_nyx_j1'), {
      uid: 'worker', amount: PAYOUT, status: 'Successful', type: 'payout', createdAt: NOW,
    }));
  });
});
