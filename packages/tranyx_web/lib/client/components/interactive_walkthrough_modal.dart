import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import 'package:shared/shared.dart';
import 'package:tranyx_web/services/web_interop.dart';
import '../tranyx_app.dart';
import 'user_badge_component.dart';

class InteractiveWalkthroughModal extends StatefulComponent {
  final TranyxAppState state;
  final VoidCallback? onDismiss;

  const InteractiveWalkthroughModal({
    required this.state,
    this.onDismiss,
    super.key,
  });

  @override
  State<InteractiveWalkthroughModal> createState() => _InteractiveWalkthroughModalState();
}

class _InteractiveWalkthroughModalState extends State<InteractiveWalkthroughModal> {
  int _currentStep = 0;

  void _complete() {
    try {
      final uid = component.state.userProfile?.uid ?? SessionStorage.uid ?? 'default';
      web.window.localStorage.setItem('has_seen_onboarding_$uid', 'true');
    } catch (_) {}
    if (component.onDismiss != null) {
      component.onDismiss!();
    } else {
      component.state.closeWalkthroughModal();
    }
  }

  void _next() {
    if (_currentStep < 3) {
      setState(() => _currentStep++);
    } else {
      _complete();
    }
  }

  void _prev() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  @override
  Component build(BuildContext context) {
    final widthCls = _currentStep == 0
        ? 'w-1/4'
        : _currentStep == 1
            ? 'w-2/4'
            : _currentStep == 2
                ? 'w-3/4'
                : 'w-full';

    return div(
      classes:
          'fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/65 backdrop-blur-md animate-fadeIn select-none',
      [
        div(
          classes:
              'relative w-full max-w-lg bg-zinc-900 border border-zinc-800 rounded-3xl shadow-xl overflow-hidden text-white flex flex-col',
          [
            // Header with comfortable breathing room (no decorative icons or images)
            div(
              classes:
                  'px-7 py-5 border-b border-zinc-800/80 bg-zinc-900/90 flex items-center justify-between',
              [
                div(classes: 'flex items-center gap-2.5', [
                  span(
                    classes:
                        'text-[10px] font-bold tracking-wide text-zinc-400 bg-zinc-800 px-2.5 py-1 rounded-full border border-zinc-700/50',
                    [Component.text('Walkthrough')],
                  ),
                  span(classes: 'text-xs text-zinc-400 font-medium', [
                    Component.text('Step ${_currentStep + 1} of 4'),
                  ]),
                ]),
                button(
                  classes:
                      'w-8 h-8 rounded-full bg-zinc-800/60 hover:bg-zinc-700 text-zinc-400 hover:text-zinc-200 flex items-center justify-center transition cursor-pointer border-0',
                  events: {'click': (_) => _complete()},
                  [
                    span(classes: 'lucide lucide-x text-sm', []),
                  ],
                ),
              ],
            ),

            // Step Progress Line
            div(classes: 'w-full bg-zinc-800 h-0.5', [
              div(
                classes:
                    'bg-zinc-300 h-0.5 transition-all duration-300 $widthCls',
                [],
              ),
            ]),

            // Body Content with spacious layout
            div(
              classes:
                  'p-7 sm:p-8 flex-1 overflow-y-auto max-h-[60vh] custom-scrollbar space-y-5',
              [
                if (_currentStep == 0) ..._buildStep1Verification(),
                if (_currentStep == 1) ..._buildStep2Rentals(),
                if (_currentStep == 2) ..._buildStep3Jobs(),
                if (_currentStep == 3) ..._buildStep4Wallet(),
              ],
            ),

            // Footer
            div(
              classes:
                  'p-6 border-t border-zinc-800/80 bg-zinc-950/40 flex items-center justify-between',
              [
                // Minimalist Pill Indicators
                div(classes: 'flex items-center gap-1.5', [
                  for (int i = 0; i < 4; i++)
                    div(
                      classes:
                          'h-1.5 rounded-full transition-all duration-200 ${i == _currentStep ? "w-6 bg-zinc-200" : "w-1.5 bg-zinc-700"}',
                      [],
                    ),
                ]),

                // Actions
                div(classes: 'flex items-center gap-2.5', [
                  if (_currentStep > 0)
                    button(
                      classes:
                          'px-4 py-2 text-xs font-semibold text-zinc-400 hover:text-zinc-200 bg-transparent hover:bg-zinc-800 rounded-xl transition cursor-pointer border-0',
                      events: {'click': (_) => _prev()},
                      [Component.text('Back')],
                    ),
                  button(
                    classes:
                        'px-6 py-2.5 text-xs font-bold text-zinc-900 bg-zinc-100 hover:bg-white rounded-xl shadow transition cursor-pointer border-0 active:scale-95',
                    events: {'click': (_) => _next()},
                    [
                      Component.text(_currentStep == 3 ? 'Got It' : 'Next'),
                    ],
                  ),
                ]),
              ],
            ),
          ],
        ),
      ],
    );
  }

