import { FieldValue, type Firestore } from 'firebase-admin/firestore';

/** Public job fields that used to hold the completion secret. */
export const JOB_CODE_FIELDS = ['completionCode', 'verificationCode'] as const;

export type JobCodeHit = { id: string; fields: string[]; status: unknown };

/**
 * Refuses an applying run unless FIRESTORE_EMULATOR_HOST is set.
 * Dry-run planning is allowed without it so a caller can see the guard fail closed.
 */
export function assertEmulatorApply(apply: boolean) {
  if (apply && !process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('REFUSING_LIVE_PURGE: set FIRESTORE_EMULATOR_HOST. This tool does not write live projects.');
  }
}

export async function planJobCodePurge(db: Firestore): Promise<JobCodeHit[]> {
  const snap = await db.collection('jobs').get();
  const hits: JobCodeHit[] = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    const fields = JOB_CODE_FIELDS.filter((field) => data[field] !== undefined);
    if (fields.length) hits.push({ id: doc.id, fields: [...fields], status: data.status ?? null });
  }
  hits.sort((a, b) => a.id.localeCompare(b.id));
  return hits;
}

export async function applyJobCodePurge(db: Firestore, opts: { apply: boolean }) {
  assertEmulatorApply(opts.apply);
  const jobs = await planJobCodePurge(db);
  const audit = {
    at: Date.now(),
    apply: opts.apply,
    emulator: process.env.FIRESTORE_EMULATOR_HOST ?? null,
    count: jobs.length,
    jobs,
  };
  if (!opts.apply) return { dryRun: true as const, ...audit };
  for (const hit of jobs) {
    const patch: Record<string, FirebaseFirestore.FieldValue> = {};
    for (const field of hit.fields) patch[field] = FieldValue.delete();
    await db.doc(`jobs/${hit.id}`).update(patch);
  }
  await db.collection('purge_audit').doc(`job_codes_${audit.at}`).set(audit);
  return { dryRun: false as const, ...audit };
}
