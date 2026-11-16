import { FieldPath, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/https';
import type { StaffAuth } from './staff_access';
import { numOf, round2, str } from './money';

/**
 * City Partner License (TRAD-15).
 *
 * A partner is not staff. Claims are `{ admin: false, role: 'partner', partnerId }` where partnerId
 * is the Auth uid and the `partners/{uid}` id. role=partner is not in isAdminTokenOrEmail.
 *
 * Super admin here is the existing top claim: `admin: true` and role admin / superadmin / super_admin
 * (or `superadmin: true`). That is the account syncStaffAccess provisions as admin. Staff, agent,
 * and partner tokens cannot create, suspend, deactivate, or approve payouts.
 *
 * 2FA: partner callables and rules require the Identity Platform token field
 * `firebase.sign_in_second_factor` of `totp` or `phone`. This repo cannot enroll the factor.
 * Console enrollment is documented in docs/city_partner.md.
 */

const DAY = 86_400_000;
const MANILA = 8 * 3_600_000;
const AREA_RE = /^[a-z0-9](?:[a-z0-9-]{0,78}[a-z0-9])?$/;
const REVIEW = new Set(['approved', 'verified', 'flagged']);
const ACTIVE_LISTING = new Set(['available', 'booked', 'rented', 'active', 'open', 'in progress']);
const OPEN_JOB = new Set(['open', 'in progress', 'awaiting acknowledgment', 'booked', 'active']);
const DONE_JOB = new Set(['completed', 'successful']);
const DEAD_BOOKING = new Set(['cancelled', 'rejected', 'refunded']);

type Doc = Record<string, any>;
type Area = { city: string; municipality: string; province: string; region: string; areaKey: string };
type Token = Record<string, unknown> | undefined;

export function slugArea(value: unknown): string {
  const raw = String(value ?? '').trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  return raw.slice(0, 80);
}

/** City or municipality slug. Province and region are stored on the area but do not split exclusivity. */
export function areaFromInput(input: unknown): Area {
  const row = (input && typeof input === 'object' ? input : {}) as Doc;
  const municipality = str(row.municipality, 80);
  const city = str(row.city, 80);
  const name = municipality || city;
  const areaKey = slugArea(name);
  if (!areaKey || !AREA_RE.test(areaKey)) {
    throw new HttpsError('invalid-argument', 'Each area needs a city or municipality.');
  }
  return { city: city || municipality, municipality, province: str(row.province, 80), region: str(row.region, 80), areaKey };
}

export function areaKeyFromRecord(data: Doc | undefined): string {
  if (!data) return '';
  const explicit = slugArea(data.areaKey);
  if (explicit) return explicit;
  return slugArea(data.city || data.registeredCity || data.municipality);
}

export function periodOf(ms: number): string {
  const d = new Date(ms + MANILA);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
}

export function previousPeriod(ms: number): string {
  const d = new Date(ms + MANILA);
  const month = d.getUTCMonth();
  const year = month === 0 ? d.getUTCFullYear() - 1 : d.getUTCFullYear();
  const prev = month === 0 ? 12 : month;
  return `${year}-${String(prev).padStart(2, '0')}`;
}

export function addMonths(ms: number, months: number): number {
  const d = new Date(ms + MANILA);
  const utc = Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + months, d.getUTCDate(), d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds());
  return utc - MANILA;
}

export function callerIsSuperAdmin(token: Token): boolean {
  if (!token || token.admin !== true) return false;
  if (token.superadmin === true) return true;
  const role = typeof token.role === 'string' ? token.role.trim().toLowerCase() : '';
  return role === 'admin' || role === 'superadmin' || role === 'super_admin';
}

export function partnerMfaFactor(token: Token): string {
  const firebase = token?.firebase;
  if (!firebase || typeof firebase !== 'object') return '';
  const factor = (firebase as Doc).sign_in_second_factor;
  return factor === 'totp' || factor === 'phone' ? factor : '';
}

export function maskPerson(data: Doc, uid: string) {
  const name = str(data.name || data.displayName, 80);
  const bits = name.split(/\s+/).filter(Boolean);
  const displayName = bits.length >= 2 ? `${bits[0]} ${bits[1].slice(0, 1)}.` : (bits[0] || 'Member');
  const review = data.partnerReview && typeof data.partnerReview === 'object' ? data.partnerReview : null;
  return {
    uid,
    displayName,
    areaKey: areaKeyFromRecord(data),
    city: str(data.city || data.registeredCity || data.municipality, 80),
    accountType: str(data.accountType, 40),
    partnerReview: review,
  };
}

function requireSuper(uid: string | undefined, token: Token) {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to manage partners.');
  if (!callerIsSuperAdmin(token)) throw new HttpsError('permission-denied', 'Only a super admin can manage partners.');
  return uid;
}

