import 'package:flutter_test/flutter_test.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'helpers/fake_firestore.dart';

void main() {
  group('Manual P2P Withdrawal (GCash & Maya) Acceptance Criteria & Safety Tests', () {
    late FakeFirebaseFirestore firestore;
    late TransitRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = TransitRepository(firestore);
    });

    test('Scenario 1: Requesting P2P withdrawal deducts user balance immediately and locks funds', () async {
      firestore.db['users/user_101'] = {
        'name': 'Zeus User',
        'email': 'zeus@tranyx.com',
        'tyxBalance': 2500.0,
      };

      final reqId = await repo.requestP2pWithdrawal(
        uid: 'user_101',
        userName: 'Zeus User',
        userEmail: 'zeus@tranyx.com',
        amount: 1000.0,
        paymentMethod: 'GCash',
        userAccountName: 'Zeus Cajurao',
        userAccountNumber: '09171234567',
      );

      expect(reqId, isNotEmpty);

      // Check user balance immediately locked/deducted
      final userDoc = firestore.db['users/user_101'];
      expect(userDoc!['tyxBalance'], 1500.0);

      // Check withdrawal request record
      final reqDoc = firestore.db['withdrawal_requests/$reqId'];
      expect(reqDoc, isNotNull);
      expect(reqDoc!['uid'], 'user_101');
      expect(reqDoc['amount'], 1000.0);
      expect(reqDoc['paymentMethod'], 'GCash');
      expect(reqDoc['userAccountName'], 'Zeus Cajurao');
      expect(reqDoc['userAccountNumber'], '09171234567');
      expect(reqDoc['status'], 'WAITING_FOR_AGENT');

      // Check transaction record
      final txDoc = firestore.db['transactions/p2p_with_$reqId'];
      expect(txDoc, isNotNull);
      expect(txDoc!['amount'], -1000.0);
      expect(txDoc['type'], 'withdraw');
      expect(txDoc['originRail'], 'manual_p2p');
      expect(txDoc['status'], 'WAITING_FOR_AGENT');
    });

    test('Scenario 2: Insufficient balance rejects P2P withdrawal request', () async {
      firestore.db['users/user_101'] = {
        'name': 'Zeus User',
        'email': 'zeus@tranyx.com',
        'tyxBalance': 500.0,
      };

      expect(
        () async => await repo.requestP2pWithdrawal(
          uid: 'user_101',
          userName: 'Zeus User',
          userEmail: 'zeus@tranyx.com',
          amount: 1000.0,
          paymentMethod: 'GCash',
          userAccountName: 'Zeus Cajurao',
          userAccountNumber: '09171234567',
        ),
        throwsA(isA<Exception>()),
      );

      // Balance unchanged
      expect(firestore.db['users/user_101']!['tyxBalance'], 500.0);
    });

    test('Scenario 3: Cancelling P2P withdrawal refunds locked balance 100%', () async {
      firestore.db['users/user_101'] = {
        'name': 'Zeus User',
        'email': 'zeus@tranyx.com',
        'tyxBalance': 3000.0,
      };

      final reqId = await repo.requestP2pWithdrawal(
        uid: 'user_101',
        userName: 'Zeus User',
        userEmail: 'zeus@tranyx.com',
        amount: 1500.0,
        paymentMethod: 'Maya',
        userAccountName: 'Zeus Maya',
        userAccountNumber: '09181234567',
      );

      expect(firestore.db['users/user_101']!['tyxBalance'], 1500.0);

      // User cancels after timeout
      await repo.cancelP2pWithdrawalRequest(reqId, reason: 'Timeout - No agent claimed');

      // Balance refunded
      expect(firestore.db['users/user_101']!['tyxBalance'], 3000.0);
      expect(firestore.db['withdrawal_requests/$reqId']!['status'], 'CANCELLED');
      expect(firestore.db['transactions/p2p_with_$reqId']!['status'], 'CANCELLED');
    });

    test('Scenario 4: User/Admin confirming completed withdrawal updates status to APPROVED/COMPLETED', () async {
      firestore.db['users/user_101'] = {
        'name': 'Zeus User',
        'email': 'zeus@tranyx.com',
        'tyxBalance': 5000.0,
      };

      final reqId = await repo.requestP2pWithdrawal(
        uid: 'user_101',
        userName: 'Zeus User',
        userEmail: 'zeus@tranyx.com',
        amount: 2000.0,
        paymentMethod: 'GCash',
        userAccountName: 'Zeus Receiver',
        userAccountNumber: '09179998877',
      );

      // Confirm completed
      await repo.confirmP2pWithdrawalCompleted(
        withdrawalRequestId: reqId,
        confirmedByUid: 'user_101',
      );

      expect(firestore.db['withdrawal_requests/$reqId']!['status'], 'APPROVED');
      expect(firestore.db['transactions/p2p_with_$reqId']!['status'], 'COMPLETED');
      // Balance remains 3000.0
      expect(firestore.db['users/user_101']!['tyxBalance'], 3000.0);
    });
  });
}
