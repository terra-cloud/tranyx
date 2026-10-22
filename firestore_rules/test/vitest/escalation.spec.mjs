// CRITICAL: privilege escalation. KNOWN-HOLE tests carry the SECURE assertion inside knownHole():
// green today because the hole exists; they error the moment a rules fix closes the hole (remove the marker then).
import { describe, it } from 'vitest';
import { expect } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { knownHole, setupEnv, seed, user, adminClaim, userProfile, withdrawal } from './helpers.mjs';

setupEnv();

const victimSeed = () => seed({
  'users/victim': userProfile('victim'),
  'withdrawal_requests/wr1': withdrawal('victim'),
  'system_config/treasury': { solanaTreasuryPubkey: 'TREASURY_PLACEHOLDER', note: 'test fixture, no secret' },
});

describe('ESC: fresh signup self-granted role flags', () => {
  for (const flag of ['isAdmin', 'isStaff', 'isP2pAgent']) {
    knownHole(`KNOWN-HOLE ESC-01-${flag} [CRITICAL] fresh signup cannot create users/{uid} with ${flag}:true (10_workspace_users_wallets.rules:12 / compiled:122)`, async () => {
      await assertFails(setDoc(doc(user('attacker'), 'users/attacker'), userProfile('attacker', { [flag]: true })));
    });
  }

  it('ESC-01-role [CRITICAL] fresh signup cannot create users/{uid} with role:"admin" (blocked today, must stay blocked)', async () => {
    await assertFails(setDoc(doc(user('attacker'), 'users/attacker'), userProfile('attacker', { role: 'admin' })));
  });

  // Attacker doc carries the flag (as ESC-01 shows it can today). Does the flag alone grant admin power?
  for (const flag of ['isAdmin', 'isStaff', 'isP2pAgent']) {
    describe(`with users/attacker.${flag}=true and NO custom claim`, () => {
      const prep = async () => { await victimSeed(); await seed({ 'users/attacker': userProfile('attacker', { [flag]: true }) }); };
      knownHole(`KNOWN-HOLE ESC-02-${flag} [CRITICAL] cannot edit another user's tyxBalance (02_admin_helpers.rules:37-46 isUserAdminInDoc / compiled:88-97,138)`, async () => {
        await prep();
        await assertFails(updateDoc(doc(user('attacker'), 'users/victim'), { tyxBalance: 0 }));
      });
      knownHole(`KNOWN-HOLE ESC-03-${flag} [CRITICAL] cannot approve another user's withdrawal (compiled:247 via isAdminOrStaff)`, async () => {
        await prep();
        await assertFails(updateDoc(doc(user('attacker'), 'withdrawal_requests/wr1'), { status: 'APPROVED', approvedBy: 'attacker' }));
      });
      knownHole(`KNOWN-HOLE ESC-04-${flag} [CRITICAL] cannot write p2p_agents for another uid (60_admin_portal_operations.rules:8 / compiled:919)`, async () => {
        await prep();
        await assertFails(setDoc(doc(user('attacker'), 'p2p_agents/victim'), { uid: 'victim', role: 'agent', isActive: true }));
      });
      knownHole(`KNOWN-HOLE ESC-05-${flag} [CRITICAL] cannot read system_config/treasury (compiled:986)`, async () => {
        await prep();
        await assertFails(getDoc(doc(user('attacker'), 'system_config/treasury')));
      });
    });
  }
});

describe('ESC: unverified @tranyx.com email', () => {
  const unverified = () => user('impostor', { email: 'impostor@tranyx.com', email_verified: false });

  knownHole('KNOWN-HOLE ESC-06 [CRITICAL] unverified @tranyx.com cannot create own users doc with role:"admin" (isStaffEmail ignores email_verified: 02_admin_helpers.rules:6-12, 10_...:13 / compiled:57-63,123)', async () => {
    await assertFails(setDoc(doc(unverified(), 'users/impostor'), userProfile('impostor', { email: 'impostor@tranyx.com', role: 'admin', isAdmin: true })));
  });
  knownHole('KNOWN-HOLE ESC-07 [CRITICAL] unverified @tranyx.com cannot update own role (10_...:25 / compiled:135)', async () => {
    await seed({ 'users/impostor': userProfile('impostor', { email: 'impostor@tranyx.com' }) });
    await assertFails(updateDoc(doc(unverified(), 'users/impostor'), { role: 'admin', isAdmin: true }));
  });
  knownHole('KNOWN-HOLE ESC-08 [CRITICAL] unverified @tranyx.com cannot write p2p_agents/{own uid} (60_...:8 / compiled:919)', async () => {
    await assertFails(setDoc(doc(unverified(), 'p2p_agents/impostor'), { uid: 'impostor', email: 'impostor@tranyx.com', role: 'agent', isActive: true }));
  });
  it('ESC-09 [CRITICAL] unverified @tranyx.com with no role docs gets no staff read (system_config) — secure today', async () => {
    await victimSeed();
    await assertFails(getDoc(doc(unverified(), 'system_config/treasury')));
  });
  knownHole('KNOWN-HOLE ESC-10 [CRITICAL] unverified @tranyx.com gains no staff access after self-writing p2p_agents/{uid} (isP2pAgentInDoc: 02_...:50-52 / compiled:101-103)', async () => {
    await victimSeed();
    await seed({ 'p2p_agents/impostor': { uid: 'impostor', role: 'agent', isActive: true } }); // state ESC-08 lets them create
    await assertFails(updateDoc(doc(unverified(), 'users/victim'), { tyxBalance: 999999 }));
  });
});

