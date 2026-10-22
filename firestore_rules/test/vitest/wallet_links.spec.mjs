// KAN-124: wallet sign-in removed. walletLinks is a signed-in-only, owner-written uid index with no credentials.
import { describe, it } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc } from 'firebase/firestore';
import { setupEnv, seed, user, guest, adminClaim, userProfile } from './helpers.mjs';

setupEnv();
const NOW = 1761123600000;
const ADDR = '9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin';
const NEW = 'NewAddr1111111111111111111111111111111111111';

describe('KWL: walletLinks after wallet sign-in removal', () => {
  it('KWL-01 [CRITICAL] guest cannot get a walletLinks doc (no pre-auth lookup)', async () => {
    await seed({ [`walletLinks/${ADDR}`]: { uid: 'victim', linkedAt: NOW } });
    await assertFails(getDoc(doc(guest(), `walletLinks/${ADDR}`)));
  });
  it('KWL-02 [CRITICAL] owner cannot store credentials on a link (refreshToken, password, email, provider)', async () => {
    await seed({ 'users/u1': userProfile('u1') });
    const db = user('u1');
    for (const extra of [{ refreshToken: 'x' }, { password: 'x' }, { email: 'u1@gmail.com' }, { provider: 'password' }])
      await assertFails(setDoc(doc(db, `walletLinks/${NEW}`), { uid: 'u1', linkedAt: NOW, ...extra }));
  });
  it('KWL-03 [HIGH] signed-in user cannot delete another user\'s link', async () => {
    await seed({ 'users/u2': userProfile('u2'), [`walletLinks/${ADDR}`]: { uid: 'victim', linkedAt: NOW } });
    await assertFails(deleteDoc(doc(user('u2'), `walletLinks/${ADDR}`)));
  });
  it('KWL-04 [MEDIUM] signed-in user cannot list walletLinks', async () => {
    await seed({ 'users/u2': userProfile('u2'), [`walletLinks/${ADDR}`]: { uid: 'victim', linkedAt: NOW } });
    await assertFails(getDocs(collection(user('u2'), 'walletLinks')));
  });
  it('KWL-05 [MUST-ALLOW] signed-in user reads a link for the one-wallet-one-account check (tranyx_app.dart, payment_pane.dart)', async () => {
    await seed({ 'users/u2': userProfile('u2'), [`walletLinks/${ADDR}`]: { uid: 'victim', linkedAt: NOW } });
    await assertSucceeds(getDoc(doc(user('u2'), `walletLinks/${ADDR}`)));
    await assertSucceeds(getDoc(doc(user('u2'), `walletLinks/${NEW}`)));
  });
  it('KWL-06 [MUST-ALLOW] owner re-links over a legacy doc that still holds a password (full replace drops it)', async () => {
    await seed({ 'users/u1': userProfile('u1'), [`walletLinks/${ADDR}`]: { uid: 'u1', email: 'u1@gmail.com', provider: 'password', password: 'legacy', linkedAt: NOW } });
    await assertSucceeds(setDoc(doc(user('u1'), `walletLinks/${ADDR}`), { uid: 'u1', linkedAt: NOW + 1 }));
  });
  it('KWL-07 [MUST-ALLOW] owner unlinks own wallet (tranyx_app.dart unlinkSolanaWallet, trust_pane.dart); admin lists and deletes', async () => {
    await seed({ 'users/u1': userProfile('u1'), [`walletLinks/${ADDR}`]: { uid: 'u1', linkedAt: NOW }, [`walletLinks/${NEW}`]: { uid: 'u3', linkedAt: NOW } });
    await assertSucceeds(deleteDoc(doc(user('u1'), `walletLinks/${ADDR}`)));
    await assertSucceeds(getDocs(collection(adminClaim(), 'walletLinks')));
    await assertSucceeds(deleteDoc(doc(adminClaim(), `walletLinks/${NEW}`)));
  });
});
