class InsufficientFundsException implements Exception {
  final double availableBalance;
  final double requiredAmount;
  final double shortfall;
  final String transactionTitle;

  const InsufficientFundsException({
    required this.availableBalance,
    required this.requiredAmount,
    required this.shortfall,
    this.transactionTitle = 'transaction',
  });

  String get formattedMessage =>
      'Insufficient Tyxbit Balance: Your available balance is ₱${availableBalance.toStringAsFixed(2)}, '
      'but this $transactionTitle requires ₱${requiredAmount.toStringAsFixed(2)} including all fees. '
      'Shortfall: ₱${shortfall.toStringAsFixed(2)}. Please top up your wallet before continuing.';

  @override
  String toString() => formattedMessage;
}

class NegativeBalanceException implements Exception {
  final double currentBalance;
  final double attemptDeduction;

  const NegativeBalanceException({
    required this.currentBalance,
    required this.attemptDeduction,
  });

  @override
  String toString() =>
      'Security Exception: Resulting balance cannot be negative. Current: ₱${currentBalance.toStringAsFixed(2)}, Deduction: ₱${attemptDeduction.toStringAsFixed(2)}.';
}

class WalletSecurityHelper {
  /// Validates that availableBalance >= totalCost and that resulting balance >= 0.
  /// Throws [InsufficientFundsException] if balance is insufficient.
  static void validateSufficientFunds({
    required double availableBalance,
    required double totalCost,
    String transactionTitle = 'transaction',
  }) {
    if (availableBalance < totalCost || (availableBalance - totalCost) < -0.000001) {
      final shortfall = (totalCost - availableBalance).clamp(0.0, double.infinity);
      throw InsufficientFundsException(
        availableBalance: availableBalance,
        requiredAmount: totalCost,
        shortfall: shortfall,
        transactionTitle: transactionTitle,
      );
    }
  }

  /// Calculates the total upfront cost for an Employer posting or funding a job.
  /// Includes the budget (discounted) plus the required employer platform fees:
  /// transaction fee (e.g. 7%) + convenience fee (e.g. 3%).
  static double calculateJobTotalEmployerCost({
    required double price,
    double discount = 0.0,
    double txFeeRate = 0.07,
    double convFeeRate = 0.03,
  }) {
    final discountedPrice = (price - discount).clamp(0.0, 9999999.0);
    final txFee = discountedPrice * txFeeRate;
    final convFee = discountedPrice * convFeeRate;
    final totalFees = txFee + convFee;
    return discountedPrice + totalFees;
  }

  /// Calculates the employer fees portion for a job
  static double calculateJobEmployerFees({
    required double price,
    double discount = 0.0,
    double txFeeRate = 0.07,
    double convFeeRate = 0.03,
  }) {
    final discountedPrice = (price - discount).clamp(0.0, 9999999.0);
    return (discountedPrice * txFeeRate) + (discountedPrice * convFeeRate);
  }

  /// Verifies a safe deduction and returns the new non-negative balance.
  /// Throws [NegativeBalanceException] if resulting balance < 0.
  static double calculateSafeNewBalance({
    required double currentBalance,
    required double amountToDeduct,
  }) {
    if (amountToDeduct < 0) {
      throw ArgumentError('Deduction amount must be non-negative: $amountToDeduct');
    }
    final newBalance = currentBalance - amountToDeduct;
    if (newBalance < -0.000001) {
      throw NegativeBalanceException(
        currentBalance: currentBalance,
        attemptDeduction: amountToDeduct,
      );
    }
    // Clean floating point tiny residuals
    return newBalance < 0.0 ? 0.0 : double.parse(newBalance.toStringAsFixed(4));
  }
}
