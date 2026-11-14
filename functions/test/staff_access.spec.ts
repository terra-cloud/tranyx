import { beforeEach, describe, expect, it } from 'vitest';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/https';
import {
  claimsForAssignedRole, parseSyncStaffBody, syncStaffAccess, type StaffAuth, type StaffAuthUser,
} from '../src/staff_access';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8189';
if (!getApps().length) initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();

class MemoryAuth implements StaffAuth {
  users = new Map<string, StaffAuthUser & { email: string; customClaims: Record<string, unknown> }>();
  created: { email: string; password?: string }[] = [];
  async getUser(uid: string) {
    const user = [...this.users.values()].find((row) => row.uid === uid);
    if (!user) {
      const error = new Error('missing') as Error & { code: string };
      error.code = 'auth/user-not-found';
      throw error;
    }
    return user;
  }
  async getUserByEmail(email: string) {
    const user = [...this.users.values()].find((row) => row.email === email);
    if (!user) {
      const error = new Error('missing') as Error & { code: string };
      error.code = 'auth/user-not-found';
      throw error;
    }
    return user;
  }
  async createUser(props: { email: string; password?: string }) {
    this.created.push(props);
    const user = { uid: `uid_${this.users.size + 1}`, email: props.email, customClaims: {} };
    this.users.set(user.uid, user);
    return user;
  }
  async setCustomUserClaims(uid: string, claims: Record<string, unknown>) {
    const user = await this.getUser(uid);
    user.customClaims = { ...claims };
  }
}

const adminToken = { admin: true, email: 'admin@tranyx.app', role: 'admin' };

async function clearAudit() {
  const snap = await db.collection('staff_audit_log').get();
  await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
}

describe('syncStaffAccess', () => {
  let auth: MemoryAuth;
  beforeEach(async () => {
    auth = new MemoryAuth();
    auth.users.set('caller', { uid: 'caller', email: 'admin@tranyx.app', customClaims: { admin: true, role: 'admin' } });
    await clearAudit();
  });

  it('rejects a signed-out caller, a staff caller, and a role sent in the body', async () => {
    await expect(syncStaffAccess({ callerUid: undefined, callerToken: adminToken, data: { staffEmail: 'a@b.co', role: 'staff' }, auth, db })).rejects.toThrow(/Sign in/);
    await expect(syncStaffAccess({
      callerUid: 'staffer', callerToken: { role: 'staff', email: 's@tranyx.app' }, data: { staffEmail: 'a@b.co', role: 'admin' }, auth, db,
    })).rejects.toMatchObject({ code: 'permission-denied' });
    await expect(syncStaffAccess({
      callerUid: 'caller', callerToken: { role: 'agent', email: 'a@tranyx.app' }, data: { staffEmail: 'a@b.co', role: 'admin' }, auth, db,
    })).rejects.toMatchObject({ code: 'permission-denied' });
  });

  it('rejects extra fields and roles that are not admin, staff, or agent', () => {
    expect(() => parseSyncStaffBody({ staffEmail: 'a@b.co', role: 'staff', password: 'secret' })).toThrow(HttpsError);
    expect(() => parseSyncStaffBody({ staffEmail: 'a@b.co', role: 'staff', claims: { admin: true } })).toThrow(HttpsError);
    expect(() => parseSyncStaffBody({ staffEmail: 'a@b.co', role: 'superadmin' })).toThrow(/admin, staff, or agent/);
  });

  it('refuses a caller syncing their own email', async () => {
    const error = await syncStaffAccess({
      callerUid: 'caller', callerToken: adminToken, data: { staffEmail: 'Admin@Tranyx.app', role: 'staff' }, auth, db,
    }).catch((e) => e);
    expect(error).toMatchObject({ code: 'permission-denied' });
    expect(error.details).toMatchObject({ code: 'SELF_ROLE' });
    expect(auth.created).toEqual([]);
  });

  it('creates a passwordless user and replaces claims for admin, staff, and agent', async () => {
    const created = await syncStaffAccess({
      callerUid: 'caller', callerToken: adminToken, data: { staffEmail: 'New.Agent@Tranyx.app', role: 'agent' }, auth, db, now: 10,
    });
    expect(created).toEqual({ uid: 'uid_2', email: 'new.agent@tranyx.app', role: 'agent', created: true });
    expect(auth.created).toEqual([{ email: 'new.agent@tranyx.app' }]);
    expect(JSON.stringify(created)).not.toContain('password');
    expect((await auth.getUser('uid_2')).customClaims).toEqual(claimsForAssignedRole('agent'));

    auth.users.get('uid_2')!.customClaims = { admin: true, role: 'admin', leftover: true };
    const updated = await syncStaffAccess({
      callerUid: 'caller', callerToken: adminToken, data: { staffEmail: 'new.agent@tranyx.app', role: 'staff' }, auth, db, now: 11,
    });
    expect(updated.created).toBe(false);
    expect((await auth.getUser('uid_2')).customClaims).toEqual({ admin: false, role: 'staff' });

    await syncStaffAccess({
      callerUid: 'caller', callerToken: { role: 'super_admin', email: 'root@tranyx.app' }, data: { staffEmail: 'boss@tranyx.app', role: 'admin' }, auth, db, now: 12,
    });
    const boss = [...auth.users.values()].find((row) => row.email === 'boss@tranyx.app');
    expect(boss?.customClaims).toEqual({ admin: true, role: 'admin' });

    const audit = await db.collection('staff_audit_log').get();
    expect(audit.size).toBe(3);
    expect(audit.docs.map((doc) => doc.get('action'))).toEqual(['syncStaffAccess', 'syncStaffAccess', 'syncStaffAccess']);
    expect(audit.docs.some((doc) => JSON.stringify(doc.data()).includes('password'))).toBe(false);
  });
});
