// Chat rules suite (Oct 22, against be724522 / e88cada). Model mapped from app code:
//   chats/{chatId}  ids: job_<jobId>_<applicantUid> (scoped), <jobId> (legacy), rental_<rentalId>_<renteeUid>, property_<propertyId>_<renteeUid>
//     fields: userIds[2], jobId, applicantId, rentalId, propertyId, type, id, lastMessage, updatedAt (serverTimestamp or epoch ms)
//   chats/{chatId}/messages/{id}: senderId (uid | 'system'), senderName, text|content, photoUrl, type, createdAt, category, deadline, slaMinutes
//   support_chats/{uid}(+/messages), notifications (type 'chat' = unread badge), jobs/{jobId}/messages (old job room)
// The app never lists `chats`; it opens a chat by id and listens to messages orderBy(createdAt).
// Web writes the first message BEFORE the chat doc has userIds (index.html:2046 vs async :1998), so membership
// must be derived from the chat id + jobs/rentals/properties docs, not from chats/{id}.userIds.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, orderBy, setDoc, updateDoc, deleteDoc, addDoc, writeBatch, serverTimestamp } from 'firebase/firestore';
import { knownHole, planned, setupEnv, seed, user, guest, adminClaim, userProfile, job, property } from './helpers.mjs';

setupEnv();
const now = () => Date.now();
const JOB = 'chats/job_j1_worker', LEGACY = 'chats/j1', RENTAL = 'chats/rental_r1_renter', PROP = 'chats/property_p1_renter';
const msg = (senderId, extra = {}) => ({ senderId, senderName: `User ${senderId}`, text: 'hello', photoUrl: null, type: 'text', createdAt: serverTimestamp(), ...extra });
const base = (extra = {}) => seed({
  ...Object.fromEntries(['poster', 'worker', 'eve', 'host', 'renter'].map((u) => [`users/${u}`, userProfile(u)])),
  'jobs/j1': job('poster', { status: 'In Progress', acceptedApplicantId: 'worker', applicantUids: ['worker'] }),
  'rentals/r1': { id: 'r1', hostId: 'host', renteeId: 'renter', status: 'Active', allowChat: true },
  'properties/p1': property('host', { renteeId: 'renter', status: 'Active', allowChat: true }),
  [JOB]: { userIds: ['poster', 'worker'], jobId: 'j1', applicantId: 'worker', type: 'job', updatedAt: 1 },
  [`${JOB}/messages/m1`]: { senderId: 'poster', senderName: 'Employer', text: 'hi', type: 'text', createdAt: 1 },
  [RENTAL]: { userIds: ['renter', 'host'], rentalId: 'r1', type: 'rental', updatedAt: 1 },
  [`${RENTAL}/messages/m1`]: { senderId: 'host', senderName: 'Host', content: 'welcome', createdAt: 1 },
  'support_chats/renter': { userIds: ['renter'], lastMessage: 'my id photo', updatedAt: 1 },
  'support_chats/renter/messages/s1': { senderId: 'renter', senderName: 'Renter', content: 'my id photo', createdAt: 1 },
  'notifications/notif_1_worke': { uid: 'worker', title: 'New message from Employer', message: 'gate code 4411', isRead: false, createdAt: 1, type: 'chat', chatId: 'job_j1_worker', senderName: 'Employer' },
  'jobs/j1/messages/jm1': { senderId: 'poster', text: 'private job note', createdAt: 1 },
  ...extra,
});

