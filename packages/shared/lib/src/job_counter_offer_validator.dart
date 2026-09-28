/// Helper and validator for Job Application Counter Offers.
/// Enforces counter offers to be between 80% (minimum) and 150% (maximum)
/// of the employer's original offer, and strictly positive (> ₱0).
class CounterOfferValidationResult {
  final bool isValid;
  final String? errorMessage;
  final double? sanitizedRate;

  const CounterOfferValidationResult({
    required this.isValid,
    this.errorMessage,
    this.sanitizedRate,
  });

  const CounterOfferValidationResult.valid([this.sanitizedRate])
      : isValid = true,
        errorMessage = null;

  const CounterOfferValidationResult.invalid(this.errorMessage)
      : isValid = false,
        sanitizedRate = null;
}

class JobCounterOfferValidator {
  static const double minPercentage = 0.80; // 80%
  static const double maxPercentage = 1.50; // 150%

  /// Calculates minimum permitted counter offer (rounded to 2 decimal places).
  static double calculateMin(double originalOffer) {
    if (originalOffer <= 0) return 0.0;
    return (((originalOffer * minPercentage) + 1e-9) * 100).round() / 100.0;
  }

  /// Calculates maximum permitted counter offer (rounded to 2 decimal places).
  static double calculateMax(double originalOffer) {
    if (originalOffer <= 0) return 0.0;
    return (((originalOffer * maxPercentage) + 1e-9) * 100).round() / 100.0;
  }

  /// Formats amount in currency representation (e.g. ₱1,000 or ₱800.50).
  static String formatAmount(double amount) {
    final isWhole = (amount % 1) == 0;
    if (isWhole) {
      final wholeStr = amount.toInt().toString();
      final withCommas = wholeStr.replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
      return '₱$withCommas';
    } else {
      final parts = amount.toStringAsFixed(2).split('.');
      final withCommas = parts[0].replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
      return '₱$withCommas.${parts[1]}';
    }
  }

  /// Returns user-facing message required by the specification:
  /// "Your counter offer must be between ₱800 and ₱1,500 based on the employer's original offer of ₱1,000."
  static String getRangeValidationMessage(double originalOffer) {
    final min = calculateMin(originalOffer);
    final max = calculateMax(originalOffer);
    return 'Your counter offer must be between ${formatAmount(min)} and ${formatAmount(max)} based on the employer\'s original offer of ${formatAmount(originalOffer)}.';
  }

  /// Returns friendly range guidance text for displaying in Nyxian UI:
  /// "Allowed counter offer: ₱800 – ₱1,500 (80% – 150% of ₱1,000)"
  static String getPermittedRangeDisplay(double originalOffer) {
    final min = calculateMin(originalOffer);
    final max = calculateMax(originalOffer);
    return 'Allowed counter offer: ${formatAmount(min)} – ${formatAmount(max)} (80% – 150% of original offer ${formatAmount(originalOffer)})';
  }

  /// Cleans user string input (removes ₱, commas, spaces) and parses to double.
  static double? cleanAndParse(dynamic input) {
    if (input == null) return null;
    if (input is num) {
      if (input.isNaN || !input.isFinite) return null;
      return input.toDouble();
    }
    final raw = input.toString().replaceAll('₱', '').replaceAll(',', '').trim();
    if (raw.isEmpty) return null;
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed.isNaN || !parsed.isFinite) return null;
    return parsed;
  }

  /// Validates a counter offer amount against an employer's original offer.
  static CounterOfferValidationResult validate({
    required double originalOffer,
    required dynamic counterOfferInput,
    required bool isCounterOffer,
  }) {
    // If not a counter offer, proposalRate equals standard originalOffer
    if (!isCounterOffer) {
      return CounterOfferValidationResult.valid(originalOffer);
    }

    if (originalOffer <= 0) {
      return const CounterOfferValidationResult.invalid(
        'Cannot submit a counter offer for a job with no valid original offer.',
      );
    }

    final parsedRate = cleanAndParse(counterOfferInput);

    if (parsedRate == null) {
      return const CounterOfferValidationResult.invalid(
        'Please enter a valid counter offer amount.',
      );
    }

    if (parsedRate <= 0) {
      return const CounterOfferValidationResult.invalid(
        'Counter offer cannot be ₱0 or negative.',
      );
    }

    final min = calculateMin(originalOffer);
    final max = calculateMax(originalOffer);

    // Epsilon tolerance of 0.001 to avoid IEEE-754 floating point precision false-negatives
    if (parsedRate < (min - 0.001) || parsedRate > (max + 0.001)) {
      return CounterOfferValidationResult.invalid(
        getRangeValidationMessage(originalOffer),
      );
    }

    return CounterOfferValidationResult.valid(parsedRate);
  }
}
