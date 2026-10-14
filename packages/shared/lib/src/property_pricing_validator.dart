class PropertyPricingValidationResult {
  final bool isValid;
  final String? errorMessage;

  const PropertyPricingValidationResult({
    required this.isValid,
    this.errorMessage,
  });
}

class PropertyPricingRules {
  /// Minimum multiplier for weekly rate relative to daily rate.
  /// (e.g. 3.5x represents ~50% maximum discount for a 7-day rental).
  static const double minWeeklyMultiplier = 3.5;

  /// Minimum multiplier for monthly rate relative to daily rate.
  /// (e.g. 12.0x represents ~60% maximum discount for a 30-day rental).
  static const double minMonthlyMultiplier = 12.0;

  static double getMinWeeklyRate(double dailyRate) => dailyRate * minWeeklyMultiplier;
  static double getMinMonthlyRate(double dailyRate) => dailyRate * minMonthlyMultiplier;

  /// Validates property rental pricing across daily, weekly, and monthly rates.
  ///
  /// Rules:
  /// 1. At least one rate (daily, weekly, or monthly) must be provided and > 0.
  /// 2. If daily rate is provided:
  ///    - Weekly rate (if offered) must be >= 3.5x daily rate and strictly > daily rate.
  ///    - Monthly rent (if offered) must be >= 12.0x daily rate and strictly > weekly rate.
  /// 3. If monthly rent is provided and daily is also provided:
  ///    - Daily rate cannot be less than (monthly / 30).
  /// 4. If monthly rent is provided and weekly is also provided:
  ///    - Weekly rate cannot be less than (monthly / 4).
  /// 5. Logical ordering invariant: when multiple tiers are provided:
  ///    Daily Rate < Weekly Rate < Monthly Rent.
  static PropertyPricingValidationResult validate({
    double? priceDaily,
    double? dailyRate,
    double? priceWeekly,
    double? weeklyRate,
    double? priceMonthly,
    double? monthlyRate,
  }) {
    final effectiveDaily = (priceDaily ?? dailyRate ?? 0.0);
    final effectiveWeekly = (priceWeekly ?? weeklyRate ?? 0.0);
    final effectiveMonthly = (priceMonthly ?? monthlyRate ?? 0.0);

    if (effectiveDaily < 0.0 || effectiveWeekly < 0.0 || effectiveMonthly < 0.0) {
      return const PropertyPricingValidationResult(
        isValid: false,
        errorMessage: 'Rental rates cannot be negative.',
      );
    }

    if (effectiveDaily <= 0.0 && effectiveWeekly <= 0.0 && effectiveMonthly <= 0.0) {
      return const PropertyPricingValidationResult(
        isValid: false,
        errorMessage: 'Please provide at least one rental rate (Daily, Weekly, or Monthly).',
      );
    }

    // Ratio validation when Daily rate is offered
    if (effectiveDaily > 0.0) {
      if (effectiveWeekly > 0.0) {
        final minWeekly = getMinWeeklyRate(effectiveDaily);
        if (effectiveWeekly < minWeekly) {
          return PropertyPricingValidationResult(
            isValid: false,
            errorMessage:
                'Weekly rate (₱${effectiveWeekly.toStringAsFixed(0)}) is below the minimum allowed rate of ₱${minWeekly.toStringAsFixed(0)} (minimum 3.5x daily rate of ₱${effectiveDaily.toStringAsFixed(0)}).',
          );
        }
        if (effectiveWeekly <= effectiveDaily) {
          return PropertyPricingValidationResult(
            isValid: false,
            errorMessage:
                'Weekly rate (₱${effectiveWeekly.toStringAsFixed(0)}) must be greater than the single daily rate (₱${effectiveDaily.toStringAsFixed(0)}).',
          );
        }
      }

      if (effectiveMonthly > 0.0) {
        final minMonthly = getMinMonthlyRate(effectiveDaily);
        if (effectiveMonthly < minMonthly) {
          return PropertyPricingValidationResult(
            isValid: false,
            errorMessage:
                'Monthly rent (₱${effectiveMonthly.toStringAsFixed(0)}) is below the minimum allowed rate of ₱${minMonthly.toStringAsFixed(0)} (minimum 12x daily rate of ₱${effectiveDaily.toStringAsFixed(0)}).',
          );
        }
        if (effectiveWeekly > 0.0 && effectiveMonthly <= effectiveWeekly) {
          return PropertyPricingValidationResult(
            isValid: false,
            errorMessage:
                'Monthly rent (₱${effectiveMonthly.toStringAsFixed(0)}) must be greater than the weekly rate (₱${effectiveWeekly.toStringAsFixed(0)}).',
          );
        }
        if (effectiveMonthly <= effectiveDaily) {
          return PropertyPricingValidationResult(
            isValid: false,
            errorMessage:
                'Monthly rent (₱${effectiveMonthly.toStringAsFixed(0)}) must be greater than the daily rate (₱${effectiveDaily.toStringAsFixed(0)}).',
          );
        }
      }
    }

    // Reverse check when Monthly is primary (e.g. daily/weekly are entered without prior daily base)
    if (effectiveMonthly > 0.0) {
      if (effectiveDaily > 0.0) {
        final minDailyEquiv = effectiveMonthly / 30.0;
        if (effectiveDaily < minDailyEquiv) {
          return PropertyPricingValidationResult(
            isValid: false,
            errorMessage:
                'Daily rate (₱${effectiveDaily.toStringAsFixed(0)}) cannot be lower than the per-day monthly equivalent of ₱${minDailyEquiv.toStringAsFixed(0)} (₱${effectiveMonthly.toStringAsFixed(0)} / 30 days).',
          );
        }
      }

      if (effectiveWeekly > 0.0) {
        final minWeeklyEquiv = effectiveMonthly / 4.0;
        if (effectiveWeekly < minWeeklyEquiv) {
          return PropertyPricingValidationResult(
            isValid: false,
            errorMessage:
                'Weekly rate (₱${effectiveWeekly.toStringAsFixed(0)}) cannot be lower than the per-week monthly equivalent of ₱${minWeeklyEquiv.toStringAsFixed(0)} (₱${effectiveMonthly.toStringAsFixed(0)} / 4 weeks).',
          );
        }
      }
    }

    // Direct weekly vs daily check if monthly is omitted
    if (effectiveWeekly > 0.0 && effectiveDaily > 0.0 && effectiveWeekly <= effectiveDaily) {
      return PropertyPricingValidationResult(
        isValid: false,
        errorMessage:
            'Weekly rate (₱${effectiveWeekly.toStringAsFixed(0)}) must be greater than the daily rate (₱${effectiveDaily.toStringAsFixed(0)}).',
      );
    }

    return const PropertyPricingValidationResult(isValid: true);
  }
}