describe('CHAT-MA: [MUST-ALLOW] app flows', () => {
  it('CHAT-MA-01 web job chat send: message as self, touch, then chat metadata merge (index.html:2046, :2048, :1998)', async () => {
    await base();
    const db = user('worker');
    await assertSucceeds(addDoc(collection(db, `${JOB}/messages`), msg('worker')));
    await assertSucceeds(setDoc(doc(db, JOB), { updatedAt: serverTimestamp() }, { merge: true }));
    await assertSucceeds(setDoc(doc(db, JOB), { updatedAt: serverTimestamp(), userIds: ['poster', 'worker'], jobId: 'j1', applicantId: 'worker', type: 'job' }, { merge: true }));
  });
  it('CHAT-MA-02 first message in a brand-new chat (chat doc not created yet, index.html:2046 runs before :1998)', async () => {
    await base();
    await assertSucceeds(addDoc(collection(user('poster'), 'chats/job_j1_worker2/messages'), msg('poster')));
  });
  it('CHAT-MA-03 both members get the chat doc and listen to messages orderBy(createdAt) (index.html:1831, active_trip_tracker_sheet.dart:301)', async () => {
    await base();
    for (const u of ['poster', 'worker']) {
      await assertSucceeds(getDoc(doc(user(u), JOB)));
      await assertSucceeds(getDocs(query(collection(user(u), `${JOB}/messages`), orderBy('createdAt', 'asc'))));
    }
  });
  it('CHAT-MA-04 mobile rental chat: renter sends {content, createdAt ms} then merges lastMessage/userIds; host replies (active_trip_tracker_sheet.dart:446-471)', async () => {
    await base();
    const r = user('renter');
    await assertSucceeds(addDoc(collection(r, `${RENTAL}/messages`), { senderId: 'renter', senderName: 'Renter', content: 'arriving 3pm', createdAt: now() }));
    await assertSucceeds(setDoc(doc(r, RENTAL), { id: 'rental_r1_renter', lastMessage: 'arriving 3pm', updatedAt: now(), userIds: ['renter', 'host'] }, { merge: true }));
    await assertSucceeds(addDoc(collection(user('host'), `${RENTAL}/messages`), { senderId: 'host', senderName: 'Host', content: 'ok', createdAt: now() }));
  });
  it('CHAT-MA-05 web property chat metadata + message (index.html:1965)', async () => {
    await base();
    const r = user('renter');
    await assertSucceeds(addDoc(collection(r, `${PROP}/messages`), msg('renter')));
    await assertSucceeds(setDoc(doc(r, PROP), { updatedAt: serverTimestamp(), userIds: ['renter', 'host'], propertyId: 'p1', type: 'property' }, { merge: true }));
  });
  it('CHAT-MA-06 employer hire transaction posts system ack request into scoped + legacy chat (job_repository.dart:463-487)', async () => {
    await base();
    const db = user('poster'); const t = now(); const b = writeBatch(db);
    const ack = { senderId: 'system', senderName: 'Tranyx System', type: 'acknowledgment_request', text: 'You have been hired', category: 'gig', deadline: t + 600000, slaMinutes: 10, createdAt: t };
    b.set(doc(db, `${JOB}/messages/msg_ack_req_${t}`), ack);
    b.set(doc(db, JOB), { userIds: ['poster', 'worker'], jobId: 'j1', applicantId: 'worker', updatedAt: t }, { merge: true });
    b.set(doc(db, `${LEGACY}/messages/msg_ack_req_${t}`), ack);
    b.set(doc(db, LEGACY), { updatedAt: t }, { merge: true });
    await assertSucceeds(b.commit());
  });
  it('CHAT-MA-07 worker acknowledgment system message + touches (firebase_service.dart:2643-2651)', async () => {
    await base();
    const db = user('worker'); const t = now();
    const conf = { senderId: 'system', senderName: 'Tranyx System', type: 'acknowledgment_confirmed', text: 'Nyxian has acknowledged', createdAt: t };
    await assertSucceeds(setDoc(doc(db, `${JOB}/messages/msg_ack_${t}`), conf));
    await assertSucceeds(setDoc(doc(db, `${LEGACY}/messages/msg_ack_${t}`), conf));
    await assertSucceeds(setDoc(doc(db, LEGACY), { updatedAt: t }, { merge: true }));
  });
  it('CHAT-MA-08 sender creates the recipient chat notification; recipient reads and marks it read (index.html:1855, notifications_provider.dart:38/55)', async () => {
    await base();
    await assertSucceeds(setDoc(doc(user('poster'), 'notifications/notif_2_worke'), { uid: 'worker', title: 'New message from Employer', message: 'hi', isRead: false, createdAt: now(), type: 'chat', chatId: 'job_j1_worker', senderName: 'Employer' }));
    await assertSucceeds(getDoc(doc(user('worker'), 'notifications/notif_1_worke')));
    await assertSucceeds(updateDoc(doc(user('worker'), 'notifications/notif_1_worke'), { isRead: true }));
  });
  it('CHAT-MA-09 owner uses own support chat (nyx_chat_view.dart:1164-1176, :878)', async () => {
    await base();
    const r = user('renter');
    await assertSucceeds(addDoc(collection(r, 'support_chats/renter/messages'), { senderId: 'renter', senderName: 'Renter', content: 'help', createdAt: now() }));
    await assertSucceeds(setDoc(doc(r, 'support_chats/renter'), { lastMessage: 'help', updatedAt: now(), userIds: ['renter'] }, { merge: true }));
    await assertSucceeds(getDocs(query(collection(r, 'support_chats/renter/messages'), orderBy('createdAt', 'asc'))));
  });
  it('CHAT-MA-10 admin can read any chat, messages and support chat (moderation)', async () => {
    await base();
    const a = adminClaim();
    await assertSucceeds(getDoc(doc(a, JOB)));
    await assertSucceeds(getDocs(collection(a, `${JOB}/messages`)));
    await assertSucceeds(getDocs(collection(a, 'support_chats/renter/messages')));
  });
});