function targetsOf(input: unknown) {
  const row = (input && typeof input === 'object' ? input : {}) as Doc;
  const activeListings = Math.floor(numOf(row.activeListings, 30));
  const activeProviders = Math.floor(numOf(row.activeProviders, 30));
  const byMonth = Math.floor(numOf(row.byMonth, 6));
  if (activeListings < 0 || activeProviders < 0 || byMonth < 1 || byMonth > 120) {
    throw new HttpsError('invalid-argument', 'Exclusivity targets are out of range.');
  }
  return { activeListings, activeProviders, byMonth };
}

function sharesOf(partnerShareBps: unknown) {
  const partner = partnerShareBps == null ? 7000 : Math.floor(numOf(partnerShareBps, NaN));
  if (!Number.isInteger(partner) || partner < 0 || partner > 10000) {
    throw new HttpsError('invalid-argument', 'partnerShareBps must be an integer from 0 to 10000.');
  }
  return { partnerShareBps: partner, tranyxShareBps: 10000 - partner };
}

function areasOf(input: unknown): Area[] {
  if (!Array.isArray(input) || input.length < 1 || input.length > 10) {
    throw new HttpsError('invalid-argument', 'Assign one to ten areas.');
  }
  const areas = input.map(areaFromInput);
  if (new Set(areas.map((a) => a.areaKey)).size !== areas.length) {
    throw new HttpsError('already-exists', 'That area is already on this partner.', { code: 'DUPLICATE_AREA' });
  }
  return areas;
}

function audit(tx: Transaction, db: Firestore, action: string, partnerId: string, now: number, entry: Doc) {
  tx.set(db.doc(`partner_audit_log/pa_${action}_${partnerId}_${now}`), {
    action, partnerId, createdAt: now, ...entry,
  });
}

async function lockAreas(tx: Transaction, db: Firestore, partnerId: string, areas: Area[], previous: string[]) {
  const next = areas.map((a) => a.areaKey);
  const keys = [...new Set([...previous, ...next])];
  const snaps = await Promise.all(keys.map((key) => tx.get(db.doc(`area_assignments/${key}`))));
  for (const snap of snaps) {
    const key = snap.ref.id;
    const wanted = next.includes(key);
    if (wanted && snap.exists && snap.get('active') === true && snap.get('partnerId') !== partnerId) {
      throw new HttpsError('already-exists', `Another active partner already covers ${key}.`, { code: 'DUPLICATE_AREA' });
    }
  }
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i];
    const area = areas.find((a) => a.areaKey === key);
    if (area) {
      tx.set(snaps[i].ref, { ...area, partnerId, active: true });
    } else if (snaps[i].exists && snaps[i].get('partnerId') === partnerId) {
      tx.set(snaps[i].ref, { active: false, partnerId, areaKey: key }, { merge: true });
    }
  }
}

