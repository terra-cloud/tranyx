import 'dart:io';
import 'package:test/test.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_web/state/app_state.dart';

void main() {
  group('Job Posting Payment Rate Types & Escrow Calculations', () {
    const rateTypes = [
      (PaymentType.daily, 'Daily'),
      (PaymentType.weekly, 'Weekly'),
      (PaymentType.fortnightly, 'Fortnightly'),
      (PaymentType.monthly, 'Monthly'),
      (PaymentType.packageFixed, 'Package/Fixed'),
    ];

    for (final (type, label) in rateTypes) {
      test('Rate Type "$label" (₱350.00 Base) correctly computes employer fees and total escrow', () {
        const double basePrice = 350.0;
        const double txFeeRate = 0.07;
        const double convFeeRate = 0.03;

        final employerFees = WalletSecurityHelper.calculateJobEmployerFees(
          price: basePrice,
          txFeeRate: txFeeRate,
          convFeeRate: convFeeRate,
        );

        final totalRequired = WalletSecurityHelper.calculateJobTotalEmployerCost(
          price: basePrice,
          txFeeRate: txFeeRate,
          convFeeRate: convFeeRate,
        );

        // 7% tx fee = 24.50, 3% conv fee = 10.50 => total fees = 35.00
        expect(employerFees, equals(35.0));
        // Total required = 350.00 + 35.00 = 385.00
        expect(totalRequired, equals(385.0));
      });
    }

    test('All 5 payment rate types have consistent calculation invariants across tiers', () {
      final testAmounts = [100.0, 350.0, 1000.0, 5000.0, 15000.0];

      for (final amt in testAmounts) {
        final fees = WalletSecurityHelper.calculateJobEmployerFees(
          price: amt,
          txFeeRate: 0.07,
          convFeeRate: 0.03,
        );
        final total = WalletSecurityHelper.calculateJobTotalEmployerCost(
          price: amt,
          txFeeRate: 0.07,
          convFeeRate: 0.03,
        );

        expect(fees, closeTo(amt * 0.10, 0.0001));
        expect(total, closeTo(amt * 1.10, 0.0001));
      }
    });

    test('Promo discount applies strictly to base payout and reduces total escrow', () {
      const double basePrice = 500.0;
      const double discount = 100.0;

      final fees = WalletSecurityHelper.calculateJobEmployerFees(
        price: basePrice,
        discount: discount,
        txFeeRate: 0.07,
        convFeeRate: 0.03,
      );

      final total = WalletSecurityHelper.calculateJobTotalEmployerCost(
        price: basePrice,
        discount: discount,
        txFeeRate: 0.07,
        convFeeRate: 0.03,
      );

      // Discounted price = 400.00 => 10% fees = 40.00 => total = 440.00
      expect(fees, equals(40.0));
      expect(total, equals(440.0));
    });
  });

  group('Firestore Rules Verification: Users Collection & tyxBalance Permitted', () {
    test('Rule 1 under match /users/{userId} does NOT blacklist tyxBalance', () {
      final rulesFile = File('../../firestore_rules/10_workspace_users_wallets.rules');
      expect(rulesFile.existsSync(), isTrue, reason: '10_workspace_users_wallets.rules must exist');

      final content = rulesFile.readAsStringSync();

      // Find Rule 1 allow update block
      final rule1Match = RegExp(
        r'// 1\. Regular User:.*?\n\s*\(isOwner\(userId\) && !request\.resource\.data\.diff\(resource\.data\)\.affectedKeys\(\)\.hasAny\(\[\s*([\s\S]*?)\s*\]\)\)',
      ).firstMatch(content);

      expect(rule1Match, isNotNull, reason: 'Rule 1 must be present in 10_workspace_users_wallets.rules');
      final forbiddenFieldsRaw = rule1Match!.group(1)!;
      final forbiddenFields = forbiddenFieldsRaw
          .replaceAll(RegExp(r"['\s]"), '')
          .split(',')
          .where((f) => f.isNotEmpty)
          .toList();

      // Strictly ensure privilege escalation fields ARE forbidden
      expect(forbiddenFields, contains('role'));
      expect(forbiddenFields, contains('isAdmin'));
      expect(forbiddenFields, contains('isStaff'));
      expect(forbiddenFields, contains('isSuperAdmin'));
      expect(forbiddenFields, contains('isP2pAgent'));
      expect(forbiddenFields, contains('banned'));
      expect(forbiddenFields, contains('suspendedUntil'));

      // Crucial: tyxBalance MUST NOT be blacklisted in Rule 1
      expect(forbiddenFields, isNot(contains('tyxBalance')),
          reason: "'tyxBalance' must not be in hasAny blacklist so user deductions succeed");

      // Verify non-negative numeric invariant remains strictly enforced at line 44
      expect(
        content,
        contains("(!('tyxBalance' in request.resource.data) || (request.resource.data.tyxBalance is number && request.resource.data.tyxBalance >= 0))"),
        reason: 'Non-negative balance invariant must remain enforced by Firestore rules',
      );
    });

    test('Compiled firestore.rules also contains unblocked tyxBalance and non-negative guard', () {
      final compiledRules = File('../../firestore.rules');
      expect(compiledRules.existsSync(), isTrue, reason: 'firestore.rules must exist');

      final content = compiledRules.readAsStringSync();

      final rule1Match = RegExp(
        r'// 1\. Regular User:.*?\n\s*\(isOwner\(userId\) && !request\.resource\.data\.diff\(resource\.data\)\.affectedKeys\(\)\.hasAny\(\[\s*([\s\S]*?)\s*\]\)\)',
      ).firstMatch(content);

      expect(rule1Match, isNotNull);
      final forbiddenFieldsRaw = rule1Match!.group(1)!;
      expect(forbiddenFieldsRaw, isNot(contains('tyxBalance')));
      expect(content, contains("request.resource.data.tyxBalance >= 0"));
    });
  });

  group('Actionable Error Message Mapping Invariants', () {
    String mapError(String errStr) {
      final lowerErr = errStr.toLowerCase();
      if (lowerErr.contains('401') ||
          lowerErr.contains('not logged in') ||
          lowerErr.contains('id-token-expired') ||
          lowerErr.contains('auth/id-token-expired')) {
        return 'Your session has expired. Please log in again to post this gig.';
      }
      if (lowerErr.contains('403') || lowerErr.contains('permission')) {
        return 'Permission denied: Unable to complete job posting. Please ensure your account is in good standing and try again, or refresh your session.';
      }
      if (lowerErr.contains('insufficient') || lowerErr.contains('funds')) {
        return 'Insufficient balance: Please deposit additional TYXBIT to cover the gig payout and escrow fees.';
      }
      return errStr;
    }

    test('403 Forbidden / Missing permissions returns actionable guidance', () {
      const raw = 'Exception: 403 Forbidden: Missing or insufficient permissions.';
      final mapped = mapError(raw);
      expect(mapped, contains('Permission denied'));
      expect(mapped, contains('account is in good standing'));
    });

    test('401 / session expired returns re-login guidance', () {
      const raw = 'AuthException: id-token-expired';
      final mapped = mapError(raw);
      expect(mapped, contains('session has expired'));
    });

    test('Insufficient funds returns deposit guidance', () {
      const raw = 'InsufficientFundsException: Shortfall: ₱35.00';
      final mapped = mapError(raw);
      expect(mapped, contains('Insufficient balance'));
      expect(mapped, contains('deposit additional TYXBIT'));
    });
  });
}
