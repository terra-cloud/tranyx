/** Live PHP rates, fetched server-side so the client can never choose its own rate. */
export interface Rates {
  solPhp: number;
  usdtPhp: number;
}
export type RateProvider = () => Promise<Rates>;

async function getJson(url: string, timeoutMs: number): Promise<any> {
  const res = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
  if (!res.ok) throw new Error(`rate source ${res.status}`);
  return res.json();
}

/** CoinGecko first, then Binance SOLUSDT x open.er-api USD/PHP (same sources the apps used). */
export const liveRates: RateProvider = async () => {
  try {
    const d = await getJson(
      'https://api.coingecko.com/api/v3/simple/price?ids=solana,tether&vs_currencies=php',
      5000,
    );
    const solPhp = Number(d?.solana?.php);
    const usdtPhp = Number(d?.tether?.php);
    if (solPhp > 0 && usdtPhp > 0) return { solPhp, usdtPhp };
  } catch {
    /* fall through */
  }
  const [b, fx] = await Promise.all([
    getJson('https://api.binance.com/api/v3/ticker/price?symbol=SOLUSDT', 4000),
    getJson('https://open.er-api.com/v6/latest/USD', 4000),
  ]);
  const solUsd = Number(b?.price);
  const usdPhp = Number(fx?.rates?.PHP);
  if (!(solUsd > 0) || !(usdPhp > 0)) throw new Error('rates unavailable');
  return { solPhp: solUsd * usdPhp, usdtPhp: usdPhp };
};
