import type { ChainReader } from './credit';

type Fetch = typeof fetch;

/**
 * Reads transactions over JSON-RPC from the project's own cluster (`SOLANA_RPC_URL`:
 * dev = devnet, uat = testnet, prod = mainnet-beta). Always `finalized` commitment: a payment that
 * could still be rolled back is never credited. `null` = not found at finalized yet.
 */
export class RpcChainReader implements ChainReader {
  constructor(
    private readonly rpcUrl: string,
    private readonly doFetch: Fetch = fetch,
    private readonly timeoutMs = 10_000,
  ) {}

  async getFinalizedTransaction(signature: string): Promise<Record<string, any> | null> {
    const res = await this.doFetch(this.rpcUrl, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'getTransaction',
        params: [signature, { encoding: 'jsonParsed', commitment: 'finalized', maxSupportedTransactionVersion: 0 }],
      }),
      signal: AbortSignal.timeout(this.timeoutMs),
    });
    if (!res.ok) throw new Error(`rpc http ${res.status}`);
    const body = (await res.json()) as { result?: unknown; error?: { code?: number; message?: string } };
    if (body.error) throw new Error(`rpc error ${body.error.code ?? ''}`);
    return body.result && typeof body.result === 'object' ? (body.result as Record<string, any>) : null;
  }
}
