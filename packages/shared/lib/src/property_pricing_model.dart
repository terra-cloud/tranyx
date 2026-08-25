/// Supported security deposit policy types configured on property listings.
enum DepositType {
  fixed,
  percentage,
  none,
}

/// Duration tiers matched by duration-driven pricing engine.
enum DurationTier {
  daily,
  weekly,
  monthly,
}

/// Helper converter for DepositType serialization.
extension DepositTypeHelper on DepositType {
  String get nameString {
    switch (this) {
      case DepositType.fixed:
        return 'FIXED_AMOUNT';
      case DepositType.percentage:
        return 'PERCENTAGE';
      case DepositType.none:
        return 'NONE';
    }
  }

  static DepositType fromString(String? val) {
    if (val == null) return DepositType.none;
    final upper = val.toUpperCase().trim();
    if (upper == 'FIXED_AMOUNT' || upper == 'FIXED') return DepositType.fixed;
    if (upper == 'PERCENTAGE' || upper == 'PERCENT') return DepositType.percentage;
    return DepositType.none;
  }
}

/// Output breakdown of a property booking calculation.
class BookingFinancials {
  final DurationTier appliedTier;
  final int totalDays;
  final double unitRate;
  final double baseRent;
  final double securityDeposit;
  final DepositType depositType;
  final double depositValue;
  final double customerPlatformFeeRate;
  final double customerPlatformFee;
  final double totalCustomerPayable;
  final double hostCommissionRate;
  final double hostCommission;
  final double hostNetIncome;

  const BookingFinancials({
    required this.appliedTier,
    required this.totalDays,
    required this.unitRate,
    required this.baseRent,
    required this.securityDeposit,
    required this.depositType,
    required this.depositValue,
    required this.customerPlatformFeeRate,
    required this.customerPlatformFee,
    required this.totalCustomerPayable,
    required this.hostCommissionRate,
    required this.hostCommission,
    required this.hostNetIncome,
  });

  Map<String, dynamic> toMap() {
    return {
      'appliedTier': appliedTier.name.toUpperCase(),
      'totalDays': totalDays,
      'unitRate': unitRate,
      'baseRentAmount': baseRent,
      'securityDepositAmount': securityDeposit,
      'depositType': depositType.nameString,
      'depositValue': depositValue,
      'customerPlatformFeeRate': customerPlatformFeeRate,
      'customerPlatformFeeAmount': customerPlatformFee,
      'totalCustomerPaid': totalCustomerPayable,
      'hostCommissionRate': hostCommissionRate,
      'hostCommissionAmount': hostCommission,
      'hostNetPayout': hostNetIncome,
    };
  }

