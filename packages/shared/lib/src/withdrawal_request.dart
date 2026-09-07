class WithdrawalRequest {
  final String id;
  final String uid;
  final String userName;
  final String userEmail;
  final double amount;
  final double feeAmount;
  final double netAmount;
  final String paymentMethod; // 'GCash' or 'Maya'
  final String userAccountName;
  final String userAccountNumber;
  final String userQrUrl;
  final String referenceNumber;
  final String proofImageUrl;
  final String status; // 'WAITING_FOR_AGENT', 'AWAITING_AGENT_PAYMENT', 'PENDING_CONFIRMATION', 'APPROVED', 'REJECTED', 'CANCELLED'
  final String? rejectionReason;
  final String? adminUid;
  final String? agentId;
  final String? agentName;
  final String? agentPhone;
  final int createdAt;
  final int? claimedAt;
  final int? proofSubmittedAt;
  final int? verifiedAt;

  const WithdrawalRequest({
    required this.id,
    required this.uid,
    required this.userName,
    required this.userEmail,
    required this.amount,
    this.feeAmount = 0.0,
    this.netAmount = 0.0,
    required this.paymentMethod,
    required this.userAccountName,
    required this.userAccountNumber,
    this.userQrUrl = '',
    this.referenceNumber = '',
    this.proofImageUrl = '',
    required this.status,
    this.rejectionReason,
    this.adminUid,
    this.agentId,
    this.agentName,
    this.agentPhone,
    required this.createdAt,
    this.claimedAt,
    this.proofSubmittedAt,
    this.verifiedAt,
  });

  factory WithdrawalRequest.fromMap(Map map, {String? docId}) {
    final createdAtRaw = map['createdAt'];
    int createdAt = 0;
    if (createdAtRaw is num) {
      createdAt = createdAtRaw.toInt();
    } else if (createdAtRaw is DateTime) {
      createdAt = createdAtRaw.millisecondsSinceEpoch;
    }

    final claimedAtRaw = map['claimedAt'];
    int? claimedAt;
    if (claimedAtRaw is num) {
      claimedAt = claimedAtRaw.toInt();
    } else if (claimedAtRaw is DateTime) {
      claimedAt = claimedAtRaw.millisecondsSinceEpoch;
    }

    final proofSubmittedAtRaw = map['proofSubmittedAt'];
    int? proofSubmittedAt;
    if (proofSubmittedAtRaw is num) {
      proofSubmittedAt = proofSubmittedAtRaw.toInt();
    } else if (proofSubmittedAtRaw is DateTime) {
      proofSubmittedAt = proofSubmittedAtRaw.millisecondsSinceEpoch;
    }

    final verifiedAtRaw = map['verifiedAt'] ?? map['approvedAt'] ?? map['rejectedAt'];
    int? verifiedAt;
    if (verifiedAtRaw is num) {
      verifiedAt = verifiedAtRaw.toInt();
    } else if (verifiedAtRaw is DateTime) {
      verifiedAt = verifiedAtRaw.millisecondsSinceEpoch;
    }

    final amount = (map['amount'] as num?)?.toDouble() ?? 0.0;
    final feeAmount = (map['feeAmount'] as num?)?.toDouble() ?? 0.0;
    final netAmount = (map['netAmount'] as num?)?.toDouble() ?? (amount - feeAmount);

    return WithdrawalRequest(
      id: (docId ?? map['id'] ?? '').toString(),
      uid: (map['uid'] ?? '').toString(),
      userName: (map['userName'] ?? map['name'] ?? 'User').toString(),
      userEmail: (map['userEmail'] ?? map['email'] ?? '').toString(),
      amount: amount,
      feeAmount: feeAmount,
      netAmount: netAmount,
      paymentMethod: (map['paymentMethod'] ?? map['method'] ?? 'GCash').toString(),
      userAccountName: (map['userAccountName'] ?? map['accountName'] ?? '').toString(),
      userAccountNumber: (map['userAccountNumber'] ?? map['accountNumber'] ?? map['phoneNumber'] ?? '').toString(),
      userQrUrl: (map['userQrUrl'] ?? map['qrUrl'] ?? '').toString(),
      referenceNumber: (map['referenceNumber'] ?? map['refNumber'] ?? '').toString(),
      proofImageUrl: (map['proofImageUrl'] ?? map['proofUrl'] ?? map['receiptUrl'] ?? '').toString(),
      status: (map['status'] ?? 'WAITING_FOR_AGENT').toString(),
      rejectionReason: (map['rejectionReason'] ?? map['reason']) as String?,
      adminUid: map['adminUid'] as String?,
      agentId: (map['agentId'] ?? map['assignedAgentId']) as String?,
      agentName: (map['agentName'] ?? map['assignedAgentName']) as String?,
      agentPhone: (map['agentPhone'] ?? map['assignedAgentPhone']) as String?,
      createdAt: createdAt,
      claimedAt: claimedAt,
      proofSubmittedAt: proofSubmittedAt,
      verifiedAt: verifiedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'userName': userName,
      'userEmail': userEmail,
      'amount': amount,
      'feeAmount': feeAmount,
      'netAmount': netAmount,
      'paymentMethod': paymentMethod,
      'userAccountName': userAccountName,
      'userAccountNumber': userAccountNumber,
      'userQrUrl': userQrUrl,
      'referenceNumber': referenceNumber,
      'proofImageUrl': proofImageUrl,
      'status': status,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (adminUid != null) 'adminUid': adminUid,
      if (agentId != null) 'agentId': agentId,
      if (agentName != null) 'agentName': agentName,
      if (agentPhone != null) 'agentPhone': agentPhone,
      'createdAt': createdAt,
      if (claimedAt != null) 'claimedAt': claimedAt,
      if (proofSubmittedAt != null) 'proofSubmittedAt': proofSubmittedAt,
      if (verifiedAt != null) 'verifiedAt': verifiedAt,
    };
  }

  WithdrawalRequest copyWith({
    String? id,
    String? uid,
    String? userName,
    String? userEmail,
    double? amount,
    double? feeAmount,
    double? netAmount,
    String? paymentMethod,
    String? userAccountName,
    String? userAccountNumber,
    String? userQrUrl,
    String? referenceNumber,
    String? proofImageUrl,
    String? status,
    String? rejectionReason,
    String? adminUid,
    String? agentId,
    String? agentName,
    String? agentPhone,
    int? createdAt,
    int? claimedAt,
    int? proofSubmittedAt,
    int? verifiedAt,
  }) {
    return WithdrawalRequest(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      amount: amount ?? this.amount,
      feeAmount: feeAmount ?? this.feeAmount,
      netAmount: netAmount ?? this.netAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      userAccountName: userAccountName ?? this.userAccountName,
      userAccountNumber: userAccountNumber ?? this.userAccountNumber,
      userQrUrl: userQrUrl ?? this.userQrUrl,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      proofImageUrl: proofImageUrl ?? this.proofImageUrl,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      adminUid: adminUid ?? this.adminUid,
      agentId: agentId ?? this.agentId,
      agentName: agentName ?? this.agentName,
      agentPhone: agentPhone ?? this.agentPhone,
      createdAt: createdAt ?? this.createdAt,
      claimedAt: claimedAt ?? this.claimedAt,
      proofSubmittedAt: proofSubmittedAt ?? this.proofSubmittedAt,
      verifiedAt: verifiedAt ?? this.verifiedAt,
    );
  }
}
