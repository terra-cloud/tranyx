import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/profile/providers/profile_provider.dart';

class WithdrawPane extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  const WithdrawPane({super.key, required this.onBack});

  @override
  ConsumerState<WithdrawPane> createState() => _WithdrawPaneState();
}

class _WithdrawPaneState extends ConsumerState<WithdrawPane> {
  final _amountController = TextEditingController(text: '100');
  String _selectedCoin = 'USDT'; // 'USDT', 'SOL'

  bool _isSubmitting = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _setPresetAmount(double amount, double maxBalance) {
    final clamped = amount.clamp(0.0, maxBalance);
    setState(() {
      _amountController.text = clamped.toStringAsFixed(0);
      _errorMessage = null;
    });
  }

  Future<void> _submitWithdrawal(double tyxBalance, String uid, String userName) async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;

    if (amount < 100) {
      setState(() => _errorMessage = 'Minimum withdrawal amount is ₱ 100.00.');
      return;
    }

    if (amount > tyxBalance) {
      setState(() => _errorMessage = 'Requested amount exceeds your available balance (₱ ${tyxBalance.toStringAsFixed(2)}).');
      return;
    }

    final profile = ref.read(userProfileProvider).value;
    final walletKey = profile?.walletPublicKey;

    if (walletKey == null || walletKey.isEmpty) {
      setState(() => _errorMessage = 'Withdrawals are only available to connected Solana wallets. Please link your wallet first in Payment Methods or Trust & Verification.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final requestId = 'withdraw_$timestamp';
      final methodTitle = 'Solana ($selectedCoinLabel)';

      final requestData = <String, dynamic>{
        'id': requestId,
        'uid': uid,
        'userName': userName,
        'amount': amount,
        'status': 'Pending',
        'createdAt': timestamp,
        'method': 'Solana',
        'methodTitle': methodTitle,
        'coin': _selectedCoin,
        'currency': 'PHP',
        'walletPublicKey': walletKey,
      };

      // 1. Save withdrawal request record
      await firestore.collection('withdrawalRequests').doc(requestId).set(requestData);

      // 2. Record ledger transaction
      await firestore.collection('transactions').doc('tx_$timestamp').set({
        'id': 'tx_$timestamp',
        'uid': uid,
        'title': 'Withdrawal Request ($methodTitle)',
        'type': 'withdraw',
        'amount': -amount,
        'currency': 'PHP',
        'status': 'Pending',
        'createdAt': timestamp,
        'walletPublicKey': walletKey,
        'method': 'Solana',
      });

      // 3. Deduct from user's Tyx balance
      final newBalance = (tyxBalance - amount).clamp(0.0, double.infinity);
      await firestore.collection('users').doc(uid).update({
        'tyxBalance': newBalance,
      });

      // 4. Invalidate profile state to update real-time balance
      ref.invalidate(userProfileProvider);

      setState(() {
        _isSubmitting = false;
        _successMessage = 'Withdrawal of ₱ ${amount.toStringAsFixed(2)} to your Solana wallet requested successfully! Processing typically completes within 1 hour.';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Withdrawal of ₱ ${amount.toStringAsFixed(2)} via Solana submitted!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Withdrawal request failed: $e';
      });
    }
  }

