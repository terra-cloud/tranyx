// Chat/support staff + probe suite (Kelvin, Oct 22 2026, review of fix/chat-rules 2902ace / rules fa46ec61).
// Admin desk access paths (tranyx_admin_portal): chats.dart:198 lists ALL support_chats, :226 messages orderBy(createdAt),
// :822 reply {senderId, senderName, content, createdAt, isStaff, agentEmail}, :831/:397/:429 merge desk fields,
// dashboard.dart:1131/1135 list support_chats + chats, disputes.dart:266/275 system message into chats/<jobId>,
// withdrawals.dart:711 / ticket_email_service.dart:417 create notifications. All gated by isAdminOrStaff().
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, where, orderBy, setDoc, updateDoc, addDoc, serverTimestamp } from 'firebase/firestore';
import { knownHole, setupEnv, seed, user, adminClaim, userProfile, job, property } from './helpers.mjs';

setupEnv();
const now = () => Date.now();
const JOB = 'chats/job_j1_worker', LEGACY = 'chats/j1', RENTAL = 'chats/rental_r1_renter';
const base = (extra = {}) => seed({
  ...Object.fromEntries(['poster', 'worker', 'eve', 'host', 'renter', 'pending', 'u1'].map((u) => [`users/${u}`, userProfile(u)])),
  'users/docAdmin': userProfile('docAdmin', { isAdmin: true }),
  'users/docAgent': userProfile('docAgent', { role: 'agent' }),
  'users/p2p': userProfile('p2p'),
  'p2p_agents/p2p': { uid: 'p2p', email: 'p2p@gmail.com', role: 'agent', isActive: true },
  'jobs/j1': job('poster', { status: 'In Progress', acceptedApplicantId: 'worker', applicantUids: ['worker'] }),
  'rentals/r1': { id: 'r1', hostId: 'host', renteeId: 'renter', status: 'Active', allowChat: true },
  'rentals/r2': { id: 'r2', hostId: 'host', renteeId: null, status: 'Available', allowChat: true },
  'rentals/r3': { id: 'r3', hostId: 'host', renteeId: 'renter', status: 'Active', allowChat: false },
  [JOB]: { userIds: ['poster', 'worker'], jobId: 'j1', applicantId: 'worker', type: 'job', updatedAt: 1 },
  [`${JOB}/messages/m1`]: { senderId: 'poster', senderName: 'Employer', text: 'hi', type: 'text', createdAt: 1 },
  [LEGACY]: { userIds: ['poster', 'worker'], jobId: 'j1', type: 'job', updatedAt: 1 },
  [`${LEGACY}/messages/old1`]: { senderId: 'poster', senderName: 'Employer', text: 'legacy hi', type: 'text', createdAt: 1000 },
  [RENTAL]: { userIds: ['renter', 'host'], rentalId: 'r1', type: 'rental', updatedAt: 1 },
  'support_chats/u1': { userIds: ['u1'], userName: 'U1', lastMessage: 'help', status: 'assigned', assignedAgentId: 'staff1', requestedAt: 1, updatedAt: 1 },
  'support_chats/u1/messages/s1': { senderId: 'u1', senderName: 'U1', content: 'help', createdAt: 1 },
  'notifications/notif_1_worke': { uid: 'worker', title: 'Gig Completed', message: 'rate', type: 'job_completed', jobId: 'j1', senderUid: 'poster', senderName: 'Employer', isRead: false, createdAt: 1 },
  ...extra,
});

