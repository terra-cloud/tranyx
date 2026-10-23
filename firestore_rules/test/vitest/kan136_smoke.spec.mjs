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
  it('SMOKE-Payout [MUST-ALLOW] worker creates payout_nyx_ with job-bound amount', async () => {
    await seed({
      'users/worker': userProfile('worker'),
      'jobs/j1': job('poster', { status: 'In Progress', acceptedApplicantId: 'worker', pricingValue: PRICE }),
    });
    await assertSucceeds(setDoc(doc(user('worker'), 'transactions/payout_nyx_j1'), {
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
  it('SMOKE-Admin [MUST-ALLOW] adminClaim still creates payout', async () => {
    await seed({
      'jobs/j1': job('poster', { status: 'In Progress', acceptedApplicantId: 'worker', pricingValue: PRICE }),
    });
    await assertSucceeds(setDoc(doc(adminClaim(), 'transactions/payout_nyx_j1'), {
      uid: 'worker', amount: PAYOUT, status: 'Successful', type: 'payout', createdAt: NOW,
    }));
  });
});
