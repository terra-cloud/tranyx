// KAN-136 rules stopgap: job completion payout/fee_deduction for regular users.
// Full ledger moves to Cloud Functions (KAN-126). Spec encodes Kelvin's agreed adds:
// 1) tyxBalance increase only alongside payout_nyx_ create, capped at amount
// 2) rates from config/app_config (or job snapshot)
// 3) admin-claims path still works (see also tool/kan136_claims_scout.mjs)
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, writeBatch, deleteDoc,
} from 'firebase/firestore';
import { setupEnv, seed, user, adminClaim, userProfile, job } from './helpers.mjs';

setupEnv();

const NOW = 1761120000000;
const CFG = {
  commissionRate: 0.03,
  holdbackRate: 0.10,
  transactionFeeRate: 0.07,
  convenienceFeeRate: 0.03,
};

const jobReady = (extra = {}) => job('poster', {
  status: 'In Progress',
  acceptedApplicantId: 'worker',
  pricingValue: 800,
  commissionRate: 0.03,
  holdbackRate: 0.10,
  transactionFeeRate: 0.07,
  convenienceFeeRate: 0.03,
  ...extra,
});

function payoutDoc(amount = 696) {
  return {
    uid: 'worker',
    title: 'Gig Payout Released',
    desc: 'Payout for completing job j1',
    amount,
    baseAmount: 800,
    commissionFee: 24,
    commissionRate: 0.03,
    holdbackAmount: 80,
    holdbackRate: 0.10,
    status: 'Successful',
    method: 'Tranyx Wallet',
    type: 'payout',
    createdAt: NOW,
  };
}

function feeDoc(amount = 80) {
  return {
    uid: 'poster',
    title: 'Job Completion Fees',
    desc: 'Fees for job j1',
    amount,
    baseAmount: 800,
    transactionFee: 56,
    convenienceFee: 24,
    transactionFeeRate: 0.07,
    convenienceFeeRate: 0.03,
    status: 'Successful',
    method: 'Tranyx Wallet',
    type: 'fee_deduction',
    createdAt: NOW,
  };
}

async function seedBase(extra = {}) {
  await seed({
    'config/app_config': CFG,
    'users/worker': userProfile('worker', { tyxBalance: 100 }),
    'users/poster': userProfile('poster', { tyxBalance: 500 }),
    'jobs/j1': jobReady(),
    ...extra,
  });
}

describe('KAN-136 stopgap: job completion tx creates', () => {
  it('K136-01 [MUST-ALLOW] worker creates payout_nyx_j1 type=payout', async () => {
    await seedBase();
    await assertSucceeds(setDoc(doc(user('worker'), 'transactions/payout_nyx_j1'), payoutDoc()));
  });

  it('K136-02 [MUST-ALLOW] employer creates fees_emp_j1 type=fee_deduction', async () => {
    await seedBase();
    await assertSucceeds(setDoc(doc(user('poster'), 'transactions/fees_emp_j1'), feeDoc()));
  });

  it('K136-03 [MUST-ALLOW] employer (other party) can create payout_nyx_ for the worker uid', async () => {
    await seedBase();
    await assertSucceeds(setDoc(doc(user('poster'), 'transactions/payout_nyx_j1'), payoutDoc()));
  });

  it('K136-04 [MUST-ALLOW] worker (other party) can create fees_emp_ for the employer uid', async () => {
    await seedBase();
    await assertSucceeds(setDoc(doc(user('worker'), 'transactions/fees_emp_j1'), feeDoc()));
  });

  it('K136-05 [HIGH] stranger cannot create payout_nyx_ / fees_emp_', async () => {
    await seedBase();
    await assertFails(setDoc(doc(user('eve'), 'transactions/payout_nyx_j1'), { ...payoutDoc(), uid: 'eve' }));
    await assertFails(setDoc(doc(user('eve'), 'transactions/fees_emp_j1'), { ...feeDoc(), uid: 'eve' }));
  });

  it('K136-06 [HIGH] arbitrary type=payout on a non-job id still denied for regular users', async () => {
    await seedBase();
    await assertFails(setDoc(doc(user('worker'), 'transactions/random_payout_1'), {
      uid: 'worker', amount: 10, status: 'Successful', type: 'payout', createdAt: NOW,
    }));
  });

  it('K136-07 [HIGH] client-chosen commissionRate that does not match job/config is denied', async () => {
    await seedBase();
    await assertFails(setDoc(doc(user('worker'), 'transactions/payout_nyx_j1'), {
      ...payoutDoc(), commissionRate: 0.01,
    }));
  });

  it('K136-08 [MUST-ALLOW] adminClaim can still create payout/fee types', async () => {
    await seedBase();
    await assertSucceeds(setDoc(doc(adminClaim(), 'transactions/payout_nyx_j1'), payoutDoc()));
    await assertSucceeds(setDoc(doc(adminClaim(), 'transactions/fees_emp_j2'), feeDoc()));
  });
});

