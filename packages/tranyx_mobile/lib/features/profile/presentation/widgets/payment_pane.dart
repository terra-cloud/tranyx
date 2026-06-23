import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';
import 'package:tranyx_mobile/flavors.dart';
import 'package:tranyx_mobile/core/utils/secure_storage_helper.dart';

final rawUserDocProvider =
    StreamProvider.autoDispose<DocumentSnapshot<Map<String, dynamic>>?>((ref) {
      final user = ref.watch(userProvider);
      if (user == null) return Stream.value(null);
      return ref
          .watch(firestoreProvider)
          .collection('users')
          .doc(user.uid)
          .snapshots();
    });

class WalletInfo {
  final String id;
  final String name;
  final String scheme;
  final String iosStoreUrl;
  final String androidStoreUrl;
  final String image;

  const WalletInfo({
    required this.id,
    required this.name,
    required this.scheme,
    required this.iosStoreUrl,
    required this.androidStoreUrl,
    required this.image,
  });
}

const List<WalletInfo> wallets = [
  WalletInfo(
    id: 'phantom',
    name: 'Phantom',
    scheme: 'phantom://',
    iosStoreUrl:
        'https://apps.apple.com/app/phantom-solana-wallet/id1598432977',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=app.phantom',
    image: 'assets/images/PhantomWallet.png',
  ),
  WalletInfo(
    id: 'solflare',
    name: 'Solflare',
    scheme: 'solflare://',
    iosStoreUrl:
        'https://apps.apple.com/app/solflare-solana-wallet/id1580902717',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=com.solflare.mobile',
    image: 'assets/images/Solflare.png',
  ),
];

class PaymentPane extends ConsumerStatefulWidget {
  final VoidCallback onBack;

  const PaymentPane({super.key, required this.onBack});

  @override
  ConsumerState<PaymentPane> createState() => _PaymentPaneState();
}

class _PaymentPaneState extends ConsumerState<PaymentPane> {
  final _amountController = TextEditingController();
  bool _isProcessing = false;
  Map<String, bool> _installedWallets = {};

  // Deposit sheet state
  String _selectedPaymentMethod = 'xendit'; // 'xendit' | 'solana'
  String _selectedSolanaCurrency = 'SOL';   // 'SOL' | 'USDT'
  double _solToPhpRate = 8000.0;
  double _usdToPhpRate = 57.0;
  double _solBalance = 0.0;
  bool _isFetchingRate = false;

  @override
  void initState() {
    super.initState();
    _checkInstalledWallets();
    _fetchRates();
  }

  Future<void> _fetchRates() async {
    if (!mounted) return;
    setState(() => _isFetchingRate = true);
    try {
      // Fetch SOL/PHP via CoinGecko (free, no key)
      try {
        await ref.read(phantomServiceProvider).fetchRecentBlockhash();
      } catch (_) {}

      final cgRes = await http.get(
        Uri.parse(
          'https://api.coingecko.com/api/v3/simple/price?ids=solana,tether&vs_currencies=php,usd',
        ),
      );
      if (cgRes.statusCode == 200) {
        final data = jsonDecode(cgRes.body) as Map<String, dynamic>;
        final sol = (data['solana']?['php'] as num?)?.toDouble();
        final usdt = (data['tether']?['php'] as num?)?.toDouble();
        if (mounted) {
          setState(() {
            if (sol != null && sol > 0) _solToPhpRate = sol;
            if (usdt != null && usdt > 0) _usdToPhpRate = usdt;
          });
        }
      }
    } catch (_) {
      // Use fallback rates silently
    } finally {
      if (mounted) setState(() => _isFetchingRate = false);
    }
  }

