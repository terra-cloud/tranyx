/**
 * Server copies of the shared Dart pricing helpers (packages/shared: SmartRateEngine,
 * PropertyPricingModel, Promo.calculateDiscount). Prices are recomputed here from the listing
 * document; a client-sent total is never trusted.
 */
import { numOf, round2 } from './money';

export interface VehicleRates {
  price12h: number;
  priceDaily: number;
  priceWeekly: number;
  priceMonthly: number;
}

export function vehicleRates(l: Record<string, unknown>): VehicleRates {
  const pick = (a: unknown, b: unknown) => numOf(a ?? b);
  return {
    price12h: pick(l.price12h, l.halfDayRate),
    priceDaily: pick(l.priceDaily, l.dailyRate),
    priceWeekly: pick(l.priceWeekly, l.weeklyRate),
    priceMonthly: pick(l.priceMonthly, l.monthlyRate),
  };
}

/** SmartRateEngine.calculateOptimizedRate → totalBasePrice. */
export function optimizedBase(r: VehicleRates, totalDays: number, hours = 0): number {
  const { price12h, priceDaily, priceWeekly, priceMonthly } = r;
  if (totalDays === 0 && hours > 0) {
    const halfDays = Math.ceil(hours / 12);
    const unit = price12h > 0 ? price12h : priceDaily > 0 ? priceDaily * 0.5 : 0;
    return halfDays * unit;
  }
  const effectiveDays = totalDays <= 0 ? 1 : totalDays;
  const effWeekly = priceWeekly > 0 && (priceDaily <= 0 || priceWeekly > priceDaily) ? priceWeekly : 0;
  const effMonthly = priceMonthly > 0 && (priceDaily <= 0 || priceMonthly > priceDaily) && (effWeekly <= 0 || priceMonthly > effWeekly) ? priceMonthly : 0;
  if (effWeekly <= 0 && effMonthly <= 0) return effectiveDays * priceDaily;

  let remaining = effectiveDays;
  let months = 0;
  let weeks = 0;
  if (effMonthly > 0 && remaining >= 30) { months = Math.floor(remaining / 30); remaining %= 30; }
  if (effWeekly > 0 && remaining >= 7) { weeks = Math.floor(remaining / 7); remaining %= 7; }
  let days = remaining;
  if (effWeekly > 0 && days > 0 && days * priceDaily > effWeekly) { weeks += 1; days = 0; }
  if (effMonthly > 0) {
    const sub = weeks * effWeekly + days * priceDaily;
    if (sub > effMonthly) { months += 1; weeks = 0; days = 0; }
  }
  let best = months * effMonthly + weeks * effWeekly + days * priceDaily;
  if (effWeekly > 0 && effectiveDays < 7 && effectiveDays * priceDaily > effWeekly && effWeekly < best) best = effWeekly;
  if (effMonthly > 0 && effMonthly < best) best = effMonthly;
  return best;
}

export type PackageType = '12h' | 'daily' | 'weekly' | 'monthly';

export function parsePackage(v: unknown): PackageType | null {
  const s = typeof v === 'string' ? v.trim().toLowerCase() : '';
  return s === '12h' || s === 'daily' || s === 'weekly' || s === 'monthly' ? s : null;
}

export function totalDaysEquivalent(pkg: PackageType, qty: number): number {
  return pkg === '12h' ? 0 : pkg === 'weekly' ? qty * 7 : pkg === 'monthly' ? qty * 30 : qty;
}

/** Vehicle base price (rate tiers + optional driver). 3% platform fee is added by the caller. */
export function vehicleBasePrice(listing: Record<string, unknown>, pkg: PackageType, qty: number, withDriver: boolean): number {
  const rates = vehicleRates(listing);
  const days = totalDaysEquivalent(pkg, qty);
  const base = pkg === '12h' ? optimizedBase(rates, 0, 12 * qty) : optimizedBase(rates, days);
  let driver = 0;
  if (withDriver && listing.offersDriver === true) {
    const eff = pkg === '12h' ? 0.5 * qty : days;
    driver = numOf(listing.driverDailyPrice) * eff;
  }
  return round2(base + driver);
}

export interface PropertyFinancials {
  baseRent: number;
  securityDeposit: number;
  customerPlatformFee: number;
  hostCommission: number;
  customerFeeRate: number;
  hostCommissionRate: number;
  appliedTier: string;
  unitRate: number;
  depositType: string;
  depositValue: number;
}