  String get selectedCoinLabel => _selectedCoin == 'SOL' ? 'SOL (Native)' : 'USDT (SPL)';

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final user = ref.watch(userProvider);

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text("Error: $err")),
      data: (profile) {
        if (profile == null) {
          return const Center(child: Text("Profile not found"));
        }

        final tyxBalance = profile.tyxBalance;
        final cardBg = isDarkMode ? const Color(0xFF1E1E24) : Colors.white;
        final borderColor = isDarkMode ? const Color(0xFF2E2E38) : const Color(0xFFE5E7EB);
        final walletKey = profile.walletPublicKey;
        final hasWallet = walletKey != null && walletKey.isNotEmpty;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: widget.onBack,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Withdraw Funds (Solana)",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Wallet security requirement banner
              if (!hasWallet)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.shield_outlined, color: Colors.amber, size: 20),
                          SizedBox(width: 8),
                          Text(
                            "Solana Wallet Required",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Withdrawals on Tranyx are only available to verified Solana wallets. Please link your wallet first in Payment Methods.",
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () {
                          ref.read(profileViewProvider.notifier).state = 'payment';
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber[800],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text("Link Wallet in Payments", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield, color: Colors.green, size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        "Connected Solana Wallet: ",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                      Expanded(
                        child: Text(
                          "${walletKey.substring(0, 6)}...${walletKey.substring(walletKey.length - 6)}",
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Colors.green),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              // Withdrawable Balance Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "WITHDRAWABLE BALANCE",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: Colors.white70,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield_outlined, size: 13, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                "Instant Escrow",
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "₱ ${tyxBalance.toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Equivalent to ${tyxBalance.toStringAsFixed(0)} Tyxbits (1 Tyx = ₱1.00)",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Step 1: Amount
              Text(
                "1. ENTER WITHDRAWAL AMOUNT",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                ),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        prefixIcon: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            "₱",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: isDarkMode ? AppColors.indigo : AppColors.blue,
                            ),
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                        hintText: "0.00",
                        hintStyle: TextStyle(
                          fontSize: 24,
                          color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
                        ),
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() => _errorMessage = null),
                    ),
                    const Divider(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildPresetChip("₱100", 100, tyxBalance, isDarkMode),
                        _buildPresetChip("₱500", 500, tyxBalance, isDarkMode),
                        _buildPresetChip("₱1,000", 1000, tyxBalance, isDarkMode),
                        _buildPresetChip("₱5,000", 5000, tyxBalance, isDarkMode),
                        _buildPresetChip("MAX", tyxBalance, tyxBalance, isDarkMode, isMax: true),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Step 2: Solana Payout Destination
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "2. SOLANA PAYOUT DESTINATION",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDarkMode ? const Color(0xFF4F46E5).withValues(alpha: 0.15) : const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "Solana Only",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Destination Wallet Address",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: hasWallet ? Colors.green.withValues(alpha: 0.15) : Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            hasWallet ? "Linked" : "No Wallet Linked",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: hasWallet ? Colors.green : Colors.amber[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (hasWallet) ...[
                      Text(
                        "${walletKey.substring(0, 6)}...${walletKey.substring(walletKey.length - 6)}",
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? AppColors.indigo : AppColors.blue,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        "Select Payout Token:",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildCoinChip('USDT', 'USDT (SPL Token)', isDarkMode),
                          const SizedBox(width: 8),
                          _buildCoinChip('SOL', 'SOL (Native SOL)', isDarkMode),
                        ],
                      ),
                    ] else ...[
                      Text(
                        "Please link your Phantom, Solflare, or Trust wallet in Payment Methods to receive instant Solana payouts.",
                        style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF13131A) : const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow(
                      "Network Fee",
                      "Covered by Tranyx (0%)",
                      isHighlight: true,
                      isDarkMode: isDarkMode,
                    ),
                    const SizedBox(height: 8),
                    _buildSummaryRow(
                      "Estimated Settlement",
                      "Instant to 1 Hour",
                      isDarkMode: isDarkMode,
                    ),
                    const SizedBox(height: 8),
                    _buildSummaryRow(
                      "Minimum Withdrawal",
                      "₱ 100.00",
                      isDarkMode: isDarkMode,
                    ),
                  ],
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_successMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Submit Button
              _isSubmitting
                  ? const Center(child: CircularProgressIndicator())
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: hasWallet
                            ? () => _submitWithdrawal(tyxBalance, user?.uid ?? profile.uid, profile.name)
                            : null,
                        icon: const Icon(Icons.arrow_upward_rounded),
                        label: Text(hasWallet ? "Confirm & Withdraw via Solana" : "Link Solana Wallet to Withdraw"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3),
                          disabledForegroundColor: Colors.grey,
                        ),
                      ),
                    ),

              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPresetChip(String label, double amount, double maxBalance, bool isDarkMode, {bool isMax = false}) {
    return InkWell(
      onTap: () => _setPresetAmount(amount, maxBalance),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMax
              ? const Color(0xFF4F46E5).withValues(alpha: 0.15)
              : (isDarkMode ? const Color(0xFF27272A) : const Color(0xFFF3F4F6)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isMax ? const Color(0xFF4F46E5) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isMax
                ? const Color(0xFF4F46E5)
                : (isDarkMode ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildCoinChip(String coin, String label, bool isDarkMode) {
    final isSelected = _selectedCoin == coin;
    return InkWell(
      onTap: () => setState(() => _selectedCoin = coin),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF4F46E5).withValues(alpha: 0.15)
              : (isDarkMode ? const Color(0xFF27272A) : const Color(0xFFF3F4F6)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF4F46E5) : Colors.transparent,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? const Color(0xFF4F46E5) : (isDarkMode ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isHighlight = false, required bool isDarkMode}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isHighlight ? Colors.green : (isDarkMode ? Colors.white : Colors.black87),
          ),
        ),
      ],
    );
  }
}
