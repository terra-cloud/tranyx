import { beforeEach, describe, expect, it } from 'vitest';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { attributePartnerRevenue, callerIsSuperAdmin as isSuper, partnerAdmin, partnerDesk, type PortalAuth } from '../src/partner';
import type { StaffAuth, StaffAuthUser } from '../src/staff_access';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8189';
if (!getApps().length) initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();

class MemoryAuth implements StaffAuth {
  users = new Map<string, StaffAuthUser & { email: string; customClaims: Record<string, unknown> }>();
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
    const user = { uid: `uid_${this.users.size + 1}`, email: props.email, customClaims: {} };
    this.users.set(user.uid, user);
    return user;
  }
  async updateUser() {}
  async setCustomUserClaims(uid: string, claims: Record<string, unknown>) {
    const user = await this.getUser(uid);
    user.customClaims = { ...claims };
  }
}

const superToken = { admin: true, role: 'admin', email: 'root@tranyx.app' };
const OCT = Date.parse('2026-10-15T04:00:00Z');
const NOV = Date.parse('2026-11-15T04:00:00Z');

async function wipe() {
  for (const name of [
    'partners', 'area_assignments', 'partner_audit_log', 'area_revenue', 'area_revenue_index',
    'partner_payouts', 'partner_statements', 'partner_config', 'rental_escrows', 'property_escrows',
    'users', 'rentals', 'jobs', 'transactions', 'platform_fees', 'rental_requests',
  ]) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
  }
}

function seedPartner(auth: MemoryAuth, uid: string, email: string) {
  auth.users.set(uid, { uid, email, customClaims: {} });
}

class MemoryPortalAuth implements PortalAuth {
  users = new Map<string, { uid: string; email: string; emailVerified: boolean }>();
  async getUserByEmail(email: string) {
    const user = [...this.users.values()].find((row) => row.email === email);
    if (!user) {
      const error = new Error('missing') as Error & { code: string };
      error.code = 'auth/user-not-found';
      throw error;
    }
    return user;
  }
  async createUser(props: { email: string; password: string; emailVerified: boolean }) {
    if (!props.password || props.emailVerified !== false) throw new Error('portal user must start unverified');
    const user = { uid: `portal_${this.users.size + 1}`, email: props.email, emailVerified: false };
    this.users.set(user.uid, user);
    return user;
  }
  async updateUser(uid: string, props: { password?: string }) {
    if (!this.users.has(uid) || !props.password) throw new Error('missing password update');
  }
  async generateEmailVerificationLink(email: string) {
    return `https://tranyx-admin-portal.firebaseapp.com/__/auth/action?mode=verifyEmail&oobCode=verify-${email.split('@')[0]}`;
  }
}

