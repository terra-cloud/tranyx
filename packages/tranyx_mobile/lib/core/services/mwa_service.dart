import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:bs58/bs58.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';
import 'package:tranyx_mobile/flavors.dart';

/// Why an MWA (Solana Mobile Wallet Adapter) request did not complete.
enum MwaFailureType {
  /// MWA only exists on Android. iOS (and web) fall back to the existing
  /// deep-link / WalletConnect wallets or a manual flow.
  unsupportedPlatform,

  /// No installed app answers the MWA intent (Phantom, Solflare, Seed Vault ...).
  noWalletInstalled,

  /// The user declined in the wallet, or the wallet closed without answering.
  /// `solana_mobile_client` swallows platform errors, so a decline and a
  /// wallet-side failure are indistinguishable here.
  userCancelled,

  /// The wallet authorized a different account than the one linked to Tranyx.
  walletMismatch,

  /// The association with the wallet could not be established in time.
  sessionFailed,
}

class MwaException implements Exception {
  const MwaException(this.type, this.message);

  final MwaFailureType type;
  final String message;

  @override
  String toString() => message;
}

/// Result of a wallet authorization.
class MwaAuthorization {
  const MwaAuthorization({
    required this.publicKey,
    required this.authToken,
    this.accountLabel,
  });

  /// Base58 Solana public key of the authorized account.
  final String publicKey;

  /// Wallet-issued token. Deliberately NOT persisted by Tranyx: every action
  /// authorizes again, so no wallet credential is ever stored.
  final String authToken;
  final String? accountLabel;
}

/// One open wallet session (a single MWA association).
abstract class MwaSession {
  Future<MwaAuthorization?> authorize({required String cluster});
  Future<bool> supportsSignAndSend();
  Future<List<Uint8List>> signAndSendTransactions(List<Uint8List> txs);
  Future<List<Uint8List>> signTransactions(List<Uint8List> txs);
  Future<void> close();
}

/// Platform seam so [MwaService] can be unit tested without Android.
abstract class MwaPlatform {
  bool get isSupported;
  Future<bool> isWalletAvailable();
  Future<MwaSession> open();
}

/// Real implementation backed by `solana_mobile_client` (Android only).
class SolanaMobileMwaPlatform implements MwaPlatform {
  const SolanaMobileMwaPlatform();

  static final Uri _identityUri = Uri.parse('https://tranyx.app');
  // MWA resolves the icon relative to the identity uri.
  static final Uri _iconUri = Uri.parse('favicon.ico');

