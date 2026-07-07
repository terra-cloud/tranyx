const { Connection, PublicKey, SystemProgram, Transaction, TransactionInstruction } = require('@solana/web3.js');
const bs58 = require('bs58');

const TOKEN_PROGRAM_ID = new PublicKey("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
const ASSOCIATED_TOKEN_PROGRAM_ID = new PublicKey("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJe1bS");

const sender = new PublicKey("H4r14zR2N9t3G5c1Fv8P8NJdTREpY1vzqKqZKvdpH4r1");
const receiver = new PublicKey("G6c1Fv8P8NJdTREpY1vzqKqZKvdpH4r14zR2N9t3G5c1");
const mint = new PublicKey("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB");

// Find ATA
const [senderATA] = PublicKey.findProgramAddressSync(
  [sender.toBuffer(), TOKEN_PROGRAM_ID.toBuffer(), mint.toBuffer()],
  ASSOCIATED_TOKEN_PROGRAM_ID
);
const [receiverATA] = PublicKey.findProgramAddressSync(
  [receiver.toBuffer(), TOKEN_PROGRAM_ID.toBuffer(), mint.toBuffer()],
  ASSOCIATED_TOKEN_PROGRAM_ID
);

console.log('Sender ATA:', senderATA.toBase58());
console.log('Receiver ATA:', receiverATA.toBase58());

// Construct a dummy transaction
const tx = new Transaction();
tx.recentBlockhash = "11111111111111111111111111111111"; // dummy blockhash
tx.feePayer = sender;

// Create ATA Instruction
const createATAInstruction = new TransactionInstruction({
  keys: [
    { pubkey: sender, isSigner: true, isWritable: true },
    { pubkey: receiverATA, isSigner: false, isWritable: true },
    { pubkey: receiver, isSigner: false, isWritable: false },
    { pubkey: mint, isSigner: false, isWritable: false },
    { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
  ],
  programId: ASSOCIATED_TOKEN_PROGRAM_ID,
  data: Buffer.alloc(0),
});

// SPL Token Transfer Instruction
const keys = [
  { pubkey: senderATA, isSigner: false, isWritable: true },
  { pubkey: receiverATA, isSigner: false, isWritable: true },
  { pubkey: sender, isSigner: true, isWritable: false },
];
// SPL Token transfer instruction data: [3, amount_le_uint64]
const data = Buffer.alloc(9);
data.writeUInt8(3, 0);
// Let's set amount to 10 USDT (10 * 10^6 = 10,000,000)
const amount = 10000000;
data.writeBigUInt64LE(BigInt(amount), 1);

const transferInstruction = new TransactionInstruction({
  keys: keys,
  programId: TOKEN_PROGRAM_ID,
  data: data,
});

tx.add(createATAInstruction);
tx.add(transferInstruction);

// Compile transaction message
const message = tx.compileMessage();
const serializedMessage = message.serialize();

console.log('Serialized Message Hex:', serializedMessage.toString('hex'));
console.log('Account Keys:', message.accountKeys.map(k => k.toBase58()));
console.log('Header:', message.header);
console.log('Instructions:', JSON.stringify(message.instructions, null, 2));
