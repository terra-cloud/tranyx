import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('JobCounterOfferValidator', () {
    const double originalOffer = 1000.0;

    test('calculateMin and calculateMax calculate 80% and 150% correctly', () {
      expect(JobCounterOfferValidator.calculateMin(originalOffer), equals(800.0));
      expect(JobCounterOfferValidator.calculateMax(originalOffer), equals(1500.0));

      // Fractional tests
      expect(JobCounterOfferValidator.calculateMin(100.05), equals(80.04));
      expect(JobCounterOfferValidator.calculateMax(100.05), equals(150.08));

      // Zero or negative
      expect(JobCounterOfferValidator.calculateMin(0.0), equals(0.0));
      expect(JobCounterOfferValidator.calculateMax(-100.0), equals(0.0));
    });

    test('formatAmount formats whole numbers and decimals correctly with commas and ₱', () {
      expect(JobCounterOfferValidator.formatAmount(1000), equals('₱1,000'));
      expect(JobCounterOfferValidator.formatAmount(800), equals('₱800'));
      expect(JobCounterOfferValidator.formatAmount(1500), equals('₱1,500'));
      expect(JobCounterOfferValidator.formatAmount(800.5), equals('₱800.50'));
      expect(JobCounterOfferValidator.formatAmount(1234567.89), equals('₱1,234,567.89'));
    });

    test('getRangeValidationMessage matches required spec message', () {
      final msg = JobCounterOfferValidator.getRangeValidationMessage(1000.0);
      expect(
        msg,
        equals("Your counter offer must be between ₱800 and ₱1,500 based on the employer's original offer of ₱1,000."),
      );
    });

    test('getPermittedRangeDisplay provides clear guidance text', () {
      final display = JobCounterOfferValidator.getPermittedRangeDisplay(1000.0);
      expect(
        display,
        equals("Allowed counter offer: ₱800 – ₱1,500 (80% – 150% of original offer ₱1,000)"),
      );
    });

    test('cleanAndParse sanitizes currency symbols, commas, and whitespace', () {
      expect(JobCounterOfferValidator.cleanAndParse('₱1,200'), equals(1200.0));
      expect(JobCounterOfferValidator.cleanAndParse(' 1,500.50 '), equals(1500.50));
      expect(JobCounterOfferValidator.cleanAndParse(800), equals(800.0));
      expect(JobCounterOfferValidator.cleanAndParse(800.25), equals(800.25));
      expect(JobCounterOfferValidator.cleanAndParse(''), isNull);
      expect(JobCounterOfferValidator.cleanAndParse('   '), isNull);
      expect(JobCounterOfferValidator.cleanAndParse('abc'), isNull);
      expect(JobCounterOfferValidator.cleanAndParse(double.nan), isNull);
      expect(JobCounterOfferValidator.cleanAndParse(double.infinity), isNull);
    });

    test('allows standard rate (isCounterOffer: false)', () {
      final res = JobCounterOfferValidator.validate(
        originalOffer: 1000.0,
        counterOfferInput: null,
        isCounterOffer: false,
      );
      expect(res.isValid, isTrue);
      expect(res.sanitizedRate, equals(1000.0));
    });

    test('allows valid counter offers in 80% to 150% range', () {
      // 80% boundary
      final res80 = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: '800',
        isCounterOffer: true,
      );
      expect(res80.isValid, isTrue);
      expect(res80.sanitizedRate, equals(800.0));

      // Middle (100%)
      final res100 = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: 1000.0,
        isCounterOffer: true,
      );
      expect(res100.isValid, isTrue);
      expect(res100.sanitizedRate, equals(1000.0));

      // 120%
      final res120 = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: '₱1,200',
        isCounterOffer: true,
      );
      expect(res120.isValid, isTrue);
      expect(res120.sanitizedRate, equals(1200.0));

      // 150% boundary
      final res150 = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: '1500',
        isCounterOffer: true,
      );
      expect(res150.isValid, isTrue);
      expect(res150.sanitizedRate, equals(1500.0));
    });

    test('prevents counter offers below 80% of original offer', () {
      final res = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: '799.99',
        isCounterOffer: true,
      );
      expect(res.isValid, isFalse);
      expect(
        res.errorMessage,
        equals("Your counter offer must be between ₱800 and ₱1,500 based on the employer's original offer of ₱1,000."),
      );
    });

    test('prevents counter offers above 150% of original offer', () {
      final res = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: '1500.01',
        isCounterOffer: true,
      );
      expect(res.isValid, isFalse);
      expect(
        res.errorMessage,
        equals("Your counter offer must be between ₱800 and ₱1,500 based on the employer's original offer of ₱1,000."),
      );
    });

    test('prevents ₱0 or negative amounts', () {
      final resZero = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: '0',
        isCounterOffer: true,
      );
      expect(resZero.isValid, isFalse);
      expect(resZero.errorMessage, equals('Counter offer cannot be ₱0 or negative.'));

      final resNegative = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: '-500',
        isCounterOffer: true,
      );
      expect(resNegative.isValid, isFalse);
      expect(resNegative.errorMessage, equals('Counter offer cannot be ₱0 or negative.'));
    });

    test('prevents blank or invalid amounts', () {
      final resBlank = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: '   ',
        isCounterOffer: true,
      );
      expect(resBlank.isValid, isFalse);
      expect(resBlank.errorMessage, equals('Please enter a valid counter offer amount.'));

      final resInvalid = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: 'xyz',
        isCounterOffer: true,
      );
      expect(resInvalid.isValid, isFalse);
      expect(resInvalid.errorMessage, equals('Please enter a valid counter offer amount.'));
    });

    test('prevents counter offers when original offer is <= 0', () {
      final res = JobCounterOfferValidator.validate(
        originalOffer: 0.0,
        counterOfferInput: '100',
        isCounterOffer: true,
      );
      expect(res.isValid, isFalse);
      expect(
        res.errorMessage,
        equals('Cannot submit a counter offer for a job with no valid original offer.'),
      );
    });
  });
}
