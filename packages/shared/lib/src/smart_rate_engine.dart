/// Smart Tiered Rate Engine for calculating optimal rental pricing.
///
/// Converts arbitrary rental durations (days, weeks, months) into the most
/// cost-effective pricing tier combination, applying automatic capping rules:
/// - 7-day threshold: switches to weekly rate if cheaper than 7x daily
/// - 30-day threshold: switches to monthly rate if cheaper
/// - Hybrid durations (e.g. 10 days): 1x weekly + 3x daily
/// - Price Capping: If N x daily exceeds weekly flat rate, automatically cap at weekly rate
/// - Live breakdown description for clear user transparency.
library;

class TierOptimizationResult {
  final double totalBasePrice;
  final int months;
  final int weeks;
  final int days;
  final int halfDays;
  final double monthlyRate;
  final double weeklyRate;
  final double dailyRate;
  final double halfDayRate;
  final String breakdownDescription;
  final bool isCapped;
  final String? capReason;
  final double unoptimizedPrice;
  final double savings;

  const TierOptimizationResult({
    required this.totalBasePrice,
    this.months = 0,
    this.weeks = 0,
    this.days = 0,
    this.halfDays = 0,
    this.monthlyRate = 0,
    this.weeklyRate = 0,
    this.dailyRate = 0,
    this.halfDayRate = 0,
    required this.breakdownDescription,
    this.isCapped = false,
    this.capReason,
    this.unoptimizedPrice = 0,
    this.savings = 0,
  });

  Map<String, dynamic> toMap() => {
    'totalBasePrice': totalBasePrice,
    'months': months,
    'weeks': weeks,
    'days': days,
    'halfDays': halfDays,
    'breakdownDescription': breakdownDescription,
    'isCapped': isCapped,
    'capReason': capReason,
    'unoptimizedPrice': unoptimizedPrice,
    'savings': savings,
  };
}

