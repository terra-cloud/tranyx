// Doc flags and p2p_agents docs are not authority for treasury, agent management, or money writes.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { setupEnv, seed, user, adminClaim, userProfile, withdrawal } from './helpers.mjs';

setupEnv();

describe('legacy flags are not money or treasury authority', () => {
  const prep = () => seed({
    'users/flag': userProfile('flag', { isAdmin: true, isP2pAgent: true, role: 'admin' }),
    'users/victim': userProfile('victim'),
    'p2p_agents/agent1': { uid: 'agent1', isActive: true },
    'users/agent1': userProfile('agent1'),
    'system_config/treasury': { solanaTreasuryPubkey: 'TREASURY_PLACEHOLDER' },
    'withdrawal_requests/wr1': withdrawal('victim'),
    'deposit_requests/d1': { uid: 'victim', userId: 'victim', amount: 900000, status: 'PENDING_VERIFICATION', referenceNumber: 'AB1' },
    'escrow/j1': { employerId: 'victim', amount: 1000, status: 'held' },
    'jobs/j1': { creatorId: 'victim', status: 'In Progress' },
  });

  it('an admin claim can read treasury; a doc flag, an agent doc, and a role=agent claim cannot', async () => {
    await prep();
    await assertSucceeds(getDoc(doc(adminClaim(), 'system_config/treasury')));
    await assertFails(getDoc(doc(user('flag'), 'system_config/treasury')));
    await assertFails(getDoc(doc(user('agent1'), 'system_config/treasury')));
    await assertFails(getDoc(doc(user('tok', { role: 'agent' }), 'system_config/treasury')));
  });

  it('only an admin claim can write p2p_agents', async () => {
    await prep();
    const body = { uid: 'new', role: 'agent', isActive: true };
    await assertFails(setDoc(doc(user('flag'), 'p2p_agents/new'), body));
    await assertFails(setDoc(doc(user('agent1'), 'p2p_agents/new'), body));
    await assertFails(setDoc(doc(user('tok', { role: 'agent' }), 'p2p_agents/new'), body));
    await assertSucceeds(setDoc(doc(adminClaim(), 'p2p_agents/new'), body));
  });

  it('nobody can client-approve or client-reject a withdrawal, or mint a request', async () => {
    await prep();
    for (const db of [user('flag'), user('agent1'), adminClaim(), user('tok', { role: 'staff' })]) {
      await assertFails(updateDoc(doc(db, 'withdrawal_requests/wr1'), { status: 'APPROVED' }));
      await assertFails(updateDoc(doc(db, 'withdrawal_requests/wr1'), { status: 'REJECTED', amount: 1 }));
      await assertFails(setDoc(doc(db, 'withdrawal_requests/forged'), withdrawal('victim', { status: 'APPROVED', amount: 900000 })));
    }
  });

  it('a claim admin cannot client-note a claim, and cannot change escrow money fields', async () => {
    await prep();
    await assertFails(updateDoc(doc(adminClaim(), 'withdrawal_requests/wr1'), { status: 'AWAITING_AGENT_PAYMENT', agentId: 'realAdmin' }));
    await assertFails(updateDoc(doc(user('flag'), 'escrow/j1'), { status: 'refunded', amount: 0 }));
    await assertFails(updateDoc(doc(adminClaim(), 'escrow/j1'), { status: 'refunded', amount: 999999 }));
    await assertSucceeds(updateDoc(doc(adminClaim(), 'escrow/j1'), { updatedAt: 1 }));
    await assertFails(updateDoc(doc(user('flag'), 'deposit_requests/d1'), { status: 'APPROVED' }));
    await assertFails(updateDoc(doc(adminClaim(), 'deposit_requests/d1'), { status: 'APPROVED' }));
  });

  it('the depositor can still mark their own request pending verification', async () => {
    await prep();
    await assertSucceeds(updateDoc(doc(user('victim'), 'deposit_requests/d1'), { status: 'PENDING_VERIFICATION', referenceNumber: 'AB2' }));
  });
});
