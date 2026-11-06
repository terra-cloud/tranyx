import { FieldValue, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/https';
import { numOf, requireAuth, str, type CallerAuth, type MoneyDeps } from './money';

/**
 * Quest points. Amounts and once/unlimited limits mirror packages/shared RewardQuest.
 * The client sends a quest id and, for a repeatable quest, the id of the event. It cannot send
 * an amount or an eligibility flag. The award document id is the once-only gate.
 *
 * Profile booleans the owner can write (emailVerified, phoneVerified, idVerified) do not qualify.
 * Email and phone proof come from the Auth token. A linked wallet must be wallet_verified.
 * Identity-trust points are not granted: there is no server KYC record an owner cannot write.
 */
const QUESTS: Record<string, { points: number; once: boolean; title: string; category: string }> = {
  register_account: { points: 500, once: true, title: 'Register Account', category: 'Onboarding' },
  verify_account: { points: 500, once: true, title: 'Verify Account', category: 'Onboarding' },
  complete_profile_trust: { points: 2000, once: true, title: 'Complete Profile Trust and Verification', category: 'Onboarding' },
  add_skills_bio: { points: 100, once: true, title: 'Add Skills & Bio', category: 'Onboarding' },
  deposit_any_amount: { points: 500, once: true, title: 'Deposit any amount to Wallet', category: 'Onboarding' },
  connect_solana_wallet: { points: 200, once: true, title: 'Connect Any Solana Wallet', category: 'Onboarding' },
  subscribe_hybrid_pro: { points: 15000, once: true, title: 'Subscribe to Hybrid PRO', category: 'Onboarding' },
  post_first_service: { points: 500, once: true, title: 'Post First Service', category: 'Services' },
  hire_applicant: { points: 500, once: true, title: 'Hire an Applicant', category: 'Services' },
  employer_complete_transaction: { points: 500, once: false, title: 'Complete transaction as employer', category: 'Services' },
  apply_first_job: { points: 500, once: true, title: 'Apply First Job', category: 'Services' },
  be_hired: { points: 500, once: true, title: 'Be hired', category: 'Services' },
  jobseeker_complete_transaction: { points: 500, once: false, title: 'Complete transaction as Nyxian', category: 'Services' },
  post_property: { points: 500, once: false, title: 'Post Property', category: 'Rental' },
  host_complete_transaction: { points: 500, once: false, title: 'Complete Transaction as a Lessor/Host', category: 'Rental' },
  rent_property: { points: 500, once: false, title: 'Rent property', category: 'Rental' },
  client_complete_transaction: { points: 500, once: false, title: 'Complete transaction as a Lessee/Renter', category: 'Rental' },
};

const completed = (status: unknown) => String(status ?? '').toLowerCase() === 'completed';

function hasSkillsOrHeadline(u: Record<string, unknown>): boolean {
  const skills = u.skills;
  const headline = typeof u.headline === 'string' ? u.headline.trim() : '';
  return (Array.isArray(skills) && skills.length > 0) || headline.length > 0;
}

async function eligible(db: Firestore, tx: Transaction, uid: string, questId: string, eventId: string, token: Record<string, unknown> | undefined, user: Record<string, unknown>): Promise<boolean> {
  const job = async (id: string) => (id ? (await tx.get(db.doc(`jobs/${id}`))).data() : undefined);
  switch (questId) {
    case 'register_account':
      return true;
    case 'verify_account':
      return token?.email_verified === true && typeof token?.phone_number === 'string' && token.phone_number.trim().length > 0;
    case 'complete_profile_trust':
      return false;
    case 'add_skills_bio':
      return hasSkillsOrHeadline(user);
    case 'deposit_any_amount':
      return numOf(user.tyxBalance) > 0;
    case 'connect_solana_wallet': {
      const wallet = typeof user.walletPublicKey === 'string' ? user.walletPublicKey.trim() : '';
      if (!wallet || wallet.includes('/')) return false;
      const ver = await tx.get(db.doc(`wallet_verified/${wallet}`));
      return ver.exists && ver.get('uid') === uid;
    }
    case 'subscribe_hybrid_pro':
      return user.isPremium === true;
    case 'post_first_service': {
      if (eventId) {
        const j = await job(eventId);
        return !!j && j.creatorId === uid;
      }
      const q = await tx.get(db.collection('jobs').where('creatorId', '==', uid).limit(1));
      return !q.empty;
    }
    case 'apply_first_job': {
      if (eventId) return (await tx.get(db.doc(`jobs/${eventId}/applications/${uid}`))).exists;
      const q = await tx.get(db.collectionGroup('applications').where('applicantUid', '==', uid).limit(1));
      return !q.empty;
    }
    case 'hire_applicant': {
      if (!eventId) return false;
      const j = await job(eventId);
      return !!j && j.creatorId === uid && typeof j.acceptedApplicantId === 'string' && j.acceptedApplicantId.length > 0;
    }
    case 'be_hired': {
      if (eventId) {
        const j = await job(eventId);
        return !!j && j.acceptedApplicantId === uid;
      }
      const q = await tx.get(db.collection('jobs').where('acceptedApplicantId', '==', uid).limit(1));
      return !q.empty;
    }
    case 'employer_complete_transaction': {
      const j = await job(eventId);
      return !!j && j.creatorId === uid && completed(j.status);
    }
    case 'jobseeker_complete_transaction': {
      const j = await job(eventId);
      return !!j && j.acceptedApplicantId === uid && completed(j.status);
    }
    case 'post_property': {
      if (!eventId) return false;
      const [rental, property] = await Promise.all([tx.get(db.doc(`rentals/${eventId}`)), tx.get(db.doc(`properties/${eventId}`))]);
      return (rental.exists && rental.get('hostId') === uid) || (property.exists && property.get('hostId') === uid);
    }
    case 'rent_property':
    case 'client_complete_transaction':
    case 'host_complete_transaction': {
      if (!eventId) return false;
      const [vehicle, property] = await Promise.all([
        tx.get(db.doc(`rental_requests/${eventId}`)),
        tx.get(db.doc(`property_requests/${eventId}`)),
      ]);
      const doc = vehicle.exists ? vehicle : property;
      if (!doc.exists) return false;
      const party = questId === 'host_complete_transaction' ? doc.get('hostId') === uid : doc.get('renteeId') === uid || doc.get('renterId') === uid;
      if (!party) return false;
      if (questId === 'rent_property') return true;
      return completed(doc.get('status'));
    }
    default:
      return false;
  }
}

export async function awardPoints(deps: MoneyDeps, auth: CallerAuth | undefined, data: unknown) {
  const uid = requireAuth(auth);
  const d = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  const questId = str(d.questId, 64);
  const quest = QUESTS[questId];
  if (!quest) throw new HttpsError('invalid-argument', 'Unknown quest.');
  if (d.points !== undefined || d.amount !== undefined || d.eligible !== undefined || d.terraPoints !== undefined) {
    throw new HttpsError('invalid-argument', 'Points and eligibility are not client fields.');
  }
  const eventId = str(d.eventId, 128);
  if (!quest.once && !eventId) throw new HttpsError('invalid-argument', 'This quest needs the id of the event.');
  if (eventId && (eventId.includes('/') || !/^[A-Za-z0-9_-]{1,128}$/.test(eventId))) {
    throw new HttpsError('invalid-argument', 'eventId is invalid.');
  }
  const awardId = quest.once ? `${uid}_${questId}` : `${uid}_${questId}_${eventId}`;
  const { db } = deps;
  const now = deps.now();

  return db.runTransaction(async (tx) => {
    const userRef = db.doc(`users/${uid}`);
    const awardRef = db.doc(`points_awards/${awardId}`);
    const [userSnap, awardSnap] = await Promise.all([tx.get(userRef), tx.get(awardRef)]);
    if (!userSnap.exists) throw new HttpsError('failed-precondition', 'Profile not found.');
    const user = userSnap.data() as Record<string, unknown>;
    const balance = numOf(user.terraPoints);
    if (awardSnap.exists) {
      return { awarded: false, alreadyAwarded: true, questId, points: numOf(awardSnap.get('points')), terraPoints: balance };
    }
    const ok = await eligible(db, tx, uid, questId, eventId, auth?.token, user);
    if (!ok) return { awarded: false, alreadyAwarded: false, questId, points: 0, terraPoints: balance };
    const next = balance + quest.points;
    tx.update(userRef, { terraPoints: next, earnedRewards: FieldValue.arrayUnion(questId) });
    tx.create(awardRef, { uid, questId, eventId: eventId || null, points: quest.points, createdAt: now });
    tx.create(db.doc(`points_history/${awardId}`), {
      uid, questId, eventId: eventId || null, points: quest.points, title: quest.title, category: quest.category, createdAt: now,
    });
    return { awarded: true, alreadyAwarded: false, questId, points: quest.points, terraPoints: next };
  });
}
