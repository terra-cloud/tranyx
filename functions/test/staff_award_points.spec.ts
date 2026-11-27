import { beforeEach, describe, expect, it } from 'vitest';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { CUSTOM_POINTS_CAP, callerMayAwardPoints, staffAwardPoints } from '../src/points';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8189';
if (!getApps().length) initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();

const err = async (p: Promise<unknown>) => p.then(() => null, (e: { code?: string }) => e);
const pointsOf = async (uid: string) => (await db.doc(`users/${uid}`).get()).get('terraPoints');
const rewardsOf = async (uid: string) => (await db.doc(`users/${uid}`).get()).get('earnedRewards') as string[];

async function clearAll() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-tranyx/databases/(default)/documents`, { method: 'DELETE' });
}

beforeEach(async () => {
  await clearAll();
  await db.doc('users/member').set({ name: 'Member', terraPoints: 40, earnedRewards: [] });
});

describe('callerMayAwardPoints', () => {
  it('accepts admin and superadmin claims and rejects staff, agent, and empty tokens', () => {
    expect(callerMayAwardPoints({ admin: true })).toBe(true);
    expect(callerMayAwardPoints({ superadmin: true })).toBe(true);
    expect(callerMayAwardPoints({ role: 'admin' })).toBe(true);
    expect(callerMayAwardPoints({ role: 'superadmin' })).toBe(true);
    expect(callerMayAwardPoints({ role: 'super_admin' })).toBe(true);
    expect(callerMayAwardPoints({ role: 'SuperAdmin' })).toBe(true);
    expect(callerMayAwardPoints({ role: 'staff', admin: false })).toBe(false);
    expect(callerMayAwardPoints({ role: 'agent' })).toBe(false);
    expect(callerMayAwardPoints({ p2pAgent: true })).toBe(false);
    expect(callerMayAwardPoints({})).toBe(false);
    expect(callerMayAwardPoints(undefined)).toBe(false);
  });
});

describe('staffAwardPoints', () => {
  const admin = { callerUid: 'admin1', callerToken: { admin: true, role: 'admin' }, db, now: 1_700_000_000_000 };

  it('awards the catalog amount, records awardedBy, and rejects a client amount', async () => {
    const denied = await err(staffAwardPoints({ ...admin, data: { targetUid: 'member', questId: 'register_account', points: 99999 } }));
    expect(denied?.code).toBe('invalid-argument');
    expect(await pointsOf('member')).toBe(40);

    const awarded = await staffAwardPoints({ ...admin, data: { targetUid: 'member', questId: 'register_account' } });
    expect(awarded).toMatchObject({
      targetUid: 'member', questId: 'register_account', points: 500, terraPoints: 540,
      title: 'Register Account', category: 'Onboarding',
    });
    expect(await pointsOf('member')).toBe(540);
    expect(await rewardsOf('member')).toEqual(['register_account']);
    const history = await db.doc(`points_history/${awarded.historyId}`).get();
    expect(history.get('points')).toBe(500);
    expect(history.get('awardedBy')).toBe('admin1');
    expect(history.get('createdAt')).toBe(1_700_000_000_000);
    expect(history.get('uid')).toBe('member');
    expect(history.get('title')).toBe('Register Account');

    const again = await staffAwardPoints({ ...admin, callerToken: { role: 'super_admin' }, data: { targetUid: 'member', questId: 'add_skills_bio' } });
    expect(again.points).toBe(100);
    expect(await pointsOf('member')).toBe(640);
    expect(await rewardsOf('member')).toEqual(['register_account', 'add_skills_bio']);
  });

  it('awards a capped custom amount only with a reason', async () => {
    expect(CUSTOM_POINTS_CAP).toBe(1000);
    const missing = await err(staffAwardPoints({ ...admin, data: { targetUid: 'member', questId: 'custom_1', points: 25 } }));
    expect(missing?.code).toBe('invalid-argument');
    const over = await err(staffAwardPoints({
      ...admin, callerToken: { superadmin: true }, data: { targetUid: 'member', questId: 'custom_1', points: 1001, reason: 'Bonus' },
    }));
    expect(over?.code).toBe('invalid-argument');
    const fraction = await err(staffAwardPoints({
      ...admin, data: { targetUid: 'member', questId: 'custom_1', points: 1.5, reason: 'Bonus' },
    }));
    expect(fraction?.code).toBe('invalid-argument');
    const zero = await err(staffAwardPoints({
      ...admin, data: { targetUid: 'member', questId: 'custom_1', points: 0, reason: 'Bonus' },
    }));
    expect(zero?.code).toBe('invalid-argument');
    expect(await pointsOf('member')).toBe(40);

    const awarded = await staffAwardPoints({
      ...admin,
      callerToken: { role: 'superadmin' },
      data: { targetUid: 'member', questId: 'custom_173000', points: 1000, reason: '  Community bonus  ' },
    });
    expect(awarded).toMatchObject({ points: 1000, terraPoints: 1040, title: 'Community bonus', category: 'Custom' });
    expect(await pointsOf('member')).toBe(1040);
    expect(await rewardsOf('member')).toEqual(['custom_173000']);
    const history = await db.doc(`points_history/${awarded.historyId}`).get();
    expect(history.get('reason')).toBe('Community bonus');
    expect(history.get('awardedBy')).toBe('admin1');
    expect(history.get('points')).toBe(1000);
  });

  it('rejects unsigned callers, non-admins, unknown quests, and unknown users without writing history', async () => {
    expect((await err(staffAwardPoints({ ...admin, callerUid: undefined, data: { targetUid: 'member', questId: 'register_account' } })))?.code).toBe('unauthenticated');
    expect((await err(staffAwardPoints({ ...admin, callerToken: { role: 'staff' }, data: { targetUid: 'member', questId: 'register_account' } })))?.code).toBe('permission-denied');
    expect((await err(staffAwardPoints({ ...admin, callerToken: { role: 'agent' }, data: { targetUid: 'member', questId: 'register_account' } })))?.code).toBe('permission-denied');
    expect((await err(staffAwardPoints({ ...admin, callerToken: {}, data: { targetUid: 'member', questId: 'register_account' } })))?.code).toBe('permission-denied');
    expect((await err(staffAwardPoints({ ...admin, data: { targetUid: 'member', questId: 'not_a_quest' } })))?.code).toBe('invalid-argument');
    expect((await err(staffAwardPoints({ ...admin, data: { targetUid: 'missing', questId: 'register_account' } })))?.code).toBe('not-found');
    expect(await pointsOf('member')).toBe(40);
    expect((await db.collection('points_history').get()).size).toBe(0);
    expect((await db.doc('users/missing').get()).exists).toBe(false);
  });
});
