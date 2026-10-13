class VehiclePricingValidationResult {
  final bool isValid;
  final String? errorMessage;

  const VehiclePricingValidationResult({
    required this.isValid,
    this.errorMessage,
  });
}

class VehiclePricingRules {
  /// Minimum multiplier for weekly rate relative to daily rate.
  /// (e.g. 3.5x represents ~50% maximum discount for a 7-day rental).
  static const double minWeeklyMultiplier = 3.5;

  /// Minimum multiplier for monthly rate relative to daily rate.
  /// (e.g. 12.0x represents ~60% maximum discount for a 30-day rental).
  static const double minMonthlyMultiplier = 12.0;

  /// Minimum multiplier for 12-hour rental package relative to daily rate.
  static const double min12hMultiplier = 0.4;

  static double getMinWeeklyRate(double dailyRate) => dailyRate * minWeeklyMultiplier;
  static double getMinMonthlyRate(double dailyRate) => dailyRate * minMonthlyMultiplier;
  static double getMin12hRate(double dailyRate) => dailyRate * min12hMultiplier;

  /// Validates vehicle rental pricing across daily, 12h, weekly, and monthly rates.
  ///
  /// - Either [dailyRate] or [priceDaily] is required and must be > 0.
  /// - [price12h], [priceWeekly], and [priceMonthly] are optional packages (0.0 or omitted means not offered).
  /// - If offered, they must comply with platform minimum ratios and logical ordering.
  static VehiclePricingValidationResult validate({
    double? dailyRate,
    double? priceDaily,
    double price12h = 0.0,
    double priceWeekly = 0.0,
    double priceMonthly = 0.0,
  }) {
    final effectiveDaily = priceDaily ?? dailyRate ?? 0.0;
    if (effectiveDaily <= 0.0) {
      return const VehiclePricingValidationResult(
        isValid: false,
        errorMessage: 'Daily rental rate must be greater than ₱0.',
      );
    }

    if (price12h > 0.0) {
      final min12h = getMin12hRate(effectiveDaily);
      if (price12h < min12h) {
        return VehiclePricingValidationResult(
          isValid: false,
          errorMessage:
              '12-Hour rate (₱${price12h.toStringAsFixed(0)}) must be at least ₱${min12h.toStringAsFixed(0)} (minimum 40% of daily rate of ₱${effectiveDaily.toStringAsFixed(0)}).',
        );
      }
      if (price12h > effectiveDaily) {
        return VehiclePricingValidationResult(
          isValid: false,
          errorMessage:
              '12-Hour rate (₱${price12h.toStringAsFixed(0)}) cannot exceed the daily rental rate (₱${effectiveDaily.toStringAsFixed(0)}).',
        );
      }
    }

    if (priceWeekly > 0.0) {
      final minWeekly = getMinWeeklyRate(effectiveDaily);
      if (priceWeekly < minWeekly) {
        return VehiclePricingValidationResult(
          isValid: false,
          errorMessage:
              'Weekly rate (₱${priceWeekly.toStringAsFixed(0)}) is below the minimum allowed rate of ₱${minWeekly.toStringAsFixed(0)} (minimum 3.5x daily rate of ₱${effectiveDaily.toStringAsFixed(0)}).',
        );
      }
      if (priceWeekly <= effectiveDaily) {
        return VehiclePricingValidationResult(
          isValid: false,
          errorMessage:
              'Weekly rate (₱${priceWeekly.toStringAsFixed(0)}) must be greater than the single daily rate (₱${effectiveDaily.toStringAsFixed(0)}).',
        );
      }
    }

    if (priceMonthly > 0.0) {
      final minMonthly = getMinMonthlyRate(effectiveDaily);
      if (priceMonthly < minMonthly) {
        return VehiclePricingValidationResult(
          isValid: false,
          errorMessage:
              'Monthly rate (₱${priceMonthly.toStringAsFixed(0)}) is below the minimum allowed rate of ₱${minMonthly.toStringAsFixed(0)} (minimum 12x daily rate of ₱${effectiveDaily.toStringAsFixed(0)}).',
        );
      }
      if (priceWeekly > 0.0 && priceMonthly <= priceWeekly) {
        return VehiclePricingValidationResult(
          isValid: false,
          errorMessage:
              'Monthly rate (₱${priceMonthly.toStringAsFixed(0)}) must be greater than the weekly rate (₱${priceWeekly.toStringAsFixed(0)}).',
        );
      }
    }

    return const VehiclePricingValidationResult(isValid: true);
  }
}
