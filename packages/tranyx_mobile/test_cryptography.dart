import 'package:cryptography/cryptography.dart';

void main() async {
  final ed25519 = Ed25519();
  print(ed25519.runtimeType);
  // Let's see what methods are available on Ed25519 or keyPair
  // We can try to use reflect or print members via code
  print('Methods on Ed25519:');
  // ed25519 has newKeyPair, newKeyPairFromSeed, verify, etc.
}
