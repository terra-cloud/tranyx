import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tranyx_mobile/core/services/onchain_credit.dart';

void main() {
  late FakeFirebaseFirestore db;
  final now = DateTime.utc(2026, 10, 29, 12);
  const day = Duration(days: 1);

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({
      'tyxBalance': 100.0,
      'isPremium': false,
      'accountType': 'nyxian',
    });
  });

  Future<Map<String, dynamic>> user() async =>
      (await db.collection('users').doc('u1').get()).data()!;
  Future<DocumentSnapshot<Map<String, dynamic>>> tx(String id) =>
      db.collection('transactions').doc(id).get();

  Future<OnchainCommitResult> deposit(
    String sig, {
    String prefix = 'deposit_sol_',
    double php = 50,
  }) => creditOnchainDeposit(
    firestore: db,
    uid: 'u1',
    signature: sig,
    markerId: '$prefix$sig',
    phpAmount: php,
    markerData: {
      'uid': 'u1',
      'type': 'deposit',
      'amount': php,
      'solanaTxSignature': sig,
    },
  );

  Future<OnchainCommitResult> subscribe(
    String sig, {
    String plan = 'monthly',
    DateTime? at,
  }) => activateSubscriptionOnce(
    firestore: db,
    uid: 'u1',
    signature: sig,
    plan: plan,
    phpAmount: 199,
    cryptoAmount: 0.0245,
    now: at ?? now,
  );

  group('creditOnchainDeposit (atomic, idempotent per signature)', () {
    test(
      'first credit increments the balance and writes both markers',
      () async {
        expect(await deposit('sigA'), OnchainCommitResult.credited);
        expect((await user())['tyxBalance'], 150.0);
        expect((await tx('deposit_sol_sigA')).exists, isTrue);
        final shared = (await tx('onchain_sigA')).data()!;
        expect(shared['uid'], 'u1');
        expect(shared['markerId'], 'deposit_sol_sigA');
        expect(shared['solanaTxSignature'], 'sigA');
      },
    );

    test(
      'the same signature never credits twice (retry / double tap)',
      () async {
        final results = <OnchainCommitResult>[
          await deposit('sigB'),
          await deposit('sigB'),
          await deposit('sigB'),
        ];
        expect(results, [
          OnchainCommitResult.credited,
          OnchainCommitResult.alreadyProcessed,
          OnchainCommitResult.alreadyProcessed,
        ]);
        expect((await user())['tyxBalance'], 150.0);
      },
    );

    test('different signatures each credit once', () async {
      await deposit('s1');
      await deposit('s2', php: 25);
      expect((await user())['tyxBalance'], 175.0);
    });

    test('uses the current balance (increment), not a stale read', () async {
      await db.collection('users').doc('u1').update({'tyxBalance': 500.0});
      await deposit('s3');
      expect((await user())['tyxBalance'], 550.0);
    });

    test(
      'the shared marker has no createdAt so history never lists it',
      () async {
        await deposit('s4');
        expect(
          (await tx('onchain_s4')).data()!.containsKey('createdAt'),
          isFalse,
        );
      },
    );
  });

  group('one shared marker per signature across flows', () {
    test('a signature credited as a SOL deposit cannot be credited as a USDT deposit', () async {
      expect(await deposit('x1'), OnchainCommitResult.credited);
      expect(
        await deposit('x1', prefix: 'deposit_usdt_'),
        OnchainCommitResult.alreadyProcessed,
      );
      expect((await tx('deposit_usdt_x1')).exists, isFalse);
      expect((await user())['tyxBalance'], 150.0);
    });

    test('a deposit signature cannot also activate a subscription', () async {
      expect(await deposit('x2'), OnchainCommitResult.credited);
      expect(await subscribe('x2'), OnchainCommitResult.alreadyProcessed);
      expect((await user())['isPremium'], isFalse);
      expect((await tx('sub_sol_x2')).exists, isFalse);
    });

    test('a subscription signature cannot also credit a deposit', () async {
      expect(await subscribe('x3'), OnchainCommitResult.credited);
      expect(await deposit('x3'), OnchainCommitResult.alreadyProcessed);
      expect((await user())['tyxBalance'], 100.0);
      expect((await tx('deposit_sol_x3')).exists, isFalse);
    });

    test(
      'an onchain marker of the same account counts as already processed',
      () async {
        await db.collection('transactions').doc(onchainMarkerId('x4')).set({
          'uid': 'u1',
        });
        expect(await deposit('x4'), OnchainCommitResult.alreadyProcessed);
        expect((await user())['tyxBalance'], 100.0);
      },
    );

    test(
      'an older per-flow marker (before this change) still blocks a replay',
      () async {
        await db.collection('transactions').doc('deposit_sol_x5').set({
          'uid': 'u1',
        });
        expect(await deposit('x5'), OnchainCommitResult.alreadyProcessed);
        expect((await user())['tyxBalance'], 100.0);
        expect((await tx('onchain_x5')).exists, isFalse);
      },
    );
  });

  group('activateSubscriptionOnce', () {
    test(
      'monthly activation matches the existing Solana subscription fields',
      () async {
        expect(await subscribe('sig1'), OnchainCommitResult.credited);
        final u = await user();
        expect(u['isPremium'], isTrue);
        expect(u['accountType'], 'hybrid');
        expect(
          u['premiumUntil'],
          now.add(const Duration(days: 30)).millisecondsSinceEpoch,
        );
        final rec = (await tx('sub_sol_sig1')).data()!;
        expect(rec['type'], 'subscription');
        expect(rec['title'], 'Hybrid PRO Subscription (Monthly)');
        expect(rec['solanaTxSignature'], 'sig1');
        expect(rec['amount'], 199);
        expect(rec['uid'], 'u1');
        expect((await tx('onchain_sig1')).exists, isTrue);
      },
    );

    test('yearly plan runs 365 days', () async {
      await subscribe('sig2', plan: 'yearly');
      expect(
        (await user())['premiumUntil'],
        now.add(const Duration(days: 365)).millisecondsSinceEpoch,
      );
      expect(
        (await tx('sub_sol_sig2')).data()!['title'],
        'Hybrid PRO Subscription (Yearly)',
      );
    });

    test('method name is recorded (Trust Wallet flow)', () async {
      await activateSubscriptionOnce(
        firestore: db,
        uid: 'u1',
        signature: 'sigT',
        plan: 'monthly',
        phpAmount: 199,
        cryptoAmount: 0.0245,
        method: 'Trust Wallet',
        now: now,
      );
      final rec = (await tx('sub_sol_sigT')).data()!;
      expect(rec['method'], 'Trust Wallet');
      expect(rec['desc'], contains('Trust Wallet'));
    });

    test('the same signature never activates or records twice', () async {
      expect(await subscribe('sig3'), OnchainCommitResult.credited);
      expect(
        await subscribe('sig3', plan: 'yearly', at: now.add(day * 20)),
        OnchainCommitResult.alreadyProcessed,
      );
      expect(
        (await user())['premiumUntil'],
        now.add(const Duration(days: 30)).millisecondsSinceEpoch,
      );
    });

    test(
      'paying while still subscribed extends from the current expiry',
      () async {
        final until = now.add(day * 10).millisecondsSinceEpoch;
        await db.collection('users').doc('u1').update({
          'isPremium': true,
          'premiumUntil': until,
        });
        await subscribe('sig4');
        expect(
          (await user())['premiumUntil'],
          until + const Duration(days: 30).inMilliseconds,
        );
      },
    );

    test(
      'an expired subscription restarts from now, not from the old expiry',
      () async {
        await db.collection('users').doc('u1').update({
          'isPremium': true,
          'premiumUntil': now.subtract(day * 40).millisecondsSinceEpoch,
        });
        await subscribe('sig5');
        expect(
          (await user())['premiumUntil'],
          now.add(const Duration(days: 30)).millisecondsSinceEpoch,
        );
      },
    );
  });

  test('the shared marker has exactly the keys the rules allow', () async {
    await deposit('k1');
    expect((await tx(onchainMarkerId('k1'))).data()!.keys.toSet(), {
      'uid',
      'type',
      'solanaTxSignature',
      'markerId',
      'markedAt',
    });
    expect((await tx(onchainMarkerId('k1'))).data()!['type'], 'onchain_marker');
  });

  group('a marker held by another account', () {
    Future<void> seedForeign(String id, {String uid = 'u2'}) => db
        .collection('transactions')
        .doc(id)
        .set({'uid': uid, 'type': 'onchain_marker'});

    test('a foreign onchain marker does not fail the credit and is not "already processed"', () async {
      await seedForeign(onchainMarkerId('f1'));
      final r = await deposit('f1');
      expect(r, OnchainCommitResult.heldByAnotherAccount);
      expect((await user())['tyxBalance'], 100.0);
      expect((await tx('deposit_sol_f1')).exists, isFalse);
    });

    test('a foreign per-flow marker is treated the same way and noted on the pending record', () async {
      await seedForeign('deposit_sol_f2');
      expect(await deposit('f2'), OnchainCommitResult.heldByAnotherAccount);
      expect((await user())['tyxBalance'], 100.0);
      expect((await tx(onchainMarkerId('f2'))).exists, isFalse);
      expect(
        (await tx(pendingOnchainId('u1', 'f2'))).data()!['note'],
        kMarkerHeldNote,
      );
    });

    test('both markers foreign: held, nothing written for the caller except the pending note', () async {
      await seedForeign(onchainMarkerId('f2b'));
      await seedForeign('deposit_sol_f2b');
      expect(await deposit('f2b'), OnchainCommitResult.heldByAnotherAccount);
      expect((await user())['tyxBalance'], 100.0);
      expect(
        (await tx(pendingOnchainId('u1', 'f2b'))).data()!['status'],
        'pending',
      );
    });

    test(
      'a foreign marker blocks a subscription and leaves premium untouched',
      () async {
        await seedForeign(onchainMarkerId('f3'));
        expect(await subscribe('f3'), OnchainCommitResult.heldByAnotherAccount);
        expect((await user())['isPremium'], isFalse);
        expect(
          (await tx(pendingOnchainId('u1', 'f3'))).data()!['kind'],
          'subscription',
        );
      },
    );

    test('the caller\'s existing pending record stays open with a note, not silently refused', () async {
      await writePendingOnchain(
        firestore: db,
        uid: 'u1',
        signature: 'f4',
        kind: 'deposit',
        phpAmount: 50,
        cryptoAmount: 0.006,
        currency: 'SOL',
      );
      await seedForeign(onchainMarkerId('f4'));
      expect(await deposit('f4'), OnchainCommitResult.heldByAnotherAccount);
      final rec = (await tx(pendingOnchainId('u1', 'f4'))).data()!;
      expect(rec['status'], 'pending');
      expect(rec['note'], kMarkerHeldNote);
      expect(rec['uid'], 'u1');
    });

    test(
      'without an earlier pending record one is created with the note',
      () async {
        await seedForeign(onchainMarkerId('f5'));
        await deposit('f5');
        final rec = (await tx(pendingOnchainId('u1', 'f5'))).data()!;
        expect(rec['status'], 'pending');
        expect(rec['note'], kMarkerHeldNote);
        expect(rec['solanaTxSignature'], 'f5');
        expect(rec.containsKey('createdAt'), isFalse);
      },
    );

    test('the other account\'s records are never modified', () async {
      await seedForeign(onchainMarkerId('f6'));
      await deposit('f6');
      expect((await tx(onchainMarkerId('f6'))).data(), {
        'uid': 'u2',
        'type': 'onchain_marker',
      });
      expect((await tx(pendingOnchainId('u2', 'f6'))).exists, isFalse);
    });

    test(
      'the UI helper turns it into a "Contact support with signature" error',
      () async {
        await seedForeign(onchainMarkerId('f7'));
        final r = await deposit('f7');
        expect(
          () => r.throwIfHeldElsewhere('f7'),
          throwsA(
            isA<OnchainSupportException>().having(
              (e) => e.toString(),
              'message',
              contains('Contact support with signature f7'),
            ),
          ),
        );
        // Other outcomes do not throw.
        OnchainCommitResult.credited.throwIfHeldElsewhere('x');
        OnchainCommitResult.alreadyProcessed.throwIfHeldElsewhere('x');
      },
    );

    test(
      'each account gets its own pending record for the same signature',
      () async {
        expect(pendingOnchainId('u1', 's'), isNot(pendingOnchainId('u2', 's')));
        expect(pendingOnchainId('u1', 's'), 'pending_onchain_u1_s');
      },
    );
  });

  group('pending on-chain record', () {
    Future<void> pending(String sig) => writePendingOnchain(
      firestore: db,
      uid: 'u1',
      signature: sig,
      kind: 'deposit',
      phpAmount: 50,
      cryptoAmount: 0.006,
      currency: 'SOL',
    );

    test(
      'is written before the credit and hidden from history (no createdAt)',
      () async {
        await pending('p1');
        final rec = (await tx(pendingOnchainId('u1', 'p1'))).data()!;
        expect(rec['status'], 'pending');
        expect(rec['uid'], 'u1');
        expect(rec['solanaTxSignature'], 'p1');
        expect(rec['kind'], 'deposit');
        expect(rec.containsKey('createdAt'), isFalse);
      },
    );

    test('does not overwrite an existing record', () async {
      await pending('p2');
      await notePendingOnchain(
        firestore: db,
        uid: 'u1',
        signature: 'p2',
        note: 'first',
      );
      await pending('p2');
      expect((await tx(pendingOnchainId('u1', 'p2'))).data()!['note'], 'first');
    });

    test('is marked done in the same transaction as the credit', () async {
      await pending('p3');
      expect(await deposit('p3'), OnchainCommitResult.credited);
      final rec = (await tx(pendingOnchainId('u1', 'p3'))).data()!;
      expect(rec['status'], 'done');
      expect(rec['completedAt'], isA<int>());
    });

    test('is marked done by a subscription credit too', () async {
      await pending('p4');
      expect(await subscribe('p4'), OnchainCommitResult.credited);
      expect(
        (await tx(pendingOnchainId('u1', 'p4'))).data()!['status'],
        'done',
      );
    });

    test('stays pending with a note when finalization never arrives', () async {
      await pending('p5');
      await notePendingOnchain(
        firestore: db,
        uid: 'u1',
        signature: 'p5',
        note: 'not finalized in time',
      );
      final rec = (await tx(pendingOnchainId('u1', 'p5'))).data()!;
      expect(rec['status'], 'pending');
      expect(rec['note'], 'not finalized in time');
      expect((await user())['tyxBalance'], 100.0);
    });

    test('a note never reopens a record that is already done', () async {
      await pending('p6');
      await deposit('p6');
      await notePendingOnchain(
        firestore: db,
        uid: 'u1',
        signature: 'p6',
        note: 'late',
      );
      final rec = (await tx(pendingOnchainId('u1', 'p6'))).data()!;
      expect(rec['status'], 'done');
      expect(rec.containsKey('note'), isFalse);
    });

    test('credit works when no pending record exists', () async {
      expect(await deposit('p7'), OnchainCommitResult.credited);
      expect((await tx(pendingOnchainId('u1', 'p7'))).exists, isFalse);
    });
  });

  group('rules refusal is not a foreign marker', () {
    late _DenyingFirestore denying;
    setUp(() => denying = _DenyingFirestore(db));

    Future<OnchainCommitResult> depositVia(FirebaseFirestore f, String sig) =>
        creditOnchainDeposit(
          firestore: f,
          uid: 'u1',
          signature: sig,
          markerId: 'deposit_sol_$sig',
          phpAmount: 50,
          markerData: {
            'uid': 'u1',
            'type': 'deposit',
            'amount': 50,
            'solanaTxSignature': sig,
          },
        );

    test('permission-denied on the user update returns refusedByRules, not heldByAnotherAccount', () async {
      denying.denyUpdatesOn('users/');
      final r = await depositVia(denying, 'r1');
      expect(r, OnchainCommitResult.refusedByRules);
      expect(r, isNot(OnchainCommitResult.heldByAnotherAccount));
      expect((await user())['tyxBalance'], 100.0);
      expect((await tx(onchainMarkerId('r1'))).exists, isFalse);
      expect((await tx('deposit_sol_r1')).exists, isFalse);
    });

    test('leaves the pending record open with the rules-refusal note (existing record)', () async {
      await writePendingOnchain(
        firestore: db,
        uid: 'u1',
        signature: 'r2',
        kind: 'deposit',
        phpAmount: 50,
        cryptoAmount: 0.006,
        currency: 'SOL',
      );
      denying.denyUpdatesOn('users/');
      await depositVia(denying, 'r2');
      final rec = (await tx(pendingOnchainId('u1', 'r2'))).data()!;
      expect(rec['status'], 'pending');
      expect(rec['note'], 'credit refused by rules (permission-denied)');
      expect(rec['note'], kRefusedByRulesNote);
      expect(rec['note'], isNot(kMarkerHeldNote));
    });

    test('creates a pending record with the note when none existed', () async {
      denying.denyUpdatesOn('users/');
      await depositVia(denying, 'r3');
      final rec = (await tx(pendingOnchainId('u1', 'r3'))).data()!;
      expect(rec['status'], 'pending');
      expect(rec['note'], kRefusedByRulesNote);
    });

    test('a subscription refusal records kind subscription', () async {
      denying.denyUpdatesOn('users/');
      final r = await activateSubscriptionOnce(
        firestore: denying,
        uid: 'u1',
        signature: 'r4',
        plan: 'monthly',
        phpAmount: 199,
        cryptoAmount: 0.0245,
        now: now,
      );
      expect(r, OnchainCommitResult.refusedByRules);
      expect((await user())['isPremium'], isFalse);
      expect(
        (await tx(pendingOnchainId('u1', 'r4'))).data()!['kind'],
        'subscription',
      );
    });

    test(
      'the UI helper asks the user to contact support for a refusal too',
      () async {
        expect(OnchainCommitResult.refusedByRules.needsSupport, isTrue);
        expect(
          () => OnchainCommitResult.refusedByRules.throwIfHeldElsewhere('r5'),
          throwsA(
            isA<OnchainSupportException>().having(
              (e) => e.toString(),
              'message',
              contains('Contact support with signature r5'),
            ),
          ),
        );
      },
    );

    test('a foreign marker that WAS read still reports heldByAnotherAccount (not refused)', () async {
      await db.collection('transactions').doc(onchainMarkerId('r6')).set({
        'uid': 'u2',
        'type': 'onchain_marker',
      });
      denying.denyUpdatesOn(
        'users/',
      ); // never reached: the foreign marker ends the transaction first
      expect(
        await depositVia(denying, 'r6'),
        OnchainCommitResult.heldByAnotherAccount,
      );
    });

    test('other failures are not swallowed', () async {
      denying.failWith('unavailable');
      expect(
        () => depositVia(denying, 'r7'),
        throwsA(isA<FirebaseException>()),
      );
    });

    test('works normally through the wrapper when nothing is denied', () async {
      expect(await depositVia(denying, 'r8'), OnchainCommitResult.credited);
    });
  });
}

