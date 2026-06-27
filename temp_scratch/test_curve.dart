import 'dart:typed_data';
import 'package:bs58/bs58.dart';

bool isOnCurve(Uint8List bytes) {
  if (bytes.length != 32) return false;
  
  final p = (BigInt.one << 255) - BigInt.from(19);
  
  var y = BigInt.zero;
  for (var i = 0; i < 32; i++) {
    y += BigInt.from(bytes[i]) << (8 * i);
  }
  
  // Clear the sign bit (MSB of the 31st byte)
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

void main() {
  final validAddress = "EYC8SkTpSMeeu9Lf9Xm6KNwH2WE1PTMJhZKT81DF9MoD";
  final validBytes = base58.decode(validAddress);
  print("$validAddress is on curve: ${isOnCurve(validBytes)} (Expected: true)");
}
