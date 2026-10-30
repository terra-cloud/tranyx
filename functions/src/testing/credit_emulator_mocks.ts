import type { ChainReader } from '../credit';

/** Used only when FUNCTIONS_EMULATOR=true and CREDIT_MOCK_SOLANA=1 (local emulator smoke test). */
export const MOCK_TREASURY = '11111111111111111111111111111112';
export const mockRates = async () => ({ solPhp: 8000, usdtPhp: 57 });
/** Transactions are read from the emulator's Firestore `__mock_chain/{signature}` doc (field `tx`, JSON). */
export const mockChain: ChainReader = {
  async getFinalizedTransaction(signature) {
    const { getFirestore } = require('firebase-admin/firestore') as typeof import('firebase-admin/firestore');
    const s = await getFirestore().doc(`__mock_chain/${signature}`).get();
    return s.exists ? JSON.parse(String(s.get('tx'))) : null;
  },
};