export async function partnerAdmin(input: {
  callerUid: string | undefined;
  callerToken: Token;
  data: unknown;
  auth: StaffAuth;
  db: Firestore;
  now?: number;
}): Promise<Doc> {
  const actor = requireSuper(input.callerUid, input.callerToken);
  const body = (input.data && typeof input.data === 'object' ? input.data : {}) as Doc;
  const action = str(body.action, 40);
  const now = input.now ?? Date.now();
  const db = input.db;

  if (action === 'overview') return partnerOverview(db, now);
  if (action === 'setRevenueConfig') {
    if (typeof body.includeSubscriptions !== 'boolean') {
      throw new HttpsError('invalid-argument', 'includeSubscriptions must be true or false.');
    }
    await db.runTransaction(async (tx) => {
      audit(tx, db, 'setRevenueConfig', 'platform', now, { actorUid: actor, includeSubscriptions: body.includeSubscriptions });
      tx.set(db.doc('partner_config/revenue'), { includeSubscriptions: body.includeSubscriptions, updatedAt: now, updatedBy: actor }, { merge: true });
    });
    return { ok: true, includeSubscriptions: body.includeSubscriptions };
  }
  if (action === 'approvePayout' || action === 'markPayoutPaid') return settlePayout(db, actor, action, str(body.payoutId, 160), now);

  const email = str(body.email, 254).toLowerCase();
  if (action === 'create') {
    if (!email.includes('@')) throw new HttpsError('invalid-argument', 'A partner email is required.');
    const callerEmail = str(input.callerToken?.email, 254).toLowerCase();
    if (callerEmail && callerEmail === email) {
      throw new HttpsError('permission-denied', 'You cannot make your own account a partner.', { code: 'SELF_ROLE' });
    }
    const areas = areasOf(body.areas);
    const termMonths = Math.floor(numOf(body.termMonths, 36));
    if (termMonths < 1 || termMonths > 120) throw new HttpsError('invalid-argument', 'termMonths must be from 1 to 120.');
    const licenseStart = Math.floor(numOf(body.licenseStart, now));
    const shares = sharesOf(body.partnerShareBps);
    const targets = targetsOf(body.targets);
    const licenseFeePaid = round2(numOf(body.licenseFeePaid, 0));
    if (licenseFeePaid < 0) throw new HttpsError('invalid-argument', 'licenseFeePaid cannot be negative.');
    let created = false;
    let user;
    try {
      user = await input.auth.getUserByEmail(email);
    } catch (error) {
      const code = (error as { code?: string }).code;
      if (code !== 'auth/user-not-found') throw error;
      user = await input.auth.createUser({ email });
      created = true;
    }
    const partnerId = user.uid;
    const renewalDate = addMonths(licenseStart, termMonths);
    await db.runTransaction(async (tx) => {
      const existing = await tx.get(db.doc(`partners/${partnerId}`));
      const previous = existing.exists && Array.isArray(existing.get('areaKeys')) ? existing.get('areaKeys') as string[] : [];
      await lockAreas(tx, db, partnerId, areas, previous);
      const profile = {
        uid: partnerId, email, areas, areaKeys: areas.map((a) => a.areaKey),
        licenseStart, termMonths, renewalDate, licenseFeePaid, status: 'active',
        ...shares, targets, createdAt: existing.exists ? existing.get('createdAt') ?? now : now, updatedAt: now,
      };
      tx.set(db.doc(`partners/${partnerId}`), profile);
      audit(tx, db, 'create', partnerId, now, { actorUid: actor, email, areaKeys: profile.areaKeys, created });
    });
    await input.auth.setCustomUserClaims(partnerId, { admin: false, role: 'partner', partnerId });
    return { ok: true, partnerId, email, created, status: 'active', renewalDate };
  }

  const partnerId = str(body.partnerId, 128);
  if (!partnerId) throw new HttpsError('invalid-argument', 'partnerId is required.');
  if (action === 'suspend' || action === 'deactivate' || action === 'reinstate') {
    const status = action === 'suspend' ? 'suspended' : action === 'reinstate' ? 'active' : 'expired';
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(db.doc(`partners/${partnerId}`));
      if (!snap.exists) throw new HttpsError('not-found', 'Partner not found.');
      const previous = Array.isArray(snap.get('areaKeys')) ? snap.get('areaKeys') as string[] : [];
      if (action === 'reinstate') {
        if (numOf(snap.get('renewalDate')) <= now) {
          throw new HttpsError('failed-precondition', 'Extend the license before reinstating this partner.', { code: 'LICENSE_EXPIRED' });
        }
        const areas = (Array.isArray(snap.get('areas')) ? snap.get('areas') : []) as Area[];
        await lockAreas(tx, db, partnerId, areas, []);
      } else {
        await lockAreas(tx, db, partnerId, [], previous);
      }
      tx.set(snap.ref, { status, updatedAt: now }, { merge: true });
      audit(tx, db, action, partnerId, now, { actorUid: actor, status });
    });
    return { ok: true, partnerId, status };
  }
  if (action === 'update') {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(db.doc(`partners/${partnerId}`));
      if (!snap.exists) throw new HttpsError('not-found', 'Partner not found.');
      const previous = Array.isArray(snap.get('areaKeys')) ? snap.get('areaKeys') as string[] : [];
      const patch: Doc = { updatedAt: now };
      if (body.areas != null) {
        const areas = areasOf(body.areas);
        if (snap.get('status') === 'active') await lockAreas(tx, db, partnerId, areas, previous);
        else await lockAreas(tx, db, partnerId, [], previous);
        patch.areas = areas;
        patch.areaKeys = areas.map((a) => a.areaKey);
      }
      if (body.partnerShareBps != null) Object.assign(patch, sharesOf(body.partnerShareBps));
      if (body.targets != null) patch.targets = targetsOf(body.targets);
      if (body.licenseFeePaid != null) {
        const fee = round2(numOf(body.licenseFeePaid, NaN));
        if (fee < 0) throw new HttpsError('invalid-argument', 'licenseFeePaid cannot be negative.');
        patch.licenseFeePaid = fee;
      }
      if (body.termMonths != null || body.licenseStart != null) {
        const termMonths = Math.floor(numOf(body.termMonths, snap.get('termMonths')));
        const licenseStart = Math.floor(numOf(body.licenseStart, snap.get('licenseStart')));
        if (termMonths < 1 || termMonths > 120) throw new HttpsError('invalid-argument', 'termMonths must be from 1 to 120.');
        patch.termMonths = termMonths;
        patch.licenseStart = licenseStart;
        patch.renewalDate = addMonths(licenseStart, termMonths);
      }
      tx.set(snap.ref, patch, { merge: true });
      audit(tx, db, 'update', partnerId, now, { actorUid: actor, fields: Object.keys(patch) });
    });
    return { ok: true, partnerId };
  }
  throw new HttpsError('invalid-argument', 'Unknown partner action.');
}

