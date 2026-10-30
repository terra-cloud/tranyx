import type { Firestore } from 'firebase-admin/firestore';

/**
 * Withdrawal limits and fees. Defaults are used when `config/withdrawals` does not exist.
 * `config/withdrawals` is admin-only in firestore.rules (config/* other than app_config), and this
 * function reads it with the Admin SDK. Every field is optional and validated; bad values fall back.
 *
 *   enabled          boolean  kill switch. DEFAULT FALSE (KAN-146 K1): withdrawals stay off until staff
 *                             explicitly set `enabled: true` (only the boolean true counts)
 *   requireIdVerified boolean require users/{uid}.idVerified === true to withdraw   default false
 *   minPhp           number   minimum amount per request (PHP)             default 100
 *   maxPhp           number   maximum amount per request (PHP)             default 50,000
 *   dailyMaxCount    number   max non-failed requests per Manila day       default 3
 *   dailyMaxPhp      number   max total PHP per Manila day                 default 100,000
 *   solanaFeeRate    number   Solana fee rate, 0..0.2                      default 0.02 (2%)
 *   p2pFeeRate       number   P2P fee rate, 0..0.2                         default 0 (0%)
 *   walletCooldownHours number hours a payout wallet must be unchanged before a Solana withdrawal to it,
 *                             0..720, 0 disables                         default 24
 *   usdtPhpMin/Max   number   sanity band for the fetched USDT/PHP rate   default 40 / 80
 *   solPhpMin/Max    number   sanity band for the fetched SOL/PHP rate    default 100 / 1,000,000
 */
export interface WithdrawConfig {
  enabled: boolean;
  requireIdVerified: boolean;
  minPhp: number;
  maxPhp: number;
  dailyMaxCount: number;
  dailyMaxPhp: number;
  solanaFeeRate: number;
  p2pFeeRate: number;
  walletCooldownHours: number;
  usdtPhpMin: number;
  usdtPhpMax: number;
  solPhpMin: number;
  solPhpMax: number;
}

export const DEFAULT_CONFIG: WithdrawConfig = {
  enabled: false,
  requireIdVerified: false,
  minPhp: 100,
  maxPhp: 50_000,
  dailyMaxCount: 3,
  dailyMaxPhp: 100_000,
  solanaFeeRate: 0.02,
  p2pFeeRate: 0,
  walletCooldownHours: 24,
  usdtPhpMin: 40,
  usdtPhpMax: 80,
  solPhpMin: 100,
  solPhpMax: 1_000_000,
};

function num(v: unknown, fallback: number, min: number, max: number): number {
  return typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max ? v : fallback;
}

export async function loadConfig(db: Firestore): Promise<WithdrawConfig> {
  const snap = await db.doc('config/withdrawals').get();
  const d = (snap.exists ? snap.data() : {}) ?? {};
  const c = DEFAULT_CONFIG;
  return {
    enabled: d.enabled === true,
    requireIdVerified: d.requireIdVerified === true,
    minPhp: num(d.minPhp, c.minPhp, 1, 1e9),
    maxPhp: num(d.maxPhp, c.maxPhp, 1, 1e9),
    dailyMaxCount: num(d.dailyMaxCount, c.dailyMaxCount, 1, 1000),
    dailyMaxPhp: num(d.dailyMaxPhp, c.dailyMaxPhp, 1, 1e10),
    solanaFeeRate: num(d.solanaFeeRate, c.solanaFeeRate, 0, 0.2),
    p2pFeeRate: num(d.p2pFeeRate, c.p2pFeeRate, 0, 0.2),
    walletCooldownHours: num(d.walletCooldownHours, c.walletCooldownHours, 0, 720),
    usdtPhpMin: num(d.usdtPhpMin, c.usdtPhpMin, 0.0001, 1e9),
    usdtPhpMax: num(d.usdtPhpMax, c.usdtPhpMax, 0.0001, 1e9),
    solPhpMin: num(d.solPhpMin, c.solPhpMin, 0.0001, 1e12),
    solPhpMax: num(d.solPhpMax, c.solPhpMax, 0.0001, 1e12),
  };
}
