import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';

class WalletActionModalComponent extends StatelessComponent {
  final TranyxAppState state;
  const WalletActionModalComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final tyxBal = s.userProfile?.tyxBalance ?? 0.0;
    final cardBg = isDark ? 'bg-zinc-900 border-zinc-800 text-white' : 'bg-white border-zinc-200 text-zinc-900 shadow-2xl';
    final tileBg = isDark ? 'bg-zinc-800/60 hover:bg-zinc-800 border-zinc-700/60' : 'bg-zinc-50 hover:bg-zinc-100 border-zinc-200';
    final textMuted = isDark ? 'text-zinc-400' : 'text-zinc-500';

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-md animate-fade-in',
      events: {'click': (_) => s.setState(() => s.showWalletActionMenu = false)},
      [
        div(
          classes: 'w-full max-w-md rounded-3xl border p-6 relative overflow-hidden transition-all duration-300 $cardBg',
          events: {
            'click': (e) {
              e.stopPropagation();
            },
          },
          [
            // Header
            div(classes: 'flex items-center justify-between mb-6 pb-4 border-b ${isDark ? "border-zinc-800" : "border-zinc-100"}', [
              div(classes: 'flex items-center gap-3', [
                div(
                  classes: 'p-3 rounded-2xl bg-indigo-500/10 text-indigo-400',
                  [lIcon('wallet', cls: 'w-6 h-6')],
                ),
                div([
                  h3(classes: 'text-xl font-bold tracking-tight', [Component.text('Wallet Options')]),
                  p(classes: 'text-xs font-semibold text-indigo-400 mt-0.5', [
                    Component.text('Available: ₱ ${tyxBal.toStringAsFixed(2)}'),
                  ]),
                ]),
              ]),
              button(
                classes: 'p-2 rounded-xl text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 hover:bg-zinc-500/10 transition-colors',
                events: {'click': (_) => s.setState(() => s.showWalletActionMenu = false)},
                attributes: {'title': 'Close'},
                [lIcon('x', cls: 'w-5 h-5')],
              ),
            ]),

            // 3 Actions
            div(classes: 'space-y-3 mb-6', [
              // 1. Deposit / Cash In
              button(
                classes: 'w-full p-4 rounded-2xl border transition-all text-left flex items-center gap-4 group cursor-pointer $tileBg',
                events: {
                  'click': (_) => s.setState(() {
                    s.showWalletActionMenu = false;
                    s.showDepositModal = true;
                  }),
                },
                [
                  div(
                    classes: 'p-3 rounded-xl bg-emerald-500/10 text-emerald-400 group-hover:scale-110 transition-transform flex-shrink-0',
                    [lIcon('arrow-down-left', cls: 'w-5 h-5')],
                  ),
                  div(classes: 'flex-1 min-w-0', [
                    h4(classes: 'font-bold text-sm leading-tight flex items-center justify-between', [
                      Component.text('Deposit / Cash In'),
                      lIcon('chevron-right', cls: 'w-4 h-4 opacity-50 group-hover:translate-x-1 transition-transform'),
                    ]),
                    p(classes: 'text-xs $textMuted mt-0.5 truncate', [
                      Component.text('Top-up Tyx via GCash, Crypto, or Bank'),
                    ]),
                  ]),
                ],
              ),

              // 2. Withdraw / Cash Out
              button(
                classes: 'w-full p-4 rounded-2xl border transition-all text-left flex items-center gap-4 group cursor-pointer $tileBg',
                events: {
                  'click': (_) => s.setState(() {
                    s.showWalletActionMenu = false;
                    s.showWithdrawModal = true;
                  }),
                },
                [
                  div(
                    classes: 'p-3 rounded-xl bg-purple-500/10 text-purple-400 group-hover:scale-110 transition-transform flex-shrink-0',
                    [lIcon('arrow-up-right', cls: 'w-5 h-5')],
                  ),
                  div(classes: 'flex-1 min-w-0', [
                    h4(classes: 'font-bold text-sm leading-tight flex items-center justify-between', [
                      Component.text('Withdraw / Cash Out'),
                      lIcon('chevron-right', cls: 'w-4 h-4 opacity-50 group-hover:translate-x-1 transition-transform'),
                    ]),
                    p(classes: 'text-xs $textMuted mt-0.5 truncate', [
                      Component.text('Transfer funds to connected wallet or bank'),
                    ]),
                  ]),
                ],
              ),

              // 3. Show All Transaction History
              button(
                classes: 'w-full p-4 rounded-2xl border transition-all text-left flex items-center gap-4 group cursor-pointer $tileBg',
                events: {
                  'click': (_) => s.setState(() {
                    s.showWalletActionMenu = false;
                    s.activeTab = AppTab.profile;
                    s.profileView = ProfileView.history;
                  }),
                },
                [
                  div(
                    classes: 'p-3 rounded-xl bg-indigo-500/10 text-indigo-400 group-hover:scale-110 transition-transform flex-shrink-0',
                    [lIcon('history', cls: 'w-5 h-5')],
                  ),
                  div(classes: 'flex-1 min-w-0', [
                    h4(classes: 'font-bold text-sm leading-tight flex items-center justify-between', [
                      Component.text('Show All Transaction History'),
                      lIcon('chevron-right', cls: 'w-4 h-4 opacity-50 group-hover:translate-x-1 transition-transform'),
                    ]),
                    p(classes: 'text-xs $textMuted mt-0.5 truncate', [
                      Component.text('View full ledger and payment activity'),
                    ]),
                  ]),
                ],
              ),
            ]),

            // Cancel Button
            button(
              classes:
                  'w-full py-3 rounded-2xl font-semibold text-sm text-center transition-colors '
                  '${isDark ? "text-zinc-400 hover:text-white bg-zinc-800/40 hover:bg-zinc-800" : "text-zinc-500 hover:text-zinc-700 bg-zinc-100 hover:bg-zinc-200/80"}',
              events: {'click': (_) => s.setState(() => s.showWalletActionMenu = false)},
              [Component.text('Cancel')],
            ),
          ],
        ),
      ],
    );
  }
}