async function settlePayout(db: Firestore, actor: string, action: 'approvePayout' | 'markPayoutPaid', payoutId: string, now: number) {
  if (!payoutId) throw new HttpsError('invalid-argument', 'payoutId is required.');
  const next = action === 'approvePayout' ? 'approved' : 'paid';
  const from = action === 'approvePayout' ? 'pending' : 'approved';
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(db.doc(`partner_payouts/${payoutId}`));
    if (!snap.exists) throw new HttpsError('not-found', 'Payout not found.');
    if (snap.get('status') !== from) {
      throw new HttpsError('failed-precondition', `Only a ${from} payout can move to ${next}.`, { code: 'PAYOUT_STATUS' });
    }
    const patch = action === 'approvePayout'
      ? { status: 'approved', approvedBy: actor, approvedAt: now, updatedAt: now }
      : { status: 'paid', paidBy: actor, paidAt: now, updatedAt: now };
    tx.set(snap.ref, patch, { merge: true });
    audit(tx, db, action, str(snap.get('partnerId'), 128), now, { actorUid: actor, payoutId, amount: snap.get('amount'), status: next });
  });
  return { ok: true, payoutId, status: next };
}

async function requirePartner(db: Firestore, uid: string | undefined, token: Token, now: number) {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to open the partner desk.');
  if (callerIsSuperAdmin(token)) return { uid, partnerId: '', super: true as const, profile: null as Doc | null };
  if (token?.role !== 'partner') throw new HttpsError('permission-denied', 'Partner access required.');
  if (!partnerMfaFactor(token)) {
    throw new HttpsError('failed-precondition', 'Partner sign-in requires a second factor.', { code: 'MFA_REQUIRED' });
  }
  const partnerId = str(token?.partnerId, 128);
  if (!partnerId || partnerId !== uid) throw new HttpsError('permission-denied', 'This partner token does not match the signed-in account.');
  const snap = await db.doc(`partners/${partnerId}`).get();
  if (!snap.exists) throw new HttpsError('failed-precondition', 'Partner profile not found.');
  const profile = snap.data() as Doc;
  if (profile.status !== 'active' || numOf(profile.renewalDate) <= now) {
    throw new HttpsError('failed-precondition', 'This partner license is not active.', { code: 'LICENSE_INACTIVE' });
  }
  return { uid, partnerId, super: false as const, profile };
}

function covers(profile: Doc | null, areaKey: string, superAdmin: boolean) {
  if (superAdmin) return true;
  const keys = Array.isArray(profile?.areaKeys) ? profile?.areaKeys as string[] : [];
  return !!areaKey && keys.includes(areaKey);
}

export async function partnerDesk(input: {
  callerUid: string | undefined;
  callerToken: Token;
  data: unknown;
  db: Firestore;
  now?: number;
}): Promise<Doc> {
  const now = input.now ?? Date.now();
  const gate = await requirePartner(input.db, input.callerUid, input.callerToken, now);
  const body = (input.data && typeof input.data === 'object' ? input.data : {}) as Doc;
  const action = str(body.action, 40);
  const db = input.db;
  const partnerId = gate.super ? str(body.partnerId, 128) : gate.partnerId;
  if (action === 'overview') {
    if (!gate.super) throw new HttpsError('permission-denied', 'Only a super admin can overview partners.');
    return partnerOverview(db, now);
  }
  if (!partnerId) throw new HttpsError('invalid-argument', 'partnerId is required.');
  const profileSnap = gate.profile ? null : await db.doc(`partners/${partnerId}`).get();
  const profile = gate.profile ?? (profileSnap?.data() as Doc | undefined);
  if (!profile) throw new HttpsError('not-found', 'Partner not found.');
  if (action === 'dashboard') return partnerDashboard(db, partnerId, profile, now);
  if (action === 'statement' || action === 'statementCsv') {
    const period = str(body.period, 7) || periodOf(now);
    if (!/^\d{4}-\d{2}$/.test(period)) throw new HttpsError('invalid-argument', 'period must be YYYY-MM.');
    const statement = await buildStatement(db, partnerId, profile, period, now);
    if (action === 'statement') return statement;
    return { ...statement, csv: statementCsv(statement) };
  }
  if (action === 'directory') return partnerDirectory(db, profile, gate.super, str(body.areaKey, 80), str(body.kind, 20));
  if (action === 'review') return partnerReview(db, gate, profile, body, now);
  throw new HttpsError('invalid-argument', 'Unknown partner desk action.');
}

