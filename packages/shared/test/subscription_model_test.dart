import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('UserProfile Subscription & Tier Tests', () {
    test('tierLabel correctly distinguishes Lite vs Pro for Nyxian, Employer, and Hybrid', () {
      final nyxianLite = UserProfile(
        uid: 'u1',
        name: 'John Nyxian',
        email: 'john@example.com',
        accountType: AccountType.nyxian,
        isPremium: false,
      );
      expect(nyxianLite.tierLabel, 'Nyxian — Lite');

      final nyxianPro = UserProfile(
        uid: 'u2',
        name: 'Jane Nyxian',
        email: 'jane@example.com',
        accountType: AccountType.nyxian,
        isPremium: true,
      );
      expect(nyxianPro.tierLabel, 'Nyxian — Pro');

      final employerLite = UserProfile(
        uid: 'u3',
        name: 'Boss Employer',
        email: 'boss@example.com',
        accountType: AccountType.employer,
        isPremium: false,
      );
      expect(employerLite.tierLabel, 'Employer — Lite');

      final employerPro = UserProfile(
        uid: 'u4',
        name: 'Boss Employer Pro',
        email: 'bosspro@example.com',
        accountType: AccountType.employer,
        isPremium: true,
      );
      expect(employerPro.tierLabel, 'Employer — Pro');

      final hybridUser = UserProfile(
        uid: 'u5',
        name: 'Hybrid User',
        email: 'hybrid@example.com',
        accountType: AccountType.hybrid,
        isPremium: false,
      );
      expect(hybridUser.tierLabel, 'Hybrid — Pro');
    });

    test('UserProfile.fromMap correctly parses all subscription fields and pendingSubscription', () {
      final now = DateTime.now();
      final map = {
        'name': 'Test User',
        'email': 'test@example.com',
        'accountType': 'hybrid',
        'isPremium': true,
        'premiumUntil': now.add(const Duration(days: 30)).millisecondsSinceEpoch,
        'tyxBalance': 500.0,
        'subscriptionPlan': 'monthly',
        'subscriptionStartedAt': now.millisecondsSinceEpoch,
        'subscriptionPaymentMethod': 'Tyxbit Balance',
        'subscriptionPaymentAmount': 299.0,
        'subscriptionTxId': 'sub_tyx_12345',
        'subscriptionStatus': 'active',
        'pendingSubscription': {
          'plan': 'yearly',
          'amount': 2999.0,
          'method': 'Cash (P2P)',
          'referenceNumber': 'P2P-999',
          'status': 'PENDING_VERIFICATION',
        },
        'earnedRewards': ['badge_1', 'badge_2'],
      };

      final profile = UserProfile.fromMap('uid_123', map);

      expect(profile.uid, 'uid_123');
      expect(profile.accountType, AccountType.hybrid);
      expect(profile.isPremium, true);
      expect(profile.subscriptionPlan, 'monthly');
      expect(profile.subscriptionPaymentMethod, 'Tyxbit Balance');
      expect(profile.subscriptionPaymentAmount, 299.0);
      expect(profile.subscriptionTxId, 'sub_tyx_12345');
      expect(profile.subscriptionStatus, 'active');
      expect(profile.subscriptionStartedAt, isNotNull);
      expect(profile.pendingSubscription, isNotNull);
      expect(profile.pendingSubscription!['referenceNumber'], 'P2P-999');
      expect(profile.earnedRewards, ['badge_1', 'badge_2']);
      expect(profile.tierLabel, 'Hybrid — Pro');
    });

    test('UserProfile.toMap and copyWith roundtrip correctly preserve subscription fields', () {
      final now = DateTime.now();
      final original = UserProfile(
        uid: 'uid_test',
        name: 'Original User',
        email: 'orig@test.com',
        accountType: AccountType.nyxian,
        tyxBalance: 1000.0,
        isPremium: false,
      );

      final upgraded = original.copyWith(
        accountType: AccountType.hybrid,
        isPremium: true,
        subscriptionPlan: 'yearly',
        subscriptionPaymentMethod: 'Solana (SOL)',
        subscriptionPaymentAmount: 2999.0,
        subscriptionTxId: 'sol_sig_abcdef',
        subscriptionStartedAt: now,
        subscriptionStatus: 'active',
      );

      expect(upgraded.tierLabel, 'Hybrid — Pro');
      expect(upgraded.subscriptionPlan, 'yearly');
      expect(upgraded.subscriptionPaymentMethod, 'Solana (SOL)');
      expect(upgraded.subscriptionPaymentAmount, 2999.0);
      expect(upgraded.subscriptionTxId, 'sol_sig_abcdef');
      expect(upgraded.subscriptionStatus, 'active');

      final map = upgraded.toMap();
      expect(map['subscriptionPlan'], 'yearly');
      expect(map['subscriptionPaymentMethod'], 'Solana (SOL)');
      expect(map['subscriptionPaymentAmount'], 2999.0);
      expect(map['subscriptionTxId'], 'sol_sig_abcdef');
      expect(map['subscriptionStatus'], 'active');
      expect(map['subscriptionStartedAt'], now.millisecondsSinceEpoch);

      final deserialized = UserProfile.fromMap(upgraded.uid, map);
      expect(deserialized.subscriptionPlan, 'yearly');
      expect(deserialized.subscriptionPaymentMethod, 'Solana (SOL)');
      expect(deserialized.subscriptionPaymentAmount, 2999.0);
      expect(deserialized.subscriptionTxId, 'sol_sig_abcdef');
      expect(deserialized.subscriptionStatus, 'active');
    });
  });
}
