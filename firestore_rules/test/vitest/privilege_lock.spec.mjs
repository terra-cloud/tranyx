// Privilege, premium, and audit-read regressions. An active p2p agent, a users-doc flag,
// and a role=agent claim must not grant isAdmin / premium or read staff_audit_log.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { deleteDoc, deleteField, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { setupEnv, seed, user, adminClaim, userProfile } from './helpers.mjs';

setupEnv();

const base = () => seed({
  'users/victim': userProfile('victim', { isAdmin: false, role: 'nyxian', isPremium: false, premiumUntil: null }),
  'users/agent1': userProfile('agent1'),
  'p2p_agents/agent1': { uid: 'agent1', isActive: true },
  'users/flag': userProfile('flag', { isAdmin: true, role: 'admin' }),
  'wallets/victim': { uid: 'victim', balance: 10 },
  'staff_audit_log/op1': { action: 'approveDeposit', actorUid: 'realAdmin' },
});

describe('privilege fields are claim-admin only', () => {
  const paths = [
    ['update isAdmin', (db) => updateDoc(doc(db, 'users/victim'), { isAdmin: true })],
    ['update role admin', (db) => updateDoc(doc(db, 'users/victim'), { role: 'admin' })],
    ['update isStaff', (db) => updateDoc(doc(db, 'users/victim'), { isStaff: true })],
    ['update isSuperAdmin', (db) => updateDoc(doc(db, 'users/victim'), { isSuperAdmin: true })],
    ['update isP2pAgent', (db) => updateDoc(doc(db, 'users/victim'), { isP2pAgent: true })],
    ['merge isAdmin', (db) => setDoc(doc(db, 'users/victim'), { isAdmin: true, role: 'admin' }, { merge: true })],
    ['remove isAdmin', (db) => updateDoc(doc(db, 'users/victim'), { isAdmin: deleteField() })],
    ['self update isSuperAdmin', (db, uid) => updateDoc(doc(db, `users/${uid}`), { isSuperAdmin: true })],
    ['create with isAdmin', (db, uid) => setDoc(doc(db, `users/new_${uid}`), userProfile(`new_${uid}`, { isAdmin: true, role: 'admin', tyxBalance: 0 }))],
  ];

  for (const [name, run] of paths) {
    it(`active p2p agent cannot ${name}`, async () => {
      await base();
      await assertFails(run(user('agent1'), 'agent1'));
    });
    it(`role=agent claim cannot ${name}`, async () => {
      await base();
      await assertFails(run(user('tok', { role: 'agent' }), 'tok'));
    });
    it(`users-doc isAdmin without a claim cannot ${name}`, async () => {
      await base();
      await assertFails(run(user('flag'), 'flag'));
    });
  }

  it('admin custom claim can still set role flags, and ordinary signup still works', async () => {
    await base();
    await assertSucceeds(updateDoc(doc(adminClaim(), 'users/victim'), { isAdmin: true, role: 'admin', isP2pAgent: true }));
    await assertSucceeds(setDoc(doc(adminClaim(), 'users/newagent'), userProfile('newagent', { role: 'agent', isP2pAgent: true, tyxBalance: 0 })));
    await assertSucceeds(setDoc(doc(user('signup'), 'users/signup'), userProfile('signup', { tyxBalance: 0, reservedBalance: 0 })));
  });

  it('an agent can still moderate a non-privilege field', async () => {
    await base();
    await assertSucceeds(updateDoc(doc(user('agent1'), 'users/victim'), { banned: true, headline: 'held' }));
  });
});

describe('paid entitlement writes', () => {
  it('agent, doc-flag staff, and the owner cannot grant premium on users or wallets', async () => {
    await base();
    const agent = user('agent1');
    await assertFails(updateDoc(doc(agent, 'users/victim'), { isPremium: true, premiumUntil: 1893456000000 }));
    await assertFails(setDoc(doc(agent, 'users/prem'), userProfile('prem', { isPremium: true, premiumUntil: 1893456000000, tyxBalance: 0 })));
    await assertFails(updateDoc(doc(agent, 'wallets/victim'), { isPremium: true, premiumUntil: 1893456000000 }));
    await assertFails(setDoc(doc(agent, 'wallets/other'), { uid: 'other', isPremium: true, premiumUntil: 1 }));
    await assertFails(updateDoc(doc(user('flag'), 'users/victim'), { isPremium: true }));
    await assertFails(updateDoc(doc(user('victim'), 'users/victim'), { isPremium: true, premiumUntil: 1893456000000 }));
    await assertFails(setDoc(doc(user('victim'), 'wallets/victim'), { isPremium: true }, { merge: true }));
    await assertFails(updateDoc(doc(user('victim'), 'wallets/victim'), { isPremium: true }));
  });

  it('an agent cannot delete someone else\'s wallet; a claim admin can grant premium', async () => {
    await base();
    await assertFails(deleteDoc(doc(user('agent1'), 'wallets/victim')));
    await assertSucceeds(updateDoc(doc(adminClaim(), 'users/victim'), { isPremium: true, premiumUntil: 1893456000000, accountType: 'hybrid' }));
    await assertSucceeds(updateDoc(doc(adminClaim(), 'wallets/victim'), { isPremium: true, premiumUntil: 1893456000000 }));
  });

  it('the owner can still downgrade premium and edit a non-entitlement wallet field', async () => {
    await seed({
      'users/victim': userProfile('victim', { isPremium: true, premiumUntil: 1000, accountType: 'hybrid' }),
      'wallets/victim': { uid: 'victim', balance: 10 },
    });
    await assertSucceeds(updateDoc(doc(user('victim'), 'users/victim'), { isPremium: false, premiumUntil: null, accountType: 'nyxian' }));
    await assertSucceeds(updateDoc(doc(user('victim'), 'wallets/victim'), { balance: 11 }));
  });
});

describe('staff_audit_log least privilege', () => {
  it('only an admin custom claim can read; agents, doc flags, and clients cannot write', async () => {
    await base();
    await assertSucceeds(getDoc(doc(adminClaim(), 'staff_audit_log/op1')));
    await assertFails(getDoc(doc(user('agent1'), 'staff_audit_log/op1')));
    await assertFails(getDoc(doc(user('flag'), 'staff_audit_log/op1')));
    await assertFails(getDoc(doc(user('victim'), 'staff_audit_log/op1')));
    await assertFails(setDoc(doc(adminClaim(), 'staff_audit_log/op2'), { action: 'x' }));
    await assertFails(setDoc(doc(user('agent1'), 'staff_audit_log/op2'), { action: 'x' }));
  });
});