  List<Component> _buildStep1Verification() {
    return [
      div(classes: 'space-y-2 mb-2', [
        h4(classes: 'text-xl font-bold tracking-tight text-zinc-100', [
          Component.text('Trust & Verification Badges'),
        ]),
        p(classes: 'text-xs text-zinc-400 leading-relaxed', [
          Component.text('Tranyx strictly identifies counterparties with authenticated tier badges so you always transact with verified profiles.'),
        ]),
      ]),

      div(classes: 'space-y-2 pt-1', [
        div(
          classes:
              'p-3 rounded-2xl bg-zinc-800/50 border border-zinc-700/60 flex items-center justify-between gap-3',
          [
            div(classes: 'space-y-0.5', [
              div(classes: 'flex items-center gap-2', [
                span(classes: 'text-xs font-bold text-zinc-300', [
                  Component.text('Level 1: Basic Gov ID Verified'),
                ]),
                const UserBadgeComponent(level: VerificationLevel.level1Basic, showLabel: false),
              ]),
              p(classes: 'text-[11px] text-zinc-400', [
                Component.text('Government ID validated with facial liveness matching.'),
              ]),
            ]),
          ],
        ),
        div(
          classes:
              'p-3 rounded-2xl bg-zinc-800/50 border border-zinc-700/60 flex items-center justify-between gap-3',
          [
            div(classes: 'space-y-0.5', [
              div(classes: 'flex items-center gap-2', [
                span(classes: 'text-xs font-bold text-zinc-300', [
                  Component.text('Level 2: Merchant & Pro Verified'),
                ]),
                const UserBadgeComponent(level: VerificationLevel.level2Pro, showLabel: false),
              ]),
              p(classes: 'text-[11px] text-zinc-400', [
                Component.text('Registered host, merchant credentials, and verified standing.'),
              ]),
            ]),
          ],
        ),
        div(
          classes:
              'p-3 rounded-2xl bg-zinc-800/30 border border-zinc-800 flex items-center justify-between gap-3 opacity-75',
          [
            div(classes: 'space-y-0.5', [
              div(classes: 'flex items-center gap-2', [
                span(classes: 'text-xs font-semibold text-zinc-400', [
                  Component.text('Unverified: Zero badges shown'),
                ]),
                span(
                  classes: 'text-[10px] font-semibold text-zinc-500 bg-zinc-800 px-1.5 py-0.5 rounded',
                  [Component.text('No Badge')],
                ),
              ]),
              p(classes: 'text-[11px] text-zinc-500', [
                Component.text('Clear notice displayed across rental & job agreements.'),
              ]),
            ]),
          ],
        ),
      ]),
    ];
  }

  List<Component> _buildStep2Rentals() {
    return [
      div(classes: 'space-y-1', [
        h4(classes: 'text-xl font-bold tracking-tight text-zinc-100', [
          Component.text('Rentals & Calendar Availability'),
        ]),
        p(classes: 'text-xs text-zinc-400 leading-relaxed', [
          Component.text('Explore vehicles and properties with persistent calendar availability. Booked dates are locked, and clean start dates automatically optimize rates.'),
        ]),
      ]),

      div(classes: 'grid grid-cols-2 gap-2 pt-1', [
        div(classes: 'p-3 rounded-2xl bg-zinc-800/50 border border-zinc-700/60 flex flex-col gap-1', [
          div(classes: 'flex items-center gap-1.5 text-zinc-300', [
            span(classes: 'lucide lucide-check-circle text-xs', []),
            span(classes: 'text-xs font-bold', [Component.text('Availability Lock')]),
          ]),
          p(classes: 'text-[11px] text-zinc-400', [
            Component.text('Persistent date checks prevent overlaps.'),
          ]),
        ]),
        div(classes: 'p-3 rounded-2xl bg-zinc-800/50 border border-zinc-700/60 flex flex-col gap-1', [
          div(classes: 'flex items-center gap-1.5 text-zinc-300', [
            span(classes: 'lucide lucide-sparkles text-xs', []),
            span(classes: 'text-xs font-bold', [Component.text('Smart Rate Cap')]),
          ]),
          p(classes: 'text-[11px] text-zinc-400', [
            Component.text('Applies weekly caps on 7-day bookings.'),
          ]),
        ]),
      ]),

      div(classes: 'p-2.5 rounded-xl bg-zinc-800/30 border border-zinc-800 flex items-center gap-2 text-xs text-zinc-400', [
        span(classes: 'lucide lucide-file-text text-zinc-400 text-sm shrink-0', []),
        span([
          Component.text('Full LTO CR/OR and insurance details embedded directly into agreements.'),
        ]),
      ]),
    ];
  }

