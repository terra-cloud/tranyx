import 'platform_fee_config.dart';

enum TransactionOriginRail {
  mwaOnChain,
  internalBalance,
  manualP2p,
}

enum WalletTransactionType {
  mwaEscrowRelease,
  onChainPayment,
  subscription,
  listingFee,
  feeDeduction,
  payout,
  deposit,
  withdraw,
  refund,
  unknown,
}

class WalletTransaction {
  final String id;
  final String uid;
  final String title;
  final String desc;
  final double amount;
  final double? feeAmount;
  final double? netAmount;
  final double? cryptoAmount;
  final String? cryptoCurrency; // 'SOL', 'USDT', 'TYXBIT'
  final String? solanaTxSignature;
  final TransactionOriginRail originRail;
  final WalletTransactionType transactionType;
  final String status; // 'Completed', 'Successful', 'Pending', 'PENDING_VERIFICATION', 'APPROVED', 'REJECTED', 'Failed'
  final int createdAt; // epoch ms
  final String? walletPublicKey;
  final String? method;
  final String? referenceNumber;
  final String? proofImageUrl;
  final String? rejectionReason;
  final String? adminUid;
  final int? verifiedAt;

  // Detailed Fee & Breakdown Fields
  final double? baseAmount;
  final double? transactionFee;
  final double? convenienceFee;
  final double? commissionFee;
  final double? serviceFeeAmount;
  final double? markupAmount;
  final double? bookingFee;
  final double? listingFee;
  final double? holdbackAmount;
  final double? discountAmount;
  final String? promoCode;
  final double? driverFee;

  // Snapshotted Fee Rates (Exact rates applied at transaction time)
  final double? transactionFeeRate;
  final double? convenienceFeeRate;
  final double? commissionRate;
  final double? serviceFeeRate;
  final double? markupRate;
  final double? bookingFeeRate;
  final double? listingFeeRate;
  final double? holdbackRate;

  const WalletTransaction({
    required this.id,
    required this.uid,
    required this.title,
    required this.desc,
    required this.amount,
    this.feeAmount,
    this.netAmount,
    this.cryptoAmount,
    this.cryptoCurrency,
    this.solanaTxSignature,
    required this.originRail,
    required this.transactionType,
    required this.status,
    required this.createdAt,
    this.walletPublicKey,
    this.method,
    this.referenceNumber,
    this.proofImageUrl,
    this.rejectionReason,
    this.adminUid,
    this.verifiedAt,
    this.baseAmount,
    this.transactionFee,
    this.convenienceFee,
    this.commissionFee,
    this.serviceFeeAmount,
    this.markupAmount,
    this.bookingFee,
    this.listingFee,
    this.holdbackAmount,
    this.discountAmount,
    this.promoCode,
    this.driverFee,
    this.transactionFeeRate,
    this.convenienceFeeRate,
    this.commissionRate,
    this.serviceFeeRate,
    this.markupRate,
    this.bookingFeeRate,
    this.listingFeeRate,
    this.holdbackRate,
  });

