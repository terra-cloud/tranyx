import { createPublicKey, randomBytes, verify } from 'node:crypto';
import { HttpsError } from 'firebase-functions/https';
import { type DocumentReference, type DocumentSnapshot, type Firestore } from 'firebase-admin/firestore';
import { PublicKey } from '@solana/web3.js';
import bs58 from 'bs58';

/**
 * Sign-In With Solana for tranyx.app.
 *
 * The browser (or app) only ever proves it holds a wallet key by signing a one-time message the server
 * issued. The server verifies the ed25519 signature, and only the server (Admin SDK) mints a Firebase
 * custom token. Linking a wallet to an account needs the same proof, so `wallet_verified/{wallet}`
 * (Admin-only, no client rule) is the authority for "this account really owns this wallet".
 * `walletLinks/{wallet}` (client-writable) is only an index and is never trusted for sign-in.
 *
 * Collections (no Firestore rule matches them: only the Admin SDK can touch them):
 *   wallet_auth_nonces/{nonce}   one-time challenge   { wallet, purpose, domain, issuedAt, expiresAt }
 *   wallet_auth_tickets/{ticket} proof that a wallet signed in but has no account yet (sign-up)
 *   wallet_verified/{wallet}     { uid, verifiedAt }  written by walletAuthLink only
 */

export const NONCE_TTL_MS = 5 * 60 * 1000;
export const TICKET_TTL_MS = 15 * 60 * 1000;

export type Purpose = 'signin' | 'link';

export type WalletRejectReason =
  | 'WALLET_LINKED_TO_ANOTHER_ACCOUNT'
  | 'WALLET_NOT_VERIFIED'
  | 'ACCOUNT_BLOCKED'
  | 'STAFF_ACCOUNT';

export interface AuthAdmin {
  createCustomToken(uid: string): Promise<string>;
  getUser(uid: string): Promise<{ disabled?: boolean; customClaims?: Record<string, unknown> | undefined }>;
}

export interface WalletAuthDeps {
  db: Firestore;
  auth: AuthAdmin;
  now: () => number;
  /** Hostnames a challenge may be issued for (the browser's Origin must be one of them). */
  allowedDomains: string[];
  token?: () => string;
}

const hex = (n: number) => randomBytes(n).toString('hex');

// ── validation helpers (pure) ──────────────────────────────────────────────────────────────────
export function parseWallet(v: unknown): string {
  const s = typeof v === 'string' ? v.trim() : '';
  try {
    if (!/^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(s)) throw new Error('shape');
    const pk = new PublicKey(s);
    if (pk.toBytes().length !== 32) throw new Error('len');
    return s;
  } catch {
    throw new HttpsError('invalid-argument', 'wallet is not a valid Solana address.');
  }
}

export function parsePurpose(v: unknown): Purpose {
  if (v === 'signin' || v === 'link') return v;
  throw new HttpsError('invalid-argument', "purpose must be 'signin' or 'link'.");
}

/** Hostname of an Origin header if (and only if) it is an allowed domain. */
export function allowedHost(origin: unknown, allowed: string[]): string | null {
  if (typeof origin !== 'string') return null;
  try {
    const u = new URL(origin);
    if (u.protocol !== 'https:' && u.hostname !== 'localhost' && u.hostname !== '127.0.0.1') return null;
    return allowed.includes(u.hostname) ? u.hostname : null;
  } catch {
    return null;
  }
}

export interface Challenge {
  wallet: string;
  purpose: Purpose;
  domain: string;
  nonce: string;
  issuedAt: number;
  expiresAt: number;
}

/** Sign-In With Solana style message. Plain text so every wallet can show it. */
export function buildMessage(c: Challenge): string {
  const action = c.purpose === 'link' ? 'link your Solana account' : 'sign in with your Solana account';
  return [
    `${c.domain} wants you to ${action}:`,
    c.wallet,
    '',
    `Tranyx wallet ${c.purpose === 'link' ? 'linking' : 'sign-in'}. This only proves you own this wallet. It sends no transaction and costs nothing.`,
    '',
    `URI: https://${c.domain}`,
    'Version: 1',
    `Nonce: ${c.nonce}`,
    `Issued At: ${new Date(c.issuedAt).toISOString()}`,
    `Expiration Time: ${new Date(c.expiresAt).toISOString()}`,
  ].join('\n');
}

// ed25519 SubjectPublicKeyInfo prefix (RFC 8410) so node:crypto can import a raw 32-byte key.
const SPKI_ED25519 = Buffer.from('302a300506032b6570032100', 'hex');

export function verifyWalletSignature(wallet: string, message: string, signature: unknown): boolean {
  try {
    if (typeof signature !== 'string' || signature.length < 80 || signature.length > 100) return false;
    // base64 (contains + / =) or base58 (what the web wallet bridge returns); both decode to 64 bytes.
    const sig = /[+/=]/.test(signature) ? Buffer.from(signature, 'base64') : Buffer.from(bs58.decode(signature));
    if (sig.length !== 64) return false;
    const key = createPublicKey({ key: Buffer.concat([SPKI_ED25519, new PublicKey(wallet).toBuffer()]), format: 'der', type: 'spki' });
    return verify(null, Buffer.from(message, 'utf8'), key, sig);
  } catch {
    return false;
  }
}

