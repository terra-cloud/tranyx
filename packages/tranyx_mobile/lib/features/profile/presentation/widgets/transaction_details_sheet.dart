import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/flavors.dart';

class TransactionDetailsSheet extends StatelessWidget {
  final WalletTransaction transaction;
  final bool isDarkMode;

  const TransactionDetailsSheet({
    super.key,
    required this.transaction,
    required this.isDarkMode,
  });

  static Future<void> show(
    BuildContext context, {
    required WalletTransaction transaction,
    required bool isDarkMode,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TransactionDetailsSheet(
        transaction: transaction,
        isDarkMode: isDarkMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tx = transaction;
    final isDeposit = tx.amount >= 0 ||
        tx.transactionType == WalletTransactionType.deposit ||
        tx.transactionType == WalletTransactionType.refund;

    final dateStr = tx.createdAt > 0
        ? DateFormat('MMM dd, yyyy • hh:mm:ss a')
            .format(DateTime.fromMillisecondsSinceEpoch(tx.createdAt))
        : 'Recently';

    final isMwa = tx.originRail == TransactionOriginRail.mwaOnChain;

    final clusterLabel = F.appFlavor == Flavor.production
        ? 'Solana Mainnet-Beta'
        : (F.appFlavor == Flavor.uat ? 'Solana Testnet' : 'Solana Devnet');

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.grey.shade700
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title & Status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDeposit
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.indigo.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      isDeposit
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      color: isDeposit ? Colors.green : AppColors.indigo,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tx.title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tx.desc,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDarkMode
                                ? AppColors.darkTextMuted
                                : AppColors.lightTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusBadge(tx.status),
                ],
              ),
              const SizedBox(height: 24),

              // Normalized Amount Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? AppColors.darkBg
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDarkMode
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'TOTAL SETTLED AMOUNT',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${isDeposit ? "+" : "-"} ₱ ${tx.amount.abs().toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: isDeposit ? Colors.green : Colors.indigo,
                      ),
                    ),
                    if (tx.cryptoAmount != null && tx.cryptoAmount! > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '≈ ${tx.cryptoAmount!.toStringAsFixed(4)} ${tx.cryptoCurrency ?? "SOL"}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode
                              ? Colors.indigo.shade300
                              : AppColors.indigo,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Rail Origin Details
              Text(
                'TRANSACTION ORIGIN & METADATA',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: isDarkMode
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
                ),
              ),
              const SizedBox(height: 12),

              _buildDetailRow(
                icon: Icons.alt_route_rounded,
                label: 'Origin Rail',
                valueWidget: _buildRailBadge(tx.originRail, isMwa),
              ),
              const SizedBox(height: 10),

              _buildDetailRow(
                icon: Icons.access_time_rounded,
                label: 'Timestamp',
                value: dateStr,
              ),

              if (tx.method != null && tx.method!.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildDetailRow(
                  icon: Icons.payment_rounded,
                  label: 'Payment Method',
                  value: tx.method!,
                ),
              ],

              // Manual P2P Details (Reference Number, Proof, Rejection Reason)
              if (tx.originRail == TransactionOriginRail.manualP2p ||
                  (tx.referenceNumber != null && tx.referenceNumber!.isNotEmpty)) ...[
                if (tx.referenceNumber != null && tx.referenceNumber!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildCopyableRow(
                    context: context,
                    icon: Icons.tag_rounded,
                    label: 'Reference Number',
                    value: tx.referenceNumber!,
                    displayValue: tx.referenceNumber!,
                  ),
                ],
                if (tx.originRail == TransactionOriginRail.manualP2p || (tx.proofImageUrl != null && tx.proofImageUrl!.isNotEmpty)) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (tx.proofImageUrl != null && tx.proofImageUrl!.isNotEmpty) {
                          launchUrl(
                            Uri.parse(tx.proofImageUrl!),
                            mode: LaunchMode.externalApplication,
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'P2P Receipt: Verified by Payment Agent (Ref: ${tx.referenceNumber ?? "Official Ledger Entry"})',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.receipt_long_rounded, size: 16),
                      label: const Text('View Proof of Receipt'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDarkMode ? Colors.indigo.shade300 : AppColors.indigo,
                        side: BorderSide(
                          color: isDarkMode ? Colors.indigo.shade300 : AppColors.indigo,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
                if (tx.rejectionReason != null && tx.rejectionReason!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Rejection Reason',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tx.rejectionReason!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode ? Colors.red.shade200 : Colors.red.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],

              // On-Chain Specific Details
              if (tx.originRail == TransactionOriginRail.mwaOnChain &&
                  tx.solanaTxSignature != null &&
                  tx.solanaTxSignature!.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildDetailRow(
                  icon: Icons.hub_rounded,
                  label: 'Network Cluster',
                  value: clusterLabel,
                ),
                const SizedBox(height: 10),
                _buildCopyableRow(
                  context: context,
                  icon: Icons.tag_rounded,
                  label: 'Solana Tx Hash',
                  value: tx.solanaTxSignature!,
                  displayValue: _truncate(tx.solanaTxSignature!),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final url = WalletTransaction.getSolanaExplorerUrl(
                        signature: tx.solanaTxSignature!,
                        environment: F.name,
                      );
                      launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('View on Solana Block Explorer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF512DA8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color: isDarkMode
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Close Details',
                    style: TextStyle(
                      color: isDarkMode ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg = Colors.green.withValues(alpha: 0.12);
    Color fg = Colors.green;

    final s = status.toUpperCase();
    if (s.contains('PENDING')) {
      bg = Colors.amber.withValues(alpha: 0.15);
      fg = Colors.amber.shade800;
    } else if (s.contains('REJECT') || s.contains('FAIL')) {
      bg = Colors.red.withValues(alpha: 0.12);
      fg = Colors.red;
    } else if (s.contains('APPROVED') || s.contains('COMPLETE')) {
      bg = Colors.green.withValues(alpha: 0.12);
      fg = Colors.green;
    }

    final label = status == 'PENDING_VERIFICATION' ? 'Pending Verification' : status;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildRailBadge(
    TransactionOriginRail rail,
    bool isMwa,
  ) {
    if (rail == TransactionOriginRail.manualP2p) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_2, color: Colors.blue, size: 14),
            SizedBox(width: 4),
            Text(
              'Manual P2P (GCash/Maya)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ],
        ),
      );
    }

    if (isMwa) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF512DA8).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt, color: Color(0xFF7E57C2), size: 14),
            SizedBox(width: 4),
            Text(
              'MWA / On-Chain',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF7E57C2),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Internal Balance',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    String? value,
    Widget? valueWidget,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isDarkMode
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isDarkMode
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          ],
        ),
        valueWidget ??
            Text(
              value ?? '',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
      ],
    );
  }

  Widget _buildCopyableRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required String displayValue,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isDarkMode
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isDarkMode
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          ],
        ),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$label copied to clipboard!'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              children: [
                Text(
                  displayValue,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.indigo.shade300 : AppColors.indigo,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: isDarkMode ? Colors.indigo.shade300 : AppColors.indigo,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _truncate(String text) {
    if (text.length <= 16) return text;
    return '${text.substring(0, 8)}...${text.substring(text.length - 8)}';
  }
}