  Future<void> _fetchSolBalance(String pubkey) async {
    try {
      final rpcUrl = 'https://api.devnet.solana.com';
      final res = await http.post(
        Uri.parse(rpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'getBalance',
          'params': [pubkey],
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final lamports = (data['result']?['value'] as num?)?.toDouble() ?? 0.0;
        if (mounted) setState(() => _solBalance = lamports / 1e9);
      }
    } catch (_) {}
  }

  void _checkInstalledWallets() async {
    final Map<String, bool> status = {};
    for (final wallet in wallets) {
      bool installed = false;
      List<String> schemesToCheck = [wallet.scheme];

      if (wallet.id == 'trust') {
        schemesToCheck = [
          'trust://wc',
          'trustwallet://wc',
          'trust://open_url',
          'trustwallet://open_url',
          'trust://',
          'trustwallet://',
        ];
      } else if (wallet.id == 'phantom') {
        schemesToCheck = ['phantom://', 'phantom://v1/connect'];
      } else if (wallet.id == 'solflare') {
        schemesToCheck = ['solflare://', 'solflare://v1/connect'];
      } else if (wallet.id == 'backpack') {
        schemesToCheck = ['backpack://', 'backpack://v1/connect'];
      }

      for (final scheme in schemesToCheck) {
        try {
          final uri = Uri.parse(scheme);
          if (await canLaunchUrl(uri)) {
            installed = true;
            break;
          }
        } catch (_) {}
      }
      status[wallet.id] = installed;
    }
    if (mounted) {
      setState(() {
        _installedWallets = status;
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _showDepositSheet(double tyxBalance, String uid) {
    final userProfile = ref.read(userProfileProvider).value;
    final rawUserDoc = ref.read(rawUserDocProvider).value;
    final hasWallet =
        userProfile?.walletPublicKey != null &&
        userProfile!.walletPublicKey!.isNotEmpty;
    final connectedWalletType =
        rawUserDoc?.data()?['connectedWalletType'] as String? ??
        (hasWallet ? 'phantom' : null);

    // Fetch SOL balance once sheet opens
    if (hasWallet) {
      _fetchSolBalance(userProfile.walletPublicKey!);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isDarkMode = ref.read(themeModeProvider);
            final phpAmount =
                double.tryParse(_amountController.text.trim()) ?? 0.0;
            final isSolana = _selectedPaymentMethod == 'solana';
            final isSOL = _selectedSolanaCurrency == 'SOL';
            final amountInSol =
                phpAmount > 0 ? phpAmount / _solToPhpRate : 0.0;
            final amountInUsdt =
                phpAmount > 0 ? phpAmount / _usdToPhpRate : 0.0;

            void onAmountChanged() => setSheetState(() {});
            _amountController.removeListener(onAmountChanged);
            _amountController.addListener(onAmountChanged);

            final cardColor =
                isDarkMode ? const Color(0xFF1A1A2E) : const Color(0xFFF8F8FC);
            final borderColor = isDarkMode
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.07);

            // ── Quick chip presets ────────────────────────────────────
            Widget quickChips() {
              final presets = [500, 1000, 2000, 5000, 10000];
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presets.map((v) {
                  final selected = phpAmount == v.toDouble();
                  return GestureDetector(
                    onTap: () {
                      _amountController.text = v.toString();
                      setSheetState(() {});
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.indigo
                            : (isDarkMode
                                  ? Colors.white.withValues(alpha: 0.07)
                                  : Colors.white),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? AppColors.indigo
                              : borderColor,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: AppColors.indigo.withValues(
                                    alpha: 0.25,
                                  ),
                                  blurRadius: 8,
                                ),
                              ]
                            : [],
                      ),
                      child: Text(
                        '₱${v >= 1000 ? '${v ~/ 1000},000' : '$v'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: selected ? Colors.white : null,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            }

            // ── Method selector card ──────────────────────────────────
            Widget methodCard({
              required String id,
              required IconData icon,
              required String label,
              required Color accent,
            }) {
              final sel = _selectedPaymentMethod == id;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setSheetState(() => _selectedPaymentMethod = id);
                    setState(() => _selectedPaymentMethod = id);
                    if (id == 'solana') _fetchRates();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: sel
                          ? accent.withValues(alpha: 0.1)
                          : cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? accent : borderColor,
                        width: sel ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: sel ? accent : Colors.grey, size: 26),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: sel ? accent : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // ── SOL / USDT sub-toggle ─────────────────────────────────
            Widget currencyToggle() {
              return Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setSheetState(
                        () => _selectedSolanaCurrency = 'SOL',
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSOL
                              ? const Color(0xFF512DA8)
                              : cardColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSOL
                                ? const Color(0xFF512DA8)
                                : borderColor,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '◎ SOL',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color:
                                  isSOL ? Colors.white : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setSheetState(
                        () => _selectedSolanaCurrency = 'USDT',
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !isSOL
                              ? const Color(0xFF059669)
                              : cardColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: !isSOL
                                ? const Color(0xFF059669)
                                : borderColor,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '\$ USDT',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: !isSOL ? Colors.white : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            // ── Rate info card ────────────────────────────────────────
            Widget rateCard() {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isSOL) ...[
                      _rateRow(
                        'Exchange Rate',
                        _isFetchingRate
                            ? 'Fetching...'
                            : '1 SOL = ₱${_solToPhpRate.toStringAsFixed(2)}',
                        isDarkMode,
                        loading: _isFetchingRate,
                      ),
                      const SizedBox(height: 10),
                      _rateRow(
                        'Required SOL',
                        '${amountInSol.toStringAsFixed(5)} SOL',
                        isDarkMode,
                        valueBold: true,
                        valueColor: const Color(0xFF805AD5),
                      ),
                    ] else ...[
                      _rateRow(
                        'USDT Rate (Stablecoin)',
                        '\$1 USDT ≈ ₱${_usdToPhpRate.toStringAsFixed(2)}',
                        isDarkMode,
                      ),
                      const SizedBox(height: 10),
                      _rateRow(
                        'Required USDT',
                        '\$${amountInUsdt.toStringAsFixed(2)} USDT',
                        isDarkMode,
                        valueBold: true,
                        valueColor: const Color(0xFF059669),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(
                              0xFF059669,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'USDT is a stablecoin — zero volatility risk!',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (hasWallet) ...[
                      Divider(
                        height: 20,
                        color: borderColor,
                      ),
                      _rateRow(
                        'Wallet Address',
                        () {
                          final addr =
                              userProfile.walletPublicKey ?? '';
                          return addr.length > 12
                              ? '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}'
                              : addr;
                        }(),
                        isDarkMode,
                        mono: true,
                      ),
                      const SizedBox(height: 6),
                      _rateRow(
                        'SOL Balance',
                        '${_solBalance.toStringAsFixed(4)} SOL',
                        isDarkMode,
                        valueBold: true,
                      ),
                    ],
                  ],
                ),
              );
            }

            // ── Xendit info card ──────────────────────────────────────
            Widget xenditCard() {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  children: [
                    _rateRow('Payment Processor', 'Xendit Gateway', isDarkMode),
                    const SizedBox(height: 8),
                    _rateRow(
                      'Tyxbit Equivalent',
                      '${phpAmount.toStringAsFixed(2)} Tyxbits',
                      isDarkMode,
                    ),
                    _rateRow(
                      'Processor Status',
                      'Awaiting Checkout',
                      isDarkMode,
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.92,
                ),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? const Color(0xFF12121C)
                      : Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Handle + Header ─────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
                      child: Column(
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.indigo.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.account_balance_wallet_outlined,
                                  color: AppColors.indigo,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Top-up Tyxbit Balance',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '1 PHP = 1 Tyxbit',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(sheetContext),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ── Scrollable body ──────────────────────────────
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Amount input
                            TextField(
                              controller: _amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                prefixText: '₱  ',
                                prefixStyle: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.indigo,
                                ),
                                hintText: '0.00',
                                hintStyle: TextStyle(
                                  fontSize: 24,
                                  color: AppColors.indigo.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: AppColors.indigo.withValues(
                                      alpha: 0.3,
                                    ),
                                    width: 2,
                                  ),
                                ),
                                focusedBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: AppColors.indigo,
                                    width: 2,
                                  ),
                                ),
                                border: InputBorder.none,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Center(
                              child: Text(
                                'Min ₱100 · Max ₱50,000 per transaction',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Quick chips
                            Center(child: quickChips()),
                            const SizedBox(height: 24),

                            // Payment method selector
                            Row(
                              children: [
                                methodCard(
                                  id: 'xendit',
                                  icon: Icons.credit_card_outlined,
                                  label: 'GCash / Card',
                                  accent: AppColors.indigo,
                                ),
                                const SizedBox(width: 12),
                                methodCard(
                                  id: 'solana',
                                  icon: Icons.bolt,
                                  label: 'Solana (SOL)',
                                  accent: const Color(0xFF512DA8),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Dynamic content by method
                            if (!isSolana) ...[
                              xenditCard(),
                              const SizedBox(height: 20),
                              // Xendit CTA
                              _isProcessing
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : _buildXenditButton(
                                      uid: uid,
                                      phpAmount: phpAmount,
                                      userProfile: userProfile,
                                      sheetContext: sheetContext,
                                    ),
                            ] else ...[
                              // SOL / USDT sub-toggle
                              currencyToggle(),
                              const SizedBox(height: 16),
                              rateCard(),
                              const SizedBox(height: 20),
                              // Solana CTA
                              _isProcessing
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : _buildSolanaCTA(
                                      uid: uid,
                                      phpAmount: phpAmount,
                                      userProfile: userProfile,
                                      connectedWalletType: connectedWalletType,
                                      hasWallet: hasWallet,
                                      amountInSol: amountInSol,
                                      amountInUsdt: amountInUsdt,
                                      isSOL: isSOL,
                                      sheetContext: sheetContext,
                                    ),
                            ],

                            // Cancel
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: Colors.grey.withValues(alpha: 0.8),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Footer ───────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: Colors.grey.withValues(alpha: 0.05),
                      width: double.infinity,
                      child: Center(
                        child: Text(
                          isSolana
                              ? 'POWERED BY SOLANA SECURE'
                              : 'POWERED BY XENDIT & TRANYX SECURE',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _rateRow(
    String label,
    String value,
    bool isDarkMode, {
    bool valueBold = false,
    Color? valueColor,
    bool mono = false,
    bool loading = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.withValues(alpha: 0.8),
          ),
        ),
        loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            : Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      valueBold ? FontWeight.bold : FontWeight.w600,
                  color: valueColor,
                  fontFamily: mono ? 'monospace' : null,
                ),
              ),
      ],
    );
  }

  Widget _buildXenditButton({
    required String uid,
    required double phpAmount,
    required dynamic userProfile,
    required BuildContext sheetContext,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.indigo,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
        ),
        onPressed: phpAmount < 100
            ? null
            : () async {
                if (phpAmount <= 0) return;
                setState(() => _isProcessing = true);
                Navigator.pop(sheetContext);
                try {
                  final userName = userProfile?.name ?? 'User';
                  final res = await ref
                      .read(transitRepositoryProvider)
                      .createXenditInvoice(
                        uid: uid,
                        amount: phpAmount,
                        userName: userName,
                      );
                  final invoiceId = res['id'] as String;
                  final invoiceUrl = res['invoice_url'] as String;
                  await ref
                      .read(firestoreProvider)
                      .collection('users')
                      .doc(uid)
                      .update({
                        'pendingXenditInvoiceId': invoiceId,
                        'pendingXenditInvoiceAmount': phpAmount,
                        'pendingXenditInvoiceUrl': invoiceUrl,
                      });
                  _amountController.clear();
                  try {
                    final uri = Uri.parse(invoiceUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  } catch (_) {}
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Invoice created. Launching checkout for ₱ ${phpAmount.toStringAsFixed(2)}',
                        ),
                        backgroundColor: Colors.indigo,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error creating invoice: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } finally {
                  setState(() => _isProcessing = false);
                }
              },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.credit_card, size: 18),
            const SizedBox(width: 8),
            Text(
              phpAmount < 100
                  ? 'Enter at least ₱100'
                  : 'Pay ₱${phpAmount.toStringAsFixed(2)} with Xendit',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSolanaCTA({
    required String uid,
    required double phpAmount,
    required dynamic userProfile,
    required String? connectedWalletType,
    required bool hasWallet,
    required double amountInSol,
    required double amountInUsdt,
    required bool isSOL,
    required BuildContext sheetContext,
  }) {
    if (!hasWallet || connectedWalletType == null) {
      // No wallet connected — show connect prompt
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF512DA8),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 0,
          ),
          onPressed: () {
            Navigator.pop(sheetContext);
            // Scroll down to wallet section
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Connect a Solana wallet below to deposit with SOL.',
                ),
                backgroundColor: Color(0xFF512DA8),
              ),
            );
          },
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 18),
              SizedBox(width: 8),
              Text(
                'Connect Solana Wallet',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    if (isSOL && _solBalance < amountInSol && phpAmount > 0) {
      // Insufficient SOL
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Text(
          'Insufficient SOL Balance\nNeed: ${amountInSol.toStringAsFixed(4)} SOL  ·  Have: ${_solBalance.toStringAsFixed(4)} SOL',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
      );
    }

    final label = isSOL
        ? 'Pay ${amountInSol.toStringAsFixed(4)} SOL'
        : 'Pay \$${amountInUsdt.toStringAsFixed(2)} USDT';
    final btnColor =
        isSOL ? const Color(0xFF512DA8) : const Color(0xFF059669);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: phpAmount < 100 ? Colors.grey : btnColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
        ),
        onPressed: phpAmount < 100
            ? null
            : () async {
                if (!isSOL) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'USDT deposits are web-only on mobile devices. Please select SOL or GCash/Card instead.',
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.pop(sheetContext);
                _amountController.clear();
                await _handleSolanaDeposit(
                  uid: uid,
                  phpAmount: phpAmount,
                  cryptoAmount: amountInSol,
                  walletType: connectedWalletType,
                  userPubkey: userProfile!.walletPublicKey!,
                );
              },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isSOL ? Icons.bolt : Icons.attach_money, size: 18),
            const SizedBox(width: 8),
            Text(
              phpAmount < 100 ? 'Enter at least ₱100' : label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _handleVerifyPayment(String uid, String invoiceId, double amount) async {
    setState(() => _isProcessing = true);
    try {
      final isPaid = await ref
          .read(transitRepositoryProvider)
          .verifyXenditPayment(uid: uid, invoiceId: invoiceId, amount: amount);

      if (isPaid) {
        // Clear pending invoice from Firestore
        await ref.read(firestoreProvider).collection('users').doc(uid).update({
          'pendingXenditInvoiceId': FieldValue.delete(),
          'pendingXenditInvoiceAmount': FieldValue.delete(),
          'pendingXenditInvoiceUrl': FieldValue.delete(),
        });
        ref.invalidate(userProfileProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment Verified! Balance credited successfully.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invoice is still unpaid or pending.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _handleCancelInvoice(String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Pending Invoice'),
        content: const Text(
          'Are you sure you want to cancel and dismiss this pending Xendit invoice?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel Invoice'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isProcessing = true);
      try {
        await ref.read(firestoreProvider).collection('users').doc(uid).update({
          'pendingXenditInvoiceId': FieldValue.delete(),
          'pendingXenditInvoiceAmount': FieldValue.delete(),
          'pendingXenditInvoiceUrl': FieldValue.delete(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pending invoice dismissed.'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to cancel invoice: $e')),
          );
        }
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _handleConnectWallet(String uid, WalletInfo wallet) async {
    setState(() => _isProcessing = true);
    try {
      final phantomService = ref.read(phantomServiceProvider);
      final connectUri = await phantomService.generateConnectUri(
        walletType: wallet.id,
      );

      debugPrint('Launching wallet deep link connect URI: $connectUri');
      final launched = await launchUrl(
        connectUri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw 'Could not launch wallet application. Make sure the wallet app is installed.';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Wallet connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleSolanaDeposit({
    required String uid,
    required double phpAmount,
    required double cryptoAmount,
    required String walletType,
    required String userPubkey,
  }) async {
    setState(() => _isProcessing = true);

    const String kSystemSolanaReceiverAddress =
        '4zMMC4mCK23ccaJ2rbzn36gkJr2cT6w9P5BmgFniS59D';

    try {
      // Phantom / Solflare: NaCl Encryption Deep-link redirect
      // 1. Save pending state to SecureStorage
      await SecureStorageHelper.savePendingDepositPhpAmount(phpAmount);
      await SecureStorageHelper.savePendingDepositCryptoAmount(cryptoAmount);
      await SecureStorageHelper.savePendingDepositCurrency('SOL');

      // 2. Generate signing link
      final phantomService = ref.read(phantomServiceProvider);
      final signUri = await phantomService.generateSignTransactionUri(
        walletType: walletType,
        senderPubkey: userPubkey,
        receiverPubkey: kSystemSolanaReceiverAddress,
        amountInSol: cryptoAmount,
      );

      debugPrint('Launching wallet sign URI: $signUri');
      final launched = await launchUrl(
        signUri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw 'Could not launch wallet app. Make sure it is installed.';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Solana Deposit failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }


  void _handleDisconnectWallet(String uid, WalletInfo wallet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Disconnect ${wallet.name}'),
        content: Text(
          'Are you sure you want to disconnect your ${wallet.name} wallet?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isProcessing = true);
      try {
        await ref.read(firestoreProvider).collection('users').doc(uid).update({
          'walletPublicKey': null,
          'connectedWalletType': null,
        });

        ref.invalidate(userProfileProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${wallet.name} wallet disconnected.'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to disconnect: $e')));
        }
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _handleWithdraw(double tyxBalance, String uid) async {
    final userProfile = ref.read(userProfileProvider).value;
    if (userProfile == null) return;

    if (userProfile.walletPublicKey == null ||
        userProfile.walletPublicKey!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please connect a Solana wallet first before withdrawing.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (tyxBalance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No earnings available for withdrawal')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Withdrawal'),
        content: Text(
          'Are you sure you want to withdraw your entire balance of ₱ ${tyxBalance.toStringAsFixed(2)} to your connected Solana wallet?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isProcessing = true);
      try {
        // Mock withdraw by setting balance to 0 and writing transaction
        await ref.read(transitRepositoryProvider).updateTyxBalance(uid, 0);
        final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
        await ref
            .read(firestoreProvider)
            .collection('transactions')
            .doc(txId)
            .set({
              'uid': uid,
              'type': 'withdraw',
              'amount': tyxBalance,
              'title': 'Earnings Withdrawn',
              'desc': 'Withdrew all earnings payout to Solana Wallet address',
              'method': 'Tranyx Wallet',
              'createdAt': DateTime.now().millisecondsSinceEpoch,
            });

        ref.invalidate(userProfileProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Withdrawal successful! Payout sent to Solana wallet.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Withdrawal failed: $e')));
        }
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final userProfile = ref.watch(userProfileProvider).value;
    final transactionsAsync = ref.watch(userTransactionsProvider);
    final rawUserDocAsync = ref.watch(rawUserDocProvider);

    if (userProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final rawUserDoc = rawUserDocAsync.value;
    final pendingInvoiceId =
        rawUserDoc?.data()?['pendingXenditInvoiceId'] as String?;
    final pendingInvoiceAmount =
        (rawUserDoc?.data()?['pendingXenditInvoiceAmount'] as num?)?.toDouble();
    final pendingInvoiceUrl =
        rawUserDoc?.data()?['pendingXenditInvoiceUrl'] as String?;

    final connectedWalletType =
        rawUserDoc?.data()?['connectedWalletType'] as String? ??
        (userProfile.walletPublicKey != null &&
                userProfile.walletPublicKey!.isNotEmpty
            ? 'phantom'
            : null);
    final hasWallet =
        userProfile.walletPublicKey != null &&
        userProfile.walletPublicKey!.isNotEmpty;

    final tyxBalance = userProfile.tyxBalance;
    final uid = userProfile.uid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
              onPressed: widget.onBack,
            ),
            const SizedBox(width: 8),
            const Text(
              'Payment Methods',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Wallet Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: const LinearGradient(
              colors: [AppColors.indigo, AppColors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.indigo.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TYXBIT MAIN WALLET',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withValues(alpha: 0.7),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userProfile.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    '₱ ',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    tyxBalance.toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'tranyx-tyxbit-v1 :: ${uid.substring(0, min(8, uid.length))}',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (F.appFlavor != Flavor.production) ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.arrow_downward, size: 16),
                        label: const Text(
                          'Deposit',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed: () => _showDepositSheet(tyxBalance, uid),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.arrow_upward, size: 16),
                      label: const Text(
                        'Withdraw',
                        style: TextStyle(fontSize: 12),
                      ),
                      onPressed: () => _handleWithdraw(tyxBalance, uid),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (pendingInvoiceId != null) ...[
          const SizedBox(height: 24),
          const Text(
            'Pending Deposit',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pending_actions, color: Colors.amber),
                        const SizedBox(width: 8),
                        Text(
                          'Xendit Checkout',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'PENDING',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Amount',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₱ ${pendingInvoiceAmount?.toStringAsFixed(2) ?? "0.00"}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Invoice ID',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${pendingInvoiceId.substring(0, min(12, pendingInvoiceId.length))}...',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.payment, size: 14),
                        label: const Text(
                          'Pay Now',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () async {
                          if (pendingInvoiceUrl != null) {
                            final uri = Uri.parse(pendingInvoiceUrl);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.indigo,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline, size: 14),
                        label: const Text(
                          'Verify',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _isProcessing
                            ? null
                            : () => _handleVerifyPayment(
                                uid,
                                pendingInvoiceId,
                                pendingInvoiceAmount ?? 0.0,
                              ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: _isProcessing
                          ? null
                          : () => _handleCancelInvoice(uid),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // Connected Solana Wallet Section
        const SizedBox(height: 24),
        const Text(
          'Linked Solana Wallet',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Column(
          children: wallets.map((wallet) {
            final isInstalled = _installedWallets[wallet.id] ?? false;
            final isConnected = hasWallet && connectedWalletType == wallet.id;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isConnected
                      ? Colors.purple
                      : (isDarkMode
                            ? AppColors.darkBorder
                            : AppColors.lightBorder),
                  width: isConnected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isConnected
                            ? Colors.purple.withValues(alpha: 0.5)
                            : (isDarkMode ? Colors.white12 : Colors.black12),
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.asset(
                        wallet.image,
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            isConnected
                                ? Icons.link
                                : Icons.account_balance_wallet,
                            color: isConnected ? Colors.purple : Colors.grey,
                            size: 20,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              wallet.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (isConnected) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Active',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.purple,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isConnected
                              ? '${userProfile.walletPublicKey!.substring(0, min(8, userProfile.walletPublicKey!.length))}...${userProfile.walletPublicKey!.substring(max(0, userProfile.walletPublicKey!.length - 8))}'
                              : (isInstalled
                                    ? 'Tap to connect Solana Wallet'
                                    : 'Not installed'),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDarkMode
                                ? AppColors.darkTextMuted
                                : AppColors.lightTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : isInstalled
                      ? ElevatedButton(
                          onPressed: () {
                            if (isConnected) {
                              _handleDisconnectWallet(uid, wallet);
                            } else {
                              if (hasWallet) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please disconnect your active wallet first before connecting another one.',
                                    ),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              } else {
                                _handleConnectWallet(uid, wallet);
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isConnected
                                ? Colors.red.withValues(alpha: 0.1)
                                : AppColors.indigo,
                            foregroundColor: isConnected
                                ? Colors.red
                                : Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            isConnected ? 'Disconnect' : 'Connect',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : OutlinedButton(
                          onPressed: () async {
                            final isIOS =
                                Theme.of(context).platform ==
                                TargetPlatform.iOS;
                            final storeUrl = isIOS
                                ? wallet.iosStoreUrl
                                : wallet.androidStoreUrl;
                            final uri = Uri.parse(storeUrl);
                            try {
                              // For simulator/iOS, using inAppWebView avoids "Safari cannot open..." scheme issues.
                              await launchUrl(
                                uri,
                                mode: LaunchMode.inAppWebView,
                              );
                            } catch (e) {
                              try {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.platformDefault,
                                );
                              } catch (_) {}
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.indigo,
                            side: const BorderSide(color: AppColors.indigo),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Install',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ],
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 32),

        const Text(
          'Transaction Log',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // Transactions List
        transactionsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, stack) {
            debugPrint('Transaction log error: $err');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('Error: $err')),
            );
          },
          data: (txList) {
            if (txList.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'No transactions recorded yet',
                    style: TextStyle(
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(0),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: txList.length,
              itemBuilder: (context, index) {
                final tx = txList[index];
                final isDeposit =
                    tx['type'] == 'deposit' || tx['type'] == 'refund';
                final isWithdraw = tx['type'] == 'withdraw';
                final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                final title = tx['title'] as String? ?? 'Transaction';
                final desc = tx['desc'] as String? ?? '';
                final dateVal = tx['createdAt'] as int? ?? 0;
                final dateStr = DateFormat(
                  'MMM dd, yyyy • hh:mm a',
                ).format(DateTime.fromMillisecondsSinceEpoch(dateVal));

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? AppColors.darkCard
                        : AppColors.lightCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDarkMode
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDeposit
                              ? Colors.green.withValues(alpha: 0.1)
                              : isWithdraw
                              ? Colors.blue.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isDeposit
                              ? Icons.add_circle_outline
                              : isWithdraw
                              ? Icons.remove_circle_outline
                              : Icons.swap_horiz,
                          color: isDeposit
                              ? Colors.green
                              : isWithdraw
                              ? Colors.blue
                              : Colors.orange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              desc,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 10,
                                color: isDarkMode
                                    ? AppColors.darkTextMuted.withValues(
                                        alpha: 0.7,
                                      )
                                    : AppColors.lightTextMuted.withValues(
                                        alpha: 0.7,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${isDeposit ? "+" : "-"}${amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDeposit ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