async function partnerDirectory(db: Firestore, profile: Doc, superAdmin: boolean, areaKey: string, kind: string) {
  const key = slugArea(areaKey);
  if (!covers(profile, key, superAdmin)) throw new HttpsError('permission-denied', 'That area is outside this license.', { code: 'OUTSIDE_AREA' });
  if (kind === 'users' || kind === 'providers' || kind === 'hosts' || kind === 'renters') {
    const snap = await db.collection('users').where('areaKey', '==', key).limit(200).get();
    return { areaKey: key, kind, records: snap.docs.map((d) => maskPerson(d.data(), d.id)) };
  }
  const listingKind = kind === 'jobs' ? 'jobs' : kind === 'properties' ? 'properties' : 'rentals';
  if (!['rentals', 'properties', 'jobs'].includes(listingKind)) {
    throw new HttpsError('invalid-argument', 'kind must be users, rentals, properties, or jobs.');
  }
  const snap = await db.collection(listingKind).where('areaKey', '==', key).limit(200).get();
  return {
    areaKey: key, kind: listingKind,
    records: snap.docs.map((d) => {
      const data = d.data();
      return {
        id: d.id, kind: listingKind, areaKey: key, status: str(data.status, 40),
        title: str(data.title || `${data.brand ?? ''} ${data.model ?? ''}`.trim(), 120),
        hostId: str(data.hostId || data.creatorId, 128),
        partnerReview: data.partnerReview ?? null,
      };
    }),
  };
}

