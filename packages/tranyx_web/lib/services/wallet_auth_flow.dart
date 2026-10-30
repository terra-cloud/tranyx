// Sign-In With Solana, client side. The wallet signs a one-time message the server issued
// (walletAuthNonce); the server verifies it and either returns a Firebase custom token
// (walletAuthSignIn) or a sign-up ticket for a wallet with no account yet. Linking a wallet to an
// account (walletAuthLink) needs the same signature proof. No browser code here: the callable and the
// wallet signer are injected, so the whole flow is unit-testable.
import 'package:shared/shared.dart';

typedef WalletCall = Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data);

/// Signs [message] with the wallet at [wallet]; null when the wallet did not return a signature.
typedef WalletSigner = Future<String?> Function(String wallet, String message);

enum WalletSignInKind { signedIn, needsSignup, rejected, failed }

class WalletSignInOutcome {
  const WalletSignInOutcome._(this.kind, {this.customToken, this.ticket, this.message = ''});
  final WalletSignInKind kind;
  final String? customToken;
  final String? ticket;

  /// User-facing text for [WalletSignInKind.rejected] / [WalletSignInKind.failed].
  final String message;

  factory WalletSignInOutcome.signedIn(String token) =>
      WalletSignInOutcome._(WalletSignInKind.signedIn, customToken: token);
  factory WalletSignInOutcome.needsSignup(String ticket) =>
      WalletSignInOutcome._(WalletSignInKind.needsSignup, ticket: ticket);
  factory WalletSignInOutcome.rejected(String message) =>
      WalletSignInOutcome._(WalletSignInKind.rejected, message: message);
  factory WalletSignInOutcome.failed(String message) =>
      WalletSignInOutcome._(WalletSignInKind.failed, message: message);
}

class WalletLinkOutcome {
  const WalletLinkOutcome(this.linked, this.message);
  final bool linked;
  final String message;
}

/// Text for the server's fixed rejection codes. Never shows server internals.
String walletRejectionMessage(String? reason) => switch (reason) {
  'BAD_SIGNATURE' => 'The wallet signature could not be verified. Please try again.',
  'BAD_TICKET' => 'This wallet sign-in expired. Please connect your wallet again.',
  'WALLET_LINK_UNVERIFIED' =>
    'This wallet was linked to an account before wallet sign-in was verified. Sign in with email or Google, then re-link your wallet from Profile (one signature).',
  'WALLET_LINKED_TO_ANOTHER_ACCOUNT' => 'This Solana wallet is already linked to another Tranyx account.',
  'ACCOUNT_BLOCKED' => 'This account cannot sign in right now. Please contact support.',
  'STAFF_ACCOUNT' => 'Staff accounts sign in through the admin portal, not tranyx.app.',
  _ => 'Wallet request was refused. Please try again.',
};

String _fnMessage(Object e) => e is CloudFunctionException ? e.message : 'Network error. Please try again.';

Future<({String nonce, String message})> _challenge(WalletCall call, String wallet, String purpose) async {
  final res = await call('walletAuthNonce', {'wallet': wallet, 'purpose': purpose});
  final nonce = res['nonce'];
  final message = res['message'];
  if (nonce is! String || message is! String || nonce.isEmpty || message.isEmpty) {
    throw const CloudFunctionException('INTERNAL', 'Unexpected server response.');
  }
  return (nonce: nonce, message: message);
}

/// Challenge -> wallet signature -> `walletAuthSignIn`.
Future<WalletSignInOutcome> signInWithWallet({
  required String wallet,
  required WalletCall call,
  required WalletSigner sign,
}) async {
  try {
    final c = await _challenge(call, wallet, 'signin');
    final signature = await sign(wallet, c.message);
    if (signature == null || signature.isEmpty) {
      return WalletSignInOutcome.failed('The wallet did not sign the sign-in request.');
    }
    final res = await call('walletAuthSignIn', {'wallet': wallet, 'nonce': c.nonce, 'signature': signature});
    switch (res['status']) {
      case 'signed_in':
        final token = res['customToken'];
        if (token is String && token.isNotEmpty) return WalletSignInOutcome.signedIn(token);
        return WalletSignInOutcome.failed('Unexpected server response.');
      case 'needs_signup':
        final ticket = res['ticket'];
        if (ticket is String && ticket.isNotEmpty) return WalletSignInOutcome.needsSignup(ticket);
        return WalletSignInOutcome.failed('Unexpected server response.');
      case 'rejected':
        return WalletSignInOutcome.rejected(walletRejectionMessage(res['reason'] as String?));
      default:
        return WalletSignInOutcome.failed('Unexpected server response.');
    }
  } catch (e) {
    return WalletSignInOutcome.failed(_fnMessage(e));
  }
}

/// Signed in: prove the wallet (purpose `link`) and link it to the caller via `walletAuthLink`.
Future<WalletLinkOutcome> proveAndLinkWallet({
  required String wallet,
  required WalletCall call,
  required WalletSigner sign,
}) async {
  try {
    final c = await _challenge(call, wallet, 'link');
    final signature = await sign(wallet, c.message);
    if (signature == null || signature.isEmpty) {
      return const WalletLinkOutcome(false, 'The wallet did not sign the linking request.');
    }
    return _linkResult(await call('walletAuthLink', {'wallet': wallet, 'nonce': c.nonce, 'signature': signature}));
  } catch (e) {
    return WalletLinkOutcome(false, _fnMessage(e));
  }
}

/// New account made after a wallet sign-in: link with the sign-up [ticket].
Future<WalletLinkOutcome> linkWalletWithTicket({required String ticket, required WalletCall call}) async {
  try {
    return _linkResult(await call('walletAuthLink', {'ticket': ticket}));
  } catch (e) {
    return WalletLinkOutcome(false, _fnMessage(e));
  }
}

WalletLinkOutcome _linkResult(Map<String, dynamic> res) {
  if (res['status'] == 'linked') return const WalletLinkOutcome(true, '');
  if (res['status'] == 'rejected') return WalletLinkOutcome(false, walletRejectionMessage(res['reason'] as String?));
  return const WalletLinkOutcome(false, 'Unexpected server response.');
}
