import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('WalletTransaction Unit Tests', () {
    test('Correctly parses MWA on-chain transaction with signature', () {
      final data = {
        'id': 'tx_12345',
        'uid': 'user_abc',
        'title': 'Job Escrow Payout',
        'desc': 'Released ₱1500 to worker on Solana',
        'amount': 1500.0,
        'cryptoAmount': 0.1875,
        'coin': 'SOL',
        'solanaTxSignature': '5Ux8N9vBqK3456789abcdef123456789',
        'type': 'on_chain_payment',
        'status': 'Completed',
        'createdAt': 1724056789000,
      };

      final tx = WalletTransaction.fromMap(data);

      expect(tx.id, 'tx_12345');
      expect(tx.originRail, TransactionOriginRail.mwaOnChain);
      expect(tx.transactionType, WalletTransactionType.onChainPayment);
      expect(tx.cryptoAmount, 0.1875);
      expect(tx.cryptoCurrency, 'SOL');
      expect(tx.solanaTxSignature, '5Ux8N9vBqK3456789abcdef123456789');

      final explorerDev = WalletTransaction.getSolanaExplorerUrl(
        signature: tx.solanaTxSignature!,
        environment: 'dev',
      );
      expect(explorerDev, contains('cluster=devnet'));

      final explorerUat = WalletTransaction.getSolanaExplorerUrl(
        signature: tx.solanaTxSignature!,
        environment: 'uat',
      );
      expect(explorerUat, contains('cluster=testnet'));

      final explorerProd = WalletTransaction.getSolanaExplorerUrl(
        signature: tx.solanaTxSignature!,
        environment: 'production',
      );
      expect(explorerProd, isNot(contains('cluster=')));
    });

    test('Correctly parses internal deposit transaction', () {
      final data = {
        'id': 'deposit_12345',
        'uid': 'user_xyz',
        'title': 'Wallet Top-Up',
        'desc': 'Deposit to wallet',
        'amount': 500.0,
        'type': 'deposit',
        'status': 'Completed',
        'createdAt': 1724056789000,
      };

      final tx = WalletTransaction.fromMap(data);

      expect(tx.id, 'deposit_12345');
      expect(tx.originRail, TransactionOriginRail.internalBalance);
      expect(tx.transactionType, WalletTransactionType.deposit);
      expect(tx.amount, 500.0);
    });

    test('Handles legacy transaction without origin rail gracefully', () {
      final data = {
        'id': 'tx_legacy_1',
        'uid': 'user_leg',
        'title': 'Listing Fee',
        'amount': -50.0,
        'type': 'listing_fee',
        'createdAt': 1724056789000,
      };

      final tx = WalletTransaction.fromMap(data);

      expect(tx.originRail, TransactionOriginRail.internalBalance);
      expect(tx.transactionType, WalletTransactionType.listingFee);
      expect(tx.amount, -50.0);
    });

    test('Correctly parses Manual P2P deposit transaction with proof and reference', () {
      final data = {
        'id': 'p2p_deposit_999',
        'uid': 'user_p2p',
        'title': 'GCash P2P Top-Up',
        'desc': 'Manual GCash Transfer Ref: 10029384812',
        'amount': 1000.0,
        'type': 'deposit',
        'originRail': 'manual_p2p',
        'method': 'GCash',
        'referenceNumber': '10029384812',
        'proofImageUrl': 'https://i.ibb.co/receipt.jpg',
        'status': 'PENDING_VERIFICATION',
        'createdAt': 1724056789000,
      };

      final tx = WalletTransaction.fromMap(data);

      expect(tx.id, 'p2p_deposit_999');
      expect(tx.originRail, TransactionOriginRail.manualP2p);
      expect(tx.transactionType, WalletTransactionType.deposit);
      expect(tx.amount, 1000.0);
      expect(tx.referenceNumber, '10029384812');
      expect(tx.proofImageUrl, 'https://i.ibb.co/receipt.jpg');
      expect(tx.status, 'PENDING_VERIFICATION');

      final map = tx.toMap();
      expect(map['originRail'], 'manual_p2p');
      expect(map['referenceNumber'], '10029384812');
      expect(map['status'], 'PENDING_VERIFICATION');
    });

    test('DepositRequest model serializes and deserializes correctly', () {
      final req = DepositRequest(
        id: 'dep_req_123',
        uid: 'user_123',
        userName: 'Zeus Cajurao',
        userEmail: 'zeus@tranyx.com',
        amount: 1500.0,
        paymentMethod: 'Maya',
        referenceNumber: 'MAYA-998877',
        proofImageUrl: 'https://i.ibb.co/maya.jpg',
        status: 'PENDING_VERIFICATION',
        createdAt: 1724056789000,
      );

      final map = req.toMap();
      expect(map['id'], 'dep_req_123');
      expect(map['paymentMethod'], 'Maya');
      expect(map['amount'], 1500.0);
      expect(map['referenceNumber'], 'MAYA-998877');

      final parsed = DepositRequest.fromMap(map);
      expect(parsed.id, 'dep_req_123');
      expect(parsed.userName, 'Zeus Cajurao');
      expect(parsed.paymentMethod, 'Maya');
      expect(parsed.referenceNumber, 'MAYA-998877');
      expect(parsed.status, 'PENDING_VERIFICATION');
    });

    test('Correctly parses Escrow Refund transaction', () {
      final data = {
        'id': 'refund_job_abc',
        'uid': 'user_emp',
        'title': 'Job Escrow Refund',
        'desc': '100% Escrow refund for cancelled job "Delivery Task"',
        'amount': 1500.0,
        'type': 'refund',
        'status': 'Completed',
        'method': 'Tranyx Escrow',
        'createdAt': 1724056789000,
      };

      final tx = WalletTransaction.fromMap(data);

      expect(tx.id, 'refund_job_abc');
      expect(tx.originRail, TransactionOriginRail.internalBalance);
      expect(tx.transactionType, WalletTransactionType.refund);
      expect(tx.amount, 1500.0);
      expect(tx.title, 'Job Escrow Refund');
      expect(tx.status, 'Completed');
    });

    test('Correctly parses job_escrow_refund type', () {
      final data = {
        'id': 'refund_job_xyz',
        'uid': 'user_emp',
        'title': 'Job Escrow Refund',
        'desc': '100% Escrow refund',
        'amount': 850.0,
        'type': 'job_escrow_refund',
        'status': 'Completed',
        'createdAt': 1724056789000,
      };

      final tx = WalletTransaction.fromMap(data);

      expect(tx.id, 'refund_job_xyz');
      expect(tx.transactionType, WalletTransactionType.refund);
      expect(tx.amount, 850.0);
    });

    test('Snapshotted fee rates retain exact historical values (1% vs 2% service fee)', () {
      // Historical Transaction 1: Executed when admin set service fee = 1% & markup = 3%
      final tx1Data = {
        'id': 'tx_hist_1',
        'uid': 'user_emp_1',
        'title': 'Job Completion Fees (4%)',
        'desc': 'Fee deduction with 1% service fee and 3% markup',
        'amount': 40.0,
        'baseAmount': 1000.0,
        'serviceFeeAmount': 10.0,
        'markupAmount': 30.0,
        'serviceFeeRate': 0.01,
        'markupRate': 0.03,
        'transactionFeeRate': 0.07,
        'convenienceFeeRate': 0.03,
        'type': 'fee_deduction',
        'status': 'Successful',
        'createdAt': 1700000000000,
      };

      // Newer Transaction 2: Executed when admin updated service fee = 2% & markup = 4%
      final tx2Data = {
        'id': 'tx_new_2',
        'uid': 'user_emp_2',
        'title': 'Job Completion Fees (6%)',
        'desc': 'Fee deduction with 2% service fee and 4% markup',
        'amount': 60.0,
        'baseAmount': 1000.0,
        'serviceFeeAmount': 20.0,
        'markupAmount': 40.0,
        'serviceFeeRate': 0.02,
        'markupRate': 0.04,
        'transactionFeeRate': 0.07,
        'convenienceFeeRate': 0.03,
        'type': 'fee_deduction',
        'status': 'Successful',
        'createdAt': 1710000000000,
      };

      final tx1 = WalletTransaction.fromMap(tx1Data);
      final tx2 = WalletTransaction.fromMap(tx2Data);

      // Verify Tx 1 displays 1% service fee and 3% markup
      expect(tx1.serviceFeeRate, 0.01);
      expect(tx1.markupRate, 0.03);
      expect(tx1.serviceFeePercentLabel, '1%');
      expect(tx1.markupPercentLabel, '3%');
      expect(tx1.computedServiceFee, 10.0);
      expect(tx1.computedMarkup, 30.0);

      // Verify Tx 2 displays 2% service fee and 4% markup
      expect(tx2.serviceFeeRate, 0.02);
      expect(tx2.markupRate, 0.04);
      expect(tx2.serviceFeePercentLabel, '2%');
      expect(tx2.markupPercentLabel, '4%');
      expect(tx2.computedServiceFee, 20.0);
      expect(tx2.computedMarkup, 40.0);

      // Both retain their respective rates concurrently without clobbering each other
      expect(tx1.serviceFeePercentLabel, isNot(equals(tx2.serviceFeePercentLabel)));
      expect(tx1.markupPercentLabel, isNot(equals(tx2.markupPercentLabel)));
    });

    test('Derives effective rate from base and fee amounts for legacy transactions', () {
      final legacyData = {
        'id': 'tx_legacy_fee',
        'uid': 'user_emp',
        'title': 'Job Completion Fees',
        'amount': 100.0,
        'baseAmount': 1000.0,
        'transactionFee': 70.0,
        'convenienceFee': 30.0,
        'type': 'fee_deduction',
        'status': 'Successful',
        'createdAt': 1690000000000,
      };

      final tx = WalletTransaction.fromMap(legacyData);
      expect(tx.effectiveTxFeeRate, 0.07);
      expect(tx.effectiveConvFeeRate, 0.03);
      expect(tx.txFeePercentLabel, '7%');
      expect(tx.convFeePercentLabel, '3%');
      expect(tx.totalEmployerFeesPercentLabel, '10%');
    });
  });
}