describe('CHAT-G: guests (secure today)', () => {
  it('CHAT-G-01 guest cannot read, list or post chats, messages or support chats', async () => {
    await base();
    const g = guest();
    await assertFails(getDoc(doc(g, JOB)));
    await assertFails(getDocs(collection(g, `${JOB}/messages`)));
    await assertFails(addDoc(collection(g, `${JOB}/messages`), msg('worker')));
    await assertFails(setDoc(doc(g, 'chats/new1'), { userIds: ['x'] }));
    await assertFails(getDocs(collection(g, 'support_chats/renter/messages')));
    await assertFails(getDocs(collection(g, 'chats')));
  });
});

describe('CHAT-H: holes (secure expectation; every one is open on be724522: /chats rule is `isActiveUser()` for read+write)', () => {
  // HIGH: any signed-in user reads any private chat by a guessable id (job ids are public).
  it('CHAT-01 [HIGH] non-member cannot get a chat doc or a message', async () => {
    await base();
    await assertFails(getDoc(doc(user('eve'), JOB)));
    await assertFails(getDoc(doc(user('eve'), `${JOB}/messages/m1`)));
  });
  // HIGH
  it('CHAT-02 [HIGH] non-member cannot list/listen to a chat\'s messages', async () => {
    await base();
    await assertFails(getDocs(query(collection(user('eve'), `${RENTAL}/messages`), orderBy('createdAt', 'asc'))));
  });
  // HIGH: also lets anyone enumerate every chat in the system.
  it('CHAT-03 [HIGH] signed-in user cannot list the whole chats collection', async () => {
    await base();
    await assertFails(getDocs(collection(user('eve'), 'chats')));
  });
  // HIGH: spam/phishing into any job or rental chat.
  it('CHAT-04 [HIGH] non-member cannot post into someone else\'s chat', async () => {
    await base();
    await assertFails(addDoc(collection(user('eve'), `${JOB}/messages`), msg('eve')));
  });
  // HIGH: impersonation inside a chat.
  it('CHAT-05 [HIGH] member cannot post with the other member\'s senderId', async () => {
    await base();
    await assertFails(addDoc(collection(user('worker'), `${JOB}/messages`), msg('poster', { text: 'Pay me outside the app' })));
  });
  // HIGH: membership metadata is client-writable.
  it('CHAT-06 [HIGH] member cannot add a third party to userIds or drop the counterparty', async () => {
    await base();
    await assertFails(updateDoc(doc(user('worker'), JOB), { userIds: ['poster', 'worker', 'eve'] }));
    await assertFails(updateDoc(doc(user('worker'), JOB), { userIds: ['worker'] }));
  });
  // MEDIUM: rewriting history (evidence for disputes).
  it('CHAT-07 [MEDIUM] member cannot edit the other member\'s message', async () => {
    await base();
    await assertFails(updateDoc(doc(user('worker'), `${JOB}/messages/m1`), { text: 'I agree to pay double' }));
  });
  // MEDIUM: deleting dispute evidence / wiping a chat.
  it('CHAT-08 [MEDIUM] nobody but admin deletes messages or chat docs', async () => {
    await base();
    await assertFails(deleteDoc(doc(user('worker'), `${JOB}/messages/m1`)));
    await assertFails(deleteDoc(doc(user('eve'), JOB)));
  });
  // MEDIUM: drags a non-consenting user into a chat (and into their unread badge via notifications).
  it('CHAT-09 [MEDIUM] user cannot create a chat for a job/rental they are not a party to', async () => {
    await base();
    await assertFails(setDoc(doc(user('eve'), 'chats/job_j1_eve'), { userIds: ['poster', 'eve'], jobId: 'j1', applicantId: 'eve', type: 'job', updatedAt: now() }));
    await assertFails(addDoc(collection(user('eve'), 'chats/rental_r1_eve/messages'), msg('eve')));
  });
  // LOW: ordering / dispute timelines rely on createdAt.
  it('CHAT-10 [LOW] message createdAt must be request.time or epoch ms in the 24h-past / 5min-ahead window', async () => {
    await base();
    await assertFails(addDoc(collection(user('worker'), `${JOB}/messages`), msg('worker', { createdAt: 946684800000 })));
    await assertFails(addDoc(collection(user('worker'), `${JOB}/messages`), msg('worker', { createdAt: now() + 86400000 })));
  });
  it('CHAT-10b createdAt window edges: 23 h old passes, 25 h old and 6 min ahead fail (KAN-139)', async () => {
    await base();
    const w = collection(user('worker'), `${JOB}/messages`), H = 3600000;
    await assertSucceeds(addDoc(w, msg('worker', { createdAt: now() - 23 * H })));
    await assertFails(addDoc(w, msg('worker', { createdAt: now() - 25 * H })));
    await assertFails(addDoc(w, msg('worker', { createdAt: now() + 6 * 60000 })));
  });
  // LOW: storage/cost abuse; UI has no limit either.
  it('CHAT-11 [LOW] message text/content is capped (e.g. 2,000 chars) and has a known shape', async () => {
    await base();
    await assertFails(addDoc(collection(user('worker'), `${JOB}/messages`), msg('worker', { text: 'x'.repeat(100000) })));
    await assertFails(addDoc(collection(user('worker'), `${JOB}/messages`), msg('worker', { isAdminNote: true, amount: 5000 })));
  });
  // HIGH: support chats carry KYC/ID and account details; keyed by the victim's uid (public in users/).
  it('CHAT-12 [HIGH] another user cannot read or post into someone\'s support chat', async () => {
    await base();
    await assertFails(getDocs(collection(user('eve'), 'support_chats/renter/messages')));
    await assertFails(getDoc(doc(user('eve'), 'support_chats/renter')));
    await assertFails(addDoc(collection(user('eve'), 'support_chats/renter/messages'), { senderId: 'renter', content: 'close my account', createdAt: now() }));
  });
  // MEDIUM: chat notifications carry message text (`message`); rule ends in `|| isAuthenticated()`.
  it('CHAT-13 [MEDIUM] another user cannot read, mark or delete someone\'s chat notification', async () => {
    await base();
    await assertFails(getDoc(doc(user('eve'), 'notifications/notif_1_worke')));
    await assertFails(updateDoc(doc(user('eve'), 'notifications/notif_1_worke'), { isRead: true }));
    await assertFails(deleteDoc(doc(user('eve'), 'notifications/notif_1_worke')));
  });
  // MEDIUM: old job room (firebase_service.dart:2366/2403) is read: isAuthenticated, write: isActiveUser.
  it('CHAT-14 [MEDIUM] non-party cannot read or write jobs/{jobId}/messages', async () => {
    await base();
    await assertFails(getDocs(collection(user('eve'), 'jobs/j1/messages')));
    await assertFails(addDoc(collection(user('eve'), 'jobs/j1/messages'), { senderId: 'eve', text: 'x', createdAt: now() }));
  });
});

