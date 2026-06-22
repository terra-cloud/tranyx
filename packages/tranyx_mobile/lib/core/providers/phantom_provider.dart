import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:pinenacl/x25519.dart';
import 'package:bs58/bs58.dart';
import 'package:tranyx_mobile/core/utils/secure_storage_helper.dart';

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

class WalletInfo {
  final String id;
  final String name;
  final String assetPath;

  /// Native deep-link scheme used on Android/iOS (e.g. `phantom://v1/connect`).
  /// This directly triggers the wallet app's connect flow without going through
  /// a browser. Requires the wallet app to be installed.
  final String nativeScheme;

  /// Universal / HTTPS fallback link if native scheme is unavailable.
  final String universalLink;

  /// Play Store URL for the "not installed" case on Android.
  final String androidStoreUrl;

  /// App Store URL for the "not installed" case on iOS.
  final String iosStoreUrl;

  const WalletInfo({
    required this.id,
    required this.name,
    required this.assetPath,
    required this.nativeScheme,
    required this.universalLink,
    required this.androidStoreUrl,
    required this.iosStoreUrl,
  });
}

const kSupportedWallets = [
  WalletInfo(
    id: 'phantom',
    name: 'Phantom',
    assetPath: 'assets/images/PhantomWallet.png',
    nativeScheme: 'phantom://v1/connect',
    universalLink: 'https://phantom.app/ul/v1/connect',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=app.phantom',
    iosStoreUrl:
        'https://apps.apple.com/app/phantom-solana-wallet/id1598432977',
  ),
  WalletInfo(
    id: 'solflare',
    name: 'Solflare',
    assetPath: 'assets/images/Solflare.png',
    nativeScheme: 'solflare://v1/connect',
    universalLink: 'https://solflare.com/ul/v1/connect',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=com.solflare.mobile',
    iosStoreUrl:
        'https://apps.apple.com/app/solflare-solana-wallet/id1580902717',
  ),
  WalletInfo(
    id: 'backpack',
    name: 'Backpack',
    assetPath: 'assets/images/BackPack.png',
    nativeScheme: 'backpack://v1/connect',
    universalLink: 'https://backpack.app/ul/v1/connect',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=app.backpack',
    iosStoreUrl: 'https://apps.apple.com/app/backpack/id6443943843',
  ),
  WalletInfo(
    id: 'trust',
    name: 'Trust Wallet',
    assetPath: 'assets/images/TrustWallet.jpeg',
    nativeScheme: 'trustwallet://v1/connect',
    universalLink: 'https://trustwallet.com/ul/v1/connect',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=com.wallet.crypto.trustapp',
    iosStoreUrl:
        'https://apps.apple.com/app/trust-crypto-bitcoin-wallet/id1288339409',
  ),
];

class PhantomService {
  final Ref _ref;

  PhantomService(this._ref);

  /// Generates an ephemeral key pair for the connection session,
  /// saves the private key to the state provider, and returns the wallet connect URI.
  ///
  /// Uses the **native custom URI scheme** (e.g. `phantom://v1/connect`) so the
  /// OS directly opens the wallet app's connect / authorize screen.
  /// Universal links (https://) are not used because Android requires verified
  /// App Links before they deep-link; otherwise they just open a browser.
  Future<Uri> generateConnectUri({required String walletType}) async {
    // Generate ephemeral session key pair
    final localPrivateKey = PrivateKey.generate();
    final localPublicKey = localPrivateKey.publicKey;

    // Persist private key to Riverpod state provider
    _ref.read(phantomSessionPrivateKeyProvider.notifier).state =
        localPrivateKey.asTypedList;
    _ref.read(connectingWalletTypeProvider.notifier).state = walletType;

    // Also persist to secure storage so it survives potential app background termination
    await SecureStorageHelper.savePhantomSessionKey(localPrivateKey.asTypedList);
    await SecureStorageHelper.saveConnectingWalletType(walletType);

    final localPubB58 = base58.encode(localPublicKey.asTypedList);

    // The redirect_link must use our custom scheme so Android/iOS opens the app
    const redirectLink = 'tranyx://onConnect';

    final queryParams = {
      'dapp_encryption_public_key': localPubB58,
      'app_url': 'https://tranyx.app',
      'redirect_link': redirectLink,
      'cluster': 'mainnet-beta',
    };

    final wallet = kSupportedWallets.firstWhere(
      (w) => w.id == walletType,
      orElse: () => kSupportedWallets.first,
    );

    final baseUrl = wallet.nativeScheme;
    final queryString = Uri(queryParameters: queryParams).query;
    debugPrint('PhantomService: Launching $baseUrl?$queryString');
    return Uri.parse('$baseUrl?$queryString');
  }

  /// Returns the Play Store / App Store URL for the given wallet on this platform.
  String storeUrlFor(String walletType) {
    final wallet = kSupportedWallets.firstWhere(
      (w) => w.id == walletType,
      orElse: () => kSupportedWallets.first,
    );
    return Platform.isIOS ? wallet.iosStoreUrl : wallet.androidStoreUrl;
  }

  /// Decrypts the connect response parameters returned by the wallet app.
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
