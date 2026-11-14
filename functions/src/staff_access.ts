import { HttpsError } from 'firebase-functions/https';
import type { Firestore } from 'firebase-admin/firestore';

/** Roles an admin may assign on this project. Portal-only names are mapped before the call. */
export const ASSIGNABLE_ROLES = ['admin', 'staff', 'agent'] as const;
export type AssignableRole = (typeof ASSIGNABLE_ROLES)[number];

const CALLER_ADMIN_ROLES = new Set(['admin', 'superadmin', 'super_admin']);

export interface StaffAuthUser {
  uid: string;
  email?: string;
  customClaims?: Record<string, unknown>;
}

export interface StaffAuth {
  getUser(uid: string): Promise<StaffAuthUser>;
  getUserByEmail(email: string): Promise<StaffAuthUser>;
  createUser(props: { email: string }): Promise<StaffAuthUser>;
  setCustomUserClaims(uid: string, claims: Record<string, unknown>): Promise<void>;
}

/** Caller authority comes only from this project's ID token. */
export function callerMaySyncStaff(token: Record<string, unknown> | undefined): boolean {
  if (!token) return false;
  if (token.admin === true) return true;
  const role = typeof token.role === 'string' ? token.role.trim().toLowerCase() : '';
  return CALLER_ADMIN_ROLES.has(role);
}

export function claimsForAssignedRole(role: AssignableRole): { admin: boolean; role: AssignableRole } {
  if (role === 'admin') return { admin: true, role: 'admin' };
  if (role === 'staff') return { admin: false, role: 'staff' };
  return { admin: false, role: 'agent' };
}

/** Body is exactly { staffEmail, role }. A password or a claims map is rejected. */
export function parseSyncStaffBody(data: unknown): { staffEmail: string; role: AssignableRole } {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new HttpsError('invalid-argument', 'Body must be exactly { staffEmail, role }.');
  }
  const record = data as Record<string, unknown>;
  const keys = Object.keys(record);
  if (keys.length !== 2 || !keys.includes('staffEmail') || !keys.includes('role')) {
    throw new HttpsError('invalid-argument', 'Body must be exactly { staffEmail, role }.');
  }
  if (typeof record.staffEmail !== 'string' || typeof record.role !== 'string') {
    throw new HttpsError('invalid-argument', 'staffEmail and role must be strings.');
  }
  const staffEmail = record.staffEmail.trim().toLowerCase();
  const role = record.role.trim().toLowerCase();
  if (!staffEmail.includes('@') || staffEmail.length > 254) {
    throw new HttpsError('invalid-argument', 'A staff email is required.');
  }
  if (!ASSIGNABLE_ROLES.includes(role as AssignableRole)) {
    throw new HttpsError('invalid-argument', 'role must be admin, staff, or agent.');
  }
  return { staffEmail, role: role as AssignableRole };
}

function notFound(error: unknown): boolean {
  const code = (error as { code?: string } | undefined)?.code;
  return code === 'auth/user-not-found';
}

export async function syncStaffAccess(input: {
  callerUid: string | undefined;
  callerToken: Record<string, unknown> | undefined;
  data: unknown;
  auth: StaffAuth;
  db: Firestore;
  now?: number;
}): Promise<{ uid: string; email: string; role: AssignableRole; created: boolean }> {
  if (!input.callerUid) throw new HttpsError('unauthenticated', 'Sign in to sync staff access.');
  if (!callerMaySyncStaff(input.callerToken)) {
    throw new HttpsError('permission-denied', 'Only an admin can sync staff access.');
  }
  const { staffEmail, role } = parseSyncStaffBody(input.data);
  let callerEmail = typeof input.callerToken?.email === 'string' ? input.callerToken.email.trim().toLowerCase() : '';
  if (!callerEmail) {
    try {
      const caller = await input.auth.getUser(input.callerUid);
      callerEmail = (caller.email || '').trim().toLowerCase();
    } catch (error) {
      if (!notFound(error)) throw error;
    }
  }
  if (callerEmail && callerEmail === staffEmail) {
    throw new HttpsError('permission-denied', 'You cannot change your own access. Another admin has to sync it.', { code: 'SELF_ROLE' });
  }

  let created = false;
  let user: StaffAuthUser;
  try {
    user = await input.auth.getUserByEmail(staffEmail);
  } catch (error) {
    if (!notFound(error)) throw error;
    user = await input.auth.createUser({ email: staffEmail });
    created = true;
  }
  const claims = claimsForAssignedRole(role);
  await input.auth.setCustomUserClaims(user.uid, claims);
  const now = input.now ?? Date.now();
  await input.db.collection('staff_audit_log').doc(`sync_${input.callerUid}_${user.uid}_${now}`).set({
    action: 'syncStaffAccess',
    actorUid: input.callerUid,
    actorEmail: callerEmail,
    actorRole: 'admin',
    targetUid: user.uid,
    targetEmail: staffEmail,
    role,
    created,
    createdAt: now,
  });
  return { uid: user.uid, email: staffEmail, role, created };
}
