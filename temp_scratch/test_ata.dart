import 'dart:convert';
import 'dart:typed_data';
import 'package:bs58/bs58.dart';
import 'package:crypto/crypto.dart';

bool isOnCurve(Uint8List bytes) {
  if (bytes.length != 32) return false;
  final p = (BigInt.one << 255) - BigInt.from(19);
  
  var y = BigInt.zero;
  for (var i = 0; i < 32; i++) {
    y += BigInt.from(bytes[i]) << (8 * i);
  }
  
  y = y & ((BigInt.one << 255) - BigInt.one);
  if (y >= p) return false;
  
  final d = BigInt.parse("37095705934669439343138083508754565189542113879843219016388785533085940283555");
  
  final y2 = (y * y) % p;
  final u = (y2 - BigInt.one) % p;
  final v = (d * y2 + BigInt.one) % p;
  
  final vInv = v.modPow(p - BigInt.two, p);
  final x2 = (u * vInv) % p;
  
  if (x2 == BigInt.zero) {
    return u == BigInt.zero;
  }
  
  final eulerLimit = (p - BigInt.one) >> 1;
  final val = x2.modPow(eulerLimit, p);
  return val == BigInt.one;
}

Uint8List findProgramAddress(List<Uint8List> seeds, Uint8List programId) {
  final stringBytes = utf8.encode("ProgramDerivedAddress");
  
  for (var bump = 255; bump >= 0; bump--) {
    final builder = BytesBuilder();
    for (final seed in seeds) {
      builder.add(seed);
    }
    builder.addByte(bump);
    builder.add(programId);
    builder.add(stringBytes);
    
    final hash = sha256.convert(builder.toBytes()).bytes;
    if (!isOnCurve(Uint8List.fromList(hash))) {
      return Uint8List.fromList(hash);
    }
  }
  throw Exception("Unable to find a viable program address");
}

void main() {
  final tokenProgramId = base58.decode("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
  final associatedTokenProgramId = base58.decode("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJe1bS");
  
  final sender = base58.decode("H4r14zR2N9t3G5c1Fv8P8NJdTREpY1vzqKqZKvdpH4r1");
  final mint = base58.decode("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB");
  
  final senderATA = findProgramAddress([
    sender,
    tokenProgramId,
    mint,
  ], associatedTokenProgramId);
  
  print("Derived Sender ATA (Dart): ${base58.encode(senderATA)}");
  print("Expected (from JS)       : GTLkDyKxuviezwJB8epmnRVQHVmzhSKn6T9tNwwVhFne");
  print("Match: ${base58.encode(senderATA) == 'GTLkDyKxuviezwJB8epmnRVQHVmzhSKn6T9tNwwVhFne'}");
}