/// A Firestore whose transactions behave like the fake, except that updates
/// under a denied path prefix throw `permission-denied` (as the rules would).
class _DenyingFirestore implements FirebaseFirestore {
  _DenyingFirestore(this.inner);
  final FakeFirebaseFirestore inner;
  final _denied = <String>[];
  String? _failCode;

  void denyUpdatesOn(String pathPrefix) => _denied.add(pathPrefix);
  void failWith(String code) => _failCode = code;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      inner.collection(path);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    return inner.runTransaction<T>(
      (tx) {
        return transactionHandler(_DenyingTransaction(tx, _denied, _failCode));
      },
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _DenyingTransaction implements Transaction {
  _DenyingTransaction(this.inner, this.denied, this.failCode);
  final Transaction inner;
  final List<String> denied;
  final String? failCode;

  void _check(DocumentReference ref) {
    if (failCode != null)
      throw FirebaseException(plugin: 'cloud_firestore', code: failCode);
    if (denied.any((p) => ref.path.startsWith(p))) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
  }

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) => inner.get(documentReference);

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    inner.set(documentReference, data, options);
    return this;
  }

  @override
  Transaction update(
    DocumentReference documentReference,
    Map<Object, Object?> data,
  ) {
    _check(documentReference);
    inner.update(documentReference, data);
    return this;
  }

  @override
  Transaction delete(DocumentReference documentReference) {
    inner.delete(documentReference);
    return this;
  }
}
