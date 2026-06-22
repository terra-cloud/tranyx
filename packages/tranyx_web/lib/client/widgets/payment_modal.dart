import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
import '../../services/web_interop.dart';

class PaymentModalComponent extends StatelessComponent {
  final TranyxAppState state;
  const PaymentModalComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final amount = s.depositAmount;
    final isSolana = s.selectedPaymentMethod == 'solana';

    // Fallback safe rate
    final rate = s.solToPhpRate > 0 ? s.solToPhpRate : 8500.0;
    final amountInSol = amount / rate;

    final modalBg = isDark ? "bg-zinc-900 border-zinc-800 shadow-2xl" : "bg-white border-zinc-200 shadow-xl";
    final cardBg = isDark ? "bg-zinc-950/40 border-zinc-850" : "bg-zinc-50 border-zinc-150";

    return div(
      classes: 'fixed inset-0 z-[100] flex items-center justify-center bg-zinc-950/80 backdrop-blur-md px-4',
      [
        div(
          classes: 'w-full max-w-md rounded-3xl border $modalBg overflow-hidden animate-fade-up',
          [
            // Header
            div(classes: 'p-6 text-center border-b ${isDark ? "border-zinc-800" : "border-zinc-100"}', [
              div(classes: 'w-16 h-16 rounded-2xl bg-indigo-500/10 flex items-center justify-center mx-auto mb-4', [
                lIcon('wallet', cls: 'w-8 h-8 text-indigo-400'),
              ]),
              h2(classes: 'text-xl font-bold mb-1', [Component.text('Top-up Tyxbit Balance')]),
              p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                Component.text('Your balance is insufficient. Top up now to complete your transaction.'),
              ]),
            ]),

            // Body
            div(classes: 'p-6 space-y-6 max-h-[60vh] overflow-y-auto custom-scrollbar', [
              // Amount section
              div(classes: 'text-center', [
                span(classes: 'text-xs font-medium ${isDark ? "text-zinc-500" : "text-zinc-400"} block mb-1', [
                  Component.text('Top-up Amount (₱)'),
                ]),
                div(classes: 'flex items-center justify-center gap-2 border-b-2 border-indigo-500/30 pb-2 mx-8', [
                  input(
                    type: InputType.number,
                    classes:
                        'w-full text-center text-3xl font-black text-indigo-400 bg-transparent border-none focus:outline-none placeholder:text-indigo-400/30',
                    // Do NOT use value: here — Jaspr would overwrite the DOM value on every
                    // re-render (controlled input), causing the user's typed amount to be reset
                    // to '' whenever any unrelated state update triggers a rebuild.
                    // Instead, set defaultValue via attributes so it only seeds the initial value.
                    attributes: {
                      'placeholder': '0.00',
                      'min': '1',
                      'step': '1',
                      'id': 'topup-amount-input',
                      'name': 'amount',
                      if (amount > 0) 'defaultValue': amount.toInt().toString(),
                    },
                    events: {
                      'input': (e) {
                        final val = getInputValue(e.target);
                        final parsed = num.tryParse(val);
                        s.setState(() => s.depositAmount = parsed != null ? parsed.toDouble() : 0.0);
                      },
                    },
                  ),
                ]),
                div(classes: 'flex flex-col gap-1 mt-2 text-center', [
                  span(classes: 'text-[10px] text-indigo-400/60 block font-medium', [
                    Component.text('1 Tyxbit = 1 Peso (₱)'),
                  ]),
                  span(classes: 'text-[10px] text-zinc-500 block font-bold', [
                    Component.text('Min ₱100 · Max ₱50,000 per transaction'),
                  ]),
                ]),

                // Quick Select Chips
                div(classes: 'flex flex-wrap justify-center gap-2 mt-4', [
                  for (final val in const [
                    (500, '₱500'),
                    (1000, '₱1,000'),
                    (2000, '₱2,000'),
                    (5000, '₱5,000'),
                    (10000, '₱10,000')
                  ])
                    button(
                      classes: 'px-3 py-1.5 rounded-xl text-xs font-bold border transition-all cursor-pointer '
                          '${amount == val.$1 ? "bg-indigo-500 text-white border-indigo-500 shadow-md shadow-indigo-500/20" : (isDark ? "bg-zinc-800/40 border-zinc-850 text-zinc-300 hover:bg-zinc-800" : "bg-white border-zinc-200 text-zinc-650 hover:bg-zinc-50")}',
                      events: {
                        'click': (_) {
                          s.setState(() => s.depositAmount = val.$1.toDouble());
                          final el = web.document.getElementById('topup-amount-input');
                          if (el != null) {
                            setInputValue(el, val.$1.toString());
                          }
                        }
                      },
                      [Component.text(val.$2)],
                    )
                ]),
              ]),

              // Payment Method Selectors
              div(
                classes: const String.fromEnvironment('ENV', defaultValue: 'dev') == 'prod' ? 'flex justify-center' : 'grid grid-cols-2 gap-3',
                [
                  if (const String.fromEnvironment('ENV', defaultValue: 'dev') != 'prod')
                    button(
                      classes:
                          'p-4 rounded-2xl border transition-all flex flex-col items-center gap-2 cursor-pointer border-0 outline-none '
                          '${!isSolana ? "border-2 border-indigo-500 bg-indigo-500/5 text-indigo-400 font-extrabold" : (isDark ? "bg-zinc-800/40 border-zinc-800 text-zinc-400 hover:bg-zinc-800/60" : "bg-zinc-50 border-zinc-200 text-zinc-650 hover:bg-zinc-100")}',
                      events: {
                        'click': (_) => s.setState(() => s.selectedPaymentMethod = 'xendit'),
                      },
                      [
                        lIcon('credit-card', cls: 'w-6 h-6'),
                        span(classes: 'text-xs', [Component.text('GCash / Card')]),
                      ],
                    ),
                  button(
                    classes:
                        'p-4 rounded-2xl border transition-all flex flex-col items-center gap-2 cursor-pointer border-0 outline-none '
                        '${const String.fromEnvironment('ENV', defaultValue: 'dev') == 'prod' ? "w-full" : ""}'
                        '${isSolana ? " border-2 border-[#512da8] bg-[#512da8]/5 text-indigo-400 font-extrabold" : (isDark ? " bg-zinc-800/40 border-zinc-800 text-zinc-400 hover:bg-zinc-800/60" : " bg-zinc-50 border-zinc-200 text-zinc-650 hover:bg-zinc-100")}',
                    events: {
                      'click': (_) {
                        s.setState(() => s.selectedPaymentMethod = 'solana');
                        s.fetchSolToPhpRate();
                      },
                    },
                    [
                      lIcon('zap', cls: 'w-6 h-6 text-[#512da8]'),
                      span(classes: 'text-xs', [Component.text('Solana (SOL)')]),
                    ],
                  ),
                ],
              ),

              // Dynamic Payment Method Detail Card
              if (!isSolana) ...[
                // Xendit fiat gateway details
                div(classes: 'p-4 rounded-2xl $cardBg space-y-3', [
                  _infoRow('Payment Processor', 'Xendit Gateway', isDark),
                  _infoRow('Tyxbit Equivalent', '${amount.toStringAsFixed(2)} Tyxbits', isDark),
                  _infoRow('Processor Status', 'Awaiting Checkout', isDark),
                ]),

                div(classes: 'space-y-3', [
                  if (s.pendingXenditInvoiceId != null) ...[
                    button(
                      classes:
                          'w-full py-4 rounded-2xl font-bold text-white bg-green-500 hover:bg-green-600 transition-colors flex items-center justify-center gap-2 border-0 cursor-pointer',
                      events: {
                        'click': (_) => s.verifyXenditPayment(),
                      },
                      [
                        if (s.isVerifyingPayment) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                        Component.text(s.isVerifyingPayment ? 'Verifying...' : 'I already paid'),
                      ],
                    ),
                    if (s.postJobError != null)
                      p(classes: 'text-xs text-red-400 text-center mt-2 font-semibold', [
                        Component.text(s.postJobError!),
                      ]),
                    button(
                      classes:
                          'w-full py-4 rounded-2xl font-bold border-0 cursor-pointer ${isDark ? "text-zinc-400 hover:text-zinc-200 bg-transparent" : "text-zinc-550 hover:text-zinc-700 bg-transparent"} transition-colors',
                      events: {
                        'click': (_) => s.setState(() {
                          s.showDepositModal = false;
                        }),
                      },
                      [Component.text('Cancel')],
                    ),
                  ] else ...[
                    button(
                      classes:
                          'w-full py-4 rounded-2xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2 border-0 cursor-pointer',
                      events: {
                        'click': (_) => s.createXenditInvoice(),
                      },
                      [
                        if (s.isDepositing) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                        Component.text(s.isDepositing ? 'Processing...' : 'Pay with Xendit'),
                      ],
                    ),
                    if (s.postJobError != null)
                      p(classes: 'text-xs text-red-400 text-center mt-2 font-semibold', [
                        Component.text(s.postJobError!),
                      ]),
                    button(
                      classes:
                          'w-full py-4 rounded-2xl font-bold border-0 cursor-pointer ${isDark ? "text-zinc-400 hover:text-zinc-200 bg-transparent" : "text-zinc-550 hover:text-zinc-700 bg-transparent"} transition-colors',
                      events: {
                        'click': (_) => s.setState(() => s.showDepositModal = false),
                      },
                      [Component.text('Cancel')],
                    ),
                  ],
                ]),
              ] else ...[
                // Solana currency sub-toggle (SOL vs USDT)
                div(classes: 'grid grid-cols-2 gap-2', [
                  button(
                    classes:
                        'py-2 rounded-xl border text-xs font-bold transition-all cursor-pointer border-0 outline-none '
                        '${s.selectedSolanaCurrency == 'SOL' ? "bg-[#512da8] text-white" : (isDark ? "bg-zinc-800/40 border-zinc-800 text-zinc-400 hover:bg-zinc-800/60" : "bg-zinc-50 border-zinc-200 text-zinc-600")}',
                    events: {'click': (_) => s.setState(() => s.selectedSolanaCurrency = 'SOL')},
                    [Component.text('◎ SOL')],
                  ),
                  button(
                    classes:
                        'py-2 rounded-xl border text-xs font-bold transition-all cursor-pointer border-0 outline-none '
                        '${s.selectedSolanaCurrency == 'USDT' ? "bg-emerald-600 text-white" : (isDark ? "bg-zinc-800/40 border-zinc-800 text-zinc-400 hover:bg-zinc-800/60" : "bg-zinc-50 border-zinc-200 text-zinc-600")}',
                    events: {'click': (_) => s.setState(() => s.selectedSolanaCurrency = 'USDT')},
                    [Component.text('\$ USDT')],
                  ),
                ]),

                // Solana payment details
                div(classes: 'p-4 rounded-2xl $cardBg space-y-3.5', [
                  if (s.selectedSolanaCurrency == 'SOL') ...[
                    div(classes: 'flex justify-between items-center text-xs', [
                      span(classes: 'text-zinc-500', [Component.text('Exchange Rate')]),
                      span(classes: 'font-semibold flex items-center gap-1', [
                        if (s.isFetchingRate) lIcon('loader-2', cls: 'w-3 h-3 animate-spin text-purple-400'),
                        Component.text('1 SOL = ₱${rate.toStringAsFixed(2)}'),
                      ]),
                    ]),
                    div(
                      classes:
                          'flex justify-between items-center text-xs border-t ${isDark ? "border-zinc-800" : "border-zinc-150"} pt-3',
                      [
                        span(classes: 'text-zinc-500', [Component.text('Required SOL')]),
                        span(classes: 'font-bold text-[#805ad5] text-sm', [
                          Component.text('${amountInSol.toStringAsFixed(5)} SOL'),
                        ]),
                      ],
                    ),
                  ] else ...[
                    div(classes: 'flex justify-between items-center text-xs', [
                      span(classes: 'text-zinc-500', [Component.text('USDT Rate (Stablecoin)')]),
                      span(classes: 'font-semibold', [
                        Component.text('\$1 USDT ≈ ₱${s.usdToPhpRate.toStringAsFixed(2)}'),
                      ]),
                    ]),
                    div(
                      classes:
                          'flex justify-between items-center text-xs border-t ${isDark ? "border-zinc-800" : "border-zinc-150"} pt-3',
                      [
                        span(classes: 'text-zinc-500', [Component.text('Required USDT')]),
                        span(classes: 'font-bold text-emerald-400 text-sm', [
                          Component.text('\$${(amount / s.usdToPhpRate).toStringAsFixed(2)} USDT'),
                        ]),
                      ],
                    ),
                    div(classes: 'mt-1 p-2 rounded-lg bg-emerald-500/10 border border-emerald-500/20', [
                      p(classes: 'text-[10px] text-emerald-400 font-semibold text-center', [
                        Component.text('USDT is a stablecoin — zero volatility risk!'),
                      ]),
                    ]),
                  ],
                  // Phantom Connection status inside card
                  div(classes: 'border-t ${isDark ? "border-zinc-800" : "border-zinc-150"} pt-3 text-xs', [
                    if (s.walletState == WalletState.disconnected)
                      p(classes: 'text-zinc-400 italic text-center', [Component.text('Solana Wallet not connected.')])
                    else if (s.walletState == WalletState.connecting)
                      p(classes: 'text-yellow-500 font-semibold flex items-center justify-center gap-1.5', [
                        lIcon('loader-2', cls: 'w-3.5 h-3.5 animate-spin'),
                        Component.text('Connecting...'),
                      ])
                    else
                      div(classes: 'space-y-2', [
                        div(classes: 'flex justify-between', [
                          span(classes: 'text-zinc-500', [Component.text('Wallet Address')]),
                          span(classes: 'font-mono text-zinc-400', [Component.text(s.walletAddress)]),
                        ]),
                        div(classes: 'flex justify-between', [
                          span(classes: 'text-zinc-500', [Component.text('SOL Balance')]),
                          span(classes: 'font-semibold', [Component.text('${s.walletBalance.toStringAsFixed(4)} SOL')]),
                        ]),
                      ]),
                  ]),
                ]),

                div(classes: 'space-y-3', [
                  if (s.walletState == WalletState.disconnected) ...[
                    button(
                      classes:
                          'w-full py-4 rounded-2xl font-bold text-white bg-[#512da8] hover:bg-[#41208a] transition-all flex items-center justify-center gap-2 border-0 cursor-pointer',
                      events: {'click': (_) => s.handleConnectWallet()},
                      [
                        lIcon('wallet', cls: 'w-5 h-5'),
                        Component.text('Connect Solana Wallet'),
                      ],
                    ),
                  ] else if (s.walletState == WalletState.connected) ...[
                    if (s.selectedSolanaCurrency == 'SOL') ...[
                      if (s.walletBalance < amountInSol) ...[
                        div(
                          classes:
                              'p-3 text-xs rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 font-semibold text-center',
                          [
                            Component.text(
                              'Insufficient SOL Balance (Need: ${amountInSol.toStringAsFixed(4)} SOL, Have: ${s.walletBalance.toStringAsFixed(4)} SOL)',
                            ),
                          ],
                        ),
                      ] else ...[
                        button(
                          classes:
                              'w-full py-4 rounded-2xl font-bold text-white bg-green-500 hover:bg-green-600 transition-colors flex items-center justify-center gap-2 border-0 cursor-pointer',
                          events: {'click': (_) => s.processSolanaPayment(amountInSol)},
                          [
                            if (s.isDepositing) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                            Component.text(s.isDepositing ? 'Confirming transaction...' : 'Pay with SOL'),
                          ],
                        ),
                      ],
                    ] else ...[
                      button(
                        classes:
                            'w-full py-4 rounded-2xl font-bold text-white bg-emerald-600 hover:bg-emerald-700 transition-colors flex items-center justify-center gap-2 border-0 cursor-pointer',
                        events: {'click': (_) => s.processUsdtPayment(amount / s.usdToPhpRate)},
                        [
                          if (s.isDepositing) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                          Component.text(s.isDepositing ? 'Confirming USDT...' : 'Pay with USDT (Stablecoin)'),
                        ],
                      ),
                    ],
                  ],
                  if (s.postJobError != null)
                    p(classes: 'text-xs text-red-400 text-center mt-2 font-semibold', [
                      Component.text(s.postJobError!),
                    ]),
                  button(
                    classes:
                        'w-full py-4 rounded-2xl font-bold border-0 cursor-pointer ${isDark ? "text-zinc-400 hover:text-zinc-200 bg-transparent" : "text-zinc-550 hover:text-zinc-700 bg-transparent"} transition-colors',
                    events: {'click': (_) => s.setState(() => s.showDepositModal = false)},
                    [Component.text('Cancel')],
                  ),
                ]),
              ],
            ]),

            // Footer
            div(classes: 'p-4 bg-zinc-500/5 text-center border-t ${isDark ? "border-zinc-800" : "border-zinc-100"}', [
              p(
                classes:
                    'text-[10px] uppercase tracking-widest font-bold ${isDark ? "text-zinc-650" : "text-zinc-400"}',
                [
                  Component.text(isSolana ? 'Powered by Solana Secure' : 'Powered by Xendit & Tranyx Secure'),
                ],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  Component _infoRow(String label, String value, bool isDark) {
    return div(classes: 'flex justify-between items-center text-xs', [
      span(classes: isDark ? "text-zinc-500" : "text-zinc-400", [Component.text(label)]),
      span(classes: 'font-semibold', [Component.text(value)]),
    ]);
  }
}
