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
  });
}
