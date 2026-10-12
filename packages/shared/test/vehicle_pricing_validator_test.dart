import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('VehiclePricingRules Validation Tests', () {
    const daily = 1500.0;

    test('Valid rates pass validation successfully', () {
      final res = VehiclePricingRules.validate(
        dailyRate: daily,
        price12h: 1000.0,
        priceWeekly: 6000.0, // 4.0x
        priceMonthly: 20000.0, // > 12x and > weekly
      );
      expect(res.isValid, isTrue);
      expect(res.errorMessage, isNull);
    });

    test('Zero daily rate is rejected', () {
      final res = VehiclePricingRules.validate(
        dailyRate: 0.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Daily rental rate must be greater than ₱0'));
    });

    test('Optional rates (0.0 or omitted) pass validation', () {
      final res = VehiclePricingRules.validate(
        dailyRate: daily,
        price12h: 0.0,
        priceWeekly: 0.0,
        priceMonthly: 0.0,
      );
      expect(res.isValid, isTrue);
    });

    test('Unusually low weekly rate (e.g. ₱11) is rejected with clear error', () {
      final res = VehiclePricingRules.validate(
        dailyRate: daily,
        priceWeekly: 11.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Weekly rate (₱11) is below the minimum allowed rate of ₱5250'));
    });

    test('Weekly rate below 3.5x daily is rejected', () {
      // 1500 * 3.5 = 5250
      final res = VehiclePricingRules.validate(
        dailyRate: daily,
        priceWeekly: 5000.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('minimum 3.5x daily rate'));
    });

    test('Weekly rate exactly 3.5x daily passes', () {
      final res = VehiclePricingRules.validate(
        dailyRate: daily,
        priceWeekly: 5250.0,
      );
      expect(res.isValid, isTrue);
    });

    test('Unusually low monthly rate (e.g. ₱47) is rejected with clear error', () {
      final res = VehiclePricingRules.validate(
        dailyRate: daily,
        priceMonthly: 47.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Monthly rate (₱47) is below the minimum allowed rate of ₱18000'));
    });

    test('Monthly rate below 12x daily is rejected', () {
      // 1500 * 12 = 18000
      final res = VehiclePricingRules.validate(
        dailyRate: daily,
        priceMonthly: 17500.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('minimum 12x daily rate'));
    });

    test('Monthly rate lower than weekly rate is rejected', () {
      final res = VehiclePricingRules.validate(
        dailyRate: daily,
        priceWeekly: 20000.0,
        priceMonthly: 19000.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Monthly rate (₱19000) must be greater than the weekly rate (₱20000)'));
    });

    test('12-hour rate higher than daily rate is rejected', () {
      final res = VehiclePricingRules.validate(
        dailyRate: daily,
        price12h: 1600.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('cannot exceed the daily rental rate'));
    });

    test('12-hour rate lower than 40% of daily rate is rejected', () {
      // 1500 * 0.4 = 600
      final res = VehiclePricingRules.validate(
        dailyRate: daily,
        price12h: 500.0,
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('minimum 40% of daily rate'));
    });
  });

  group('SmartRateEngine Corrupt Pricing Defense Tests', () {
    test('Corrupt weekly rate (₱11) is ignored and does not undercharge daily rental', () {
      final res = SmartRateEngine.calculateOptimizedRate(
        totalDays: 1,
        priceDaily: 1500.0,
        priceWeekly: 11.0, // Corrupt sub-daily rate
        priceMonthly: 47.0, // Corrupt sub-daily rate
      );

      // Must charge normal 1x daily rate (1500), NOT 11 or 47!
      expect(res.totalBasePrice, equals(1500.0));
      expect(res.days, equals(1));
      expect(res.weeks, equals(0));
      expect(res.months, equals(0));
    });

    test('Corrupt weekly rate (₱11) for 7 days falls back safely to pure daily calculation', () {
      final res = SmartRateEngine.calculateOptimizedRate(
        totalDays: 7,
        priceDaily: 1500.0,
        priceWeekly: 11.0, // Corrupt
      );

      // Must charge 7 * 1500 = 10500, NOT 11!
      expect(res.totalBasePrice, equals(10500.0));
    });
  });
}
