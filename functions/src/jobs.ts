import { HttpsError } from 'firebase-functions/https';
import {
  ledger, notify, numOf, parseId, parseKey, readOp, requireAuth, round2, str, Wallet, writeOp, type CallerAuth, type MoneyDeps,
} from './money';
import { promoDiscount } from './pricing';

/**
 * Phase 4 jobs / gigs. `escrow/{jobId}` is server-owned (Admin SDK only); amounts come from the
 * escrow snapshot written at creation (price, fee rates, commission), never from client fields.
 *
 *   create     employer pays discounted price + employer fees up front -> job doc + escrow {status:'held'}
 *   accept     hire an applicant; a counter offer adjusts the held amount (diff in total employer cost)
 *   complete   verification code ok -> worker payout (price - commission - holdback) from escrow, once
 *   cancel     employer, before the worker acknowledges -> full escrow (price + fees) back, once
 *   reclaim    employer, 48h stale -> refund + Abandoned;  delete  employer, open job -> refund + remove
 *   releaseHoldbacks  worker claims their own holdbacks whose releaseAt passed
 * Staff arbitration (disputes, admin override cancel) stays staff-only client writes under isAdminOrStaff().
 */

type Doc = Record<string, any>;
const ACTIONS = ['create', 'accept', 'complete', 'cancel', 'reclaim', 'delete', 'releaseHoldbacks'] as const;
type Action = (typeof ACTIONS)[number];
const HOUR = 3_600_000;
const SERVER_JOB_KEYS = new Set([
  'id', 'status', 'creatorId', 'pricingValue', 'createdAt', 'updatedAt', 'applicantCount', 'recentApplicantPhotos', 'applicantUids',
  'transactionFeeRate', 'convenienceFeeRate', 'serviceFeeRate', 'markupRate', 'commissionRate', 'employerFees', 'totalEscrowed',
  'promoCode', 'discountAmount', 'acceptedApplicantId', 'acceptedApplicantName', 'hiredAt', 'completionCode', 'verificationCode',
  'hasInspectionHoldback', 'hasTracker', 'acknowledgmentStatus', 'acknowledgmentDeadline', 'escrowStatus',
]);
const ACK_KEYS = ['acknowledgmentDeadline', 'acknowledgmentSlaMinutes', 'acknowledgmentCategory', 'acknowledgmentStatus', 'acknowledgmentReminderSent'];

function clientFields(raw: unknown): Doc {
  const out: Doc = {};
  if (!raw || typeof raw !== 'object') return out;
  for (const [k, v] of Object.entries(raw as Doc)) {
    if (SERVER_JOB_KEYS.has(k) || k.includes('/') || k.startsWith('__')) continue;
    if (v === null || ['string', 'number', 'boolean'].includes(typeof v) || Array.isArray(v)) out[k] = typeof v === 'string' ? v.slice(0, 5000) : v;
  }
  return out;
}

const ms = (v: unknown): number => {
  if (typeof v === 'number') return v;
  if (v && typeof v === 'object' && typeof (v as { toMillis?: unknown }).toMillis === 'function') return (v as { toMillis(): number }).toMillis();
  return 0;
};

export function employerCost(price: number, discount: number, tx: number, conv: number) {
  const discounted = Math.min(Math.max(price - discount, 0), 999_999);
  const fees = round2(discounted * tx + discounted * conv);
  return { discounted: round2(discounted), fees, total: round2(discounted + fees) };
}

