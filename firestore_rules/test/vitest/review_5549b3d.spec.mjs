// Added Oct 22 during review of Saga's 5549b3d: walletLinks holes + per-action jobs checks after the update-rule split.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDocs, setDoc, updateDoc } from 'firebase/firestore';
import { knownHole, setupEnv, seed, user, guest, userProfile, job, withdrawal } from './helpers.mjs';

setupEnv();
const NOW = 1761123600000;
const ADDR = '9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin';

describe('WL: walletLinks (wallet address -> uid map)', () => {
  // Single-doc guest read is MON-T3 (money.spec.mjs). These add the enumeration and hijack cases.
  knownHole('KNOWN-HOLE WL-01 [MEDIUM] guest cannot read walletLinks/{address} or enumerate the collection (10_...:94 / walletLinks read: if true)', async () => {
    await seed({ [`walletLinks/${ADDR}`]: { uid: 'victim', linkedAt: NOW } });
    await assertFails(getDocs(collection(guest(), 'walletLinks')));
  });
  knownHole('KNOWN-HOLE WL-02 [CRITICAL] signed-in user cannot overwrite another user\'s walletLinks doc (re-point victim wallet to self; 10_...:95)', async () => {
    await seed({ 'users/u2': userProfile('u2'), [`walletLinks/${ADDR}`]: { uid: 'victim', linkedAt: NOW } });
    await assertFails(setDoc(doc(user('u2'), `walletLinks/${ADDR}`), { uid: 'u2', linkedAt: NOW }));
  });
  it('WL-03 [MUST-ALLOW] owner links a new wallet address to self', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    await assertSucceeds(setDoc(doc(user('u1'), 'walletLinks/NewAddr1111111111111111111111111111111111111'), { uid: 'u1', linkedAt: NOW }));
  });
});

describe('JOB: each action after the 30_ update split; mixed updates denied', () => {
  const hired = (extra = {}) => job('poster', { status: 'Awaiting Acknowledgment', acceptedApplicantId: 'worker', ...extra });
  const prep = (j, extra = {}) => seed({ 'users/poster': userProfile('poster'), 'users/worker': userProfile('worker'), 'users/a2': userProfile('a2'), 'jobs/j1': j, ...extra });

  it('JOB-01 [MUST-ALLOW] applicant applies (count/uids/photos)', async () => {
    await prep(job('poster'));
    await assertSucceeds(updateDoc(doc(user('a2'), 'jobs/j1'), { applicantCount: 2, applicantUids: ['worker', 'a2'], recentApplicantPhotos: [''] }));
  });
  it('JOB-02 [MUST-ALLOW] poster accepts applicant (44527aa jobPatch)', async () => {
    await prep(job('poster', { status: 'Reviewing' }));
    await assertSucceeds(updateDoc(doc(user('poster'), 'jobs/j1'), { status: 'Awaiting Acknowledgment', acceptedApplicantId: 'worker', acceptedApplicantName: 'Juan', hiredAt: NOW, acknowledgmentDeadline: NOW + 1800000, acknowledgmentSlaMinutes: 30, acknowledgmentCategory: 'homeServices', acknowledgmentStatus: 'pending', updatedAt: NOW }));
  });
  it('JOB-03 [MUST-ALLOW] worker completes with receipt', async () => {
    await prep(hired({ status: 'In Progress' }));
    await assertSucceeds(updateDoc(doc(user('worker'), 'jobs/j1'), { status: 'Completed', receiptUrl: 'https://example.invalid/r.webp', updatedAt: NOW }));
  });
  it('JOB-04 [MUST-ALLOW] poster cancels an Open job, then deletes it', async () => {
    await prep(job('poster'));
    await assertSucceeds(updateDoc(doc(user('poster'), 'jobs/j1'), { status: 'Cancelled', updatedAt: NOW }));
    await assertSucceeds(deleteDoc(doc(user('poster'), 'jobs/j1')));
  });
  it('JOB-05 [MUST-ALLOW] poster edits an Open listing', async () => {
    await prep(job('poster'));
    await assertSucceeds(updateDoc(doc(user('poster'), 'jobs/j1'), { title: 'Fix kitchen sink + faucet', description: 'Also replace faucet', pricingValue: 950, imageUrls: ['https://example.invalid/s.webp'], updatedAt: NOW }));
  });
  it('JOB-06 [HIGH] mixed: worker completes AND raises pricingValue in one write -> denied', async () => {
    await prep(hired({ status: 'In Progress' }));
    await assertFails(updateDoc(doc(user('worker'), 'jobs/j1'), { status: 'Completed', pricingValue: 99999 }));
  });
  it('JOB-07 [HIGH] mixed: poster re-opens unacknowledged job AND reprices it -> denied', async () => {
    await prep(hired());
    await assertFails(updateDoc(doc(user('poster'), 'jobs/j1'), { status: 'Open', acceptedApplicantId: null, pricingValue: 10 }));
  });
  it('JOB-08 [HIGH] mixed: applicant applies AND edits title -> denied', async () => {
    await prep(job('poster'));
    await assertFails(updateDoc(doc(user('a2'), 'jobs/j1'), { applicantCount: 2, applicantUids: ['worker', 'a2'], title: 'pwned' }));
  });
  it('JOB-09 [HIGH] mixed: poster rates a completed job AND rewrites completionCode -> denied', async () => {
    await prep(hired({ status: 'Completed' }));
    await assertFails(updateDoc(doc(user('poster'), 'jobs/j1'), { employerRated: true, completionCode: '000000' }));
  });
  it('JOB-10 [MUST-ALLOW] today\'s admin panel identity (users doc isAdmin, no claim) can still cancel a job (phase-2 dependency)', async () => {
    await prep(hired({ status: 'In Progress' }), { 'users/staff1': userProfile('staff1', { isAdmin: true, role: 'admin' }) });
    await assertSucceeds(updateDoc(doc(user('staff1'), 'jobs/j1'), { status: 'Cancelled', adminNote: 'refunded' }));
  });
});

describe('RES: residuals after 5549b3d', () => {
  it('WR-06 [HIGH] owner cannot flip balanceDeducted on own REJECTED/refunded request (isOwnerWithdrawalUpdate allowlist)', async () => {
    await seed({ 'withdrawal_requests/wr1': withdrawal('u1', { status: 'REJECTED', balanceDeducted: false, refundedAt: NOW }) });
    await assertFails(updateDoc(doc(user('u1'), 'withdrawal_requests/wr1'), { balanceDeducted: true }));
  });
  it('MON-T6 [MEDIUM] signed-in user cannot list every user\'s transactions (list is owner-only)', async () => {
    await seed({ 'transactions/tx1': { uid: 'victim', type: 'deposit', amount: 1500, status: 'Successful' } });
    await assertFails(getDocs(collection(user('u2'), 'transactions')));
  });
});
