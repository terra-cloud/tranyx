import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('SmartRateEngine Tier Optimization & Capping Tests', () {
    const dailyRate = 1000.0;
    const weeklyRate = 4500.0;
    const monthlyRate = 16000.0;

    test('Scenario 1: 7-Day Threshold auto-applies 1x Weekly Rate', () {
      final res = SmartRateEngine.calculateOptimizedRate(
        totalDays: 7,
        priceDaily: dailyRate,
        priceWeekly: weeklyRate,
        priceMonthly: monthlyRate,
      );

      expect(res.totalBasePrice, equals(4500.0));
      expect(res.weeks, equals(1));
      expect(res.days, equals(0));
      expect(res.breakdownDescription, contains('1 x Weekly'));
      expect(res.savings, equals(2500.0)); // 7000 - 4500
    });

    test('Scenario 2: 30-Day Threshold auto-applies 1x Monthly Rate', () {
      final res = SmartRateEngine.calculateOptimizedRate(
        totalDays: 30,
        priceDaily: dailyRate,
        priceWeekly: weeklyRate,
        priceMonthly: monthlyRate,
      );

      expect(res.totalBasePrice, equals(16000.0));
      expect(res.months, equals(1));
      expect(res.weeks, equals(0));
      expect(res.days, equals(0));
      expect(res.breakdownDescription, contains('1 x Monthly'));
    });

    test('Scenario 3: Hybrid Duration (10 Days) = 1x Weekly + 3x Daily', () {
      final res = SmartRateEngine.calculateOptimizedRate(
        totalDays: 10,
        priceDaily: dailyRate,
        priceWeekly: weeklyRate,
        priceMonthly: monthlyRate,
      );

      expect(res.totalBasePrice, equals(7500.0)); // 4500 + 3*1000
      expect(res.weeks, equals(1));
      expect(res.days, equals(3));
      expect(res.breakdownDescription, contains('1 x Weekly'));
      expect(res.breakdownDescription, contains('3 x Daily'));
    });

    test('Scenario 4: Price Capping (5 Days Daily > 1-Week Flat Rate)', () {
      final res = SmartRateEngine.calculateOptimizedRate(
        totalDays: 5,
        priceDaily: dailyRate,
        priceWeekly: weeklyRate, // 5 * 1000 = 5000 > 4500
        priceMonthly: monthlyRate,
      );

      expect(res.totalBasePrice, equals(4500.0));
      expect(res.weeks, equals(1));
      expect(res.days, equals(0));
      expect(res.isCapped, isTrue);
      expect(res.capReason, isNotNull);
      expect(res.savings, equals(500.0));
    });

    test('Scenario 5: Remainder Capping (13 Days: 1w + 6d > 2w)', () {
      final res = SmartRateEngine.calculateOptimizedRate(
        totalDays: 13,
        priceDaily: dailyRate,
        priceWeekly: weeklyRate,
        priceMonthly: monthlyRate,
      );

      // 1 week (4500) + 6 days (6000) = 10500 > 2 weeks (9000) -> capped at 9000
      expect(res.totalBasePrice, equals(9000.0));
      expect(res.weeks, equals(2));
      expect(res.days, equals(0));
      expect(res.isCapped, isTrue);
    });

    test('Scenario 6: 12-Hour Package calculation', () {
      final res = SmartRateEngine.calculateOptimizedRate(
        totalDays: 0,
        hours: 12,
        price12h: 600.0,
        priceDaily: dailyRate,
      );

      expect(res.totalBasePrice, equals(600.0));
      expect(res.halfDays, equals(1));
      expect(res.breakdownDescription, contains('12-Hour Rate'));
    });
  });
}