describe('KAN-136 stopgap: tyxBalance credit capped alongside payout_nyx_', () => {
  it('K136-B1 [MUST-ALLOW] worker credits self with lastCompletedJobId when payout is in the same batch, capped at amount', async () => {
    await seedBase();
    const db = user('worker');
    const batch = writeBatch(db);
    batch.set(doc(db, 'transactions/payout_nyx_j1'), payoutDoc(696));
    batch.update(doc(db, 'users/worker'), {
      tyxBalance: 100 + 696,
      jobsDone: 4,
      totalEarned: 1200 + 696,
      completedGigsCount: 1,
      repeatHireRate: 0.0,
      lastCompletedJobId: 'j1',
    });
    await assertSucceeds(batch.commit());
  });

  it('K136-B2 [CRITICAL] credit above payout amount is denied', async () => {
    await seedBase();
    const db = user('worker');
    const batch = writeBatch(db);
    batch.set(doc(db, 'transactions/payout_nyx_j1'), payoutDoc(696));
    batch.update(doc(db, 'users/worker'), {
      tyxBalance: 100 + 5000,
      jobsDone: 4,
      totalEarned: 1200 + 5000,
      completedGigsCount: 1,
      repeatHireRate: 0.0,
      lastCompletedJobId: 'j1',
    });
    await assertFails(batch.commit());
  });

  it('K136-B3 [CRITICAL] free tyxBalance increase without payout_nyx_ is denied', async () => {
    await seedBase();
    await assertFails(updateDoc(doc(user('worker'), 'users/worker'), { tyxBalance: 99999 }));
  });

  it('K136-B4 [MUST-ALLOW] employer credits worker in the same batch as payout_nyx_', async () => {
    await seedBase();
    const db = user('poster');
    const batch = writeBatch(db);
    batch.set(doc(db, 'transactions/payout_nyx_j1'), payoutDoc(696));
    batch.update(doc(db, 'users/worker'), {
      tyxBalance: 100 + 696,
      jobsDone: 4,
      totalEarned: 1200 + 696,
      completedGigsCount: 1,
      repeatHireRate: 0.0,
      lastCompletedJobId: 'j1',
    });
    await assertSucceeds(batch.commit());
  });

  it('K136-B5 [HIGH] replay credit for the same lastCompletedJobId is denied', async () => {
    await seedBase({
      'users/worker': userProfile('worker', { tyxBalance: 796, lastCompletedJobId: 'j1' }),
      'transactions/payout_nyx_j1': payoutDoc(696),
    });
    await assertFails(updateDoc(doc(user('worker'), 'users/worker'), {
      tyxBalance: 796 + 696,
      jobsDone: 5,
      totalEarned: 1896,
      completedGigsCount: 2,
      repeatHireRate: 0.35,
      lastCompletedJobId: 'j1',
    }));
  });
});

describe('KAN-136 stopgap: platform_fees + holdbacks for completion shape', () => {
  it('K136-P1 [MUST-ALLOW] job party creates platform_fees/{jobId} when payout existsAfter', async () => {
    await seedBase();
    const db = user('worker');
    const batch = writeBatch(db);
    batch.set(doc(db, 'transactions/payout_nyx_j1'), payoutDoc());
    batch.set(doc(db, 'platform_fees/j1'), {
      jobId: 'j1', amount: 104, commissionFee: 24, transactionFee: 56, convenienceFee: 24,
      timestamp: NOW,
    });
    await assertSucceeds(batch.commit());
  });

  it('K136-P2 [MUST-ALLOW] worker creates escrow_holdbacks with nyxianId', async () => {
    await seedBase();
    await assertSucceeds(setDoc(doc(user('worker'), 'escrow_holdbacks/j1'), {
      jobId: 'j1', amount: 80, nyxianId: 'worker', employerId: 'poster', status: 'held', createdAt: NOW, releaseAt: NOW + 1,
    }));
  });
});
