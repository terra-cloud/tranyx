import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('PropertyPricingRules Validation Tests', () {
    const daily = 1500.0;

    test('Valid rates pass validation successfully', () {
      final res = PropertyPricingRules.validate(
        dailyRate: daily,
        weeklyRate: 6000.0, // 4.0x
        monthlyRate: 20000.0, // > 12x and > weekly
      );
      expect(res.isValid, isTrue);
      expect(res.errorMessage, isNull);
    });

    test('Single-tier listings (daily only, monthly only, weekly only) pass', () {
      expect(
        PropertyPricingRules.validate(dailyRate: 1500.0).isValid,
        isTrue,
      );
      expect(
        PropertyPricingRules.validate(monthlyRate: 25000.0).isValid,
        isTrue,
      );
      expect(
        PropertyPricingRules.validate(weeklyRate: 8000.0).isValid,
        isTrue,
      );
    });

    test('Zero or missing rates on all tiers is rejected', () {
      final res = PropertyPricingRules.validate(
        dailyRate: 0.0,
        weeklyRate: 0.0,
        monthlyRate: 0.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Please provide at least one rental rate'));
    });

    test('Negative rates are rejected', () {
      final res = PropertyPricingRules.validate(
        dailyRate: -100.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('cannot be negative'));
    });

    test('Unusually low weekly rate (e.g. ₱50) is rejected with clear error', () {
      final res = PropertyPricingRules.validate(
        dailyRate: daily,
        weeklyRate: 50.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Weekly rate (₱50) is below the minimum allowed rate of ₱5250'));
    });

    test('Weekly rate below 3.5x daily is rejected', () {
      final res = PropertyPricingRules.validate(
        dailyRate: daily,
        weeklyRate: 5000.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('minimum 3.5x daily rate'));
    });

    test('Weekly rate exactly 3.5x daily passes', () {
      final res = PropertyPricingRules.validate(
        dailyRate: daily,
        weeklyRate: 5250.0,
      );
      expect(res.isValid, isTrue);
    });

    test('Unusually low monthly rate (e.g. ₱1) is rejected with clear error', () {
      final res = PropertyPricingRules.validate(
        dailyRate: daily,
        monthlyRate: 1.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Monthly rent (₱1) is below the minimum allowed rate of ₱18000'));
    });

    test('Monthly rate below 12x daily is rejected', () {
      final res = PropertyPricingRules.validate(
        dailyRate: daily,
        monthlyRate: 17500.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('minimum 12x daily rate'));
    });

    test('Monthly rate lower than weekly rate is rejected', () {
      final res = PropertyPricingRules.validate(
        dailyRate: daily,
        weeklyRate: 20000.0,
        monthlyRate: 19000.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Monthly rent (₱19000) must be greater than the weekly rate (₱20000)'));
    });

    test('Reverse check: daily rate cannot be lower than monthly / 30', () {
      final res = PropertyPricingRules.validate(
        dailyRate: 500.0,
        monthlyRate: 30000.0, // 30000 / 30 = 1000
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('cannot be lower than the per-day monthly equivalent'));
    });

    test('Reverse check: weekly rate cannot be lower than monthly / 4', () {
      final res = PropertyPricingRules.validate(
        weeklyRate: 6000.0,
        monthlyRate: 30000.0, // 30000 / 4 = 7500
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('cannot be lower than the per-week monthly equivalent'));
    });
  });

  group('PropertyPricingModel Defense-in-depth Tests', () {
    test('Corrupted monthly rate (₱1) with valid daily rate (₱1500) does not charge ₱1 for 30 days', () {
      final model = PropertyPricingModel(
        dailyRate: 1500.0,
        monthlyRate: 1.0, // Corrupted
      );

      final financials = model.calculate(totalDays: 30);
      // Inverted monthly rate must be ignored, falling back to 30 * 1500 = 45000
      expect(financials.baseRent, equals(45000.0));
      expect(financials.appliedTier, equals(DurationTier.daily));
    });

    test('Corrupted weekly rate (₱50) with valid daily rate (₱1500) does not charge ₱50 for 7 days', () {
      final model = PropertyPricingModel(
        dailyRate: 1500.0,
        weeklyRate: 50.0, // Corrupted
      );

      final financials = model.calculate(totalDays: 7);
      // Inverted weekly rate must be ignored, falling back to 7 * 1500 = 10500
      expect(financials.baseRent, equals(10500.0));
      expect(financials.appliedTier, equals(DurationTier.daily));
    });
  });
}