export function propertyFinancials(p: Record<string, unknown>, totalDaysIn: number, custFeeRate: number, hostCommRate: number): PropertyFinancials {
  const totalDays = totalDaysIn <= 0 ? 1 : totalDaysIn;
  const dailyRate = numOf(p.priceDaily ?? p.dailyRate) || undefined;
  const weeklyRate = numOf(p.priceWeekly ?? p.weeklyRate) || undefined;
  const monthlyRate = numOf(p.priceMonthly ?? p.monthlyRate) || undefined;

  let depositType = 'none';
  let depositValue = 0;
  const policy = p.securityDepositPolicy as Record<string, unknown> | undefined;
  if (policy && typeof policy === 'object') {
    depositType = String(policy.type ?? 'none').toLowerCase();
    depositValue = numOf(policy.value);
  } else if (p.depositType != null) {
    depositType = String(p.depositType).toLowerCase();
    depositValue = numOf(p.depositValue);
  } else if (numOf(p.securityDepositAmount) > 0) {
    depositType = 'fixed';
    depositValue = numOf(p.securityDepositAmount);
  } else if (numOf(p.depositMonths) > 0 && monthlyRate && monthlyRate > 0) {
    depositType = 'fixed';
    depositValue = numOf(p.depositMonths) * monthlyRate;
  }
  if (depositType !== 'fixed' && depositType !== 'percentage') depositType = 'none';

  const safeDaily = dailyRate && dailyRate > 0 ? dailyRate : undefined;
  let safeWeekly = weeklyRate && weeklyRate > 0 ? weeklyRate : undefined;
  if (safeWeekly && safeDaily && safeWeekly < safeDaily) safeWeekly = undefined;
  let safeMonthly = monthlyRate && monthlyRate > 0 ? monthlyRate : undefined;
  if (safeMonthly && safeDaily && safeMonthly < safeDaily) safeMonthly = undefined;
  if (safeMonthly && safeWeekly && safeMonthly <= safeWeekly) safeMonthly = undefined;

  let baseRent = 0;
  let unitRate = 0;
  let tier = 'DAILY';
  if (totalDays >= 30 && safeMonthly) {
    tier = 'MONTHLY';
    unitRate = safeMonthly;
    const months = Math.floor(totalDays / 30);
    const rem = totalDays % 30;
    const fallback = safeDaily ?? (safeWeekly ? safeWeekly / 7 : safeMonthly / 30);
    baseRent = months * safeMonthly + rem * fallback;
  } else if (totalDays >= 7 && safeWeekly) {
    tier = 'WEEKLY';
    unitRate = safeWeekly;
    const weeks = Math.floor(totalDays / 7);
    const rem = totalDays % 7;
    const fallback = safeDaily ?? safeWeekly / 7;
    baseRent = weeks * safeWeekly + rem * fallback;
  } else {
    const rate = safeDaily ?? (safeWeekly ? safeWeekly / 7 : safeMonthly ? safeMonthly / 30 : 0);
    unitRate = rate;
    baseRent = rate * totalDays;
  }
  let deposit = depositType === 'fixed' ? depositValue : depositType === 'percentage' ? baseRent * (depositValue / 100) : 0;
  baseRent = round2(baseRent);
  deposit = round2(deposit);
  return {
    baseRent,
    securityDeposit: deposit,
    customerPlatformFee: round2(baseRent * custFeeRate),
    hostCommission: round2(baseRent * hostCommRate),
    customerFeeRate: custFeeRate,
    hostCommissionRate: hostCommRate,
    appliedTier: tier,
    unitRate,
    depositType,
    depositValue,
  };
}

// ── promos ─────────────────────────────────────────────────────────────────────────────────────
const toMs = (v: unknown): number | null => {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (v && typeof v === 'object' && typeof (v as { toMillis?: unknown }).toMillis === 'function') return (v as { toMillis(): number }).toMillis();
  if (typeof v === 'string') { const t = Date.parse(v); return Number.isNaN(t) ? null : t; }
  return null;
};

/**
 * Promo.calculateDiscount, plus eligibility checks. A promo may only reduce the TRANYX fee, never the
 * provider price. Returns null when the promo is not usable (caller turns that into PROMO_INVALID).
 */
export function promoDiscount(
  promo: Record<string, unknown> | undefined,
  o: { base: number; fee: number; uid: string; now: number; module: string },
): number | null {
  if (!promo || promo.isActive === false) return null;
  const start = toMs(promo.startDate);
  const end = toMs(promo.endDate) ?? toMs(promo.expirationDate);
  if (start != null && o.now < start) return null;
  if (end != null && o.now > end) return null;
  const modules = Array.isArray(promo.eligibleModules) ? (promo.eligibleModules as unknown[]).map(String) : [];
  if (modules.length && !modules.includes('all') && !modules.includes(o.module) && !modules.includes('rentals')) return null;
  const usedBy = Array.isArray(promo.usedBy) ? (promo.usedBy as unknown[]) : [];
  const perUser = numOf(promo.maxUsesPerUser, 1);
  if (usedBy.filter((x) => x === o.uid).length >= Math.max(1, perUser)) return null;
  const maxUsers = promo.maxUsers == null ? null : numOf(promo.maxUsers, 0);
  if (maxUsers != null && maxUsers > 0 && numOf(promo.usedCount) >= maxUsers) return null;
  const minTx = promo.minTransactionAmount == null ? null : numOf(promo.minTransactionAmount);
  if (minTx != null && o.base + o.fee < minTx) return 0;
  const value = numOf(promo.discountValue);
  let raw = promo.discountType === 'percentage' ? o.fee * (value / 100) : value;
  const cap = promo.maxDiscountAmount == null ? null : numOf(promo.maxDiscountAmount);
  if (cap != null && raw > cap) raw = cap;
  return round2(Math.min(Math.max(raw, 0), o.fee));
}
