// Runs against the Firestore emulator (npm run test:emulator). Real ed25519 keys sign the challenge.
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { generateKeyPairSync, sign, type KeyObject } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import bs58 from 'bs58';
import {
  allowedHost, buildMessage, isStaffLike, issueNonce, parseWallet, verifyWalletSignature, walletLink, walletSignIn, walletStatus,
  type AuthAdmin, type WalletAuthDeps,
} from '../src/wallet_auth';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8189';
initializeApp({ projectId: 'demo-tranyx' });
const db = getFirestore();

interface Wallet { address: string; priv: KeyObject }
const newWallet = (): Wallet => {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  const raw = publicKey.export({ format: 'der', type: 'spki' }).subarray(-32);
  return { address: bs58.encode(raw), priv: privateKey };
};
const signMsg = (w: Wallet, msg: string) => sign(null, Buffer.from(msg, 'utf8'), w.priv).toString('base64');

const ORIGIN = 'https://dev.tranyx.app';
let clock = Date.UTC(2026, 9, 31, 4, 0, 0);
let disabled = new Set<string>();
let claims: Record<string, Record<string, unknown>> = {};
const auth: AuthAdmin = {
  createCustomToken: async (uid) => `custom-token-for-${uid}`,
  getUser: async (uid) => {
    if (uid === 'ghost') throw new Error('no user');
    return { disabled: disabled.has(uid), customClaims: claims[uid] };
  },
};
const deps = (): WalletAuthDeps => ({ db, auth, now: () => clock, allowedDomains: ['tranyx.app', 'dev.tranyx.app', 'localhost'] });
const err = async (p: Promise<unknown>) => p.then(() => null, (e) => e as { code: string });

