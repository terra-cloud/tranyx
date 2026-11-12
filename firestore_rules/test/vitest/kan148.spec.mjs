// KAN-148: the apps read settings/platform_fees before every gig/booking total; with no rule the read
// was denied and the "Permission denied" banner showed on every job post.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, deleteDoc } from 'firebase/firestore';
import { setupEnv, seed, user, guest, adminClaim, userProfile } from './helpers.mjs';

setupEnv();

describe('KAN-148: settings/platform_fees', () => {
  it('[MUST-ALLOW] a signed-in user reads settings/platform_fees (a missing doc too)', async () => {
    await seed({ 'users/u1': userProfile('u1'), 'settings/platform_fees': { transactionFeeRate: 0.02 } });
    await assertSucceeds(getDoc(doc(user('u1'), 'settings/platform_fees')));
    await seed({ 'users/u1': userProfile('u1') });
    await assertSucceeds(getDoc(doc(user('u1'), 'settings/platform_fees')));
  });
  it('a guest cannot read it; no other settings doc is readable', async () => {
    await seed({ 'users/u1': userProfile('u1'), 'settings/platform_fees': { transactionFeeRate: 0.02 }, 'settings/secret': { v: 1 } });
    await assertFails(getDoc(doc(guest(), 'settings/platform_fees')));
    await assertFails(getDoc(doc(user('u1'), 'settings/secret')));
  });
  it('[CRITICAL] clients cannot write the fee rates (only admin/staff)', async () => {
    await seed({ 'users/u1': userProfile('u1'), 'settings/platform_fees': { transactionFeeRate: 0.02 } });
    await assertFails(setDoc(doc(user('u1'), 'settings/platform_fees'), { transactionFeeRate: 0 }));
    await assertFails(deleteDoc(doc(user('u1'), 'settings/platform_fees')));
    await assertSucceeds(setDoc(doc(adminClaim(), 'settings/platform_fees'), { transactionFeeRate: 0.03 }));
  });
});