async function partnerReview(db: Firestore, gate: { uid: string; partnerId: string; super: boolean }, profile: Doc, body: Doc, now: number) {
  const decision = str(body.decision, 20);
  if (!REVIEW.has(decision)) throw new HttpsError('invalid-argument', 'decision must be approved, verified, or flagged.');
  if (decision === 'flagged' && str(body.reason, 500).length < 3) {
    throw new HttpsError('invalid-argument', 'A flag needs a short reason.');
  }
  const kind = str(body.kind, 20);
  const id = str(body.id, 128);
  const collection = kind === 'rental' ? 'rentals' : kind === 'property' ? 'properties' : kind === 'job' ? 'jobs' : kind === 'provider' ? 'users' : '';
  if (!collection || !id) throw new HttpsError('invalid-argument', 'kind and id are required.');
  const ref = db.doc(`${collection}/${id}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'Record not found.');
    const areaKey = areaKeyFromRecord(snap.data());
    if (!covers(profile, areaKey, gate.super)) {
      throw new HttpsError('permission-denied', 'That record is outside this license.', { code: 'OUTSIDE_AREA' });
    }
    const partnerReview = { status: decision, reason: str(body.reason, 500), partnerId: gate.partnerId || gate.uid, at: now };
    tx.set(ref, { partnerReview, updatedAt: now }, { merge: true });
    audit(tx, db, 'review', gate.partnerId || gate.uid, now, { actorUid: gate.uid, kind, id, areaKey, decision });
  });
  return { ok: true, kind, id, decision };
}

const LISTING_COLLECTIONS = ['rentals', 'properties'] as const;

async function countWhere(db: Firestore, collection: string, areaKey: string, accept: (data: Doc) => boolean) {
  const snap = await db.collection(collection).where('areaKey', '==', areaKey).limit(300).get();
  let n = 0;
  const ids = new Set<string>();
  for (const doc of snap.docs) {
    if (!accept(doc.data())) continue;
    n += 1;
    const host = str(doc.get('hostId') || doc.get('creatorId'), 128);
    if (host) ids.add(host);
  }
  return { n, ids };
}

export async function partnerDashboard(db: Firestore, partnerId: string, profile: Doc, now: number) {
  const keys = (Array.isArray(profile.areaKeys) ? profile.areaKeys : []) as string[];
  let activeListings = 0;
  let bookings = 0;
  let completedJobs = 0;
  let newUsers = 0;
  const providers = new Set<string>();
  const monthStart = monthStartMs(now);
  for (const areaKey of keys) {
    for (const collection of LISTING_COLLECTIONS) {
      const row = await countWhere(db, collection, areaKey, (d) => ACTIVE_LISTING.has(String(d.status ?? '').toLowerCase()) && d.isDeleted !== true);
      activeListings += row.n;
      row.ids.forEach((id) => providers.add(id));
    }
    for (const doc of (await db.collection('jobs').where('areaKey', '==', areaKey).limit(300).get()).docs) {
      const status = String(doc.get('status') ?? '').toLowerCase();
      if (OPEN_JOB.has(status)) {
        const host = str(doc.get('creatorId') || doc.get('acceptedApplicantId'), 128);
        if (host) providers.add(host);
      }
      if (DONE_JOB.has(status)) completedJobs += 1;
    }
    for (const collection of ['rental_requests', 'property_requests']) {
      const snap = await db.collection(collection).where('areaKey', '==', areaKey).limit(300).get();
      bookings += snap.docs.filter((d) => !DEAD_BOOKING.has(String(d.get('status') ?? '').toLowerCase())).length;
    }
    const users = await db.collection('users').where('areaKey', '==', areaKey).limit(300).get();
    newUsers += users.docs.filter((d) => numOf(d.get('createdAt')) >= monthStart).length;
  }
  const entries = await revenueForPartner(db, partnerId);
  const period = periodOf(now);
  let grossVolume = 0;
  let earningsToDate = 0;
  let earningsThisMonth = 0;
  for (const entry of entries) {
    grossVolume = round2(grossVolume + numOf(entry.gross));
    earningsToDate = round2(earningsToDate + numOf(entry.partnerShare));
    if (entry.period === period) earningsThisMonth = round2(earningsThisMonth + numOf(entry.partnerShare));
  }
  const targets = targetsOf(profile.targets);
  const monthsElapsed = Math.max(0, Math.floor((now - numOf(profile.licenseStart)) / (30 * DAY)));
  const behindTarget = monthsElapsed >= targets.byMonth && (activeListings < targets.activeListings || providers.size < targets.activeProviders);
  const renewalDate = numOf(profile.renewalDate);
  return {
    partnerId, areas: profile.areas ?? [], areaKeys: keys, status: profile.status, renewalDate,
    licenseExpiring: renewalDate > now && renewalDate - now <= 30 * DAY,
    licenseExpired: renewalDate <= now,
    targets, monthsElapsed, behindTarget,
    activeListings, activeProviders: providers.size, bookings, completedJobs,
    grossVolume, earningsThisMonth, earningsToDate, newUsers,
  };
}

async function revenueForPartner(db: Firestore, partnerId: string) {
  const snap = await db.collection('area_revenue').where('partnerId', '==', partnerId).limit(1000).get();
  return snap.docs.map((d) => d.data());
}

export async function buildStatement(db: Firestore, partnerId: string, profile: Doc, period: string, now: number) {
  const entries = (await revenueForPartner(db, partnerId)).filter((e) => e.period === period);
  const bySource: Doc = {};
  let gross = 0;
  let platform = 0;
  let partnerShare = 0;
  let tranyxShare = 0;
  const lines = entries.map((e) => {
    const source = str(e.source, 40) || 'unknown';
    const row = bySource[source] ?? { gross: 0, platformRevenue: 0, partnerShare: 0, tranyxShare: 0, count: 0 };
    row.gross = round2(row.gross + numOf(e.gross));
    row.platformRevenue = round2(row.platformRevenue + numOf(e.platformRevenue));
    row.partnerShare = round2(row.partnerShare + numOf(e.partnerShare));
    row.tranyxShare = round2(row.tranyxShare + numOf(e.tranyxShare));
    row.count += 1;
    bySource[source] = row;
    gross = round2(gross + numOf(e.gross));
    platform = round2(platform + numOf(e.platformRevenue));
    partnerShare = round2(partnerShare + numOf(e.partnerShare));
    tranyxShare = round2(tranyxShare + numOf(e.tranyxShare));
    return {
      entryId: e.id, source, sourceId: e.sourceId, areaKey: e.areaKey, status: e.status,
      gross: numOf(e.gross), platformRevenue: numOf(e.platformRevenue),
      partnerShare: numOf(e.partnerShare), tranyxShare: numOf(e.tranyxShare),
    };
  });
  const payoutId = `${partnerId}_${period}`;
  const payoutSnap = await db.doc(`partner_payouts/${payoutId}`).get();
  const statement = {
    partnerId, period, partnerShareBps: numOf(profile.partnerShareBps, 7000),
    grossBookings: gross, platformRevenue: platform, partnerShare, tranyxShare, bySource, lines,
    payout: payoutSnap.exists ? { id: payoutId, ...payoutSnap.data() } : null,
    generatedAt: now,
  };
  await db.doc(`partner_statements/${payoutId}`).set(statement, { merge: true });
  return statement;
}

export function statementCsv(statement: Doc): string {
  const header = 'period,source,sourceId,areaKey,status,gross,platformRevenue,partnerShare,tranyxShare';
  const lines = (statement.lines as Doc[]).map((line) =>
    [statement.period, line.source, line.sourceId, line.areaKey, line.status, line.gross, line.platformRevenue, line.partnerShare, line.tranyxShare]
      .map((v) => String(v ?? '').replaceAll('"', '""')).map((v) => `"${v}"`).join(','));
  return [header, ...lines].join('\n');
}

async function partnerOverview(db: Firestore, now: number) {
  const [partners, payouts, config] = await Promise.all([
    db.collection('partners').limit(200).get(),
    db.collection('partner_payouts').where('status', 'in', ['pending', 'approved']).limit(500).get(),
    db.doc('partner_config/revenue').get(),
  ]);
  const unpaid = new Map<string, Doc[]>();
  for (const doc of payouts.docs) {
    const id = str(doc.get('partnerId'), 128);
    unpaid.set(id, [...(unpaid.get(id) ?? []), { id: doc.id, ...doc.data() }]);
  }
  const rows = [];
  for (const doc of partners.docs) {
    const dash = await partnerDashboard(db, doc.id, doc.data(), now);
    rows.push({ ...dash, unpaidPayouts: unpaid.get(doc.id) ?? [], flags: { behindTarget: dash.behindTarget, licenseExpiring: dash.licenseExpiring, licenseExpired: dash.licenseExpired } });
  }
  return { generatedAt: now, includeSubscriptions: config.get('includeSubscriptions') === true, partners: rows };
}

function monthStartMs(now: number) {
  const d = new Date(now + MANILA);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1) - MANILA;
}

type MoneyRow = { gross: number; platform: number; source: string; sourceId: string; areaKey: string; settled: boolean };

function moneyOfEscrow(kind: 'vehicle_rental' | 'property_rental', data: Doc, id: string): MoneyRow | null {
  const status = String(data.status ?? '');
  const settled = status === 'Released';
  const reversed = status === 'Refunded' || status === 'Cancelled';
  if (!settled && !reversed) return null;
  const gross = round2(numOf(data.totalPaid, numOf(data.amount) + numOf(data.bookingFee)));
  const commission = round2(numOf(data.hostCommissionDeducted, numOf(data.amount) * (kind === 'vehicle_rental' ? 0.03 : numOf(data.hostCommissionRate, 0.07))));
  const fee = round2(numOf(data.bookingFee, numOf(data.customerPlatformFeeAmount)));
  const platform = round2(commission + fee);
  if (gross === 0 && platform === 0) return null;
  return { gross, platform, source: kind, sourceId: id, areaKey: areaKeyFromRecord(data), settled };
}

export async function attributePartnerRevenue(db: Firestore, now = Date.now()): Promise<{ settled: number; reversed: number; expired: number }> {
  const configRef = db.doc('partner_config/revenue');
  const config = await configRef.get();
  let settled = 0;
  let reversed = 0;
  const cursors: Doc = {};
  for (const spec of [
    { collection: 'rental_escrows', source: 'vehicle_rental' as const, cursor: 'rentalCursor' },
    { collection: 'property_escrows', source: 'property_rental' as const, cursor: 'propertyCursor' },
  ]) {
    const page = await readPage(db, spec.collection, str(config.get(spec.cursor), 200));
    cursors[spec.cursor] = page.next;
    for (const doc of page.docs) {
      const row = moneyOfEscrow(spec.source, doc.data(), doc.id);
      if (!row) continue;
      const areaKey = row.areaKey || await fallbackArea(db, doc.data());
      const result = await applyRevenue(db, { ...row, areaKey }, now);
      settled += result.settled;
      reversed += result.reversed;
    }
  }
  const feePage = await readPage(db, 'platform_fees', str(config.get('feeCursor'), 200));
  cursors.feeCursor = feePage.next;
  for (const doc of feePage.docs) {
    const job = await db.doc(`jobs/${doc.id}`).get();
    const jobData = job.exists ? job.data() as Doc : {};
    const status = String(jobData.status ?? '').toLowerCase();
    const done = DONE_JOB.has(status);
    const undone = status === 'cancelled' || status === 'refunded';
    if (!done && !undone) continue;
    const platform = round2(numOf(doc.get('amount')));
    const gross = round2(numOf(jobData.pricingValue, platform));
    const areaKey = areaKeyFromRecord(jobData) || areaKeyFromRecord(doc.data()) || await fallbackArea(db, jobData);
    const source = String(jobData.categoryGroup ?? '').toLowerCase() === 'services' ? 'service_job' : 'gig_job';
    const result = await applyRevenue(db, { gross, platform, source, sourceId: doc.id, areaKey, settled: done && !undone }, now);
    settled += result.settled;
    reversed += result.reversed;
  }
  if (config.get('includeSubscriptions') === true) {
    const subs = await db.collection('transactions').where('category', '==', 'subscription').limit(100).get();
    for (const doc of subs.docs) {
      if (String(doc.get('status') ?? '').toLowerCase() !== 'successful') continue;
      const user = await db.doc(`users/${str(doc.get('uid'), 128)}`).get();
      const areaKey = areaKeyFromRecord(user.data());
      const amount = round2(numOf(doc.get('amount')));
      const result = await applyRevenue(db, {
        gross: amount, platform: amount, source: 'subscription', sourceId: doc.id, areaKey, settled: true,
      }, numOf(doc.get('createdAt'), now));
      settled += result.settled;
    }
  }
  let expired = 0;
  const active = await db.collection('partners').where('status', '==', 'active').limit(200).get();
  for (const doc of active.docs) {
    if (numOf(doc.get('renewalDate')) > now) continue;
    await partnerAdmin({
      callerUid: 'system', callerToken: { admin: true, role: 'admin', email: 'system@tranyx.local' },
      data: { action: 'deactivate', partnerId: doc.id },
      auth: { async getUser() { throw new Error('unused'); }, async getUserByEmail() { throw new Error('unused'); }, async createUser() { throw new Error('unused'); }, async setCustomUserClaims() {} },
      db, now,
    });
    expired += 1;
  }
  const period = previousPeriod(now);
  const partners = await db.collection('partners').limit(200).get();
  for (const doc of partners.docs) {
    await ensurePayout(db, doc.id, doc.data(), period, now);
  }
  await configRef.set({ ...cursors, updatedAt: now, includeSubscriptions: config.get('includeSubscriptions') === true }, { merge: true });
  return { settled, reversed, expired };
}

async function readPage(db: Firestore, collection: string, cursor: string) {
  let q = db.collection(collection).orderBy(FieldPath.documentId()).limit(100);
  if (cursor) q = q.startAfter(cursor);
  let snap = await q.get();
  if (snap.empty && cursor) snap = await db.collection(collection).orderBy(FieldPath.documentId()).limit(100).get();
  const last = snap.docs.at(-1);
  return { docs: snap.docs, next: last ? last.id : '' };
}

async function fallbackArea(db: Firestore, data: Doc) {
  for (const uid of [data.hostId, data.renteeId, data.creatorId, data.uid, data.acceptedApplicantId]) {
    const id = str(uid, 128);
    if (!id) continue;
    const user = await db.doc(`users/${id}`).get();
    const key = areaKeyFromRecord(user.data());
    if (key) return key;
  }
  return '';
}

async function applyRevenue(db: Firestore, row: MoneyRow, now: number): Promise<{ settled: number; reversed: number }> {
  if (!row.areaKey) return { settled: 0, reversed: 0 };
  const base = `${row.source}_${row.sourceId}`;
  const indexRef = db.doc(`area_revenue_index/${base}`);
  const reversalRef = db.doc(`area_revenue_index/${base}__reversal`);
  let settled = 0;
  let reversed = 0;
  await db.runTransaction(async (tx) => {
    const [index, reversal, lock] = await Promise.all([tx.get(indexRef), tx.get(reversalRef), tx.get(db.doc(`area_assignments/${row.areaKey}`))]);
    let partnerId = '';
    let bps = 0;
    if (lock.exists && lock.get('active') === true) {
      const pid = str(lock.get('partnerId'), 128);
      const partner = pid ? await tx.get(db.doc(`partners/${pid}`)) : null;
      if (partner?.exists && partner.get('status') === 'active') {
        partnerId = pid;
        bps = numOf(partner.get('partnerShareBps'), 7000);
      }
    }
    if (row.settled && !index.exists) {
      const partnerShare = round2(row.platform * bps / 10000);
      const entry = {
        id: base, source: row.source, sourceId: row.sourceId, areaKey: row.areaKey, status: 'settled',
        gross: row.gross, platformRevenue: row.platform, partnerShare, tranyxShare: round2(row.platform - partnerShare),
        partnerId, period: periodOf(now), occurredAt: now,
      };
      tx.set(db.doc(`area_revenue/${base}`), entry);
      tx.set(indexRef, { entryId: base, at: now });
      settled = 1;
    }
    if (!row.settled && index.exists && !reversal.exists) {
      const original = await tx.get(db.doc(`area_revenue/${base}`));
      if (!original.exists) return;
      const revId = `${base}__reversal`;
      tx.set(db.doc(`area_revenue/${revId}`), {
        id: revId, source: row.source, sourceId: row.sourceId, areaKey: original.get('areaKey'), status: 'reversed',
        gross: round2(-numOf(original.get('gross'))), platformRevenue: round2(-numOf(original.get('platformRevenue'))),
        partnerShare: round2(-numOf(original.get('partnerShare'))), tranyxShare: round2(-numOf(original.get('tranyxShare'))),
        partnerId: original.get('partnerId') ?? '', period: periodOf(now), occurredAt: now, reverses: base,
      });
      tx.set(reversalRef, { entryId: revId, at: now });
      reversed = 1;
    }
  });
  return { settled, reversed };
}

async function ensurePayout(db: Firestore, partnerId: string, profile: Doc, period: string, now: number) {
  const entries = (await revenueForPartner(db, partnerId)).filter((e) => e.period === period);
  if (!entries.length) return;
  const amount = round2(entries.reduce((sum, e) => sum + numOf(e.partnerShare), 0));
  const id = `${partnerId}_${period}`;
  const ref = db.doc(`partner_payouts/${id}`);
  const snap = await ref.get();
  if (snap.exists && snap.get('status') !== 'pending') return;
  await ref.set({
    id, partnerId, period, amount: Math.max(0, amount), status: 'pending',
    partnerShareBps: numOf(profile.partnerShareBps, 7000), updatedAt: now,
    createdAt: snap.exists ? snap.get('createdAt') ?? now : now,
  }, { merge: true });
}
