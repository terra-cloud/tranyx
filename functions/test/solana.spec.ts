// Real Web3SolanaPayer against a stubbed RPC Connection (no network).
import { describe, expect, it, vi } from 'vitest';
import { Connection, Keypair, SystemProgram, Transaction } from '@solana/web3.js';
import { TOKEN_PROGRAM_ID, getAssociatedTokenAddressSync } from '@solana/spl-token';
import bs58 from 'bs58';
import { Web3SolanaPayer, parseSecretKey } from '../src/solana';

const treasury = Keypair.generate();
const dest = Keypair.generate().publicKey;
const MINT = 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB';
const mk = (secret: string) => new Web3SolanaPayer({ rpcUrl: 'http://127.0.0.1:1', secretKey: secret, usdtMint: MINT });
const stub = () => vi.spyOn(Connection.prototype, 'getLatestBlockhash').mockResolvedValue({
  blockhash: bs58.encode(Buffer.alloc(32, 7)), lastValidBlockHeight: 4242,
});

describe('Web3SolanaPayer (stubbed RPC)', () => {
  it('parses base58 and JSON-array secret keys; rejects bad length', () => {
    expect(parseSecretKey(bs58.encode(treasury.secretKey))).toEqual(treasury.secretKey);
    expect(parseSecretKey(JSON.stringify(Array.from(treasury.secretKey)))).toEqual(treasury.secretKey);
    expect(() => parseSecretKey(bs58.encode(Buffer.alloc(10)))).toThrow();
  });

  it('SOL: signs a System transfer of exactly the requested lamports from the treasury; signature matches', async () => {
    stub();
    const p = await mk(bs58.encode(treasury.secretKey)).prepare({ coin: 'SOL', recipient: dest.toBase58(), baseUnits: 123_456_789n });
    const tx = Transaction.from(Buffer.from(p.rawBase64, 'base64'));
    expect(tx.verifySignatures()).toBe(true);
    expect(bs58.encode(tx.signature!)).toBe(p.signature);
    expect(p.lastValidBlockHeight).toBe(4242);
    expect(tx.feePayer!.equals(treasury.publicKey)).toBe(true);
    expect(tx.instructions).toHaveLength(1);
    const ix = tx.instructions[0];
    expect(ix.programId.equals(SystemProgram.programId)).toBe(true);
    expect(ix.keys[0].pubkey.equals(treasury.publicKey)).toBe(true);
    expect(ix.keys[1].pubkey.equals(dest)).toBe(true);
    expect(ix.data.readBigUInt64LE(4)).toBe(123_456_789n);
  });

  it('USDT: idempotent ATA create + SPL transfer of exact micro units between the right ATAs', async () => {
    stub();
    const p = await mk(JSON.stringify(Array.from(treasury.secretKey))).prepare({ coin: 'USDT', recipient: dest.toBase58(), baseUnits: 8_596_491n });
    const tx = Transaction.from(Buffer.from(p.rawBase64, 'base64'));
    expect(tx.verifySignatures()).toBe(true);
    expect(tx.instructions).toHaveLength(2);
    const mint = new (await import('@solana/web3.js')).PublicKey(MINT);
    const fromAta = getAssociatedTokenAddressSync(mint, treasury.publicKey, true);
    const toAta = getAssociatedTokenAddressSync(mint, dest, true);
    const transfer = tx.instructions[1];
    expect(transfer.programId.equals(TOKEN_PROGRAM_ID)).toBe(true);
    expect(transfer.keys[0].pubkey.equals(fromAta)).toBe(true);
    expect(transfer.keys[1].pubkey.equals(toAta)).toBe(true);
    expect(transfer.keys[2].pubkey.equals(treasury.publicKey)).toBe(true);
    expect(transfer.data[0]).toBe(3);
    expect(transfer.data.readBigUInt64LE(1)).toBe(8_596_491n);
  });

  describe('outcome() (K4: finalized height + margin, history search, no refund on lag)', () => {
    const setup = () => {
      const payer = mk(bs58.encode(treasury.secretKey));
      const conn = (payer as unknown as { connection: Connection }).connection;
      const sig = vi.spyOn(conn, 'getSignatureStatuses');
      const height = vi.spyOn(conn, 'getBlockHeight');
      return { payer, sig, height };
    };
    const ctx = { slot: 1 };
    const st = (over: Record<string, unknown>) => ({ slot: 1, confirmations: 1, err: null, confirmationStatus: 'confirmed', ...over }) as any;
    const P = { signature: 's', lastValidBlockHeight: 1000 };

    it('confirmed / finalized -> confirmed; always searches transaction history', async () => {
      const { payer, sig } = setup();
      sig.mockResolvedValue({ context: ctx, value: [st({})] });
      expect(await payer.outcome(P)).toEqual({ state: 'confirmed' });
      sig.mockResolvedValue({ context: ctx, value: [st({ confirmationStatus: 'finalized' })] });
      expect(await payer.outcome(P)).toEqual({ state: 'confirmed' });
      expect(sig).toHaveBeenCalledWith(['s'], { searchTransactionHistory: true });
    });

    it('error only counts once confirmed+; an error at "processed" may be dropped by a fork -> waiting', async () => {
      const { payer, sig } = setup();
      const err = { InstructionError: [0, 'Custom'] };
      sig.mockResolvedValue({ context: ctx, value: [st({ err })] });
      expect((await payer.outcome(P)).state).toBe('failed');
      sig.mockResolvedValue({ context: ctx, value: [st({ err, confirmationStatus: 'processed' })] });
      expect(await payer.outcome(P)).toEqual({ state: 'waiting' });
      sig.mockResolvedValue({ context: ctx, value: [st({ confirmationStatus: 'processed' })] });
      expect(await payer.outcome(P)).toEqual({ state: 'waiting' });
    });

    it('not found: compares the FINALIZED height with a 150-block margin', async () => {
      const { payer, sig, height } = setup();
      sig.mockResolvedValue({ context: ctx, value: [null] });
      height.mockResolvedValue(1000 + 150);
      expect(await payer.outcome(P)).toEqual({ state: 'waiting' }); // exactly at the margin: still waiting
      height.mockResolvedValue(1000 + 151);
      expect(await payer.outcome(P)).toEqual({ state: 'expired' });
      expect(height).toHaveBeenCalledWith('finalized');
      expect(height).not.toHaveBeenCalledWith('confirmed');
    });

    it('LAGGING node: finalized height behind lastValidBlockHeight (or only just past it) never reports expired', async () => {
      const { payer, sig, height } = setup();
      sig.mockResolvedValue({ context: ctx, value: [null] });
      for (const h of [900, 999, 1000, 1001, 1050, 1149]) {
        height.mockResolvedValue(h);
        expect(await payer.outcome(P)).toEqual({ state: 'waiting' });
      }
    });

    it('RPC errors propagate (the reconciler treats them as waiting)', async () => {
      const { payer, sig } = setup();
      sig.mockRejectedValue(new Error('503'));
      await expect(payer.outcome(P)).rejects.toThrow();
    });
  });
});
