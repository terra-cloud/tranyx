import type { Firestore } from 'firebase-admin/firestore';
import { FieldValue } from 'firebase-admin/firestore';

/** Guest-visible summary. Exact address and coordinates move to private/location. */
export const PUBLIC_ADDRESS_MASK = 'Brgy. *****, ****';

export const LISTING_COLLECTIONS = ['jobs', 'properties', 'rentals'] as const;

export const EXACT_LOCATION_FIELDS = [
  'address', 'landmark', 'location', 'pickupAddress', 'pickupLat', 'pickupLng',
  'destinationAddress', 'destinationLat', 'destinationLng', 'latitude', 'longitude', 'lat', 'lng',
  'nyxianLat', 'nyxianLng', 'currentLocationLat', 'currentLocationLng', 'trackingLat', 'trackingLng',
  'routeHistory',
] as const;

export type ListingLocationHit = { collection: string; id: string; fields: string[] };

export function assertEmulatorApply(apply: boolean) {
  if (apply && !process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('REFUSING_LIVE_MIGRATION: set FIRESTORE_EMULATOR_HOST. This tool does not write live projects.');
  }
}

export async function planListingLocationMigration(db: Firestore): Promise<ListingLocationHit[]> {
  const hits: ListingLocationHit[] = [];
  for (const collection of LISTING_COLLECTIONS) {
    const snap = await db.collection(collection).get();
    for (const doc of snap.docs) {
      const data = doc.data();
      const fields = EXACT_LOCATION_FIELDS.filter((field) => data[field] !== undefined);
      if (fields.length) hits.push({ collection, id: doc.id, fields: [...fields] });
    }
  }
  hits.sort((a, b) => `${a.collection}/${a.id}`.localeCompare(`${b.collection}/${b.id}`));
  return hits;
}

export async function applyListingLocationMigration(db: Firestore, opts: { apply: boolean }) {
  assertEmulatorApply(opts.apply);
  const listings = await planListingLocationMigration(db);
  const audit = {
    at: Date.now(),
    apply: opts.apply,
    emulator: process.env.FIRESTORE_EMULATOR_HOST ?? null,
    count: listings.length,
    listings,
  };
  if (!opts.apply) return { dryRun: true as const, ...audit };
  for (const hit of listings) {
    const ref = db.doc(`${hit.collection}/${hit.id}`);
    const data = (await ref.get()).data() ?? {};
    const location: Record<string, unknown> = {};
    const patch: Record<string, unknown> = { addressPublic: PUBLIC_ADDRESS_MASK };
    for (const field of hit.fields) {
      location[field] = data[field];
      patch[field] = FieldValue.delete();
    }
    await db.doc(`${hit.collection}/${hit.id}/private/location`).set(location, { merge: true });
    await ref.update(patch);
  }
  await db.collection('purge_audit').doc(`listing_locations_${audit.at}`).set(audit);
  return { dryRun: false as const, ...audit };
}
