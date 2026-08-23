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
    );
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