describe('CHAT-P: design gaps (PLANNED)', () => {
  // MEDIUM: fake "system" messages (e.g. forged hire/ack/payout notices). Clients write them today
  // (job_repository.dart:463, firebase_service.dart:1778/2643/2705/2781/2854), so this needs a Cloud Function.
  planned('PLANNED CHAT-P1 [MEDIUM] clients cannot post senderId "system" messages (server-only)', async () => {
    await base();
    await assertFails(addDoc(collection(user('worker'), `${JOB}/messages`), { senderId: 'system', senderName: 'Tranyx System', type: 'acknowledgment_confirmed', text: 'Payout released', createdAt: now() }));
  });
  // MEDIUM: host turned chat off (manage_listing_sheet.dart:1504, transit_repository.dart:441/1582) but rules ignore it.
  it('CHAT-P2 [MEDIUM] renter cannot post into a rental/property chat when allowChat is false', async () => {
    await base({ 'properties/p1': property('host', { renteeId: 'renter', status: 'Active', allowChat: false }) });
    await assertFails(addDoc(collection(user('renter'), `${PROP}/messages`), msg('renter')));
  });
  // LOW: photoUrl is free text; should point at this project's chat_photos/<chatId>/ (no storage.rules exist yet).
  planned('PLANNED CHAT-P3 [LOW] photoUrl must be a chat_photos/<chatId>/ URL in the project bucket', async () => {
    await base();
    await assertFails(addDoc(collection(user('worker'), `${JOB}/messages`), msg('worker', { text: '', photoUrl: 'https://evil.example/phish.jpg' })));
  });
});
