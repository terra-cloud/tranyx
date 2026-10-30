import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { onCall, HttpsError } from 'firebase-functions/https';
import { onSchedule } from 'firebase-functions/scheduler';
import * as logger from 'firebase-functions/logger';
import { defineBoolean, defineSecret, defineString } from 'firebase-functions/params';
import { liveRates } from './rates';
import { processCredit, type CreditDeps } from './credit';
import { RpcChainReader } from './solana_chain';
import { Web3SolanaPayer } from './solana';
import { processP2pAction, processWithdrawal, reconcileAll, type Deps } from './withdraw';
import { issueNonce, walletLink, walletSignIn, type WalletAuthDeps } from './wallet_auth';
import { uploadImage, type FetchLike } from './image_upload';

initializeApp();

// Non-secret config: functions/.env.<projectId>. dev = devnet, uat = testnet, prod = mainnet-beta.
// Do not commit an RPC URL that carries an API key.
const SOLANA_RPC_URL = defineString('SOLANA_RPC_URL', { default: 'https://api.devnet.solana.com' });
const SOLANA_USDT_MINT = defineString('SOLANA_USDT_MINT', { default: 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB' });
/** Treasury PUBLIC key (never the secret). Empty = read system_config/treasury. */
const SOLANA_TREASURY_PUBLIC_KEY = defineString('SOLANA_TREASURY_PUBLIC_KEY', { default: '' });
// App Check is enforced unless explicitly turned off in functions/.env.<projectId>.
const ENFORCE_APP_CHECK = defineBoolean('ENFORCE_APP_CHECK', { default: true });

/**
 * Treasury key: Secret Manager ONLY. Never in the repo, the client builds, or CI.
 *   firebase functions:secrets:set SOLANA_TREASURY_SECRET_KEY --project <project>
 * Accepts the 64-byte secret key as base58 or as a JSON byte array.
 */
const TREASURY_SECRET = defineSecret('SOLANA_TREASURY_SECRET_KEY');

/** Test hooks: only honoured inside the local Functions emulator, never in a deployed function. */
const isEmulator = () => process.env.FUNCTIONS_EMULATOR === 'true';
const useCreditMocks = () => isEmulator() && process.env.CREDIT_MOCK_SOLANA === '1';
const useWithdrawMocks = () => isEmulator() && process.env.WITHDRAW_MOCK_SOLANA === '1';

function creditDeps(): CreditDeps {
  const mocks = useCreditMocks()
    ? (require('./testing/credit_emulator_mocks') as typeof import('./testing/credit_emulator_mocks'))
    : null;
  return {
    db: getFirestore(),
    chain: mocks ? mocks.mockChain : new RpcChainReader(SOLANA_RPC_URL.value()),
    rates: mocks ? mocks.mockRates : liveRates,
    now: () => Date.now(),
    treasuryPublicKey: mocks ? mocks.MOCK_TREASURY : SOLANA_TREASURY_PUBLIC_KEY.value(),
    usdtMint: SOLANA_USDT_MINT.value(),
  };
}

function withdrawDeps(): Deps {
  const mocks = useWithdrawMocks()
    ? (require('./testing/emulator_mocks') as typeof import('./testing/emulator_mocks'))
    : null;
  return {
    db: getFirestore(),
    rates: mocks ? mocks.mockRates : liveRates,
    payer: () =>
      mocks
        ? mocks.mockPayer
        : new Web3SolanaPayer({
          rpcUrl: SOLANA_RPC_URL.value(),
          secretKey: TREASURY_SECRET.value(),
          usdtMint: SOLANA_USDT_MINT.value(),
        }),
    now: () => Date.now(),
  };
}

/**
 * Credits an on-chain payment (SOL/USDT deposit, SOL subscription) exactly once per signature.
 * Client sends { signature, kind, plan? }; amount, payer, destination and PHP value come from
 * the finalized transaction and server-side rates.
 */
export const creditOnchainPayment = onCall(
  { enforceAppCheck: ENFORCE_APP_CHECK, timeoutSeconds: 60, maxInstances: 10, memory: '256MiB' },
  async (req) => {
    try {
      return await processCredit(creditDeps(), req.auth ? { uid: req.auth.uid } : undefined, req.data);
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error('creditOnchainPayment failed', {
        detail: (e instanceof Error ? e.message : String(e)).replace(/https?:\/\/\S+/gi, '[url]').slice(0, 300),
      });
      throw new HttpsError('internal', 'The payment could not be processed.');
    }
  },
);

/**
 * Single entry point for withdrawals ('solana' = on-chain payout, 'p2p' = GCash/Maya manual review).
 * Client sends only idempotencyKey, method, amount, coin | p2p{...}. Fee, net, rate, crypto amount,
 * destination wallet and balance are all computed/read server-side.
 */
export const requestWithdrawal = onCall(
  { secrets: [TREASURY_SECRET], enforceAppCheck: ENFORCE_APP_CHECK, timeoutSeconds: 120, maxInstances: 10, memory: '256MiB' },
  async (req) => {
    try {
      return await processWithdrawal(withdrawDeps(), req.auth ? { uid: req.auth.uid, token: req.auth.token } : undefined, req.data);
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      // Detail stays in Cloud Logging (URLs stripped: RPC urls may carry keys); the caller gets a generic error.
      logger.error('requestWithdrawal failed', { detail: (e instanceof Error ? e.message : String(e)).replace(/https?:\/\/\S+/gi, '[url]').slice(0, 300) });
      throw new HttpsError('internal', 'Withdrawal could not be processed.');
    }
  },
);

/**
 * Owner actions on a P2P cashout: { withdrawalId, action: 'cancel' | 'confirm', reason? }.
 * Cancel refunds the held balance in one status-guarded transaction (never twice); confirm records receipt.
 * Not gated by the withdrawal kill switch. The owner can no longer write these docs from the client.
 */
export const updateP2pWithdrawal = onCall(
  { enforceAppCheck: ENFORCE_APP_CHECK, timeoutSeconds: 60, maxInstances: 10, memory: '256MiB' },
  async (req) => {
    try {
      return await processP2pAction(withdrawDeps(), req.auth ? { uid: req.auth.uid, token: req.auth.token } : undefined, req.data);
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error('updateP2pWithdrawal failed', { detail: (e instanceof Error ? e.message : String(e)).replace(/https?:\/\/\S+/gi, '[url]').slice(0, 300) });
      throw new HttpsError('internal', 'The request could not be processed.');
    }
  },
);

/** Settles in-flight transfers from on-chain truth (confirmed -> sent; failed/expired -> refund once). */
export const reconcileWithdrawals = onSchedule(
  { schedule: 'every 5 minutes', timeoutSeconds: 300, maxInstances: 1, secrets: [TREASURY_SECRET] },
  async () => {
    const res = await reconcileAll(withdrawDeps());
    logger.info('reconcileWithdrawals', res);
  },
);

// ── Sign-In With Solana (see wallet_auth.ts) ────────────────────────────────────────────────────
/** Hostnames a wallet challenge may be issued for. Set per project in functions/.env.<projectId>. */
const WALLET_AUTH_DOMAINS = defineString('WALLET_AUTH_DOMAINS', { default: 'tranyx.app,dev.tranyx.app,uat.tranyx.app,localhost' });

function walletDeps(): WalletAuthDeps {
  const auth = getAuth();
  return {
    db: getFirestore(),
    auth: { createCustomToken: (uid) => auth.createCustomToken(uid), getUser: (uid) => auth.getUser(uid) },
    now: () => Date.now(),
    allowedDomains: WALLET_AUTH_DOMAINS.value().split(',').map((d) => d.trim()).filter(Boolean),
  };
}

function guard<T>(name: string, run: () => Promise<T>): Promise<T> {
  return run().catch((e) => {
    if (e instanceof HttpsError) throw e;
    logger.error(`${name} failed`, { detail: (e instanceof Error ? e.message : String(e)).replace(/https?:\/\/\S+/gi, '[url]').slice(0, 300) });
    throw new HttpsError('internal', 'The wallet request could not be processed.');
  });
}

const walletOpts = { enforceAppCheck: ENFORCE_APP_CHECK, timeoutSeconds: 30, maxInstances: 10, memory: '256MiB' as const };

/** Issues a one-time challenge message for a wallet to sign. No sign-in needed (purpose 'signin' or 'link'). */
export const walletAuthNonce = onCall(walletOpts, (req) =>
  guard('walletAuthNonce', () => issueNonce(walletDeps(), req.data, req.rawRequest?.headers?.origin)));

/** Verifies the signed challenge. Existing verified wallet -> Firebase custom token; unknown wallet -> sign-up ticket. */
export const walletAuthSignIn = onCall(walletOpts, (req) =>
  guard('walletAuthSignIn', () => walletSignIn(walletDeps(), req.data)));

/** Links a proven wallet (sign-up ticket or fresh signature) to the signed-in caller. */
export const walletAuthLink = onCall(walletOpts, (req) =>
  guard('walletAuthLink', () => walletLink(walletDeps(), req.auth?.uid, req.data)));

// ── Image upload proxy (see image_upload.ts) ────────────────────────────────────────────────────
/** Secret Manager: `firebase functions:secrets:set IMGBB_API_KEY` per project. Not committed, never logged. */
const IMGBB_API_KEY = defineSecret('IMGBB_API_KEY');

/** Signed-in users upload a base64 image; the function posts it to imgbb server-side and returns { url }. */
export const uploadImageProxy = onCall(
  { enforceAppCheck: ENFORCE_APP_CHECK, secrets: [IMGBB_API_KEY], timeoutSeconds: 40, maxInstances: 10, memory: '512MiB' },
  async (req) => {
    try {
      return await uploadImage(
        { db: getFirestore(), fetchFn: fetch as unknown as FetchLike, apiKey: IMGBB_API_KEY.value(), now: () => Date.now() },
        req.auth?.uid,
        req.data,
      );
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error('uploadImageProxy failed', { detail: (e instanceof Error ? e.message : String(e)).replace(/https?:\/\/\S+/gi, '[url]').slice(0, 200) });
      throw new HttpsError('internal', 'The image could not be uploaded.');
    }
  },
);
