import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { applyJobCodePurge, planJobCodePurge } from '../src/purge_job_codes';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8189';
initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();

async function clearAll() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-tranyx/databases/(default)/documents`, { method: 'DELETE' });
}

beforeEach(async () => {
  await clearAll();
  await db.doc('jobs/legacy').set({ title: 'Old gig', status: 'In Progress', completionCode: '482913', verificationCode: '482913', address: '12 Mabini St' });
  await db.doc('jobs/clean').set({ title: 'New gig', status: 'Open', address: 'public listing' });
});
afterEach(async () => { await clearAll(); });

describe('job completion-code purge (emulator fixtures only)', () => {
  it('dry-run lists legacy codes and does not delete them', async () => {
    const plan = await planJobCodePurge(db);
    expect(plan).toEqual([{ id: 'legacy', fields: ['completionCode', 'verificationCode'], status: 'In Progress' }]);
    const result = await applyJobCodePurge(db, { apply: false });
    expect(result.dryRun).toBe(true);
    expect(result.count).toBe(1);
    expect((await db.doc('jobs/legacy').get()).get('completionCode')).toBe('482913');
    expect((await db.doc('jobs/clean').get()).get('title')).toBe('New gig');
    expect((await db.collection('purge_audit').get()).size).toBe(0);
  });

  it('apply deletes only the secret fields and writes an audit doc', async () => {
    const result = await applyJobCodePurge(db, { apply: true });
    expect(result.dryRun).toBe(false);
    expect(result.count).toBe(1);
    const legacy = (await db.doc('jobs/legacy').get()).data()!;
    expect(legacy.completionCode).toBeUndefined();
    expect(legacy.verificationCode).toBeUndefined();
    expect(legacy.title).toBe('Old gig');
    expect(legacy.address).toBe('12 Mabini St');
    expect((await db.doc('jobs/clean').get()).get('title')).toBe('New gig');
    const audits = await db.collection('purge_audit').get();
    expect(audits.size).toBe(1);
    expect(audits.docs[0].get('jobs')[0].id).toBe('legacy');
  });

  it('apply refuses when FIRESTORE_EMULATOR_HOST is unset', async () => {
    const saved = process.env.FIRESTORE_EMULATOR_HOST;
    delete process.env.FIRESTORE_EMULATOR_HOST;
    try {
      await expect(applyJobCodePurge(db, { apply: true })).rejects.toThrow(/REFUSING_LIVE_PURGE/);
    } finally {
      process.env.FIRESTORE_EMULATOR_HOST = saved;
    }
    expect((await db.doc('jobs/legacy').get()).get('completionCode')).toBe('482913');
  });
});
