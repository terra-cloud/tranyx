/// Platform-wide dynamic fee configuration model.
/// Stores customizable rates (service fees, markup, transaction fees, convenience fees, commission, etc.).
class PlatformFeeConfig {
  /// Transaction processing fee (default 0.07 / 7%)
  final double transactionFeeRate;

  /// Convenience fee (default 0.03 / 3%)
  final double convenienceFeeRate;

  /// Worker / Host platform commission (default 0.03 / 3%)
  final double commissionRate;

  /// Service fee (e.g. 0.01 / 1% or customized by admin)
  final double serviceFeeRate;

  /// Markup fee (e.g. 0.03 / 3% or customized by admin)
  final double markupRate;

  /// Rentee / Guest booking fee (default 0.03 / 3%)
  final double bookingFeeRate;

  /// Upfront listing fee for host listings (default 0.015 / 1.5%)
  final double listingFeeRate;

  /// Quality inspection escrow holdback rate (default 0.10 / 10%)
  final double holdbackRate;

  const PlatformFeeConfig({
    this.transactionFeeRate = 0.07,
    this.convenienceFeeRate = 0.03,
    this.commissionRate = 0.03,
    this.serviceFeeRate = 0.01,
    this.markupRate = 0.03,
    this.bookingFeeRate = 0.03,
    this.listingFeeRate = 0.015,
    this.holdbackRate = 0.10,
  });

  /// Factory parser from Firestore map
  factory PlatformFeeConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PlatformFeeConfig();
    return PlatformFeeConfig(
      transactionFeeRate: (map['transactionFeeRate'] as num?)?.toDouble() ??
          (map['txFeeRate'] as num?)?.toDouble() ??
          0.07,
      convenienceFeeRate: (map['convenienceFeeRate'] as num?)?.toDouble() ??
          (map['convFeeRate'] as num?)?.toDouble() ??
          0.03,
      commissionRate: (map['commissionRate'] as num?)?.toDouble() ??
          (map['platformCommissionRate'] as num?)?.toDouble() ??
          0.03,
      serviceFeeRate: (map['serviceFeeRate'] as num?)?.toDouble() ?? 0.01,
      markupRate: (map['markupRate'] as num?)?.toDouble() ?? 0.03,
      bookingFeeRate: (map['bookingFeeRate'] as num?)?.toDouble() ?? 0.03,
      listingFeeRate: (map['listingFeeRate'] as num?)?.toDouble() ?? 0.015,
      holdbackRate: (map['holdbackRate'] as num?)?.toDouble() ?? 0.10,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'transactionFeeRate': transactionFeeRate,
      'convenienceFeeRate': convenienceFeeRate,
      'commissionRate': commissionRate,
      'serviceFeeRate': serviceFeeRate,
      'markupRate': markupRate,
      'bookingFeeRate': bookingFeeRate,
      'listingFeeRate': listingFeeRate,
      'holdbackRate': holdbackRate,
    };
  }

  /// Formatted rate string helper (e.g. 0.01 -> "1%", 0.015 -> "1.5%")
  static String formatPercent(double rate) {
    final pct = rate * 100;
    if ((pct - pct.round()).abs() < 0.0001) {
      return '${pct.round()}%';
    }
    final formatted = pct.toStringAsFixed(2);
    if (formatted.endsWith('0')) {
      return '${pct.toStringAsFixed(1)}%';
    }
    return '$formatted%';
  }
}