describe('ESC: only the admin custom claim grants admin', () => {
  it('ESC-11 [HIGH] owner writing an unrecognised "admin": true field to own doc gains nothing', async () => {
    await victimSeed();
    await seed({ 'users/u1': userProfile('u1') });
    const db = user('u1');
    await assertSucceeds(updateDoc(doc(db, 'users/u1'), { admin: true })); // harmless field, allowed by owner branch
    await assertFails(updateDoc(doc(db, 'users/victim'), { tyxBalance: 0 }));
  });
  it('ESC-12 [CRITICAL] existing owner cannot update own role/isAdmin — secure today (10_...:20-22)', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    await assertFails(updateDoc(doc(user('u1'), 'users/u1'), { role: 'admin' }));
    await assertFails(updateDoc(doc(user('u1'), 'users/u1'), { isAdmin: true }));
  });
  knownHole('KNOWN-HOLE ESC-13 [HIGH] verified @tranyx.com email WITHOUT admin claim cannot do admin actions (email-domain admin: 02_...:28-30 / compiled:78-80)', async () => {
    await victimSeed();
    await assertFails(updateDoc(doc(user('emp', { email: 'emp@tranyx.com', email_verified: true }), 'users/victim'), { tyxBalance: 0 }));
  });
  knownHole('KNOWN-HOLE ESC-14 [HIGH] token.role:"support" claim without admin==true cannot edit balances (02_...:21-26 / compiled:71-76)', async () => {
    await victimSeed();
    await assertFails(updateDoc(doc(user('sup', { role: 'support' }), 'users/victim'), { tyxBalance: 0 }));
  });
  it('ESC-15 [MUST-ALLOW] request.auth.token.admin==true can edit balance and approve withdrawal', async () => {
    await victimSeed();
    await assertSucceeds(updateDoc(doc(adminClaim(), 'users/victim'), { tyxBalance: 50 }));
    await assertSucceeds(updateDoc(doc(adminClaim(), 'withdrawal_requests/wr1'), { status: 'APPROVED' }));
  });
});

describe('ESC-AGG fresh signup cannot reach admin by any path', () => {
  // Each path runs as a distinct fresh Gmail/tranyx identity THROUGH the rules (no seeding of the attacker doc),
  // then probes one admin-only action. Secure expectation: no path escalates.
  const paths = {
    'self-create isAdmin': async (db, uid) => setDoc(doc(db, `users/${uid}`), userProfile(uid, { isAdmin: true })),
    'self-create isStaff': async (db, uid) => setDoc(doc(db, `users/${uid}`), userProfile(uid, { isStaff: true })),
    'self-create isP2pAgent': async (db, uid) => setDoc(doc(db, `users/${uid}`), userProfile(uid, { isP2pAgent: true })),
    'self-create role:admin': async (db, uid) => setDoc(doc(db, `users/${uid}`), userProfile(uid, { role: 'admin' })),
    'self-create then update isAdmin': async (db, uid) => { await setDoc(doc(db, `users/${uid}`), userProfile(uid)); await updateDoc(doc(db, `users/${uid}`), { isAdmin: true }); },
    'self-write p2p_agents (gmail)': async (db, uid) => setDoc(doc(db, `p2p_agents/${uid}`), { uid, role: 'agent', isActive: true }),
    'unverified @tranyx.com p2p_agents': async (db, uid) => setDoc(doc(db, `p2p_agents/${uid}`), { uid, role: 'agent', isActive: true }),
  };
  knownHole('KNOWN-HOLE ESC-AGG [CRITICAL] no escalation path succeeds', async () => {
    await victimSeed();
    const escalated = [];
    let i = 0;
    for (const [name, attempt] of Object.entries(paths)) {
      const uid = `fresh${i++}`;
      const db = name.startsWith('unverified')
        ? user(uid, { email: `${uid}@tranyx.com`, email_verified: false })
        : user(uid);
      try { await attempt(db, uid); } catch { continue; } // path blocked at step 1
      try { await updateDoc(doc(db, 'users/victim'), { tyxBalance: 1000 + i }); escalated.push(name); } catch { /* denied */ }
    }
    console.log('ESC-AGG escalated via:', escalated);
    expect(escalated).toEqual([]);
  });
});
