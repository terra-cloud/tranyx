import 'dart:io';
import 'dart:typed_data';

import 'package:bs58/bs58.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tranyx_mobile/core/services/mwa_service.dart';
import 'package:tranyx_mobile/core/widgets/solana_logo.dart';

const _wallet = 'So11111111111111111111111111111111111111112';

class _FakeSession implements MwaSession {
  _FakeSession({
    this.auth,
    this.signAndSend = true,
    this.sentSignatures,
    this.signedPayloads,
  });

  final MwaAuthorization? auth;
  final bool signAndSend;
  final List<Uint8List>? sentSignatures;
  final List<Uint8List>? signedPayloads;
  bool closed = false;
  String? clusterAsked;
  List<Uint8List> lastSent = [];

  @override
  Future<MwaAuthorization?> authorize({required String cluster}) async {
    clusterAsked = cluster;
    return auth;
  }

  @override
  Future<bool> supportsSignAndSend() async => signAndSend;

  @override
  Future<List<Uint8List>> signAndSendTransactions(List<Uint8List> txs) async {
    lastSent = txs;
    return sentSignatures ?? [];
  }

  @override
  Future<List<Uint8List>> signTransactions(List<Uint8List> txs) async {
    lastSent = txs;
    return signedPayloads ?? [];
  }

  @override
  Future<void> close() async => closed = true;
}

class _FakePlatform implements MwaPlatform {
  _FakePlatform({this.supported = true, this.walletAvailable = true, this.session});

  final bool supported;
  final bool walletAvailable;
  final _FakeSession? session;
  int opened = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> isWalletAvailable() async => walletAvailable;

  @override
  Future<MwaSession> open() async {
    opened++;
    return session!;
  }
}

MwaAuthorization _auth([String key = _wallet]) =>
    MwaAuthorization(publicKey: key, authToken: 'token');

Future<void> Function() _expectFailure(
  Future<Object?> Function() run,
  MwaFailureType type,
) => () async {
  await expectLater(
    run(),
    throwsA(isA<MwaException>().having((e) => e.type, 'type', type)),
  );
};

void main() {
  group('MwaService.connect', () {
    test('returns the authorized public key and closes the session', () async {
      final session = _FakeSession(auth: _auth());
      final service = MwaService(platform: _FakePlatform(session: session), cluster: 'devnet');
      final result = await service.connect();
      expect(result.publicKey, _wallet);
      expect(session.clusterAsked, 'devnet');
      expect(session.closed, isTrue);
    });

    test('unsupported platform (iOS) fails without opening a session', () async {
      final platform = _FakePlatform(supported: false);
      final service = MwaService(platform: platform, cluster: 'devnet');
      await _expectFailure(service.connect, MwaFailureType.unsupportedPlatform)();
      expect(platform.opened, 0);
      expect(await service.isWalletAvailable(), isFalse);
    });

    test('no wallet installed is reported, not crashed', () async {
      final platform = _FakePlatform(walletAvailable: false);
      final service = MwaService(platform: platform, cluster: 'devnet');
      await _expectFailure(service.connect, MwaFailureType.noWalletInstalled)();
      expect(platform.opened, 0);
    });

    test('declined authorization maps to userCancelled and still closes', () async {
      final session = _FakeSession(auth: null);
      final service = MwaService(platform: _FakePlatform(session: session), cluster: 'devnet');
      await _expectFailure(service.connect, MwaFailureType.userCancelled)();
      expect(session.closed, isTrue);
    });
  });

  group('MwaService.signAndSend', () {
    final sig = Uint8List.fromList(List<int>.generate(64, (i) => i + 1));
    final tx = Uint8List.fromList([1, 2, 3]);

    test('builds the tx for the authorized account and returns the base58 signature', () async {
      final session = _FakeSession(auth: _auth(), sentSignatures: [sig]);
      final service = MwaService(platform: _FakePlatform(session: session), cluster: 'mainnet-beta');
      String? builtFor;
      final result = await service.signAndSend(
        expectedPublicKey: _wallet,
        buildTransaction: (sender) async {
          builtFor = sender;
          return tx;
        },
        broadcastSigned: (_) async => fail('wallet supports sign-and-send'),
      );
      expect(builtFor, _wallet);
      expect(result, base58.encode(sig));
      expect(session.lastSent, [tx]);
      expect(session.closed, isTrue);
    });

    test('falls back to sign + app broadcast when the wallet cannot sign-and-send', () async {
      final signed = Uint8List.fromList([9, 9, 9]);
      final session = _FakeSession(auth: _auth(), signAndSend: false, signedPayloads: [signed]);
      final service = MwaService(platform: _FakePlatform(session: session), cluster: 'devnet');
      Uint8List? broadcasted;
      final result = await service.signAndSend(
        buildTransaction: (_) async => tx,
        broadcastSigned: (bytes) async {
          broadcasted = bytes;
          return 'sig-from-rpc';
        },
      );
      expect(result, 'sig-from-rpc');
      expect(broadcasted, signed);
    });

    test('a different wallet account than the linked one is rejected before building', () async {
      final session = _FakeSession(auth: _auth('11111111111111111111111111111111'), sentSignatures: [sig]);
      final service = MwaService(platform: _FakePlatform(session: session), cluster: 'devnet');
      var built = false;
      await _expectFailure(
        () => service.signAndSend(
          expectedPublicKey: _wallet,
          buildTransaction: (_) async {
            built = true;
            return tx;
          },
          broadcastSigned: (_) async => '',
        ),
        MwaFailureType.walletMismatch,
      )();
      expect(built, isFalse);
      expect(session.closed, isTrue);
    });

    test('user declining the signing request maps to userCancelled', () async {
      final session = _FakeSession(auth: _auth(), sentSignatures: const []);
      final service = MwaService(platform: _FakePlatform(session: session), cluster: 'devnet');
      await _expectFailure(
        () => service.signAndSend(
          buildTransaction: (_) async => tx,
          broadcastSigned: (_) async => '',
        ),
        MwaFailureType.userCancelled,
      )();
      expect(session.closed, isTrue);
    });

    test('a failure while building the tx still closes the session', () async {
      final session = _FakeSession(auth: _auth());
      final service = MwaService(platform: _FakePlatform(session: session), cluster: 'devnet');
      await expectLater(
        service.signAndSend(
          buildTransaction: (_) async => throw StateError('rpc down'),
          broadcastSigned: (_) async => '',
        ),
        throwsStateError,
      );
      expect(session.closed, isTrue);
    });
  });

  group('helpers', () {
    test('walletLinkedToAnotherAccount only flags a different owner', () {
      expect(walletLinkedToAnotherAccount(existingOwnerUid: null, uid: 'a'), isFalse);
      expect(walletLinkedToAnotherAccount(existingOwnerUid: 'a', uid: 'a'), isFalse);
      expect(walletLinkedToAnotherAccount(existingOwnerUid: 'b', uid: 'a'), isTrue);
    });

    test('shortWalletKey shortens long keys only', () {
      expect(shortWalletKey(_wallet), 'So111111...11111112');
      expect(shortWalletKey('short'), 'short');
    });
  });

  group('Solana logo asset', () {
    test('the PNG is on disk and declared through the assets/icons/ folder', () {
      expect(File(SolanaLogo.assetPath).existsSync(), isTrue);
      expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/icons/'));
    });

    testWidgets('SolanaLogo renders the asset at the requested size', (tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: SolanaLogo(size: 24),
      ));
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, SolanaLogo.assetPath);
      expect(image.width, 24);
    });
  });
}