describe('city partner license', () => {
  let auth: MemoryAuth;
  beforeEach(async () => {
    auth = new MemoryAuth();
    await wipe();
  });

  it('only a super admin with the admin claim can provision partners', async () => {
    expect(isSuper(superToken)).toBe(true);
    expect(isSuper({ admin: false, role: 'staff' })).toBe(false);
    expect(isSuper({ role: 'admin' })).toBe(false);
    seedPartner(auth, 'pCal', 'cal@example.com');
    await expect(partnerAdmin({
      callerUid: 'staffer', callerToken: { admin: false, role: 'staff', email: 's@tranyx.app' },
      data: { action: 'create', email: 'cal@example.com', areas: [{ city: 'Calbayog', province: 'Samar' }] },
      auth, db, now: OCT,
    })).rejects.toMatchObject({ code: 'permission-denied' });
  });

  it('rejects a second active partner for the same city and allows that city after suspend', async () => {
    seedPartner(auth, 'pCal', 'cal@example.com');
    seedPartner(auth, 'pTag', 'tag@example.com');
    seedPartner(auth, 'pNext', 'next@example.com');
    const created = await partnerAdmin({
      callerUid: 'root', callerToken: superToken, auth, db, now: OCT,
      data: { action: 'create', email: 'cal@example.com', areas: [{ city: 'Calbayog', province: 'Samar' }], licenseFeePaid: 50000 },
    });
    expect(created.partnerId).toBe('pCal');
    expect(auth.users.get('pCal')?.customClaims).toMatchObject({ admin: false, role: 'partner', partnerId: 'pCal' });
    await expect(partnerAdmin({
      callerUid: 'root', callerToken: superToken, auth, db, now: OCT,
      data: { action: 'create', email: 'tag@example.com', areas: [{ city: 'Calbayog', province: 'Northern Samar' }] },
    })).rejects.toMatchObject({ code: 'already-exists' });
    await partnerAdmin({
      callerUid: 'root', callerToken: superToken, auth, db, now: OCT,
      data: { action: 'create', email: 'tag@example.com', areas: [{ city: 'Tagbilaran', province: 'Bohol' }] },
    });
    await partnerAdmin({
      callerUid: 'root', callerToken: superToken, auth, db, now: OCT,
      data: { action: 'suspend', partnerId: 'pCal' },
    });
    const next = await partnerAdmin({
      callerUid: 'root', callerToken: superToken, auth, db, now: OCT,
      data: { action: 'create', email: 'next@example.com', areas: [{ city: 'Calbayog', province: 'Samar' }] },
    });
    expect(next.partnerId).toBe('pNext');
    const log = await db.collection('partner_audit_log').get();
    expect(log.docs.map((d) => d.get('action')).sort()).toEqual(['create', 'create', 'create', 'suspend']);
  });

  it('keeps a Calbayog partner out of Tagbilaran and masks people', async () => {
    seedPartner(auth, 'pCal', 'cal@example.com');
    await partnerAdmin({
      callerUid: 'root', callerToken: superToken, auth, db, now: OCT,
      data: { action: 'create', email: 'cal@example.com', areas: [{ city: 'Calbayog' }] },
    });
    await db.doc('users/host1').set({
      name: 'Maria Santos', email: 'maria@example.com', phoneNumber: '+63917', walletPublicKey: 'secret',
      areaKey: 'calbayog', city: 'Calbayog', accountType: 'host', createdAt: OCT,
    });
    await db.doc('users/host2').set({ name: 'Juan Cruz', email: 'juan@example.com', areaKey: 'tagbilaran', city: 'Tagbilaran', createdAt: OCT });
    await db.doc('rentals/r1').set({ areaKey: 'calbayog', status: 'Available', hostId: 'host1', brand: 'Honda', model: 'Click', plateNumber: 'ABC 123' });
    await db.doc('rentals/r2').set({ areaKey: 'tagbilaran', status: 'Available', hostId: 'host2', brand: 'Toyota', model: 'Vios', plateNumber: 'XYZ 9' });
    const token = { admin: false, role: 'partner', partnerId: 'pCal', email_verified: true, firebase: { sign_in_second_factor: 'totp' } };
    await expect(partnerDesk({
      callerUid: 'pCal', callerToken: { admin: false, role: 'partner', partnerId: 'pCal', email_verified: false }, db, now: OCT,
      data: { action: 'profile' },
    })).rejects.toMatchObject({ code: 'failed-precondition' });
    const withoutFactor = await partnerDesk({
      callerUid: 'pCal', callerToken: { admin: false, role: 'partner', partnerId: 'pCal', email_verified: true }, db, now: OCT,
      data: { action: 'profile' },
    });
    expect(withoutFactor.mfaEnrolled).toBe(false);
    expect(withoutFactor.mfaEnforced).toBe(false);
    process.env.ENFORCE_PARTNER_MFA = 'true';
    await expect(partnerDesk({
      callerUid: 'pCal', callerToken: { admin: false, role: 'partner', partnerId: 'pCal' }, db, now: OCT,
      data: { action: 'directory', kind: 'users', areaKey: 'calbayog' },
    })).rejects.toMatchObject({ code: 'failed-precondition' });
    delete process.env.ENFORCE_PARTNER_MFA;
    const own = await partnerDesk({
      callerUid: 'pCal', callerToken: token, db, now: OCT,
      data: { action: 'directory', kind: 'users', areaKey: 'calbayog' },
    });
    expect(own.records).toEqual([expect.objectContaining({ uid: 'host1', displayName: 'Maria S.' })]);
    expect(JSON.stringify(own.records)).not.toContain('maria@example.com');
    expect(JSON.stringify(own.records)).not.toContain('secret');
    await expect(partnerDesk({
      callerUid: 'pCal', callerToken: token, db, now: OCT,
      data: { action: 'directory', kind: 'rentals', areaKey: 'tagbilaran' },
    })).rejects.toMatchObject({ code: 'permission-denied' });
    const listings = await partnerDesk({
      callerUid: 'pCal', callerToken: token, db, now: OCT,
      data: { action: 'directory', kind: 'rentals', areaKey: 'calbayog' },
    });
    expect(listings.records).toHaveLength(1);
    expect(JSON.stringify(listings.records)).not.toContain('ABC 123');
    await expect(partnerDesk({
      callerUid: 'pCal', callerToken: token, db, now: OCT,
      data: { action: 'review', kind: 'rental', id: 'r2', decision: 'flagged', reason: 'wrong city' },
    })).rejects.toMatchObject({ code: 'permission-denied' });
    await expect(partnerDesk({
      callerUid: 'pCal', callerToken: token, db, now: OCT,
      data: { action: 'review', kind: 'provider', id: 'host1', decision: 'suspended', reason: 'no' },
    })).rejects.toMatchObject({ code: 'invalid-argument' });
    await partnerDesk({
      callerUid: 'pCal', callerToken: token, db, now: OCT,
      data: { action: 'review', kind: 'rental', id: 'r1', decision: 'verified' },
    });
    expect((await db.doc('rentals/r1').get()).get('partnerReview.status')).toBe('verified');
    await db.doc('rental_requests/bCal').set({
      areaKey: 'calbayog', status: 'Pending', renteeId: 'host1', hostId: 'host1',
      phone: '+63917', email: 'maria@example.com', address: '12 Real St',
    });
    await db.doc('rental_requests/bTag').set({ areaKey: 'tagbilaran', status: 'Pending', renteeId: 'host2' });
    await db.doc('supportTickets/tCal').set({ areaKey: 'calbayog', status: 'Open', subject: 'Pickup', userEmail: 'maria@example.com' });
    const bookings = await partnerDesk({
      callerUid: 'pCal', callerToken: token, db, now: OCT,
      data: { action: 'directory', kind: 'bookings', areaKey: 'calbayog' },
    });
    expect(bookings.records).toEqual([expect.objectContaining({ id: 'bCal', status: 'Pending' })]);
    expect(JSON.stringify(bookings.records)).not.toContain('maria@example.com');
    expect(JSON.stringify(bookings.records)).not.toContain('Real St');
    await expect(partnerDesk({
      callerUid: 'pCal', callerToken: token, db, now: OCT,
      data: { action: 'directory', kind: 'bookings', areaKey: 'tagbilaran' },
    })).rejects.toMatchObject({ code: 'permission-denied' });
    const tickets = await partnerDesk({
      callerUid: 'pCal', callerToken: token, db, now: OCT,
      data: { action: 'directory', kind: 'tickets', areaKey: 'calbayog' },
    });
    expect(JSON.stringify(tickets.records)).toContain('Pickup');
    expect(JSON.stringify(tickets.records)).not.toContain('maria@example.com');
    const hosts = await partnerDesk({
      callerUid: 'pCal', callerToken: token, db, now: OCT,
      data: { action: 'directory', kind: 'hosts', areaKey: 'calbayog' },
    });
    expect(hosts.records).toEqual([expect.objectContaining({ uid: 'host1', displayName: 'Maria S.' })]);
  });

  it('reverses settled area revenue and ignores subscriptions while the flag is off', async () => {
    await db.doc('area_assignments/calbayog').set({ active: true, partnerId: 'pCal', areaKey: 'calbayog', city: 'Calbayog' });
    await db.doc('partners/pCal').set({
      uid: 'pCal', status: 'active', areaKeys: ['calbayog'], renewalDate: NOV + 86_400_000 * 400, licenseStart: OCT,
      targets: { activeListings: 30, activeProviders: 30, byMonth: 6 },
    });
    await db.doc('rental_escrows/b1').set({
      status: 'Released', areaKey: 'calbayog', amount: 1000, bookingFee: 30, hostCommissionDeducted: 30, totalPaid: 1030,
    });
    await db.doc('transactions/sub1').set({
      category: 'subscription', status: 'Successful', amount: 499, uid: 'pCal', createdAt: OCT,
    });
    const first = await attributePartnerRevenue(db, OCT);
    expect(first.settled).toBe(1);
    const entry = (await db.doc('area_revenue/vehicle_rental_b1').get()).data();
    expect(entry).toMatchObject({ status: 'settled', platformRevenue: 60, partnerShare: 18, tranyxShare: 42, areaKey: 'calbayog', partnerId: 'pCal' });
    expect((await db.doc('area_revenue/subscription_sub1').get()).exists).toBe(false);
    await db.doc('rental_escrows/b1').update({ status: 'Refunded' });
    const second = await attributePartnerRevenue(db, OCT + 86_400_000);
    expect(second.reversed).toBe(1);
    const rows = (await db.collection('area_revenue').get()).docs.map((d) => d.data());
    const net = rows.reduce((sum, row) => sum + Number(row.platformRevenue), 0);
    expect(net).toBe(0);
    expect(rows.map((row) => row.status).sort()).toEqual(['reversed', 'settled']);
  });

  it('lets only a super admin approve then mark a monthly payout paid', async () => {
    await db.doc('area_assignments/calbayog').set({ active: true, partnerId: 'pCal', areaKey: 'calbayog' });
    await db.doc('partners/pCal').set({
      uid: 'pCal', status: 'active', areaKeys: ['calbayog'],
      renewalDate: NOV + 86_400_000 * 400, licenseStart: OCT, targets: { activeListings: 30, activeProviders: 30, byMonth: 6 },
    });
    await db.doc('rental_escrows/b1').set({
      status: 'Released', areaKey: 'calbayog', amount: 1000, bookingFee: 30, hostCommissionDeducted: 30, totalPaid: 1030,
    });
    await attributePartnerRevenue(db, OCT);
    await attributePartnerRevenue(db, NOV);
    const payoutId = 'pCal_2026-10';
    expect((await db.doc(`partner_payouts/${payoutId}`).get()).get('status')).toBe('pending');
    expect((await db.doc(`partner_payouts/${payoutId}`).get()).get('amount')).toBe(18);
    const token = { admin: false, role: 'partner', partnerId: 'pCal', firebase: { sign_in_second_factor: 'totp' } };
    await expect(partnerAdmin({
      callerUid: 'pCal', callerToken: token, auth, db, now: NOV,
      data: { action: 'approvePayout', payoutId },
    })).rejects.toMatchObject({ code: 'permission-denied' });
    await partnerAdmin({
      callerUid: 'root', callerToken: superToken, auth, db, now: NOV,
      data: { action: 'approvePayout', payoutId },
    });
    expect((await db.doc(`partner_payouts/${payoutId}`).get()).get('status')).toBe('approved');
    await partnerAdmin({
      callerUid: 'root', callerToken: superToken, auth, db, now: NOV,
      data: { action: 'markPayoutPaid', payoutId },
    });
    expect((await db.doc(`partner_payouts/${payoutId}`).get()).get('status')).toBe('paid');
    const statement = await partnerDesk({
      callerUid: 'root', callerToken: superToken, db, now: NOV,
      data: { action: 'statementCsv', period: '2026-10', partnerId: 'pCal' },
    });
    expect(statement.csv).toContain('vehicle_rental');
    expect(statement.partnerShare).toBe(18);
    const dash = await partnerDesk({
      callerUid: 'root', callerToken: superToken, db, now: NOV,
      data: { action: 'dashboard', partnerId: 'pCal' },
    });
    expect(dash.earningsToDate).toBe(18);
    expect(dash.targets).toMatchObject({ activeListings: 30, activeProviders: 30, byMonth: 6 });
  });

  it('upserts the admin-portal users doc as partner and never returns a password', async () => {
    seedPartner(auth, 'pCal', 'cal@example.com');
    const portalAuth = new MemoryPortalAuth();
    const created = await partnerAdmin({
      callerUid: 'root', callerToken: superToken, auth, db, now: OCT,
      portal: { auth: portalAuth, db },
      data: {
        action: 'create', email: 'cal@example.com', password: 'Calbayog1',
        areas: [{ city: 'Calbayog', province: 'Samar' }],
      },
    });
    expect(created.portalUid).toBe('portal_1');
    expect(created.emailVerified).toBe(false);
    expect(created).not.toHaveProperty('password');
    expect(created).not.toHaveProperty('passwordSetupLink');
    expect(created).not.toHaveProperty('verificationLink');
    const doc = await db.doc('users/portal_1').get();
    expect(doc.get('role')).toBe('partner');
    expect(doc.get('partnerId')).toBe('pCal');
    expect(doc.get('email')).toBe('cal@example.com');
    expect(doc.get('areaKeys')).toEqual(['calbayog']);
    expect(doc.data()).not.toHaveProperty('password');
    const resent = await partnerAdmin({
      callerUid: 'root', callerToken: superToken, auth, db, now: OCT,
      portal: { auth: portalAuth, db },
      data: { action: 'resendVerification', email: 'cal@example.com' },
    });
    expect(resent.emailVerified).toBe(false);
    expect(String(resent.verificationLink)).toContain('verifyEmail');
    expect(resent).not.toHaveProperty('password');
    expect((await db.doc('users/portal_1').get()).get('role')).toBe('partner');
    const reset = await partnerAdmin({
      callerUid: 'root', callerToken: superToken, auth, db, now: OCT,
      portal: { auth: portalAuth, db },
      data: { action: 'setPartnerPassword', email: 'cal@example.com', password: 'Calbayog2' },
    });
    expect(reset).toEqual({ ok: true, partnerId: 'pCal', email: 'cal@example.com' });
  });

  it('returns only this partner share and no platform or other-area figures', async () => {
    seedPartner(auth, 'pCal', 'cal@example.com');
    await partnerAdmin({
      callerUid: 'root', callerToken: superToken, auth, db, now: OCT,
      data: { action: 'create', email: 'cal@example.com', areas: [{ city: 'Calbayog' }] },
    });
    await db.doc('area_revenue/own').set({
      partnerId: 'pCal', areaKey: 'calbayog', source: 'vehicle_rental', sourceId: 'b1', status: 'settled',
      gross: 1000, platformRevenue: 100, partnerShare: 70, tranyxShare: 30, period: '2026-10',
    });
    await db.doc('area_revenue/other').set({
      partnerId: 'pOther', areaKey: 'tagbilaran', source: 'vehicle_rental', sourceId: 'b2', status: 'settled',
      gross: 500, platformRevenue: 50, partnerShare: 35, tranyxShare: 15, period: '2026-10',
    });
    const token = { admin: false, role: 'partner', partnerId: 'pCal', email_verified: true };
    const view = await partnerDesk({
      callerUid: 'pCal', callerToken: token, db, now: OCT,
      data: { action: 'revenue' },
    });
    expect(view.partnerShare).toBe(70);
    expect(view.lines).toEqual([expect.objectContaining({ areaKey: 'calbayog', partnerShare: 70 })]);
    const encoded = JSON.stringify(view);
    expect(encoded).not.toContain('tranyxShare');
    expect(encoded).not.toContain('platformRevenue');
    expect(encoded).not.toContain('gross');
    expect(encoded).not.toContain('pOther');
    expect(encoded).not.toContain('tagbilaran');
    await expect(partnerDesk({
      callerUid: 'pCal', callerToken: token, db, now: OCT,
      data: { action: 'statement', period: '2026-10' },
    })).rejects.toMatchObject({ code: 'permission-denied' });
  });
});
