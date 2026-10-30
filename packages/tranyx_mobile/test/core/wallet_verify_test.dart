import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tranyx_mobile/core/services/mwa_service.dart';
import 'package:tranyx_mobile/core/services/wallet_verify.dart';

const _wallet = 'So11111111111111111111111111111111111111112';

class _Session implements MwaSession {
  @override
  Future<MwaAuthorization?> authorize({required String cluster}) async => MwaAuthorization(publicKey: _wallet, authToken: 't');
  @override
  Future<bool> supportsSignAndSend() async => true;
  @override
  Future<List<Uint8List>> signAndSendTransactions(List<Uint8List> txs) async => [];
  @override
  Future<List<Uint8List>> signTransactions(List<Uint8List> txs) async => [];
  @override
  Future<List<Uint8List>> signMessages(List<Uint8List> messages, Uint8List address) async => [Uint8List(64)];
  @override
  Future<void> close() async {}
}

class _Platform implements MwaPlatform {
  @override
  bool get isSupported => true;
  @override
  Future<bool> isWalletAvailable() async => true;
  @override
  Future<MwaSession> open() async => _Session();
}

void main() {
  final mwa = MwaService(platform: _Platform(), cluster: 'devnet');

  test('already verified: nothing is signed', () async {
    final calls = <String>[];
    await ensureWalletVerified(
      mwa: mwa,
      walletType: 'mwa',
      pubkey: _wallet,
      call: (n, d) async {
        calls.add(n);
        return {'verified': true};
      },
    );
    expect(calls, ['walletAuthStatus']);
  });

  test('MWA wallet: challenge -> signature -> walletAuthLink, sending only wallet/nonce/signature', () async {
    final calls = <String, Map<String, dynamic>>{};
    await ensureWalletVerified(
      mwa: mwa,
      walletType: 'mwa',
      pubkey: _wallet,
      call: (n, d) async {
        calls[n] = d;
        return switch (n) {
          'walletAuthStatus' => {'verified': false},
          'walletAuthNonce' => {'nonce': 'ab' * 16, 'message': 'sign me'},
          _ => {'status': 'linked', 'wallet': _wallet},
        };
      },
    );
    expect(calls['walletAuthNonce'], {'wallet': _wallet, 'purpose': 'link'});
    expect(calls['walletAuthLink']!.keys.toSet(), {'wallet', 'nonce', 'signature'});
    expect(calls['walletAuthLink']!['nonce'], 'ab' * 16);
  });

  test('a refusal from the server surfaces a clear message', () async {
    await expectLater(
      ensureWalletVerified(
        mwa: mwa,
        walletType: 'mwa',
        pubkey: _wallet,
        call: (n, d) async => switch (n) {
          'walletAuthStatus' => {'verified': false},
          'walletAuthNonce' => {'nonce': 'ab' * 16, 'message': 'm'},
          _ => {'status': 'rejected', 'reason': 'WALLET_LINKED_TO_ANOTHER_ACCOUNT'},
        },
      ),
      throwsA(isA<WalletVerifyException>().having((e) => e.message, 'message', contains('another Tranyx account'))),
    );
  });

  test('wallets that cannot sign here (Phantom/Trust) get the verify-on-web message and nothing is signed', () async {
    final calls = <String>[];
    await expectLater(
      ensureWalletVerified(
        mwa: mwa,
        walletType: 'phantom',
        pubkey: _wallet,
        call: (n, d) async {
          calls.add(n);
          return {'verified': false};
        },
      ),
      throwsA(isA<WalletVerifyException>().having((e) => e.message, 'message', kVerifyOnWebMessage)),
    );
    expect(calls, ['walletAuthStatus']);
  });
}