const STAFF = {
  'verified @tranyx.app email': () => user('staff1', { email: 'staff1@tranyx.app', email_verified: true }),
  'admin custom claim': () => adminClaim('claimAdmin'),
  'role:"support" claim': () => user('sup', { role: 'support' }),
  'users doc isAdmin:true (gmail)': () => user('docAdmin'),
  'users doc role:"agent" (gmail)': () => user('docAgent'),
  'P2P agent: p2p_agents/{uid} doc (gmail)': () => user('p2p'),
};
const deskOps = {
  'list all support_chats (chats.dart:198, dashboard.dart:1131)': (db) => getDocs(collection(db, 'support_chats')),
  'listen support messages orderBy createdAt (chats.dart:226)': (db) => getDocs(query(collection(db, 'support_chats/u1/messages'), orderBy('createdAt'))),
  'reply in support chat (chats.dart:822)': (db) => addDoc(collection(db, 'support_chats/u1/messages'), { senderId: 'agentX', senderName: 'Agent', content: 'hi', createdAt: now(), isStaff: true, agentEmail: 'a@tranyx.app' }),
  'claim/assign desk fields merge (chats.dart:831, request_lock_service.dart:392)': (db) => setDoc(doc(db, 'support_chats/u1'), { status: 'active', lastMessage: 'hi', updatedAt: now(), assignedAgentId: 'agentX', assignedAgentName: 'Agent' }, { merge: true }),
  'list chats (dashboard.dart:1135)': (db) => getDocs(collection(db, 'chats')),
  'read a job chat + messages (disputes evidence)': (db) => getDocs(collection(db, `${JOB}/messages`)),
  'dispute resolution system message (disputes.dart:266-277)': (db) => setDoc(doc(db, `${LEGACY}/messages/msg_res_1`), { senderId: 'system', senderName: 'Tranyx Arbitration', type: 'dispute_resolved', disputeId: 'd1', resolutionType: 'split', text: 'resolved', createdAt: now() }),
  'create a notification for a user (withdrawals.dart:711)': (db) => setDoc(doc(collection(db, 'notifications')), { uid: 'u1', title: 'Withdrawal approved', message: 'ok', isRead: false, createdAt: now(), type: 'withdrawal' }),
  'read any notification': (db) => getDoc(doc(db, 'notifications/notif_1_worke')),
};

describe('STAFF-MA: [MUST-ALLOW] support desk / disputes / agent access via isAdminOrStaff()', () => {
  for (const [who, mk] of Object.entries(STAFF)) {
    it(`STAFF-MA ${who}: every desk op`, async () => {
      await base();
      for (const [op, fn] of Object.entries(deskOps)) {
        try { await assertSucceeds(fn(mk())); } catch (e) { throw new Error(`${op}: ${e.message}`); }
      }
    });
  }
});

describe('STAFF-L: accounts that LOSE desk access under 2902ace (had it only because old rules were open)', () => {
  const LOSERS = {
    'unverified @tranyx.app email/password, no claim, no users flag, no p2p_agents doc': () => user('nv', { email: 'nv@tranyx.app', email_verified: false }),
    'gmail email/password staff with no claim/flag/doc': () => user('gstaff'),
  };
  for (const [who, mk] of Object.entries(LOSERS)) {
    it(`STAFF-L ${who}: denied every desk op`, async () => {
      await base();
      for (const [op, fn] of Object.entries(deskOps)) {
        if (op.startsWith('create a notification')) continue; // open to any signed-in user, see STAFF-OPEN-02
        try { await assertFails(fn(mk())); } catch (e) { throw new Error(`${op}: ${e.message}`); }
      }
    });
  }
  knownHole('KNOWN-HOLE STAFF-L3 [CRITICAL] (=ESC-08/10, KAN-136) unverified @tranyx.app self-writes p2p_agents/{uid} (admin portal syncEnvAuth environment_provider.dart:81) and then reads every support chat', async () => {
    await base();
    const db = user('nv', { email: 'nv@tranyx.app', email_verified: false });
    await setDoc(doc(db, 'p2p_agents/nv'), { uid: 'nv', email: 'nv@tranyx.app', role: 'agent', isActive: true }).catch(() => {});
    await assertFails(getDocs(collection(db, 'support_chats')));
  });
});