class SmartRateEngine {
  /// Computes the optimal, lowest-cost tiered rate for a given rental duration in days.
  static TierOptimizationResult calculateOptimizedRate({
    required int totalDays,
    int hours = 0,
    double price12h = 0,
    double priceDaily = 0,
    double priceWeekly = 0,
    double priceMonthly = 0,
  }) {
    // 12-Hour Package handling
    if (totalDays == 0 && hours > 0) {
      final halfDays = (hours / 12).ceil();
      final unitRate = price12h > 0 ? price12h : (priceDaily > 0 ? priceDaily * 0.5 : 0.0);
      final total = halfDays * unitRate;
      return TierOptimizationResult(
        totalBasePrice: total,
        halfDays: halfDays,
        halfDayRate: unitRate,
        dailyRate: priceDaily,
        weeklyRate: priceWeekly,
        monthlyRate: priceMonthly,
        breakdownDescription: '$halfDays x 12-Hour Rate (₱${unitRate.toStringAsFixed(0)})',
        unoptimizedPrice: total,
        savings: 0,
      );
    }

    final effectiveDays = totalDays <= 0 ? 1 : totalDays;
    final unoptimized = priceDaily > 0 ? (effectiveDays * priceDaily) : 0.0;

    // If only daily rate is provided and no weekly/monthly rates exist:
    if (priceWeekly <= 0 && priceMonthly <= 0) {
      final total = effectiveDays * priceDaily;
      return TierOptimizationResult(
        totalBasePrice: total,
        days: effectiveDays,
        dailyRate: priceDaily,
        breakdownDescription: '$effectiveDays x Daily Rate (₱${priceDaily.toStringAsFixed(0)})',
        unoptimizedPrice: unoptimized,
        savings: 0,
      );
    }

    // Step 1: Base decomposition into months (30d), weeks (7d), and leftover days
    int remainingDays = effectiveDays;
    int months = 0;
    int weeks = 0;
    int days = 0;

    if (priceMonthly > 0 && remainingDays >= 30) {
      months = remainingDays ~/ 30;
      remainingDays %= 30;
    }

    if (priceWeekly > 0 && remainingDays >= 7) {
      weeks = remainingDays ~/ 7;
      remainingDays %= 7;
    }

    days = remainingDays;

    // Step 2: Capping checks within remainder
    // Check 2A: Does leftover days * priceDaily exceed priceWeekly?
    bool cappedDaysToWeek = false;
    if (priceWeekly > 0 && days > 0 && (days * priceDaily > priceWeekly)) {
      weeks += 1;
      days = 0;
      cappedDaysToWeek = true;
    }

    // Check 2B: Does (weeks * priceWeekly + days * priceDaily) exceed priceMonthly?
    bool cappedWeeksToMonth = false;
    if (priceMonthly > 0) {
      final subMonthCost = (weeks * priceWeekly) + (days * priceDaily);
      if (subMonthCost > priceMonthly) {
        months += 1;
        weeks = 0;
        days = 0;
        cappedWeeksToMonth = true;
      }
    }

    // Calculate candidate 1 cost
    final candidate1Cost = (months * priceMonthly) + (weeks * priceWeekly) + (days * priceDaily);

    // Check Candidate 2: Whole duration capped at next whole week (if total days <= 7 and priceWeekly > 0)
    double bestCost = candidate1Cost;
    int bestMonths = months;
    int bestWeeks = weeks;
    int bestDays = days;
    bool isCapped = cappedDaysToWeek || cappedWeeksToMonth;
    String? capReason;

    if (cappedDaysToWeek) {
      capReason = 'Optimal Weekly Cap Applied (Cheaper than individual daily rates)';
    } else if (cappedWeeksToMonth) {
      capReason = 'Optimal Monthly Cap Applied (Cheaper than combined weekly/daily rates)';
    }

    // Check if flat weekly is cheaper than pure daily
    if (priceWeekly > 0 && effectiveDays < 7 && (effectiveDays * priceDaily > priceWeekly)) {
      if (priceWeekly < bestCost) {
        bestCost = priceWeekly;
        bestMonths = 0;
        bestWeeks = 1;
        bestDays = 0;
        isCapped = true;
        capReason = 'Optimal 1-Week Cap Applied (Cheaper than $effectiveDays days at daily rate)';
      }
    }

    // Check if flat monthly is cheaper than total
    if (priceMonthly > 0 && priceMonthly < bestCost) {
      bestCost = priceMonthly;
      bestMonths = 1;
      bestWeeks = 0;
      bestDays = 0;
      isCapped = true;
      capReason = 'Optimal 1-Month Cap Applied';
    }

    // Build human-friendly breakdown string
    final List<String> parts = [];
    if (bestMonths > 0) {
      parts.add('$bestMonths x Monthly (₱${(bestMonths * priceMonthly).toStringAsFixed(0)})');
    }
    if (bestWeeks > 0) {
      parts.add('$bestWeeks x Weekly (₱${(bestWeeks * priceWeekly).toStringAsFixed(0)})');
    }
    if (bestDays > 0) {
      parts.add('$bestDays x Daily (₱${(bestDays * priceDaily).toStringAsFixed(0)})');
    }

    final breakdownStr = parts.isEmpty ? '₱ ${bestCost.toStringAsFixed(0)}' : parts.join(' + ');
    final savings = (unoptimized > bestCost) ? (unoptimized - bestCost) : 0.0;

    return TierOptimizationResult(
      totalBasePrice: bestCost,
      months: bestMonths,
      weeks: bestWeeks,
      days: bestDays,
      monthlyRate: priceMonthly,
      weeklyRate: priceWeekly,
      dailyRate: priceDaily,
      halfDayRate: price12h,
      breakdownDescription: breakdownStr,
      isCapped: isCapped,
      capReason: capReason,
      unoptimizedPrice: unoptimized,
      savings: savings,
    );
  }
}