  List<Component> _buildStep3Jobs() {
    return [
      div(classes: 'space-y-1', [
        h4(classes: 'text-xl font-bold tracking-tight text-zinc-100', [
          Component.text('Jobs & Live Execution Tracking'),
        ]),
        p(classes: 'text-xs text-zinc-400 leading-relaxed', [
          Component.text('Post gigs or apply with live filtering. Bidding is open to all Nyxians, and real-time live execution updates strictly activate once hired.'),
        ]),
      ]),

      div(classes: 'grid grid-cols-2 gap-2 pt-1', [
        div(classes: 'p-3 rounded-2xl bg-zinc-800/50 border border-zinc-700/60 flex flex-col gap-1', [
          div(classes: 'flex items-center gap-1.5 text-zinc-300', [
            span(classes: 'lucide lucide-shield text-xs', []),
            span(classes: 'text-xs font-bold', [Component.text('Escrow Protection')]),
          ]),
          p(classes: 'text-[11px] text-zinc-400', [
            Component.text('Funds secured safely before gig execution.'),
          ]),
        ]),
        div(classes: 'p-3 rounded-2xl bg-zinc-800/50 border border-zinc-700/60 flex flex-col gap-1', [
          div(classes: 'flex items-center gap-1.5 text-zinc-300', [
            span(classes: 'lucide lucide-qr-code text-xs', []),
            span(classes: 'text-xs font-bold', [Component.text('QR Release')]),
          ]),
          p(classes: 'text-[11px] text-zinc-400', [
            Component.text('Instant payout release upon completion code scan.'),
          ]),
        ]),
      ]),

      div(classes: 'p-2.5 rounded-xl bg-zinc-800/30 border border-zinc-800 flex items-center gap-2 text-xs text-zinc-400', [
        span(classes: 'lucide lucide-sliders text-zinc-400 text-sm shrink-0', []),
        span([
          Component.text('Summary strip displays active category, radius distance, and remote status.'),
        ]),
      ]),
    ];
  }

  List<Component> _buildStep4Wallet() {
    return [
      div(classes: 'space-y-1', [
        h4(classes: 'text-xl font-bold tracking-tight text-zinc-100', [
          Component.text('MWA Web3 Wallet & Fiat Ledger'),
        ]),
        p(classes: 'text-xs text-zinc-400 leading-relaxed', [
          Component.text('Connect your Solana wallet via Mobile Wallet Adapter to sign smart contract transactions and view unified GCash & token ledgers.'),
        ]),
      ]),

      div(classes: 'grid grid-cols-2 gap-2 pt-1', [
        div(classes: 'p-3 rounded-2xl bg-zinc-800/50 border border-zinc-700/60 flex flex-col gap-1', [
          div(classes: 'flex items-center gap-1.5 text-zinc-300', [
            span(classes: 'lucide lucide-smartphone text-xs', []),
            span(classes: 'text-xs font-bold', [Component.text('GCash & Maya')]),
          ]),
          p(classes: 'text-[11px] text-zinc-400', [
            Component.text('Manual P2P top-up with QR code receipts.'),
          ]),
        ]),
        div(classes: 'p-3 rounded-2xl bg-zinc-800/50 border border-zinc-700/60 flex flex-col gap-1', [
          div(classes: 'flex items-center gap-1.5 text-zinc-300', [
            span(classes: 'lucide lucide-coins text-xs', []),
            span(classes: 'text-xs font-bold', [Component.text('Solana (SOL & USDT)')]),
          ]),
          p(classes: 'text-[11px] text-zinc-400', [
            Component.text('On-chain instant settlement with zero fees.'),
          ]),
        ]),
      ]),

      div(classes: 'p-2.5 rounded-xl bg-zinc-800/30 border border-zinc-800 flex items-center gap-2 text-xs text-zinc-400', [
        span(classes: 'lucide lucide-check-check text-zinc-400 text-sm shrink-0', []),
        span([
          Component.text('Atomic Firestore transactions protect every deposit with duplicate reference locks.'),
        ]),
      ]),
    ];
  }
}
