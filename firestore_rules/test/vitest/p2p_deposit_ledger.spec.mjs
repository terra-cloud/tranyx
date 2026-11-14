// Owner proof + cancel on a P2P top-up rewrite transactions/p2p_dep_<id>
// (firebase_service.dart submitDepositProof / cancelDepositRequest). Amount and settled rows stay locked.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, updateDoc } from 'firebase/firestore';
import { setupEnv, seed, user, userProfile } from './helpers.mjs';

setupEnv();
const NOW = 1761123600000;
const depTx = {
  id: 'p2p_dep_d1', uid: 'u1', depositRequestId: 'd1', amount: 500, type: 'deposit',
  status: 'AWAITING_PAYMENT', originRail: 'manual_p2p', method: 'GCash',
  title: 'GCash P2P Top-Up Request', desc: 'Agent sent QR', createdAt: NOW,
};
const prep = () => seed({
  'users/u1': userProfile('u1'),
  'users/eve': userProfile('eve'),
  'deposit_requests/d1': { uid: 'u1', amount: 500, status: 'AWAITING_PAYMENT', paymentMethod: 'GCash', createdAt: NOW },
  'transactions/p2p_dep_d1': depTx,
  'transactions/p2p_dep_done': { ...depTx, id: 'p2p_dep_done', status: 'COMPLETED' },
  'transactions/p2p_with_w1': { id: 'p2p_with_w1', uid: 'u1', amount: 500, type: 'withdrawal', status: 'WAITING_FOR_AGENT', createdAt: NOW },
});

describe('P2P deposit ledger owner patch', () => {
  it('lets the owner cancel and attach proof without changing the amount', async () => {
    await prep();
    const db = user('u1');
    await assertSucceeds(updateDoc(doc(db, 'transactions/p2p_dep_d1'), { status: 'CANCELLED', verifiedAt: NOW }));
    await seed({ 'transactions/p2p_dep_d1': depTx });
    await assertSucceeds(updateDoc(doc(db, 'transactions/p2p_dep_d1'), {
      status: 'PENDING_VERIFICATION',
      referenceNumber: 'GC123',
      proofImageUrl: 'https://i.ibb.co/receipt.jpg',
      desc: 'Payment proof submitted. Awaiting agent verification.',
    }));
    await assertSucceeds(updateDoc(doc(db, 'deposit_requests/d1'), { status: 'CANCELLED', verifiedAt: NOW }));
  });

  it('refuses amount, owner, settled-row, and cashout edits', async () => {
    await prep();
    const owner = user('u1');
    await assertFails(updateDoc(doc(owner, 'transactions/p2p_dep_d1'), { amount: 1 }));
    await assertFails(updateDoc(doc(owner, 'transactions/p2p_dep_d1'), { status: 'APPROVED' }));
    await assertFails(updateDoc(doc(owner, 'transactions/p2p_dep_d1'), { status: 'COMPLETED' }));
    await assertFails(updateDoc(doc(owner, 'transactions/p2p_dep_d1'), { uid: 'eve' }));
    await assertFails(updateDoc(doc(owner, 'transactions/p2p_dep_done'), { status: 'CANCELLED' }));
    await assertFails(updateDoc(doc(owner, 'transactions/p2p_with_w1'), { status: 'CANCELLED' }));
    await assertFails(updateDoc(doc(user('eve'), 'transactions/p2p_dep_d1'), { status: 'CANCELLED' }));
  });
});
