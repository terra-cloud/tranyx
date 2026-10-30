import { HttpsError } from 'firebase-functions/https';
import type { DocumentReference, Transaction } from 'firebase-admin/firestore';
import {
  ledger, notify, numOf, parseId, parseKey, readOp, requireAuth, round2, str, tokenIsStaff, userDocIsStaff, Wallet, writeOp,
  type CallerAuth, type MoneyDeps,
} from './money';
import { parsePackage, promoDiscount, propertyFinancials, vehicleBasePrice } from './pricing';

/**
 * Phase 4 rentals + properties (vehicle and real estate share this module, `kind` picks the collections).
 *
 *   {kind}_escrows/{requestId}   server-owned (Admin SDK only): Held -> Released | Refunded
 *   bookingRequest   renter pays total (price recomputed from the listing) -> request doc + escrow, one transaction
 *   bookingAction    reject | cancelRequest | revoke (full refund), cancelActive (refund - flat fee), complete (host payout)
 *   rentalExtension  request | autoApprove | approve | reject (vehicle extension hours at the listing's hourly rate)
 *   listingFee       charge / refund the host listing fee (settings/platform_fees.listingFeeRate, 0 today)
 */

export type Kind = 'vehicle' | 'property';
const C = {
  vehicle: { listing: 'rentals', requests: 'rental_requests', escrows: 'rental_escrows', idField: 'rentalId', label: 'Vehicle', module: 'vehicle_rentals' },
  property: { listing: 'properties', requests: 'property_requests', escrows: 'property_escrows', idField: 'propertyId', label: 'Property', module: 'property_rentals' },
} as const;

export const CANCELLATION_FEE = 2.0;
const VEHICLE_BOOKING_FEE_RATE = 0.03;
const VEHICLE_COMMISSION_RATE = 0.03;
const DAY_MS = 86_400_000;
const OPEN_REQUEST = ['Pending'];
const PRE_SIGN = ['Pending', 'Approved', 'Awaiting Signature'];
const CLOSED = ['Rejected', 'Cancelled', 'Completed', 'Refunded'];

type Doc = Record<string, any>;

function parseKind(v: unknown): Kind {
  if (v !== 'vehicle' && v !== 'property') throw new HttpsError('invalid-argument', "kind must be 'vehicle' or 'property'.");
  return v;
}

function parseBody(data: unknown): Doc {
  return (data && typeof data === 'object' ? data : {}) as Doc;
}

const refs = (deps: MoneyDeps, kind: Kind, requestId: string, listingId?: string) => {
  const c = C[kind];
  return {
    request: deps.db.doc(`${c.requests}/${requestId}`),
    escrow: deps.db.doc(`${c.escrows}/${requestId}`),
    mirror: listingId && listingId !== requestId ? deps.db.doc(`${c.escrows}/${listingId}`) : null,
  };
};

/** Client keys that are never copied from a client-built request document (the server owns them). */
const SERVER_OWNED = new Set([
  'id', 'status', 'renteeId', 'renterId', 'hostId', 'totalCost', 'bookingFee', 'originalCost', 'discountAmount', 'promoCode',
  'createdAt', 'approvedAt', 'rejectedAt', 'cancelledAt', 'completedAt', 'allowChat', 'baseRentAmount', 'securityDepositAmount',
  'customerPlatformFeeAmount', 'customerPlatformFeeRate', 'hostCommissionRate', 'totalCustomerPaid', 'appliedTier', 'unitRate',
  'totalDays', 'depositType', 'depositValue', 'escrowStatus', 'refundAmount',
]);

function clientFields(raw: unknown): Doc {
  const out: Doc = {};
  if (!raw || typeof raw !== 'object') return out;
  for (const [k, v] of Object.entries(raw as Doc)) {
    if (SERVER_OWNED.has(k) || k.includes('/') || k.startsWith('__')) continue;
    if (v === null || ['string', 'number', 'boolean'].includes(typeof v) || Array.isArray(v)) {
      out[k] = typeof v === 'string' ? v.slice(0, 2000) : v;
    }
  }
  return out;
}

