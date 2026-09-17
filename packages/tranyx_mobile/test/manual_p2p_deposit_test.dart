import 'package:flutter_test/flutter_test.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'helpers/fake_firestore.dart';

void main() {
  group('Manual P2P Deposit (GCash & Maya) Acceptance Criteria & Safety Tests', () {
    late FakeFirebaseFirestore firestore;
    late TransitRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = TransitRepository(firestore);
    });

    test('Scenario 1 & 2: Submitting Manual P2P deposit creates PENDING_VERIFICATION request & transaction', () async {
      firestore.db['users/user_101'] = {
        'name': 'Zeus User',
        'email': 'zeus@tranyx.com',
        'tyxBalance': 250.0,
      };

      final reqId = await repo.submitManualDepositRequest(
        uid: 'user_101',
        userName: 'Zeus User',
        userEmail: 'zeus@tranyx.com',
        amount: 1000.0,
        paymentMethod: 'GCash',
        referenceNumber: '10029384812',
        proofImageUrl: 'https://i.ibb.co/receipt_101.jpg',
      );

      expect(reqId, isNotEmpty);

      // Check deposit_requests collection
      final depositDoc = firestore.db['deposit_requests/$reqId'];
      expect(depositDoc, isNotNull);
      expect(depositDoc!['uid'], 'user_101');
      expect(depositDoc['amount'], 1000.0);
      expect(depositDoc['paymentMethod'], 'GCash');
      expect(depositDoc['referenceNumber'], '10029384812');
      expect(depositDoc['proofImageUrl'], 'https://i.ibb.co/receipt_101.jpg');
      expect(depositDoc['status'], 'PENDING_VERIFICATION');

      // Check transactions ledger
      final txDoc = firestore.db['transactions/p2p_dep_$reqId'];
      expect(txDoc, isNotNull);
      expect(txDoc!['uid'], 'user_101');
      expect(txDoc['title'], 'GCash P2P Top-Up');
      expect(txDoc['amount'], 1000.0);
      expect(txDoc['originRail'], 'manual_p2p');
      expect(txDoc['method'], 'GCash');
      expect(txDoc['status'], 'PENDING_VERIFICATION');
      expect(txDoc['referenceNumber'], '10029384812');

      // User balance MUST remain unchanged
      final userDoc = firestore.db['users/user_101'];
      expect(userDoc!['tyxBalance'], 250.0);
    });

    test('Scenario 3: Admin Approval atomically credits balance, locks reference, and completes transaction', () async {
      firestore.db['users/user_202'] = {
        'name': 'Alice Worker',
        'email': 'alice@tranyx.com',
        'tyxBalance': 500.0,
      };

      final reqId = await repo.submitManualDepositRequest(
        uid: 'user_202',
        userName: 'Alice Worker',
        userEmail: 'alice@tranyx.com',
        amount: 1500.0,
        paymentMethod: 'Maya',
        referenceNumber: 'MAYA-99887766',
        proofImageUrl: 'https://i.ibb.co/maya_proof.jpg',
      );

      // Admin approves
      await repo.approveDepositRequest(
        depositRequestId: reqId,
        adminUid: 'admin_master_007',
      );

      // 1. Status updated to APPROVED
      final depositDoc = firestore.db['deposit_requests/$reqId'];
      expect(depositDoc!['status'], 'APPROVED');
      expect(depositDoc['adminUid'], 'admin_master_007');
      expect(depositDoc['verifiedAt'], isNotNull);

      // 2. User balance atomically credited (500 + 1500 = 2000)
      final userDoc = firestore.db['users/user_202'];
      expect(userDoc!['tyxBalance'], 2000.0);

      // 3. Reference number lock document created
      final refLockDoc = firestore.db['deposit_references/maya_MAYA-99887766'];
      expect(refLockDoc, isNotNull);
      expect(refLockDoc!['depositRequestId'], reqId);
      expect(refLockDoc['uid'], 'user_202');
      expect(refLockDoc['amount'], 1500.0);
      expect(refLockDoc['adminUid'], 'admin_master_007');

      // 4. Transaction status updated to Completed
      final txDoc = firestore.db['transactions/p2p_dep_$reqId'];
      expect(txDoc!['status'], 'Completed');
      expect(txDoc['adminUid'], 'admin_master_007');
    });

    test('Scenario 4: Admin Rejection sets REJECTED status and reason without modifying balance', () async {
      firestore.db['users/user_303'] = {
        'name': 'Bob Tester',
        'email': 'bob@tranyx.com',
        'tyxBalance': 100.0,
      };

      final reqId = await repo.submitManualDepositRequest(
        uid: 'user_303',
        userName: 'Bob Tester',
        userEmail: 'bob@tranyx.com',
        amount: 2000.0,
        paymentMethod: 'GCash',
        referenceNumber: 'GCASH-FAKE-REF',
        proofImageUrl: 'https://i.ibb.co/fake_receipt.jpg',
      );

      // Admin rejects with reason
      await repo.rejectDepositRequest(
        depositRequestId: reqId,
        adminUid: 'admin_verifier_1',
        reason: 'Reference number not found in GCash merchant account records.',
      );

      // 1. Status updated to REJECTED with reason
      final depositDoc = firestore.db['deposit_requests/$reqId'];
      expect(depositDoc!['status'], 'REJECTED');
      expect(depositDoc['rejectionReason'], 'Reference number not found in GCash merchant account records.');
      expect(depositDoc['adminUid'], 'admin_verifier_1');

      // 2. User balance remains untouched (100.0)
      final userDoc = firestore.db['users/user_303'];
      expect(userDoc!['tyxBalance'], 100.0);

      // 3. Transaction record updated to REJECTED
      final txDoc = firestore.db['transactions/p2p_dep_$reqId'];
      expect(txDoc!['status'], 'REJECTED');
      expect(txDoc['rejectionReason'], 'Reference number not found in GCash merchant account records.');
    });

    test('Scenario 5: Duplicate Reference Protection blocks approval and prevents double crediting', () async {
      firestore.db['users/user_attacker'] = {
        'name': 'Attacker',
        'email': 'bad@tranyx.com',
        'tyxBalance': 0.0,
      };

      // Existing already-approved reference in database
      firestore.db['deposit_references/gcash_10029384812'] = {
        'depositRequestId': 'prev_dep_1',
        'referenceNumber': '10029384812',
        'paymentMethod': 'GCash',
        'uid': 'victim_user',
        'amount': 1000.0,
        'approvedAt': 1724000000000,
      };

      // Attacker attempts to claim same reference number
      final reqId = await repo.submitManualDepositRequest(
        uid: 'user_attacker',
        userName: 'Attacker',
        userEmail: 'bad@tranyx.com',
        amount: 1000.0,
        paymentMethod: 'GCash',
        referenceNumber: '10029384812',
        proofImageUrl: 'https://i.ibb.co/reused_receipt.jpg',
      );

      // Attempting approval MUST throw duplicate reference exception
      expect(
        () async => await repo.approveDepositRequest(
          depositRequestId: reqId,
          adminUid: 'admin_verifier',
        ),
        throwsA(
          predicate((e) => e.toString().contains('Reference number has already been claimed/approved')),
        ),
      );

      // Attacker balance MUST remain 0.0
      final attackerDoc = firestore.db['users/user_attacker'];
      expect(attackerDoc!['tyxBalance'], 0.0);
    });

    test('Scenario 6: Double-Approval & Concurrent Safety blocks already processed requests', () async {
      firestore.db['users/user_404'] = {
        'name': 'Concurrent User',
        'email': 'user404@tranyx.com',
        'tyxBalance': 300.0,
      };

      final reqId = await repo.submitManualDepositRequest(
        uid: 'user_404',
        userName: 'Concurrent User',
        userEmail: 'user404@tranyx.com',
        amount: 500.0,
        paymentMethod: 'Maya',
        referenceNumber: 'MAYA-UNIQUE-404',
        proofImageUrl: 'https://i.ibb.co/maya_404.jpg',
      );

      // First approval succeeds
      await repo.approveDepositRequest(
        depositRequestId: reqId,
        adminUid: 'admin_1',
      );
      expect(firestore.db['users/user_404']!['tyxBalance'], 800.0);

      // Second approval attempt (e.g. double-click or simultaneous admin action) MUST fail
      expect(
        () async => await repo.approveDepositRequest(
          depositRequestId: reqId,
          adminUid: 'admin_2',
        ),
        throwsA(
          predicate((e) => e.toString().contains('is not pending verification')),
        ),
      );

      // Balance MUST NOT be double-credited (must remain 800.0)
      expect(firestore.db['users/user_404']!['tyxBalance'], 800.0);
    });

    test('Scenario 7: P2P Agent Profile Fetch, Update & Custom QR Integration', () async {
      // Default agent fallback when none saved
      final defaultAgent = await repo.fetchActiveP2pAgent();
      expect(defaultAgent.name, contains('TRANYX Official Desk'));
      expect(defaultAgent.gcashAccountName, 'TRANYX OFFICIAL / ZEUS C.');
      expect(defaultAgent.gcashNumber, '0917 890 1234');

      // Update agent profile
      final updatedAgent = defaultAgent.copyWith(
        name: 'Agent Maria Santos',
        gcashNumber: '0919 999 8888',
        gcashQrUrl: 'https://example.com/qr/gcash_maria.png',
        mayaNumber: '0919 999 7777',
      );
      await repo.updateP2pAgentProfile(updatedAgent);

      // Verify fetch returns updated agent
      final fetchedAgent = await repo.fetchActiveP2pAgent(agentId: updatedAgent.agentId);
      expect(fetchedAgent.name, 'Agent Maria Santos');
      expect(fetchedAgent.gcashNumber, '0919 999 8888');
      expect(fetchedAgent.gcashQrUrl, 'https://example.com/qr/gcash_maria.png');

      // Submitting deposit with agent details links request to agent
      final reqId = await repo.submitManualDepositRequest(
        uid: 'user_agent_test',
        userName: 'Zeus Submitter',
        userEmail: 'zeus@tranyx.com',
        amount: 1500.0,
        paymentMethod: 'GCash',
        referenceNumber: 'REF-AGENT-101',
        proofImageUrl: 'https://example.com/proof.png',
        agentId: fetchedAgent.agentId,
        agentName: fetchedAgent.name,
        agentQrUrl: fetchedAgent.gcashQrUrl,
      );

      final reqDoc = firestore.db['deposit_requests/$reqId'];
      expect(reqDoc!['agentId'], 'official_tranyx_agent');
      expect(reqDoc['agentName'], 'Agent Maria Santos');
      expect(reqDoc['agentQrUrl'], 'https://example.com/qr/gcash_maria.png');
    });

    test('Scenario 8: Full 2-Step P2P Dispatch: User Requests -> Agent Sends QR -> User Pays -> Agent Confirms', () async {
      firestore.db['users/user_p2p_flow'] = {
        'name': 'P2P Tester',
        'email': 'tester@tranyx.com',
        'tyxBalance': 100.0,
      };

      // Step 1: User requests top-up (Status -> WAITING_FOR_AGENT)
      final reqId = await repo.requestP2pTopup(
        uid: 'user_p2p_flow',
        userName: 'P2P Tester',
        userEmail: 'tester@tranyx.com',
        amount: 2500.0,
        paymentMethod: 'GCash',
      );

      var doc = firestore.db['deposit_requests/$reqId'];
      expect(doc!['status'], 'WAITING_FOR_AGENT');
      expect(doc['amount'], 2500.0);
      expect(doc['paymentMethod'], 'GCash');

      // Step 2: Payment Agent accepts & sends QR code (Status -> AWAITING_PAYMENT)
      await repo.agentAcceptAndSendQr(
        depositRequestId: reqId,
        agentId: 'agent_zeus_1',
        agentName: 'Agent Zeus Desk',
        agentAccountName: 'ZEUS C. / TRANYX',
        agentAccountNumber: '0917 890 1234',
        agentQrUrl: 'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=gcash_zeus',
      );

      doc = firestore.db['deposit_requests/$reqId'];
      expect(doc!['status'], 'AWAITING_PAYMENT');
      expect(doc['agentId'], 'agent_zeus_1');
      expect(doc['agentName'], 'Agent Zeus Desk');
      expect(doc['agentAccountName'], 'ZEUS C. / TRANYX');
      expect(doc['agentAccountNumber'], '0917 890 1234');
      expect(doc['agentQrUrl'], contains('gcash_zeus'));
      expect(doc['qrSentAt'], isNotNull);

      // Step 3: User submits payment reference and proof (Status -> PENDING_VERIFICATION)
      await repo.submitDepositProof(
        depositRequestId: reqId,
        referenceNumber: 'GCASH-REF-889900',
        proofImageUrl: 'https://i.ibb.co/receipt_p2p_flow.jpg',
      );

      doc = firestore.db['deposit_requests/$reqId'];
      expect(doc!['status'], 'PENDING_VERIFICATION');
      expect(doc['referenceNumber'], 'GCASH-REF-889900');
      expect(doc['proofImageUrl'], 'https://i.ibb.co/receipt_p2p_flow.jpg');
      expect(doc['proofSubmittedAt'], isNotNull);

      // Step 4: Agent verifies receipt and approves in Admin Panel (Status -> APPROVED, Balance Credited)
      await repo.approveDepositRequest(
        depositRequestId: reqId,
        adminUid: 'agent_zeus_1',
      );

      doc = firestore.db['deposit_requests/$reqId'];
      expect(doc!['status'], 'APPROVED');
      expect(doc['adminUid'], 'agent_zeus_1');
      expect(doc['verifiedAt'], isNotNull);

      // Check user balance updated: 100.0 + 2500.0 = 2600.0
      final userDoc = firestore.db['users/user_p2p_flow'];
      expect(userDoc!['tyxBalance'], 2600.0);

      // Check reference locked
      final refLock = firestore.db['deposit_references/gcash_GCASH-REF-889900'];
      expect(refLock, isNotNull);
      expect(refLock!['amount'], 2500.0);
    });
  });
}