  /// Factory parser with backwards compatibility for legacy transaction documents.
  factory WalletTransaction.fromMap(Map<String, dynamic> map, {String? docId}) {
    final id = (docId ?? map['id'] ?? map['txId'] ?? '').toString();
    final uid = (map['uid'] ?? '').toString();
    final title = (map['title'] ?? 'Transaction').toString();
    final desc = (map['desc'] ?? map['description'] ?? '').toString();
    final rawAmount = (map['amount'] as num?)?.toDouble() ?? 0.0;
    final feeAmount = (map['feeAmount'] as num?)?.toDouble();
    final netAmount = (map['netAmount'] as num?)?.toDouble();

    final cryptoAmount = (map['cryptoAmount'] as num?)?.toDouble() ??
        (map['solAmount'] as num?)?.toDouble() ??
        (map['usdtAmount'] as num?)?.toDouble();

    final cryptoCurrency = map['cryptoCurrency'] as String? ??
        map['coin'] as String? ??
        (map['solAmount'] != null ? 'SOL' : (map['usdtAmount'] != null ? 'USDT' : null));

    final method = (map['method'] ?? map['paymentMethod']) as String?;
    final rawType = (map['type'] ?? '').toString().toLowerCase();

    final rawSolanaTxSignature = (map['solanaTxSignature'] ??
            map['txSignature'] ??
            map['signature'] ??
            map['solanaSignature']) as String?;

    final isP2p = map['originRail'] == 'manual_p2p' ||
        map['originRail'] == 'manualP2p' ||
        map['originRail'] == 'p2p' ||
        map['depositRequestId'] != null ||
        id.startsWith('p2p_') ||
        (method != null &&
            (method.toLowerCase().contains('gcash') ||
                method.toLowerCase().contains('maya') ||
                method.toLowerCase().contains('p2p'))) ||
        desc.toLowerCase().contains('gcash') ||
        desc.toLowerCase().contains('maya') ||
        desc.toLowerCase().contains('p2p');

    // Determine Origin Rail
    TransactionOriginRail rail;
    if (isP2p) {
      rail = TransactionOriginRail.manualP2p;
    } else if (map['originRail'] == 'mwa_on_chain' ||
        map['originRail'] == 'mwaOnChain' ||
        rawSolanaTxSignature != null ||
        (method != null && (method.toLowerCase().contains('solana') ||
            method.toLowerCase().contains('phantom') ||
            method.toLowerCase().contains('solflare') ||
            method.toLowerCase().contains('trust')))) {
      rail = TransactionOriginRail.mwaOnChain;
    } else {
      rail = TransactionOriginRail.internalBalance;
    }

    final solanaTxSignature = rail == TransactionOriginRail.mwaOnChain ? rawSolanaTxSignature : null;

    // Determine Transaction Type
    WalletTransactionType txType;
    if (rawType.contains('refund') || rawType == 'refund' || rawType == 'job_escrow_refund') {
      txType = WalletTransactionType.refund;
    } else if (rawType.contains('fee_deduction') || rawType == 'fee' || rawType == 'fees' || rawType == 'fee_deductions') {
      txType = WalletTransactionType.feeDeduction;
    } else if (rawType.contains('payout') || rawType == 'payout_released') {
      txType = WalletTransactionType.payout;
    } else if (rawType.contains('escrow') || rawType == 'mwa_escrow_release') {
      txType = WalletTransactionType.mwaEscrowRelease;
    } else if (rawType == 'on_chain_payment' || rawType == 'onchain_payment') {
      txType = WalletTransactionType.onChainPayment;
    } else if (rawType == 'subscription') {
      txType = WalletTransactionType.subscription;
    } else if (rawType == 'listing_fee') {
      txType = WalletTransactionType.listingFee;
    } else if (rawType == 'deposit' || rawType.contains('topup') || rawType.contains('p2p')) {
      txType = WalletTransactionType.deposit;
    } else if (rawType == 'withdraw' || rawType.contains('withdrawal')) {
      txType = WalletTransactionType.withdraw;
    } else {
      txType = WalletTransactionType.unknown;
    }

    final status = (map['status'] ?? 'Completed').toString();
    final createdAtRaw = map['createdAt'];
    int createdAt = 0;
    if (createdAtRaw is num) {
      createdAt = createdAtRaw.toInt();
    } else if (createdAtRaw is DateTime) {
      createdAt = createdAtRaw.millisecondsSinceEpoch;
    }

    final verifiedAtRaw = map['verifiedAt'] ?? map['approvedAt'] ?? map['rejectedAt'];
    int? verifiedAt;
    if (verifiedAtRaw is num) {
      verifiedAt = verifiedAtRaw.toInt();
    } else if (verifiedAtRaw is DateTime) {
      verifiedAt = verifiedAtRaw.millisecondsSinceEpoch;
    }

    final baseAmount = (map['baseAmount'] as num?)?.toDouble() ??
        (map['principal'] as num?)?.toDouble() ??
        (map['budget'] as num?)?.toDouble();
    final transactionFee = (map['transactionFee'] as num?)?.toDouble() ??
        (map['txFee'] as num?)?.toDouble();
    final convenienceFee = (map['convenienceFee'] as num?)?.toDouble() ??
        (map['convFee'] as num?)?.toDouble();
    final commissionFee = (map['commissionFee'] as num?)?.toDouble() ??
        (map['platformCommission'] as num?)?.toDouble() ??
        (map['nyxianFee'] as num?)?.toDouble();
    final serviceFeeAmount = (map['serviceFeeAmount'] as num?)?.toDouble() ??
        (map['serviceFee'] as num?)?.toDouble();
    final markupAmount = (map['markupAmount'] as num?)?.toDouble() ??
        (map['markup'] as num?)?.toDouble();
    final bookingFee = (map['bookingFee'] as num?)?.toDouble();
    final listingFee = (map['listingFee'] as num?)?.toDouble();
    final holdbackAmount = (map['holdbackAmount'] as num?)?.toDouble() ??
        (map['inspectionHoldback'] as num?)?.toDouble();
    final discountAmount = (map['discountAmount'] as num?)?.toDouble() ??
        (map['discount'] as num?)?.toDouble();
    final promoCode = map['promoCode'] as String?;
    final driverFee = (map['driverFee'] as num?)?.toDouble() ??
        (map['driverServicesFee'] as num?)?.toDouble();

    // Snapshotted rate percentages
    final transactionFeeRate = (map['transactionFeeRate'] as num?)?.toDouble() ??
        (map['txFeeRate'] as num?)?.toDouble();
    final convenienceFeeRate = (map['convenienceFeeRate'] as num?)?.toDouble() ??
        (map['convFeeRate'] as num?)?.toDouble();
    final commissionRate = (map['commissionRate'] as num?)?.toDouble() ??
        (map['platformCommissionRate'] as num?)?.toDouble();
    final serviceFeeRate = (map['serviceFeeRate'] as num?)?.toDouble();
    final markupRate = (map['markupRate'] as num?)?.toDouble();
    final bookingFeeRate = (map['bookingFeeRate'] as num?)?.toDouble();
    final listingFeeRate = (map['listingFeeRate'] as num?)?.toDouble();
    final holdbackRate = (map['holdbackRate'] as num?)?.toDouble();

    return WalletTransaction(
      id: id,
      uid: uid,
      title: title,
      desc: desc,
      amount: rawAmount,
      feeAmount: feeAmount,
      netAmount: netAmount,
      cryptoAmount: cryptoAmount,
      cryptoCurrency: cryptoCurrency,
      solanaTxSignature: solanaTxSignature,
      originRail: rail,
      transactionType: txType,
      status: status,
      createdAt: createdAt,
      walletPublicKey: map['walletPublicKey'] as String?,
      method: method,
      referenceNumber: (map['referenceNumber'] ?? map['refNumber']) as String?,
      proofImageUrl: (map['proofImageUrl'] ?? map['proofUrl'] ?? map['receiptUrl']) as String?,
      rejectionReason: (map['rejectionReason'] ?? map['reason']) as String?,
      adminUid: map['adminUid'] as String?,
      verifiedAt: verifiedAt,
      baseAmount: baseAmount,
      transactionFee: transactionFee,
      convenienceFee: convenienceFee,
      commissionFee: commissionFee,
      serviceFeeAmount: serviceFeeAmount,
      markupAmount: markupAmount,
      bookingFee: bookingFee,
      listingFee: listingFee,
      holdbackAmount: holdbackAmount,
      discountAmount: discountAmount,
      promoCode: promoCode,
      driverFee: driverFee,
      transactionFeeRate: transactionFeeRate,
      convenienceFeeRate: convenienceFeeRate,
      commissionRate: commissionRate,
      serviceFeeRate: serviceFeeRate,
      markupRate: markupRate,
      bookingFeeRate: bookingFeeRate,
      listingFeeRate: listingFeeRate,
      holdbackRate: holdbackRate,
    );
  }

