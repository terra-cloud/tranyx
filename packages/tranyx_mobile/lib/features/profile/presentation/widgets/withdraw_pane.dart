import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/profile/providers/profile_provider.dart';
import 'package:tranyx_mobile/features/profile/presentation/widgets/payment_pane.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'package:shared/shared.dart';

class WithdrawPane extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  const WithdrawPane({super.key, this.onBack});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const WithdrawPane(),
    );
  }

  @override
  ConsumerState<WithdrawPane> createState() => _WithdrawPaneState();
}

class _WithdrawPaneState extends ConsumerState<WithdrawPane> with SingleTickerProviderStateMixin {
  String _selectedRail = 'manual_p2p'; // 'manual_p2p' or 'solana'
  final _amountController = TextEditingController(text: '100');
  String _selectedCoin = 'USDT'; // 'USDT', 'SOL'
  String _selectedP2pMethod = 'GCash'; // 'GCash', 'Maya'
  final _accountNameController = TextEditingController();
  final _accountNumberController = TextEditingController();

  double _solToPhpRate = 8000.0;
  double _usdToPhpRate = 57.0;
  bool _isFetchingRates = false;

  bool _isSubmitting = false;
  String? _errorMessage;
  String? _successMessage;

  final _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onAmountChanged);
    _fetchLiveRates();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(userProfileProvider).value;
      if (profile != null) {
        if (_accountNameController.text.isEmpty && profile.name.isNotEmpty) {
          _accountNameController.text = profile.name;
        }
        final phone = profile.phoneNumber;
        if (_accountNumberController.text.isEmpty && phone != null && phone.isNotEmpty) {
          _accountNumberController.text = phone;
        }
      }
    });
  }

  void _onAmountChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _fetchLiveRates() async {
    if (!mounted) return;
    setState(() => _isFetchingRates = true);
    try {
      final cgRes = await http
          .get(
            Uri.parse(
              'https://api.coingecko.com/api/v3/simple/price?ids=solana,tether&vs_currencies=php,usd',
            ),
          )
          .timeout(const Duration(seconds: 5));

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
      } else {
        final binanceRes = await http
            .get(
              Uri.parse(
                'https://api.binance.com/api/v3/ticker/price?symbol=SOLUSDT',
              ),
            )
            .timeout(const Duration(seconds: 4));
        final usdPhpRes = await http
            .get(Uri.parse('https://open.er-api.com/v6/latest/USD'))
            .timeout(const Duration(seconds: 4));

        double usdPhp = 57.0;
        if (usdPhpRes.statusCode == 200) {
          final usdData = jsonDecode(usdPhpRes.body) as Map<String, dynamic>;
          final php = (usdData['rates']?['PHP'] as num?)?.toDouble();
          if (php != null && php > 0) usdPhp = php;
        }

        if (binanceRes.statusCode == 200) {
          final bData = jsonDecode(binanceRes.body) as Map<String, dynamic>;
          final solUsd = double.tryParse(bData['price']?.toString() ?? '') ?? 0.0;
          if (solUsd > 0 && mounted) {
            setState(() {
              _solToPhpRate = solUsd * usdPhp;
              _usdToPhpRate = usdPhp;
            });
          }
        }
      }
    } catch (_) {
      // Retain fallback values if network fetch fails
    } finally {
      if (mounted) {
        setState(() => _isFetchingRates = false);
      }
    }
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _accountNameController.dispose();
    _accountNumberController.dispose();
    super.dispose();
  }

  void _setPresetAmount(double amount, double maxBalance) {
    HapticFeedback.selectionClick();
    final clamped = amount.clamp(0.0, maxBalance);
    setState(() {
      _amountController.text = clamped.toStringAsFixed(0);
      _errorMessage = null;
    });
  }

  Future<void> _submitP2pWithdrawal(
    double tyxBalance,
    String uid,
    String userName,
    String userEmail,
  ) async {
    HapticFeedback.mediumImpact();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final accountName = _accountNameController.text.trim();
    final accountNumber = _accountNumberController.text.trim();

    if (accountName.isEmpty) {
      setState(() => _errorMessage = 'Please enter your recipient account name.');
      return;
    }
    if (accountNumber.isEmpty) {
      setState(() => _errorMessage = 'Please enter your GCash / Maya mobile number.');
      return;
    }
    if (amount < 100) {
      setState(() => _errorMessage = 'Minimum cashout amount is ₱ 100.00.');
      return;
    }
    if (amount > tyxBalance) {
      setState(() => _errorMessage = 'Requested amount exceeds your available balance.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final repo = ref.read(transitRepositoryProvider);
      await repo.requestP2pWithdrawal(
        uid: uid,
        userName: userName,
        userEmail: userEmail,
        amount: amount,
        paymentMethod: _selectedP2pMethod,
        userAccountName: accountName,
        userAccountNumber: accountNumber,
      );

      setState(() {
        _isSubmitting = false;
        _successMessage = 'Cashout request broadcasted to P2P Payment Agents!';
      });
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Cashout request failed: $e';
      });
    }
  }

  Future<void> _submitSolanaWithdrawal(
    double tyxBalance,
    String uid,
    String userName,
  ) async {
    HapticFeedback.mediumImpact();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;

    if (amount < 100) {
      setState(() => _errorMessage = 'Minimum withdrawal amount is ₱ 100.00.');
      return;
    }

    if (amount > tyxBalance) {
      setState(
        () => _errorMessage =
            'Requested amount exceeds your available balance (₱ ${_currencyFormat.format(tyxBalance)}).',
      );
      return;
    }

    final profile = ref.read(userProfileProvider).value;
    final rawUserDoc = ref.read(rawUserDocProvider).value;
    final walletKey = profile?.walletPublicKey ??
        rawUserDoc?.data()?['walletPublicKey'] as String? ??
        rawUserDoc?.data()?['solanaWalletAddress'] as String? ??
        rawUserDoc?.data()?['walletAddress'] as String?;

    if (walletKey == null || walletKey.isEmpty) {
      setState(
        () => _errorMessage =
            'Withdrawals are only available to connected Solana wallets. Please link your wallet first in Payment Methods.',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final phantomService = ref.read(phantomServiceProvider);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final requestId = 'withdraw_$timestamp';
      final methodTitle = 'Solana ($selectedCoinLabel)';

      final feePhp = (amount * 0.02);
      final netPhp = (amount - feePhp);
      final solPricePhp = _solToPhpRate > 0 ? _solToPhpRate : 8000.0;
      final usdtPricePhp = _usdToPhpRate > 0 ? _usdToPhpRate : 57.0;

      final solAmount = netPhp / solPricePhp;
      final feeSolAmount = feePhp / solPricePhp;
      final usdtAmount = netPhp / usdtPricePhp;
      final feeUsdtAmount = feePhp / usdtPricePhp;

      String txSignature = '';
      bool isOnChainTransferred = false;

      try {
        String? treasuryPrivKey = Env.solanaPrivateKey.isNotEmpty ? Env.solanaPrivateKey : null;
        if (treasuryPrivKey == null || treasuryPrivKey.isEmpty) {
          final configDoc = await firestore.collection('system_config').doc('treasury').get();
          treasuryPrivKey = configDoc.data()?['privateKeyBase58'] as String?;
        }

        if (treasuryPrivKey != null && treasuryPrivKey.isNotEmpty) {
          if (_selectedCoin == 'SOL') {
            final lamports = (solAmount * 1e9).round();
            if (lamports > 0) {
              txSignature = await phantomService.signAndBroadcastTransfer(
                treasuryPrivKeyBase58: treasuryPrivKey,
                recipientPubkey: walletKey,
                lamports: lamports,
              );
              isOnChainTransferred = true;
            }
          } else {
            if (usdtAmount > 0) {
              txSignature = await phantomService.signAndBroadcastTokenTransfer(
                treasuryPrivKeyBase58: treasuryPrivKey,
                recipientPubkey: walletKey,
                amountInUsdt: usdtAmount,
              );
              isOnChainTransferred = true;
            }
          }

          if (isOnChainTransferred && txSignature.isNotEmpty) {
            await phantomService.confirmTransaction(txSignature);
          }
        }
      } catch (vaultErr) {
        debugPrint('Direct client-side vault transfer skipped/queued: $vaultErr');
      }

      final newBalance = (tyxBalance - amount).clamp(0.0, double.infinity);
      await firestore.collection('users').doc(uid).update({'tyxBalance': newBalance});

      final txId = 'tx_$timestamp';
      await firestore.collection('transactions').doc(txId).set({
        'id': txId,
        'uid': uid,
        'type': 'withdraw',
        'originRail': 'mwa_on_chain',
        'amount': -amount,
        'cryptoAmount': _selectedCoin == 'SOL' ? solAmount : usdtAmount,
        'cryptoCurrency': _selectedCoin,
        'feeAmount': feePhp,
        'netAmount': netPhp,
        if (_selectedCoin == 'SOL') ...{
          'solAmount': solAmount,
          'feeSolAmount': feeSolAmount,
          'lamports': (solAmount * 1e9).round(),
        } else ...{
          'usdtAmount': usdtAmount,
          'feeUsdtAmount': feeUsdtAmount,
          'microUnits': (usdtAmount * 1e6).round(),
        },
        'title': isOnChainTransferred
            ? 'Earnings Withdrawn ($methodTitle)'
            : 'Withdrawal Request ($methodTitle)',
        'desc': _selectedCoin == 'SOL'
            ? 'Withdrew ₱${netPhp.toStringAsFixed(2)} (${solAmount.toStringAsFixed(6)} SOL) after 2% fee to $walletKey'
            : 'Withdrew ₱${netPhp.toStringAsFixed(2)} (${usdtAmount.toStringAsFixed(2)} USDT) after 2% fee to $walletKey',
        'currency': 'PHP',
        'status': isOnChainTransferred ? 'Completed' : 'Pending',
        'method': 'Solana',
        'coin': _selectedCoin,
        'walletPublicKey': walletKey,
        if (txSignature.isNotEmpty) 'solanaTxSignature': txSignature,
        'createdAt': timestamp,
      });

      final requestData = <String, dynamic>{
        'id': requestId,
        'uid': uid,
        'userName': userName,
        'amount': amount,
        'feeAmount': feePhp,
        'netAmount': netPhp,
        'status': isOnChainTransferred ? 'Completed' : 'Pending',
        'createdAt': timestamp,
        'method': 'Solana',
        'methodTitle': methodTitle,
        'coin': _selectedCoin,
        'currency': 'PHP',
        'walletPublicKey': walletKey,
        if (txSignature.isNotEmpty) 'solanaTxSignature': txSignature,
      };

      await firestore.collection('withdrawalRequests').doc(requestId).set(requestData);

      setState(() {
        _isSubmitting = false;
        _successMessage = isOnChainTransferred
            ? 'Withdrawal of ₱ ${_currencyFormat.format(amount)} has been transferred directly to your Solana wallet on-chain!'
            : 'Withdrawal of ₱ ${_currencyFormat.format(amount)} requested successfully! Processing typically completes within 1 hour.';
      });
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Withdrawal failed: $e';
      });
    }
  }

  String get selectedCoinLabel => _selectedCoin == 'SOL' ? 'SOL (Native)' : 'USDT (SPL)';

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final user = ref.watch(userProvider);
    final repo = ref.watch(transitRepositoryProvider);

    return profileAsync.when(
      loading: () => Container(
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: Color(0xFF7C3AED)),
      ),
      error: (err, stack) => Container(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            "Unable to load profile: $err",
            style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
      data: (profile) {
        if (profile == null) {
          return const Center(child: Text("Profile not found"));
        }

        final tyxBalance = profile.tyxBalance;
        final cardBg = isDarkMode ? const Color(0xFF13131A) : Colors.white;
        final borderColor = isDarkMode ? const Color(0xFF22222E) : const Color(0xFFE5E7EB);
        final isP2p = _selectedRail == 'manual_p2p';

        final rawUserDoc = ref.watch(rawUserDocProvider).value;
        final walletKey = profile.walletPublicKey ??
            rawUserDoc?.data()?['walletPublicKey'] as String? ??
            rawUserDoc?.data()?['solanaWalletAddress'] as String? ??
            rawUserDoc?.data()?['walletAddress'] as String?;
        final hasWallet = walletKey != null && walletKey.isNotEmpty;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.94,
            ),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF0C0C12) : const Color(0xFFF9FAFB),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDarkMode ? 0.6 : 0.15),
                  blurRadius: 30,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── HEADER & GRAB HANDLE ────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                  child: Column(
                    children: [
                      // Modern Pill Handle
                      Center(
                        child: Container(
                          width: 48,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? Colors.white.withValues(alpha: 0.18)
                                : Colors.black.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          if (widget.onBack != null)
                            IconButton(
                              icon: Icon(
                                LucideIcons.arrowLeft,
                                color: isDarkMode ? Colors.white : Colors.black87,
                                size: 20,
                              ),
                              onPressed: widget.onBack,
                            )
                          else
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                LucideIcons.arrowUpRight,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      "Withdraw Funds",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.3,
                                        color: isDarkMode ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                      decoration: BoxDecoration(
                                        color: isP2p
                                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                            : const Color(0xFF6366F1).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isP2p
                                              ? const Color(0xFF10B981).withValues(alpha: 0.35)
                                              : const Color(0xFF6366F1).withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Text(
                                        isP2p ? "0% FEE" : "WEB3",
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                          color: isP2p
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFF818CF8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isP2p
                                      ? "Direct P2P Fiat Cashout to GCash or Maya"
                                      : "On-Chain Transfer to Linked Solana Wallet",
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            style: IconButton.styleFrom(
                              backgroundColor: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.04),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: Icon(
                              LucideIcons.x,
                              color: isDarkMode ? Colors.white70 : Colors.black54,
                              size: 18,
                            ),
                            onPressed: () {
                              if (widget.onBack != null) {
                                widget.onBack!();
                              } else {
                                Navigator.of(context).pop();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── DUAL-RAIL TAB SWITCHER ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDarkMode ? const Color(0xFF181824) : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDarkMode ? const Color(0xFF27273A) : const Color(0xFFD1D5DB),
                      ),
                    ),
                    child: Row(
                      children: [
                        // P2P Rail Tab
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedRail = 'manual_p2p';
                                _errorMessage = null;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isP2p
                                    ? (isDarkMode ? const Color(0xFF7C3AED) : const Color(0xFF7C3AED))
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: isP2p
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    LucideIcons.smartphone,
                                    size: 15,
                                    color: isP2p ? Colors.white : (isDarkMode ? Colors.grey[400] : Colors.grey[700]),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    "P2P Agent (GCash/Maya)",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isP2p ? Colors.white : (isDarkMode ? Colors.grey[400] : Colors.grey[700]),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Solana Web3 Tab
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedRail = 'solana';
                                _errorMessage = null;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !isP2p
                                    ? (isDarkMode ? const Color(0xFF4F46E5) : const Color(0xFF4F46E5))
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: !isP2p
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF4F46E5).withValues(alpha: 0.4),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    LucideIcons.wallet,
                                    size: 15,
                                    color: !isP2p ? Colors.white : (isDarkMode ? Colors.grey[400] : Colors.grey[700]),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    "Solana (SOL/USDT)",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: !isP2p ? Colors.white : (isDarkMode ? Colors.grey[400] : Colors.grey[700]),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ── SCROLLABLE BODY ─────────────────────────────────────────
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isP2p)
                          StreamBuilder<List<WithdrawalRequest>>(
                            stream: repo.getUserWithdrawalRequestsStream(user?.uid ?? profile.uid),
                            builder: (context, snapshot) {
                              final activeReqs = snapshot.data
                                      ?.where((r) =>
                                          r.status == 'WAITING_FOR_AGENT' ||
                                          r.status == 'AWAITING_AGENT_PAYMENT' ||
                                          r.status == 'PENDING_CONFIRMATION')
                                      .toList() ??
                                  [];
                              if (activeReqs.isNotEmpty) {
                                final activeReq = activeReqs.first;
                                return _buildActiveP2pWithdrawalView(activeReq, isDarkMode);
                              }
                              return _buildP2pForm(tyxBalance, cardBg, borderColor, isDarkMode, user, profile);
                            },
                          )
                        else
                          _buildSolanaForm(tyxBalance, cardBg, borderColor, isDarkMode, user, profile, hasWallet, walletKey),
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
  }

  // ── ACTIVE P2P ORDER TRACKING VIEW ──────────────────────────────────────────
  Widget _buildActiveP2pWithdrawalView(WithdrawalRequest req, bool isDarkMode) {
    final status = req.status.toUpperCase();
    final isWaitingAgent = status == 'WAITING_FOR_AGENT';
    final isAwaitingPayment = status == 'AWAITING_AGENT_PAYMENT';
    final isPendingConfirmation = status == 'PENDING_CONFIRMATION';

    final isGcash = req.paymentMethod.toUpperCase().contains('GCASH');
    final methodBrandColor = isGcash ? const Color(0xFF007DFE) : const Color(0xFF00D084);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF13131D) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isPendingConfirmation
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : const Color(0xFF7C3AED).withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isPendingConfirmation ? const Color(0xFF10B981) : const Color(0xFF7C3AED))
                .withValues(alpha: isDarkMode ? 0.2 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header Status Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isPendingConfirmation
                    ? [const Color(0xFF065F46), const Color(0xFF047857)]
                    : isAwaitingPayment
                        ? [const Color(0xFF92400E), const Color(0xFFB45309)]
                        : [const Color(0xFF4C1D95), const Color(0xFF6D28D9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPendingConfirmation
                        ? LucideIcons.checkCircle2
                        : isAwaitingPayment
                            ? LucideIcons.clock
                            : LucideIcons.radio,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isWaitingAgent
                            ? "WAITING FOR AGENT CLAIM"
                            : isAwaitingPayment
                                ? "PAYOUT IN PROGRESS"
                                : "PAYOUT SENT — CONFIRM RECEIPT",
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isWaitingAgent
                            ? "Broadcasting to Payment Desk..."
                            : isAwaitingPayment
                                ? "${req.agentName ?? 'P2P Agent'} claimed order"
                                : "Check your ${req.paymentMethod} account",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 3-Step Lifecycle Visual Stepper
                _buildStepperTimeline(status, isDarkMode),
                const SizedBox(height: 20),

                // Cashout Summary Details Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF1C1C28) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDarkMode ? const Color(0xFF2A2A3C) : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Payout Amount",
                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                          Text(
                            "₱ ${_currencyFormat.format(req.amount)}",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Destination Wallet",
                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: methodBrandColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              req.paymentMethod,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: methodBrandColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Recipient Details",
                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                          Text(
                            "${req.userAccountNumber} • ${req.userAccountName}",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      if (req.agentName != null && req.agentName!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Assigned Agent",
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                            Text(
                              req.agentName!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF818CF8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── PENDING CONFIRMATION PROOF & ACTION ──────────────────────
                if (isPendingConfirmation) ...[
                  if (req.referenceNumber.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(LucideIcons.banknote, color: Color(0xFF10B981), size: 16),
                              const SizedBox(width: 8),
                              Text(
                                "Reference #",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                req.referenceNumber,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'monospace',
                                  color: Color(0xFF10B981),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: req.referenceNumber));
                                  HapticFeedback.lightImpact();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Reference number copied!"),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                child: const Icon(LucideIcons.copy, size: 14, color: Color(0xFF10B981)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (req.proofImageUrl.isNotEmpty) ...[
                    Text(
                      "AGENT PAYMENT RECEIPT",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        height: 190,
                        width: double.infinity,
                        color: isDarkMode ? const Color(0xFF1F1F2C) : const Color(0xFFE5E7EB),
                        child: Image.network(
                          req.proofImageUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (ctx, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(color: Color(0xFF10B981)),
                            );
                          },
                          errorBuilder: (ctx, err, stack) => const Center(
                            child: Icon(LucideIcons.image, size: 36, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        HapticFeedback.heavyImpact();
                        await ref.read(transitRepositoryProvider).confirmP2pWithdrawalCompleted(
                              withdrawalRequestId: req.id,
                              confirmedByUid: req.uid,
                            );
                        if (mounted) {
                          setState(() => _successMessage = 'Cashout completed successfully! Thank you.');
                        }
                      },
                      icon: const Icon(LucideIcons.checkCircle2, size: 20),
                      label: Text(
                        "Confirm Receipt (₱${_currencyFormat.format(req.amount)})",
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ] else if (isWaitingAgent) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.info, size: 16, color: Color(0xFF818CF8)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Agents typically claim and complete cashouts within 3-5 minutes. You can cancel at any time.",
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        HapticFeedback.selectionClick();
                        await ref.read(transitRepositoryProvider).cancelP2pWithdrawalRequest(
                              req.id,
                              reason: 'Cancelled by user',
                            );
                      },
                      icon: const Icon(LucideIcons.x, size: 16),
                      label: const Text("Cancel Request & Refund Balance"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperTimeline(String currentStatus, bool isDarkMode) {
    int currentStep = 1;
    if (currentStatus == 'AWAITING_AGENT_PAYMENT') currentStep = 2;
    if (currentStatus == 'PENDING_CONFIRMATION') currentStep = 3;

    final steps = [
      {'title': 'Queued', 'icon': LucideIcons.radio},
      {'title': 'Processing', 'icon': LucideIcons.clock},
      {'title': 'Payout Sent', 'icon': LucideIcons.checkCircle2},
    ];

    return Row(
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: i + 1 <= currentStep
                        ? const Color(0xFF10B981)
                        : (isDarkMode ? const Color(0xFF27273A) : const Color(0xFFE5E7EB)),
                    shape: BoxShape.circle,
                    boxShadow: i + 1 <= currentStep
                        ? [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    steps[i]['icon'] as IconData,
                    size: 16,
                    color: i + 1 <= currentStep
                        ? Colors.white
                        : (isDarkMode ? Colors.grey[500] : Colors.grey[600]),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  steps[i]['title'] as String,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: i + 1 <= currentStep ? FontWeight.bold : FontWeight.w500,
                    color: i + 1 <= currentStep
                        ? (isDarkMode ? Colors.white : Colors.black87)
                        : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          if (i < steps.length - 1)
            Container(
              width: 32,
              height: 2,
              margin: const EdgeInsets.only(bottom: 20),
              color: i + 1 < currentStep
                  ? const Color(0xFF10B981)
                  : (isDarkMode ? const Color(0xFF27273A) : const Color(0xFFE5E7EB)),
            ),
        ],
      ],
    );
  }

  // ── P2P CASH OUT FORM ───────────────────────────────────────────────────────
  Widget _buildP2pForm(
    double tyxBalance,
    Color cardBg,
    Color borderColor,
    bool isDarkMode,
    dynamic user,
    dynamic profile,
  ) {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final isGcash = _selectedP2pMethod == 'GCash';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── BALANCE CARD (AURORA GRADIENT) ──────────────────────────────────
        _buildBalanceCard(tyxBalance, "0% P2P Agent Fee", const [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
        const SizedBox(height: 22),

        // ── 1. SELECT PAYOUT WALLET (GCASH / MAYA) ──────────────────────────
        Text(
          "1. SELECT PAYOUT WALLET",
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
            color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // GCash Card
            Expanded(
              child: _buildWalletBrandCard(
                brandName: "GCash",
                subtext: "Instant Payout",
                brandColor: const Color(0xFF007DFE),
                isSelected: isGcash,
                isDarkMode: isDarkMode,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedP2pMethod = 'GCash');
                },
              ),
            ),
            const SizedBox(width: 12),
            // Maya Card
            Expanded(
              child: _buildWalletBrandCard(
                brandName: "Maya",
                subtext: "Instant Payout",
                brandColor: const Color(0xFF00D084),
                isSelected: !isGcash,
                isDarkMode: isDarkMode,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedP2pMethod = 'Maya');
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // ── 2. CASHOUT AMOUNT ────────────────────────────────────────────────
        Text(
          "2. CASHOUT AMOUNT (₱)",
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
            color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
          ),
        ),
        const SizedBox(height: 10),
        _buildAmountInputCard(tyxBalance, cardBg, borderColor, isDarkMode),
        const SizedBox(height: 22),

        // ── 3. RECIPIENT ACCOUNT DETAILS ─────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "3. RECIPIENT DETAILS",
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
                color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
            if (profile.name.isNotEmpty)
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _accountNameController.text = profile.name;
                    final phone = profile.phoneNumber;
                    if (phone != null && phone.isNotEmpty) {
                      _accountNumberController.text = phone;
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Icon(LucideIcons.sparkles, size: 12, color: const Color(0xFF818CF8)),
                      const SizedBox(width: 4),
                      Text(
                        "Fill Profile Info",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF818CF8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            children: [
              TextField(
                controller: _accountNameController,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  labelText: "Registered Name ($_selectedP2pMethod)",
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                  prefixIcon: Icon(LucideIcons.user, size: 18, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                  hintText: "e.g. Juan Dela Cruz",
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
                  ),
                  filled: true,
                  fillColor: isDarkMode ? const Color(0xFF191924) : const Color(0xFFF9FAFB),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _accountNumberController,
                keyboardType: TextInputType.phone,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  labelText: "Mobile / Account Number",
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                  prefixIcon: Icon(LucideIcons.smartphone, size: 18, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                  hintText: "e.g. 09171234567",
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
                  ),
                  filled: true,
                  fillColor: isDarkMode ? const Color(0xFF191924) : const Color(0xFFF9FAFB),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── SUMMARY RECEIPT CARD ─────────────────────────────────────────────
        _buildBreakdownCard(
          isDarkMode: isDarkMode,
          borderColor: borderColor,
          rows: [
            {'label': 'Cashout Amount', 'val': '₱ ${_currencyFormat.format(amount)}', 'highlight': false},
            {'label': 'P2P Fulfillment Fee', 'val': '₱ 0.00 (FREE)', 'highlight': true, 'isGreen': true},
            {'label': 'Transfer Duration', 'val': '⚡ ~3-5 mins', 'highlight': false},
            {'label': 'Total Net Received via $_selectedP2pMethod', 'val': '₱ ${_currencyFormat.format(amount)}', 'highlight': true, 'isGreen': true},
          ],
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildMessageBanner(_errorMessage!, isError: true),
        ],
        if (_successMessage != null) ...[
          const SizedBox(height: 16),
          _buildMessageBanner(_successMessage!, isError: false),
        ],

        const SizedBox(height: 24),
        // ── ACTION CTA BUTTON ────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_isSubmitting || amount < 100 || amount > tyxBalance)
                ? null
                : () => _submitP2pWithdrawal(
                      tyxBalance,
                      user?.uid ?? profile.uid,
                      profile.name,
                      profile.email,
                    ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              disabledBackgroundColor: isDarkMode ? const Color(0xFF27273A) : const Color(0xFFD1D5DB),
              disabledForegroundColor: isDarkMode ? Colors.grey[600] : Colors.grey[500],
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 4,
              shadowColor: const Color(0xFF7C3AED).withValues(alpha: 0.4),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.arrowUpRight, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        amount > tyxBalance
                            ? "Insufficient Balance"
                            : amount < 100
                                ? "Enter Min. ₱ 100.00"
                                : "Request Cashout via $_selectedP2pMethod",
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── SOLANA ON-CHAIN FORM ───────────────────────────────────────────────────
  Widget _buildSolanaForm(
    double tyxBalance,
    Color cardBg,
    Color borderColor,
    bool isDarkMode,
    dynamic user,
    dynamic profile,
    bool hasWallet,
    String? walletKey,
  ) {
    final enteredAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final feePhp = enteredAmount * 0.02;
    final netPhp = (enteredAmount - feePhp).clamp(0.0, double.infinity);
    final activeRate = _selectedCoin == 'SOL'
        ? (_solToPhpRate > 0 ? _solToPhpRate : 8000.0)
        : (_usdToPhpRate > 0 ? _usdToPhpRate : 57.0);
    final estCryptoAmount = activeRate > 0 ? netPhp / activeRate : 0.0;
    final estCryptoStr = _selectedCoin == 'SOL'
        ? '${estCryptoAmount.toStringAsFixed(6)} SOL'
        : '${estCryptoAmount.toStringAsFixed(2)} USDT';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wallet Connection Status Banner
        if (!hasWallet)
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.shieldAlert, color: Color(0xFFF59E0B), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Solana Wallet Not Linked",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Link your Phantom or Solflare wallet in Payment Methods to enable crypto cashouts.",
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.shieldCheck, color: Color(0xFF10B981), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "CONNECTED SOLANA WALLET",
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: Color(0xFF10B981),
                        ),
                      ),
                      Text(
                        "${walletKey!.substring(0, 8)}...${walletKey.substring(walletKey.length - 8)}",
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // ── BALANCE CARD ────────────────────────────────────────────────────
        _buildBalanceCard(tyxBalance, "2% Network Fee", const [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
        const SizedBox(height: 22),

        // ── 1. ENTER AMOUNT ─────────────────────────────────────────────────
        Text(
          "1. ENTER WITHDRAWAL AMOUNT",
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
            color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
          ),
        ),
        const SizedBox(height: 10),
        _buildAmountInputCard(tyxBalance, cardBg, borderColor, isDarkMode),
        const SizedBox(height: 22),

        // ── 2. SELECT PAYOUT ASSET ──────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "2. SELECT PAYOUT ASSET",
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
                color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
            if (_isFetchingRates)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: Color(0xFF818CF8)))
            else
              Text(
                "Live Rates",
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildCoinChip('USDT', 'USDT (SPL)', isDarkMode, rateText: '1 USDT ≈ ₱${_usdToPhpRate.toStringAsFixed(2)}'),
            const SizedBox(width: 10),
            _buildCoinChip('SOL', 'SOL (Native)', isDarkMode, rateText: '1 SOL ≈ ₱${_solToPhpRate.toStringAsFixed(2)}'),
          ],
        ),
        const SizedBox(height: 22),

        // ── 3. BREAKDOWN SUMMARY ────────────────────────────────────────────
        _buildBreakdownCard(
          isDarkMode: isDarkMode,
          borderColor: borderColor,
          rows: [
            {'label': 'Reference Market Price', 'val': '1 $_selectedCoin ≈ ₱${activeRate.toStringAsFixed(2)}', 'highlight': false},
            {'label': 'Platform Fee (2%)', 'val': '₱ ${_currencyFormat.format(feePhp)}', 'highlight': false},
            {'label': 'Est. Crypto Transfer', 'val': estCryptoStr, 'highlight': true, 'isGreen': true},
            {'label': 'Net PHP Equivalent', 'val': '₱ ${_currencyFormat.format(netPhp)}', 'highlight': true, 'isGreen': true},
          ],
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildMessageBanner(_errorMessage!, isError: true),
        ],
        if (_successMessage != null) ...[
          const SizedBox(height: 16),
          _buildMessageBanner(_successMessage!, isError: false),
        ],

        const SizedBox(height: 24),
        // ── ACTION BUTTON ───────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_isSubmitting || !hasWallet || enteredAmount < 100 || enteredAmount > tyxBalance)
                ? null
                : () => _submitSolanaWithdrawal(
                      tyxBalance,
                      user?.uid ?? profile.uid,
                      profile.name,
                    ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              disabledBackgroundColor: isDarkMode ? const Color(0xFF27273A) : const Color(0xFFD1D5DB),
              disabledForegroundColor: isDarkMode ? Colors.grey[600] : Colors.grey[500],
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 4,
              shadowColor: const Color(0xFF4F46E5).withValues(alpha: 0.4),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.arrowUpRight, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        !hasWallet
                            ? "Link Solana Wallet to Withdraw"
                            : enteredAmount > tyxBalance
                                ? "Insufficient Balance"
                                : enteredAmount < 100
                                    ? "Enter Min. ₱ 100.00"
                                    : "Confirm & Withdraw $estCryptoStr",
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── REUSABLE UI ATOMS & HELPERS ─────────────────────────────────────────────

  Widget _buildBalanceCard(double balance, String badgeText, List<Color> gradientColors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withValues(alpha: 0.35),
            blurRadius: 20,
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
              const Row(
                children: [
                  Icon(LucideIcons.shieldCheck, color: Colors.white70, size: 14),
                  SizedBox(width: 6),
                  Text(
                    "WITHDRAWABLE BALANCE",
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "₱ ${_currencyFormat.format(balance)}",
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletBrandCard({
    required String brandName,
    required String subtext,
    required Color brandColor,
    required bool isSelected,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? brandColor.withValues(alpha: isDarkMode ? 0.18 : 0.1)
              : (isDarkMode ? const Color(0xFF13131A) : Colors.white),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? brandColor
                : (isDarkMode ? const Color(0xFF22222E) : const Color(0xFFE5E7EB)),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: brandColor.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: brandColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                LucideIcons.smartphone,
                size: 20,
                color: brandColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        brandName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: isSelected
                              ? brandColor
                              : (isDarkMode ? Colors.white : Colors.black87),
                        ),
                      ),
                      if (isSelected)
                        Icon(LucideIcons.checkCircle2, size: 16, color: brandColor),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtext,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountInputCard(
    double tyxBalance,
    Color cardBg,
    Color borderColor,
    bool isDarkMode,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "₱",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: isDarkMode ? const Color(0xFF818CF8) : const Color(0xFF7C3AED),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: "100.00",
                    hintStyle: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.grey[500],
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => setState(() => _errorMessage = null),
                ),
              ),
              if (_amountController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 16, color: Colors.grey),
                  onPressed: () {
                    _amountController.clear();
                    setState(() {});
                  },
                ),
            ],
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
    );
  }

  Widget _buildPresetChip(
    String label,
    double amount,
    double maxBalance,
    bool isDarkMode, {
    bool isMax = false,
  }) {
    final currentAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final isSelected = (currentAmount == amount) || (isMax && currentAmount == maxBalance);

    return InkWell(
      onTap: () => _setPresetAmount(amount, maxBalance),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF7C3AED).withValues(alpha: 0.2)
              : isMax
                  ? const Color(0xFF4F46E5).withValues(alpha: 0.12)
                  : (isDarkMode ? const Color(0xFF1F1F2C) : const Color(0xFFF3F4F6)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF7C3AED)
                : isMax
                    ? const Color(0xFF4F46E5)
                    : Colors.transparent,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected
                ? const Color(0xFF818CF8)
                : isMax
                    ? const Color(0xFF6366F1)
                    : (isDarkMode ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildCoinChip(
    String coin,
    String label,
    bool isDarkMode, {
    required String rateText,
  }) {
    final isSelected = _selectedCoin == coin;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedCoin = coin);
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF4F46E5).withValues(alpha: 0.18)
                : (isDarkMode ? const Color(0xFF13131A) : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF4F46E5)
                  : (isDarkMode ? const Color(0xFF22222E) : const Color(0xFFE5E7EB)),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFF818CF8)
                          : (isDarkMode ? Colors.white70 : Colors.black87),
                    ),
                  ),
                  if (isSelected)
                    const Icon(LucideIcons.checkCircle2, size: 16, color: Color(0xFF6366F1)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                rateText,
                style: TextStyle(
                  fontSize: 11,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreakdownCard({
    required bool isDarkMode,
    required Color borderColor,
    required List<Map<String, dynamic>> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF101017) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  rows[i]['label'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                Text(
                  rows[i]['val'] as String,
                  style: TextStyle(
                    fontSize: (rows[i]['highlight'] as bool? ?? false) ? 13.5 : 12,
                    fontWeight: (rows[i]['highlight'] as bool? ?? false)
                        ? FontWeight.w900
                        : FontWeight.w600,
                    color: (rows[i]['isGreen'] as bool? ?? false)
                        ? const Color(0xFF10B981)
                        : (isDarkMode ? Colors.white : Colors.black87),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageBanner(String text, {required bool isError}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isError
            ? const Color(0xFFEF4444).withValues(alpha: 0.12)
            : const Color(0xFF10B981).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isError
              ? const Color(0xFFEF4444).withValues(alpha: 0.3)
              : const Color(0xFF10B981).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? LucideIcons.alertCircle : LucideIcons.checkCircle2,
            size: 16,
            color: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
