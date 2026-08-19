import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
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

  double _solToPhpRate = 8000.0;
  double _usdToPhpRate = 57.0;
  bool _isFetchingRates = false;

  bool _isSubmitting = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _fetchLiveRates();
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

  Future<void> _submitWithdrawal() async {
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

      // 1. Direct on-chain treasury transfer if private key configured
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

      final txStatus = isOnChainTransferred ? 'Successful' : 'Pending';

      // 2. Save withdrawal request record
      await svc.createOrUpdate('withdrawalRequests/$requestId', {
        ...requestData,
        'status': txStatus,
        if (txSignature.isNotEmpty) 'solanaTxSignature': txSignature,
      });

      // 3. Record ledger transaction
      final txId = 'tx_$timestamp';
      await svc.createOrUpdate('transactions/$txId', {
        'id': txId,
        'uid': uid,
        'title': isOnChainTransferred
            ? 'Withdrawal Successful ($methodTitle)'
            : 'Withdrawal Request ($methodTitle)',
        'type': 'withdraw',
        'amount': -amount,
        'feeAmount': feePhp,
        'netAmount': netPhp,
        'rate': activeRate,
        'cryptoAmount': cryptoAmount,
        'coin': _selectedCoin,
        'currency': 'PHP',
        'status': txStatus,
        'method': 'Solana',
        'walletPublicKey': walletKey,
        if (txSignature.isNotEmpty) 'solanaTxSignature': txSignature,
        'desc': isOnChainTransferred
            ? 'Withdrew ₱${amount.toStringAsFixed(2)} to $walletKey (${cryptoAmount.toStringAsFixed(_selectedCoin == 'SOL' ? 6 : 2)} $_selectedCoin). On-Chain Tx: $txSignature'
            : 'Requested ₱${amount.toStringAsFixed(2)} withdrawal to $walletKey (${cryptoAmount.toStringAsFixed(_selectedCoin == 'SOL' ? 6 : 2)} $_selectedCoin)',
        'createdAt': timestamp,
      });

      // 4. Deduct balance
      final newBal = (tyxBal - amount).clamp(0.0, double.infinity);
      await svc.createOrUpdate('users/$uid', {'tyxBalance': newBal});

      // 5. Update local state
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
                    p(classes: 'text-xs text-zinc-500', [Component.text('Solana Network (SOL & USDT)')]),
                  ]),
                ]),
                button(
                  classes: 'p-2 rounded-xl text-zinc-400 hover:text-zinc-100 hover:bg-zinc-800/50 transition-colors',
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
                    classes: 'px-3 py-1.5 rounded-xl bg-amber-500 text-black text-xs font-bold hover:bg-amber-400 transition-colors',
                    events: {
                      'click': (_) => s.setState(() {
                        s.showWithdrawModal = false;
                        s.activeTab = AppTab.profile;
                        s.profileView = ProfileView.payment;
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
                    },
                  ),
                ]),

                // Quick preset buttons
                div(classes: 'grid grid-cols-5 gap-2 pt-1', [
                  for (final val in [100, 500, 1000, 5000])
                    button(
                      classes: 'py-2 rounded-xl text-xs font-bold border transition-colors ${amount == val.toDouble() ? "bg-purple-500 text-white border-purple-500" : (isDark ? "bg-zinc-800/60 border-zinc-700/60 text-zinc-300 hover:bg-zinc-800" : "bg-zinc-100 border-zinc-200 text-zinc-700 hover:bg-zinc-200")}',
                      events: {'click': (_) => setState(() => _amountInput = val.toString())},
                      [Component.text('₱$val')],
                    ),
                  button(
                    classes: 'py-2 rounded-xl text-xs font-bold border transition-colors ${amount == tyxBal ? "bg-purple-500 text-white border-purple-500" : (isDark ? "bg-purple-500/10 border-purple-500/30 text-purple-300 hover:bg-purple-500/20" : "bg-purple-50 border-purple-200 text-purple-700 hover:bg-purple-100")}',
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
                    classes: 'p-3.5 rounded-2xl border text-left transition-all ${_selectedCoin == 'USDT' ? "bg-purple-500/10 border-purple-500 ring-1 ring-purple-500" : (isDark ? "bg-zinc-800/40 border-zinc-800 hover:border-zinc-700" : "bg-zinc-50 border-zinc-200 hover:border-zinc-300")}',
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
                    classes: 'p-3.5 rounded-2xl border text-left transition-all ${_selectedCoin == 'SOL' ? "bg-purple-500/10 border-purple-500 ring-1 ring-purple-500" : (isDark ? "bg-zinc-800/40 border-zinc-800 hover:border-zinc-700" : "bg-zinc-50 border-zinc-200 hover:border-zinc-300")}',
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
                classes: 'w-full py-4 rounded-2xl bg-gradient-to-r from-purple-600 to-indigo-600 text-white font-bold text-sm shadow-lg shadow-purple-500/25 hover:from-purple-500 hover:to-indigo-500 transition-all flex items-center justify-center gap-2 cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed',
                attributes: {
                  if (_isSubmitting || !hasWallet || amount < 100 || amount > tyxBal) 'disabled': 'true',
                },
                events: {'click': (_) => _submitWithdrawal()},
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
            ]),
          ],
        ),
      ],
    );
  }
}
