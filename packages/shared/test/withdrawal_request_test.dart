import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('WithdrawalRequest Unit Tests', () {
    test('Correctly serializes and deserializes WithdrawalRequest', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final req = WithdrawalRequest(
        id: 'withdraw_123',
        uid: 'user_456',
        userName: 'Maria Santos',
        userEmail: 'maria@example.com',
        amount: 2500.0,
        feeAmount: 0.0,
        netAmount: 2500.0,
        paymentMethod: 'GCash',
        userAccountName: 'Maria Santos',
        userAccountNumber: '09171234567',
        userQrUrl: 'https://cdn.tranyx.com/user_qr.png',
        status: 'WAITING_FOR_AGENT',
        createdAt: now,
      );

      final map = req.toMap();
      expect(map['id'], 'withdraw_123');
      expect(map['uid'], 'user_456');
      expect(map['amount'], 2500.0);
      expect(map['paymentMethod'], 'GCash');
      expect(map['userAccountName'], 'Maria Santos');
      expect(map['userAccountNumber'], '09171234567');
      expect(map['userQrUrl'], 'https://cdn.tranyx.com/user_qr.png');
      expect(map['status'], 'WAITING_FOR_AGENT');

      final fromMap = WithdrawalRequest.fromMap(map, docId: 'withdraw_123');
      expect(fromMap.id, 'withdraw_123');
      expect(fromMap.userName, 'Maria Santos');
      expect(fromMap.amount, 2500.0);
      expect(fromMap.userAccountNumber, '09171234567');
      expect(fromMap.status, 'WAITING_FOR_AGENT');
    });

    test('Transitions through Agent Claiming, Proof Submission, and Completion', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      var req = WithdrawalRequest(
        id: 'withdraw_789',
        uid: 'user_111',
        userName: 'Carlos Reyes',
        userEmail: 'carlos@example.com',
        amount: 1000.0,
        paymentMethod: 'Maya',
        userAccountName: 'Carlos Reyes',
        userAccountNumber: '09189876543',
        status: 'WAITING_FOR_AGENT',
        createdAt: now,
      );

      // 1. Agent Claims
      req = req.copyWith(
        status: 'AWAITING_AGENT_PAYMENT',
        agentId: 'agent_999',
        agentName: 'Top P2P Agent',
        agentPhone: '09170001122',
        claimedAt: now + 5000,
      );
      expect(req.status, 'AWAITING_AGENT_PAYMENT');
      expect(req.agentName, 'Top P2P Agent');

      // 2. Agent Submits Proof
      req = req.copyWith(
        status: 'PENDING_CONFIRMATION',
        referenceNumber: 'MAYAREF998877',
        proofImageUrl: 'https://cdn.tranyx.com/maya_receipt.jpg',
        proofSubmittedAt: now + 25000,
      );
      expect(req.status, 'PENDING_CONFIRMATION');
      expect(req.referenceNumber, 'MAYAREF998877');

      // 3. User / Admin Confirms
      req = req.copyWith(
        status: 'APPROVED',
        verifiedAt: now + 35000,
      );
      expect(req.status, 'APPROVED');
      expect(req.verifiedAt, isNotNull);
    });

    test('Handles Cancellation & Rejection with reason', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final req = WithdrawalRequest(
        id: 'withdraw_cancel',
        uid: 'user_222',
        userName: 'Ana Gomez',
        userEmail: 'ana@example.com',
        amount: 500.0,
        paymentMethod: 'GCash',
        userAccountName: 'Ana Gomez',
        userAccountNumber: '09151239876',
        status: 'WAITING_FOR_AGENT',
        createdAt: now,
      );

      final rejected = req.copyWith(
        status: 'REJECTED',
        rejectionReason: 'Invalid GCash number provided',
        verifiedAt: now + 60000,
      );
      expect(rejected.status, 'REJECTED');
      expect(rejected.rejectionReason, 'Invalid GCash number provided');
    });
  });
}
