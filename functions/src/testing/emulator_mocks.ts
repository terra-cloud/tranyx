import type { SolanaPayer } from '../solana';

/** Used only when FUNCTIONS_EMULATOR=true and WITHDRAW_MOCK_SOLANA=1 (local emulator smoke test). */
export const mockRates = async () => ({ solPhp: 8000, usdtPhp: 57 });
export const mockPayer: SolanaPayer = {
  async prepare() {
    return { signature: 'MOCKSIG' + Date.now(), rawBase64: '', lastValidBlockHeight: 1_000_000 };
  },
  async broadcast() {},
  async outcome() {
    return { state: 'confirmed' };
  },
};