const STAFF_ROLES = ['admin', 'staff', 'support', 'agent', 'p2p_agent', 'super_admin', 'superadmin'];
export function isStaffLike(userDoc: Record<string, unknown> | undefined, claims: Record<string, unknown> | undefined): boolean {
  const d = userDoc ?? {};
  const c = claims ?? {};
  const role = (v: unknown) => typeof v === 'string' && STAFF_ROLES.includes(v.toLowerCase());
  return (
    d.isAdmin === true || d.isStaff === true || d.isSuperAdmin === true || d.isP2pAgent === true || role(d.role) ||
    c.admin === true || c.superadmin === true || role(c.role)
  );
}

// ── callables' cores ───────────────────────────────────────────────────────────────────────────
export interface NonceResult {
  nonce: string;
  message: string;
  issuedAt: number;
  expiresAt: number;
}

export async function issueNonce(deps: WalletAuthDeps, data: unknown, origin: unknown): Promise<NonceResult> {
  const d = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  const wallet = parseWallet(d.wallet);
  const purpose = parsePurpose(d.purpose);
  const domain = allowedHost(origin, deps.allowedDomains);
  if (!domain) throw new HttpsError('permission-denied', 'This site is not allowed to request a wallet sign-in.');
  const issuedAt = deps.now();
  const c: Challenge = { wallet, purpose, domain, nonce: (deps.token ?? (() => hex(16)))(), issuedAt, expiresAt: issuedAt + NONCE_TTL_MS };
  await deps.db.doc(`wallet_auth_nonces/${c.nonce}`).create({ ...c });
  return { nonce: c.nonce, message: buildMessage(c), issuedAt: c.issuedAt, expiresAt: c.expiresAt };
}

/** Reads + deletes the nonce in one transaction (single use) and checks the signature against the stored challenge. */
async function consumeProof(deps: WalletAuthDeps, wallet: string, purpose: Purpose, nonce: unknown, signature: unknown): Promise<boolean> {
  const n = typeof nonce === 'string' ? nonce.trim() : '';
  if (!/^[0-9a-f]{32}$/.test(n)) throw new HttpsError('invalid-argument', 'nonce is not valid.');
  const ref = deps.db.doc(`wallet_auth_nonces/${n}`);
  return deps.db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) return false; // unknown or already used
    const c = snap.data() as Challenge;
    t.delete(ref); // a nonce gets exactly one attempt, valid or not
    if (c.wallet !== wallet || c.purpose !== purpose || deps.now() > c.expiresAt) return false;
    return verifyWalletSignature(wallet, buildMessage({ ...c, nonce: n }), signature);
  });
}

export type SignInResult =
  | { status: 'signed_in'; customToken: string }
  | { status: 'needs_signup'; ticket: string; expiresAt: number }
  | { status: 'rejected'; reason: WalletRejectReason | 'BAD_SIGNATURE' | 'WALLET_LINK_UNVERIFIED' };

export async function walletSignIn(deps: WalletAuthDeps, data: unknown): Promise<SignInResult> {
  const d = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  const wallet = parseWallet(d.wallet);
  if (!(await consumeProof(deps, wallet, 'signin', d.nonce, d.signature))) return { status: 'rejected', reason: 'BAD_SIGNATURE' };

  const { db } = deps;
  const [verifiedSnap, link] = await Promise.all([db.doc(`wallet_verified/${wallet}`).get(), db.doc(`walletLinks/${wallet}`).get()]);
  // A proof is only live while the owner's profile still names the wallet (unlinking clears users.walletPublicKey).
  const owner = verifiedSnap.exists ? await db.doc(`users/${String(verifiedSnap.get('uid'))}`).get() : null;
  const verified = { exists: !!owner && owner.exists && owner.get('walletPublicKey') === wallet, get: (k: string) => verifiedSnap.get(k) };

  if (!verified.exists) {
    // A walletLinks entry that was never proven (written by a client): it must not log anyone in.
    if (link.exists) return { status: 'rejected', reason: 'WALLET_LINK_UNVERIFIED' };
    const ticket = hex(24);
    const expiresAt = deps.now() + TICKET_TTL_MS;
    await db.doc(`wallet_auth_tickets/${ticket}`).create({ wallet, issuedAt: deps.now(), expiresAt });
    return { status: 'needs_signup', ticket, expiresAt };
  }

  const uid = String(verified.get('uid'));
  // The index must still agree; if a client re-pointed it, refuse rather than guess.
  if (link.exists && link.get('uid') !== uid) return { status: 'rejected', reason: 'WALLET_LINK_UNVERIFIED' };

  const [userDoc, userRec] = await Promise.all([db.doc(`users/${uid}`).get(), deps.auth.getUser(uid).catch(() => null)]);
  if (!userRec || userRec.disabled) return { status: 'rejected', reason: 'ACCOUNT_BLOCKED' };
  const u = userDoc.data() as Record<string, unknown> | undefined;
  if (u && (u.banned === true || (typeof u.suspendedUntil === 'number' && u.suspendedUntil > deps.now()))) {
    return { status: 'rejected', reason: 'ACCOUNT_BLOCKED' };
  }
  // Staff / admin / agent accounts never sign in to tranyx.app (they use the admin portal).
  if (isStaffLike(u, userRec.customClaims)) return { status: 'rejected', reason: 'STAFF_ACCOUNT' };

  return { status: 'signed_in', customToken: await deps.auth.createCustomToken(uid) };
}

