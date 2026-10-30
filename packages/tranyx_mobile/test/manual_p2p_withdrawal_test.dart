import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';
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

    // KAN-146: the debit, fee and request records are created by the requestWithdrawal Cloud
    // Function (covered by the functions/ emulator tests). The app only sends the request.

    /// Mimics what the requestWithdrawal Cloud Function commits (KAN-146): debit + request + ledger row.
    String serverCreatesRequest(String uid, double amount, String method, String accName, String accNo) {
      const id = '22222222-2222-4222-8222-222222222222';
      final bal = (firestore.db['users/$uid']!['tyxBalance'] as num).toDouble();
      firestore.db['users/$uid']!['tyxBalance'] = bal - amount;
      firestore.db['withdrawal_requests/$id'] = {
        'id': id, 'uid': uid, 'amount': amount, 'paymentMethod': method, 'userAccountName': accName,
        'userAccountNumber': accNo, 'status': 'WAITING_FOR_AGENT', 'originRail': 'manual_p2p',
        'balanceDeducted': true, 'createdAt': 1,
      };
      firestore.db['transactions/p2p_with_$id'] = {
        'id': 'p2p_with_$id', 'uid': uid, 'amount': -amount, 'type': 'withdraw', 'status': 'WAITING_FOR_AGENT',
      };
      return id;
    }

    test('Scenario 1: P2P withdrawal goes through the server callable with ONLY the allowed fields and never writes balances', () async {
      firestore.db['users/user_101'] = {'name': 'Zeus User', 'email': 'zeus@tranyx.com', 'tyxBalance': 2500.0};
      Map<String, dynamic>? sent;
      repo = TransitRepository(firestore, withdrawalCaller: (data) async {
        sent = data;
        return {'id': data['idempotencyKey'], 'status': 'WAITING_FOR_AGENT', 'feeAmount': 0.0};
      });

      final reqId = await repo.requestP2pWithdrawal(
        uid: 'user_101',
        userName: 'Zeus User',
        userEmail: 'zeus@tranyx.com',
        amount: 1000.0,
        paymentMethod: 'GCash',
        userAccountName: 'Zeus Cajurao',
        userAccountNumber: '09171234567',
        idempotencyKey: '11111111-1111-4111-8111-111111111111',
      );

      expect(reqId, '11111111-1111-4111-8111-111111111111');
      expect(sent!.keys.toSet(), {'idempotencyKey', 'method', 'amount', 'p2p'});
      expect(sent!['method'], 'p2p');
      expect(sent!['amount'], 1000.0);
      expect((sent!['p2p'] as Map)['paymentMethod'], 'GCash');
      expect((sent!['p2p'] as Map)['accountNumber'], '09171234567');
      // no client-side money writes at all
      expect(firestore.db['users/user_101']!['tyxBalance'], 2500.0);
      expect(firestore.db['withdrawal_requests/$reqId'], isNull);
      expect(firestore.db['transactions/p2p_with_$reqId'], isNull);
    });

    test('Scenario 2: server rejection (insufficient balance) propagates and nothing is written client-side', () async {
      firestore.db['users/user_101'] = {'name': 'Zeus User', 'email': 'zeus@tranyx.com', 'tyxBalance': 500.0};
      repo = TransitRepository(firestore, withdrawalCaller: (data) async {
        throw const WithdrawalException('FAILED_PRECONDITION', 'Requested amount exceeds your available balance.');
      });

      await expectLater(
        repo.requestP2pWithdrawal(
          uid: 'user_101',
          userName: 'Zeus User',
          userEmail: 'zeus@tranyx.com',
          amount: 1000.0,
          paymentMethod: 'GCash',
          userAccountName: 'Zeus Cajurao',
          userAccountNumber: '09171234567',
        ),
        throwsA(isA<WithdrawalException>()),
      );
      expect(firestore.db['users/user_101']!['tyxBalance'], 500.0);
    });

    test('Scenario 3: Cancelling P2P withdrawal refunds locked balance 100%', () async {
      firestore.db['users/user_101'] = {
        'name': 'Zeus User',
        'email': 'zeus@tranyx.com',
        'tyxBalance': 3000.0,
      };

      final reqId = serverCreatesRequest('user_101', 1500.0, 'Maya', 'Zeus Maya', '09181234567');

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

      final reqId = serverCreatesRequest('user_101', 2000.0, 'GCash', 'Zeus Receiver', '09179998877');

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
