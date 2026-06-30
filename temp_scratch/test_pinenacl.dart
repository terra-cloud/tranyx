import 'dart:convert';
import 'dart:typed_data';
import 'package:pinenacl/ed25519.dart';
import 'package:pinenacl/digests.dart'; // sha256 or similar might be here
import 'package:bs58/bs58.dart';

void main() {
  print("PineNaCl loaded successfully!");
  
  // Let's print the public classes of pinenacl/ed25519
  // to find if there is a curve check or public key validation.
  final key = VerifyKey(base58.decode("H4r14zR2N9t3G5c1Fv8P8NJdTREpY1vzqKqZKvdpH4r1"));
  print("VerifyKey: ${key.runtimeType}");
  
  try {
    // If it's on the curve, VerifyKey creation should succeed. 
    // What if it is not on the curve? Does VerifyKey constructor throw an error, 
    // or is there another way to check? Let's check if VerifyKey validates the point.
    // Let's create an invalid point and see if it throws.
    final invalidBytes = Uint8List(32);
    invalidBytes[0] = 12; // Some random bytes
    final invalidKey = VerifyKey(invalidBytes);
    print("Invalid key created successfully (did not throw): ${invalidKey.runtimeType}");
  } catch (e) {
    print("Thrown error on invalid key: $e");
  }
}
