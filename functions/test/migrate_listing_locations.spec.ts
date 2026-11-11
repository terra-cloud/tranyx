import { beforeEach, describe, expect, it } from 'vitest';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { applyListingLocationMigration, planListingLocationMigration, PUBLIC_ADDRESS_MASK } from '../src/migrate_listing_locations';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8189';
initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();

async function clearAll() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-tranyx/databases/(default)/documents`, { method: 'DELETE' });
}

beforeEach(async () => {
  await clearAll();
  await db.doc('jobs/legacy').set({ title: 'Old', address: '12 Mabini St', pickupLat: 14.5, pickupLng: 121.0, status: 'Open' });
  await db.doc('properties/legacy').set({ title: 'Flat', address: 'Unit 12B', latitude: 14.5, longitude: 121.0 });
  await db.doc('rentals/clean').set({ title: 'Vios', addressPublic: PUBLIC_ADDRESS_MASK });
});

describe('listing location migration (emulator fixtures only)', () => {
  it('dry-run lists exact public fields and does not move them', async () => {
    const plan = await planListingLocationMigration(db);
    expect(plan.map((hit) => hit.id).sort()).toEqual(['legacy', 'legacy']);
    const result = await applyListingLocationMigration(db, { apply: false });
    expect(result.dryRun).toBe(true);
    expect((await db.doc('jobs/legacy').get()).get('address')).toBe('12 Mabini St');
    expect((await db.doc('jobs/legacy/private/location').get()).exists).toBe(false);
  });

  it('apply moves exact fields to private/location and leaves the public mask', async () => {
    const result = await applyListingLocationMigration(db, { apply: true });
    expect(result.dryRun).toBe(false);
    const job = (await db.doc('jobs/legacy').get()).data()!;
    expect(job.address).toBeUndefined();
    expect(job.pickupLat).toBeUndefined();
    expect(job.addressPublic).toBe(PUBLIC_ADDRESS_MASK);
    expect(job.title).toBe('Old');
    expect((await db.doc('jobs/legacy/private/location').get()).data()).toMatchObject({ address: '12 Mabini St', pickupLat: 14.5 });
    const property = (await db.doc('properties/legacy').get()).data()!;
    expect(property.latitude).toBeUndefined();
    expect((await db.doc('properties/legacy/private/location').get()).get('address')).toBe('Unit 12B');
    expect((await db.doc('rentals/clean').get()).get('title')).toBe('Vios');
  });

  it('apply refuses when FIRESTORE_EMULATOR_HOST is unset', async () => {
    const saved = process.env.FIRESTORE_EMULATOR_HOST;
    delete process.env.FIRESTORE_EMULATOR_HOST;
    try {
      await expect(applyListingLocationMigration(db, { apply: true })).rejects.toThrow(/REFUSING_LIVE_MIGRATION/);
    } finally {
      process.env.FIRESTORE_EMULATOR_HOST = saved;
    }
    expect((await db.doc('jobs/legacy').get()).get('address')).toBe('12 Mabini St');
  });
});
