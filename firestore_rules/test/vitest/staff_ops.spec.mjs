// staffOps lock: no client (admin claim, staff, P2P agent doc) can write balances; audit log is Admin-SDK only.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { setupEnv, seed, user, adminClaim, userProfile } from './helpers.mjs';

setupEnv();
const base = {
  'users/victim': userProfile('victim', { tyxBalance: 100 }),
  'users/agent1': userProfile('agent1', { isP2pAgent: true }),
  'p2p_agents/agent1': { uid: 'agent1', isActive: true },
  'users/staff1': userProfile('staff1', { role: 'staff' }),
};

describe('staff / P2P agent balance writes are callable-only', () => {
  it('a P2P agent (doc flags) cannot change tyxBalance or reservedBalance of any user, nor create a funded profile', async () => {
    await seed(base);
    const a = user('agent1');
    await assertFails(updateDoc(doc(a, 'users/victim'), { tyxBalance: 0 }));
    await assertFails(updateDoc(doc(a, 'users/victim'), { reservedBalance: 5 }));
    await assertFails(setDoc(doc(a, 'users/brandnew'), userProfile('brandnew', { tyxBalance: 5000 })));
    await assertFails(setDoc(doc(a, 'users/victim'), { tyxBalance: 1 }, { merge: true }));
  });
  it('a staff user doc and the admin claim are denied as well, but non-money staff edits still work', async () => {
    await seed(base);
    await assertFails(updateDoc(doc(user('staff1'), 'users/victim'), { tyxBalance: 1 }));
    await assertFails(updateDoc(doc(adminClaim(), 'users/victim'), { tyxBalance: 1 }));
    await assertSucceeds(updateDoc(doc(user('agent1'), 'users/victim'), { banned: false, headline: 'ok' }));
    await assertSucceeds(setDoc(doc(adminClaim(), 'users/zero'), userProfile('zero', { tyxBalance: 0 })));
  });
  it('staff_audit_log: staff read, nobody writes from a client', async () => {
    await seed({ ...base, 'staff_audit_log/op1': { action: 'approveDeposit' } });
    await assertSucceeds(getDoc(doc(user('agent1'), 'staff_audit_log/op1')));
    await assertFails(getDoc(doc(user('victim'), 'staff_audit_log/op1')));
    await assertFails(setDoc(doc(adminClaim(), 'staff_audit_log/op2'), { action: 'x' }));
    await assertFails(updateDoc(doc(adminClaim(), 'staff_audit_log/op1'), { action: 'tampered' }));
  });
});
