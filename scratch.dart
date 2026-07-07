// Run with: dart run scratch.dart
// This generates a brand-new Solana keypair you can use as your treasury wallet.
// The output gives you:
//   - Public Key  → put this in kSystemSolanaReceiverAddress in payment_pane.dart
//   - Private Key → put this ONLY in Firestore systemConfig/treasury.privateKeyBase58

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// Pure Dart Ed25519 key generation using the dart:math CSPRNG.
// We use the same pinenacl approach the app already uses.

void main() async {
  // pinenacl is a workspace dependency — run from the monorepo root.
  // Since we can't import it in a plain script, we'll use the Solana CLI approach
  // via node.js which is almost always available.
  print('Run the following Node.js snippet to generate a keypair:');
  print('');
  print(r'''
node -e "
const { Keypair } = require('@solana/web3.js');
const bs58 = require('bs58');

// Install deps first if needed:
// npm install @solana/web3.js bs58

const kp = Keypair.generate();
const privKeyBase58 = bs58.encode(kp.secretKey); // 64 bytes
const pubKey = kp.publicKey.toBase58();

console.log('=== NEW TREASURY KEYPAIR ===');
console.log('Public Key  :', pubKey);
console.log('Private Key (Base58, 64 bytes):', privKeyBase58);
console.log('');
console.log('→ Put the Public Key  in kSystemSolanaReceiverAddress in payment_pane.dart');
console.log('→ Put the Private Key ONLY in Firestore: systemConfig/treasury.privateKeyBase58');
"
''');
}