// ── bookingRequest ─────────────────────────────────────────────────────────────────────────────
export async function bookingRequest(deps: MoneyDeps, auth: CallerAuth | undefined, data: unknown) {
  const uid = requireAuth(auth);
  const d = parseBody(data);
  const key = parseKey(d.idempotencyKey);
  const kind = parseKind(d.kind);
  const listingId = parseId(d.listingId, 'listingId');
  const c = C[kind];
  const { db } = deps;
  const now = deps.now();
  const requestId = `req_${key}`;
  const promoCode = str(d.promoCode, 40).toUpperCase();
  const startDate = numOf(d.startDate);
  const endDate = numOf(d.endDate);
  const qty = Math.floor(numOf(d.multiplier, 1));
  if (qty < 1 || qty > 366) throw new HttpsError('invalid-argument', 'Invalid duration.');
  const pkg = kind === 'vehicle' ? parsePackage(d.durationType) : null;
  if (kind === 'vehicle' && !pkg) throw new HttpsError('invalid-argument', 'Invalid duration type.');

  return db.runTransaction(async (tx) => {
    const replay = await readOp(tx, db, uid, key);
    if (replay) return { ...replay, replay: true };

    const listingSnap = await tx.get(db.doc(`${c.listing}/${listingId}`));
    const feeSnap = await tx.get(db.doc('settings/platform_fees'));
    const promoSnap = promoCode ? await tx.get(db.doc(`promos/${promoCode}`)) : null;
    const w = new Wallet(tx, db);
    await w.load(uid);
    if (!listingSnap.exists) throw new HttpsError('not-found', 'Listing not found.');
    const l = listingSnap.data() as Doc;
    const hostId = str(l.hostId, 128);
    if (!hostId) throw new HttpsError('failed-precondition', 'Listing has no host.');
    if (hostId === uid) throw new HttpsError('failed-precondition', 'You cannot book your own listing.');
    const blocked = ['Inactive', 'Unpublished', 'Archived', 'Deleted', 'Not Accepting Bookings'];
    if (blocked.includes(String(l.status)) || l.isDeleted === true || l.acceptingBookings === false) {
      throw new HttpsError('failed-precondition', 'This listing is not accepting new bookings.');
    }
    const fees = (feeSnap.exists ? feeSnap.data() : {}) as Doc;

    let base: number;
    let fee: number;
    let deposit = 0;
    let custRate = VEHICLE_BOOKING_FEE_RATE;
    let hostRate = VEHICLE_COMMISSION_RATE;
    let extra: Doc = {};
    if (kind === 'vehicle') {
      base = vehicleBasePrice(l, pkg!, qty, d.hireWithDriver === true);
      if (!(base > 0)) throw new HttpsError('failed-precondition', 'This listing has no valid price.');
      fee = round2(base * VEHICLE_BOOKING_FEE_RATE);
    } else {
      custRate = numOf(fees.propertyCustomerFeeRate, 0.03);
      hostRate = numOf(fees.propertyHostCommissionRate, 0.07);
      let days: number;
      if (endDate > startDate) {
        const diff = Math.round((endDate - startDate) / DAY_MS);
        days = diff > 0 ? diff : 1;
      } else {
        const t = String(d.durationType ?? '').toLowerCase();
        days = qty * (t === 'daily' ? 1 : t === 'weekly' ? 7 : 30);
      }
      const f = propertyFinancials(l, days, custRate, hostRate);
      if (!(f.baseRent > 0)) throw new HttpsError('failed-precondition', 'This listing has no valid price.');
      base = f.baseRent;
      fee = f.customerPlatformFee;
      deposit = f.securityDeposit;
      extra = {
        totalDays: days, baseRentAmount: base, securityDepositAmount: deposit, depositType: f.depositType, depositValue: f.depositValue,
        customerPlatformFeeRate: custRate, hostCommissionRate: hostRate, appliedTier: f.appliedTier, unitRate: f.unitRate,
      };
    }

    let discount = 0;
    if (promoCode) {
      const dsc = promoDiscount(promoSnap?.exists ? (promoSnap.data() as Doc) : undefined, { base, fee, uid, now, module: c.module });
      if (dsc == null) throw new HttpsError('failed-precondition', 'This promo code cannot be used.', { code: 'PROMO_INVALID' });
      discount = dsc;
    }
    const finalFee = round2(Math.max(0, fee - discount));
    const totalPaid = round2(base + finalFee + deposit);

    w.debit(uid, totalPaid);
    const { request, escrow } = refs(deps, kind, requestId, listingId);
    const existing = await tx.get(escrow);
    if (existing.exists) throw new HttpsError('already-exists', 'This request was already submitted.');

    const requestDoc: Doc = {
      ...clientFields(d.request),
      ...extra,
      id: requestId,
      [c.idField]: listingId,
      renteeId: uid,
      hostId,
      status: 'Pending',
      createdAt: now,
      totalCost: kind === 'vehicle' ? base : totalPaid,
      bookingFee: finalFee,
      originalCost: base,
      ...(kind === 'property' ? { customerPlatformFeeAmount: finalFee, totalCustomerPaid: totalPaid } : {}),
      ...(kind === 'vehicle' ? { brand: l.brand ?? '', model: l.model ?? '', year: l.year ?? '' } : { title: l.title ?? '' }),
      startDate, endDate,
      ...(promoCode ? { promoCode, discountAmount: discount } : {}),
    };
    const escrowDoc: Doc = {
      requestId, [c.idField]: listingId, renteeId: uid, renterId: uid, hostId, status: 'Held', createdAt: now,
      amount: kind === 'vehicle' ? base : totalPaid,
      baseAmount: base, bookingFee: finalFee, securityDepositAmount: deposit, totalPaid,
      customerPlatformFeeAmount: finalFee, customerPlatformFeeRate: custRate, hostCommissionRate: hostRate,
      ...(kind === 'property' ? { baseRentAmount: base } : {}),
    };
    tx.create(request, requestDoc);
    tx.create(escrow, escrowDoc);
    ledger(tx, db, `bk_${kind}_${requestId}_hold`, uid, now, {
      type: 'payment', category: 'rental', amount: totalPaid, previousBalance: w.balance(uid) + totalPaid, newBalance: w.balance(uid),
      title: kind === 'vehicle' ? 'Vehicle Booking Request' : 'Property Booking Request',
      desc: `Requested ${kind === 'vehicle' ? `${l.brand ?? ''} ${l.model ?? ''}`.trim() : `property "${l.title ?? ''}"`}${promoCode ? ` (Promo ${promoCode}: -₱${discount.toFixed(2)})` : ''}`,
      status: 'Successful', refId: requestId,
    });
    notify(tx, db, hostId, now, 'Booking Request Received', 'A renter sent a booking request for your listing.', requestId.slice(-6));
    w.flush();
    const result = { ok: true, requestId, totalPaid, base, bookingFee: finalFee, securityDeposit: deposit, discount, newBalance: w.balance(uid) };
    writeOp(tx, db, uid, key, 'bookingRequest', result, now);
    return result;
  });
}