describe('STAFF-N: non-staff denies', () => {
  const eve = () => user('eve');
  it('STAFF-N-01 regular user denied every desk op (list/read/reply/assign support chats, list chats, foreign chat, system msg, read others\' notifications)', async () => {
    await base();
    for (const [op, fn] of Object.entries(deskOps)) {
      if (op.startsWith('create a notification')) continue; // still open by design, see STAFF-OPEN-02
      try { await assertFails(fn(eve())); } catch (e) { throw new Error(`${op}: ${e.message}`); }
    }
  });
  it('STAFF-N-02 user lists only own notifications (uid filter) and cannot list unfiltered', async () => {
    await base();
    await assertSucceeds(getDocs(query(collection(user('worker'), 'notifications'), where('uid', '==', 'worker'))));
    await assertSucceeds(getDocs(query(collection(user('worker'), 'notifications'), where('uid', '==', 'worker'), where('isRead', '==', false))));
    await assertFails(getDocs(collection(user('worker'), 'notifications')));
    await assertFails(getDocs(query(collection(eve(), 'notifications'), where('uid', '==', 'worker'))));
  });
  it('STAFF-N-03 recipient may only flip isRead; cannot re-target uid; others cannot mark read', async () => {
    await base();
    await assertSucceeds(updateDoc(doc(user('worker'), 'notifications/notif_1_worke'), { isRead: true }));
    await assertFails(updateDoc(doc(user('worker'), 'notifications/notif_1_worke'), { uid: 'eve' }));
    await assertFails(updateDoc(doc(eve(), 'notifications/notif_1_worke'), { isRead: true }));
  });
  it('STAFF-N-04 support_chats/<uid>: other users cannot get, post, or overwrite; owner can', async () => {
    await base();
    await assertFails(getDoc(doc(eve(), 'support_chats/u1')));
    await assertFails(addDoc(collection(eve(), 'support_chats/u1/messages'), { senderId: 'eve', senderName: 'E', content: 'x', createdAt: now() }));
    await assertFails(setDoc(doc(eve(), 'support_chats/u1'), { lastMessage: 'x', updatedAt: now(), userIds: ['u1'] }));
    await assertFails(addDoc(collection(user('u1'), 'support_chats/u1/messages'), { senderId: 'staff1', senderName: 'Fake agent', content: 'x', createdAt: now() }));
    await assertSucceeds(getDocs(collection(user('u1'), 'support_chats/u1/messages')));
  });
});

