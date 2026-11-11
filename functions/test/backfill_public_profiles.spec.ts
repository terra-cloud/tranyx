import { beforeEach, describe, expect, it } from 'vitest';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { planAndApply, projectPublicProfile } from '../../tool/backfill_public_profiles.mjs';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8189';
initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();

async function clearAll() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-tranyx/databases/(default)/documents`, { method: 'DELETE' });
}

beforeEach(clearAll);

describe('public profile backfill (emulator fixtures only)', () => {
  it('projects the public card and drops private account fields', () => {
    const card = projectPublicProfile('u1', {
      name: 'Ada', email: 'ada@example.com', phone: '0917', walletPublicKey: 'wallet',
      tyxBalance: 50, idVerified: true, rating: 4, isPremium: false,
    });
    expect(card).toEqual({ uid: 'u1', name: 'Ada', rating: 4, isPremium: false });
    expect(card).not.toHaveProperty('email');
    expect(card).not.toHaveProperty('phone');
    expect(card).not.toHaveProperty('walletPublicKey');
    expect(card).not.toHaveProperty('idVerified');
    expect(card).not.toHaveProperty('tyxBalance');
  });

  it('dry-run lists a missing card and does not write it', async () => {
    await db.doc('users/u1').set({ name: 'Ada', email: 'ada@example.com', rating: 4 });
    const result = await planAndApply(db, { apply: false, project: 'demo-tranyx', host: '127.0.0.1:8189' });
    expect(result.dryRun).toBe(true);
    expect(result.profiles.map((row) => row.uid)).toEqual(['u1']);
    expect((await db.doc('public_profiles/u1').get()).exists).toBe(false);
  });

  it('apply writes the card once and a second apply skips it', async () => {
    await db.doc('users/u1').set({ name: 'Ada', email: 'ada@example.com', phone: '0917', rating: 4, isPremium: false });
    await db.doc('users/u2').set({ name: 'Bea' });
    await db.doc('public_profiles/u2').set({ uid: 'u2', name: 'Bea' });
    const first = await planAndApply(db, { apply: true, project: 'demo-tranyx', host: '127.0.0.1:8189' });
    expect(first.dryRun).toBe(false);
    expect(first.wrote).toBe(1);
    const card = (await db.doc('public_profiles/u1').get()).data();
    expect(card).toEqual({ uid: 'u1', name: 'Ada', rating: 4, isPremium: false });
    const second = await planAndApply(db, { apply: true, project: 'demo-tranyx', host: '127.0.0.1:8189' });
    expect(second.wrote).toBe(0);
    expect(second.count).toBe(0);
    expect((await db.doc('public_profiles/u1').get()).data()).toEqual(card);
  });

  it('apply replaces a card that leaked a private field', async () => {
    await db.doc('users/u1').set({ name: 'Ada' });
    await db.doc('public_profiles/u1').set({ uid: 'u1', name: 'Ada', email: 'ada@example.com' });
    const result = await planAndApply(db, { apply: true, project: 'demo-tranyx', host: '127.0.0.1:8189' });
    expect(result.wrote).toBe(1);
    expect((await db.doc('public_profiles/u1').get()).data()).toEqual({ uid: 'u1', name: 'Ada' });
  });
});
