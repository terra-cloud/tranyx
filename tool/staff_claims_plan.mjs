/** Pure matching for staff-claims sync. Admin-portal uids are not tranyx-app uids. */

export const DEFAULT_ADMIN_PROJECT_ID = 'tranyx-admin-portal';

export function staffClaimsFor(data) {
  if (!data || typeof data !== 'object') return null;
  if (data.isAdmin !== true && data.isStaff !== true && data.isSuperAdmin !== true) return null;
  return data.isAdmin === true || data.isSuperAdmin === true
    ? { admin: true, role: 'admin' }
    : { admin: false, role: 'staff' };
}

export function normalizeEmail(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

function stronger(current, next) {
  if (!current) return next;
  if (current.admin || !next.admin) return current;
  return next;
}

/**
 * Match flagged admin-portal users to target Auth users by email.
 * Grants use the target uid only. Unmatched people are reported and never granted.
 * Revocation is the target users who still hold admin/staff claims and were not matched.
 */
export function planStaffClaims({ flagged, sourceAuthEmailByUid, targetByEmail, targetUsers }) {
  const wanted = new Map();
  const unmatched = [];

  for (const row of flagged) {
    const docEmail = normalizeEmail(row.docEmail);
    const authEmail = normalizeEmail(sourceAuthEmailByUid.get(row.sourceUid));
    const email = docEmail || authEmail;
    if (!email) {
      unmatched.push({ sourceUid: row.sourceUid, email: '', reason: 'no-email' });
      continue;
    }
    const target = targetByEmail.get(email);
    if (!target?.uid) {
      unmatched.push({ sourceUid: row.sourceUid, email, reason: 'no-target-user' });
      continue;
    }
    const prev = wanted.get(target.uid);
    const claims = stronger(prev?.claims, row.claims);
    const keepPrevSource = prev && prev.claims.admin && !row.claims.admin;
    wanted.set(target.uid, {
      uid: target.uid,
      email: normalizeEmail(target.email) || email,
      sourceUid: keepPrevSource ? prev.sourceUid : row.sourceUid,
      claims,
    });
  }

  const targetByUid = new Map(targetUsers.map((user) => [user.uid, user]));
  const grant = [];
  for (const row of wanted.values()) {
    const live = targetByUid.get(row.uid);
    if (!live) {
      unmatched.push({ sourceUid: row.sourceUid, email: row.email, reason: 'no-target-user' });
      wanted.delete(row.uid);
      continue;
    }
    const current = live.customClaims || {};
    if (current.admin === row.claims.admin && current.role === row.claims.role) continue;
    grant.push({
      uid: live.uid,
      email: normalizeEmail(live.email) || row.email,
      sourceUid: row.sourceUid,
      admin: row.claims.admin,
      role: row.claims.role,
    });
  }

  const wouldRevoke = [];
  for (const user of targetUsers) {
    const claims = user.customClaims || {};
    const privileged = claims.admin === true || claims.role === 'admin' || claims.role === 'staff';
    if (privileged && !wanted.has(user.uid)) {
      wouldRevoke.push({ uid: user.uid, email: normalizeEmail(user.email) });
    }
  }

  return { grant, unmatched, wouldRevoke };
}
