import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../services/firebase_service.dart';
import '../../services/web_interop.dart';
import 'package:shared/shared.dart';

class WithdrawModalComponent extends StatefulComponent {
  final TranyxAppState state;
  const WithdrawModalComponent({required this.state, super.key});

  @override
  State<WithdrawModalComponent> createState() => _WithdrawModalComponentState();
}

class _WithdrawModalComponentState extends State<WithdrawModalComponent> {
  String _amountInput = '100';
  String _selectedCoin = 'USDT'; // 'USDT' or 'SOL'
  String _accountNameInput = '';
  String _accountNumberInput = '';

  double _solToPhpRate = 8000.0;
  double _usdToPhpRate = 57.0;
  bool _isFetchingRates = false;

  bool _isSubmitting = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    final profile = component.state.userProfile;
    final name = profile?.name;
    final phone = profile?.phoneNumber;
    _accountNameInput = (name != null && name.isNotEmpty) ? name : '';
    _accountNumberInput = (phone != null && phone.isNotEmpty) ? phone : '';
    _fetchLiveRates();

    final activeId = component.state.activeP2pWithdrawalId;
    if (activeId != null && activeId.isNotEmpty) {
      _loadActiveRequest(activeId);
    }
  }

  Future<void> _loadActiveRequest(String reqId) async {
    final token = SessionStorage.idToken;
    if (token != null) {
      try {
        final svc = FirestoreService(token, component.state.handleTokenRefresh);
        final req = await svc.getP2pWithdrawalRequest(reqId);
        if (req != null && mounted) {
          component.state.activeP2pWithdrawalRequest = req;
          setState(() {});
        }
      } catch (_) {}
    }
  }

  Future<void> _fetchLiveRates() async {
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
        setState(() {
          if (sol != null && sol > 0) _solToPhpRate = sol;
          if (usdt != null && usdt > 0) _usdToPhpRate = usdt;
        });
      } else {
        final binanceRes = await http
            .get(
              Uri.parse(
                'https://api.binance.com/api/v3/ticker/price?symbol=SOLUSDT',
              ),
            )
            .timeout(const Duration(seconds: 4));

        final usdPhpRes = await http
            .get(
              Uri.parse('https://open.er-api.com/v6/latest/USD'),
            )
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
          if (solUsd > 0) {
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
      setState(() => _isFetchingRates = false);
    }
  }

  Future<void> _submitP2pWithdrawal() async {
    final s = component.state;
    final amount = double.tryParse(_amountInput.trim()) ?? 0.0;
    final phone = s.userProfile?.phoneNumber;
    final name = s.userProfile?.name;
    final registeredPhone = (phone != null && phone.isNotEmpty) ? phone : '';
    final registeredName = (name != null && name.isNotEmpty)
        ? name
        : (s.userName.isNotEmpty ? s.userName : '');

    final cleanName = _accountNameInput.trim().isNotEmpty
        ? _accountNameInput.trim()
        : registeredName;
    final cleanNumber = _accountNumberInput.trim().isNotEmpty
        ? _accountNumberInput.trim()
        : registeredPhone;

    if (cleanName.isEmpty) {
      setState(() => _errorMessage = 'Please enter your recipient account name.');
      return;
    }
    if (cleanNumber.isEmpty) {
      setState(() => _errorMessage = 'Please enter your GCash / Maya mobile number.');
      return;
    }
    if (amount < 100) {
      setState(() => _errorMessage = 'Minimum cashout amount is ₱ 100.00.');
      return;
    }

    final tyxBal = s.userProfile?.tyxBalance ?? 0.0;
    if (amount > tyxBal) {
      setState(() => _errorMessage = 'Requested amount exceeds your available balance.');
      return;
    }

    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });

    String qrUrl = '';
    if (s.p2pWithdrawQrBytes != null && s.p2pWithdrawQrBytes!.isNotEmpty) {
      try {
        final token = SessionStorage.idToken;
        if (token != null) {
          final imgService = ImgBBService(currentFirebaseConfig, idToken: token);
          final uploaded = await imgService.uploadImageBytes(
            s.p2pWithdrawQrBytes!,
            s.p2pWithdrawQrFileName ?? 'user_qr.jpg',
          );
          if (uploaded != null) qrUrl = uploaded;
        }
      } catch (uploadErr) {
        print('User QR upload optional skip: $uploadErr');
      }
    }

    await s.requestP2pWithdrawalOrder(
      amount: amount,
      paymentMethod: s.selectedP2pWithdrawMethod,
      userAccountName: cleanName,
      userAccountNumber: cleanNumber,
      userQrUrl: qrUrl,
    );

    if (s.postJobError != null && s.postJobError!.isNotEmpty) {
      setState(() => _errorMessage = s.postJobError);
    }
  }

  Future<void> _submitSolanaWithdrawal() async {
    final s = component.state;
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;

    if (uid == null || token == null) {
      setState(() => _errorMessage = 'Please sign in to proceed.');
      return;
    }

    final hasActiveVehicleRentals = s.realtimeRentals.any((rMap) {
      final rental = VehicleRental.fromMap(rMap, rMap['id'] ?? '');
      final isRenter = (rental.renteeId == uid);
      final statusLower = rental.status.toLowerCase();
      final isActive = (statusLower != 'completed' && statusLower != 'cancelled');
      return isRenter && isActive;
    });

    final hasActivePropertyRentals = s.realtimeProperties.any((prop) {
      final isRenter = (prop.renteeId == uid);
      final statusLower = prop.status.toLowerCase();
      final isActive = (statusLower != 'completed' && statusLower != 'cancelled' && statusLower != 'available');
      return isRenter && isActive;
    });

    if (hasActiveVehicleRentals || hasActivePropertyRentals) {
      setState(
        () => _errorMessage =
            'Withdrawals are disabled while you have active/ongoing rentals.',
      );
      return;
    }

    final tyxBal = s.userProfile?.tyxBalance ?? 0.0;
    final amount = double.tryParse(_amountInput.trim()) ?? 0.0;

    if (amount < 100) {
      setState(() => _errorMessage = 'Minimum withdrawal amount is ₱ 100.00.');
      return;
    }

    if (amount > tyxBal) {
      setState(() => _errorMessage = 'Requested amount exceeds your available balance.');
      return;
    }

    final walletKey = (s.userProfile?.walletPublicKey != null && s.userProfile!.walletPublicKey!.isNotEmpty)
        ? s.userProfile!.walletPublicKey!
        : s.walletAddress;

    if (walletKey.isEmpty) {
      setState(
        () => _errorMessage =
            'Withdrawals are only available to connected Solana wallets. Please link your Solana wallet first in Payment Methods or Trust & Verification.',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final requestId = 'withdraw_$timestamp';
      final svc = FirestoreService(token, s.handleTokenRefresh);
      final methodTitle = 'Solana ($_selectedCoin)';

      final feePhp = (amount * 0.02);
      final netPhp = (amount - feePhp);
      final activeRate = _selectedCoin == 'SOL' ? (_solToPhpRate > 0 ? _solToPhpRate : 8000.0) : (_usdToPhpRate > 0 ? _usdToPhpRate : 57.0);
      final cryptoAmount = activeRate > 0 ? netPhp / activeRate : 0.0;

      final requestData = <String, dynamic>{
        'id': requestId,
        'uid': uid,
        'userName': s.userName,
        'amount': amount,
        'feeAmount': feePhp,
        'netAmount': netPhp,
        'rate': activeRate,
        'currency': 'PHP',
        'cryptoAmount': cryptoAmount,
        'coin': _selectedCoin,
        'status': 'Pending',
        'createdAt': timestamp,
        'method': methodTitle,
        'walletPublicKey': walletKey,
      };

      // Direct on-chain treasury transfer if private key configured
      String txSignature = '';
      bool isOnChainTransferred = false;

      final treasuryPrivKey = Env.solanaPrivateKey;
      if (treasuryPrivKey.isNotEmpty) {
        try {
          if (_selectedCoin == 'SOL') {
            final lamports = (cryptoAmount * 1e9).round();
            if (lamports > 0) {
              final sig = await broadcastTreasuryTransfer(
                treasuryPrivKeyBase58: treasuryPrivKey,
                recipientPubkey: walletKey,
                lamports: lamports,
              );
              if (sig != null && sig.isNotEmpty) {
                txSignature = sig;
                isOnChainTransferred = true;
              }
            }
          } else {
            if (cryptoAmount > 0) {
              final sig = await broadcastTreasuryTokenTransfer(
                treasuryPrivKeyBase58: treasuryPrivKey,
                recipientPubkey: walletKey,
                amountInUsdt: cryptoAmount,
              );
              if (sig != null && sig.isNotEmpty) {
                txSignature = sig;
                isOnChainTransferred = true;
              }
            }
          }
        } catch (vaultErr) {
          print('Direct client-side vault transfer skipped/queued: $vaultErr');
        }
      }

      final txStatus = isOnChainTransferred ? 'Successful' : 'PENDING_REVIEW';

      // Save withdrawal request record (Dual-collection sync with admin queue)
      final withReqPayload = {
        ...requestData,
        'userId': uid,
        'originRail': 'mwa_on_chain',
        'status': txStatus,
        if (txSignature.isNotEmpty) 'solanaTxSignature': txSignature,
        'updatedAt': timestamp,
      };
      await svc.createOrUpdate('withdrawalRequests/$requestId', withReqPayload);
      await svc.createOrUpdate('withdrawal_requests/$requestId', withReqPayload);

      // Record in user wallet sub-collection (/wallets/{userId}/transactions/{txId})
      final ledgerTxData = {
        'id': requestId,
        'userId': uid,
        'uid': uid,
        'title': isOnChainTransferred
            ? 'Withdrawal Successful ($methodTitle)'
            : 'Withdrawal Request ($methodTitle)',
        'type': 'WITHDRAWAL',
        'direction': 'DEBIT',
        'amount': amount,
        'feeAmount': feePhp,
        'netAmount': netPhp,
        'rate': activeRate,
        'cryptoAmount': cryptoAmount,
        'coin': _selectedCoin,
        'currency': 'PHP',
        'status': txStatus,
        'originRail': 'mwa_on_chain',
        'payoutMethod': 'Solana',
        'paymentMethod': 'Solana',
        'method': 'Solana',
        'walletPublicKey': walletKey,
        if (txSignature.isNotEmpty) 'solanaTxSignature': txSignature,
        'referenceNumber': requestId.length >= 8 ? requestId.substring(0, 8).toUpperCase() : requestId,
        'description': isOnChainTransferred
            ? 'Withdrew ₱${amount.toStringAsFixed(2)} to $walletKey (${cryptoAmount.toStringAsFixed(_selectedCoin == 'SOL' ? 6 : 2)} $_selectedCoin). On-Chain Tx: $txSignature'
            : 'Requested ₱${amount.toStringAsFixed(2)} withdrawal to $walletKey (${cryptoAmount.toStringAsFixed(_selectedCoin == 'SOL' ? 6 : 2)} $_selectedCoin)',
        'desc': isOnChainTransferred
            ? 'Withdrew ₱${amount.toStringAsFixed(2)} to $walletKey (${cryptoAmount.toStringAsFixed(_selectedCoin == 'SOL' ? 6 : 2)} $_selectedCoin). On-Chain Tx: $txSignature'
            : 'Requested ₱${amount.toStringAsFixed(2)} withdrawal to $walletKey (${cryptoAmount.toStringAsFixed(_selectedCoin == 'SOL' ? 6 : 2)} $_selectedCoin)',
        'createdAt': timestamp,
        'updatedAt': timestamp,
      };
      await svc.createOrUpdate('wallets/$uid/transactions/$requestId', ledgerTxData);

      // Record global ledger transaction
      final txId = 'tx_$timestamp';
      await svc.createOrUpdate('transactions/$txId', {
        ...ledgerTxData,
        'id': txId,
        'amount': -amount,
      });

      // Deduct balance
      final newBal = (tyxBal - amount).clamp(0.0, double.infinity);
      await svc.createOrUpdate('users/$uid', {'tyxBalance': newBal});

      // Update local state
      s.userProfile = s.userProfile?.copyWith(tyxBalance: newBal);
      s.loadTransactions();

      setState(() {
        _isSubmitting = false;
        _successMessage = isOnChainTransferred
            ? 'Withdrawal of ₱ ${amount.toStringAsFixed(2)} (${cryptoAmount.toStringAsFixed(_selectedCoin == 'SOL' ? 6 : 2)} $_selectedCoin) has been transferred directly to your Solana wallet on-chain!'
            : 'Withdrawal of ₱ ${amount.toStringAsFixed(2)} to your Solana wallet requested successfully! Processing typically completes within 1 hour.';
      });
      s.showAppToast(
        isOnChainTransferred ? 'Withdrawal Completed' : 'Withdrawal Requested',
        '₱ ${amount.toStringAsFixed(2)} via $methodTitle ${isOnChainTransferred ? "sent on-chain!" : "submitted."}',
      );
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Withdrawal request failed: $e';
      });
    }
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final tyxBal = s.userProfile?.tyxBalance ?? 0.0;
    final isP2p = s.selectedWithdrawRail == 'manual_p2p';
    final isGcash = s.selectedP2pWithdrawMethod == 'GCash';
    final req = s.activeP2pWithdrawalRequest;

    final walletKey = (s.userProfile?.walletPublicKey != null && s.userProfile!.walletPublicKey!.isNotEmpty)
        ? s.userProfile!.walletPublicKey!
        : s.walletAddress;
    final hasWallet = walletKey.isNotEmpty;

    final amount = double.tryParse(_amountInput.trim()) ?? 0.0;
    final feePhp = amount * 0.02;
    final netPhp = (amount - feePhp).clamp(0.0, double.infinity);

    final solRate = _solToPhpRate > 0 ? _solToPhpRate : 8000.0;
    final usdtRate = _usdToPhpRate > 0 ? _usdToPhpRate : 57.0;
    final estCrypto = _selectedCoin == 'SOL' ? (netPhp / solRate) : (netPhp / usdtRate);

    final modalBg = isDark ? "bg-zinc-900 border-zinc-800 shadow-2xl" : "bg-white border-zinc-200 shadow-xl";
    final cardBg = isDark ? "bg-zinc-950/40 border-zinc-850" : "bg-zinc-50 border-zinc-150";

    return div(
      classes: 'fixed inset-0 z-[100] flex items-center justify-center bg-zinc-950/80 backdrop-blur-md px-4',
      [
        div(
          classes: 'w-full max-w-lg rounded-3xl border $modalBg overflow-hidden animate-fade-up',
          [
            // Header
            div(
              classes: 'p-6 flex items-center justify-between border-b ${isDark ? "border-zinc-800" : "border-zinc-100"}',
              [
                div(classes: 'flex items-center gap-3', [
                  div(
                    classes: 'w-10 h-10 rounded-2xl bg-purple-500/10 flex items-center justify-center text-purple-400',
                    [lIcon('arrow-up-right', cls: 'w-5 h-5')],
                  ),
                  div([
                    h2(classes: 'text-lg font-bold', [Component.text('Withdraw Funds')]),
                    p(classes: 'text-xs text-zinc-500', [
                      Component.text(isP2p ? 'P2P Fiat Cashout (GCash & Maya)' : 'Solana Network (SOL & USDT)'),
                    ]),
                  ]),
                ]),
                button(
                  classes: 'p-2 rounded-xl text-zinc-400 hover:text-zinc-100 hover:bg-zinc-800/50 transition-colors border-0 bg-transparent cursor-pointer',
                  events: {'click': (_) => s.setState(() => s.showWithdrawModal = false)},
                  [lIcon('x', cls: 'w-5 h-5')],
                ),
              ],
            ),

            // Body
            div(classes: 'p-6 space-y-5 max-h-[75vh] overflow-y-auto custom-scrollbar', [
              // Alerts
              if (_errorMessage != null)
                div(classes: 'p-3.5 rounded-2xl bg-red-500/10 border border-red-500/20 text-red-400 text-xs flex items-center gap-2', [
                  lIcon('alert-circle', cls: 'w-4 h-4 flex-shrink-0'),
                  span([Component.text(_errorMessage!)]),
                ]),

              if (_successMessage != null)
                div(classes: 'p-3.5 rounded-2xl bg-green-500/10 border border-green-500/20 text-green-400 text-xs flex items-center gap-2', [
                  lIcon('check-circle-2', cls: 'w-4 h-4 flex-shrink-0'),
                  span([Component.text(_successMessage!)]),
                ]),

              // Top Rail Selector
              div(classes: 'p-1 rounded-2xl $cardBg grid grid-cols-2 gap-1', [
                button(
                  classes:
                      'py-2 rounded-xl text-xs font-bold transition-all cursor-pointer border-0 outline-none flex items-center justify-center gap-1.5 '
                      '${isP2p ? "bg-purple-600 text-white shadow" : (isDark ? "text-zinc-400 hover:text-zinc-200" : "text-zinc-600 hover:text-zinc-800")}',
                  events: {'click': (_) => s.setState(() => s.selectedWithdrawRail = 'manual_p2p')},
                  [
                    lIcon('users', cls: 'w-4 h-4'),
                    Component.text('P2P Agent Rail'),
                  ],
                ),
                button(
                  classes:
                      'py-2 rounded-xl text-xs font-bold transition-all cursor-pointer border-0 outline-none flex items-center justify-center gap-1.5 '
                      '${!isP2p ? "bg-[#512da8] text-white shadow" : (isDark ? "text-zinc-400 hover:text-zinc-200" : "text-zinc-600 hover:text-zinc-800")}',
                  events: {'click': (_) => s.setState(() => s.selectedWithdrawRail = 'solana')},
                  [
                    lIcon('coins', cls: 'w-4 h-4'),
                    Component.text('Solana (SOL/USDT)'),
                  ],
                ),
              ]),

              // ══════════════════════════════════════════════════════════════
              // P2P AGENT CASH OUT RAIL
              // ══════════════════════════════════════════════════════════════
              if (isP2p) ...[
                // ── P2P SUB-STATE 1: WAITING FOR AGENT CLAIM ────────────────
                if (req != null &&
                    (req.status == 'WAITING_FOR_AGENT' ||
                        req.status == 'PENDING_REVIEW' ||
                        req.status == 'PENDING')) ...[
                  div(
                    classes:
                        'p-6 rounded-2xl bg-purple-500/10 border border-purple-500/20 text-center space-y-4 animate-fadeIn',
                    [
                      div(
                        classes:
                            'w-16 h-16 rounded-full bg-purple-500/20 text-purple-400 flex items-center justify-center mx-auto animate-pulse',
                        [
                          lIcon('radio', cls: 'w-8 h-8'),
                        ],
                      ),
                      div(classes: 'space-y-1', [
                        h3(classes: 'text-base font-bold text-white', [
                          Component.text('Notifying Payment Agents...'),
                        ]),
                        p(classes: 'text-xs text-zinc-400 leading-relaxed', [
                          Component.text(
                            'Your cashout request for ₱${req.amount.toStringAsFixed(2)} via ${req.paymentMethod} to ${req.userAccountNumber} (${req.userAccountName}) has been broadcasted to verified P2P agents.',
                          ),
                        ]),
                      ]),
                      div(classes: 'flex items-center justify-center gap-2 text-xs text-purple-400 font-bold', [
                        span(classes: 'w-2 h-2 rounded-full bg-purple-400 animate-ping', []),
                        Component.text('Awaiting Agent Claim & Transfer'),
                      ]),

                      // Cancellation Action
                      div(classes: 'pt-2 space-y-2', [
                        button(
                          classes:
                              'w-full py-2.5 rounded-xl text-xs font-bold text-rose-400 hover:text-rose-300 bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/30 transition cursor-pointer flex items-center justify-center gap-2',
                          events: {'click': (_) => s.handleCancelP2pWithdrawal(req.id)},
                          [
                            lIcon('x-circle', cls: 'w-4 h-4 text-rose-400'),
                            Component.text('Cancel Request & Refund ₱${req.amount.toStringAsFixed(2)}'),
                          ],
                        ),
                        span(classes: 'text-[10px] text-zinc-500 text-center block', [
                          Component.text('No agent has claimed this order yet. You may cancel at any time to instantly unlock your balance.'),
                        ]),
                      ]),
                    ],
                  ),
                ]
                // ── P2P SUB-STATE 2: AGENT CLAIMED ORDER / SENDING MONEY ────
                else if (req != null && req.status == 'AWAITING_AGENT_PAYMENT') ...[
                  div(classes: 'space-y-4 animate-fadeIn', [
                    div(
                      classes:
                          'p-4 rounded-2xl bg-amber-500/10 border border-amber-500/30 flex items-center gap-3',
                      [
                        div(
                          classes:
                              'w-10 h-10 rounded-xl bg-amber-500/20 text-amber-400 flex items-center justify-center shrink-0 font-bold text-xs',
                          [lIcon('loader', cls: 'w-5 h-5 animate-spin')],
                        ),
                        div(classes: 'text-left space-y-0.5', [
                          span(classes: 'text-xs font-bold text-amber-400 block', [
                            Component.text('${req.agentName ?? "Agent"} is processing your payout'),
                          ]),
                          span(classes: 'text-[11px] text-zinc-400 block', [
                            Component.text('Transferring ₱${req.amount.toStringAsFixed(2)} to ${req.paymentMethod} (${req.userAccountNumber}).'),
                          ]),
                        ]),
                      ],
                    ),
                    div(classes: 'p-4 rounded-2xl $cardBg space-y-2 text-xs text-left', [
                      div(classes: 'flex justify-between', [
                        span(classes: 'text-zinc-500', [Component.text('Recipient Name')]),
                        span(classes: 'font-bold text-zinc-200', [Component.text(req.userAccountName)]),
                      ]),
                      div(classes: 'flex justify-between', [
                        span(classes: 'text-zinc-500', [Component.text('Recipient Number')]),
                        span(classes: 'font-mono font-bold text-purple-400', [Component.text(req.userAccountNumber)]),
                      ]),
                      div(classes: 'flex justify-between', [
                        span(classes: 'text-zinc-500', [Component.text('Payout Amount')]),
                        span(classes: 'font-bold text-emerald-400', [Component.text('₱ ${req.amount.toStringAsFixed(2)}')]),
                      ]),
                    ]),
                  ]),
                ]
                // ── P2P SUB-STATE 3: AGENT SENT RECEIPT / AWAITING USER CONFIRMATION ─
                else if (req != null && req.status == 'PENDING_CONFIRMATION') ...[
                  div(classes: 'space-y-4 animate-fadeIn', [
                    div(
                      classes:
                          'p-4 rounded-2xl bg-emerald-500/10 border border-emerald-500/30 flex items-center gap-3',
                      [
                        div(
                          classes:
                              'w-10 h-10 rounded-xl bg-emerald-500/20 text-emerald-400 flex items-center justify-center shrink-0',
                          [lIcon('check-circle', cls: 'w-5 h-5')],
                        ),
                        div(classes: 'text-left space-y-0.5', [
                          span(classes: 'text-xs font-bold text-emerald-400 block', [
                            Component.text('Payout Dispatched by Agent!'),
                          ]),
                          span(classes: 'text-[11px] text-zinc-400 block', [
                            Component.text('Please verify receipt on your ${req.paymentMethod} app, then confirm below.'),
                          ]),
                        ]),
                      ],
                    ),

                    // Receipt preview & reference
                    div(classes: 'p-4 rounded-2xl $cardBg space-y-3 text-center', [
                      if (req.proofImageUrl.isNotEmpty)
                        div(classes: 'rounded-xl overflow-hidden border border-zinc-700 bg-black/40 max-h-48 flex items-center justify-center', [
                          img(
                            src: req.proofImageUrl,
                            classes: 'w-full h-auto max-h-48 object-contain',
                            alt: 'Agent Payment Receipt',
                          ),
                        ]),
                      div(classes: 'flex justify-between items-center text-xs px-2 pt-1', [
                        span(classes: 'text-zinc-500', [Component.text('Reference Number')]),
                        span(classes: 'font-mono font-bold text-purple-400 text-sm', [Component.text(req.referenceNumber)]),
                      ]),
                      div(classes: 'flex justify-between items-center text-xs px-2', [
                        span(classes: 'text-zinc-500', [Component.text('Paid to')]),
                        span(classes: 'font-bold text-zinc-200', [Component.text('${req.userAccountName} (${req.userAccountNumber})')]),
                      ]),
                    ]),

                    // Confirmation button
                    button(
                      classes:
                          'w-full py-3.5 rounded-2xl bg-gradient-to-r from-emerald-600 to-teal-600 text-white font-bold text-sm shadow-lg shadow-emerald-500/25 hover:from-emerald-500 hover:to-teal-500 transition cursor-pointer border-0 flex items-center justify-center gap-2',
                      events: {'click': (_) => s.handleConfirmP2pWithdrawalReceived(req.id)},
                      [
                        lIcon('check-check', cls: 'w-5 h-5'),
                        Component.text('I Received ₱${req.amount.toStringAsFixed(2)} in my ${req.paymentMethod}'),
                      ],
                    ),
                  ]),
                ]
                // ── P2P SUB-STATE 4: LOADING ACTIVE ORDER IF ID IS PRESENT ─────────────
                else if (s.activeP2pWithdrawalId != null && s.activeP2pWithdrawalId!.isNotEmpty) ...[
                  div(
                    classes:
                        'p-8 rounded-2xl bg-purple-500/10 border border-purple-500/20 text-center space-y-4 animate-fadeIn',
                    [
                      div(
                        classes:
                            'w-12 h-12 rounded-full bg-purple-500/20 text-purple-400 flex items-center justify-center mx-auto',
                        [lIcon('loader', cls: 'w-6 h-6 animate-spin')],
                      ),
                      div(classes: 'space-y-1', [
                        h3(classes: 'text-sm font-bold text-white', [
                          Component.text('Loading Cashout Details...'),
                        ]),
                        p(classes: 'text-xs text-zinc-400', [
                          Component.text('Fetching real-time order status from P2P network...'),
                        ]),
                      ]),
                    ],
                  ),
                ]
                // ── P2P SUB-STATE 5: NEW WITHDRAWAL REQUEST FORM ─────────────
                else ...[
                  // Withdrawable balance card
                  div(
                    classes:
                        'p-5 rounded-2xl bg-gradient-to-br from-purple-900/40 via-indigo-900/30 to-zinc-900 border border-purple-500/20 flex items-center justify-between',
                    [
                      div([
                        span(classes: 'text-[10px] uppercase font-bold tracking-widest text-purple-300', [Component.text('Withdrawable Balance')]),
                        h3(classes: 'text-2xl font-black text-white mt-0.5', [Component.text('₱ ${tyxBal.toStringAsFixed(2)}')]),
                      ]),
                      div(classes: 'text-right', [
                        span(classes: 'text-[10px] text-zinc-400 block', [Component.text('Min: ₱100.00')]),
                        span(classes: 'text-[10px] text-emerald-400 font-bold', [Component.text('0% P2P Agent Fee')]),
                      ]),
                    ],
                  ),

                  // Method Selector (GCash / Maya)
                  div(classes: 'space-y-2', [
                    label(classes: 'text-xs font-bold text-zinc-400', [Component.text('Select Payout Method')]),
                    div(classes: 'grid grid-cols-2 gap-3', [
                      button(
                        classes:
                            'p-3.5 rounded-2xl border text-left transition-all ${isGcash ? "bg-purple-500/10 border-purple-500 ring-1 ring-purple-500" : (isDark ? "bg-zinc-800/40 border-zinc-800 hover:border-zinc-700" : "bg-zinc-50 border-zinc-200 hover:border-zinc-300")} cursor-pointer',
                        events: {'click': (_) => s.setState(() => s.selectedP2pWithdrawMethod = 'GCash')},
                        [
                          div(classes: 'flex items-center justify-between mb-1', [
                            span(classes: 'font-bold text-sm text-blue-400', [Component.text('GCash')]),
                            span(classes: 'text-[10px] px-1.5 py-0.5 rounded bg-blue-500/20 text-blue-300 font-bold', [Component.text('Instant')]),
                          ]),
                          p(classes: 'text-[11px] text-zinc-400', [Component.text('Philippine E-Wallet')]),
                        ],
                      ),
                      button(
                        classes:
                            'p-3.5 rounded-2xl border text-left transition-all ${!isGcash ? "bg-purple-500/10 border-purple-500 ring-1 ring-purple-500" : (isDark ? "bg-zinc-800/40 border-zinc-800 hover:border-zinc-700" : "bg-zinc-50 border-zinc-200 hover:border-zinc-300")} cursor-pointer',
                        events: {'click': (_) => s.setState(() => s.selectedP2pWithdrawMethod = 'Maya')},
                        [
                          div(classes: 'flex items-center justify-between mb-1', [
                            span(classes: 'font-bold text-sm text-emerald-400', [Component.text('Maya')]),
                            span(classes: 'text-[10px] px-1.5 py-0.5 rounded bg-emerald-500/20 text-emerald-300 font-bold', [Component.text('Instant')]),
                          ]),
                          p(classes: 'text-[11px] text-zinc-400', [Component.text('Digital Bank & Wallet')]),
                        ],
                      ),
                    ]),
                  ]),

                  // Cashout Amount Entry
                  div(classes: 'space-y-2', [
                    label(classes: 'text-xs font-bold text-zinc-400', [Component.text('Cashout Amount (₱)')]),
                    div(classes: 'relative', [
                      span(classes: 'absolute left-4 top-1/2 -translate-y-1/2 text-lg font-black text-zinc-500', [Component.text('₱')]),
                      input(
                        type: InputType.number,
                        classes: 'w-full pl-9 pr-4 py-3 rounded-2xl border ${isDark ? "bg-zinc-950 border-zinc-800 text-white" : "bg-zinc-50 border-zinc-200 text-black"} font-bold text-lg focus:border-purple-500 focus:outline-none transition-colors',
                        attributes: {
                          'placeholder': '100.00',
                          'min': '100',
                          'step': '50',
                          'value': _amountInput,
                        },
                        events: {
                          'input': (e) {
                            final val = getInputValue(e.target);
                            setState(() => _amountInput = val);
                          },
                          'change': (e) {
                            final val = getInputValue(e.target);
                            setState(() => _amountInput = val);
                          },
                        },
                      ),
                    ]),

                    // Quick presets
                    div(classes: 'grid grid-cols-5 gap-2 pt-1', [
                      for (final val in [100, 500, 1000, 5000])
                        button(
                          classes: 'py-2 rounded-xl text-xs font-bold border transition-colors ${amount == val.toDouble() ? "bg-purple-500 text-white border-purple-500" : (isDark ? "bg-zinc-800/60 border-zinc-700/60 text-zinc-300 hover:bg-zinc-800" : "bg-zinc-100 border-zinc-200 text-zinc-700 hover:bg-zinc-200")} cursor-pointer',
                          events: {'click': (_) => setState(() => _amountInput = val.toString())},
                          [Component.text('₱$val')],
                        ),
                      button(
                        classes: 'py-2 rounded-xl text-xs font-bold border transition-colors ${amount == tyxBal ? "bg-purple-500 text-white border-purple-500" : (isDark ? "bg-purple-500/10 border-purple-500/30 text-purple-300 hover:bg-purple-500/20" : "bg-purple-50 border-purple-200 text-purple-700 hover:bg-purple-100")} cursor-pointer',
                        events: {'click': (_) => setState(() => _amountInput = tyxBal.toStringAsFixed(0))},
                        [Component.text('MAX')],
                      ),
                    ]),
                  ]),

                  // Recipient Account Name & Number
                  () {
                    final phone = s.userProfile?.phoneNumber;
                    final name = s.userProfile?.name;
                    final registeredPhone = (phone != null && phone.isNotEmpty) ? phone : '';
                    final registeredName = (name != null && name.isNotEmpty)
                        ? name
                        : (s.userName.isNotEmpty ? s.userName : '');

                    final displayAccountName = _accountNameInput.isNotEmpty ? _accountNameInput : registeredName;
                    final displayAccountNumber = _accountNumberInput.isNotEmpty ? _accountNumberInput : registeredPhone;

                    return div(classes: 'space-y-3', [
                      div(classes: 'space-y-1', [
                        label(classes: 'text-xs font-bold text-zinc-400', [Component.text('Recipient Registered Name (${s.selectedP2pWithdrawMethod})')]),
                        input(
                          type: InputType.text,
                          classes: 'w-full px-4 py-3 rounded-2xl border ${isDark ? "bg-zinc-950 border-zinc-800 text-white" : "bg-zinc-50 border-zinc-200 text-black"} text-sm focus:border-purple-500 focus:outline-none transition-colors',
                          attributes: {
                            'placeholder': 'e.g., Juan Dela Cruz',
                            'value': displayAccountName,
                          },
                          events: {'input': (e) => setState(() => _accountNameInput = getInputValue(e.target))},
                        ),
                      ]),
                      div(classes: 'space-y-1', [
                        label(classes: 'text-xs font-bold text-zinc-400', [Component.text('Recipient Mobile / Account Number')]),
                        input(
                          type: InputType.text,
                          classes: 'w-full px-4 py-3 rounded-2xl border ${isDark ? "bg-zinc-950 border-zinc-800 text-white" : "bg-zinc-50 border-zinc-200 text-black"} text-sm font-mono focus:border-purple-500 focus:outline-none transition-colors',
                          attributes: {
                            'placeholder': 'e.g., 09171234567',
                            'value': displayAccountNumber,
                          },
                          events: {'input': (e) => setState(() => _accountNumberInput = getInputValue(e.target))},
                        ),
                        if (registeredPhone.isNotEmpty)
                          div(classes: 'flex items-center gap-1.5 text-[11px] text-purple-400 font-medium pt-0.5', [
                            lIcon('check-circle-2', cls: 'w-3.5 h-3.5 text-purple-400 shrink-0'),
                            Component.text('Auto-filled with registered phone ($registeredPhone)'),
                          ]),
                      ]),
                    ]);
                  }(),

                  // Summary
                  div(classes: 'p-4 rounded-2xl border $cardBg space-y-2 text-xs', [
                    div(classes: 'flex justify-between text-zinc-400', [
                      span([Component.text('Cashout Amount')]),
                      span(classes: 'font-bold text-zinc-200 font-mono', [Component.text('₱ ${amount.toStringAsFixed(2)}')]),
                    ]),
                    div(classes: 'flex justify-between text-zinc-400', [
                      span([Component.text('P2P Fulfillment Fee')]),
                      span(classes: 'font-bold text-emerald-400 font-mono', [Component.text('₱ 0.00 (Free)')]),
                    ]),
                    div(classes: 'flex justify-between items-center text-zinc-400 border-t ${isDark ? "border-zinc-800" : "border-zinc-200"} pt-2', [
                      span(classes: 'font-bold text-purple-400', [Component.text('Total Received via ${s.selectedP2pWithdrawMethod}')]),
                      span(classes: 'font-black text-base text-emerald-400 font-mono', [Component.text('₱ ${amount.toStringAsFixed(2)}')]),
                    ]),
                  ]),

                  // Request button
                  button(
                    classes:
                        'w-full py-4 rounded-2xl bg-gradient-to-r from-purple-600 to-indigo-600 text-white font-bold text-sm shadow-lg shadow-purple-500/25 hover:from-purple-500 hover:to-indigo-500 transition-all flex items-center justify-center gap-2 cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed border-0',
                    attributes: {
                      if (s.isSubmittingP2pWithdraw || amount < 100 || amount > tyxBal || _accountNameInput.trim().isEmpty || _accountNumberInput.trim().isEmpty) 'disabled': 'true',
                    },
                    events: {'click': (_) => _submitP2pWithdrawal()},
                    [
                      if (s.isSubmittingP2pWithdraw)
                        lIcon('loader', cls: 'w-5 h-5 animate-spin')
                      else
                        lIcon('arrow-up-right', cls: 'w-5 h-5'),
                      Component.text(
                        s.isSubmittingP2pWithdraw
                            ? 'Broadcasting Request...'
                            : (amount > tyxBal
                                ? 'Insufficient Balance'
                                : 'Request P2P Cashout via ${s.selectedP2pWithdrawMethod}'),
                      ),
                    ],
                  ),
                ],
              ]
              // ══════════════════════════════════════════════════════════════
              // SOLANA CRYPTO GATEWAY RAIL
              // ══════════════════════════════════════════════════════════════
              else ...[
                // Connected wallet status banner
                if (hasWallet)
                  div(classes: 'p-3 rounded-2xl bg-green-500/10 border border-green-500/20 flex items-center justify-between', [
                    div(classes: 'flex items-center gap-2.5 min-w-0', [
                      div(classes: 'w-2 h-2 rounded-full bg-green-400 animate-pulse flex-shrink-0', []),
                      div(classes: 'min-w-0', [
                        p(classes: 'text-[11px] font-bold text-green-400', [Component.text('Connected Solana Wallet')]),
                        p(classes: 'text-xs font-mono text-zinc-300 truncate', [Component.text(walletKey)]),
                      ]),
                    ]),
                    span(classes: 'px-2 py-0.5 rounded text-[10px] font-bold bg-green-500/20 text-green-300', [Component.text('VERIFIED')]),
                  ])
                else
                  div(classes: 'p-3.5 rounded-2xl bg-amber-500/10 border border-amber-500/20 flex items-center justify-between', [
                    div(classes: 'flex items-center gap-2.5', [
                      lIcon('shield-alert', cls: 'w-5 h-5 text-amber-400 flex-shrink-0'),
                      div([
                        p(classes: 'text-xs font-bold text-amber-400', [Component.text('No Solana Wallet Linked')]),
                        p(classes: 'text-[11px] text-zinc-400', [Component.text('Link your Solana wallet in Payment Methods first.')]),
                      ]),
                    ]),
                    button(
                      classes: 'px-3 py-1.5 rounded-xl bg-amber-500 text-black text-xs font-bold hover:bg-amber-400 transition-colors border-0 cursor-pointer',
                      events: {
                        'click': (_) => s.setState(() {
                          s.showWalletSelectionModal = true;
                        }),
                      },
                      [Component.text('Link Wallet')],
                    ),
                  ]),

                // Withdrawable balance card
                div(
                  classes: 'p-5 rounded-2xl bg-gradient-to-br from-purple-900/40 via-indigo-900/30 to-zinc-900 border border-purple-500/20 flex items-center justify-between',
                  [
                    div([
                      span(classes: 'text-[10px] uppercase font-bold tracking-widest text-purple-300', [Component.text('Withdrawable Balance')]),
                      h3(classes: 'text-2xl font-black text-white mt-0.5', [Component.text('₱ ${tyxBal.toStringAsFixed(2)}')]),
                    ]),
                    div(classes: 'text-right', [
                      span(classes: 'text-[10px] text-zinc-400 block', [Component.text('Min: ₱100.00')]),
                      span(classes: 'text-[10px] text-purple-400 font-bold', [Component.text('2% Processing Fee')]),
                    ]),
                  ],
                ),

                // Amount entry
                div(classes: 'space-y-2', [
                  label(classes: 'text-xs font-bold text-zinc-400', [Component.text('Withdrawal Amount (₱)')]),
                  div(classes: 'relative', [
                    span(classes: 'absolute left-4 top-1/2 -translate-y-1/2 text-lg font-black text-zinc-500', [Component.text('₱')]),
                    input(
                      type: InputType.number,
                      classes: 'w-full pl-9 pr-4 py-3 rounded-2xl border ${isDark ? "bg-zinc-950 border-zinc-800 text-white" : "bg-zinc-50 border-zinc-200 text-black"} font-bold text-lg focus:border-purple-500 focus:outline-none transition-colors',
                      attributes: {
                        'placeholder': '100.00',
                        'min': '100',
                        'step': '50',
                        'value': _amountInput,
                      },
                      events: {
                        'input': (e) {
                          final val = getInputValue(e.target);
                          setState(() => _amountInput = val);
                        },
                        'change': (e) {
                          final val = getInputValue(e.target);
                          setState(() => _amountInput = val);
                        },
                      },
                    ),
                  ]),

                  // Quick preset buttons
                  div(classes: 'grid grid-cols-5 gap-2 pt-1', [
                    for (final val in [100, 500, 1000, 5000])
                      button(
                        classes: 'py-2 rounded-xl text-xs font-bold border transition-colors ${amount == val.toDouble() ? "bg-purple-500 text-white border-purple-500" : (isDark ? "bg-zinc-800/60 border-zinc-700/60 text-zinc-300 hover:bg-zinc-800" : "bg-zinc-100 border-zinc-200 text-zinc-700 hover:bg-zinc-200")} cursor-pointer',
                        events: {'click': (_) => setState(() => _amountInput = val.toString())},
                        [Component.text('₱$val')],
                      ),
                    button(
                      classes: 'py-2 rounded-xl text-xs font-bold border transition-colors ${amount == tyxBal ? "bg-purple-500 text-white border-purple-500" : (isDark ? "bg-purple-500/10 border-purple-500/30 text-purple-300 hover:bg-purple-500/20" : "bg-purple-50 border-purple-200 text-purple-700 hover:bg-purple-100")} cursor-pointer',
                      events: {'click': (_) => setState(() => _amountInput = tyxBal.toStringAsFixed(0))},
                      [Component.text('MAX')],
                    ),
                  ]),
                ]),

                // Payout asset selection (SOL / USDT)
                div(classes: 'space-y-2', [
                  div(classes: 'flex items-center justify-between', [
                    label(classes: 'text-xs font-bold text-zinc-400', [Component.text('Select Payout Asset')]),
                    span(classes: 'text-[10px] text-zinc-500 flex items-center gap-1', [
                      lIcon('refresh-cw', cls: 'w-3 h-3 ${_isFetchingRates ? "animate-spin" : ""}'),
                      Component.text(_isFetchingRates ? 'Updating rates...' : 'Live Rates'),
                    ]),
                  ]),
                  div(classes: 'grid grid-cols-2 gap-3', [
                    // USDT
                    button(
                      classes: 'p-3.5 rounded-2xl border text-left transition-all ${_selectedCoin == 'USDT' ? "bg-purple-500/10 border-purple-500 ring-1 ring-purple-500" : (isDark ? "bg-zinc-800/40 border-zinc-800 hover:border-zinc-700" : "bg-zinc-50 border-zinc-200 hover:border-zinc-300")} cursor-pointer',
                      events: {'click': (_) => setState(() => _selectedCoin = 'USDT')},
                      [
                        div(classes: 'flex items-center justify-between mb-1', [
                          span(classes: 'font-bold text-sm text-green-400', [Component.text('USDT (SPL)')]),
                          span(classes: 'text-[10px] px-1.5 py-0.5 rounded bg-green-500/20 text-green-300 font-bold', [Component.text('Stable')]),
                        ]),
                        p(classes: 'text-[11px] text-zinc-400 font-mono', [Component.text('1 USDT ≈ ₱${usdtRate.toStringAsFixed(2)}')]),
                      ],
                    ),
                    // SOL
                    button(
                      classes: 'p-3.5 rounded-2xl border text-left transition-all ${_selectedCoin == 'SOL' ? "bg-purple-500/10 border-purple-500 ring-1 ring-purple-500" : (isDark ? "bg-zinc-800/40 border-zinc-800 hover:border-zinc-700" : "bg-zinc-50 border-zinc-200 hover:border-zinc-300")} cursor-pointer',
                      events: {'click': (_) => setState(() => _selectedCoin = 'SOL')},
                      [
                        div(classes: 'flex items-center justify-between mb-1', [
                          span(classes: 'font-bold text-sm text-purple-400', [Component.text('SOL (Native)')]),
                          span(classes: 'text-[10px] px-1.5 py-0.5 rounded bg-purple-500/20 text-purple-300 font-bold', [Component.text('Solana')]),
                        ]),
                        p(classes: 'text-[11px] text-zinc-400 font-mono', [Component.text('1 SOL ≈ ₱${solRate.toStringAsFixed(0)}')]),
                      ],
                    ),
                  ]),
                ]),

                // Summary
                div(classes: 'p-4 rounded-2xl border $cardBg space-y-2 text-xs', [
                  div(classes: 'flex justify-between text-zinc-400', [
                    span([Component.text('Gross Amount')]),
                    span(classes: 'font-bold text-zinc-200 font-mono', [Component.text('₱ ${amount.toStringAsFixed(2)}')]),
                  ]),
                  div(classes: 'flex justify-between text-zinc-400', [
                    span([Component.text('Network Fee (2%)')]),
                    span(classes: 'font-bold text-red-400 font-mono', [Component.text('- ₱ ${feePhp.toStringAsFixed(2)}')]),
                  ]),
                  div(classes: 'flex justify-between text-zinc-400 border-t ${isDark ? "border-zinc-800" : "border-zinc-200"} pt-2', [
                    span(classes: 'font-bold text-zinc-300', [Component.text('Net PHP Value')]),
                    span(classes: 'font-bold text-green-400 font-mono', [Component.text('₱ ${netPhp.toStringAsFixed(2)}')]),
                  ]),
                  div(classes: 'flex justify-between items-center text-zinc-400 border-t ${isDark ? "border-zinc-800" : "border-zinc-200"} pt-2', [
                    span(classes: 'font-bold text-purple-400', [Component.text('Estimated Payout')]),
                    span(
                      classes: 'font-black text-sm text-purple-300 font-mono',
                      [Component.text('${estCrypto.toStringAsFixed(_selectedCoin == 'SOL' ? 6 : 2)} $_selectedCoin')],
                    ),
                  ]),
                ]),

                // Submit Button
                button(
                  classes: 'w-full py-4 rounded-2xl bg-gradient-to-r from-purple-600 to-indigo-600 text-white font-bold text-sm shadow-lg shadow-purple-500/25 hover:from-purple-500 hover:to-indigo-500 transition-all flex items-center justify-center gap-2 cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed border-0',
                  attributes: {
                    if (_isSubmitting || !hasWallet || amount < 100 || amount > tyxBal) 'disabled': 'true',
                  },
                  events: {'click': (_) => _submitSolanaWithdrawal()},
                  [
                    if (_isSubmitting)
                      lIcon('loader', cls: 'w-5 h-5 animate-spin')
                    else
                      lIcon('arrow-up-right', cls: 'w-5 h-5'),
                    Component.text(
                      _isSubmitting
                          ? 'Processing Request...'
                          : (hasWallet
                              ? 'Confirm & Withdraw via Solana'
                              : 'Link Solana Wallet First'),
                    ),
                  ],
                ),
              ],
            ]),
          ],
        ),
      ],
    );
  }
}
