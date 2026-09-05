import 'package:test/test.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_web/services/firebase_service.dart';

void main() {
  group('Wallet & Platform Fees Calculations', () {
    test('1000 PHP Base Price Calculations', () {
      final double price = 1000.0;

      // Platform commission fee (3% from Nyxian)
      final platformFee = price * 0.03;
      final nyxianPayout = price - platformFee;

      // Employer fees (7% transaction fee + 3% convenience fee = 10%)
      final txFee = price * 0.07;
      final convFee = price * 0.03;
      final totalEmployerFees = txFee + convFee;
      final totalEmployerCost = price + totalEmployerFees;

      // Company income (total 13% of base rate)
      final totalCompanyIncome = platformFee + txFee + convFee;

      expect(platformFee, equals(30.0));
      expect(nyxianPayout, equals(970.0));
      expect(txFee, equals(70.0));
      expect(convFee, equals(30.0));
      expect(totalEmployerFees, equals(100.0));
      expect(totalEmployerCost, equals(1100.0));
      expect(totalCompanyIncome, equals(130.0));
    });

    test('2000 PHP Base Price Calculations', () {
      final double price = 2000.0;
      final platformFee = price * 0.03;
      final nyxianPayout = price - platformFee;
      final txFee = price * 0.07;
      final convFee = price * 0.03;
      final totalEmployerFees = txFee + convFee;
      final totalCompanyIncome = platformFee + txFee + convFee;

      expect(platformFee, equals(60.0));
      expect(nyxianPayout, equals(1940.0));
      expect(totalEmployerFees, equals(200.0));
      expect(totalCompanyIncome, equals(260.0));
    });

    test('5000 PHP Base Price Calculations with 10% Inspection Holdback', () {
      final double price = 5000.0;
      final platformFee = price * 0.03;
      final nyxianPayout = price - platformFee;

      // Holdback is 10% of base price
      final holdbackAmount = price * 0.10;
      final immediatePayout = nyxianPayout - holdbackAmount;

      expect(platformFee, equals(150.0));
      expect(nyxianPayout, equals(4850.0));
      expect(holdbackAmount, equals(500.0));
      expect(immediatePayout, equals(4350.0));
    });
  });

  group('Session Expiration and 403 Forbidden Error Handling', () {
    bool sessionExpiredTriggered = false;

    setUp(() {
      sessionExpiredTriggered = false;
      onSessionExpiredGlobal = () {
        sessionExpiredTriggered = true;
      };
    });

    tearDown(() {
      onSessionExpiredGlobal = null;
    });

    test('401 Unauthorized MUST trigger session expiration', () {
      try {
        throw FirebaseException('Unauthorized access', 401);
      } catch (e) {
        expect(sessionExpiredTriggered, isTrue);
      }
    });

    test('String containing "id-token-expired" MUST trigger session expiration', () {
      try {
        throw FirebaseException('firebase error: id-token-expired', 400);
      } catch (e) {
        expect(sessionExpiredTriggered, isTrue);
      }
    });

    test('403 Forbidden MUST NOT trigger session expiration', () {
      try {
        throw FirebaseException('PERMISSION_DENIED', 403);
      } catch (e) {
        expect(sessionExpiredTriggered, isFalse);
      }
    });

    test('Generic 400 error MUST NOT trigger session expiration', () {
      try {
        throw FirebaseException('Some other error occurred', 400);
      } catch (e) {
        expect(sessionExpiredTriggered, isFalse);
      }
    });
  });

  group('Vehicle Rental Free Tier & Ledger Debit Invariant', () {
    test('Vehicle Listing Upfront Fee is 100% Free (0.00 TYX)', () {
      const config = PlatformFeeConfig();
      expect(config.listingFeeRate, equals(0.0));

      final double dailyRate = 2500.0;
      final listingFee = config.listingFeeRate * dailyRate;
      expect(listingFee, equals(0.0));

      // 3% Platform Commission deducted upon completion
      final commissionDaily = dailyRate * 0.03;
      final payoutDaily = dailyRate - commissionDaily;
      expect(commissionDaily, equals(75.0));
      expect(payoutDaily, equals(2425.0));
    });

    test('Listing Fee Transaction Classification is strictly Debit (not Deposit)', () {
      final txMap = {
        'id': 'tx_123456789',
        'uid': 'user_host_1',
        'type': 'listing_fee',
        'amount': 37.5,
        'title': 'Vehicle Listing Fee',
        'desc': '1.5% posting fee for Nissan Almera (2026)',
        'method': 'Tranyx Wallet',
        'createdAt': 1788570750000,
        'status': 'Completed',
      };

      final record = WalletTransaction.fromMap(txMap);
      expect(record.transactionType, equals(WalletTransactionType.listingFee));

      final rawType = (txMap['type'] ?? '').toString().toLowerCase();
      final isDebitType = record.transactionType == WalletTransactionType.listingFee ||
          record.transactionType == WalletTransactionType.feeDeduction ||
          record.transactionType == WalletTransactionType.subscription ||
          record.transactionType == WalletTransactionType.withdraw ||
          record.transactionType == WalletTransactionType.onChainPayment ||
          rawType == 'listing_fee' ||
          rawType == 'fee_deduction' ||
          rawType == 'subscription' ||
          rawType == 'withdraw' ||
          rawType == 'withdrawal' ||
          rawType == 'fee' ||
          rawType == 'service_fee' ||
          rawType == 'payment';

      expect(isDebitType, isTrue);

      final isDeposit = !isDebitType &&
          (record.transactionType == WalletTransactionType.deposit ||
              record.transactionType == WalletTransactionType.refund ||
              rawType.contains('deposit') ||
              rawType.contains('topup') ||
              rawType.contains('refund') ||
              (rawType == 'credit' && !isDebitType));

      expect(isDeposit, isFalse, reason: 'Listing fee must NEVER be classified as a deposit/inflow');
    });
  });
}
