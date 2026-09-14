import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('WalletSecurityHelper & Financial Control Tests', () {
    test('₱100 balance -> ₱100 transaction allowed, resulting in ₱0.00', () {
      const current = 100.0;
      const deduction = 100.0;

      // Validate sufficient funds
      expect(
        () => WalletSecurityHelper.validateSufficientFunds(
          availableBalance: current,
          totalCost: deduction,
          transactionTitle: 'Job Payment',
        ),
        returnsNormally,
      );

      final newBal = WalletSecurityHelper.calculateSafeNewBalance(
        currentBalance: current,
        amountToDeduct: deduction,
      );
      expect(newBal, equals(0.0));
    });

    test('₱100 balance -> ₱101 transaction rejected with InsufficientFundsException', () {
      const current = 100.0;
      const deduction = 101.0;

      expect(
        () => WalletSecurityHelper.validateSufficientFunds(
          availableBalance: current,
          totalCost: deduction,
        ),
        throwsA(isA<InsufficientFundsException>().having(
          (e) => e.shortfall,
          'shortfall',
          equals(1.0),
        )),
      );

      expect(
        () => WalletSecurityHelper.calculateSafeNewBalance(
          currentBalance: current,
          amountToDeduct: deduction,
        ),
        throwsA(isA<NegativeBalanceException>()),
      );
    });

    test('₱100 balance -> ₱90 + ₱20 fees (total ₱110) rejected', () {
      const current = 100.0;
      const base = 90.0;
      const fees = 20.0;
      const totalCost = base + fees;

      expect(
        () => WalletSecurityHelper.validateSufficientFunds(
          availableBalance: current,
          totalCost: totalCost,
        ),
        throwsA(isA<InsufficientFundsException>().having(
          (e) => e.shortfall,
          'shortfall',
          equals(10.0),
        )),
      );
    });

    test('Job total cost calculation includes budget and 10% employer completion fees', () {
      // ₱1,000 job with 7% transaction fee and 3% convenience fee
      final total = WalletSecurityHelper.calculateJobTotalEmployerCost(
        price: 1000.0,
        discount: 0.0,
        txFeeRate: 0.07,
        convFeeRate: 0.03,
      );
      expect(total, equals(1100.0));

      final fees = WalletSecurityHelper.calculateJobEmployerFees(
        price: 1000.0,
        discount: 0.0,
        txFeeRate: 0.07,
        convFeeRate: 0.03,
      );
      expect(fees, equals(100.0));

      // With promo discount (₱100 discount -> ₱900 budget -> ₱90 fees -> total ₱990)
      final discountedTotal = WalletSecurityHelper.calculateJobTotalEmployerCost(
        price: 1000.0,
        discount: 100.0,
        txFeeRate: 0.07,
        convFeeRate: 0.03,
      );
      expect(discountedTotal, equals(990.0));
    });

    test('Available Balance distinction: ₱1,000 balance with ₱700 reserved has ₱300 available', () {
      const profile = UserProfile(
        uid: 'user_123',
        name: 'Test User',
        email: 'test@example.com',
        accountType: AccountType.employer,
        tyxBalance: 1000.0,
        reservedBalance: 700.0,
      );

      expect(profile.availableBalance, equals(300.0));
      expect(profile.hasNegativeBalance, isFalse);

      // Attempting ₱500 payment against ₱300 available balance must be rejected
      expect(
        () => WalletSecurityHelper.validateSufficientFunds(
          availableBalance: profile.availableBalance,
          totalCost: 500.0,
        ),
        throwsA(isA<InsufficientFundsException>().having(
          (e) => e.shortfall,
          'shortfall',
          equals(200.0),
        )),
      );
    });

    test('Negative balance detection flags account correctly', () {
      const negativeProfile = UserProfile(
        uid: 'user_neg',
        name: 'Negative Balance User',
        email: 'neg@example.com',
        accountType: AccountType.employer,
        tyxBalance: -100.0,
      );

      expect(negativeProfile.hasNegativeBalance, isTrue);
      expect(negativeProfile.availableBalance, equals(0.0)); // Clamped to zero
    });
  });
}
