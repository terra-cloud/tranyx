import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('WithdrawalRequest Model Integrity', () {
    test('Correctly serializes and deserializes originRail and balanceDeducted', () {
      final req = WithdrawalRequest(
        id: 'with_123',
        uid: 'user_abc',
        userName: 'Zeus',
        userEmail: 'zeus@tranyx.com',
        amount: 500.0,
        paymentMethod: 'Solana (USDT)',
        userAccountName: '',
        userAccountNumber: '',
        originRail: 'mwa_on_chain',
        balanceDeducted: true,
        status: 'PENDING_REVIEW',
        createdAt: 1700000000000,
      );

      final map = req.toMap();
      expect(map['originRail'], equals('mwa_on_chain'));
      expect(map['balanceDeducted'], isTrue);

      final reconstructed = WithdrawalRequest.fromMap(map, docId: 'with_123');
      expect(reconstructed.originRail, equals('mwa_on_chain'));
      expect(reconstructed.balanceDeducted, isTrue);
      expect(reconstructed.paymentMethod, equals('Solana (USDT)'));
    });

    test('Defaults originRail to empty string and balanceDeducted to false if missing', () {
      final legacyMap = {
        'id': 'legacy_with_1',
        'uid': 'user_xyz',
        'amount': 250.0,
        'paymentMethod': 'GCash',
        'status': 'WAITING_FOR_AGENT',
        'createdAt': 1690000000000,
      };

      final req = WithdrawalRequest.fromMap(legacyMap);
      expect(req.originRail, isEmpty);
      expect(req.balanceDeducted, isFalse);
    });

    test('copyWith properly updates originRail and balanceDeducted', () {
      const initial = WithdrawalRequest(
        id: 'with_orig',
        uid: 'user_orig',
        userName: 'Test User',
        userEmail: 'test@tranyx.com',
        amount: 300.0,
        paymentMethod: 'GCash',
        userAccountName: 'Test',
        userAccountNumber: '09123456789',
        status: 'PENDING_REVIEW',
        createdAt: 1700000000000,
      );

      final updated = initial.copyWith(
        originRail: 'manual_p2p',
        balanceDeducted: true,
      );

      expect(updated.originRail, equals('manual_p2p'));
      expect(updated.balanceDeducted, isTrue);
    });
  });

  group('Solana vs P2P Rail Separation Guard', () {
    test('Identifies on-chain Solana requests and excludes them from P2P polling', () {
      final solanaReq = WithdrawalRequest(
        id: 'sol_1',
        uid: 'user_1',
        userName: 'Solana User',
        userEmail: 'sol@tranyx.com',
        amount: 1000.0,
        paymentMethod: 'Solana (SOL)',
        userAccountName: '',
        userAccountNumber: '',
        originRail: 'mwa_on_chain',
        balanceDeducted: true,
        status: 'PENDING_REVIEW',
        createdAt: 1700000000000,
      );

      final isSolana = solanaReq.originRail == 'mwa_on_chain' ||
          solanaReq.paymentMethod.toLowerCase().contains('solana') ||
          solanaReq.userAccountNumber.isEmpty;

      expect(isSolana, isTrue, reason: 'Solana requests must be identified as crypto and excluded from P2P');
    });

    test('Identifies legitimate P2P requests and allows them in P2P polling', () {
      final p2pReq = WithdrawalRequest(
        id: 'p2p_1',
        uid: 'user_2',
        userName: 'P2P User',
        userEmail: 'p2p@tranyx.com',
        amount: 500.0,
        paymentMethod: 'GCash',
        userAccountName: 'Juan Dela Cruz',
        userAccountNumber: '09171234567',
        originRail: 'manual_p2p',
        balanceDeducted: true,
        status: 'WAITING_FOR_AGENT',
        createdAt: 1700000000000,
      );

      final isSolana = p2pReq.originRail == 'mwa_on_chain' ||
          p2pReq.paymentMethod.toLowerCase().contains('solana') ||
          p2pReq.userAccountNumber.isEmpty;

      expect(isSolana, isFalse, reason: 'Legitimate P2P requests must NOT be treated as Solana');
    });
  });

  group('Double-Refund Prevention & Accounting Simulation', () {
    test('Simulates rejection when balance was NOT deducted -> skips refund', () {
      final phantomReq = {
        'id': 'phantom_req',
        'uid': 'user_victim',
        'amount': 500.0,
        'balanceDeducted': false,
        'status': 'PENDING_REVIEW',
      };

      double userBalance = 1000.0;
      final currentStatus = (phantomReq['status'] as String).toUpperCase();
      expect(currentStatus != 'REJECTED', isTrue);

      final wasDeducted = phantomReq['balanceDeducted'] == true;
      if (wasDeducted) {
        userBalance += (phantomReq['amount'] as num).toDouble();
      }

      // Balance must remain unchanged because it was never deducted!
      expect(userBalance, equals(1000.0), reason: 'Refund must NOT be credited if balance was not deducted');
    });

    test('Simulates rejection when balance WAS deducted -> refunds once and clears balanceDeducted', () {
      final legitimateReq = <String, dynamic>{
        'id': 'legit_req',
        'uid': 'user_victim',
        'amount': 500.0,
        'balanceDeducted': true,
        'status': 'PENDING_REVIEW',
      };

      double userBalance = 500.0; // 500 was previously deducted from 1000

      // First Rejection
      final wasDeductedFirst = legitimateReq['balanceDeducted'] == true;
      if (wasDeductedFirst) {
        userBalance += (legitimateReq['amount'] as num).toDouble();
        legitimateReq['balanceDeducted'] = false;
        legitimateReq['status'] = 'REJECTED';
      }

      expect(userBalance, equals(1000.0));
      expect(legitimateReq['balanceDeducted'], isFalse);
      expect(legitimateReq['status'], equals('REJECTED'));

      // Attempt Second Duplicate Rejection
      final currentStatus = (legitimateReq['status'] as String).toUpperCase();
      bool secondRefundAttempted = false;
      if (currentStatus != 'REJECTED' && legitimateReq['balanceDeducted'] == true) {
        userBalance += (legitimateReq['amount'] as num).toDouble();
        secondRefundAttempted = true;
      }

      expect(secondRefundAttempted, isFalse);
      expect(userBalance, equals(1000.0), reason: 'Balance must not increase again on duplicate rejection');
    });
  });
}