  /// Whether this transaction has any fee breakdown or pricing components
  bool get hasBreakdown =>
      baseAmount != null ||
      transactionFee != null ||
      convenienceFee != null ||
      commissionFee != null ||
      serviceFeeAmount != null ||
      markupAmount != null ||
      bookingFee != null ||
      listingFee != null ||
      holdbackAmount != null ||
      driverFee != null ||
      discountAmount != null ||
      transactionType == WalletTransactionType.feeDeduction ||
      transactionType == WalletTransactionType.payout ||
      transactionType == WalletTransactionType.listingFee ||
      title.toLowerCase().contains('fee') ||
      title.toLowerCase().contains('payout');

  double get computedBaseAmount {
    if (baseAmount != null && baseAmount! > 0) return baseAmount!;
    if (transactionType == WalletTransactionType.feeDeduction || title.toLowerCase().contains('completion fee')) {
      final totalRate = effectiveTxFeeRate + effectiveConvFeeRate;
      return amount > 0 ? (amount / (totalRate > 0 ? totalRate : 0.10)) : 0.0;
    }
    if (transactionType == WalletTransactionType.payout || title.toLowerCase().contains('payout')) {
      final netRate = 1.0 - effectiveCommissionRate;
      return amount > 0 ? (amount / (netRate > 0 ? netRate : 0.97)) : 0.0;
    }
    return amount.abs();
  }

