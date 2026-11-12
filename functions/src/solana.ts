import {
  Connection,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
} from '@solana/web3.js';
import {
  TOKEN_PROGRAM_ID,
  createAssociatedTokenAccountIdempotentInstruction,
  createTransferInstruction,
  getAssociatedTokenAddressSync,
} from '@solana/spl-token';
import bs58 from 'bs58';

export type Coin = 'SOL' | 'USDT';

export interface TransferRequest {
  coin: Coin;
  recipient: string;
  /** SOL: lamports. USDT: 6-decimal micro units. */
  baseUnits: bigint;
}

/** A fully built and signed transfer. Persist `signature` + `lastValidBlockHeight` BEFORE broadcasting. */
export interface PreparedTransfer {
  signature: string;
  rawBase64: string;
  lastValidBlockHeight: number;
}

export type SignatureOutcome =
  | { state: 'confirmed' }
  | { state: 'failed'; error: string } // landed on-chain with an error: funds did not move
  | { state: 'expired' } // never landed and the blockhash can no longer land: funds did not move
  | { state: 'waiting' }; // not found yet, still within validity window (or status unknown)

/**
 * Blocks past lastValidBlockHeight that the FINALIZED height must exceed before 'not found' counts as
 * "can no longer land" (KAN-146 K4). Absorbs RPC lag / skew between nodes and forks.
 */
export const EXPIRY_MARGIN_BLOCKS = 150;

export interface SolanaPayer {
  prepare(t: TransferRequest): Promise<PreparedTransfer>;
  /** Send and wait for confirmation. Throws on ANY failure or timeout (the outcome may still be unknown). */
  broadcast(p: PreparedTransfer): Promise<void>;
  /**
   * Ground truth for a previously prepared transfer. 'expired' is only a CANDIDATE: the reconciler
   * must see it on two separate passes before it refunds (a lagging node can report a landed
   * transfer as not found).
   */
  outcome(p: { signature: string; lastValidBlockHeight: number }): Promise<SignatureOutcome>;
}

export function parseSecretKey(secret: string): Uint8Array {
  const s = secret.trim();
  const bytes = Uint8Array.from(s.startsWith('[') ? (JSON.parse(s) as number[]) : bs58.decode(s));
  if (bytes.length !== 64) throw new Error('treasury secret must be a 64-byte secret key');
  return bytes;
}

export class Web3SolanaPayer implements SolanaPayer {
  private readonly connection: Connection;
  private readonly keypair: Keypair;
  private readonly usdtMint: PublicKey;
  private readonly expiryMargin: number;

  constructor(opts: { rpcUrl: string; secretKey: string; usdtMint: string; expiryMarginBlocks?: number }) {
    this.expiryMargin = opts.expiryMarginBlocks ?? EXPIRY_MARGIN_BLOCKS;
    this.connection = new Connection(opts.rpcUrl, 'confirmed');
    this.keypair = Keypair.fromSecretKey(parseSecretKey(opts.secretKey));
    this.usdtMint = new PublicKey(opts.usdtMint);
  }

  async prepare(t: TransferRequest): Promise<PreparedTransfer> {
    const to = new PublicKey(t.recipient);
    const from = this.keypair.publicKey;
    const tx = new Transaction();
    if (t.coin === 'SOL') {
      tx.add(SystemProgram.transfer({ fromPubkey: from, toPubkey: to, lamports: t.baseUnits }));
    } else {
      const fromAta = getAssociatedTokenAddressSync(this.usdtMint, from, true);
      const toAta = getAssociatedTokenAddressSync(this.usdtMint, to, true);
      tx.add(createAssociatedTokenAccountIdempotentInstruction(from, toAta, to, this.usdtMint));
      tx.add(createTransferInstruction(fromAta, toAta, from, t.baseUnits, [], TOKEN_PROGRAM_ID));
    }
    const { blockhash, lastValidBlockHeight } = await this.connection.getLatestBlockhash('confirmed');
    tx.recentBlockhash = blockhash;
    tx.feePayer = from;
    tx.sign(this.keypair);
    const sig = tx.signature;
    if (!sig) throw new Error('signing failed');
    return {
      signature: bs58.encode(sig),
      rawBase64: tx.serialize().toString('base64'),
      lastValidBlockHeight,
    };
  }

  async broadcast(p: PreparedTransfer): Promise<void> {
    const raw = Buffer.from(p.rawBase64, 'base64');
    const sig = await this.connection.sendRawTransaction(raw, { maxRetries: 3 });
    const bh = Transaction.from(raw).recentBlockhash!;
    const res = await this.connection.confirmTransaction(
      { signature: sig, blockhash: bh, lastValidBlockHeight: p.lastValidBlockHeight },
      'confirmed',
    );
    if (res.value.err) throw new Error(`transaction failed on-chain: ${JSON.stringify(res.value.err)}`);
  }

  async outcome(p: { signature: string; lastValidBlockHeight: number }): Promise<SignatureOutcome> {
    const { value } = await this.connection.getSignatureStatuses([p.signature], {
      searchTransactionHistory: true,
    });
    const st = value[0];
    if (st) {
      const settled = st.confirmationStatus === 'confirmed' || st.confirmationStatus === 'finalized';
      // An error at 'processed' level may still be dropped by a fork: wait for confirmed+.
      if (st.err) return settled ? { state: 'failed', error: JSON.stringify(st.err) } : { state: 'waiting' };
      return settled ? { state: 'confirmed' } : { state: 'waiting' };
    }
    // Not found. Compare the FINALIZED height (never ahead of the cluster) with a safety margin.
    const finalizedHeight = await this.connection.getBlockHeight('finalized');
    return finalizedHeight > p.lastValidBlockHeight + this.expiryMargin ? { state: 'expired' } : { state: 'waiting' };
  }
}
