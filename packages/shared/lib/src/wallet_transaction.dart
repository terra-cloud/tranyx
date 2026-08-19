enum TransactionOriginRail {
  mwaOnChain,
  gcashXendit,
  internalBalance,
}

enum WalletTransactionType {
  mwaEscrowRelease,
  onChainPayment,
  fiatTopup,
  fiatWithdrawal,
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
  final String? xenditReferenceId;
  final String? xenditChannel; // 'GCASH'
  final TransactionOriginRail originRail;
  final WalletTransactionType transactionType;
  final String status; // 'Completed', 'Successful', 'Pending', 'Failed'
  final int createdAt; // epoch ms
  final String? walletPublicKey;
  final String? method;

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
    this.xenditReferenceId,
    this.xenditChannel,
    required this.originRail,
    required this.transactionType,
    required this.status,
    required this.createdAt,
    this.walletPublicKey,
    this.method,
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

    final solanaTxSignature = (map['solanaTxSignature'] ??
            map['txSignature'] ??
            map['signature'] ??
            map['solanaSignature']) as String?;

    final xenditReferenceId = (map['xenditReferenceId'] ??
            map['invoiceId'] ??
            map['xenditInvoiceId']) as String?;

    final xenditChannel = (map['xenditChannel'] ??
            (map['method'] == 'GCash' || map['method'] == 'Xendit' ? 'GCASH' : null)) as String?;

    final method = map['method'] as String?;
    final rawType = (map['type'] ?? '').toString().toLowerCase();

    // Determine Origin Rail
    TransactionOriginRail rail;
    if (map['originRail'] == 'mwa_on_chain' ||
        map['originRail'] == 'mwaOnChain' ||
        solanaTxSignature != null ||
        (method != null && (method.toLowerCase().contains('solana') ||
            method.toLowerCase().contains('phantom') ||
            method.toLowerCase().contains('solflare') ||
            method.toLowerCase().contains('trust')))) {
      rail = TransactionOriginRail.mwaOnChain;
    } else if (map['originRail'] == 'gcash_xendit' ||
        map['originRail'] == 'gcashXendit' ||
        xenditReferenceId != null ||
        (method != null && (method.toLowerCase().contains('xendit') ||
            method.toLowerCase().contains('gcash')))) {
      rail = TransactionOriginRail.gcashXendit;
    } else {
      rail = TransactionOriginRail.internalBalance;
    }

    // Determine Transaction Type
    WalletTransactionType txType;
    if (rawType.contains('escrow') || rawType == 'mwa_escrow_release') {
      txType = WalletTransactionType.mwaEscrowRelease;
    } else if (rawType == 'on_chain_payment' || rawType == 'onchain_payment') {
      txType = WalletTransactionType.onChainPayment;
    } else if (rawType == 'subscription') {
      txType = WalletTransactionType.subscription;
    } else if (rawType == 'listing_fee') {
      txType = WalletTransactionType.listingFee;
    } else if (rawType == 'refund') {
      txType = WalletTransactionType.refund;
    } else if (rawType == 'deposit' || rawType.contains('topup')) {
      txType = rail == TransactionOriginRail.gcashXendit
          ? WalletTransactionType.fiatTopup
          : WalletTransactionType.deposit;
    } else if (rawType == 'withdraw' || rawType.contains('withdrawal')) {
      txType = rail == TransactionOriginRail.gcashXendit
          ? WalletTransactionType.fiatWithdrawal
          : WalletTransactionType.withdraw;
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
      xenditReferenceId: xenditReferenceId,
      xenditChannel: xenditChannel,
      originRail: rail,
      transactionType: txType,
      status: status,
      createdAt: createdAt,
      walletPublicKey: map['walletPublicKey'] as String?,
      method: method,
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
      if (xenditReferenceId != null) 'xenditReferenceId': xenditReferenceId,
      if (xenditChannel != null) 'xenditChannel': xenditChannel,
      'originRail': originRail == TransactionOriginRail.mwaOnChain
          ? 'mwa_on_chain'
          : originRail == TransactionOriginRail.gcashXendit
              ? 'gcash_xendit'
              : 'internal_balance',
      'type': transactionType.name,
      'status': status,
      'createdAt': createdAt,
      if (walletPublicKey != null) 'walletPublicKey': walletPublicKey,
      if (method != null) 'method': method,
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