export async function jobAction(deps: MoneyDeps, auth: CallerAuth | undefined, data: unknown) {
  const uid = requireAuth(auth);
  const d = (data && typeof data === 'object' ? data : {}) as Doc;
  const key = parseKey(d.idempotencyKey);
  const action = d.action as Action;
  if (!ACTIONS.includes(action)) throw new HttpsError('invalid-argument', 'Unknown action.');
  const { db } = deps;
  const now = deps.now();

  return db.runTransaction(async (tx) => {
    const replay = await readOp(tx, db, uid, key);
    if (replay) return { ...replay, replay: true };
    const w = new Wallet(tx, db);
    const done = (result: Record<string, unknown>) => { writeOp(tx, db, uid, key, `job:${action}`, result, now); return result; };

    // ── create ───────────────────────────────────────────────────────────────────────────────
    if (action === 'create') {
      const raw = (d.job ?? {}) as Doc;
      const price = numOf(raw.pricingValue);
      if (!(price > 0) || price > 999_999) throw new HttpsError('invalid-argument', 'Invalid gig price.');
      const promoCode = str(raw.promoCode, 40).toUpperCase();
      // No underscore / no 'job_' prefix: clients parse chat ids like job_{jobId}_{uid} by splitting on '_'.
      const jobId = `jb${key.replace(/[^A-Za-z0-9]/g, '')}`;
      const [feeSnap, promoSnap] = await Promise.all([tx.get(db.doc('settings/platform_fees')), promoCode ? tx.get(db.doc(`promos/${promoCode}`)) : Promise.resolve(null)]);
      await w.load(uid);
      if (!w.exists(uid)) throw new HttpsError('failed-precondition', 'Profile not found.');
      const f = (feeSnap.exists ? feeSnap.data() : {}) as Doc;
      const txRate = numOf(f.transactionFeeRate ?? f.txFeeRate, 0.07);
      const convRate = numOf(f.convenienceFeeRate ?? f.convFeeRate, 0.03);
      const holdbackRate = numOf(f.holdbackRate, 0.1);
      const commissionRate = numOf(f.commissionRate ?? f.platformCommissionRate, 0.03);
      let discount = 0;
      if (promoCode) {
        const dsc = promoDiscount(promoSnap?.exists ? (promoSnap.data() as Doc) : undefined, { base: price, fee: price * (txRate + convRate), uid, now, module: 'jobs' });
        if (dsc == null) throw new HttpsError('failed-precondition', 'This promo code cannot be used.', { code: 'PROMO_INVALID' });
        discount = dsc;
      }
      const c = employerCost(price, discount, txRate, convRate);
      w.debit(uid, c.total);
      const hasHoldback = raw.hasInspectionHoldback === true;
      const hasTracker = raw.hasTracker === true;
      const jobRef = db.doc(`jobs/${jobId}`);
      if ((await tx.get(jobRef)).exists) throw new HttpsError('already-exists', 'This gig was already posted.');
      tx.create(jobRef, {
        ...clientFields(raw), id: jobId, creatorId: uid, status: 'Open', createdAt: now, pricingValue: price,
        applicantCount: 0, recentApplicantPhotos: [], applicantUids: [], hasTracker, hasInspectionHoldback: hasHoldback,
        transactionFeeRate: txRate, convenienceFeeRate: convRate, commissionRate, employerFees: c.fees, totalEscrowed: c.total,
        ...(promoCode ? { promoCode, discountAmount: discount } : {}),
      });
      tx.create(db.doc(`escrow/${jobId}`), {
        amount: c.discounted, price, employerFees: c.fees, totalEscrowed: c.total, transactionFee: round2(c.discounted * txRate),
        convenienceFee: round2(c.discounted * convRate), transactionFeeRate: txRate, convenienceFeeRate: convRate, commissionRate,
        discountAmount: discount, holdbackRate, employerId: uid, creatorId: uid, status: 'held', createdAt: now, updatedAt: now,
        hasInspectionHoldback: hasHoldback, ...(hasHoldback ? { holdbackAmount: round2(price * holdbackRate) } : {}),
      });
      ledger(tx, db, `job_escrow_${jobId}`, uid, now, {
        type: 'payment', category: 'escrow_funding', amount: c.total, title: 'Gig Escrow & Platform Fees', status: 'Successful',
        desc: `Funded escrow for gig (₱${c.discounted.toFixed(2)} gig payout + ₱${c.fees.toFixed(2)} fees)`, jobId,
        jobPrice: price, discountedPrice: c.discounted, employerFees: c.fees, totalRequired: c.total, transactionFeeRate: txRate, convenienceFeeRate: convRate,
      });
      if (promoSnap?.exists) {
        const p = promoSnap.data() as Doc;
        tx.update(promoSnap.ref, { usedBy: [...(Array.isArray(p.usedBy) ? p.usedBy : []), uid], usedCount: numOf(p.usedCount) + 1 });
      }
      w.flush();
      return done({ ok: true, jobId, total: c.total, fees: c.fees, discount, newBalance: w.balance(uid) });
    }

    // ── releaseHoldbacks (worker claims own due holdbacks) ────────────────────────────────────
    if (action === 'releaseHoldbacks') {
      const snap = await tx.get(db.collection('escrow_holdbacks').where('nyxianId', '==', uid));
      const me = await w.load(uid);
      const due = snap.docs.filter((s) => s.get('status') === 'held' && ms(s.get('releaseAt')) <= now);
      const total = round2(due.reduce((a, s) => a + numOf(s.get('amount')), 0));
      if (total > 0) {
        w.credit(uid, total);
        for (const s of due) tx.update(s.ref, { status: 'released', releasedAt: now });
        ledger(tx, db, `holdback_${uid}_${key}`, uid, now, { type: 'payout', category: 'payout', amount: total, title: 'Inspection Holdback Released', desc: `Released ${due.length} holdback(s)`, status: 'Successful' });
        w.flush({ [uid]: { totalEarned: round2(numOf(me.totalEarned) + total) } });
      }
      return done({ ok: true, released: due.length, total });
    }

    // ── everything else is per job ───────────────────────────────────────────────────────────
    const jobId = parseId(d.jobId, 'jobId');
    const jobRef = db.doc(`jobs/${jobId}`);
    const escRef = db.doc(`escrow/${jobId}`);
    const [jobSnap, escSnap] = await Promise.all([tx.get(jobRef), tx.get(escRef)]);
    if (!jobSnap.exists) throw new HttpsError('not-found', 'Gig not found.');
    const job = jobSnap.data() as Doc;
    const esc = (escSnap.exists ? escSnap.data() : null) as Doc | null;
    const status = String(job.status ?? '').toLowerCase();
    const employerId = str(job.creatorId, 128);
    const workerId = str(job.acceptedApplicantId ?? job.nyxianId, 128);
    const escHeld = !!esc && String(esc.status).toLowerCase() === 'held';

    if (action === 'accept') {
      if (uid !== employerId) throw new HttpsError('permission-denied', 'Only the employer can hire.');
      if (status !== 'open') throw new HttpsError('failed-precondition', 'This gig is no longer open.');
      if (!escHeld) throw new HttpsError('failed-precondition', 'No funds are held for this gig.');
      const applicantUid = parseId(d.applicantUid, 'applicantUid');
      const appSnap = await tx.get(db.doc(`jobs/${jobId}/applications/${applicantUid}`));
      if (!appSnap.exists) throw new HttpsError('failed-precondition', 'This applicant has no application on this gig.');
      const app = appSnap.data() as Doc;
      await w.load(employerId);
      const original = numOf(esc!.price, numOf(job.pricingValue));
      const rate = numOf(app.proposalRate);
      let finalPrice = original;
      let diff = 0;
      const txRate = numOf(esc!.transactionFeeRate, 0.07);
      const convRate = numOf(esc!.convenienceFeeRate, 0.03);
      const discount = numOf(esc!.discountAmount);
      if (app.isCounterOffer === true) {
        const min = Math.round((original * 0.8 + 1e-9) * 100) / 100;
        const max = Math.round((original * 1.5 + 1e-9) * 100) / 100;
        if (!(rate > 0) || rate < min || rate > max) throw new HttpsError('failed-precondition', 'The counter offer is outside the allowed range.');
        finalPrice = rate;
        diff = round2(employerCost(rate, discount, txRate, convRate).total - employerCost(original, discount, txRate, convRate).total);
      }
      if (!(finalPrice > 0)) throw new HttpsError('failed-precondition', 'Transaction price must be greater than 0.');
      const nc = employerCost(finalPrice, discount, txRate, convRate);
      if (diff > 0) {
        w.debit(employerId, diff);
        ledger(tx, db, `counter_offer_${jobId}_${applicantUid}_${Math.round(rate * 100)}`, employerId, now, {
          type: 'payment', category: 'escrow_funding', amount: diff, title: 'Gig Counter Offer Adjustment', desc: `Additional funds for accepted counter offer on job ${jobId}`, status: 'Successful', jobId,
        });
      } else if (diff < 0) {
        w.credit(employerId, -diff);
        ledger(tx, db, `counter_offer_${jobId}_${applicantUid}_${Math.round(rate * 100)}`, employerId, now, {
          type: 'refund', category: 'refund', amount: -diff, title: 'Gig Counter Offer Adjustment', desc: `Escrow reduced for accepted counter offer on job ${jobId}`, originRail: 'internal_balance', jobId,
        });
      }
      const holdbackRate = numOf(esc!.holdbackRate, 0.1);
      tx.update(escRef, {
        price: finalPrice, amount: nc.discounted, employerFees: nc.fees, totalEscrowed: nc.total, workerId: applicantUid, updatedAt: now,
        ...(esc!.hasInspectionHoldback ? { holdbackAmount: round2(finalPrice * holdbackRate) } : {}),
      });
      const ack: Doc = {};
      const patch = (d.jobPatch ?? {}) as Doc;
      for (const k of ACK_KEYS) if (patch[k] !== undefined && ['string', 'number', 'boolean'].includes(typeof patch[k])) ack[k] = patch[k];
      tx.update(jobRef, {
        ...ack, status: 'Awaiting Acknowledgment', acceptedApplicantId: applicantUid, acceptedApplicantName: str(app.applicantName, 120) || 'Nyxian',
        hiredAt: now, updatedAt: now, pricingValue: finalPrice, ...(app.isCounterOffer === true ? { pricingType: 'Fixed Task' } : {}),
        totalEscrowed: nc.total, employerFees: nc.fees,
      });
      w.flush();
      return done({ ok: true, jobId, price: finalPrice, adjustment: diff, newBalance: w.balance(employerId) });
    }

    if (action === 'complete') {
      if (status === 'completed') throw new HttpsError('failed-precondition', 'This gig is already completed.');
      if (!escHeld) throw new HttpsError('failed-precondition', 'No funds are held for this gig.');
      const correct = str(job.completionCode ?? job.verificationCode, 64);
      if (!correct || str(d.verificationCode, 64) !== correct) throw new HttpsError('failed-precondition', 'Invalid or expired verification code.');
      if (!workerId) throw new HttpsError('failed-precondition', 'No worker is assigned to this gig.');
      const hasTracker = job.hasTracker === true || job.hasTracker === 'true';
      if (hasTracker ? uid !== employerId : uid !== workerId) {
        throw new HttpsError('permission-denied', hasTracker ? 'Only the employer can verify this gig.' : 'Only the assigned worker can complete this gig.');
      }
      const workerSnapData = await w.load(workerId);
      await w.load(employerId);
      const promoCode = str(workerSnapData.activePromoCode, 40).toUpperCase();
      const promoSnap = promoCode ? await tx.get(db.doc(`promos/${promoCode}`)) : null;
      const price = numOf(esc!.price, numOf(job.pricingValue));
      const commissionRate = numOf(esc!.commissionRate, 0.03);
      const platformFee = round2(price * commissionRate);
      let actualFee = platformFee;
      let redeemed: string | null = null;
      if (promoSnap?.exists) {
        const dsc = promoDiscount(promoSnap.data() as Doc, { base: price, fee: platformFee, uid: workerId, now, module: 'jobs' });
        if (dsc != null && dsc > 0) { actualFee = round2(platformFee - dsc); redeemed = promoCode; }
      }
      const hasHoldback = esc!.hasInspectionHoldback === true;
      const holdback = hasHoldback ? round2(numOf(esc!.holdbackAmount, price * numOf(esc!.holdbackRate, 0.1))) : 0;
      const immediate = round2(price - actualFee - holdback);
      w.credit(workerId, immediate);
      const gigs = numOf(workerSnapData.completedGigsCount) + 1;
      const workerPatch: Doc = {
        jobsDone: numOf(workerSnapData.jobsDone) + 1,
        totalEarned: round2(numOf(workerSnapData.totalEarned) + immediate),
        completedGigsCount: gigs, repeatHireRate: gigs > 1 ? 0.35 : 0, lastCompletedJobId: jobId,
        ...(redeemed ? { activePromoCode: null, activePromoDiscountType: null, activePromoDiscountValue: null } : {}),
      };
      if (redeemed && promoSnap?.exists) {
        const p = promoSnap.data() as Doc;
        tx.update(promoSnap.ref, { usedBy: [...(Array.isArray(p.usedBy) ? p.usedBy : []), workerId], usedCount: numOf(p.usedCount) + 1 });
      }
      const txRate = numOf(esc!.transactionFeeRate, 0.07);
      const convRate = numOf(esc!.convenienceFeeRate, 0.03);
      const preFunded = numOf(esc!.employerFees) > 0;
      const discounted = numOf(esc!.amount);
      const txFee = round2(discounted * txRate);
      const convFee = round2(discounted * convRate);
      const totalFees = round2(txFee + convFee);
      if (!preFunded) w.debit(employerId, Math.min(totalFees, w.available(employerId)));
      ledger(tx, db, `payout_nyx_${jobId}`, workerId, now, {
        type: 'payout', title: 'Gig Payout Released', status: 'Successful', amount: immediate, baseAmount: price, commissionFee: actualFee, commissionRate,
        holdbackAmount: holdback, holdbackRate: numOf(esc!.holdbackRate, 0.1), ...(redeemed ? { promoCode: redeemed } : {}),
        desc: `Payout for completing job ${jobId} (${(commissionRate * 100).toFixed(0)}% commission deducted${redeemed ? ` - Promo ${redeemed} applied` : ''})`,
      });
      ledger(tx, db, `fees_emp_${jobId}`, employerId, now, {
        type: 'fee_deduction', title: preFunded ? 'Job Platform Fees Settled' : 'Job Completion Fees', status: 'Successful', amount: totalFees, baseAmount: discounted,
        transactionFee: txFee, convenienceFee: convFee, transactionFeeRate: txRate, convenienceFeeRate: convRate, discountAmount: numOf(esc!.discountAmount),
        method: preFunded ? 'Tranyx Escrow' : 'Tranyx Wallet', desc: `Transaction and convenience fees for job ${jobId}`,
      });
      const income = round2(actualFee + totalFees);
      tx.set(db.doc(`platform_fees/${jobId}`), {
        jobId, amount: income, commissionFee: actualFee, transactionFee: txFee, convenienceFee: convFee, transactionFeeRate: txRate, convenienceFeeRate: convRate,
        employerFees: totalFees, nyxianFee: actualFee, totalFees: income, timestamp: now,
      });
      if (hasHoldback && holdback > 0) {
        tx.set(db.doc(`escrow_holdbacks/${jobId}`), {
          jobId, amount: holdback, nyxianId: workerId, employerId, status: 'held', createdAt: now, releaseAt: now + 48 * HOUR,
        });
      }
      tx.update(escRef, { status: 'released', releasedAt: now, releasedTo: workerId, payout: immediate, updatedAt: now });
      tx.update(jobRef, { status: 'Completed', updatedAt: now });
      notify(tx, db, uid === employerId ? workerId : employerId, now, 'Gig Completed', `Gig "${str(job.title, 80)}" was marked complete.`, jobId.slice(-6));
      w.flush({ [workerId]: workerPatch });
      return done({ ok: true, jobId, payout: immediate, holdback, commission: actualFee, newBalance: w.balance(uid) });
    }

    // cancel | reclaim | delete: refund the full escrow (price + employer fees) to the employer, once
    if (uid !== employerId) throw new HttpsError('permission-denied', 'Only the employer can do this.');
    if (['completed', 'cancelled', 'admin_cancelled'].includes(status) || (action === 'reclaim' && status === 'abandoned')) {
      throw new HttpsError('failed-precondition', 'This gig can no longer be changed this way.');
    }
    const acknowledged = job.acknowledgmentStatus === 'acknowledged';
    if (action === 'cancel' && ((!!workerId && acknowledged) || status === 'in progress' || status === 'in_progress' || job.status === 'MUTUAL_CANCEL_PENDING')) {
      throw new HttpsError('failed-precondition', 'The worker has already committed to this gig.', { code: 'JOB_ALREADY_COMMITTED' });
    }
    if (action === 'delete' && escHeld && status !== 'open') {
      throw new HttpsError('failed-precondition', 'Only an open gig can be deleted while funds are held.');
    }
    if (action === 'reclaim') {
      const last = Math.max(ms(job.updatedAt), ms(job.createdAt), esc ? ms(esc.updatedAt) : 0);
      if (now - last < 48 * HOUR) throw new HttpsError('failed-precondition', 'The 48-hour inactivity threshold has not been reached.', { code: 'JOB_NOT_STALE' });
    }
    await w.load(employerId);
    const apps = action === 'cancel' ? await tx.get(db.collection(`jobs/${jobId}/applications`)) : null;
    const promoCode = str(job.promoCode, 40).toUpperCase();
    const promoSnap = promoCode ? await tx.get(db.doc(`promos/${promoCode}`)) : null;
    const workerSnap = action === 'reclaim' && workerId ? await w.load(workerId) : null;
    let refund = 0;
    let workerExtra: Record<string, Record<string, unknown>> | undefined;
    if (escHeld) {
      refund = round2(numOf(esc!.amount) + numOf(esc!.employerFees));
      if (refund > 0) {
        w.credit(employerId, refund);
        ledger(tx, db, `refund_job_${jobId}`, employerId, now, {
          type: 'refund', category: 'refund', amount: refund, title: 'Job Escrow Refund', desc: `100% escrow refund for ${action === 'delete' ? 'deleted' : action === 'reclaim' ? 'reclaimed' : 'cancelled'} job "${str(job.title, 80)}"`,
          method: 'Tranyx Escrow', originRail: 'internal_balance', jobId,
        });
      }
      if (action === 'delete') tx.delete(escRef);
      else tx.update(escRef, { status: 'refunded', refundAmount: refund, refundedAt: now, refundedTo: employerId, updatedAt: now });
    }
    if (promoSnap?.exists && escHeld) {
      const p = promoSnap.data() as Doc;
      const used: unknown[] = Array.isArray(p.usedBy) ? [...p.usedBy] : [];
      const i = used.indexOf(employerId);
      if (i >= 0) used.splice(i, 1);
      tx.update(promoSnap.ref, { usedBy: used, usedCount: Math.max(0, numOf(p.usedCount, 1) - 1) });
    }
    if (action === 'delete') {
      tx.delete(jobRef);
    } else if (action === 'reclaim') {
      tx.update(jobRef, { status: 'Abandoned', updatedAt: now, abandonedAt: now, abandonReason: str(d.reason, 300) || 'Job reclaimed by employer due to 48+ hours of inactivity' });
      if (workerSnap && w.exists(workerId)) workerExtra = { [workerId]: { abandonedJobs: numOf(workerSnap.abandonedJobs) + 1 } };
    } else {
      tx.update(jobRef, { status: 'Cancelled', updatedAt: now });
      for (const a of apps!.docs) tx.update(a.ref, { status: 'REJECTED_JOB_CANCELLED' });
    }
    tx.set(db.collection('job_cancellation_logs').doc(), {
      jobId, cancelledBy: uid, role: 'employer', action: action === 'reclaim' ? 'RECLAIM_INACTIVE_JOB' : action === 'delete' ? 'DELETE_JOB' : 'UNILATERAL_CANCEL',
      status: action === 'reclaim' ? 'ABANDONED' : 'CANCELLED', reason: str(d.reason, 300) || 'Employer action', previousStatus: job.status ?? 'Open',
      acceptedApplicantId: workerId || null, timestamp: now,
    });
    w.flush(workerExtra);
    return done({ ok: true, jobId, refund, newBalance: w.balance(employerId) });
  });
}
