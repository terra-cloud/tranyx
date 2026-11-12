import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { MoneyDeps } from '../src/money';
import { awardPoints } from '../src/points';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8189';
initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();
let clock = Date.UTC(2026, 10, 6, 4, 0, 0);
const deps = (): MoneyDeps => ({ db, now: () => clock });
const as = (uid: string, token: Record<string, unknown> = {}) => ({ uid, token });
const err = async (p: Promise<unknown>) => p.then(() => null, (e: any) => e);
const points = async (uid: string) => (await db.doc(`users/${uid}`).get()).get('terraPoints') as number;

async function clearAll() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-tranyx/databases/(default)/documents`, { method: 'DELETE' });
}

beforeAll(async () => { await clearAll(); });
beforeEach(async () => {
  await clearAll();
  await db.doc('users/u1').set({ name: 'U', terraPoints: 0, tyxBalance: 0, skills: [], headline: '' });
});

describe('awardPoints', () => {
  it('awards the catalog amount once and ignores a client amount', async () => {
    expect((await err(awardPoints(deps(), as('u1'), { questId: 'register_account', points: 99999 })) )?.code).toBe('invalid-argument');
    expect(await points('u1')).toBe(0);
    const r = await awardPoints(deps(), as('u1'), { questId: 'register_account' });
    expect(r).toMatchObject({ awarded: true, points: 500, terraPoints: 500 });
    expect(await points('u1')).toBe(500);
    const again = await awardPoints(deps(), as('u1'), { questId: 'register_account' });
    expect(again).toMatchObject({ awarded: false, alreadyAwarded: true, terraPoints: 500 });
    expect(await points('u1')).toBe(500);
    expect((await db.collection('points_awards').get()).size).toBe(1);
    expect((await db.doc('points_history/u1_register_account').get()).get('points')).toBe(500);
  });

  it('two concurrent calls award once', async () => {
    const [a, b] = await Promise.all([
      awardPoints(deps(), as('u1'), { questId: 'register_account' }),
      awardPoints(deps(), as('u1'), { questId: 'register_account' }),
    ]);
    expect([a.awarded, b.awarded].filter(Boolean).length).toBe(1);
    expect(await points('u1')).toBe(500);
  });

  it('does not grant from profile flags, another user, or a replayed completion', async () => {
    await db.doc('users/u1').set({ idVerified: true, phoneVerified: true, emailVerified: true, walletPublicKey: 'NotAVerifiedWallet', terraPoints: 0 }, { merge: true });
    expect((await awardPoints(deps(), as('u1'), { questId: 'complete_profile_trust' })).awarded).toBe(false);
    expect((await awardPoints(deps(), as('u1'), { questId: 'connect_solana_wallet' })).awarded).toBe(false);
    expect((await awardPoints(deps(), as('u1', { email_verified: true }), { questId: 'verify_account' })).awarded).toBe(false);
    expect((await awardPoints(deps(), as('u1', { email_verified: true, phone_number: '+63917' }), { questId: 'verify_account' })).awarded).toBe(true);
    expect(await points('u1')).toBe(500);

    await db.doc('jobs/j1').set({ creatorId: 'emp', acceptedApplicantId: 'u1', status: 'Completed' });
    await db.doc('users/emp').set({ terraPoints: 0, name: 'E' });
    const cross = await awardPoints(deps(), as('u1'), { questId: 'employer_complete_transaction', eventId: 'j1' });
    expect(cross.awarded).toBe(false);
    expect(await points('emp')).toBe(0);
    const own = await awardPoints(deps(), as('u1'), { questId: 'jobseeker_complete_transaction', eventId: 'j1' });
    expect(own).toMatchObject({ awarded: true, points: 500 });
    const replay = await awardPoints(deps(), as('u1'), { questId: 'jobseeker_complete_transaction', eventId: 'j1' });
    expect(replay.alreadyAwarded).toBe(true);
    expect(await points('u1')).toBe(1000);
    expect((await err(awardPoints(deps(), undefined, { questId: 'register_account' })))?.code).toBe('unauthenticated');
  });

  it('skills text earns the catalog 100, and a second job completion earns another 500', async () => {
    await db.doc('users/u1').set({ headline: 'Plumber', terraPoints: 0 }, { merge: true });
    expect((await awardPoints(deps(), as('u1'), { questId: 'add_skills_bio' })).points).toBe(100);
    await db.doc('jobs/j1').set({ creatorId: 'u1', status: 'Completed' });
    await db.doc('jobs/j2').set({ creatorId: 'u1', status: 'Completed' });
    expect((await awardPoints(deps(), as('u1'), { questId: 'employer_complete_transaction', eventId: 'j1' })).awarded).toBe(true);
    expect((await awardPoints(deps(), as('u1'), { questId: 'employer_complete_transaction', eventId: 'j2' })).awarded).toBe(true);
    expect(await points('u1')).toBe(1100);
  });
});