// ── bookingAction ──────────────────────────────────────────────────────────────────────────────
export type BookingActionName = 'reject' | 'cancelRequest' | 'revoke' | 'cancelActive' | 'complete';
const ACTIONS: BookingActionName[] = ['reject', 'cancelRequest', 'revoke', 'cancelActive', 'complete'];

export async function bookingAction(deps: MoneyDeps, auth: CallerAuth | undefined, data: unknown) {
  const uid = requireAuth(auth);
  const d = parseBody(data);
  const key = parseKey(d.idempotencyKey);
  const kind = parseKind(d.kind);
  const action = d.action as BookingActionName;
  if (!ACTIONS.includes(action)) throw new HttpsError('invalid-argument', 'Unknown action.');
  const requestId = parseId(d.requestId, 'requestId');
  const listingId = d.listingId ? parseId(d.listingId, 'listingId') : undefined;
  const { db } = deps;
  const now = deps.now();
  const staffToken = tokenIsStaff(auth?.token);

  return db.runTransaction(async (tx) => {
    const replay = await readOp(tx, db, uid, key);
    if (replay) return { ...replay, replay: true };

    const r = refs(deps, kind, requestId, listingId);
    const [escSnap, reqSnap, callerSnap] = await Promise.all([tx.get(r.escrow), tx.get(r.request), tx.get(db.doc(`users/${uid}`))]);
    if (!escSnap.exists) throw new HttpsError('failed-precondition', 'No funds are held for this booking.');
    const e = escSnap.data() as Doc;
    const q = (reqSnap.exists ? reqSnap.data() : {}) as Doc;
    const renteeId = str(e.renteeId, 128);
    const hostId = str(e.hostId, 128);
    const isStaff = staffToken || userDocIsStaff(callerSnap.data());
    const isRentee = uid === renteeId;
    const isHost = uid === hostId;
    const reqStatus = String(q.status ?? '');

    if (!renteeId || !hostId) throw new HttpsError('failed-precondition', 'This booking has no parties on record.');
    const w = new Wallet(tx, db);
    await w.load(renteeId);
    if (action === 'complete') await w.load(hostId);

    if (e.status === 'Refunded' || e.status === 'Released') {
      // already settled: idempotent no-op for the same direction, error otherwise
      if ((action === 'complete') === (e.status === 'Released')) return { ok: true, alreadyDone: true, status: e.status };
      throw new HttpsError('failed-precondition', 'This booking is already settled.');
    }
    if (e.status !== 'Held') throw new HttpsError('failed-precondition', 'This booking cannot be settled right now.');

    const totalPaid = round2(numOf(e.totalPaid, numOf(e.amount) + numOf(e.bookingFee)));
    const deposit = round2(numOf(e.securityDepositAmount));
    const patchReq: Doc = {};
    let refund = 0;
    let refundTitle = '';
    let refundDesc = '';
    let payout = 0;
    let commission = 0;
    let rate = 0;

    if (action === 'reject' || action === 'revoke') {
      if (!(isHost || isStaff)) throw new HttpsError('permission-denied', 'Only the host can do this.');
      if (action === 'reject' ? !OPEN_REQUEST.includes(reqStatus) : !['Approved', 'Awaiting Signature'].includes(reqStatus)) {
        throw new HttpsError('failed-precondition', 'The request is not in a state that allows this.');
      }
      refund = totalPaid;
      refundTitle = action === 'reject' ? 'Booking Request Rejected' : 'Booking Approval Revoked';
      refundDesc = `Full refund: host ${action === 'reject' ? 'rejected' : 'revoked approval for'} your ${kind === 'vehicle' ? 'vehicle' : 'property'} request`;
      patchReq.status = action === 'reject' ? 'Rejected' : 'Cancelled';
      patchReq[action === 'reject' ? 'rejectedAt' : 'cancelledAt'] = now;
    } else if (action === 'cancelRequest') {
      if (!(isRentee || isStaff)) throw new HttpsError('permission-denied', 'Only the renter can cancel this request.');
      if (!PRE_SIGN.includes(reqStatus)) throw new HttpsError('failed-precondition', 'This request can no longer be cancelled here.');
      refund = totalPaid;
      refundTitle = 'Booking Request Cancelled';
      refundDesc = 'Refund for cancelled booking request';
      patchReq.status = 'Cancelled';
      patchReq.cancelledAt = now;
    } else if (action === 'cancelActive') {
      if (!(isRentee || isHost || isStaff)) throw new HttpsError('permission-denied', 'Not your booking.');
      if (CLOSED.includes(reqStatus) || OPEN_REQUEST.includes(reqStatus)) throw new HttpsError('failed-precondition', 'This booking is not active.');
      refund = round2(Math.max(0, totalPaid - CANCELLATION_FEE));
      refundTitle = kind === 'vehicle' ? 'Rental Cancellation — Refund' : 'Property Lease Cancellation — Refund';
      refundDesc = `Refund for cancelled booking (total paid: ${totalPaid.toFixed(2)} − ${CANCELLATION_FEE.toFixed(2)} TYXBIT cancellation fee)`;
      patchReq.status = 'Cancelled';
      patchReq.cancelledAt = now;
    } else {
      if (!(isHost || isRentee || isStaff)) throw new HttpsError('permission-denied', 'Not your booking.');
      if (CLOSED.includes(reqStatus) || OPEN_REQUEST.includes(reqStatus)) throw new HttpsError('failed-precondition', 'This booking cannot be completed.');
      if (kind === 'vehicle') {
        rate = VEHICLE_COMMISSION_RATE;
        commission = round2(numOf(e.amount) * rate);
        payout = round2(numOf(e.amount) - commission);
      } else {
        rate = numOf(e.hostCommissionRate, 0.07);
        const baseRent = numOf(e.baseRentAmount, numOf(e.baseAmount));
        commission = round2(baseRent * rate);
        payout = round2(baseRent - commission);
      }
      patchReq.status = 'Completed';
      patchReq.completedAt = now;
    }

    const escPatch: Doc = { updatedAt: now };
    if (action === 'complete') {
      w.credit(hostId, payout);
      ledger(tx, db, `bk_${kind}_${requestId}_payout`, hostId, now, {
        type: 'payment', amount: payout, baseAmount: kind === 'vehicle' ? numOf(e.amount) : numOf(e.baseRentAmount), commissionFee: commission,
        commissionRate: rate, commissionLabel: `Platform Commission (${(rate * 100).toFixed(0)}%)`,
        title: kind === 'vehicle' ? 'Rental Earnings Payout' : 'Property Rental Payout', desc: 'Rental payout released from escrow', status: 'Completed', timestamp: now, refId: requestId,
      });
      Object.assign(escPatch, { status: 'Released', releasedAt: now, hostCommissionDeducted: commission, hostPayout: payout });
      if (deposit > 0) {
        w.credit(renteeId, deposit);
        ledger(tx, db, `bk_${kind}_${requestId}_deposit`, renteeId, now, {
          type: 'refund', category: 'refund', amount: deposit, title: 'Security Deposit Refund', desc: '100% refund of security deposit for completed lease', originRail: 'internal_balance', refId: requestId,
        });
        Object.assign(escPatch, { securityDepositRefunded: deposit, securityDepositStatus: 'Refunded' });
      } else {
        escPatch.securityDepositStatus = 'None';
      }
      notify(tx, db, hostId, now, 'Rental Completed', `Payout of ${payout.toFixed(2)} TYXBIT credited to your wallet.`, requestId.slice(-6));
    } else {
      if (refund > 0) {
        w.credit(renteeId, refund);
        ledger(tx, db, `bk_${kind}_${requestId}_refund`, renteeId, now, {
          type: 'refund', category: 'refund', amount: refund, title: refundTitle, desc: refundDesc, originRail: 'internal_balance', refId: requestId,
        });
      }
      Object.assign(escPatch, { status: 'Refunded', refundAmount: refund, refundClaimedAt: now, refundReason: refundTitle });
      notify(tx, db, renteeId, now, refundTitle, `₱${refund.toFixed(2)} was refunded to your wallet.`, requestId.slice(-6));
    }

    tx.set(r.escrow, escPatch, { merge: true });
    if (r.mirror) tx.set(r.mirror, escPatch, { merge: true });
    if (reqSnap.exists) tx.update(r.request, patchReq);
    w.flush();
    const result = { ok: true, status: escPatch.status, refund, payout, commission, rate, deposit: action === 'complete' ? deposit : 0 };
    writeOp(tx, db, uid, key, `booking:${action}`, result, now);
    return result;
  });
}

