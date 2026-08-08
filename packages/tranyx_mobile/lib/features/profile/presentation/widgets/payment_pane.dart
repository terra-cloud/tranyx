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
import 'package:tranyx_mobile/core/services/trust_wallet_service.dart';
import 'package:reown_appkit/reown_appkit.dart';
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
  WalletInfo(
    id: 'trust',
    name: 'Trust Wallet',
    scheme: 'trust://',
    iosStoreUrl:
        'https://apps.apple.com/app/trust-crypto-bitcoin-wallet/id1288339409',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=com.wallet.crypto.trustapp',
    image: 'assets/images/TrustWallet.jpeg',
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
  final _promoRedeemController = TextEditingController();
  bool _isProcessing = false;
  Map<String, bool> _installedWallets = {};

  String? _redeemFeedback;
  bool _isRedeeming = false;

  // Trust Wallet AppKit modal (kept alive for session requests)
  ReownAppKitModal? _trustModal;

  // Deposit sheet state
  String _selectedPaymentMethod = 'xendit'; // 'xendit' | 'solana'
  String _selectedSolanaCurrency = 'SOL'; // 'SOL' | 'USDT'
  double _solToPhpRate = 8000.0;
  double _usdToPhpRate = 57.0;
  double _solBalance = 0.0;
  double _usdtBalance = 0.0;
  bool _isFetchingRate = false;

  // Real-time SOL balance polling
  Timer? _balancePollingTimer;
  String? _lastPolledPubkey;

  @override
  void initState() {
    super.initState();
    _checkInstalledWallets();
    _fetchRates();
  }

  @override
  void dispose() {
    _trustModal?.dispose();
    _stopBalancePolling();
    _amountController.dispose();
    _promoRedeemController.dispose();
    super.dispose();
  }

  void _handleRedeemPromo(String code, String uid) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) {
      setState(() {
        _redeemFeedback = 'Please enter a promo code.';
      });
      return;
    }

    setState(() {
      _isRedeeming = true;
      _redeemFeedback = null;
    });

    try {
      final repo = ref.read(transitRepositoryProvider);
      final promo = await repo.getPromo(cleanCode);
      if (promo == null) {
        setState(() {
          _redeemFeedback = 'Promo code not found.';
        });
        return;
      }
      if (!promo.isActive) {
        setState(() {
          _redeemFeedback = 'This promo code is inactive.';
        });
        return;
      }
      if (promo.expirationDate != null && promo.expirationDate!.isBefore(DateTime.now())) {
        setState(() {
          _redeemFeedback = 'This promo code has expired.';
        });
        return;
      }
      if (promo.maxUsers != null && promo.usedCount >= promo.maxUsers!) {
        setState(() {
          _redeemFeedback = 'This promo code has reached its usage limit.';
        });
        return;
      }
      if (promo.isSingleUsePerUser && promo.usedBy.contains(uid)) {
        setState(() {
          _redeemFeedback = 'You have already used this promo code.';
        });
        return;
      }

      // Check eligible user UIDs list
      if (promo.eligibleUserUids != null &&
          promo.eligibleUserUids!.isNotEmpty &&
          !promo.eligibleUserUids!.contains(uid)) {
        setState(() {
          _redeemFeedback = 'You are not eligible for this promotion.';
        });
        return;
      }

      // Fetch user profile to check subscription status, hybrid status, and roles
      final profile = ref.read(userProfileProvider).value;
      if (profile != null) {
        if (profile.disabledPromos.contains(cleanCode)) {
          setState(() {
            _redeemFeedback = 'You have disabled this promotion and cannot re-enable it.';
          });
          return;
        }

        // Checking subscribed-only requirement
        if (promo.onlyForSubscribed && !profile.isPremium) {
          setState(() {
            _redeemFeedback = 'This promo code is only for premium subscribed accounts.';
          });
          return;
        }

        // Checking hybrid-only requirement
        if (promo.onlyForHybrid && profile.accountType != AccountType.hybrid) {
          setState(() {
            _redeemFeedback = 'This promo code is only for hybrid accounts.';
          });
          return;
        }

        // Checking targeted roles requirement
        if (promo.applicableRoles.isNotEmpty) {
          final userRoles = <String>[];
          if (profile.accountType == AccountType.employer) {
            userRoles.addAll(['renter', 'employer']);
          } else if (profile.accountType == AccountType.nyxian) {
            userRoles.addAll(['host', 'nyxian']);
          } else if (profile.accountType == AccountType.hybrid) {
            userRoles.addAll(['renter', 'host', 'employer', 'nyxian']);
          }

          final hasMatchingRole = promo.applicableRoles.any((r) => userRoles.contains(r));
          if (!hasMatchingRole) {
            setState(() {
              _redeemFeedback = 'You do not have the required role to use this promotion.';
            });
            return;
          }
        }
      }

      await repo.redeemPromoToProfile(uid, promo);
      
      // Invalidate profile to show active promo
      ref.invalidate(userProfileProvider);

      setState(() {
        _redeemFeedback = 'Promo code redeemed successfully to profile!';
        _promoRedeemController.clear();
      });
    } catch (e) {
      setState(() {
        _redeemFeedback = 'Failed to redeem: $e';
      });
    } finally {
      setState(() {
        _isRedeeming = false;
      });
    }
  }

  void _handleDisablePromo(BuildContext context, String code, String uid) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable Promo Code?'),
        content: Text('Are you sure you want to disable the promo code "$code"? Once disabled, you will lose the discount and can never re-enable or redeem it again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Disable'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isRedeeming = true;
      _redeemFeedback = null;
    });

    try {
      final repo = ref.read(transitRepositoryProvider);
      await repo.disablePromoForUser(uid, code);
      ref.invalidate(userProfileProvider);
      setState(() {
        _redeemFeedback = 'Promo code "$code" disabled permanently.';
      });
    } catch (e) {
      setState(() {
        _redeemFeedback = 'Failed to disable promo: $e';
      });
    } finally {
      setState(() {
        _isRedeeming = false;
      });
    }
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
      final rpcUrl = ref.read(phantomServiceProvider).rpcUrl;

      // Fetch SOL balance
      final solRes = await http.post(
        Uri.parse(rpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'getBalance',
          'params': [pubkey],
        }),
      );
      if (solRes.statusCode == 200) {
        final data = jsonDecode(solRes.body);
        final lamports = (data['result']?['value'] as num?)?.toDouble() ?? 0.0;
        if (mounted) setState(() => _solBalance = lamports / 1e9);
      }

      // Fetch USDT token balance via getTokenAccountsByOwner
      final usdtMint = ref.read(phantomServiceProvider).usdtMintAddress;
      final tokenRes = await http.post(
        Uri.parse(rpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'getTokenAccountsByOwner',
          'params': [
            pubkey,
            {'mint': usdtMint},
            {'encoding': 'jsonParsed'},
          ],
        }),
      );
      if (tokenRes.statusCode == 200) {
        final tokenData = jsonDecode(tokenRes.body);
        final accounts = tokenData['result']?['value'] as List<dynamic>? ?? [];
        double totalUsdt = 0.0;
        for (final account in accounts) {
          final amount = account['account']?['data']?['parsed']?['info']
              ?['tokenAmount']?['uiAmount'];
          if (amount != null) totalUsdt += (amount as num).toDouble();
        }
        if (mounted) setState(() => _usdtBalance = totalUsdt);
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
        schemesToCheck = ['solflare://', 'solflare://ul/v1/connect', 'solflare://v1/connect'];
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

  /// Starts a periodic timer that refreshes the on-chain SOL balance every
  /// 10 seconds. If a timer is already running for the same pubkey it is a
  /// no-op; if the pubkey changed the old timer is cancelled first.
  void _startBalancePolling(String pubkey) {
    if (_lastPolledPubkey == pubkey && _balancePollingTimer?.isActive == true) {
      return; // already polling for this key
    }
    _stopBalancePolling();
    _lastPolledPubkey = pubkey;
    // Fetch immediately, then every 10 s.
    _fetchSolBalance(pubkey);
    _balancePollingTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _fetchSolBalance(pubkey),
    );
  }

  void _stopBalancePolling() {
    _balancePollingTimer?.cancel();
    _balancePollingTimer = null;
    _lastPolledPubkey = null;
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

    // Balance is kept up-to-date by the periodic timer started in build().
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
            final amountInSol = phpAmount > 0 ? phpAmount / _solToPhpRate : 0.0;
            final amountInUsdt = phpAmount > 0
                ? phpAmount / _usdToPhpRate
                : 0.0;

            void onAmountChanged() => setSheetState(() {});
            _amountController.removeListener(onAmountChanged);
            _amountController.addListener(onAmountChanged);

            final cardColor = isDarkMode
                ? const Color(0xFF1A1A2E)
                : const Color(0xFFF8F8FC);
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
                          color: selected ? AppColors.indigo : borderColor,
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
                      color: sel ? accent.withValues(alpha: 0.1) : cardColor,
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
                      onTap: () =>
                          setSheetState(() => _selectedSolanaCurrency = 'SOL'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSOL ? const Color(0xFF512DA8) : cardColor,
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
                              color: isSOL ? Colors.white : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          setSheetState(() => _selectedSolanaCurrency = 'USDT'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !isSOL ? const Color(0xFF059669) : cardColor,
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
                      Divider(height: 20, color: borderColor),
                      _rateRow(
                        'Wallet Address',
                        () {
                          final addr = userProfile.walletPublicKey ?? '';
                          return addr.length > 12
                              ? '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}'
                              : addr;
                        }(),
                        isDarkMode,
                        mono: true,
                      ),
                      const SizedBox(height: 6),
                      isSOL
                          ? _rateRow(
                              'SOL Balance',
                              '${_solBalance.toStringAsFixed(4)} SOL',
                              isDarkMode,
                              valueBold: true,
                              valueColor: const Color(0xFF805AD5),
                            )
                          : _rateRow(
                              'USDT Balance',
                              '\$${_usdtBalance.toStringAsFixed(2)} USDT',
                              isDarkMode,
                              valueBold: true,
                              valueColor: const Color(0xFF059669),
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
                  color: isDarkMode ? const Color(0xFF12121C) : Colors.white,
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
                                  label: 'Solana Wallet',
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
                  fontWeight: valueBold ? FontWeight.bold : FontWeight.w600,
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
                        mode: LaunchMode.inAppBrowserView,
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
    final btnColor = isSOL ? const Color(0xFF512DA8) : const Color(0xFF059669);

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
                Navigator.pop(sheetContext);
                _amountController.clear();
                if (isSOL) {
                  await _handleSolanaDeposit(
                    uid: uid,
                    phpAmount: phpAmount,
                    cryptoAmount: amountInSol,
                    walletType: connectedWalletType,
                    userPubkey: userProfile!.walletPublicKey!,
                  );
                } else {
                  await _handleUsdtDeposit(
                    uid: uid,
                    phpAmount: phpAmount,
                    amountInUsdt: amountInUsdt,
                    walletType: connectedWalletType,
                    userPubkey: userProfile!.walletPublicKey!,
                  );
                }
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
    if (wallet.id == 'trust') {
      await _handleConnectTrustWallet(uid);
      return;
    }
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

  Future<void> _handleMobileAccountChanged(String newAddress, String walletType) async {
    setState(() {
      _solBalance = 0.0;
      _usdtBalance = 0.0;
      _isProcessing = false;
      _amountController.clear();
    });

    final user = ref.read(userProvider);
    if (user != null) {
      final currentProfile = ref.read(userProfileProvider).value;
      if (currentProfile?.walletPublicKey != newAddress) {
        await ref.read(authControllerProvider).signOut();
        ref.invalidate(userProfileProvider);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Wallet account switched. Logged out.'),
              backgroundColor: Colors.amber,
            ),
          );
        }
      }
    }

    try {
      final walletLinkDoc = await ref
          .read(firestoreProvider)
          .collection('walletLinks')
          .doc(newAddress)
          .get();
      if (walletLinkDoc.exists) {
        final linkData = walletLinkDoc.data();
        final email = linkData?['email'] as String?;
        final obfuscatedPassword = linkData?['password'] as String?;
        if (email != null && obfuscatedPassword != null && obfuscatedPassword.isNotEmpty) {
          final password = SecureStorageHelper.deobfuscate(obfuscatedPassword);
          await ref
              .read(firebaseAuthProvider)
              .signInWithEmailAndPassword(
                email: email,
                password: password,
              );
          ref.invalidate(userProfileProvider);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Switched to account linked with: $newAddress'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        ref.read(pendingWalletPublicKeyProvider.notifier).state = newAddress;
        ref.read(authViewProvider.notifier).state = 'register-path';
      }
    } catch (_) {}
  }

  Future<void> _handleMobileDisconnect() async {
    setState(() {
      _solBalance = 0.0;
      _usdtBalance = 0.0;
      _isProcessing = false;
      _amountController.clear();
    });

    await ref.read(authControllerProvider).signOut();
    ref.invalidate(userProfileProvider);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wallet disconnected. Logged out.'),
          backgroundColor: Colors.amber,
        ),
      );
    }
  }

  /// Opens the Reown AppKit modal so the user can connect Trust Wallet
  /// via WalletConnect v2. Phantom and Solflare are NOT affected.
  Future<void> _handleConnectTrustWallet(String uid) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Dispose any stale modal first
    _trustModal?.dispose();
    _trustModal = null;

    try {
      const projectId = '52cb8eaaad34baed8dbe063b454b28f6';

      final modal = await TrustWalletService.createModal(
        context: context,
        projectId: projectId,
      );
      _trustModal = modal;

      modal.appKit?.onSessionUpdate.subscribe((SessionUpdate? args) async {
        final address = modal.session?.getAddress(NetworkUtils.solana);
        if (address != null && address.isNotEmpty) {
          await _handleMobileAccountChanged(address, 'trust');
        }
      });

      modal.appKit?.onSessionDelete.subscribe((SessionDelete? args) async {
        await _handleMobileDisconnect();
      });

      // Listen for successful connection
      modal.onModalConnect.subscribe((ModalConnect? event) async {
        modal.onModalConnect.unsubscribeAll();

        final address = modal.session?.getAddress(NetworkUtils.solana);
        debugPrint('Trust Wallet connected! Address: $address');

        if (address != null && address.isNotEmpty) {
          final user = ref.read(userProvider);
          if (user != null && mounted) {
            try {
              // ── 1:1 guard: check if this wallet is already owned by another user ──
              final existingDoc = await ref
                  .read(firestoreProvider)
                  .collection('walletLinks')
                  .doc(address)
                  .get();

              if (existingDoc.exists) {
                final existingUid = existingDoc.data()?['uid'] as String?;
                if (existingUid != null && existingUid != user.uid) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'This wallet is already linked to another account. Each wallet can only be connected to one account.',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    setState(() => _isProcessing = false);
                  }
                  return;
                }
              }

              await ref
                  .read(firestoreProvider)
                  .collection('users')
                  .doc(user.uid)
                  .update({
                    'walletPublicKey': address,
                    'connectedWalletType': 'trust',
                  });

              // Write wallet link for cross-platform login support
              final password = await SecureStorageHelper.getPassword();
              final obfuscatedPassword = password != null
                  ? SecureStorageHelper.obfuscate(password)
                  : null;
              final linkData = <String, dynamic>{
                'uid': user.uid,
                'email': user.email,
                'linkedAt': DateTime.now().millisecondsSinceEpoch,
              };
              if (obfuscatedPassword != null) {
                linkData['password'] = obfuscatedPassword;
              }
              await ref
                  .read(firestoreProvider)
                  .collection('walletLinks')
                  .doc(address)
                  .set(linkData);

              ref.invalidate(userProfileProvider);

              if (mounted) {
                setState(() => _isProcessing = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Trust Wallet connected: $address'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                setState(() => _isProcessing = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to save Trust Wallet address: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          } else {
            if (mounted) setState(() => _isProcessing = false);
          }
        } else {
          if (mounted) setState(() => _isProcessing = false);
        }
      });

      modal.onModalDisconnect.subscribe((_) {
        modal.onModalDisconnect.unsubscribeAll();
        if (mounted && _isProcessing) {
          setState(() => _isProcessing = false);
        }
      });

      // Generate the WC v2 connection URI from the initialized AppKit client
      if (modal.appKit == null) {
        throw Exception('Reown AppKit client not initialized.');
      }
      final connectResponse = await modal.appKit!.connect(
        optionalNamespaces: modal.optionalNamespaces,
      );

      final wcUri = connectResponse.uri;
      if (wcUri == null) {
        throw Exception('Could not generate WalletConnect URI.');
      }

      final encodedUri = Uri.encodeComponent(wcUri.toString());
      final schemes = [
        'trust://wc?uri=$encodedUri',
        'trustwallet://wc?uri=$encodedUri',
        'https://link.trustwallet.com/wc?uri=$encodedUri',
      ];

      bool launched = false;
      for (final scheme in schemes) {
        try {
          final uri = Uri.parse(scheme);
          if (await canLaunchUrl(uri)) {
            launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (launched) {
              debugPrint('Successfully launched Trust Wallet directly: $scheme');
              break;
            }
          }
        } catch (e) {
          debugPrint('Error launching scheme $scheme: $e');
        }
      }

      if (!launched) {
        throw Exception('Could not launch Trust Wallet. Please make sure the app is installed.');
      }

      // Await connection in background, handle potential failure/rejection
      connectResponse.session.future.then((sessionData) {
        debugPrint('Direct Trust Wallet connection session settled.');
      }).catchError((e) {
        debugPrint('Direct Trust Wallet connection rejected or failed: $e');
        modal.onModalConnect.unsubscribeAll();
        if (mounted) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trust Wallet connection failed or rejected.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    } catch (e) {
      _trustModal?.dispose();
      _trustModal = null;
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Trust Wallet connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
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

    try {
      final firestore = ref.read(firestoreProvider);

      // Fetch treasury public key from Firestore config
      final configDoc = await firestore
          .collection('system_config')
          .doc('treasury')
          .get();
      final treasuryPublicKey = configDoc.data()?['publicKey'] as String?;

      if (treasuryPublicKey == null || treasuryPublicKey.isEmpty) {
        throw Exception(
          'Treasury wallet is not configured. Please contact support.',
        );
      }

      if (walletType == 'trust') {
        // ── Trust Wallet: Reown AppKit v2 (WalletConnect v2) signing flow ─
        await SecureStorageHelper.savePendingDepositPhpAmount(phpAmount);
        await SecureStorageHelper.savePendingDepositCryptoAmount(cryptoAmount);
        await SecureStorageHelper.savePendingDepositCurrency('SOL');

        final modal = _trustModal;
        if (modal == null || !modal.isConnected || modal.session == null) {
          throw Exception(
            'No active Trust Wallet session. Please reconnect your wallet first.',
          );
        }

        // Build the unsigned transaction bytes
        final phantomService = ref.read(phantomServiceProvider);
        final blockhash = await phantomService.fetchRecentBlockhash();
        final lamports = (cryptoAmount * 1e9).round();
        final txBytes = phantomService.serializeTransferTransaction(
          senderPubkey: userPubkey,
          receiverPubkey: treasuryPublicKey,
          blockhash: blockhash,
          lamports: lamports,
        );

        // Simulate before signing
        await phantomService.simulateTransaction(base58.encode(txBytes));

        // Encode as base64 for WalletConnect v2 Solana spec
        final base64Tx = base64.encode(txBytes);
        final chainId = TrustWalletService.getSolanaChainId();

        // Send solana_signTransaction request to Trust Wallet via WC v2 relay
        final requestFuture = modal.request(
          topic: modal.session!.topic,
          chainId: chainId,
          request: SessionRequestParams(
            method: 'solana_signTransaction',
            params: {'transaction': base64Tx},
          ),
        );

        // Immediately open Trust Wallet app so the user is prompted to sign the transaction
        final schemes = [
          'trust://',
          'trustwallet://',
        ];
        bool launched = false;
        for (final scheme in schemes) {
          try {
            final uri = Uri.parse(scheme);
            if (await canLaunchUrl(uri)) {
              launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (launched) {
                debugPrint('Successfully opened Trust Wallet for signing via: $scheme');
                break;
              }
            }
          } catch (_) {}
        }
        if (!launched) {
          // Try standard universal redirect if deep link scheme didn't work
          final redirectLink = modal.session?.peer?.metadata.redirect?.native;
          if (redirectLink != null && redirectLink.isNotEmpty) {
            try {
              await launchUrl(Uri.parse(redirectLink), mode: LaunchMode.externalApplication);
            } catch (_) {}
          }
        }

        // Await signing response from Trust Wallet
        final result = await requestFuture;

        // Extract signature from response (WC v2 returns {"signature": "..."})
        String txSignature;
        if (result is Map) {
          final sig =
              result['signature'] as String? ??
              result['transaction'] as String?;
          if (sig == null || sig.isEmpty) {
            throw Exception('Trust Wallet returned an empty signature.');
          }
          // sig is the base58 signature — broadcast directly
          txSignature = await ref
              .read(phantomServiceProvider)
              .sendTransaction(sig);
        } else if (result is String) {
          txSignature = await ref
              .read(phantomServiceProvider)
              .sendTransaction(result);
        } else {
          throw Exception('Unexpected response from Trust Wallet: $result');
        }

        final confirmed = await ref
            .read(phantomServiceProvider)
            .confirmTransaction(txSignature);

        if (!confirmed) {
          throw Exception(
            'Trust Wallet transaction broadcast but not confirmed. '
            'Check: https://explorer.solana.com/tx/$txSignature',
          );
        }

        // Clear pending deposit
        await SecureStorageHelper.deletePendingDepositPhpAmount();
        await SecureStorageHelper.deletePendingDepositCryptoAmount();
        await SecureStorageHelper.deletePendingDepositCurrency();

        // Update Firestore balance
        final repo = ref.read(transitRepositoryProvider);
        final userProfile = await repo.getUser(uid);
        if (userProfile != null) {
          final newBalance = userProfile.tyxBalance + phpAmount;
          await repo.updateTyxBalance(uid, newBalance);

          final txId = 'deposit_sol_$txSignature';
          await firestore.collection('transactions').doc(txId).set({
            'uid': uid,
            'type': 'deposit',
            'amount': phpAmount,
            'title': 'Wallet Top-Up (SOL via Trust Wallet)',
            'desc':
                'Crypto deposit of ${cryptoAmount.toStringAsFixed(4)} SOL via Trust Wallet',
            'method': 'Trust Wallet',
            'solanaTxSignature': txSignature,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });

          ref.invalidate(userProfileProvider);
          ref.invalidate(userTransactionsProvider);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Successfully deposited ₱ ${phpAmount.toStringAsFixed(2)} via Trust Wallet',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        // ── Phantom / Solflare: NaCl Encryption Deep-link redirect ──────
        // 1. Save pending state to SecureStorage
        await SecureStorageHelper.savePendingDepositPhpAmount(phpAmount);
        await SecureStorageHelper.savePendingDepositCryptoAmount(cryptoAmount);
        await SecureStorageHelper.savePendingDepositCurrency('SOL');

        // 2. Generate signing link
        final phantomService = ref.read(phantomServiceProvider);
        final signUri = await phantomService.generateSignTransactionUri(
          walletType: walletType,
          senderPubkey: userPubkey,
          receiverPubkey: treasuryPublicKey,
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

  /// Handles a USDT (SPL token) deposit for all supported wallets:
  /// - Phantom / Solflare: NaCl encrypted deep-link → `/onSignTransaction`
  /// - Trust Wallet: WalletConnect v2 `solana_signTransaction` with base64 SPL tx
  ///
  /// The `/onSignTransaction` route in app_router.dart already reads
  /// `pendingCurrency` from SecureStorage, so USDT credits flow through
  /// the same Firestore balance update path as SOL — no router changes needed.
  Future<void> _handleUsdtDeposit({
    required String uid,
    required double phpAmount,
    required double amountInUsdt,
    required String walletType,
    required String userPubkey,
  }) async {
    setState(() => _isProcessing = true);

    try {
      final firestore = ref.read(firestoreProvider);

      // Fetch treasury public key from Firestore config
      final configDoc = await firestore
          .collection('system_config')
          .doc('treasury')
          .get();
      final treasuryPublicKey = configDoc.data()?['publicKey'] as String?;

      if (treasuryPublicKey == null || treasuryPublicKey.isEmpty) {
        throw Exception(
          'Treasury wallet is not configured. Please contact support.',
        );
      }

      final phantomService = ref.read(phantomServiceProvider);

      if (walletType == 'trust') {
        // ── Trust Wallet: Reown AppKit v2 (WalletConnect v2) signing flow ──
        await SecureStorageHelper.savePendingDepositPhpAmount(phpAmount);
        await SecureStorageHelper.savePendingDepositCryptoAmount(amountInUsdt);
        await SecureStorageHelper.savePendingDepositCurrency('USDT');

        final modal = _trustModal;
        if (modal == null || !modal.isConnected || modal.session == null) {
          throw Exception(
            'No active Trust Wallet session. Please reconnect your wallet first.',
          );
        }

        // Build unsigned SPL token transfer transaction bytes
        final blockhash = await phantomService.fetchRecentBlockhash();
        final microUnits = (amountInUsdt * 1e6).round();
        final txBytes = await phantomService.serializeTokenTransferTransaction(
          senderPubkey: userPubkey,
          receiverPubkey: treasuryPublicKey,
          mintPubkey: phantomService.usdtMintAddress,
          blockhash: blockhash,
          microUnits: microUnits,
        );

        // Simulate before signing
        await phantomService.simulateTransaction(base58.encode(txBytes));

        // Encode as base64 for WalletConnect v2 Solana spec
        final base64Tx = base64.encode(txBytes);
        final chainId = TrustWalletService.getSolanaChainId();

        // Send solana_signTransaction request to Trust Wallet
        final requestFuture = modal.request(
          topic: modal.session!.topic,
          chainId: chainId,
          request: SessionRequestParams(
            method: 'solana_signTransaction',
            params: {'transaction': base64Tx},
          ),
        );

        // Immediately open Trust Wallet app for signing
        final schemes = ['trust://', 'trustwallet://'];
        bool launched = false;
        for (final scheme in schemes) {
          try {
            final uri = Uri.parse(scheme);
            if (await canLaunchUrl(uri)) {
              launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (launched) break;
            }
          } catch (_) {}
        }
        if (!launched) {
          final redirectLink = modal.session?.peer?.metadata.redirect?.native;
          if (redirectLink != null && redirectLink.isNotEmpty) {
            try {
              await launchUrl(Uri.parse(redirectLink), mode: LaunchMode.externalApplication);
            } catch (_) {}
          }
        }

        // Await signing response from Trust Wallet
        final result = await requestFuture;

        // Extract signed transaction or signature and broadcast
        String txSignature;
        if (result is Map) {
          final sig =
              result['signature'] as String? ??
              result['transaction'] as String?;
          if (sig == null || sig.isEmpty) {
            throw Exception('Trust Wallet returned an empty signature.');
          }
          txSignature = await phantomService.sendTransaction(sig);
        } else if (result is String) {
          txSignature = await phantomService.sendTransaction(result);
        } else {
          throw Exception('Unexpected response from Trust Wallet: $result');
        }

        final confirmed = await phantomService.confirmTransaction(txSignature);
        if (!confirmed) {
          throw Exception(
            'USDT transaction broadcast but not confirmed. '
            'Check: https://explorer.solana.com/tx/$txSignature',
          );
        }

        // Clear pending deposit
        await SecureStorageHelper.deletePendingDepositPhpAmount();
        await SecureStorageHelper.deletePendingDepositCryptoAmount();
        await SecureStorageHelper.deletePendingDepositCurrency();

        // Update Firestore balance
        final repo = ref.read(transitRepositoryProvider);
        final userProfile = await repo.getUser(uid);
        if (userProfile != null) {
          final newBalance = userProfile.tyxBalance + phpAmount;
          await repo.updateTyxBalance(uid, newBalance);

          final txId = 'deposit_usdt_$txSignature';
          await firestore.collection('transactions').doc(txId).set({
            'uid': uid,
            'type': 'deposit',
            'amount': phpAmount,
            'title': 'Wallet Top-Up (USDT via Trust Wallet)',
            'desc':
                'Crypto deposit of \$${amountInUsdt.toStringAsFixed(2)} USDT via Trust Wallet',
            'method': 'Trust Wallet',
            'solanaTxSignature': txSignature,
            'currency': 'USDT',
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });

          ref.invalidate(userProfileProvider);
          ref.invalidate(userTransactionsProvider);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Successfully deposited ₱ ${phpAmount.toStringAsFixed(2)} via USDT (Trust Wallet)',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        // ── Phantom / Solflare: NaCl Encrypted deep-link ────────────────
        // 1. Save pending state to SecureStorage
        await SecureStorageHelper.savePendingDepositPhpAmount(phpAmount);
        await SecureStorageHelper.savePendingDepositCryptoAmount(amountInUsdt);
        await SecureStorageHelper.savePendingDepositCurrency('USDT');

        // 2. Generate USDT sign URI and launch wallet
        final signUri = await phantomService.generateSignTokenTransferUri(
          walletType: walletType,
          senderPubkey: userPubkey,
          receiverPubkey: treasuryPublicKey,
          amountInUsdt: amountInUsdt,
        );

        debugPrint('Launching USDT sign URI: $signUri');
        final launched = await launchUrl(
          signUri,
          mode: LaunchMode.externalApplication,
        );

        if (!launched) {
          throw 'Could not launch wallet app. Make sure it is installed.';
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('USDT Deposit failed: $e'),
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
    if (wallet.id == 'trust') {
      await _handleDisconnectTrustWallet(uid);
      return;
    }
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

  /// Disconnects Trust Wallet and clears its WalletConnect session from storage.
  Future<void> _handleDisconnectTrustWallet(String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Trust Wallet'),
        content: const Text(
          'Are you sure you want to disconnect your Trust Wallet?\n\nThis will clear the WalletConnect session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isProcessing = true);
      try {
        // Disconnect and dispose AppKit modal session
        if (_trustModal?.isConnected == true) {
          await _trustModal!.disconnect();
        }
        _trustModal?.dispose();
        _trustModal = null;

        // Clear any legacy Trust Wallet keys from SecureStorage
        await SecureStorageHelper.deleteTrustWalletAddress();
        await SecureStorageHelper.deleteTrustWalletTopic();
        await SecureStorageHelper.deleteTrustWalletKey();

        // Clear wallet from Firestore
        await ref.read(firestoreProvider).collection('users').doc(uid).update({
          'walletPublicKey': null,
          'connectedWalletType': null,
        });

        ref.invalidate(userProfileProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trust Wallet disconnected.'),
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

    final double feeRate = 0.02;
    final feePhp = tyxBalance * feeRate;
    final netPhp = tyxBalance - feePhp;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        String selectedCoin = 'SOL';
        bool isWithdrawing = false;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isDarkMode = ref.read(themeModeProvider);
            final cardColor = isDarkMode
                ? const Color(0xFF1A1A2E)
                : const Color(0xFFF8F8FC);
            final borderColor = isDarkMode
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.07);

            final rateSol = _solToPhpRate > 0 ? _solToPhpRate : 8000.0;
            final rateUsdt = _usdToPhpRate > 0 ? _usdToPhpRate : 57.0;

            final solAmount = netPhp / rateSol;
            final feeSolAmount = feePhp / rateSol;

            final usdtAmount = netPhp / rateUsdt;
            final feeUsdtAmount = feePhp / rateUsdt;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.92,
                ),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF12121C) : Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle + Header
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
                                  color: Colors.blue.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.account_balance_wallet_outlined,
                                  color: Colors.blue,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Withdraw Earnings',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Choose payout cryptocurrency',
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

                    const Divider(height: 24, thickness: 1),

                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Current Balance Display
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'WITHDRAWABLE BALANCE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode ? Colors.white60 : Colors.black54,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(
                                        '₱ ${tyxBalance.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Wallet: ${userProfile.walletPublicKey!.substring(0, 8)}...${userProfile.walletPublicKey!.substring(userProfile.walletPublicKey!.length - 8)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),
                            const Text(
                              'Select Payout Asset',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Option SOL
                            InkWell(
                              onTap: () {
                                if (!isWithdrawing) {
                                  setSheetState(() => selectedCoin = 'SOL');
                                }
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: selectedCoin == 'SOL'
                                      ? AppColors.indigo.withValues(alpha: isDarkMode ? 0.15 : 0.05)
                                      : cardColor,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selectedCoin == 'SOL'
                                        ? AppColors.indigo
                                        : borderColor,
                                    width: selectedCoin == 'SOL' ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.bolt,
                                      color: Colors.purple,
                                      size: 32,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Solana (SOL)',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            '1 SOL ≈ ₱${rateSol.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${solAmount.toStringAsFixed(6)} SOL',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.purple,
                                          ),
                                        ),
                                        const Text(
                                          'Est. Payout',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Option USDT
                            InkWell(
                              onTap: () {
                                if (!isWithdrawing) {
                                  setSheetState(() => selectedCoin = 'USDT');
                                }
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: selectedCoin == 'USDT'
                                      ? AppColors.indigo.withValues(alpha: isDarkMode ? 0.15 : 0.05)
                                      : cardColor,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selectedCoin == 'USDT'
                                        ? AppColors.indigo
                                        : borderColor,
                                    width: selectedCoin == 'USDT' ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.monetization_on,
                                      color: Colors.teal,
                                      size: 32,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Tether (USDT)',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            '1 USDT ≈ ₱${rateUsdt.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${usdtAmount.toStringAsFixed(2)} USDT',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal,
                                          ),
                                        ),
                                        const Text(
                                          'Est. Payout',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Fee Breakdown
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? Colors.white.withValues(alpha: 0.03)
                                    : Colors.black.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Gross Balance',
                                        style: TextStyle(color: Colors.grey, fontSize: 13),
                                      ),
                                      Text(
                                        '₱ ${tyxBalance.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: isDarkMode ? Colors.white : Colors.black,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Platform Fee (2%)',
                                        style: TextStyle(color: Colors.grey, fontSize: 13),
                                      ),
                                      Text(
                                        '₱ ${feePhp.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Net Received Value',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      Text(
                                        '₱ ${netPhp.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.indigo,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // CTA Button
                            isWithdrawing
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : SizedBox(
                                    width: double.infinity,
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: () async {
                                        setSheetState(() => isWithdrawing = true);
                                        try {
                                          final firestore = ref.read(firestoreProvider);
                                          final phantomService = ref.read(phantomServiceProvider);

                                          // 1. Fetch treasury private key
                                          final configDoc = await firestore
                                              .collection('system_config')
                                              .doc('treasury')
                                              .get();
                                          final treasuryPrivKey =
                                              configDoc.data()?['privateKeyBase58'] as String?;
                                          if (treasuryPrivKey == null || treasuryPrivKey.isEmpty) {
                                            throw Exception(
                                              'Treasury wallet is not configured. Please contact support.',
                                            );
                                          }

                                          String txSignature = '';

                                          if (selectedCoin == 'SOL') {
                                            final lamports = (solAmount * 1e9).round();
                                            if (lamports <= 0) {
                                              throw Exception('Withdrawal amount too small to process on-chain.');
                                            }

                                            // 2. Sign & broadcast Treasury -> User SOL
                                            txSignature = await phantomService.signAndBroadcastTransfer(
                                              treasuryPrivKeyBase58: treasuryPrivKey,
                                              recipientPubkey: userProfile.walletPublicKey!,
                                              lamports: lamports,
                                            );
                                          } else {
                                            // selectedCoin == 'USDT'
                                            if (usdtAmount <= 0) {
                                              throw Exception('Withdrawal amount too small to process on-chain.');
                                            }

                                            // 2. Sign & broadcast Treasury -> User USDT
                                            txSignature = await phantomService.signAndBroadcastTokenTransfer(
                                              treasuryPrivKeyBase58: treasuryPrivKey,
                                              recipientPubkey: userProfile.walletPublicKey!,
                                              amountInUsdt: usdtAmount,
                                            );
                                          }

                                          // 3. Confirm transaction
                                          final txConfirmed = await phantomService.confirmTransaction(txSignature);
                                          if (!txConfirmed) {
                                            throw Exception(
                                              'Transaction was broadcast but could not be confirmed. '
                                              'Check explorer: https://explorer.solana.com/tx/$txSignature',
                                            );
                                          }

                                          // 4. Deduct tyxBalance
                                          await ref.read(transitRepositoryProvider).updateTyxBalance(uid, 0);

                                          // 5. Save history
                                          final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
                                          await firestore.collection('transactions').doc(txId).set({
                                            'uid': uid,
                                            'type': 'withdraw',
                                            'amount': tyxBalance,
                                            'feeAmount': feePhp,
                                            'netAmount': netPhp,
                                            if (selectedCoin == 'SOL') ...{
                                              'solAmount': solAmount,
                                              'feeSolAmount': feeSolAmount,
                                              'lamports': (solAmount * 1e9).round(),
                                            } else ...{
                                              'usdtAmount': usdtAmount,
                                              'feeUsdtAmount': feeUsdtAmount,
                                              'microUnits': (usdtAmount * 1e6).round(),
                                            },
                                            'title': 'Earnings Withdrawn',
                                            'desc': selectedCoin == 'SOL'
                                                ? 'Withdrew ₱${netPhp.toStringAsFixed(2)} (${solAmount.toStringAsFixed(6)} SOL) '
                                                    'after 2% fee of ₱${feePhp.toStringAsFixed(2)} (${feeSolAmount.toStringAsFixed(6)} SOL) '
                                                    'to ${userProfile.walletPublicKey}'
                                                : 'Withdrew ₱${netPhp.toStringAsFixed(2)} (${usdtAmount.toStringAsFixed(2)} USDT) '
                                                    'after 2% fee of ₱${feePhp.toStringAsFixed(2)} (${feeUsdtAmount.toStringAsFixed(2)} USDT) '
                                                    'to ${userProfile.walletPublicKey}',
                                            'method': selectedCoin,
                                            'solanaTxSignature': txSignature,
                                            'createdAt': DateTime.now().millisecondsSinceEpoch,
                                          });

                                          // 6. Record withdrawal request
                                          final requestId = 'withdraw_${DateTime.now().microsecondsSinceEpoch}';
                                          await firestore.collection('withdrawalRequests').doc(requestId).set({
                                            'uid': uid,
                                            'userName': userProfile.name,
                                            'amount': tyxBalance,
                                            'feeAmount': feePhp,
                                            'netAmount': netPhp,
                                            if (selectedCoin == 'SOL') 'solAmount': solAmount else 'usdtAmount': usdtAmount,
                                            'status': 'Completed',
                                            'createdAt': DateTime.now().millisecondsSinceEpoch,
                                            'method': selectedCoin,
                                            'walletPublicKey': userProfile.walletPublicKey,
                                            'solanaTxSignature': txSignature,
                                          });

                                          // 7. Record fee
                                          final feeId = 'fee_$txId';
                                          await firestore.collection('platform_fees').doc(feeId).set({
                                            'withdrawalId': requestId,
                                            'txId': txId,
                                            'uid': uid,
                                            'amount': feePhp,
                                            if (selectedCoin == 'SOL') 'solAmount': feeSolAmount else 'usdtAmount': feeUsdtAmount,
                                            'feeType': 'withdrawal',
                                            'rate': selectedCoin == 'SOL' ? rateSol : rateUsdt,
                                            'timestamp': DateTime.now().millisecondsSinceEpoch,
                                          });

                                          ref.invalidate(userProfileProvider);
                                          if (sheetContext.mounted) {
                                            Navigator.pop(sheetContext);
                                          }
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '✅ Withdrawal successful! '
                                                  '${selectedCoin == 'SOL' ? '${solAmount.toStringAsFixed(6)} SOL' : '${usdtAmount.toStringAsFixed(2)} USDT'} sent to your wallet.\n'
                                                  'Tx: ${txSignature.substring(0, 12)}…',
                                                ),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          }
                                        } catch (e, s) {
                                          debugPrint("Withdrawal error: $e $s");
                                          setSheetState(() => isWithdrawing = false);
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Withdrawal failed: $e')),
                                            );
                                          }
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.indigo,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: Text(
                                        'Withdraw to ${selectedCoin == 'SOL' ? 'SOL' : 'USDT'}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                          ],
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

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final userProfile = ref.watch(userProfileProvider).value;
    final transactionsAsync = ref.watch(userTransactionsProvider);
    final rawUserDocAsync = ref.watch(rawUserDocProvider);

    // ── Real-time SOL balance: start / stop polling whenever the wallet
    //    connection state changes (pubkey appears, changes, or is removed).
    ref.listen<AsyncValue>(userProfileProvider, (_, next) {
      final profile = next.value;
      final pubkey = (profile as dynamic)?.walletPublicKey as String?;
      if (pubkey != null && pubkey.isNotEmpty) {
        _startBalancePolling(pubkey);
      } else {
        _stopBalancePolling();
        if (mounted) {
          setState(() {
            _solBalance = 0.0;
            _usdtBalance = 0.0;
          });
        }
      }
    });

    if (userProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Kick off polling on first build if a wallet is already connected.
    final currentPubkey = userProfile.walletPublicKey;
    if (currentPubkey != null && currentPubkey.isNotEmpty) {
      _startBalancePolling(currentPubkey);
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
                                mode: LaunchMode.inAppBrowserView,
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

        // Redeem Promo Code Section
        const SizedBox(height: 24),
        const Text(
          'Redeem Promo Code',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (userProfile.activePromoCode != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Active Promo Code: ${userProfile.activePromoCode}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Benefit: ${userProfile.activePromoDiscountType == 'percentage' ? '${userProfile.activePromoDiscountValue}% off platform commission' : '₱${userProfile.activePromoDiscountValue} off platform commission'}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 20),
                        onPressed: () => _handleDisablePromo(
                          context,
                          userProfile.activePromoCode!,
                          uid,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Text(
                'Enter a promo code to apply a discount to your next gig/booking transaction fee or payout commission.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promoRedeemController,
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter code (e.g., SAVE50)...',
                        hintStyle: const TextStyle(color: Colors.grey),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDarkMode
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDarkMode
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.indigo),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isRedeeming
                        ? null
                        : () => _handleRedeemPromo(
                              _promoRedeemController.text,
                              uid,
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.indigo,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isRedeeming
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Redeem',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                  ),
                ],
              ),
              if (_redeemFeedback != null) ...[
                const SizedBox(height: 8),
                Text(
                  _redeemFeedback!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _redeemFeedback!.contains('successfully')
                        ? Colors.green
                        : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),

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