describe('PROBE: party logic attacks', () => {
  it('PR-01 uid containing "_" cannot reach a chat by splitting differently (job_j1_a_b -> legacy path jobs/job_j1_a_b)', async () => {
    await base({ 'jobs/j1': job('poster', { status: 'Open', applicantUids: ['a_b', 'worker'], acceptedApplicantId: 'worker' }) });
    const db = user('a_b');
    await assertFails(addDoc(collection(db, 'chats/job_j1_a_b/messages'), { senderId: 'a_b', senderName: 'x', text: 'x', type: 'text', createdAt: serverTimestamp() }));
    await assertFails(getDoc(doc(db, 'chats/job_j1_a_b')));
  });
  it('PR-02 forged chat ids for jobs/listings you are not on', async () => {
    await base();
    const e = user('eve');
    for (const id of ['job_j1_eve', 'job_j1_worker', 'j1', 'rental_r1_eve', 'rental_r1_renter', 'property_p1_eve', 'job_nojob_eve', 'rental_r1_renter_x']) {
      await assertFails(addDoc(collection(e, `chats/${id}/messages`), { senderId: 'eve', senderName: 'E', text: 'x', type: 'text', createdAt: serverTimestamp() }));
      await assertFails(getDocs(collection(e, `chats/${id}/messages`)));
    }
  });
  it('PR-03 member cannot rewrite userIds to add a third party or swap the counterparty', async () => {
    await base();
    await assertFails(setDoc(doc(user('renter'), RENTAL), { userIds: ['renter', 'eve'] }, { merge: true }));
    await assertFails(setDoc(doc(user('host'), RENTAL), { userIds: ['renter', 'host', 'eve'] }, { merge: true }));
    await assertFails(setDoc(doc(user('poster'), JOB), { userIds: ['poster', 'eve'] }, { merge: true }));
  });
  it('PR-04 non-party cannot add self to userIds (create own rental_<r>_<self> chat or merge into existing)', async () => {
    await base();
    await assertFails(setDoc(doc(user('eve'), 'chats/rental_r2_eve'), { userIds: ['eve', 'host'], rentalId: 'r2', type: 'rental' }));
    await assertFails(setDoc(doc(user('eve'), RENTAL), { userIds: ['eve', 'host'] }, { merge: true }));
  });
  it('PR-05 list queries on chats denied for users (even array-contains self); app never lists chats', async () => {
    await base();
    await assertFails(getDocs(query(collection(user('renter'), 'chats'), where('userIds', 'array-contains', 'renter'))));
  });
  it('PR-06 no existence oracle: non-party get on existing vs nonexistent chat both PERMISSION_DENIED', async () => {
    await base();
    const codes = [];
    for (const id of ['job_j1_worker', 'job_j1_ghost', 'rental_r1_renter', 'rental_r1_ghost', 'rental_r2_eve', 'zzz']) {
      codes.push(await getDoc(doc(user('eve'), `chats/${id}`)).then(() => 'ok', (e) => e.code));
    }
    if (codes.some((c) => c !== 'permission-denied')) throw new Error(`codes ${codes}`);
  });
  it('PR-07 jobs/{id}/messages: party read/write ok, stranger denied', async () => {
    await base({ 'jobs/j1/messages/jm1': { senderId: 'poster', text: 'note', timestamp: 1 } });
    await assertSucceeds(getDocs(collection(user('worker'), 'jobs/j1/messages')));
    await assertSucceeds(setDoc(doc(user('poster'), 'jobs/j1/messages/jm2'), { senderId: 'poster', senderName: 'E', text: 'x', timestamp: now() }));
    await assertFails(getDocs(collection(user('eve'), 'jobs/j1/messages')));
    await assertFails(setDoc(doc(user('eve'), 'jobs/j1/messages/jm3'), { senderId: 'eve', text: 'x', timestamp: now() }));
  });
  it('PR-08 a party cannot spoof another sender or post a non-text type as self', async () => {
    await base();
    await assertFails(addDoc(collection(user('worker'), `${JOB}/messages`), { senderId: 'poster', senderName: 'Employer', text: 'pay me off-app', type: 'text', createdAt: serverTimestamp() }));
    await assertFails(addDoc(collection(user('worker'), `${JOB}/messages`), { senderId: 'worker', senderName: 'W', text: 'x', type: 'dispute_resolved', createdAt: serverTimestamp() }));
  });
  knownHole('KNOWN-HOLE PR-09 [LOW] job creator cannot open a job_<job>_<uid> chat with a user who never applied (owner is a party for any suffix)', async () => {
    await base();
    await assertFails(addDoc(collection(user('poster'), 'chats/job_j1_eve/messages'), { senderId: 'poster', senderName: 'Employer', text: 'hey', type: 'text', createdAt: serverTimestamp() }));
  });
});

