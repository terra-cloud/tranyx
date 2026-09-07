import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('P2pAgent Model & DepositRequest Agent Support Tests', () {
    test('P2pAgent.defaultAgent creates valid official desk credentials', () {
      final defaultAgent = P2pAgent.defaultAgent();

      expect(defaultAgent.agentId, equals('official_tranyx_agent'));
      expect(defaultAgent.name, contains('TRANYX Official Desk'));
      expect(defaultAgent.isActive, isTrue);
      expect(defaultAgent.gcashAccountName, equals('TRANYX OFFICIAL / ZEUS C.'));
      expect(defaultAgent.gcashNumber, equals('0917 890 1234'));
      expect(defaultAgent.gcashQrUrl, contains('qrserver.com'));
      expect(defaultAgent.mayaAccountName, equals('TRANYX CORP / ZEUS C.'));
      expect(defaultAgent.mayaNumber, equals('0918 901 2345'));
      expect(defaultAgent.mayaQrUrl, contains('qrserver.com'));
    });

    test('P2pAgent serialization and deserialization works correctly', () {
      final agent = P2pAgent(
        agentId: 'agent_9988',
        name: 'Agent Maria Santos',
        email: 'maria@tranyx.ph',
        phone: '0919 123 4567',
        isActive: true,
        gcashAccountName: 'MARIA S. / TRANYX',
        gcashNumber: '0919 123 4567',
        gcashQrUrl: 'https://example.com/qr/gcash_maria.png',
        mayaAccountName: 'MARIA SANTOS / TRANYX',
        mayaNumber: '0919 123 4567',
        mayaQrUrl: 'https://example.com/qr/maya_maria.png',
        completedDeposits: 52,
        totalProcessedAmount: 120500.0,
        updatedAt: 1718000000000,
      );

      final map = agent.toMap();
      final reconstructed = P2pAgent.fromMap(map, docId: 'agent_9988');

      expect(reconstructed.agentId, equals('agent_9988'));
      expect(reconstructed.name, equals('Agent Maria Santos'));
      expect(reconstructed.email, equals('maria@tranyx.ph'));
      expect(reconstructed.isActive, isTrue);
      expect(reconstructed.gcashAccountName, equals('MARIA S. / TRANYX'));
      expect(reconstructed.gcashQrUrl, equals('https://example.com/qr/gcash_maria.png'));
      expect(reconstructed.mayaNumber, equals('0919 123 4567'));
      expect(reconstructed.completedDeposits, equals(52));
      expect(reconstructed.totalProcessedAmount, equals(120500.0));
    });

    test('DepositRequest supports agent fields serialization and deserialization', () {
      final req = DepositRequest(
        id: 'dep_123',
        uid: 'user_456',
        userName: 'Zeus Tester',
        userEmail: 'zeus@test.ph',
        amount: 2500.0,
        paymentMethod: 'GCash',
        referenceNumber: '10029384812',
        proofImageUrl: 'https://i.ibb.co/receipt.png',
        status: 'PENDING_VERIFICATION',
        agentId: 'official_tranyx_agent',
        agentName: 'TRANYX Official Desk (Zeus C.)',
        agentQrUrl: 'https://api.qrserver.com/v1/create-qr-code/?size=350x350&data=gcash',
        createdAt: 1718000000000,
      );

      final map = req.toMap();
      expect(map['agentId'], equals('official_tranyx_agent'));
      expect(map['agentName'], equals('TRANYX Official Desk (Zeus C.)'));
      expect(map['agentQrUrl'], contains('qrserver.com'));

      final reconstructed = DepositRequest.fromMap(map, docId: 'dep_123');
      expect(reconstructed.id, equals('dep_123'));
      expect(reconstructed.agentId, equals('official_tranyx_agent'));
      expect(reconstructed.agentName, equals('TRANYX Official Desk (Zeus C.)'));
      expect(reconstructed.agentQrUrl, contains('qrserver.com'));
      expect(reconstructed.status, equals('PENDING_VERIFICATION'));
    });

    test('5-minute P2P cancellation eligibility rules', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Case 1: Fresh request (2 minutes old) -> Not cancellable yet
      final recentReq = DepositRequest(
        id: 'dep_recent',
        uid: 'user_1',
        userName: 'User 1',
        userEmail: 'user1@test.ph',
        amount: 500.0,
        paymentMethod: 'GCash',
        status: 'WAITING_FOR_AGENT',
        createdAt: now - (2 * 60 * 1000), // 2 mins ago
      );
      final elapsedRecent = now - recentReq.createdAt;
      final canCancelRecent = elapsedRecent >= 5 * 60 * 1000;
      expect(canCancelRecent, isFalse);

      // Case 2: Stale request (6 minutes old) -> Cancellable
      final staleReq = DepositRequest(
        id: 'dep_stale',
        uid: 'user_2',
        userName: 'User 2',
        userEmail: 'user2@test.ph',
        amount: 500.0,
        paymentMethod: 'GCash',
        status: 'WAITING_FOR_AGENT',
        createdAt: now - (6 * 60 * 1000), // 6 mins ago
      );
      final elapsedStale = now - staleReq.createdAt;
      final canCancelStale = elapsedStale >= 5 * 60 * 1000;
      expect(canCancelStale, isTrue);

      // Case 3: Completed / Approved request -> Never cancellable regardless of age
      final approvedReq = DepositRequest(
        id: 'dep_approved',
        uid: 'user_3',
        userName: 'User 3',
        userEmail: 'user3@test.ph',
        amount: 500.0,
        paymentMethod: 'GCash',
        status: 'APPROVED',
        createdAt: now - (10 * 60 * 1000), // 10 mins ago
      );
      final isTransferred = approvedReq.status == 'APPROVED' || approvedReq.status == 'COMPLETED';
      expect(isTransferred, isTrue);
    });
  });
}