  // --- Effective Snapshotted Rates & Formatted Labels ---

  double get effectiveTxFeeRate {
    if (transactionFeeRate != null) return transactionFeeRate!;
    if (baseAmount != null && baseAmount! > 0 && transactionFee != null) {
      return transactionFee! / baseAmount!;
    }
    return 0.07;
  }

  double get effectiveConvFeeRate {
    if (convenienceFeeRate != null) return convenienceFeeRate!;
    if (baseAmount != null && baseAmount! > 0 && convenienceFee != null) {
      return convenienceFee! / baseAmount!;
    }
    return 0.03;
  }

  double get effectiveCommissionRate {
    if (commissionRate != null) return commissionRate!;
    if (baseAmount != null && baseAmount! > 0 && commissionFee != null) {
      return commissionFee! / baseAmount!;
    }
    return 0.03;
  }

  double get effectiveServiceFeeRate {
    if (serviceFeeRate != null) return serviceFeeRate!;
    if (baseAmount != null && baseAmount! > 0 && serviceFeeAmount != null) {
      return serviceFeeAmount! / baseAmount!;
    }
    return 0.01;
  }

  double get effectiveMarkupRate {
    if (markupRate != null) return markupRate!;
    if (baseAmount != null && baseAmount! > 0 && markupAmount != null) {
      return markupAmount! / baseAmount!;
    }
    return 0.03;
  }

  double get effectiveBookingFeeRate {
    if (bookingFeeRate != null) return bookingFeeRate!;
    if (baseAmount != null && baseAmount! > 0 && bookingFee != null) {
      return bookingFee! / baseAmount!;
    }
    return 0.03;
  }

  double get effectiveListingFeeRate {
    if (listingFeeRate != null) return listingFeeRate!;
    if (baseAmount != null && baseAmount! > 0 && listingFee != null) {
      return listingFee! / baseAmount!;
    }
    return 0.015;
  }

  String get txFeePercentLabel => PlatformFeeConfig.formatPercent(effectiveTxFeeRate);
  String get convFeePercentLabel => PlatformFeeConfig.formatPercent(effectiveConvFeeRate);
  String get commissionPercentLabel => PlatformFeeConfig.formatPercent(effectiveCommissionRate);
  String get serviceFeePercentLabel => PlatformFeeConfig.formatPercent(effectiveServiceFeeRate);
  String get markupPercentLabel => PlatformFeeConfig.formatPercent(effectiveMarkupRate);
  String get bookingFeePercentLabel => PlatformFeeConfig.formatPercent(effectiveBookingFeeRate);
  String get listingFeePercentLabel => PlatformFeeConfig.formatPercent(effectiveListingFeeRate);
  String get totalEmployerFeesPercentLabel =>
      PlatformFeeConfig.formatPercent(effectiveTxFeeRate + effectiveConvFeeRate);

  double get computedTxFee {
    if (transactionFee != null && transactionFee! > 0) return transactionFee!;
    if (transactionType == WalletTransactionType.feeDeduction || title.toLowerCase().contains('completion fee')) {
      return computedBaseAmount * effectiveTxFeeRate;
    }
    return 0.0;
  }