// ── rentalExtension (vehicle) ──────────────────────────────────────────────────────────────────
export type ExtensionAction = 'request' | 'autoApprove' | 'approve' | 'reject';

/** extensionRatePerHour | latePenaltyRatePerHour | extensionPenaltyPerHour, else 1.5x the hourly daily rate, else 200. */
export function extensionRatePerHour(l: Doc): number {
  for (const k of ['extensionRatePerHour', 'latePenaltyRatePerHour', 'extensionPenaltyPerHour']) {
    if (numOf(l[k]) > 0) return numOf(l[k]);
  }
  if (numOf(l.priceDaily) > 0) return (numOf(l.priceDaily) / 24) * 1.5;
  if (numOf(l.priceHourly) > 0) return numOf(l.priceHourly);
  return 200;
}

export async function rentalExtension(deps: MoneyDeps, auth: CallerAuth | undefined, data: unknown) {
  const uid = requireAuth(auth);
  const d = parseBody(data);
  const key = parseKey(d.idempotencyKey);
  const action = d.action as ExtensionAction;
  if (!['request', 'autoApprove', 'approve', 'reject'].includes(action)) throw new HttpsError('invalid-argument', 'Unknown action.');
  const { db } = deps;
  const now = deps.now();
  const hours = Math.floor(numOf(d.extendHours));
  if ((action === 'request' || action === 'autoApprove') && (hours < 1 || hours > 24 * 30)) throw new HttpsError('invalid-argument', 'Invalid extension length.');

  return db.runTransaction(async (tx) => {
    const replay = await readOp(tx, db, uid, key);
    if (replay) return { ...replay, replay: true };
    const w = new Wallet(tx, db);

    if (action === 'request' || action === 'autoApprove') {
      const requestId = parseId(d.requestId, 'requestId');
      const rentalId = parseId(d.rentalId, 'rentalId');
      const [escSnap, rentalSnap] = await Promise.all([tx.get(db.doc(`rental_escrows/${requestId}`)), tx.get(db.doc(`rentals/${rentalId}`))]);
      await w.load(uid);
      if (!escSnap.exists || !rentalSnap.exists) throw new HttpsError('failed-precondition', 'No active booking found.');
      const e = escSnap.data() as Doc;
      if (e.status !== 'Held' || e.renteeId !== uid) throw new HttpsError('failed-precondition', 'You have no active booking to extend.');
      const fee = round2(extensionRatePerHour(rentalSnap.data() as Doc) * hours);
      w.debit(uid, fee);
      const extId = `ext_${key}`;
      ledger(tx, db, `bk_vehicle_${extId}_hold`, uid, now, {
        type: 'payment', category: 'rental', amount: fee, status: 'Successful',
        title: action === 'autoApprove' ? 'Rental Extension (Auto-Approved)' : 'Rental Extension Request', desc: `Extension of ${hours} hour(s) for vehicle rental`, refId: extId,
      });
      if (action === 'autoApprove') {
        const bump = { amount: round2(numOf(e.amount) + fee), totalPaid: round2(numOf(e.totalPaid, numOf(e.amount) + numOf(e.bookingFee)) + fee), updatedAt: now };
        tx.set(db.doc(`rental_escrows/${requestId}`), bump, { merge: true });
        if (rentalId !== requestId) tx.set(db.doc(`rental_escrows/${rentalId}`), bump, { merge: true });
      } else {
        tx.create(db.doc(`rental_extensions/${extId}`), {
          id: extId, rentalId, requestId, renteeId: uid, hostId: e.hostId ?? '', extendHours: hours, fee, status: 'Pending', createdAt: now,
        });
        tx.create(db.doc(`rental_extension_escrows/${extId}`), {
          extensionId: extId, rentalId, requestId, renteeId: uid, renterId: uid, hostId: e.hostId ?? '', amount: fee, status: 'Held', createdAt: now,
        });
      }
      w.flush();
      const result = { ok: true, extensionId: extId, fee, extendHours: hours, newBalance: w.balance(uid) };
      writeOp(tx, db, uid, key, `extension:${action}`, result, now);
      return result;
    }

    // approve / reject: host (or staff) decides a pending extension
    const extensionId = parseId(d.extensionId, 'extensionId');
    const extRef: DocumentReference = db.doc(`rental_extensions/${extensionId}`);
    const [extSnap, extEscSnap, callerSnap] = await Promise.all([
      tx.get(extRef), tx.get(db.doc(`rental_extension_escrows/${extensionId}`)), tx.get(db.doc(`users/${uid}`)),
    ]);
    if (!extSnap.exists || !extEscSnap.exists) throw new HttpsError('not-found', 'Extension request not found.');
    const x = extSnap.data() as Doc;
    const xe = extEscSnap.data() as Doc;
    const isStaff = tokenIsStaff(auth?.token) || userDocIsStaff(callerSnap.data());
    if (!(uid === x.hostId || isStaff)) throw new HttpsError('permission-denied', 'Only the host can do this.');
    if (x.status !== 'Pending' || xe.status !== 'Held') throw new HttpsError('failed-precondition', 'Extension already processed.');
    const fee = round2(numOf(xe.amount));
    const requestId = String(x.requestId ?? '');
    const rentalId = String(x.rentalId ?? '');
    if (action === 'approve') {
      const mainSnap = requestId ? await tx.get(db.doc(`rental_escrows/${requestId}`)) : null;
      if (!mainSnap?.exists || mainSnap.get('status') !== 'Held') throw new HttpsError('failed-precondition', 'The booking is no longer active.');
      const m = mainSnap.data() as Doc;
      const bump = { amount: round2(numOf(m.amount) + fee), totalPaid: round2(numOf(m.totalPaid, numOf(m.amount) + numOf(m.bookingFee)) + fee), updatedAt: now };
      tx.set(db.doc(`rental_escrows/${requestId}`), bump, { merge: true });
      if (rentalId && rentalId !== requestId) tx.set(db.doc(`rental_escrows/${rentalId}`), bump, { merge: true });
      tx.update(extRef, { status: 'Approved', approvedAt: now });
      tx.update(extEscSnap.ref, { status: 'Merged', mergedAt: now });
      const result = { ok: true, extensionId, fee, status: 'Approved', extendHours: numOf(x.extendHours) };
      writeOp(tx, db, uid, key, 'extension:approve', result, now);
      return result;
    }
    await w.load(String(xe.renteeId));
    w.credit(String(xe.renteeId), fee);
    ledger(tx, db, `bk_vehicle_${extensionId}_refund`, String(xe.renteeId), now, {
      type: 'refund', category: 'refund', amount: fee, title: 'Rental Extension Refund', desc: 'Extension request rejected by host', originRail: 'internal_balance', refId: extensionId,
    });
    tx.update(extRef, { status: 'Rejected', rejectedAt: now });
    tx.update(extEscSnap.ref, { status: 'Refunded', refundAmount: fee, refundClaimedAt: now });
    w.flush();
    const result = { ok: true, extensionId, fee, status: 'Rejected' };
    writeOp(tx, db, uid, key, 'extension:reject', result, now);
    return result;
  });
}

