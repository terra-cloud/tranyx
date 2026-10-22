// Seed the LOCAL emulators (project demo-tranyx) with test-only users.
// Start emulators first (tool/emulators.sh), then: npm run seed --prefix firestore_rules/test
// All emails/passwords below are fake and TEST-ONLY. Never reuse them anywhere real.
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';

const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ID = 'demo-tranyx';
const PASSWORD = 'test-only-password';

// guest: intentionally no account (tests use an unauthenticated context).
const USERS = [
  { uid: 'owner', email: 'owner@example.test' },
  { uid: 'staff', email: 'staff@example.test', claims: { role: 'staff' } },
  { uid: 'admin', email: 'admin@example.test', claims: { admin: true } },
  // No claims. Privilege comes only from self-set profile fields and an unverified staff-domain email.
  {
    uid: 'attacker',
    email: 'attacker@tranyx.com',
    emailVerified: false,
    profile: { isAdmin: true, isP2pAgent: true, role: 'admin' },
  },
];

async function main() {
  initializeApp({ projectId: PROJECT_ID });
  const auth = getAuth();
  const db = getFirestore();

  for (const u of USERS) {
    await auth.deleteUser(u.uid).catch((e) => {
      if (e.code !== 'auth/user-not-found') throw e;
    });
    await auth.createUser({
      uid: u.uid,
      email: u.email,
      password: PASSWORD,
      emailVerified: u.emailVerified ?? true,
    });
    if (u.claims) await auth.setCustomUserClaims(u.uid, u.claims);
    await db.doc(`users/${u.uid}`).set({ email: u.email, ...(u.profile ?? {}) });
    console.log(`seeded ${u.uid} <${u.email}>${u.claims ? ' claims=' + JSON.stringify(u.claims) : ''}`);
  }
  await db.doc('jobs/seed-job').set({ title: 'Seed job', status: 'Open', creatorId: 'owner' });
  console.log('seeded jobs/seed-job');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
