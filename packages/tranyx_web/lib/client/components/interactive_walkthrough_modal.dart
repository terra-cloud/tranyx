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
      classes: 'fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-fadeIn',
      [
        div(
          classes: 'relative w-full max-w-2xl bg-zinc-900 border border-zinc-800 rounded-3xl shadow-2xl overflow-hidden text-white flex flex-col',
          [
            // Top banner with gradient & progress
            div(
              classes: 'p-6 pb-4 border-b border-zinc-800/80 bg-gradient-to-r from-purple-950/40 via-zinc-900 to-cyan-950/40 flex items-center justify-between',
              [
                div(classes: 'flex items-center gap-3', [
                  div(
                    classes: 'w-10 h-10 rounded-2xl bg-purple-500/20 border border-purple-500/30 flex items-center justify-center text-purple-400 font-bold',
                    [
                      span(classes: 'lucide lucide-sparkles text-xl', []),
                    ],
                  ),
                  div([
                    h3(classes: 'text-lg font-bold text-zinc-100', [
                      Component.text('Tranyx Platform Tour'),
                    ]),
                    p(classes: 'text-xs text-purple-400 font-medium', [
                      Component.text('Step ${_currentStep + 1} of 4'),
                    ]),
                  ]),
                ]),
                button(
                  classes: 'p-2 text-zinc-400 hover:text-white rounded-xl hover:bg-zinc-800 transition',
                  events: {'click': (_) => _complete()},
                  [
                    span(classes: 'lucide lucide-x text-lg', []),
                  ],
                ),
              ],
            ),

            // Step Progress Bar
            div(classes: 'w-full bg-zinc-800 h-1', [
              div(
                classes: 'bg-gradient-to-r from-purple-500 to-cyan-400 h-1 transition-all duration-300 $widthCls',
                [],
              ),
            ]),

            // Body Content based on _currentStep
            div(classes: 'p-6 md:p-8 flex-1 overflow-y-auto max-h-[60vh]', [
              if (_currentStep == 0) ..._buildStep1Verification(),
              if (_currentStep == 1) ..._buildStep2Rentals(),
              if (_currentStep == 2) ..._buildStep3Jobs(),
              if (_currentStep == 3) ..._buildStep4Wallet(),
            ]),

            // Bottom Navigation Footer
            div(
              classes: 'p-6 pt-4 border-t border-zinc-800 bg-zinc-950/50 flex items-center justify-between',
              [
                // Dots Indicator
                div(classes: 'flex items-center gap-1.5', [
                  for (int i = 0; i < 4; i++)
                    div(
                      classes: 'h-2 rounded-full transition-all duration-200 ${i == _currentStep ? "w-6 bg-purple-500" : "w-2 bg-zinc-700"}',
                      [],
                    ),
                ]),

                // Buttons
                div(classes: 'flex items-center gap-3', [
                  if (_currentStep > 0)
                    button(
                      classes: 'px-4 py-2 text-sm font-medium text-zinc-300 hover:text-white bg-zinc-800 hover:bg-zinc-700 rounded-xl transition',
                      events: {'click': (_) => _prev()},
                      [Component.text('Back')],
                    ),
                  button(
                    classes: 'px-6 py-2.5 text-sm font-bold text-white bg-gradient-to-r from-purple-600 to-indigo-600 hover:from-purple-500 hover:to-indigo-500 rounded-xl shadow-lg shadow-purple-600/30 transition active:scale-95',
                    events: {'click': (_) => _next()},
                    [
                      Component.text(_currentStep == 3 ? 'Got It, Let\'s Go!' : 'Next'),
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
      div(classes: 'flex items-center gap-3 mb-3', [
        div(classes: 'p-2 rounded-xl bg-cyan-500/20 text-cyan-400', [
          span(classes: 'lucide lucide-shield-check text-2xl', []),
        ]),
        div([
          h4(classes: 'text-xl font-bold text-zinc-100', [Component.text('Trust & Verification Badges')]),
          p(classes: 'text-xs text-zinc-400', [Component.text('Know exactly who you are transacting and contracting with')]),
        ]),
      ]),
      p(classes: 'text-sm text-zinc-300 mb-5 leading-relaxed', [
        Component.text('Tranyx strictly identifies counterparties with authenticated tier badges so you never deal with counterfeit or unverified profiles.'),
      ]),
      div(classes: 'grid grid-cols-1 md:grid-cols-3 gap-3 mb-4', [
        div(classes: 'p-4 rounded-2xl bg-zinc-800/60 border border-zinc-700/60 flex flex-col gap-2', [
          div(classes: 'flex items-center justify-between', [
            span(classes: 'text-xs font-bold text-zinc-400 uppercase tracking-wider', [Component.text('Level 1')]),
            const UserBadgeComponent(level: VerificationLevel.level1Basic, showLabel: true),
          ]),
          h5(classes: 'font-bold text-sm text-zinc-200', [Component.text('Basic Gov ID')]),
          p(classes: 'text-xs text-zinc-400', [Component.text('Authenticated against Government ID records with facial liveness match.')]),
        ]),
        div(classes: 'p-4 rounded-2xl bg-zinc-800/60 border border-amber-500/30 flex flex-col gap-2', [
          div(classes: 'flex items-center justify-between', [
            span(classes: 'text-xs font-bold text-amber-400 uppercase tracking-wider', [Component.text('Level 2')]),
            const UserBadgeComponent(level: VerificationLevel.level2Pro, showLabel: true),
          ]),
          h5(classes: 'font-bold text-sm text-amber-300', [Component.text('Merchant & Pro')]),
          p(classes: 'text-xs text-zinc-400', [Component.text('LTO/DTI registered hosts, verified merchant records, and top-tier standing.')]),
        ]),
        div(classes: 'p-4 rounded-2xl bg-zinc-800/60 border border-zinc-700/40 opacity-75 flex flex-col gap-2', [
          div(classes: 'flex items-center justify-between', [
            span(classes: 'text-xs font-bold text-zinc-500 uppercase tracking-wider', [Component.text('Unverified')]),
            span(classes: 'text-[10px] font-bold text-zinc-400 bg-zinc-700/60 px-2 py-0.5 rounded-full', [Component.text('No Badge')]),
          ]),
          h5(classes: 'font-bold text-sm text-zinc-400', [Component.text('Pending KYC')]),
          p(classes: 'text-xs text-zinc-500', [Component.text('Zero badges rendered. Clear notice on rental & job contracts.')]),
        ]),
      ]),
    ];
  }

  List<Component> _buildStep2Rentals() {
    return [
      div(classes: 'flex items-center gap-3 mb-3', [
        div(classes: 'p-2 rounded-xl bg-purple-500/20 text-purple-400', [
          span(classes: 'lucide lucide-car text-2xl', []),
        ]),
        div([
          h4(classes: 'text-xl font-bold text-zinc-100', [Component.text('Rentals & Calendar Availability')]),
          p(classes: 'text-xs text-zinc-400', [Component.text('Book vehicles and properties with persistent dates and smart rates')]),
        ]),
      ]),
      p(classes: 'text-sm text-zinc-300 mb-5 leading-relaxed', [
        Component.text('Choose clean start dates with persistent calendar locking. Booked dates are automatically blocked, and Smart Rate Engine optimizes package rates.'),
      ]),
      div(classes: 'p-4 rounded-2xl bg-zinc-800/50 border border-zinc-700/60 space-y-3 mb-3', [
        div(classes: 'flex items-center gap-3', [
          span(classes: 'lucide lucide-calendar-check text-purple-400 text-lg', []),
          div([
            span(classes: 'text-sm font-bold text-zinc-200', [Component.text('Persistent Calendar Locking: ')]),
            span(classes: 'text-xs text-zinc-400', [Component.text('Real-time conflict checks prevent double booking.')]),
          ]),
        ]),
        div(classes: 'flex items-center gap-3', [
          span(classes: 'lucide lucide-sparkles text-amber-400 text-lg', []),
          div([
            span(classes: 'text-sm font-bold text-zinc-200', [Component.text('Smart Rate Capping: ')]),
            span(classes: 'text-xs text-zinc-400', [Component.text('Automatically applies cheaper weekly caps when daily totals exceed.')]),
          ]),
        ]),
        div(classes: 'flex items-center gap-3', [
          span(classes: 'lucide lucide-file-text text-cyan-400 text-lg', []),
          div([
            span(classes: 'text-sm font-bold text-zinc-200', [Component.text('LTO & Insurance Compliance: ')]),
            span(classes: 'text-xs text-zinc-400', [Component.text('Full CR/OR and policy references populated in contracts.')]),
          ]),
        ]),
      ]),
    ];
  }

  List<Component> _buildStep3Jobs() {
    return [
      div(classes: 'flex items-center gap-3 mb-3', [
        div(classes: 'p-2 rounded-xl bg-blue-500/20 text-blue-400', [
          span(classes: 'lucide lucide-briefcase text-2xl', []),
        ]),
        div([
          h4(classes: 'text-xl font-bold text-zinc-100', [Component.text('Jobs & Live Execution Tracking')]),
          p(classes: 'text-xs text-zinc-400', [Component.text('Post gigs or apply with live filtering and milestones')]),
        ]),
      ]),
      p(classes: 'text-sm text-zinc-300 mb-5 leading-relaxed', [
        Component.text('Browse gigs with category presets, radius distance, and remote toggles. Bidding is open to all Nyxians, with live execution updates once hired.'),
      ]),
      div(classes: 'p-4 rounded-2xl bg-zinc-800/50 border border-zinc-700/60 space-y-3 mb-3', [
        div(classes: 'flex items-center gap-3', [
          span(classes: 'lucide lucide-sliders text-blue-400 text-lg', []),
          div([
            span(classes: 'text-sm font-bold text-zinc-200', [Component.text('Transparent Filtering: ')]),
            span(classes: 'text-xs text-zinc-400', [Component.text('Active summary strip shows exactly which gigs qualify.')]),
          ]),
        ]),
        div(classes: 'flex items-center gap-3', [
          span(classes: 'lucide lucide-map-pin text-green-400 text-lg', []),
          div([
            span(classes: 'text-sm font-bold text-zinc-200', [Component.text('Remote Work Flexibility: ')]),
            span(classes: 'text-xs text-zinc-400', [Component.text('Remote gigs bypass physical distance checks seamlessly.')]),
          ]),
        ]),
      ]),
    ];
  }

  List<Component> _buildStep4Wallet() {
    return [
      div(classes: 'flex items-center gap-3 mb-3', [
        div(classes: 'p-2 rounded-xl bg-emerald-500/20 text-emerald-400', [
          span(classes: 'lucide lucide-wallet text-2xl', []),
        ]),
        div([
          h4(classes: 'text-xl font-bold text-zinc-100', [Component.text('MWA Web3 Wallet & GCash Ledger')]),
          p(classes: 'text-xs text-zinc-400', [Component.text('Unified Web3 token transactions and GCash / PHP fiat balances')]),
        ]),
      ]),
      p(classes: 'text-sm text-zinc-300 mb-5 leading-relaxed', [
        Component.text('Connect your Solana Phantom or Solflare wallet to sign smart contracts and escrow releases, with automated QR payouts upon completion.'),
      ]),
      div(classes: 'p-4 rounded-2xl bg-zinc-800/50 border border-zinc-700/60 space-y-3 mb-3', [
        div(classes: 'flex items-center gap-3', [
          span(classes: 'lucide lucide-shield text-emerald-400 text-lg', []),
          div([
            span(classes: 'text-sm font-bold text-zinc-200', [Component.text('Smart Escrow Protection: ')]),
            span(classes: 'text-xs text-zinc-400', [Component.text('Funds are locked securely until job completion QR is scanned.')]),
          ]),
        ]),
        div(classes: 'flex items-center gap-3', [
          span(classes: 'lucide lucide-qr-code text-cyan-400 text-lg', []),
          div([
            span(classes: 'text-sm font-bold text-zinc-200', [Component.text('Instant Payout Release: ')]),
            span(classes: 'text-xs text-zinc-400', [Component.text('Instant payouts directly to your connected wallet or GCash.')]),
          ]),
        ]),
      ]),
    ];
  }
}