// ── listing fee ────────────────────────────────────────────────────────────────────────────────
/** charge: host pays settings/platform_fees.listingFeeRate x daily price (0 today = no-op). refund: returns what was recorded here. */
export async function listingFee(deps: MoneyDeps, auth: CallerAuth | undefined, data: unknown) {
  const uid = requireAuth(auth);
  const d = parseBody(data);
  const key = parseKey(d.idempotencyKey);
  const kind = parseKind(d.kind);
  const listingId = parseId(d.listingId, 'listingId');
  const op = d.op === 'refund' ? 'refund' : d.op === 'charge' ? 'charge' : null;
  if (!op) throw new HttpsError('invalid-argument', "op must be 'charge' or 'refund'.");
  const c = C[kind];
  const { db } = deps;
  const now = deps.now();

  return db.runTransaction(async (tx) => {
    const replay = await readOp(tx, db, uid, key);
    if (replay) return { ...replay, replay: true };
    const feeRef = db.doc(`listing_fees/${kind}_${listingId}`);
    const [lSnap, fSnap, recSnap] = await Promise.all([tx.get(db.doc(`${c.listing}/${listingId}`)), tx.get(db.doc('settings/platform_fees')), tx.get(feeRef)]);
    if (!lSnap.exists) throw new HttpsError('not-found', 'Listing not found.');
    const l = lSnap.data() as Doc;
    const callerSnap = await tx.get(db.doc(`users/${uid}`));
    if (l.hostId !== uid && !(tokenIsStaff(auth?.token) || userDocIsStaff(callerSnap.data()))) throw new HttpsError('permission-denied', 'Not your listing.');
    const w = new Wallet(tx, db);
    let amount = 0;
    if (op === 'charge') {
      if (recSnap.exists) {
        const same = { ok: true, amount: 0, alreadyCharged: true };
        writeOp(tx, db, uid, key, 'listingFee:charge', same, now);
        return same;
      }
      const rate = numOf((fSnap.exists ? fSnap.data() : {})?.listingFeeRate, 0);
      const daily = numOf(l.priceDaily ?? l.dailyRate);
      const monthly = numOf(l.priceMonthly ?? l.monthlyRate);
      const basis = kind === 'property' ? (monthly > 0 ? monthly : daily * 30) : daily;
      amount = round2(rate * basis);
      if (amount > 0) {
        await w.load(uid);
        w.debit(uid, amount);
        ledger(tx, db, `bk_${kind}_${listingId}_listing_fee`, uid, now, {
          type: 'listing_fee', amount, listingFeeRate: rate, title: `${c.label} Listing Fee`, desc: `${(rate * 100).toFixed(1)}% posting fee`, status: 'Completed',
        });
      }
      tx.create(feeRef, { uid, kind, listingId, amount, status: 'paid', createdAt: now });
    } else {
      if (!recSnap.exists || recSnap.get('status') !== 'paid') {
        const none = { ok: true, amount: 0, nothingToRefund: true };
        writeOp(tx, db, uid, key, 'listingFee:refund', none, now);
        return none;
      }
      amount = round2(numOf(recSnap.get('amount')));
      const payer = String(recSnap.get('uid'));
      if (amount > 0) {
        await w.load(payer);
        w.credit(payer, amount);
        ledger(tx, db, `bk_${kind}_${listingId}_listing_refund`, payer, now, {
          type: 'refund', category: 'refund', amount, title: `${c.label} Listing Fee Refund`, desc: 'Listing removed before any confirmed booking', originRail: 'internal_balance',
        });
      }
      tx.update(feeRef, { status: 'refunded', refundedAt: now });
    }
    w.flush();
    const result = { ok: true, amount };
    writeOp(tx, db, uid, key, `listingFee:${op}`, result, now);
    return result;
  });
}

export type { Transaction };