async function clearAll() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-tranyx/databases/(default)/documents`, { method: 'DELETE' });
}
/** challenge -> signed proof for the given wallet */
async function proof(w: Wallet, purpose: 'signin' | 'link', signer: Wallet = w) {
  const n = await issueNonce(deps(), { wallet: w.address, purpose }, ORIGIN);
  return { wallet: w.address, nonce: n.nonce, signature: signMsg(signer, n.message) };
}
const seedUser = (uid: string, over: Record<string, unknown> = {}) => db.doc(`users/${uid}`).set({ name: uid, walletPublicKey: '', ...over });
const verified = (w: string) => db.doc(`wallet_verified/${w}`).get();
const links = (w: string) => db.doc(`walletLinks/${w}`).get();

beforeAll(clearAll);
beforeEach(async () => { await clearAll(); clock = Date.UTC(2026, 9, 31, 4, 0, 0); disabled = new Set(); claims = {}; });

describe('pure helpers', () => {
  it('parseWallet accepts a 32-byte base58 key only', () => {
    const w = newWallet();
    expect(parseWallet(w.address)).toBe(w.address);
    for (const bad of ['', 'abc', 'O0Il' .repeat(10), 5, null, bs58.encode(Buffer.alloc(31, 1))]) expect(() => parseWallet(bad)).toThrow();
  });
  it('allowedHost: https allowed domains and localhost only', () => {
    const a = ['tranyx.app', 'dev.tranyx.app', 'localhost'];
    expect(allowedHost('https://dev.tranyx.app', a)).toBe('dev.tranyx.app');
    expect(allowedHost('http://localhost:8197', a)).toBe('localhost');
    expect(allowedHost('http://dev.tranyx.app', a)).toBeNull();
    expect(allowedHost('https://tranyx.app.evil.com', a)).toBeNull();
    expect(allowedHost('https://evil.com', a)).toBeNull();
    expect(allowedHost(undefined, a)).toBeNull();
    expect(allowedHost('not a url', a)).toBeNull();
  });
  it('verifyWalletSignature: valid, tampered message, wrong key, junk', () => {
    const w = newWallet(); const o = newWallet();
    const sig = signMsg(w, 'hello');
    expect(verifyWalletSignature(w.address, 'hello', sig)).toBe(true);
    expect(verifyWalletSignature(w.address, 'hello!', sig)).toBe(false);
    expect(verifyWalletSignature(o.address, 'hello', sig)).toBe(false);
    // the web wallet bridge sends base58
    expect(verifyWalletSignature(w.address, 'hello', bs58.encode(Buffer.from(sig, 'base64')))).toBe(true);
    expect(verifyWalletSignature(w.address, 'hello!', bs58.encode(Buffer.from(sig, 'base64')))).toBe(false);
    expect(verifyWalletSignature(w.address, 'hello', 'AAAA')).toBe(false);
    expect(verifyWalletSignature(w.address, 'hello', undefined)).toBe(false);
  });
  it('buildMessage names the domain, wallet, nonce and expiry', () => {
    const m = buildMessage({ wallet: 'W', purpose: 'signin', domain: 'dev.tranyx.app', nonce: 'n1', issuedAt: 0, expiresAt: 60000 });
    expect(m).toContain('dev.tranyx.app wants you to sign in with your Solana account:\nW');
    expect(m).toContain('Nonce: n1');
    expect(m).toContain('Expiration Time: 1970-01-01T00:01:00.000Z');
  });
  it('isStaffLike reads user-doc flags/roles and token claims', () => {
    expect(isStaffLike({ role: 'STAFF' }, undefined)).toBe(true);
    expect(isStaffLike({ isP2pAgent: true }, undefined)).toBe(true);
    expect(isStaffLike({}, { admin: true })).toBe(true);
    expect(isStaffLike({ role: 'nyxian' }, {})).toBe(false);
    expect(isStaffLike(undefined, undefined)).toBe(false);
  });
});

describe('walletAuthNonce (issueNonce)', () => {
  it('rejects a bad wallet, a bad purpose and a foreign origin', async () => {
    const w = newWallet();
    expect((await err(issueNonce(deps(), { wallet: 'x', purpose: 'signin' }, ORIGIN)))?.code).toBe('invalid-argument');
    expect((await err(issueNonce(deps(), { wallet: w.address, purpose: 'admin' }, ORIGIN)))?.code).toBe('invalid-argument');
    expect((await err(issueNonce(deps(), { wallet: w.address, purpose: 'signin' }, 'https://evil.example')))?.code).toBe('permission-denied');
    expect((await err(issueNonce(deps(), { wallet: w.address, purpose: 'signin' }, undefined)))?.code).toBe('permission-denied');
  });
  it('stores a challenge bound to wallet, purpose and domain', async () => {
    const w = newWallet();
    const n = await issueNonce(deps(), { wallet: w.address, purpose: 'signin' }, ORIGIN);
    const d = (await db.doc(`wallet_auth_nonces/${n.nonce}`).get()).data()!;
    expect(d).toMatchObject({ wallet: w.address, purpose: 'signin', domain: 'dev.tranyx.app' });
    expect(n.message).toContain(w.address);
  });
});

describe('walletAuthSignIn', () => {
  it('unknown wallet with a valid signature -> sign-up ticket, no token', async () => {
    const w = newWallet();
    const r = await walletSignIn(deps(), await proof(w, 'signin'));
    expect(r.status).toBe('needs_signup');
    expect(JSON.stringify(r)).not.toContain('custom-token');
    const ticket = (r as any).ticket as string;
    expect((await db.doc(`wallet_auth_tickets/${ticket}`).get()).get('wallet')).toBe(w.address);
  });

  it('a signature from another key is refused (and burns the nonce)', async () => {
    const w = newWallet(); const attacker = newWallet();
    const p = await proof(w, 'signin', attacker);
    expect(await walletSignIn(deps(), p)).toEqual({ status: 'rejected', reason: 'BAD_SIGNATURE' });
    // even the right signature cannot reuse that nonce
    const n = await db.doc(`wallet_auth_nonces/${p.nonce}`).get();
    expect(n.exists).toBe(false);
  });

  it('a nonce works once; replay is refused', async () => {
    const w = newWallet();
    const p = await proof(w, 'signin');
    expect((await walletSignIn(deps(), p)).status).toBe('needs_signup');
    expect(await walletSignIn(deps(), p)).toEqual({ status: 'rejected', reason: 'BAD_SIGNATURE' });
  });

  it('an expired challenge is refused', async () => {
    const w = newWallet();
    const p = await proof(w, 'signin');
    clock += 5 * 60 * 1000 + 1;
    expect(await walletSignIn(deps(), p)).toEqual({ status: 'rejected', reason: 'BAD_SIGNATURE' });
  });

  it('a signature for the wrong purpose or another wallet cannot be replayed here', async () => {
    const w = newWallet(); const other = newWallet();
    const link = await proof(w, 'link');
    expect(await walletSignIn(deps(), link)).toEqual({ status: 'rejected', reason: 'BAD_SIGNATURE' });
    const p = await proof(w, 'signin');
    expect(await walletSignIn(deps(), { ...p, wallet: other.address })).toEqual({ status: 'rejected', reason: 'BAD_SIGNATURE' });
  });

  it('malformed nonce / wallet -> invalid-argument', async () => {
    const w = newWallet();
    expect((await err(walletSignIn(deps(), { wallet: w.address, nonce: 'zz', signature: 'x' })))?.code).toBe('invalid-argument');
    expect((await err(walletSignIn(deps(), { wallet: 'nope', nonce: 'a'.repeat(32), signature: 'x' })))?.code).toBe('invalid-argument');
  });

  it('a verified wallet signs in: server mints the custom token for the owner', async () => {
    const w = newWallet();
    await seedUser('u1', { walletPublicKey: w.address });
    await db.doc(`walletLinks/${w.address}`).set({ uid: 'u1', linkedAt: 1 });
    await db.doc(`wallet_verified/${w.address}`).set({ uid: 'u1', verifiedAt: 1 });
    expect(await walletSignIn(deps(), await proof(w, 'signin'))).toEqual({ status: 'signed_in', customToken: 'custom-token-for-u1' });
  });

  it('an UNVERIFIED walletLinks entry (client-written) never signs anyone in', async () => {
    const victim = newWallet();
    await seedUser('attacker', { walletPublicKey: victim.address });
    await db.doc(`walletLinks/${victim.address}`).set({ uid: 'attacker', linkedAt: 1 });
    const r = await walletSignIn(deps(), await proof(victim, 'signin'));
    expect(r).toEqual({ status: 'rejected', reason: 'WALLET_LINK_UNVERIFIED' });
    expect(JSON.stringify(r)).not.toContain('custom-token');
  });

  it('a link index re-pointed to another uid is refused', async () => {
    const w = newWallet();
    await seedUser('u1'); await seedUser('u2');
    await db.doc(`walletLinks/${w.address}`).set({ uid: 'u2', linkedAt: 1 });
    await db.doc(`wallet_verified/${w.address}`).set({ uid: 'u1', verifiedAt: 1 });
    expect(await walletSignIn(deps(), await proof(w, 'signin'))).toEqual({ status: 'rejected', reason: 'WALLET_LINK_UNVERIFIED' });
  });

  it.each([
    ['staff by users doc role', { role: 'staff' }, undefined],
    ['admin flag', { isAdmin: true }, undefined],
    ['p2p agent', { isP2pAgent: true }, undefined],
    ['admin token claim', {}, { admin: true }],
  ])('staff accounts cannot sign in: %s', async (_n, doc, cl) => {
    const w = newWallet();
    await seedUser('s1', { walletPublicKey: w.address, ...doc });
    if (cl) claims['s1'] = cl;
    await db.doc(`wallet_verified/${w.address}`).set({ uid: 's1', verifiedAt: 1 });
    expect(await walletSignIn(deps(), await proof(w, 'signin'))).toEqual({ status: 'rejected', reason: 'STAFF_ACCOUNT' });
  });

  it('after the owner unlinks (profile cleared), the old proof no longer signs in', async () => {
    const w = newWallet();
    await seedUser('u1', { walletPublicKey: '' });
    await db.doc(`wallet_verified/${w.address}`).set({ uid: 'u1', verifiedAt: 1 });
    expect((await walletSignIn(deps(), await proof(w, 'signin'))).status).toBe('needs_signup');
  });

  it('banned, suspended, disabled and deleted accounts cannot sign in', async () => {
    for (const [uid, doc] of [['b', { banned: true }], ['s', { suspendedUntil: clock + 1000 }], ['d', {}], ['ghost', {}]] as const) {
      const w = newWallet();
      await seedUser(uid, { walletPublicKey: w.address, ...doc });
      if (uid === 'd') disabled.add('d');
      await db.doc(`wallet_verified/${w.address}`).set({ uid, verifiedAt: 1 });
      expect(await walletSignIn(deps(), await proof(w, 'signin'))).toEqual({ status: 'rejected', reason: 'ACCOUNT_BLOCKED' });
    }
  });
});

describe('walletAuthLink', () => {
  it('requires a signed-in caller', async () => {
    expect((await err(walletLink(deps(), undefined, {})))?.code).toBe('unauthenticated');
  });

  it('sign-up: ticket from sign-in links the wallet to the new account, once', async () => {
    const w = newWallet();
    const r = (await walletSignIn(deps(), await proof(w, 'signin'))) as any;
    await seedUser('new1');
    expect(await walletLink(deps(), 'new1', { ticket: r.ticket })).toEqual({ status: 'linked', wallet: w.address });
    expect((await db.doc('users/new1').get()).get('walletPublicKey')).toBe(w.address);
    expect((await links(w.address)).get('uid')).toBe('new1');
    expect((await verified(w.address)).get('uid')).toBe('new1');
    // ticket is single use
    await seedUser('new2');
    expect(await walletLink(deps(), 'new2', { ticket: r.ticket })).toEqual({ status: 'rejected', reason: 'BAD_TICKET' });
    // and the wallet now signs in as new1
    expect(await walletSignIn(deps(), await proof(w, 'signin'))).toEqual({ status: 'signed_in', customToken: 'custom-token-for-new1' });
  });

  it('an expired or forged ticket is refused', async () => {
    const w = newWallet();
    const r = (await walletSignIn(deps(), await proof(w, 'signin'))) as any;
    await seedUser('u');
    clock += 15 * 60 * 1000 + 1;
    expect(await walletLink(deps(), 'u', { ticket: r.ticket })).toEqual({ status: 'rejected', reason: 'BAD_TICKET' });
    expect(await walletLink(deps(), 'u', { ticket: 'f'.repeat(48) })).toEqual({ status: 'rejected', reason: 'BAD_TICKET' });
    expect((await err(walletLink(deps(), 'u', { ticket: 'short' })))?.code).toBe('invalid-argument');
  });

  it('profile link: needs a fresh signature from that wallet', async () => {
    const w = newWallet(); const attacker = newWallet();
    await seedUser('u1');
    expect(await walletLink(deps(), 'u1', await proof(w, 'link', attacker))).toEqual({ status: 'rejected', reason: 'BAD_SIGNATURE' });
    expect((await verified(w.address)).exists).toBe(false);
    expect(await walletLink(deps(), 'u1', await proof(w, 'link'))).toEqual({ status: 'linked', wallet: w.address });
    // a SIGN-IN signature cannot be used to link
    const w2 = newWallet();
    expect(await walletLink(deps(), 'u1', await proof(w2, 'signin'))).toEqual({ status: 'rejected', reason: 'BAD_SIGNATURE' });
  });

  it('a wallet proven by another account cannot be linked to a second account', async () => {
    const w = newWallet();
    await seedUser('a'); await seedUser('b');
    expect((await walletLink(deps(), 'a', await proof(w, 'link'))).status).toBe('linked');
    expect(await walletLink(deps(), 'b', await proof(w, 'link'))).toEqual({ status: 'rejected', reason: 'WALLET_LINKED_TO_ANOTHER_ACCOUNT' });
    expect((await links(w.address)).get('uid')).toBe('a');
  });

  it('a wallet the previous owner unlinked can be linked by another account', async () => {
    const w = newWallet();
    await seedUser('old', { walletPublicKey: '' });
    await db.doc(`wallet_verified/${w.address}`).set({ uid: 'old', verifiedAt: 1 });
    await seedUser('new');
    expect(await walletLink(deps(), 'new', await proof(w, 'link'))).toEqual({ status: 'linked', wallet: w.address });
    expect((await verified(w.address)).get('uid')).toBe('new');
  });

  it('a squatter who linked a wallet without proof loses it to the real key holder', async () => {
    const w = newWallet();
    await seedUser('squatter', { walletPublicKey: w.address });
    await db.doc(`walletLinks/${w.address}`).set({ uid: 'squatter', linkedAt: 1 });
    await seedUser('owner');
    expect(await walletLink(deps(), 'owner', await proof(w, 'link'))).toEqual({ status: 'linked', wallet: w.address });
    expect((await links(w.address)).get('uid')).toBe('owner');
    expect((await db.doc('users/squatter').get()).get('walletPublicKey')).toBe('');
  });

  it('relinking releases the previous wallet (one wallet per account)', async () => {
    const w1 = newWallet(); const w2 = newWallet();
    await seedUser('u');
    await walletLink(deps(), 'u', await proof(w1, 'link'));
    await walletLink(deps(), 'u', await proof(w2, 'link'));
    expect((await links(w1.address)).exists).toBe(false);
    expect((await verified(w1.address)).exists).toBe(false);
    expect((await db.doc('users/u').get()).get('walletPublicKey')).toBe(w2.address);
  });

  it('banned accounts cannot link; missing profile is a failed-precondition', async () => {
    const w = newWallet();
    await seedUser('bad', { banned: true });
    expect(await walletLink(deps(), 'bad', await proof(w, 'link'))).toEqual({ status: 'rejected', reason: 'ACCOUNT_BLOCKED' });
    const w2 = newWallet();
    expect((await err(walletLink(deps(), 'nobody', await proof(w2, 'link'))))?.code).toBe('failed-precondition');
  });
});

describe('walletAuthStatus (walletStatus)', () => {
  it('requires sign-in; reports linked/verified for the caller only', async () => {
    expect((await err(walletStatus(deps(), undefined)))?.code).toBe('unauthenticated');
    const w = newWallet();
    await seedUser('u');
    expect(await walletStatus(deps(), 'u')).toEqual({ wallet: '', linked: false, verified: false });
    // a client-written claim (profile key + index) is not proof
    await db.doc('users/u').update({ walletPublicKey: w.address });
    await db.doc(`walletLinks/${w.address}`).set({ uid: 'u', linkedAt: 1 });
    expect(await walletStatus(deps(), 'u')).toEqual({ wallet: w.address, linked: true, verified: false });
    // proof for someone else's uid does not count
    await db.doc(`wallet_verified/${w.address}`).set({ uid: 'other', verifiedAt: 1 });
    expect((await walletStatus(deps(), 'u')).verified).toBe(false);
    // re-linking the same wallet with a signature verifies it
    expect(await walletLink(deps(), 'u', await proof(w, 'link'))).toEqual({ status: 'linked', wallet: w.address });
    expect(await walletStatus(deps(), 'u')).toEqual({ wallet: w.address, linked: true, verified: true });
  });
});
