import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tranyx_mobile/core/services/mwa_subscription.dart';

void main() {
  late FakeFirebaseFirestore db;
  final now = DateTime.utc(2026, 10, 29, 12);

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({'isPremium': false, 'accountType': 'nyxian'});
  });

  Future<bool> subscribe(String sig, {String plan = 'monthly'}) => activateSubscriptionOnce(
    firestore: db,
    uid: 'u1',
    signature: sig,
    plan: plan,
    phpAmount: 199,
    cryptoAmount: 0.0245,
    now: now,
  );

  test('monthly activation matches the existing Solana subscription fields', () async {
    expect(await subscribe('sig1'), isTrue);
    final user = (await db.collection('users').doc('u1').get()).data()!;
    expect(user['isPremium'], isTrue);
    expect(user['accountType'], 'hybrid');
    expect(user['premiumUntil'], now.add(const Duration(days: 30)).millisecondsSinceEpoch);
    final rec = (await db.collection('transactions').doc('sub_sol_sig1').get()).data()!;
    expect(rec['type'], 'subscription');
    expect(rec['title'], 'Hybrid PRO Subscription (Monthly)');
    expect(rec['solanaTxSignature'], 'sig1');
    expect(rec['amount'], 199);
    expect(rec['uid'], 'u1');
  });

  test('yearly plan runs 365 days', () async {
    await subscribe('sig2', plan: 'yearly');
    final user = (await db.collection('users').doc('u1').get()).data()!;
    expect(user['premiumUntil'], now.add(const Duration(days: 365)).millisecondsSinceEpoch);
    final rec = (await db.collection('transactions').doc('sub_sol_sig2').get()).data()!;
    expect(rec['title'], 'Hybrid PRO Subscription (Yearly)');
  });

  test('the same signature never activates or records twice', () async {
    expect(await subscribe('sig3'), isTrue);
    // A replay later must not extend premiumUntil or rewrite the record.
    final replay = await activateSubscriptionOnce(
      firestore: db,
      uid: 'u1',
      signature: 'sig3',
      plan: 'yearly',
      phpAmount: 199,
      cryptoAmount: 0.0245,
      now: now.add(const Duration(days: 20)),
    );
    expect(replay, isFalse);
    final user = (await db.collection('users').doc('u1').get()).data()!;
    expect(user['premiumUntil'], now.add(const Duration(days: 30)).millisecondsSinceEpoch);
  });
}
