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

    test('Correctly parses Xendit GCash fiat sandbox transaction', () {
      final data = {
        'id': 'deposit_inv_998877',
        'uid': 'user_xyz',
        'title': 'Wallet Top-Up',
        'desc': 'Fiat deposit via Xendit',
        'amount': 500.0,
        'xenditReferenceId': 'inv_998877',
        'method': 'GCash',
        'type': 'deposit',
        'status': 'Completed',
        'createdAt': 1724056789000,
      };

      final tx = WalletTransaction.fromMap(data);

      expect(tx.id, 'deposit_inv_998877');
      expect(tx.originRail, TransactionOriginRail.gcashXendit);
      expect(tx.transactionType, WalletTransactionType.fiatTopup);
      expect(tx.amount, 500.0);
      expect(tx.xenditReferenceId, 'inv_998877');
      expect(tx.xenditChannel, 'GCASH');
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
  });
}
