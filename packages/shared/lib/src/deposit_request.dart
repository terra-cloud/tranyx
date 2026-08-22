class DepositRequest {
  final String id;
  final String uid;
  final String userName;
  final String userEmail;
  final double amount;
  final String paymentMethod; // 'GCash' or 'Maya'
  final String referenceNumber;
  final String proofImageUrl;
  final String status; // 'WAITING_FOR_AGENT', 'AWAITING_PAYMENT', 'PENDING_VERIFICATION', 'APPROVED', 'REJECTED', 'CANCELLED'
  final String? rejectionReason;
  final String? adminUid;
  final String? agentId;
  final String? agentName;
  final String? agentAccountName;
  final String? agentAccountNumber;
  final String? agentQrUrl;
  final int createdAt;
  final int? qrSentAt;
  final int? proofSubmittedAt;
  final int? verifiedAt;

  const DepositRequest({
    required this.id,
    required this.uid,
    required this.userName,
    required this.userEmail,
    required this.amount,
    required this.paymentMethod,
    this.referenceNumber = '',
    this.proofImageUrl = '',
    required this.status,
    this.rejectionReason,
    this.adminUid,
    this.agentId,
    this.agentName,
    this.agentAccountName,
    this.agentAccountNumber,
    this.agentQrUrl,
    required this.createdAt,
    this.qrSentAt,
    this.proofSubmittedAt,
    this.verifiedAt,
  });

  factory DepositRequest.fromMap(Map<String, dynamic> map, {String? docId}) {
    final createdAtRaw = map['createdAt'];
    int createdAt = 0;
    if (createdAtRaw is num) {
      createdAt = createdAtRaw.toInt();
    } else if (createdAtRaw is DateTime) {
      createdAt = createdAtRaw.millisecondsSinceEpoch;
    }

    final qrSentAtRaw = map['qrSentAt'];
    int? qrSentAt;
    if (qrSentAtRaw is num) {
      qrSentAt = qrSentAtRaw.toInt();
    } else if (qrSentAtRaw is DateTime) {
      qrSentAt = qrSentAtRaw.millisecondsSinceEpoch;
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

    return DepositRequest(
      id: (docId ?? map['id'] ?? '').toString(),
      uid: (map['uid'] ?? '').toString(),
      userName: (map['userName'] ?? map['name'] ?? 'User').toString(),
      userEmail: (map['userEmail'] ?? map['email'] ?? '').toString(),
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: (map['paymentMethod'] ?? map['method'] ?? 'GCash').toString(),
      referenceNumber: (map['referenceNumber'] ?? map['refNumber'] ?? '').toString(),
      proofImageUrl: (map['proofImageUrl'] ?? map['proofUrl'] ?? map['receiptUrl'] ?? '').toString(),
      status: (map['status'] ?? 'WAITING_FOR_AGENT').toString(),
      rejectionReason: (map['rejectionReason'] ?? map['reason']) as String?,
      adminUid: map['adminUid'] as String?,
      agentId: (map['agentId'] ?? map['assignedAgentId']) as String?,
      agentName: (map['agentName'] ?? map['assignedAgentName']) as String?,
      agentAccountName: (map['agentAccountName'] ?? map['accountName']) as String?,
      agentAccountNumber: (map['agentAccountNumber'] ?? map['accountNumber'] ?? map['phoneNumber']) as String?,
      agentQrUrl: (map['agentQrUrl'] ?? map['qrUrl']) as String?,
      createdAt: createdAt,
      qrSentAt: qrSentAt,
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
      'paymentMethod': paymentMethod,
      'referenceNumber': referenceNumber,
      'proofImageUrl': proofImageUrl,
      'status': status,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (adminUid != null) 'adminUid': adminUid,
      if (agentId != null) 'agentId': agentId,
      if (agentName != null) 'agentName': agentName,
      if (agentAccountName != null) 'agentAccountName': agentAccountName,
      if (agentAccountNumber != null) 'agentAccountNumber': agentAccountNumber,
      if (agentQrUrl != null) 'agentQrUrl': agentQrUrl,
      'createdAt': createdAt,
      if (qrSentAt != null) 'qrSentAt': qrSentAt,
      if (proofSubmittedAt != null) 'proofSubmittedAt': proofSubmittedAt,
      if (verifiedAt != null) 'verifiedAt': verifiedAt,
    };
  }

  DepositRequest copyWith({
    String? id,
    String? uid,
    String? userName,
    String? userEmail,
    double? amount,
    String? paymentMethod,
    String? referenceNumber,
    String? proofImageUrl,
    String? status,
    String? rejectionReason,
    String? adminUid,
    String? agentId,
    String? agentName,
    String? agentAccountName,
    String? agentAccountNumber,
    String? agentQrUrl,
    int? createdAt,
    int? qrSentAt,
    int? proofSubmittedAt,
    int? verifiedAt,
  }) {
    return DepositRequest(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      amount: amount ?? this.amount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      proofImageUrl: proofImageUrl ?? this.proofImageUrl,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      adminUid: adminUid ?? this.adminUid,
      agentId: agentId ?? this.agentId,
      agentName: agentName ?? this.agentName,
      agentAccountName: agentAccountName ?? this.agentAccountName,
      agentAccountNumber: agentAccountNumber ?? this.agentAccountNumber,
      agentQrUrl: agentQrUrl ?? this.agentQrUrl,
      createdAt: createdAt ?? this.createdAt,
      qrSentAt: qrSentAt ?? this.qrSentAt,
      proofSubmittedAt: proofSubmittedAt ?? this.proofSubmittedAt,
      verifiedAt: verifiedAt ?? this.verifiedAt,
    );
  }
}