describe('FLOW: the 6 newly denied app flows (documents current behaviour on 2902ace)', () => {
  it('FLOW-1 legacy bridge (tranyx_app.dart:4527-4545) copying a message with original senderId/createdAt is denied; legacy room stays readable', async () => {
    await base();
    const w = user('worker');
    await assertFails(setDoc(doc(w, 'chats/job_j1_worker/messages/old1'), { senderId: 'poster', senderName: 'Employer', text: 'legacy hi', type: 'text', createdAt: 1000 }));
    await assertSucceeds(getDocs(collection(w, `${LEGACY}/messages`)));
  });
  it('FLOW-2 pending requester (not renteeId, no chat yet) cannot send or read; once host writes userIds they can', async () => {
    await base();
    const m = { senderId: 'pending', senderName: 'P', text: 'is it available?', type: 'text', createdAt: serverTimestamp() };
    await assertFails(addDoc(collection(user('pending'), 'chats/rental_r2_pending/messages'), m));
    await assertSucceeds(setDoc(doc(user('host'), 'chats/rental_r2_pending'), { updatedAt: serverTimestamp(), userIds: ['pending', 'host'], rentalId: 'r2', type: 'rental' }, { merge: true }));
    await assertSucceeds(addDoc(collection(user('pending'), 'chats/rental_r2_pending/messages'), m));
  });
  it('FLOW-3 createdAt ms: 4 min skew ok, 6 min past now ok (offline queue, KAN-139), 6 min future denied; serverTimestamp ok', async () => {
    await base();
    const r = user('renter');
    const m = (createdAt) => ({ senderId: 'renter', senderName: 'R', content: 'x', createdAt });
    await assertSucceeds(addDoc(collection(r, `${RENTAL}/messages`), m(now() - 240000)));
    await assertSucceeds(addDoc(collection(r, `${RENTAL}/messages`), m(now() - 360000)));
    await assertFails(addDoc(collection(r, `${RENTAL}/messages`), m(now() + 360000)));
    await assertSucceeds(addDoc(collection(r, `${RENTAL}/messages`), m(serverTimestamp())));
  });
  it('FLOW-4 notif_<ms>_<prefix> collision: second sender writing the same id is denied (was silent overwrite)', async () => {
    await base();
    const n = (from) => ({ uid: 'worker', title: `New message from ${from}`, message: 'x', isRead: false, createdAt: 5, type: 'chat', chatId: 'job_j1_worker', senderName: from });
    await assertSucceeds(setDoc(doc(user('poster'), 'notifications/notif_5_worke'), n('poster')));
    await assertFails(setDoc(doc(user('eve'), 'notifications/notif_5_worke'), n('eve')));
  });
  it('FLOW-5 web rating popup full re-save {...latest, id, isRead:true} (tranyx_app.dart:1211) passes when fields round-trip; any other change denied', async () => {
    await base();
    const w = user('worker');
    const latest = { uid: 'worker', title: 'Gig Completed', message: 'rate', type: 'job_completed', jobId: 'j1', senderUid: 'poster', senderName: 'Employer', isRead: false, createdAt: 1, id: 'notif_1_worke' };
    await assertSucceeds(setDoc(doc(w, 'notifications/notif_1_worke'), { ...latest, isRead: true }));
    await assertFails(setDoc(doc(w, 'notifications/notif_1_worke'), { ...latest, isRead: true, title: 'changed' }));
  });
  it('FLOW-6 listing allowChat:false blocks the renter (matches web client gate tranyx_app.dart:4402); host can still post', async () => {
    await base({ 'chats/rental_r3_renter': { userIds: ['renter', 'host'], rentalId: 'r3', type: 'rental', updatedAt: 1 } });
    const m = (s) => ({ senderId: s, senderName: s, content: 'x', createdAt: now() });
    await assertFails(addDoc(collection(user('renter'), 'chats/rental_r3_renter/messages'), m('renter')));
    await assertSucceeds(addDoc(collection(user('host'), 'chats/rental_r3_renter/messages'), m('host')));
  });
});

