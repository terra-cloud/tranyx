import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../services/web_interop.dart';

class PaymentModalComponent extends StatelessComponent {
  final TranyxAppState state;
  const PaymentModalComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final amount = s.depositAmount;
    final req = s.activeP2pDepositRequest;

    // Fallback safe rate
    final rate = s.solToPhpRate > 0 ? s.solToPhpRate : 8500.0;
    final amountInSol = amount / rate;

    final modalBg = isDark ? "bg-zinc-900 border-zinc-800 shadow-2xl" : "bg-white border-zinc-200 shadow-xl";
    final cardBg = isDark ? "bg-zinc-950/40 border-zinc-850" : "bg-zinc-50 border-zinc-150";

    final isP2p = s.selectedDepositRail == 'manual_p2p';
    final isGcash = s.selectedP2pMethod == 'GCash';

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
              p(classes: 'text-xs sm:text-sm ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                Component.text(
                  isP2p
                      ? 'P2P Matching: Agents are notified and send their live QR code upon request.'
                      : 'Deposit funds instantly via Solana Crypto Gateway.',
                ),
              ]),
            ]),

            // Body
            div(classes: 'p-6 space-y-5 max-h-[68vh] overflow-y-auto custom-scrollbar', [
              // Top Rail Selector
              div(classes: 'p-1 rounded-2xl $cardBg grid grid-cols-2 gap-1', [
                button(
                  classes:
                      'py-2 rounded-xl text-xs font-bold transition-all cursor-pointer border-0 outline-none flex items-center justify-center gap-1.5 '
                      '${isP2p ? "bg-indigo-600 text-white shadow" : (isDark ? "text-zinc-400 hover:text-zinc-200" : "text-zinc-600 hover:text-zinc-800")}',
                  events: {'click': (_) => s.setState(() => s.selectedDepositRail = 'manual_p2p')},
                  [
                    lIcon('users', cls: 'w-4 h-4'),
                    Component.text('P2P Agent Rail'),
                  ],
                ),
                button(
                  classes:
                      'py-2 rounded-xl text-xs font-bold transition-all cursor-pointer border-0 outline-none flex items-center justify-center gap-1.5 '
                      '${!isP2p ? "bg-[#512da8] text-white shadow" : (isDark ? "text-zinc-400 hover:text-zinc-200" : "text-zinc-600 hover:text-zinc-800")}',
                  events: {'click': (_) => s.setState(() => s.selectedDepositRail = 'solana')},
                  [
                    lIcon('coins', cls: 'w-4 h-4'),
                    Component.text('Solana (SOL/USDT)'),
                  ],
                ),
              ]),

              if (isP2p) ...[
                // ── P2P SUB-STATE 1: WAITING FOR AGENT TO SEND QR ─────────────────
                if (req != null && req.status == 'WAITING_FOR_AGENT') ...[
                  div(
                    classes:
                        'p-6 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 text-center space-y-4 animate-fadeIn',
                    [
                      div(
                        classes:
                            'w-16 h-16 rounded-full bg-indigo-500/20 text-indigo-400 flex items-center justify-center mx-auto animate-pulse',
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
                            'Your request for ₱${req.amount.toStringAsFixed(2)} via ${req.paymentMethod} has been broadcasted. Once an online agent accepts, their custom QR code will appear here.',
                          ),
                        ]),
                      ]),
                      div(classes: 'flex items-center justify-center gap-2 text-xs text-indigo-400 font-bold', [
                        span(classes: 'w-2 h-2 rounded-full bg-indigo-400 animate-ping', []),
                        Component.text('Awaiting Agent QR dispatch'),
                      ]),

                      // 5-Minute Cancellation Window
                      () {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final createdAt = req.createdAt;
                        final elapsedMs = now - createdAt;
                        final canCancel = elapsedMs >= 5 * 60 * 1000;
                        final remainingSec = canCancel ? 0 : (((5 * 60 * 1000) - elapsedMs) / 1000).ceil();
                        final remainMin = remainingSec ~/ 60;
                        final remainSec = remainingSec % 60;
                        final timeRemainingText = '${remainMin}m ${remainSec.toString().padLeft(2, '0')}s';

                        if (canCancel) {
                          return button(
                            classes:
                                'w-full py-2.5 rounded-xl text-xs font-bold text-rose-400 hover:text-rose-300 bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/30 transition cursor-pointer',
                            events: {'click': (_) => s.handleCancelP2pOrder(req.id)},
                            [Component.text('Cancel Request (5m Timeout Passed)')],
                          );
                        } else {
                          return div(classes: 'flex flex-col items-center gap-1 w-full', [
                            button(
                              classes:
                                  'w-full py-2 rounded-xl text-xs font-semibold text-zinc-500 bg-zinc-800/40 border border-zinc-800 cursor-not-allowed opacity-60',
                              attributes: {'disabled': 'true'},
                              [Component.text('Cancel available in $timeRemainingText')],
                            ),
                            span(classes: 'text-[10px] text-zinc-500 text-center', [
                              Component.text('P2P request can be cancelled if no agent responds within 5 minutes.'),
                            ]),
                          ]);
                        }
                      }(),
                    ],
                  ),
                ]
                // ── P2P SUB-STATE 2: AGENT SENT QR / AWAITING USER PAYMENT ─────────
                else if (req != null && req.status == 'AWAITING_PAYMENT') ...[
                  div(classes: 'space-y-4 animate-fadeIn', [
                    // Agent banner
                    div(
                      classes:
                          'p-3.5 rounded-2xl bg-emerald-500/10 border border-emerald-500/30 flex items-center gap-3',
                      [
                        div(
                          classes:
                              'w-9 h-9 rounded-xl bg-emerald-500/20 text-emerald-400 flex items-center justify-center shrink-0 font-bold text-xs',
                          [
                            lIcon('check-circle', cls: 'w-5 h-5'),
                          ],
                        ),
                        div(classes: 'text-left space-y-0.5', [
                          span(classes: 'text-xs font-bold text-emerald-400 block', [
                            Component.text('Agent ${_cleanDisplayName(req.agentName, fallback: "Desk")} Sent Payment QR'),
                          ]),
                          span(classes: 'text-[11px] text-zinc-400 block', [
                            Component.text('Scan the QR code below or transfer to the mobile number.'),
                          ]),
                        ]),
                      ],
                    ),

                    // QR and Account Details Box
                    div(classes: 'p-4 rounded-2xl $cardBg space-y-3 text-center', [
                      if (req.agentQrUrl != null && req.agentQrUrl!.isNotEmpty)
                        div(classes: 'inline-block p-2 rounded-2xl bg-white shadow-md mx-auto', [
                          img(
                            src: req.agentQrUrl!,
                            classes: 'w-36 h-36 mx-auto rounded-xl object-contain',
                            alt: '${req.paymentMethod} Payment QR',
                          ),
                        ]),

                      div(classes: 'flex justify-between items-center text-xs px-2 pt-1', [
                        span(classes: 'text-zinc-500', [Component.text('Agent Account Name')]),
                        span(classes: 'font-bold text-zinc-200', [
                          Component.text(_cleanDisplayName(req.agentAccountName ?? req.agentName, fallback: 'TRANYX AGENT')),
                        ]),
                      ]),

                      if (req.agentAccountNumber != null && req.agentAccountNumber!.isNotEmpty)
                        div(
                          classes:
                              'flex justify-between items-center p-2.5 rounded-xl bg-indigo-500/10 border border-indigo-500/20 text-xs',
                          [
                            div(classes: 'flex items-center gap-2 text-left', [
                              lIcon('smartphone', cls: 'w-4 h-4 text-indigo-400'),
                              span(classes: 'font-mono font-bold text-indigo-400', [
                                Component.text(req.agentAccountNumber!),
                              ]),
                            ]),
                            button(
                              classes:
                                  'px-2.5 py-1 rounded-lg bg-indigo-500 text-white text-[11px] font-bold cursor-pointer hover:bg-indigo-600 transition border-0',
                              events: {
                                'click': (_) {
                                  web.window.navigator.clipboard.writeText(req.agentAccountNumber!);
                                  s.showAppToast('Copied', 'Agent number copied to clipboard!');
                                }
                              },
                              [Component.text('Copy')],
                            ),
                          ],
                        ),
                    ]),

                    // Payment Reference Input
                    div(classes: 'space-y-1.5 text-left', [
                      label(classes: 'text-xs font-bold text-zinc-400', [
                        Component.text('Payment Reference Number (from ${req.paymentMethod})'),
                      ]),
                      input(
                        type: InputType.text,
                        classes:
                            'w-full px-4 py-3 rounded-2xl text-sm font-semibold border ${isDark ? "bg-zinc-950/60 border-zinc-800 text-white" : "bg-zinc-50 border-zinc-200 text-zinc-800"} focus:outline-none focus:border-indigo-500',
                        attributes: {
                          'placeholder': 'e.g., 10029384812',
                          if (s.p2pReferenceNumber.isNotEmpty) 'defaultValue': s.p2pReferenceNumber,
                        },
                        events: {
                          'input': (e) {
                            final val = getInputValue(e.target);
                            s.setState(() => s.p2pReferenceNumber = val);
                          },
                        },
                      ),
                    ]),

                    // Proof Screenshot Upload
                    div(classes: 'space-y-1.5 text-left', [
                      label(classes: 'text-xs font-bold text-zinc-400', [
                        Component.text('Upload Transfer Screenshot / Receipt'),
                      ]),
                      if (s.p2pProofBytes == null)
                        label(
                          classes:
                              'w-full py-4 px-4 rounded-2xl border-2 border-dashed border-indigo-500/30 flex flex-col items-center justify-center gap-1 cursor-pointer hover:bg-indigo-500/5 transition-colors',
                          [
                            lIcon('upload-cloud', cls: 'w-6 h-6 text-indigo-400'),
                            span(classes: 'text-xs font-bold text-indigo-400', [
                              Component.text('Click to upload payment receipt'),
                            ]),
                            span(classes: 'text-[10px] text-zinc-500', [Component.text('PNG, JPG, or JPEG up to 10MB')]),
                            input(
                              type: InputType.file,
                              classes: 'hidden',
                              attributes: {'accept': 'image/*'},
                              events: {
                                'change': (e) async {
                                  final files = await readFilesFromEvent(e);
                                  if (files.isNotEmpty) {
                                    s.setState(() {
                                      s.p2pProofBytes = files.first.bytes;
                                      s.p2pProofFileName = files.first.name;
                                    });
                                  }
                                }
                              },
                            ),
                          ],
                        )
                      else
                        div(
                          classes:
                              'w-full p-3 rounded-2xl bg-emerald-500/10 border border-emerald-500/30 flex items-center justify-between',
                          [
                            div(classes: 'flex items-center gap-2', [
                              lIcon('check-circle', cls: 'w-4 h-4 text-emerald-400'),
                              span(classes: 'text-xs font-bold text-emerald-400 truncate max-w-[200px]', [
                                Component.text(s.p2pProofFileName ?? 'Receipt Uploaded'),
                              ]),
                            ]),
                            button(
                              classes:
                                  'text-xs text-red-400 hover:text-red-300 font-bold bg-transparent border-0 cursor-pointer',
                              events: {
                                'click': (_) {
                                  s.setState(() {
                                    s.p2pProofBytes = null;
                                    s.p2pProofFileName = null;
                                  });
                                }
                              },
                              [Component.text('Remove')],
                            ),
                          ],
                        ),
                    ]),

                    // Submit Proof Button
                    button(
                      classes:
                          'w-full py-3.5 rounded-2xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-sm shadow-lg shadow-indigo-600/30 cursor-pointer transition border-0 flex items-center justify-center gap-2 disabled:opacity-50',
                      attributes: {if (s.isSubmittingP2p) 'disabled': 'true'},
                      events: {'click': (_) => s.submitPaymentProofForP2pOrder()},
                      [
                        if (s.isSubmittingP2p) lIcon('loader', cls: 'w-4 h-4 animate-spin'),
                        Component.text(s.isSubmittingP2p ? 'Uploading Proof...' : 'Submit Payment Proof'),
                      ],
                    ),

                    // 5-Minute Cancellation option if user wants to abort
                    () {
                      final now = DateTime.now().millisecondsSinceEpoch;
                      final createdAt = req.createdAt;
                      final elapsedMs = now - createdAt;
                      final canCancel = elapsedMs >= 5 * 60 * 1000;
                      final remainingSec = canCancel ? 0 : (((5 * 60 * 1000) - elapsedMs) / 1000).ceil();
                      final remainMin = remainingSec ~/ 60;
                      final remainSec = remainingSec % 60;
                      final timeRemainingText = '${remainMin}m ${remainSec.toString().padLeft(2, '0')}s';

                      if (canCancel) {
                        return button(
                          classes:
                              'w-full py-2.5 rounded-xl text-xs font-bold text-rose-400 hover:text-rose-300 bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/30 transition cursor-pointer',
                          events: {'click': (_) => s.handleCancelP2pOrder(req.id)},
                          [Component.text('Cancel Request (5m Timeout Reached)')],
                        );
                      } else {
                        return div(classes: 'text-center pt-1', [
                          span(classes: 'text-[10px] text-zinc-500', [
                            Component.text('Cancellation unlocks in $timeRemainingText if transfer is not completed.'),
                          ]),
                        ]);
                      }
                    }(),
                  ]),
                ]
                // ── P2P SUB-STATE 3: PENDING VERIFICATION ──────────────────────────
                else if (req != null && req.status == 'PENDING_VERIFICATION') ...[
                  div(
                    classes:
                        'p-6 rounded-2xl bg-amber-500/10 border border-amber-500/30 text-center space-y-4 animate-fadeIn',
                    [
                      div(
                        classes:
                            'w-16 h-16 rounded-full bg-amber-500/20 text-amber-400 flex items-center justify-center mx-auto',
                        [
                          lIcon('clock', cls: 'w-8 h-8 animate-spin'),
                        ],
                      ),
                      div(classes: 'space-y-1', [
                        h3(classes: 'text-base font-bold text-white', [
                          Component.text('Proof Submitted — Verifying Receipt'),
                        ]),
                        p(classes: 'text-xs text-zinc-400 leading-relaxed', [
                          Component.text(
                            'Your payment of ₱${req.amount.toStringAsFixed(2)} (Ref: ${req.referenceNumber}) is currently being confirmed by the agent in the admin panel. Funds will appear instantly.',
                          ),
                        ]),
                      ]),
                      if (req.proofImageUrl.isNotEmpty)
                        div(classes: 'w-24 h-24 mx-auto rounded-xl overflow-hidden border border-zinc-700 bg-black/40', [
                          img(src: req.proofImageUrl, classes: 'w-full h-full object-cover', alt: 'Receipt'),
                        ]),

                      div(classes: 'space-y-2', [
                        button(
                          classes:
                              'w-full py-3 rounded-xl bg-zinc-800 hover:bg-zinc-700 text-zinc-200 text-xs font-bold cursor-pointer border border-zinc-700',
                          events: {'click': (_) => s.setState(() => s.showDepositModal = false)},
                          [Component.text('Close & Check Balance Later')],
                        ),

                        // If uncredited after 5 minutes
                        () {
                          final now = DateTime.now().millisecondsSinceEpoch;
                          final createdAt = req.proofSubmittedAt ?? req.createdAt;
                          final elapsedMs = now - createdAt;
                          final canCancel = elapsedMs >= 5 * 60 * 1000;

                          if (canCancel) {
                            return button(
                              classes:
                                  'w-full py-2.5 rounded-xl text-xs font-bold text-rose-400 hover:text-rose-300 bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/30 transition cursor-pointer',
                              events: {'click': (_) => s.handleCancelP2pOrder(req.id)},
                              [Component.text('Cancel Request & Revoke Proof')],
                            );
                          }
                          return div([]);
                        }(),
                      ]),
                    ],
                  ),
                ]
                // ── P2P SUB-STATE 4: APPROVED ──────────────────────────────────────
                else if (req != null && req.status == 'APPROVED') ...[
                  div(
                    classes:
                        'p-6 rounded-2xl bg-emerald-500/10 border border-emerald-500/30 text-center space-y-4 animate-fadeIn',
                    [
                      div(
                        classes:
                            'w-16 h-16 rounded-full bg-emerald-500/20 text-emerald-400 flex items-center justify-center mx-auto',
                        [
                          lIcon('check', cls: 'w-8 h-8'),
                        ],
                      ),
                      h3(classes: 'text-lg font-bold text-white', [Component.text('Deposit Credited!')]),
                      p(classes: 'text-xs text-zinc-400', [
                        Component.text(
                          '₱${req.amount.toStringAsFixed(2)} has been successfully verified and added to your Tyxbit balance.',
                        ),
                      ]),
                      button(
                        classes:
                            'w-full py-3 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-bold cursor-pointer border-0',
                        events: {
                          'click': (_) {
                            s.setState(() {
                              s.activeP2pDepositId = null;
                              s.activeP2pDepositRequest = null;
                              s.showDepositModal = false;
                            });
                          }
                        },
                        [Component.text('Done / View Balance')],
                      ),
                    ],
                  ),
                ]
                // ── P2P SUB-STATE 5: REJECTED ──────────────────────────────────────
                else if (req != null && req.status == 'REJECTED') ...[
                  div(
                    classes:
                        'p-6 rounded-2xl bg-red-500/10 border border-red-500/30 text-center space-y-4 animate-fadeIn',
                    [
                      div(
                        classes:
                            'w-16 h-16 rounded-full bg-red-500/20 text-red-400 flex items-center justify-center mx-auto',
                        [
                          lIcon('alert-triangle', cls: 'w-8 h-8'),
                        ],
                      ),
                      h3(classes: 'text-base font-bold text-white', [Component.text('Deposit Not Approved')]),
                      p(classes: 'text-xs text-red-300 leading-relaxed', [
                        Component.text('Reason: ${req.rejectionReason ?? "Verification failed"}'),
                      ]),
                      button(
                        classes:
                            'w-full py-3 rounded-xl bg-zinc-800 hover:bg-zinc-700 text-zinc-200 text-xs font-bold cursor-pointer border border-zinc-700',
                        events: {
                          'click': (_) {
                            s.setState(() {
                              s.activeP2pDepositId = null;
                              s.activeP2pDepositRequest = null;
                            });
                          }
                        },
                        [Component.text('Create New Request')],
                      ),
                    ],
                  ),
                ]
                // ── P2P INITIAL FORM: USER REQUESTS TOP-UP ────────────────────────
                else ...[
                  // Method toggle
                  div(classes: 'grid grid-cols-2 gap-2', [
                    button(
                      classes:
                          'py-2.5 rounded-xl border text-xs font-bold transition-all cursor-pointer border-0 outline-none flex items-center justify-center gap-2 '
                          '${isGcash ? "bg-[#007DFE] text-white shadow-md shadow-blue-500/20" : (isDark ? "bg-zinc-800/40 border-zinc-800 text-zinc-400" : "bg-zinc-50 border-zinc-200 text-zinc-600")}',
                      events: {'click': (_) => s.setState(() => s.selectedP2pMethod = 'GCash')},
                      [
                        div(classes: 'w-2.5 h-2.5 rounded-full bg-white', []),
                        Component.text('GCash Direct'),
                      ],
                    ),
                    button(
                      classes:
                          'py-2.5 rounded-xl border text-xs font-bold transition-all cursor-pointer border-0 outline-none flex items-center justify-center gap-2 '
                          '${!isGcash ? "bg-[#00D084] text-white shadow-md shadow-emerald-500/20" : (isDark ? "bg-zinc-800/40 border-zinc-800 text-zinc-400" : "bg-zinc-50 border-zinc-200 text-zinc-600")}',
                      events: {'click': (_) => s.setState(() => s.selectedP2pMethod = 'Maya')},
                      [
                        div(classes: 'w-2.5 h-2.5 rounded-full bg-white', []),
                        Component.text('Maya Direct'),
                      ],
                    ),
                  ]),

                  // Amount input
                  div(classes: 'text-center pt-2', [
                    span(classes: 'text-xs font-medium ${isDark ? "text-zinc-500" : "text-zinc-400"} block mb-1', [
                      Component.text('Deposit Amount (₱)'),
                    ]),
                    div(classes: 'flex items-center justify-center gap-2 border-b-2 border-indigo-500/30 pb-2 mx-8', [
                      input(
                        type: InputType.number,
                        classes:
                            'w-full text-center text-3xl font-black text-indigo-400 bg-transparent border-none focus:outline-none placeholder:text-indigo-400/30',
                        attributes: {
                          'placeholder': '0.00',
                          'min': '100',
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
                        Component.text('Min ₱100 · Max ₱50,000 per request'),
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
                          classes:
                              'px-3 py-1.5 rounded-xl text-xs font-bold border transition-all cursor-pointer '
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

                  // Notice Card
                  div(
                    classes:
                        'p-3.5 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 text-xs text-indigo-300 flex items-start gap-2.5 text-left',
                    [
                      lIcon('info', cls: 'w-4 h-4 shrink-0 text-indigo-400 mt-0.5'),
                      span([
                        Component.text(
                          'When you click request, online agents are notified immediately to dispatch their verified ${s.selectedP2pMethod} QR code.',
                        ),
                      ]),
                    ],
                  ),

                  // Submit Request Button
                  button(
                    classes:
                        'w-full py-3.5 rounded-2xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-sm shadow-lg shadow-indigo-600/30 cursor-pointer transition border-0 flex items-center justify-center gap-2 disabled:opacity-50 active:scale-95',
                    attributes: {if (s.isSubmittingP2p) 'disabled': 'true'},
                    events: {'click': (_) => s.requestP2pTopupOrder()},
                    [
                      if (s.isSubmittingP2p) lIcon('loader', cls: 'w-4 h-4 animate-spin'),
                      Component.text(s.isSubmittingP2p ? 'Notifying Agents...' : 'Request P2P Top-up (Notify Agent)'),
                    ],
                  ),
                ],
              ] else ...[
                // ── SOLANA GATEWAY FLOW ──────────────────────────────────────────
                // Amount input for Solana
                div(classes: 'text-center pt-1', [
                  span(classes: 'text-xs font-medium ${isDark ? "text-zinc-500" : "text-zinc-400"} block mb-1', [
                    Component.text('Deposit Amount (₱)'),
                  ]),
                  div(classes: 'flex items-center justify-center gap-2 border-b-2 border-[#512da8]/40 pb-2 mx-8', [
                    input(
                      type: InputType.number,
                      classes:
                          'w-full text-center text-3xl font-black text-[#9d74ff] bg-transparent border-none focus:outline-none placeholder:text-[#9d74ff]/30',
                      attributes: {
                        'placeholder': '0.00',
                        'min': '100',
                        'step': '1',
                        'id': 'solana-amount-input',
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
                    span(classes: 'text-[10px] text-[#9d74ff]/70 block font-medium', [
                      Component.text('1 Tyxbit = 1 Peso (₱)'),
                    ]),
                  ]),

                  // Quick Select Chips
                  div(classes: 'flex flex-wrap justify-center gap-2 mt-3', [
                    for (final val in const [
                      (500, '₱500'),
                      (1000, '₱1,000'),
                      (2000, '₱2,000'),
                      (5000, '₱5,000'),
                      (10000, '₱10,000')
                    ])
                      button(
                        classes:
                            'px-3 py-1.5 rounded-xl text-xs font-bold border transition-all cursor-pointer '
                            '${amount == val.$1 ? "bg-[#512da8] text-white border-[#512da8] shadow-md shadow-purple-500/20" : (isDark ? "bg-zinc-800/40 border-zinc-850 text-zinc-300 hover:bg-zinc-800" : "bg-white border-zinc-200 text-zinc-650 hover:bg-zinc-50")}',
                        events: {
                          'click': (_) {
                            s.setState(() => s.depositAmount = val.$1.toDouble());
                            final el = web.document.getElementById('solana-amount-input');
                            if (el != null) {
                              setInputValue(el, val.$1.toString());
                            }
                          }
                        },
                        [Component.text(val.$2)],
                      )
                  ]),
                ]),

                // Connected / Selected Wallet Info Card
                () {
                  final activeType = s.selectedWalletType ?? 'phantom';
                  final isInstalled = isSolanaWalletInstalled(activeType);
                  final friendlyName = activeType.substring(0, 1).toUpperCase() + activeType.substring(1);
                  final linkedKey = (s.userProfile?.walletPublicKey != null && s.userProfile!.walletPublicKey!.isNotEmpty)
                      ? s.userProfile!.walletPublicKey!
                      : s.walletAddress;
                  final hasLinkedKey = linkedKey.isNotEmpty;

                  return div(
                    classes: 'p-3.5 rounded-2xl $cardBg border ${isDark ? "border-zinc-800" : "border-zinc-200"} flex items-center justify-between',
                    [
                      div(classes: 'flex items-center gap-3 min-w-0', [
                        div(
                          classes: 'w-9 h-9 rounded-xl bg-purple-500/10 flex items-center justify-center text-purple-400 shrink-0',
                          [lIcon('wallet', cls: 'w-4 h-4')],
                        ),
                        div(classes: 'min-w-0 text-left', [
                          div(classes: 'flex items-center gap-1.5', [
                            span(classes: 'text-xs font-bold ${isDark ? "text-white" : "text-zinc-900"}', [Component.text('$friendlyName Wallet')]),
                            span(
                              classes:
                                  'text-[10px] px-1.5 py-0.2 rounded font-bold ${isInstalled ? "bg-emerald-500/20 text-emerald-400" : "bg-zinc-500/20 text-zinc-400"}',
                              [Component.text(isInstalled ? 'Ready' : 'Not Detected')],
                            ),
                          ]),
                          p(
                            classes: 'text-[11px] font-mono text-zinc-500 truncate max-w-[180px] sm:max-w-[220px]',
                            [Component.text(hasLinkedKey ? linkedKey : 'Connect & Pay via $friendlyName')],
                          ),
                        ]),
                      ]),
                      button(
                        classes:
                            'px-2.5 py-1.5 rounded-xl text-xs font-bold text-purple-400 hover:text-purple-300 hover:bg-purple-500/10 transition border border-purple-500/30 cursor-pointer shrink-0',
                        events: {'click': (_) => s.setState(() => s.showWalletSelectionModal = true)},
                        [Component.text('Change')],
                      ),
                    ],
                  );
                }(),

                // Solana Conversion Display
                div(classes: 'p-4 rounded-2xl $cardBg space-y-2 text-center border border-[#512da8]/20', [
                  div(classes: 'flex items-center justify-between text-xs', [
                    span(classes: 'text-zinc-400 font-medium', [Component.text('Crypto Required:')]),
                    span(classes: 'font-black text-lg text-white font-mono', [
                      Component.text(amount > 0 ? '${amountInSol.toStringAsFixed(4)} SOL' : '0.0000 SOL'),
                    ]),
                  ]),
                  div(classes: 'flex items-center justify-between text-[11px] text-zinc-500 pt-1 border-t border-zinc-800/50', [
                    span([Component.text('Market Rate:')]),
                    span([Component.text('1 SOL ≈ ₱${rate.toStringAsFixed(0)} PHP')]),
                  ]),
                ]),

                // Solana Payment CTA Button
                button(
                  classes:
                      'w-full py-3.5 rounded-2xl bg-[#512da8] hover:bg-[#4527a0] text-white font-bold text-sm shadow-lg shadow-purple-900/30 cursor-pointer transition border-0 flex items-center justify-center gap-2 disabled:opacity-50 active:scale-95',
                  attributes: {if (amount <= 0 || s.isDepositing) 'disabled': 'true'},
                  events: {'click': (_) => s.processSolanaPayment(amountInSol)},
                  [
                    if (s.isDepositing) lIcon('loader', cls: 'w-4 h-4 animate-spin') else lIcon('wallet', cls: 'w-4 h-4'),
                    Component.text(s.isDepositing ? 'Processing Solana Transaction...' : 'Pay with Solana Wallet'),
                  ],
                ),
              ],

              if (s.postJobError != null)
                div(classes: 'p-3 rounded-xl bg-red-500/10 border border-red-500/30 text-xs text-red-400 text-center', [
                  Component.text(s.postJobError!),
                ]),
            ]),

            // Footer
            div(classes: 'p-4 border-t ${isDark ? "border-zinc-800 bg-zinc-950/40" : "border-zinc-100 bg-zinc-50"} text-center', [
              button(
                classes: 'text-xs font-semibold text-zinc-500 hover:text-zinc-300 transition bg-transparent border-0 cursor-pointer',
                events: {'click': (_) => s.setState(() => s.showDepositModal = false)},
                [Component.text('Close Window')],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  String _cleanDisplayName(String? raw, {String fallback = 'TRANYX AGENT'}) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    var text = raw.trim();
    if (text.contains('@')) {
      final prefix = text.split('@').first;
      text = prefix
          .replaceAll(RegExp(r'[._\-]'), ' ')
          .split(' ')
          .where((part) => part.isNotEmpty)
          .map((part) => part[0].toUpperCase() + (part.length > 1 ? part.substring(1).toLowerCase() : ''))
          .join(' ');
    }
    return text.isEmpty ? fallback : text;
  }
}
