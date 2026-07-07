const { Connection, PublicKey, SystemProgram, Transaction, TransactionInstruction } = require('@solana/web3.js');

const TOKEN_PROGRAM_ID = new PublicKey("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");

const sender = new PublicKey("H4r14zR2N9t3G5c1Fv8P8NJdTREpY1vzqKqZKvdpH4r1");
const receiverATA = new PublicKey("2auUs5GXdACdPi8urgr6GsJnTSMGV4kdD6sVSL3XRVMZ");
const senderATA = new PublicKey("GTLkDyKxuviezwJB8epmnRVQHVmzhSKn6T9tNwwVhFne");

const tx = new Transaction();
tx.recentBlockhash = "11111111111111111111111111111111"; // dummy blockhash
tx.feePayer = sender;

// SPL Token Transfer Instruction
const keys = [
  { pubkey: senderATA, isSigner: false, isWritable: true },
  { pubkey: receiverATA, isSigner: false, isWritable: true },
  { pubkey: sender, isSigner: true, isWritable: false },
];
const data = Buffer.alloc(9);
data.writeUInt8(3, 0);
const amount = 10000000;
data.writeBigUInt64LE(BigInt(amount), 1);

const transferInstruction = new TransactionInstruction({
  keys: keys,
  programId: TOKEN_PROGRAM_ID,
  data: data,
});

tx.add(transferInstruction);

// Compile transaction message
const message = tx.compileMessage();
const serializedMessage = message.serialize();

console.log('Serialized Message Hex:', serializedMessage.toString('hex'));
console.log('Account Keys:', message.accountKeys.map(k => k.toBase58()));
console.log('Header:', message.header);
console.log('Instructions:', JSON.stringify(message.instructions, null, 2));