describe('MSG: message shapes still accepted', () => {
  it('MSG-01 web photo message {text:"", photoUrl:i.ibb.co, type:"text", serverTimestamp} (index.html:2036, tranyx_app.dart:4661)', async () => {
    await base();
    await assertSucceeds(addDoc(collection(user('worker'), `${JOB}/messages`), { senderId: 'worker', senderName: 'W', text: '', photoUrl: 'https://i.ibb.co/abc/x.jpg', type: 'text', createdAt: serverTimestamp() }));
  });
  it('MSG-02 mobile trip-tracker message + merge chat doc {id,lastMessage,updatedAt,userIds} (active_trip_tracker_sheet.dart:446-471)', async () => {
    await base();
    const r = user('renter');
    await assertSucceeds(addDoc(collection(r, `${RENTAL}/messages`), { senderId: 'renter', senderName: 'R', content: 'x', createdAt: now() }));
    await assertSucceeds(setDoc(doc(r, RENTAL), { id: 'rental_r1_renter', lastMessage: 'x', updatedAt: now(), userIds: ['renter', 'host'] }, { merge: true }));
  });
  it('MSG-03 web masked touch setDocument(chats/<id>, {updatedAt}) on a job chat (firebase_service.dart:2648-2862, KAN-139)', async () => {
    await base();
    await assertSucceeds(setDoc(doc(user('worker'), JOB), { updatedAt: now() }, { merge: true }));
  });
  it('MSG-04 full overwrite that drops userIds or strips status/resolvedAt is denied; merge touch keeps them (KAN-139)', async () => {
    await base({ [JOB]: { userIds: ['poster', 'worker'], jobId: 'j1', applicantId: 'worker', type: 'job', updatedAt: 1, createdAt: 1, status: 'resolved', resolvedAt: 2 } });
    await assertFails(setDoc(doc(user('worker'), JOB), { updatedAt: now() }));
    await assertSucceeds(setDoc(doc(user('worker'), JOB), { updatedAt: now() }, { merge: true }));
  });
  it('MSG-04 guard: a party still cannot add a field outside the allow-list', async () => {
    await base();
    await assertFails(setDoc(doc(user('worker'), JOB), { status: 'resolved' }, { merge: true }));
  });
});

describe('STAFF-OPEN: still open on 2902ace (Saga flagged)', () => {
  knownHole('KNOWN-HOLE STAFF-OPEN-01 [MEDIUM] owner cannot set desk fields on own support chat (status/assignedAgentId)', async () => {
    await base();
    await assertFails(setDoc(doc(user('u1'), 'support_chats/u1'), { status: 'resolved', assignedAgentId: 'someAgent' }, { merge: true }));
  });
  knownHole('KNOWN-HOLE STAFF-OPEN-02 [MEDIUM] user cannot forge a notification for someone else posing as admin / job_completed', async () => {
    await base();
    await assertFails(setDoc(doc(user('eve'), 'notifications/notif_admin_1'), { uid: 'worker', title: 'Tranyx Admin: verify your wallet', message: 'go to evil.example', type: 'job_completed', senderUid: 'eve', senderName: 'Tranyx Support', isRead: false, createdAt: now() }));
  });
  it('TRAD6-01 support message parent write uses an update mask, so status and assignedAgentId survive (KAN-139, TRAD-6)', async () => {
    await base();
    await assertSucceeds(updateDoc(doc(user('u1'), 'support_chats/u1'), { lastMessage: 'again', updatedAt: now(), userIds: ['u1'] }));
    let snap;
    await (await import('./helpers.mjs')).env.withSecurityRulesDisabled(async (c) => { snap = (await c.firestore().doc('support_chats/u1').get()).data(); });
    if (snap.status !== 'assigned' || snap.assignedAgentId !== 'staff1' || snap.lastMessage !== 'again') throw new Error(JSON.stringify(snap));
  });
  // App path is masked (TRAD6-01 / support_chat_mask_test.dart). Rules still allow a raw full overwrite that wipes desk fields.
  knownHole('KNOWN-HOLE TRAD6-02 [MEDIUM] owner full overwrite of support_chats/<uid> cannot wipe desk fields (status/assignedAgentId) (KAN-139, TRAD-6)', async () => {
    await base();
    await assertFails(setDoc(doc(user('u1'), 'support_chats/u1'), { lastMessage: 'again', updatedAt: now(), userIds: ['u1'] }));
  });
});