  factory BookingFinancials.fromMap(Map<String, dynamic> map) {
    final tierStr = (map['appliedTier'] as String? ?? 'DAILY').toLowerCase();
    final tier = DurationTier.values.firstWhere(
      (t) => t.name == tierStr,
      orElse: () => DurationTier.daily,
    );

    return BookingFinancials(
      appliedTier: tier,
      totalDays: (map['totalDays'] as num?)?.toInt() ?? 1,
      unitRate: (map['unitRate'] as num?)?.toDouble() ?? 0.0,
      baseRent: (map['baseRentAmount'] as num?)?.toDouble() ?? 0.0,
      securityDeposit: (map['securityDepositAmount'] as num?)?.toDouble() ?? 0.0,
      depositType: DepositTypeHelper.fromString(map['depositType'] as String?),
      depositValue: (map['depositValue'] as num?)?.toDouble() ?? 0.0,
      customerPlatformFeeRate: (map['customerPlatformFeeRate'] as num?)?.toDouble() ?? 0.03,
      customerPlatformFee: (map['customerPlatformFeeAmount'] as num?)?.toDouble() ?? 0.0,
      totalCustomerPayable: (map['totalCustomerPaid'] as num?)?.toDouble() ?? 0.0,
      hostCommissionRate: (map['hostCommissionRate'] as num?)?.toDouble() ?? 0.07,
      hostCommission: (map['hostCommissionAmount'] as num?)?.toDouble() ?? 0.0,
      hostNetIncome: (map['hostNetPayout'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Duration-Driven Property Pricing Model with decoupled rate tiers and flexible security deposit policies.
class PropertyPricingModel {
  final double? dailyRate;
  final double? weeklyRate;
  final double? monthlyRate;
  final DepositType depositType;
  final double depositValue;

  const PropertyPricingModel({
    this.dailyRate,
    this.weeklyRate,
    this.monthlyRate,
    this.depositType = DepositType.none,
    this.depositValue = 0.0,
  });

  /// Factory from a property listing map or model
  factory PropertyPricingModel.fromPropertyMap(Map<String, dynamic> map) {
    final daily = (map['priceDaily'] as num?)?.toDouble() ??
        (map['dailyRate'] as num?)?.toDouble();
    final weekly = (map['priceWeekly'] as num?)?.toDouble() ??
        (map['weeklyRate'] as num?)?.toDouble();
    final monthly = (map['priceMonthly'] as num?)?.toDouble() ??
        (map['monthlyRate'] as num?)?.toDouble();

    DepositType dType = DepositType.none;
    double dVal = 0.0;

    if (map['securityDepositPolicy'] is Map) {
      final policy = map['securityDepositPolicy'] as Map<String, dynamic>;
      dType = DepositTypeHelper.fromString(policy['type'] as String?);
      dVal = (policy['value'] as num?)?.toDouble() ?? 0.0;
    } else if (map['depositType'] != null) {
      dType = DepositTypeHelper.fromString(map['depositType'] as String?);
      dVal = (map['depositValue'] as num?)?.toDouble() ?? 0.0;
    } else if (map['securityDepositAmount'] != null && (map['securityDepositAmount'] as num) > 0) {
      dType = DepositType.fixed;
      dVal = (map['securityDepositAmount'] as num).toDouble();
    } else if (map['depositMonths'] != null && (map['depositMonths'] as num) > 0 && monthly != null && monthly > 0) {
      dType = DepositType.fixed;
      dVal = (map['depositMonths'] as num).toDouble() * monthly;
    }

    return PropertyPricingModel(
      dailyRate: daily,
      weeklyRate: weekly,
      monthlyRate: monthly,
      depositType: dType,
      depositValue: dVal,
    );
  }

  /// Calculates the complete financial breakdown for a rental duration in days.
  /// [customerPlatformFeeRate] and [hostCommissionRate] default to platform admin defaults (3% and 7%).
  BookingFinancials calculate({
    required int totalDays,
    double? customerPlatformFeeRate,
    double? hostCommissionRate,
  }) {
    if (totalDays <= 0) totalDays = 1;

    final double custFeeRate = customerPlatformFeeRate ?? 0.03;
    final double hostCommRate = hostCommissionRate ?? 0.07;

    double baseRent = 0.0;
    double unitRate = 0.0;
    DurationTier appliedTier;

    // 1. Duration-Driven Base Rent Determination
    if (totalDays >= 30 && monthlyRate != null && monthlyRate! > 0) {
      appliedTier = DurationTier.monthly;
      unitRate = monthlyRate!;
      final months = totalDays ~/ 30;
      final remainingDays = totalDays % 30;
      final dailyFallback = dailyRate ?? (weeklyRate != null && weeklyRate! > 0 ? weeklyRate! / 7 : monthlyRate! / 30);
      baseRent = (months * monthlyRate!) + (remainingDays * dailyFallback);
    } else if (totalDays >= 7 && weeklyRate != null && weeklyRate! > 0) {
      appliedTier = DurationTier.weekly;
      unitRate = weeklyRate!;
      final weeks = totalDays ~/ 7;
      final remainingDays = totalDays % 7;
      final dailyFallback = dailyRate ?? (weeklyRate! / 7);
      baseRent = (weeks * weeklyRate!) + (remainingDays * dailyFallback);
    } else {
      appliedTier = DurationTier.daily;
      final rate = dailyRate ?? (weeklyRate != null && weeklyRate! > 0 ? weeklyRate! / 7 : (monthlyRate != null && monthlyRate! > 0 ? monthlyRate! / 30 : 0.0));
      unitRate = rate;
      baseRent = rate * totalDays;
    }

    // 2. Security Deposit Calculation (Exempt from TRANYX commissions/platform fees)
    double depositAmount = 0.0;
    switch (depositType) {
      case DepositType.fixed:
        depositAmount = depositValue;
        break;
      case DepositType.percentage:
        depositAmount = baseRent * (depositValue / 100.0);
        break;
      case DepositType.none:
        depositAmount = 0.0;
        break;
    }

    baseRent = _round2(baseRent);
    depositAmount = _round2(depositAmount);

    // 3. Platform Fees & Host Payouts
    final customerPlatformFee = _round2(baseRent * custFeeRate);
    final hostCommission = _round2(baseRent * hostCommRate);
    final totalCustomerPayable = _round2(baseRent + customerPlatformFee + depositAmount);
    final hostNetIncome = _round2(baseRent - hostCommission);

    return BookingFinancials(
      appliedTier: appliedTier,
      totalDays: totalDays,
      unitRate: unitRate,
      baseRent: baseRent,
      securityDeposit: depositAmount,
      depositType: depositType,
      depositValue: depositValue,
      customerPlatformFeeRate: custFeeRate,
      customerPlatformFee: customerPlatformFee,
      totalCustomerPayable: totalCustomerPayable,
      hostCommissionRate: hostCommRate,
      hostCommission: hostCommission,
      hostNetIncome: hostNetIncome,
    );
  }

  static double _round2(double val) {
    return double.parse(val.toStringAsFixed(2));
  }
}
