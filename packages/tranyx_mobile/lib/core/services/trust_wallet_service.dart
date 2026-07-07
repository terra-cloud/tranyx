import 'package:flutter/material.dart';
import 'package:reown_appkit/reown_appkit.dart';

const kSolanaChainId = 'solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp'; // mainnet
const kSolanaTestnet = 'solana:4uhcVJyU9pJkvQyS88uRDiswHXSCkY3z'; // testnet
const kSolanaDevnet = 'solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1'; // devnet

class TrustWalletService {
  static String getSolanaChainId() {
    // Note: Trust Wallet only supports Solana Mainnet natively. Proposing Devnet
    // or Testnet chains causes the WalletConnect connection request to fail.
    // Since Solana transactions do not contain a chain ID field (only a blockhash),
    // we can request a session on Mainnet and still sign Devnet/Testnet transactions
    // without issue.
    return kSolanaChainId;
  }

  static Future<ReownAppKitModal> createModal({
    required BuildContext context,
    required String projectId,
  }) async {
    final chainId = getSolanaChainId();
    final modal = ReownAppKitModal(
      context: context,
      projectId: projectId,
      metadata: const PairingMetadata(
        name: 'Tranyx',
        description: 'Tranyx - Crypto Remittance',
        url: 'https://tranyx.app',
        icons: ['https://tranyx.app/favicon.png'],
        redirect: Redirect(
          native: 'tranyx://',
          universal: 'https://tranyx.app',
          linkMode: true,
        ),
      ),
      optionalNamespaces: {
        'solana': RequiredNamespace(
          chains: [chainId],
          methods: [
            'solana_signTransaction',
            'solana_signAllTransactions',
            'solana_signMessage',
            'solana_getAccounts',
          ],
          events: [],
        ),
      },
    );

    await modal.init();
    return modal;
  }
}
