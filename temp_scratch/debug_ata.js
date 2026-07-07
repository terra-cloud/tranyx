const { PublicKey } = require('@solana/web3.js');
const crypto = require('crypto');

const TOKEN_PROGRAM_ID = new PublicKey("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
const ASSOCIATED_TOKEN_PROGRAM_ID = new PublicKey("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJe1bS");

const sender = new PublicKey("H4r14zR2N9t3G5c1Fv8P8NJdTREpY1vzqKqZKvdpH4r1");
const mint = new PublicKey("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB");

// Let's print the seeds and programId bytes
console.log('Sender bytes:', Array.from(sender.toBuffer()));
console.log('Token program bytes:', Array.from(TOKEN_PROGRAM_ID.toBuffer()));
console.log('Mint bytes:', Array.from(mint.toBuffer()));
console.log('Assoc token program bytes:', Array.from(ASSOCIATED_TOKEN_PROGRAM_ID.toBuffer()));

// Find ATA and show the chosen bump
const [ata, bump] = PublicKey.findProgramAddressSync(
  [sender.toBuffer(), TOKEN_PROGRAM_ID.toBuffer(), mint.toBuffer()],
  ASSOCIATED_TOKEN_PROGRAM_ID
);

console.log('Chosen bump:', bump);
console.log('Derived ATA:', ata.toBase58());

// Let's manually reconstruct the bytes hashed for the chosen bump
const seeds = [sender.toBuffer(), TOKEN_PROGRAM_ID.toBuffer(), mint.toBuffer()];
const stringBytes = Buffer.from("ProgramDerivedAddress");

const parts = [];
for (const seed of seeds) parts.push(seed);
parts.push(Buffer.from([bump]));
parts.push(stringBytes);
parts.push(ASSOCIATED_TOKEN_PROGRAM_ID.toBuffer());

const total = Buffer.concat(parts);
console.log('Concatenated bytes length:', total.length);
console.log('Concatenated bytes first 20:', Array.from(total.slice(0, 20)));
console.log('Concatenated bytes last 20:', Array.from(total.slice(-20)));

const hash = crypto.createHash('sha256').update(total).digest();
console.log('SHA256 hash:', Array.from(hash));
const derivedKey = new PublicKey(hash);
console.log('Derived Key from Hash:', derivedKey.toBase58());
