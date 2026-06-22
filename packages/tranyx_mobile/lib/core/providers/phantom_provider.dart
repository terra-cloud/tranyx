import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:pinenacl/x25519.dart';
import 'package:bs58/bs58.dart';
import 'package:tranyx_mobile/flavors.dart';

// Stores the session private key generated for a connection request
final phantomSessionPrivateKeyProvider = StateProvider<Uint8List?>(
  (ref) => null,
);

// Stores the type of wallet currently being connected (e.g. phantom, solflare, backpack, trust)
final connectingWalletTypeProvider = StateProvider<String?>((ref) => null);

// Stores the pending wallet public key for new registration/linking
final pendingWalletPublicKeyProvider = StateProvider<String?>((ref) => null);

final phantomServiceProvider = Provider<PhantomService>((ref) {
  return PhantomService(ref);
});

class PhantomService {
  final Ref _ref;

  PhantomService(this._ref);

  /// Generates an ephemeral key pair for the connection session,
  /// saves the private key to the state provider, and returns the Phantom Connect URI.
  Future<Uri> generateConnectUri({required String walletType}) async {
    // Generate session key pair
    final localPrivateKey = PrivateKey.generate();
    final localPublicKey = localPrivateKey.publicKey;

    // Save private key bytes to the provider
    _ref.read(phantomSessionPrivateKeyProvider.notifier).state =
        localPrivateKey.asTypedList;
    _ref.read(connectingWalletTypeProvider.notifier).state = walletType;

    final localPubB58 = base58.encode(localPublicKey.asTypedList);

    // Use custom scheme redirect so that the OS directly launches the app 
    // without requiring Universal Link / App Link validation in development/emulators
    final redirectLink = 'tranyx://onConnect';

    final queryParams = {
      'dapp_encryption_public_key': localPubB58,
      'app_url': 'https://tranyx.com',
      'redirect_link': redirectLink,
      'cluster': 'devnet', // Target devnet for Tranyx local/dev testing
    };

    // Determine deep link prefix based on wallet type
    String baseScheme;
    switch (walletType) {
      case 'solflare':
        baseScheme = 'https://solflare.com/ul/v1/connect';
        break;
      case 'backpack':
        baseScheme = 'https://backpack.app/ul/v1/connect';
        break;
      case 'trust':
        baseScheme = 'https://trustwallet.com/ul/v1/connect';
        break;
      case 'phantom':
      default:
        baseScheme = 'https://phantom.app/ul/v1/connect';
        break;
    }

    // Try to construct standard deep link URL
    return Uri.parse('$baseScheme?${Uri(queryParameters: queryParams).query}');
  }

  /// Decrypts the connect response query parameters using the saved session private key.
  Map<String, dynamic>? decryptConnectResponse({
    required String phantomPubB58,
    required String dataB58,
    required String nonceB58,
    required Uint8List sessionPrivateKeyBytes,
  }) {
    try {
      final localPrivateKey = PrivateKey(sessionPrivateKeyBytes);
      final remotePublicKey = PublicKey(
        Uint8List.fromList(base58.decode(phantomPubB58)),
      );

      final decodedNonce = base58.decode(nonceB58);
      final decodedCipherText = base58.decode(dataB58);

      final msg = EncryptedMessage(
        nonce: Uint8List.fromList(decodedNonce),
        cipherText: Uint8List.fromList(decodedCipherText),
      );

      final appBox = Box(
        myPrivateKey: localPrivateKey,
        theirPublicKey: remotePublicKey,
      );

      final decryptedBytes = appBox.decrypt(msg);
      final decryptedText = utf8.decode(decryptedBytes);

      final Map<String, dynamic> payload = jsonDecode(decryptedText);
      return payload;
    } catch (e) {
      debugPrint('PhantomService: Decryption failed: $e');
      return null;
    }
  }
}
