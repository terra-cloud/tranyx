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
  static const int _totalSteps = 5;

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
    if (_currentStep < _totalSteps - 1) {
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
    final widthPercent = ((_currentStep + 1) / _totalSteps * 100).toStringAsFixed(0);

    return div(
      classes:
          'fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/75 backdrop-blur-md animate-fadeIn select-none',
      [
        div(
          classes:
              'relative w-full max-w-xl bg-zinc-900 border border-zinc-800 rounded-3xl shadow-2xl overflow-hidden text-white flex flex-col',
          [
            // Header
            div(
              classes:
                  'px-7 py-4.5 border-b border-zinc-800/80 bg-zinc-900/90 flex items-center justify-between',
              [
                div(classes: 'flex items-center gap-2.5', [
                  span(
                    classes:
                        'text-[10px] font-bold tracking-wide text-indigo-400 bg-indigo-500/10 px-2.5 py-1 rounded-full border border-indigo-500/20',
                    [Component.text('Walkthrough')],
                  ),
                  span(classes: 'text-xs text-zinc-400 font-medium', [
                    Component.text('Step ${_currentStep + 1} of $_totalSteps'),
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
            div(classes: 'w-full bg-zinc-800 h-1', [
              div(
                classes:
                    'logo-gradient h-1 transition-all duration-300',
                styles: Styles(
                  raw: {'width': '$widthPercent%'},
                ),
                [],
              ),
            ]),

            // Body Content
            div(
              classes:
                  'p-6 sm:p-7 flex-1 overflow-y-auto max-h-[65vh] custom-scrollbar space-y-4',
              [
                if (_currentStep == 0) ..._buildStep1Everyone(),
                if (_currentStep == 1) ..._buildStep2TurnAssets(),
                if (_currentStep == 2) ..._buildStep3Safety(),
                if (_currentStep == 3) ..._buildStep4Workflow(),
                if (_currentStep == 4) ..._buildStep5Rewards(),
              ],
            ),

            // Footer
            div(
              classes:
                  'px-7 py-4.5 border-t border-zinc-800/80 bg-zinc-950/60 flex items-center justify-between',
              [
                // Pill Step Indicators
                div(classes: 'flex items-center gap-1.5', [
                  for (int i = 0; i < _totalSteps; i++)
                    div(
                      classes:
                          'h-1.5 rounded-full transition-all duration-300 cursor-pointer ${i == _currentStep ? "w-6 bg-indigo-500" : "w-1.5 bg-zinc-700 hover:bg-zinc-600"}',
                      events: {'click': (_) => setState(() => _currentStep = i)},
                      [],
                    ),
                ]),

                // Actions
                div(classes: 'flex items-center gap-2.5', [
                  if (_currentStep > 0)
                    button(
                      classes:
                          'px-4 py-2 text-xs font-semibold text-zinc-400 hover:text-zinc-200 bg-transparent hover:bg-zinc-800 rounded-xl transition cursor-pointer border border-zinc-800',
                      events: {'click': (_) => _prev()},
                      [Component.text('Back')],
                    ),
                  button(
                    classes:
                        'px-5 py-2.5 text-xs font-bold text-white ${_currentStep == _totalSteps - 1 ? "logo-gradient shadow-lg shadow-indigo-600/30" : "bg-indigo-600 hover:bg-indigo-500"} rounded-xl transition cursor-pointer border-0 active:scale-95 flex items-center gap-1.5',
                    events: {'click': (_) => _next()},
                    [
                      Component.text(_currentStep == _totalSteps - 1 ? "🚀 Let's Go!" : 'Next →'),
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

  // ── Step 1: Something for Everyone ──────────────────────────────────────────
  List<Component> _buildStep1Everyone() {
    return [
      div(classes: 'space-y-1.5', [
        div(classes: 'flex items-center gap-2', [
          span(classes: 'text-lg', [Component.text('🚀')]),
          h4(classes: 'text-xl font-black tracking-tight text-white', [
            Component.text('Something for Everyone'),
          ]),
        ]),
        p(classes: 'text-xs font-semibold text-indigo-400', [
          Component.text('Your next opportunity starts here.'),
        ]),
        p(classes: 'text-xs text-zinc-300 leading-relaxed pt-1', [
          Component.text(
            'Looking for work? Need a service? Have something to rent? TRANYX brings opportunities together—all in one place.',
          ),
        ]),
      ]),

      div(classes: 'grid grid-cols-1 sm:grid-cols-2 gap-2.5 pt-2', [
        div(
          classes:
              'p-3.5 rounded-2xl bg-zinc-800/60 border border-zinc-700/60 flex items-start gap-3 hover:border-indigo-500/40 transition',
          [
            div(classes: 'w-9 h-9 rounded-xl bg-indigo-500/10 text-indigo-400 flex items-center justify-center flex-shrink-0', [
              span(classes: 'lucide lucide-briefcase text-sm', []),
            ]),
            div(classes: 'space-y-0.5', [
              p(classes: 'text-xs font-bold text-zinc-100', [Component.text('Jobs & Freelance Gigs')]),
              p(classes: 'text-[11px] text-zinc-400', [
                Component.text('Browse open contracts, post gig requirements, or bid on tasks.'),
              ]),
            ]),
          ],
        ),
        div(
          classes:
              'p-3.5 rounded-2xl bg-zinc-800/60 border border-zinc-700/60 flex items-start gap-3 hover:border-indigo-500/40 transition',
          [
            div(classes: 'w-9 h-9 rounded-xl bg-emerald-500/10 text-emerald-400 flex items-center justify-center flex-shrink-0', [
              span(classes: 'lucide lucide-car text-sm', []),
            ]),
            div(classes: 'space-y-0.5', [
              p(classes: 'text-xs font-bold text-zinc-100', [Component.text('Vehicle & Space Rentals')]),
              p(classes: 'text-[11px] text-zinc-400', [
                Component.text('Rent vehicles, equipment, and properties with calendar availability.'),
              ]),
            ]),
          ],
        ),
      ]),

      div(classes: 'p-3 rounded-xl bg-indigo-500/5 border border-indigo-500/20 text-xs text-zinc-300 flex items-center gap-2.5', [
        span(classes: 'lucide lucide-sparkles text-indigo-400 text-sm shrink-0', []),
        p(classes: 'text-[11px] leading-relaxed', [
          Component.text(
            'From jobs and services to rentals and hiring opportunities, discover new possibilities built around what you need and what you can offer.',
          ),
        ]),
      ]),
    ];
  }

  // ── Step 2: Turn What You Have Into Something More ─────────────────────────
  List<Component> _buildStep2TurnAssets() {
    return [
      div(classes: 'space-y-1.5', [
        div(classes: 'flex items-center gap-2', [
          span(classes: 'text-lg', [Component.text('💡')]),
          h4(classes: 'text-xl font-black tracking-tight text-white', [
            Component.text('Turn What You Have Into Something More'),
          ]),
        ]),
        p(classes: 'text-xs font-semibold text-amber-400', [
          Component.text('Skills. Time. Things you own.'),
        ]),
        p(classes: 'text-xs text-zinc-300 leading-relaxed pt-1', [
          Component.text(
            'You have more ways to earn than you think. Turn your skills, time, services, and assets into opportunities.',
          ),
        ]),
      ]),

      div(classes: 'space-y-2 pt-1', [
        div(
          classes: 'p-3 rounded-2xl bg-zinc-800/50 border border-zinc-700/60 flex items-center gap-3',
          [
            div(classes: 'w-8 h-8 rounded-xl bg-amber-500/10 text-amber-400 flex items-center justify-center flex-shrink-0', [
              span(classes: 'lucide lucide-wrench text-xs', []),
            ]),
            div(classes: 'flex-1', [
              p(classes: 'text-xs font-bold text-zinc-200', [Component.text('Find Gigs & Offer Expertise')]),
              p(classes: 'text-[11px] text-zinc-400', [Component.text('Monetize your carpentry, design, plumbing, or courier capabilities.')]),
            ]),
          ],
        ),
        div(
          classes: 'p-3 rounded-2xl bg-zinc-800/50 border border-zinc-700/60 flex items-center gap-3',
          [
            div(classes: 'w-8 h-8 rounded-xl bg-cyan-500/10 text-cyan-400 flex items-center justify-center flex-shrink-0', [
              span(classes: 'lucide lucide-key text-xs', []),
            ]),
            div(classes: 'flex-1', [
              p(classes: 'text-xs font-bold text-zinc-200', [Component.text('Rent Out What You Own')]),
              p(classes: 'text-[11px] text-zinc-400', [Component.text('List motorcycles, cars, commercial spaces, and idle tools safely.')]),
            ]),
          ],
        ),
      ]),

      div(classes: 'p-3 rounded-xl bg-amber-500/10 border border-amber-500/20 flex items-center justify-between text-xs', [
        div(classes: 'flex items-center gap-2 text-amber-300 font-bold', [
          span(classes: 'lucide lucide-trending-up text-sm', []),
          Component.text('Your opportunity could be worth more than you think.'),
        ]),
      ]),
    ];
  }

  // ── Step 3: Safe. Secure. Built for You ─────────────────────────────────────
  List<Component> _buildStep3Safety() {
    return [
      div(classes: 'space-y-1.5', [
        div(classes: 'flex items-center gap-2', [
          span(classes: 'text-lg', [Component.text('🔥')]),
          h4(classes: 'text-xl font-black tracking-tight text-white', [
            Component.text('Safe. Secure. Built for You. 🛡️'),
          ]),
        ]),
        p(classes: 'text-xs font-semibold text-emerald-400', [
          Component.text('Transact with confidence. Your safety matters.'),
        ]),
        p(classes: 'text-xs text-zinc-400 leading-relaxed pt-1', [
          Component.text(
            'TRANYX uses identity verification, trust badges, and security measures to help you know who you\'re dealing with before you transact.',
          ),
        ]),
      ]),

      div(classes: 'space-y-2 pt-1', [
        div(classes: 'text-[11px] font-bold text-zinc-400 uppercase tracking-wider', [
          Component.text('Trust & Verification Badges'),
        ]),
        div(
          classes:
              'p-3 rounded-2xl bg-zinc-800/60 border border-zinc-700/60 flex items-center justify-between gap-3',
          [
            div(classes: 'space-y-0.5 flex-1', [
              div(classes: 'flex items-center gap-2', [
                span(classes: 'text-xs font-bold text-zinc-200', [
                  Component.text('🔵 Level 1: Basic Gov ID Verified'),
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
              'p-3 rounded-2xl bg-zinc-800/60 border border-zinc-700/60 flex items-center justify-between gap-3',
          [
            div(classes: 'space-y-0.5 flex-1', [
              div(classes: 'flex items-center gap-2', [
                span(classes: 'text-xs font-bold text-zinc-200', [
                  Component.text('🟡 Level 2: Merchant & Pro Verified'),
                ]),
                const UserBadgeComponent(level: VerificationLevel.level2Pro, showLabel: false),
              ]),
              p(classes: 'text-[11px] text-zinc-400', [
                Component.text('Registered hosts, merchants, and professionals with verified credentials.'),
              ]),
            ]),
          ],
        ),
        div(
          classes:
              'p-2.5 rounded-2xl bg-zinc-800/30 border border-zinc-800 flex items-center justify-between gap-3 opacity-75',
          [
            div(classes: 'space-y-0.5 flex-1', [
              div(classes: 'flex items-center gap-2', [
                span(classes: 'text-xs font-semibold text-zinc-400', [
                  Component.text('⚪ Unverified'),
                ]),
                span(
                  classes: 'text-[10px] font-semibold text-zinc-500 bg-zinc-800 px-1.5 py-0.5 rounded',
                  [Component.text('No Badge')],
                ),
              ]),
              p(classes: 'text-[11px] text-zinc-500', [
                Component.text('No verification badge shown, so you can make informed decisions before proceeding.'),
              ]),
            ]),
          ],
        ),
      ]),

      div(classes: 'text-center pt-1', [
        p(classes: 'text-xs font-bold text-zinc-400', [
          Component.text('Your trust matters. Your transactions matter.'),
        ]),
      ]),
    ];
  }

  // ── Step 4: Make Opportunities Happen ──────────────────────────────────────
  List<Component> _buildStep4Workflow() {
    return [
      div(classes: 'space-y-1.5', [
        div(classes: 'flex items-center gap-2', [
          span(classes: 'text-lg', [Component.text('✨')]),
          h4(classes: 'text-xl font-black tracking-tight text-white', [
            Component.text('Make Opportunities Happen'),
          ]),
        ]),
        p(classes: 'text-xs font-semibold text-indigo-400', [
          Component.text('From discovery to done.'),
        ]),
        p(classes: 'text-xs text-zinc-300 leading-relaxed pt-1', [
          Component.text(
            'Found an opportunity? Take the next step: Apply for the job. Book the service. Accept the offer. Complete the rental. Get things done—all through TRANYX.',
          ),
        ]),
      ]),

      // Visual workflow concept: Progressing through TRANYX ecosystem
      div(classes: 'p-3.5 rounded-2xl bg-zinc-950/80 border border-zinc-800 space-y-2.5', [
        div(classes: 'flex items-center justify-between text-[11px] font-bold text-zinc-400 px-1', [
          span([Component.text('Opportunity Lifecycle')]),
          span(classes: 'text-emerald-400 flex items-center gap-1', [
            span(classes: 'lucide lucide-shield-check text-xs', []),
            Component.text('Escrow Protected'),
          ]),
        ]),

        div(classes: 'grid grid-cols-4 gap-1.5 text-center', [
          div(classes: 'p-2 rounded-xl bg-zinc-800/80 border border-zinc-700/60 flex flex-col items-center gap-1', [
            span(classes: 'lucide lucide-search text-indigo-400 text-xs', []),
            span(classes: 'text-[10px] font-bold text-zinc-200', [Component.text('1. Found')]),
          ]),
          div(classes: 'p-2 rounded-xl bg-zinc-800/80 border border-zinc-700/60 flex flex-col items-center gap-1', [
            span(classes: 'lucide lucide-message-square text-cyan-400 text-xs', []),
            span(classes: 'text-[10px] font-bold text-zinc-200', [Component.text('2. Connected')]),
          ]),
          div(classes: 'p-2 rounded-xl bg-zinc-800/80 border border-zinc-700/60 flex flex-col items-center gap-1', [
            span(classes: 'lucide lucide-lock text-amber-400 text-xs', []),
            span(classes: 'text-[10px] font-bold text-zinc-200', [Component.text('3. Transact')]),
          ]),
          div(classes: 'p-2 rounded-xl bg-emerald-500/15 border border-emerald-500/30 flex flex-col items-center gap-1', [
            span(classes: 'lucide lucide-check-circle text-emerald-400 text-xs', []),
            span(classes: 'text-[10px] font-black text-emerald-300', [Component.text('4. Done ✓')]),
          ]),
        ]),

        div(classes: 'p-2.5 rounded-xl bg-zinc-900 border border-zinc-800 flex items-center justify-between text-[11px]', [
          div(classes: 'flex items-center gap-2', [
            span(classes: 'w-2 h-2 rounded-full bg-emerald-400 animate-pulse', []),
            span(classes: 'text-zinc-300 font-medium', [Component.text('Live QR Completion & Reputation Score ★')]),
          ]),
          span(classes: 'text-xs font-bold text-indigo-400', [Component.text('+ 5.0 Rating')]),
        ]),
      ]),

      p(classes: 'text-center text-xs font-semibold text-zinc-400 pt-1', [
        Component.text('One connection can become your next opportunity.'),
      ]),
    ];
  }

  // ── Step 5: Get Rewarded Along the Way ──────────────────────────────────────
  List<Component> _buildStep5Rewards() {
    return [
      div(classes: 'space-y-1.5', [
        div(classes: 'flex items-center gap-2', [
          span(classes: 'text-lg', [Component.text('🪙')]),
          h4(classes: 'text-xl font-black tracking-tight text-white', [
            Component.text('Get Rewarded Along the Way'),
          ]),
        ]),
        p(classes: 'text-xs font-semibold text-purple-400', [
          Component.text('Your activity can take you further.'),
        ]),
        p(classes: 'text-xs text-zinc-300 leading-relaxed pt-1', [
          Component.text(
            'Every opportunity is more than just a transaction. As you participate in the TRANYX ecosystem, you can earn Terra Rewards Points.',
          ),
        ]),
      ]),

      // Rewards Flow Diagram
      div(classes: 'p-3.5 rounded-2xl bg-zinc-950/80 border border-zinc-800 space-y-2.5', [
        div(classes: 'flex items-center justify-between text-[11px] font-bold text-zinc-400 px-1', [
          span([Component.text('Earn. Build. Unlock More.')]),
          span(classes: 'text-purple-400 font-bold', [Component.text('⚡ Powered by Solana')]),
        ]),

        div(classes: 'grid grid-cols-2 gap-2 text-xs', [
          div(classes: 'p-2.5 rounded-xl bg-zinc-900 border border-zinc-800 flex items-center gap-2', [
            span(classes: 'text-sm', [Component.text('✨')]),
            div([
              p(classes: 'font-bold text-zinc-200 text-[11px]', [Component.text('Terra Rewards')]),
              p(classes: 'text-[10px] text-zinc-400', [Component.text('Earned on transactions')]),
            ]),
          ]),
          div(classes: 'p-2.5 rounded-xl bg-zinc-900 border border-zinc-800 flex items-center gap-2', [
            span(classes: 'text-sm', [Component.text('🪙')]),
            div([
              p(classes: 'font-bold text-zinc-200 text-[11px]', [Component.text('TYXBIT Tokens')]),
              p(classes: 'text-[10px] text-zinc-400', [Component.text('Utility cryptocurrency')]),
            ]),
          ]),
          div(classes: 'p-2.5 rounded-xl bg-zinc-900 border border-zinc-800 flex items-center gap-2', [
            span(classes: 'text-sm', [Component.text('🔗')]),
            div([
              p(classes: 'font-bold text-zinc-200 text-[11px]', [Component.text('Crypto Wallet')]),
              p(classes: 'text-[10px] text-zinc-400', [Component.text('MWA & Phantom support')]),
            ]),
          ]),
          div(classes: 'p-2.5 rounded-xl bg-zinc-900 border border-zinc-800 flex items-center gap-2', [
            span(classes: 'text-sm', [Component.text('⚡')]),
            div([
              p(classes: 'font-bold text-zinc-200 text-[11px]', [Component.text('Fast & Low Fees')]),
              p(classes: 'text-[10px] text-zinc-400', [Component.text('Sub-second settlement')]),
            ]),
          ]),
        ]),
      ]),

      div(classes: 'p-3 rounded-2xl logo-gradient text-white text-center shadow-lg shadow-indigo-600/20 space-y-0.5', [
        p(classes: 'text-xs font-black tracking-wide uppercase', [
          Component.text('One platform. Endless opportunities.'),
        ]),
        p(classes: 'text-[11px] opacity-90', [
          Component.text('Your opportunities. Your rewards. Your TRANYX.'),
        ]),
      ]),
    ];
  }
}