export type LinkResult =
  | { status: 'linked'; wallet: string }
  | { status: 'rejected'; reason: WalletRejectReason | 'BAD_SIGNATURE' | 'BAD_TICKET' };

/**
 * Links a PROVEN wallet to the caller. Proof is either a sign-up `ticket` (from walletSignIn) or a fresh
 * { wallet, nonce, signature } for purpose 'link'. One wallet per account, both ways.
 */
export async function walletLink(deps: WalletAuthDeps, uid: string | undefined, data: unknown): Promise<LinkResult> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const d = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  const { db } = deps;

  let wallet: string;
  let ticketRef: DocumentReference | null = null;
  if (typeof d.ticket === 'string' && d.ticket) {
    if (!/^[0-9a-f]{48}$/.test(d.ticket)) throw new HttpsError('invalid-argument', 'ticket is not valid.');
    ticketRef = db.doc(`wallet_auth_tickets/${d.ticket}`);
    const t = await ticketRef.get();
    if (!t.exists || deps.now() > (t.get('expiresAt') as number)) return { status: 'rejected', reason: 'BAD_TICKET' };
    wallet = String(t.get('wallet'));
  } else {
    wallet = parseWallet(d.wallet);
    if (!(await consumeProof(deps, wallet, 'link', d.nonce, d.signature))) return { status: 'rejected', reason: 'BAD_SIGNATURE' };
  }

  const userRef = db.doc(`users/${uid}`);
  const linkRef = db.doc(`walletLinks/${wallet}`);
  const verRef = db.doc(`wallet_verified/${wallet}`);

  return db.runTransaction(async (t): Promise<LinkResult> => {
    const [user, link, ver, ticket] = await Promise.all([t.get(userRef), t.get(linkRef), t.get(verRef), ticketRef ? t.get(ticketRef) : Promise.resolve(null)]);
    if (ticketRef && (!ticket || !ticket.exists)) return { status: 'rejected', reason: 'BAD_TICKET' }; // used meanwhile
    if (!user.exists) throw new HttpsError('failed-precondition', 'Profile not found.');
    const u = user.data() as Record<string, unknown>;
    if (u.banned === true || (typeof u.suspendedUntil === 'number' && u.suspendedUntil > deps.now())) {
      return { status: 'rejected', reason: 'ACCOUNT_BLOCKED' };
    }
    // Proven by someone else already: hands off.
    // (Stale proof: the previous owner unlinked it, so their profile no longer names the wallet.)
    let liveVer = ver.exists;
    if (ver.exists && ver.get('uid') !== uid) {
      const ownerSnap = await t.get(db.doc(`users/${String(ver.get('uid'))}`));
      liveVer = ownerSnap.exists && ownerSnap.get('walletPublicKey') === wallet;
      if (liveVer) return { status: 'rejected', reason: 'WALLET_LINKED_TO_ANOTHER_ACCOUNT' };
    }

    // The caller's previous wallet (one wallet per account) is released.
    const prev = typeof u.walletPublicKey === 'string' ? u.walletPublicKey : '';
    let prevLink: DocumentSnapshot | null = null;
    let prevVer: DocumentSnapshot | null = null;
    // An unproven squatter on this wallet loses it: the signature proves who really holds the key.
    let squatter: DocumentSnapshot | null = null;
    const squatUid = !liveVer && link.exists && link.get('uid') !== uid ? String(link.get('uid')) : '';
    if (prev && prev !== wallet) [prevLink, prevVer] = await Promise.all([t.get(db.doc(`walletLinks/${prev}`)), t.get(db.doc(`wallet_verified/${prev}`))]);
    if (squatUid) squatter = await t.get(db.doc(`users/${squatUid}`));

    if (prev && prev !== wallet) {
      if (prevLink?.exists && prevLink.get('uid') === uid) t.delete(prevLink.ref);
      if (prevVer?.exists && prevVer.get('uid') === uid) t.delete(prevVer.ref);
    }
    if (squatter?.exists && squatter.get('walletPublicKey') === wallet) t.update(squatter.ref, { walletPublicKey: '' });

    t.set(linkRef, { uid, linkedAt: deps.now() });
    t.set(verRef, { uid, verifiedAt: deps.now() });
    t.update(userRef, { walletPublicKey: wallet });
    if (ticketRef) t.delete(ticketRef);
    return { status: 'linked', wallet };
  });
}
