import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/https';
import * as logger from 'firebase-functions/logger';
import { defineBoolean, defineString } from 'firebase-functions/params';
import { liveRates } from './rates';
import { processCredit, type CreditDeps } from './credit';
import { RpcChainReader } from './solana_chain';

initializeApp();

// Non-secret config: functions/.env.<projectId>. dev = devnet, uat = testnet, prod = mainnet-beta.
// Do not commit an RPC URL that carries an API key (use `firebase functions:config`/params for that).
const SOLANA_RPC_URL = defineString('SOLANA_RPC_URL', { default: 'https://api.devnet.solana.com' });
const SOLANA_USDT_MINT = defineString('SOLANA_USDT_MINT', { default: 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB' });
/** Treasury PUBLIC key (never the secret). Empty = read system_config/treasury. */
const SOLANA_TREASURY_PUBLIC_KEY = defineString('SOLANA_TREASURY_PUBLIC_KEY', { default: '' });
const ENFORCE_APP_CHECK = defineBoolean('ENFORCE_APP_CHECK', { default: true });

/** Test hook: only honoured inside the local Functions emulator, never in a deployed function. */
const useEmulatorMocks = () => process.env.FUNCTIONS_EMULATOR === 'true' && process.env.CREDIT_MOCK_SOLANA === '1';

function deps(): CreditDeps {
  const mocks = useEmulatorMocks() ? (require('./testing/credit_emulator_mocks') as typeof import('./testing/credit_emulator_mocks')) : null;
  return {
    db: getFirestore(),
    chain: mocks ? mocks.mockChain : new RpcChainReader(SOLANA_RPC_URL.value()),
    rates: mocks ? mocks.mockRates : liveRates,
    now: () => Date.now(),
    treasuryPublicKey: mocks ? mocks.MOCK_TREASURY : SOLANA_TREASURY_PUBLIC_KEY.value(),
    usdtMint: SOLANA_USDT_MINT.value(),
  };
}

/**
 * Credits an on-chain payment (SOL/USDT deposit, SOL subscription) exactly once per signature.
 * Client sends { signature, kind: 'deposit_sol'|'deposit_usdt'|'subscription_sol', plan? }; the amount,
 * payer, destination and PHP value all come from the finalized transaction and server-side rates.
 */
export const creditOnchainPayment = onCall(
  { enforceAppCheck: ENFORCE_APP_CHECK, timeoutSeconds: 60, maxInstances: 10, memory: '256MiB' },
  async (req) => {
    try {
      return await processCredit(deps(), req.auth ? { uid: req.auth.uid } : undefined, req.data);
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      // Detail stays in Cloud Logging (URLs stripped: RPC urls may carry keys); the caller gets a generic error.
      logger.error('creditOnchainPayment failed', { detail: (e instanceof Error ? e.message : String(e)).replace(/https?:\/\/\S+/gi, '[url]').slice(0, 300) });
      throw new HttpsError('internal', 'The payment could not be processed.');
    }
  },
);
