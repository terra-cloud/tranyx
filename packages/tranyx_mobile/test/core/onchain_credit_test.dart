import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared/shared.dart' show CloudFunctionException;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tranyx_mobile/core/services/onchain_credit.dart';

/// The app no longer writes balances or markers: crediting is the server's job (see
/// functions/test/credit.spec.ts). These tests pin the client contract.
void main() {
  late FakeFirebaseFirestore db;
  const sig = 'sig-1';

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({'tyxBalance': 100.0, 'isPremium': false});
  });

  Future<Map<String, dynamic>> user() async => (await db.collection('users').doc('u1').get()).data()!;
  Future<DocumentSnapshot<Map<String, dynamic>>> tx(String id) => db.collection('transactions').doc(id).get();

  Future<OnchainCommitResult> deposit(Map<String, dynamic> response, {bool usdt = false, List<Map<String, dynamic>>? sent}) =>
      creditOnchainDeposit(
        firestore: db,
        uid: 'u1',
        signature: sig,
        isUsdt: usdt,
        invoke: (d) async {
          sent?.add(d);
          return response;
        },
      );

  group('creditOnchainDeposit / activateSubscriptionOnce call the server and write nothing themselves', () {
    test('credited: no client write to the balance, markers or pending record', () async {
      final sent = <Map<String, dynamic>>[];
      expect(await deposit({'status': 'credited', 'phpAmount': 4000}, sent: sent), OnchainCommitResult.credited);
      expect(sent.single, {'signature': sig, 'kind': 'deposit_sol'});
      expect((await user())['tyxBalance'], 100.0);
      expect((await tx('onchain_$sig')).exists, isFalse);
      expect((await tx('deposit_sol_$sig')).exists, isFalse);
    });

    test('USDT deposits use kind deposit_usdt; the client never sends an amount', () async {
      final sent = <Map<String, dynamic>>[];
      await deposit({'status': 'credited'}, usdt: true, sent: sent);
      expect(sent.single, {'signature': sig, 'kind': 'deposit_usdt'});
    });

    test('subscription sends the plan only', () async {
      final sent = <Map<String, dynamic>>[];
      final r = await activateSubscriptionOnce(
        firestore: db,
        uid: 'u1',
        signature: sig,
        plan: 'yearly',
        invoke: (d) async {
          sent.add(d);
          return {'status': 'credited', 'plan': 'yearly'};
        },
      );
      expect(r, OnchainCommitResult.credited);
      expect(sent.single, {'signature': sig, 'kind': 'subscription_sol', 'plan': 'yearly'});
      expect((await user())['isPremium'], false);
    });

    test('replay is alreadyProcessed and needs no support', () async {
      final r = await deposit({'status': 'already_processed'});
      expect(r, OnchainCommitResult.alreadyProcessed);
      expect(r.needsSupport, isFalse);
    });

    test('a marker held by another account sends the user to support and notes the pending record', () async {
      final r = await deposit({'status': 'held_by_another_account'});
      expect(r, OnchainCommitResult.heldByAnotherAccount);
      expect(() => r.throwIfHeldElsewhere(sig), throwsA(isA<OnchainSupportException>()));
      expect((await tx(pendingOnchainId('u1', sig))).data(), containsPair('note', kMarkerHeldNote));
    });

    test('a server rejection needs support (the server writes its own note)', () async {
      final r = await deposit({'status': 'rejected', 'reason': 'NO_MATCHING_TRANSFER'});
      expect(r, OnchainCommitResult.rejectedByServer);
      expect(r.needsSupport, isTrue);
      expect(() => r.throwIfHeldElsewhere(sig), throwsA(isA<OnchainSupportException>()));
    });

    test('a hard server failure is not swallowed', () async {
      await expectLater(
        creditOnchainDeposit(
          firestore: db,
          uid: 'u1',
          signature: sig,
          isUsdt: false,
          invoke: (_) async => throw const CloudFunctionException('UNAUTHENTICATED', 'Sign in'),
        ),
        throwsA(isA<CloudFunctionException>()),
      );
    });
  });

  group('pending on-chain record (bookkeeping the app still writes before waiting)', () {
    test('is created once, owner-bound, without createdAt, and never overwritten', () async {
      await writePendingOnchain(
        firestore: db,
        uid: 'u1',
        signature: sig,
        kind: 'deposit',
        phpAmount: 50,
        cryptoAmount: 0.01,
        currency: 'SOL',
      );
      final first = (await tx(pendingOnchainId('u1', sig))).data()!;
      expect(first, containsPair('status', 'pending'));
      expect(first.containsKey('createdAt'), isFalse);
      await writePendingOnchain(
        firestore: db,
        uid: 'u1',
        signature: sig,
        kind: 'deposit',
        phpAmount: 999,
        cryptoAmount: 9,
        currency: 'SOL',
      );
      expect((await tx(pendingOnchainId('u1', sig))).data()!['phpAmount'], 50);
    });

    test('a note is added to a pending record, created when missing, and never reopens a done record', () async {
      await notePendingOnchain(firestore: db, uid: 'u1', signature: 'a', note: kContentionNote);
      expect((await tx(pendingOnchainId('u1', 'a'))).data(), containsPair('note', kContentionNote));
      await db.collection('transactions').doc(pendingOnchainId('u1', 'b')).set({'status': 'done'});
      await notePendingOnchain(firestore: db, uid: 'u1', signature: 'b', note: 'late');
      expect((await tx(pendingOnchainId('u1', 'b'))).data(), {'status': 'done'});
    });
  });
}