  @override
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  @override
  Future<bool> isWalletAvailable() async {
    if (!isSupported) return false;
    try {
      return await LocalAssociationScenario.isAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<MwaSession> open() async {
    final scenario = await LocalAssociationScenario.create();
    try {
      // Launches the wallet; completes when the wallet activity returns.
      unawaited(scenario.startActivityForResult(null).catchError((_) {}));
      final client = await scenario.start().timeout(const Duration(seconds: 30));
      return _PluginSession(scenario, client);
    } catch (e) {
      try {
        await scenario.close();
      } catch (_) {}
      if (e is TimeoutException) {
        throw const MwaException(
          MwaFailureType.sessionFailed,
          'Could not reach your wallet app. Open it once and try again.',
        );
      }
      rethrow;
    }
  }
}

class _PluginSession implements MwaSession {
  _PluginSession(this._scenario, this._client);

  final LocalAssociationScenario _scenario;
  final MobileWalletAdapterClient _client;

  @override
  Future<MwaAuthorization?> authorize({required String cluster}) async {
    final result = await _client.authorize(
      identityUri: SolanaMobileMwaPlatform._identityUri,
      iconUri: SolanaMobileMwaPlatform._iconUri,
      identityName: 'Tranyx',
      cluster: cluster,
    );
    if (result == null) return null;
    return MwaAuthorization(
      publicKey: base58.encode(result.publicKey),
      authToken: result.authToken,
      accountLabel: result.accountLabel,
    );
  }

  @override
  Future<bool> supportsSignAndSend() async {
    final caps = await _client.getCapabilities();
    // If the wallet will not say, assume the common case (sign_and_send is
    // implemented by Phantom, Solflare and Seed Vault).
    return caps?.supportsSignAndSendTransactions ?? true;
  }

  @override
  Future<List<Uint8List>> signAndSendTransactions(List<Uint8List> txs) async =>
      (await _client.signAndSendTransactions(transactions: txs)).signatures;

  @override
  Future<List<Uint8List>> signTransactions(List<Uint8List> txs) async =>
      (await _client.signTransactions(transactions: txs)).signedPayloads;

  @override
  Future<void> close() => _scenario.close();
}

/// Solana Mobile Wallet Adapter for Tranyx (Android).
///
/// - [connect]: authorize and return the wallet's public key (used to link a
///   wallet and to confirm a withdraw destination). No signing, no custody.
/// - [signAndSend]: authorize, let the caller build a transaction for the
///   authorized account, then have the wallet sign and send it (deposit).
///
/// Withdraw payouts are NOT signed here; they stay server/treasury side.
class MwaService {
  MwaService({MwaPlatform? platform, required this.cluster})
    : _platform = platform ?? const SolanaMobileMwaPlatform();

  final MwaPlatform _platform;

  /// MWA cluster name: `mainnet-beta`, `testnet` or `devnet`.
  final String cluster;

  bool get isSupported => _platform.isSupported;

  Future<bool> isWalletAvailable() async =>
      isSupported && await _platform.isWalletAvailable();

  Future<MwaSession> _openChecked() async {
    if (!isSupported) {
      throw const MwaException(
        MwaFailureType.unsupportedPlatform,
        'Solana Mobile Wallet Adapter is only available on Android. '
        'Use Phantom, Solflare or Trust Wallet instead.',
      );
    }
    if (!await _platform.isWalletAvailable()) {
      throw const MwaException(
        MwaFailureType.noWalletInstalled,
        'No Solana wallet app was found on this phone. Install Phantom or '
        'Solflare and try again.',
      );
    }
    return _platform.open();
  }

  static MwaException get _declined => const MwaException(
    MwaFailureType.userCancelled,
    'The request was cancelled or declined in your wallet.',
  );

  Future<MwaAuthorization> connect() async {
    final session = await _openChecked();
    try {
      final auth = await session.authorize(cluster: cluster);
      if (auth == null) throw _declined;
      return auth;
    } finally {
      await _safeClose(session);
    }
  }

  /// Authorizes, builds one transaction for the authorized account, and has the
  /// wallet sign and send it. Returns the base58 transaction signature.
  ///
  /// [expectedPublicKey]: when set, the authorized account must match it
  /// (the wallet linked to the Tranyx account).
  /// [broadcastSigned]: used only when the wallet cannot sign-and-send; it gets
  /// the signed transaction bytes and must return the signature.
  Future<String> signAndSend({
    required Future<Uint8List> Function(String senderPublicKey) buildTransaction,
    required Future<String> Function(Uint8List signedTransaction) broadcastSigned,
    String? expectedPublicKey,
  }) async {
    final session = await _openChecked();
    try {
      final auth = await session.authorize(cluster: cluster);
      if (auth == null) throw _declined;
      if (expectedPublicKey != null &&
          expectedPublicKey.isNotEmpty &&
          auth.publicKey != expectedPublicKey) {
        throw const MwaException(
          MwaFailureType.walletMismatch,
          'Your wallet selected a different account than the one linked to '
          'Tranyx. Switch to the linked account and try again.',
        );
      }
      final tx = await buildTransaction(auth.publicKey);
      if (await session.supportsSignAndSend()) {
        final sigs = await session.signAndSendTransactions([tx]);
        if (sigs.isEmpty) throw _declined;
        return base58.encode(sigs.first);
      }
      final signed = await session.signTransactions([tx]);
      if (signed.isEmpty) throw _declined;
      return await broadcastSigned(signed.first);
    } finally {
      await _safeClose(session);
    }
  }

  Future<void> _safeClose(MwaSession session) async {
    try {
      await session.close();
    } catch (_) {}
  }
}

/// MWA cluster for the current app flavor (matches the deep-link wallets).
String mwaClusterForFlavor() {
  switch (F.appFlavor) {
    case Flavor.production:
      return 'mainnet-beta';
    case Flavor.uat:
      return 'testnet';
    case Flavor.dev:
      return 'devnet';
  }
}

final mwaServiceProvider = Provider<MwaService>(
  (ref) => MwaService(cluster: mwaClusterForFlavor()),
);

/// Decides what to do when linking [publicKey] for [uid], given the current
/// owner (if any) of that wallet in the `walletLinks` index (KAN-124: one
/// wallet, one account).
bool walletLinkedToAnotherAccount({
  required String? existingOwnerUid,
  required String uid,
}) => existingOwnerUid != null && existingOwnerUid != uid;

/// Short `abcd1234…wxyz5678` form of a public key for display.
String shortWalletKey(String key) =>
    key.length <= 16 ? key : '${key.substring(0, 8)}...${key.substring(key.length - 8)}';
