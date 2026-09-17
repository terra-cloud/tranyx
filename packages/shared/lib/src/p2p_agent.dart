/// Model representing a P2P Deposit Agent in Tranyx
class P2pAgent {
  final String agentId;
  final String name;
  final String email;
  final String phone;
  final bool isActive;
  final String gcashAccountName;
  final String gcashNumber;
  final String gcashQrUrl;
  final String mayaAccountName;
  final String mayaNumber;
  final String mayaQrUrl;
  final int completedDeposits;
  final double totalProcessedAmount;
  final int updatedAt;

  const P2pAgent({
    required this.agentId,
    required this.name,
    this.email = '',
    this.phone = '',
    this.isActive = true,
    required this.gcashAccountName,
    required this.gcashNumber,
    required this.gcashQrUrl,
    required this.mayaAccountName,
    required this.mayaNumber,
    required this.mayaQrUrl,
    this.completedDeposits = 0,
    this.totalProcessedAmount = 0.0,
    required this.updatedAt,
  });

  /// Factory fallback for default designated official Tranyx Agent
  factory P2pAgent.defaultAgent() {
    return P2pAgent(
      agentId: 'official_tranyx_agent',
      name: 'TRANYX Official Desk (Zeus C.)',
      email: 'p2p-ops@tranyx.ph',
      phone: '0917 890 1234',
      isActive: true,
      gcashAccountName: 'TRANYX OFFICIAL / ZEUS C.',
      gcashNumber: '0917 890 1234',
      gcashQrUrl: 'https://api.qrserver.com/v1/create-qr-code/?size=350x350&data=00020101021126580014ph.com.gcash0111091789012345204599953036085802PH5915TRANYX+OFFICIAL6011PASIG+CITY6304C63E',
      mayaAccountName: 'TRANYX CORP / ZEUS C.',
      mayaNumber: '0918 901 2345',
      mayaQrUrl: 'https://api.qrserver.com/v1/create-qr-code/?size=350x350&data=00020101021126560012ph.maya.pay0111091890123455204599953036085802PH5911TRANYX+CORP6011PASIG+CITY63049F2D',
      completedDeposits: 142,
      totalProcessedAmount: 285400.0,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory P2pAgent.fromMap(Map map, {String? docId}) {
    final updatedAtRaw = map['updatedAt'] ?? map['createdAt'];
    int updatedAt = 0;
    if (updatedAtRaw is num) {
      updatedAt = updatedAtRaw.toInt();
    } else if (updatedAtRaw is DateTime) {
      updatedAt = updatedAtRaw.millisecondsSinceEpoch;
    }

    return P2pAgent(
      agentId: (docId ?? map['agentId'] ?? map['id'] ?? 'official_tranyx_agent').toString(),
      name: (map['name'] ?? map['agentName'] ?? 'TRANYX Official Desk').toString(),
      email: (map['email'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      isActive: map['isActive'] as bool? ?? true,
      gcashAccountName: (map['gcashAccountName'] ?? 'TRANYX OFFICIAL / ZEUS C.').toString(),
      gcashNumber: (map['gcashNumber'] ?? '0917 890 1234').toString(),
      gcashQrUrl: (map['gcashQrUrl'] ?? '').toString().isNotEmpty
          ? map['gcashQrUrl'].toString()
          : P2pAgent.defaultAgent().gcashQrUrl,
      mayaAccountName: (map['mayaAccountName'] ?? 'TRANYX CORP / ZEUS C.').toString(),
      mayaNumber: (map['mayaNumber'] ?? '0918 901 2345').toString(),
      mayaQrUrl: (map['mayaQrUrl'] ?? '').toString().isNotEmpty
          ? map['mayaQrUrl'].toString()
          : P2pAgent.defaultAgent().mayaQrUrl,
      completedDeposits: (map['completedDeposits'] as num?)?.toInt() ?? 0,
      totalProcessedAmount: (map['totalProcessedAmount'] as num?)?.toDouble() ?? 0.0,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'agentId': agentId,
      'name': name,
      'email': email,
      'phone': phone,
      'isActive': isActive,
      'gcashAccountName': gcashAccountName,
      'gcashNumber': gcashNumber,
      'gcashQrUrl': gcashQrUrl,
      'mayaAccountName': mayaAccountName,
      'mayaNumber': mayaNumber,
      'mayaQrUrl': mayaQrUrl,
      'completedDeposits': completedDeposits,
      'totalProcessedAmount': totalProcessedAmount,
      'updatedAt': updatedAt,
    };
  }

  P2pAgent copyWith({
    String? agentId,
    String? name,
    String? email,
    String? phone,
    bool? isActive,
    String? gcashAccountName,
    String? gcashNumber,
    String? gcashQrUrl,
    String? mayaAccountName,
    String? mayaNumber,
    String? mayaQrUrl,
    int? completedDeposits,
    double? totalProcessedAmount,
    int? updatedAt,
  }) {
    return P2pAgent(
      agentId: agentId ?? this.agentId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
      gcashAccountName: gcashAccountName ?? this.gcashAccountName,
      gcashNumber: gcashNumber ?? this.gcashNumber,
      gcashQrUrl: gcashQrUrl ?? this.gcashQrUrl,
      mayaAccountName: mayaAccountName ?? this.mayaAccountName,
      mayaNumber: mayaNumber ?? this.mayaNumber,
      mayaQrUrl: mayaQrUrl ?? this.mayaQrUrl,
      completedDeposits: completedDeposits ?? this.completedDeposits,
      totalProcessedAmount: totalProcessedAmount ?? this.totalProcessedAmount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Cleans raw agent display name or email into a human-friendly title.
/// e.g. "agent.juana2@tranyx.app" -> "Agent Juana", "juana.agent@tranyx.app" -> "Agent Juana"
String cleanAgentDisplayName(String? raw, {String fallback = 'TRANYX Agent'}) {
  if (raw == null || raw.trim().isEmpty) return fallback;
  var text = raw.trim();
  if (text.contains('@')) {
    text = text.split('@').first;
  }
  // Strip trailing digits (e.g. juana2 -> juana, agent1 -> agent)
  text = text.replaceAll(RegExp(r'\d+$'), '');
  final parts = text.split(RegExp(r'[._\-\s]+')).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return fallback;

  final formatted = parts
      .map((s) => s[0].toUpperCase() + (s.length > 1 ? s.substring(1).toLowerCase() : ''))
      .toList();

  if (formatted.any((p) => p.toLowerCase() == 'agent')) {
    formatted.removeWhere((p) => p.toLowerCase() == 'agent');
    if (formatted.isEmpty) return 'TRANYX Agent';
    return 'Agent ${formatted.join(' ')}';
  }
  return 'Agent ${formatted.join(' ')}';
}