  double get computedConvFee {
    if (convenienceFee != null && convenienceFee! > 0) return convenienceFee!;
    if (transactionType == WalletTransactionType.feeDeduction || title.toLowerCase().contains('completion fee')) {
      return computedBaseAmount * effectiveConvFeeRate;
    }
    return 0.0;
  }

  double get computedCommissionFee {
    if (commissionFee != null && commissionFee! > 0) return commissionFee!;
    if (transactionType == WalletTransactionType.payout || title.toLowerCase().contains('payout')) {
      return computedBaseAmount * effectiveCommissionRate;
    }
    return 0.0;
  }

  double get computedServiceFee {
    if (serviceFeeAmount != null && serviceFeeAmount! > 0) return serviceFeeAmount!;
    return computedBaseAmount * effectiveServiceFeeRate;
  }

  double get computedMarkup {
    if (markupAmount != null && markupAmount! > 0) return markupAmount!;
    return computedBaseAmount * effectiveMarkupRate;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'title': title,
      'desc': desc,
      'amount': amount,
      if (feeAmount != null) 'feeAmount': feeAmount,
      if (netAmount != null) 'netAmount': netAmount,
      if (cryptoAmount != null) 'cryptoAmount': cryptoAmount,
      if (cryptoCurrency != null) 'cryptoCurrency': cryptoCurrency,
      if (solanaTxSignature != null) 'solanaTxSignature': solanaTxSignature,
      'originRail': originRail == TransactionOriginRail.mwaOnChain
          ? 'mwa_on_chain'
          : (originRail == TransactionOriginRail.manualP2p
              ? 'manual_p2p'
              : 'internal_balance'),
      'type': transactionType.name,
      'status': status,
      'createdAt': createdAt,
      if (walletPublicKey != null) 'walletPublicKey': walletPublicKey,
      if (method != null) 'method': method,
      if (referenceNumber != null) 'referenceNumber': referenceNumber,
      if (proofImageUrl != null) 'proofImageUrl': proofImageUrl,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (adminUid != null) 'adminUid': adminUid,
      if (verifiedAt != null) 'verifiedAt': verifiedAt,
      if (baseAmount != null) 'baseAmount': baseAmount,
      if (transactionFee != null) 'transactionFee': transactionFee,
      if (convenienceFee != null) 'convenienceFee': convenienceFee,
      if (commissionFee != null) 'commissionFee': commissionFee,
      if (serviceFeeAmount != null) 'serviceFeeAmount': serviceFeeAmount,
      if (markupAmount != null) 'markupAmount': markupAmount,
      if (bookingFee != null) 'bookingFee': bookingFee,
      if (listingFee != null) 'listingFee': listingFee,
      if (holdbackAmount != null) 'holdbackAmount': holdbackAmount,
      if (discountAmount != null) 'discountAmount': discountAmount,
      if (promoCode != null) 'promoCode': promoCode,
      if (driverFee != null) 'driverFee': driverFee,
      if (transactionFeeRate != null) 'transactionFeeRate': transactionFeeRate,
      if (convenienceFeeRate != null) 'convenienceFeeRate': convenienceFeeRate,
      if (commissionRate != null) 'commissionRate': commissionRate,
      if (serviceFeeRate != null) 'serviceFeeRate': serviceFeeRate,
      if (markupRate != null) 'markupRate': markupRate,
      if (bookingFeeRate != null) 'bookingFeeRate': bookingFeeRate,
      if (listingFeeRate != null) 'listingFeeRate': listingFeeRate,
      if (holdbackRate != null) 'holdbackRate': holdbackRate,
    };
  }

  /// Returns the Solana Explorer URL for on-chain transactions.
  static String getSolanaExplorerUrl({
    required String signature,
    required String environment, // 'dev', 'uat', 'production'
  }) {
    final env = environment.toLowerCase();
    if (env.contains('dev')) {
      return 'https://explorer.solana.com/tx/$signature?cluster=devnet';
    } else if (env.contains('uat') || env.contains('test')) {
      return 'https://explorer.solana.com/tx/$signature?cluster=testnet';
    } else {
      return 'https://explorer.solana.com/tx/$signature';
    }
  }
}
