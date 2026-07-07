import 'dart:typed_data';
import 'package:pinenacl/ed25519.dart';
import 'package:bs58/bs58.dart';

final _tokenProgramId = base58.decode('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA');
final _ataProgramId = base58.decode('ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJe1bS');

bool isOnCurve(List<int> bytes) {
  final p = (BigInt.one << 255) - BigInt.from(19);
  final d = BigInt.parse('37095705934669439343138083508754565189542113879843219016388785533085940283555');

  if (bytes.length != 32) return false;

  final s = Uint8List.fromList(bytes);
  final sign = (s[31] & 0x80) >> 7;
  s[31] &= 0x7F;

  BigInt y = BigInt.zero;
  for (int i = 0; i < 32; i++) {
    y += BigInt.from(s[i]) << (i * 8);
  }

  if (y >= p) return false;

  // u = y^2 - 1
  final u = (y * y - BigInt.one) % p;
  // v = d * y^2 + 1
  final v = (d * y * y + BigInt.one) % p;

  if (v == BigInt.zero) return false;

  // vInv = v^(p-2) % p
  final vInv = v.modPow(p - BigInt.two, p);
  // x2 = u * vInv % p
  final x2 = (u * vInv) % p;

  if (x2 == BigInt.zero) {
    return sign == 0;
  }

  // Check if x2 is quadratic residue: check = x2^((p-1)/2) % p
  final exp = (p - BigInt.one) >> 1;
  final check = x2.modPow(exp, p);

  return check == BigInt.one;
}

Uint8List _sha256ProgramAddress(Uint8List seeds, Uint8List programId) {
  final builder = BytesBuilder();
  builder.add(seeds);
  builder.add(programId);
  builder.add(Uint8List.fromList([
    80, 114, 111, 103, 114, 97, 109, 68, 101, 114, 105, 118, 101, 100, 65, 100, 100, 114, 101, 115, 115
  ])); // 'ProgramDerivedAddress'
  
  // Pure Dart SHA256 block processing
  return Uint8List.fromList(_sha256Impl(builder.toBytes()));
}

List<int> _sha256Impl(List<int> data) {
  const k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  int h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
  int h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

  final msgLen = data.length;
  final bitLen = msgLen * 8;
  final padded = <int>[...data, 0x80];
  while (padded.length % 64 != 56) {
    padded.add(0);
  }
  for (int i = 7; i >= 0; i--) {
    padded.add((bitLen >> (i * 8)) & 0xFF);
  }

  for (int chunkStart = 0; chunkStart < padded.length; chunkStart += 64) {
    final w = List<int>.filled(64, 0);
    for (int i = 0; i < 16; i++) {
      w[i] = (padded[chunkStart + i * 4] << 24) |
          (padded[chunkStart + i * 4 + 1] << 16) |
          (padded[chunkStart + i * 4 + 2] << 8) |
          (padded[chunkStart + i * 4 + 3]);
      w[i] = w[i].toSigned(32).toUnsigned(32);
    }
    for (int i = 16; i < 64; i++) {
      final s0 = (_rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)).toUnsigned(32);
      final s1 = (_rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)).toUnsigned(32);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1).toUnsigned(32);
    }

    int a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;

    for (int i = 0; i < 64; i++) {
      final s1 = (_rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25)).toUnsigned(32);
      final ch = ((e & f) ^ (~e & g)).toUnsigned(32);
      final temp1 = (h + s1 + ch + k[i] + w[i]).toUnsigned(32);
      final s0 = (_rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22)).toUnsigned(32);
      final maj = ((a & b) ^ (a & c) ^ (b & c)).toUnsigned(32);
      final temp2 = (s0 + maj).toUnsigned(32);

      h = g; g = f; f = e;
      e = (d + temp1).toUnsigned(32);
      d = c; c = b; b = a;
      a = (temp1 + temp2).toUnsigned(32);
    }

    h0 = (h0 + a).toUnsigned(32);
    h1 = (h1 + b).toUnsigned(32);
    h2 = (h2 + c).toUnsigned(32);
    h3 = (h3 + d).toUnsigned(32);
    h4 = (h4 + e).toUnsigned(32);
    h5 = (h5 + f).toUnsigned(32);
    h6 = (h6 + g).toUnsigned(32);
    h7 = (h7 + h).toUnsigned(32);
  }

  final result = <int>[];
  for (final val in [h0, h1, h2, h3, h4, h5, h6, h7]) {
    result.addAll([(val >> 24) & 0xFF, (val >> 16) & 0xFF, (val >> 8) & 0xFF, val & 0xFF]);
  }
  return result;
}

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))).toUnsigned(32);

String deriveATA({
  required String walletPubkey,
  required String mintPubkey,
}) {
  final walletBytes = Uint8List.fromList(base58.decode(walletPubkey));
  final mintBytes = Uint8List.fromList(base58.decode(mintPubkey));
  final tokenProgramBytes = Uint8List.fromList(_tokenProgramId);
  final ataProgramBytes = Uint8List.fromList(_ataProgramId);

  for (int nonce = 255; nonce >= 0; nonce--) {
    final builder = BytesBuilder();
    builder.add(walletBytes);
    builder.add(tokenProgramBytes);
    builder.add(mintBytes);
    builder.add(Uint8List.fromList([nonce]));
    final seeds = builder.toBytes();

    final hash = _sha256ProgramAddress(seeds, ataProgramBytes);
    if (!isOnCurve(hash)) {
      print('Found off-curve point at nonce: $nonce');
      return base58.encode(hash);
    }
  }
  throw Exception('deriveATA: could not find valid off-curve point');
}

void main() {
  final wallet = 'F4x29tDk7XgD6JkXFvXvXvXvXvXvXvXvXvXvXvXvXvX'; // dummy valid-looking wallet address
  // Let's generate a real valid public key
  final walletPk = base58.encode(SigningKey.generate().verifyKey.asTypedList);
  final mint = 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB';

  print('Wallet: $walletPk');
  print('Mint: $mint');
  try {
    final ata = deriveATA(walletPubkey: walletPk, mintPubkey: mint);
    print('Derived ATA: $ata');
    print('Derived ATA is on curve: ${isOnCurve(base58.decode(ata))}');
  } catch (e) {
    print('deriveATA failed: $e');
  }
}
