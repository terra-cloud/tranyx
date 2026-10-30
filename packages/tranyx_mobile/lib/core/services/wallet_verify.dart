import 'package:shared/shared.dart';
import 'package:tranyx_mobile/core/services/cloud_function_client.dart';
import 'package:tranyx_mobile/core/services/mwa_service.dart';
import 'package:tranyx_mobile/core/services/mwa_wallet_link.dart' show kMwaWalletType;

/// One-time proof that the linked wallet is the user's: the wallet signs a server challenge
/// (`walletAuthNonce`, purpose `link`) and `walletAuthLink` records the Admin-only `wallet_verified`
/// entry that `creditOnchainPayment` requires. Deposits and subscriptions call [ensureWalletVerified]
/// BEFORE any money leaves the wallet.
typedef WalletCallable = Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data);

/// Challenges are issued for the Tranyx site; the apps have no browser Origin, so they name it.
const Map<String, String> kWalletAuthHeaders = {'Origin': 'https://tranyx.app'};

class WalletVerifyException implements Exception {
  const WalletVerifyException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Shown for wallets that cannot sign a message from this app (Phantom / Trust deep links).
const String kVerifyOnWebMessage =
    'Verify your wallet once before depositing: open tranyx.app, go to Profile and tap Verify next to your Solana wallet (one signature, no fee), then come back and deposit again.';

String _rejection(Object? reason) => switch (reason) {
  'BAD_SIGNATURE' => 'The wallet signature could not be verified. Please try again.',
  'WALLET_LINKED_TO_ANOTHER_ACCOUNT' => 'This Solana wallet is already linked to another Tranyx account.',
  'ACCOUNT_BLOCKED' => 'This account cannot verify a wallet right now. Please contact support.',
  _ => 'Wallet verification was refused. Please try again.',
};

/// Whether the caller's linked wallet already has a server-side proof.
Future<bool> isWalletVerified({WalletCallable? call}) async {
  final c = call ?? ((n, d) => callCloudFunction(n, d, extraHeaders: kWalletAuthHeaders));
  final res = await c('walletAuthStatus', <String, dynamic>{});
  return res['verified'] == true;
}

/// Returns when [pubkey] is verified (asking the wallet for one signature if needed and possible);
/// throws [WalletVerifyException] (or [MwaException] / [CloudFunctionException]) otherwise.
Future<void> ensureWalletVerified({
  required MwaService mwa,
  required String? walletType,
  required String pubkey,
  WalletCallable? call,
}) async {
  final c = call ?? ((n, d) => callCloudFunction(n, d, extraHeaders: kWalletAuthHeaders));
  if (await isWalletVerified(call: c)) return;
  if (walletType != kMwaWalletType) throw const WalletVerifyException(kVerifyOnWebMessage);

  String? nonce;
  final signed = await mwa.signMessage(
    expectedPublicKey: pubkey,
    buildMessage: (wallet) async {
      final res = await c('walletAuthNonce', {'wallet': wallet, 'purpose': 'link'});
      final message = res['message'];
      final n = res['nonce'];
      if (message is! String || n is! String || message.isEmpty || n.isEmpty) {
        throw const WalletVerifyException('Unexpected server response. Please try again.');
      }
      nonce = n;
      return message;
    },
  );
  final res = await c('walletAuthLink', {'wallet': signed.publicKey, 'nonce': nonce, 'signature': signed.signature});
  if (res['status'] != 'linked') throw WalletVerifyException(_rejection(res['reason']));
}

/// The server's backstop for a deposit that slipped through unverified.
bool isWalletNotVerifiedError(Object e) => e is CloudFunctionException && e.message.contains('WALLET_NOT_VERIFIED');
