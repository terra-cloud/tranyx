import 'package:test/test.dart';
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
}
