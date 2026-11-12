// Wallet sign-in flow logic: challenge -> wallet signature -> signIn / needs_signup / rejected, and
// linking by proof or ticket. The callable and the wallet are fakes.
import 'package:shared/shared.dart';
import 'package:test/test.dart';
import 'package:tranyx_web/services/wallet_auth_flow.dart';

void main() {
  const wallet = '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU';
  final calls = <(String, Map<String, dynamic>)>[];
  late Map<String, Object> responses; // callable name -> result map or exception
  final signed = <(String, String)>[];
  String? signature;

  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    calls.add((name, data));
    final r = responses[name];
    if (r is Exception) throw r;
    return Map<String, dynamic>.from(r as Map);
  }

  Future<String?> sign(String w, String m) async {
    signed.add((w, m));
    return signature;
  }

  setUp(() {
    calls.clear();
    signed.clear();
    signature = 'c2lnbmF0dXJl';
    responses = {
      'walletAuthNonce': {'nonce': 'n' * 32, 'message': 'dev.tranyx.app wants you to sign in'},
    };
  });

  group('signInWithWallet', () {
    test('known wallet: signs the server message and returns the custom token', () async {
      responses['walletAuthSignIn'] = {'status': 'signed_in', 'customToken': 'tok'};
      final out = await signInWithWallet(wallet: wallet, call: call, sign: sign);
      expect(out.kind, WalletSignInKind.signedIn);
      expect(out.customToken, 'tok');
      expect(calls[0].$1, 'walletAuthNonce');
      expect(calls[0].$2, {'wallet': wallet, 'purpose': 'signin'});
      expect(signed.single, (wallet, 'dev.tranyx.app wants you to sign in'));
      expect(calls[1].$2, {'wallet': wallet, 'nonce': 'n' * 32, 'signature': 'c2lnbmF0dXJl'});
    });

    test('new wallet: goes to account creation with the sign-up ticket', () async {
      responses['walletAuthSignIn'] = {'status': 'needs_signup', 'ticket': 't1', 'expiresAt': 1};
      final out = await signInWithWallet(wallet: wallet, call: call, sign: sign);
      expect(out.kind, WalletSignInKind.needsSignup);
      expect(out.ticket, 't1');
      expect(out.customToken, isNull);
    });

    test('rejections map to fixed messages (staff, blocked, unverified link)', () async {
      for (final reason in ['STAFF_ACCOUNT', 'ACCOUNT_BLOCKED', 'WALLET_LINK_UNVERIFIED', 'BAD_SIGNATURE']) {
        responses['walletAuthSignIn'] = {'status': 'rejected', 'reason': reason};
        final out = await signInWithWallet(wallet: wallet, call: call, sign: sign);
        expect(out.kind, WalletSignInKind.rejected, reason: reason);
        expect(out.message, walletRejectionMessage(reason));
      }
      expect(walletRejectionMessage('STAFF_ACCOUNT'), contains('admin portal'));
      expect(walletRejectionMessage('WALLET_LINK_UNVERIFIED'), contains('re-link'));
      expect(walletRejectionMessage('something internal'), isNot(contains('internal')));
    });

    test('wallet refuses to sign: no sign-in call is made', () async {
      signature = null;
      final out = await signInWithWallet(wallet: wallet, call: call, sign: sign);
      expect(out.kind, WalletSignInKind.failed);
      expect(calls.map((c) => c.$1), ['walletAuthNonce']);
    });

    test('a signed_in reply without a token, or an unknown status, is a failure (never a sign-in)', () async {
      responses['walletAuthSignIn'] = {'status': 'signed_in'};
      expect((await signInWithWallet(wallet: wallet, call: call, sign: sign)).kind, WalletSignInKind.failed);
      responses['walletAuthSignIn'] = {'status': 'weird'};
      expect((await signInWithWallet(wallet: wallet, call: call, sign: sign)).kind, WalletSignInKind.failed);
    });

    test('server / network errors surface the callable message', () async {
      responses['walletAuthNonce'] = const CloudFunctionException(
        'PERMISSION_DENIED',
        'This site is not allowed to request a wallet sign-in.',
      );
      final out = await signInWithWallet(wallet: wallet, call: call, sign: sign);
      expect(out.kind, WalletSignInKind.failed);
      expect(out.message, contains('not allowed'));
      expect(signed, isEmpty);
    });

    test('a malformed challenge is not signed', () async {
      responses['walletAuthNonce'] = {'nonce': '', 'message': ''};
      final out = await signInWithWallet(wallet: wallet, call: call, sign: sign);
      expect(out.kind, WalletSignInKind.failed);
      expect(signed, isEmpty);
    });
  });

  group('linking', () {
    test('proveAndLinkWallet: link challenge, signature, walletAuthLink', () async {
      responses['walletAuthLink'] = {'status': 'linked', 'wallet': wallet};
      final out = await proveAndLinkWallet(wallet: wallet, call: call, sign: sign);
      expect(out.linked, isTrue);
      expect(calls[0].$2['purpose'], 'link');
      expect(calls[1].$1, 'walletAuthLink');
      expect(calls[1].$2, {'wallet': wallet, 'nonce': 'n' * 32, 'signature': 'c2lnbmF0dXJl'});
    });

    test('a wallet linked to another account is refused with its message', () async {
      responses['walletAuthLink'] = {'status': 'rejected', 'reason': 'WALLET_LINKED_TO_ANOTHER_ACCOUNT'};
      final out = await proveAndLinkWallet(wallet: wallet, call: call, sign: sign);
      expect(out.linked, isFalse);
      expect(out.message, contains('already linked to another'));
    });

    test('no signature, no link call', () async {
      signature = null;
      final out = await proveAndLinkWallet(wallet: wallet, call: call, sign: sign);
      expect(out.linked, isFalse);
      expect(calls.map((c) => c.$1), ['walletAuthNonce']);
    });

    test('linkWalletWithTicket (after sign-up): sends only the ticket', () async {
      responses['walletAuthLink'] = {'status': 'linked', 'wallet': wallet};
      final out = await linkWalletWithTicket(ticket: 'tkt', call: call);
      expect(out.linked, isTrue);
      expect(calls.single.$1, 'walletAuthLink');
      expect(calls.single.$2, {'ticket': 'tkt'});
      responses['walletAuthLink'] = {'status': 'rejected', 'reason': 'BAD_TICKET'};
      final bad = await linkWalletWithTicket(ticket: 'tkt', call: call);
      expect(bad.linked, isFalse);
      expect(bad.message, contains('expired'));
    });
  });
}
