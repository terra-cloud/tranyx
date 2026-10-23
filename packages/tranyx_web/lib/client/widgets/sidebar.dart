import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../../state/app_state.dart';
import '../../components/ui_helpers.dart';
import '../tranyx_app.dart';

/// W10/W20 shell sidebar — 248px labeled rail on lg+, 80px icon rail on md–lg.
class SidebarComponent extends StatelessComponent {
  final TranyxAppState state;
  const SidebarComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    if (s.isGuestBrowse) return _buildGuestSidebar(s);
    return _buildAuthSidebar(s);
  }

  Component _buildAuthSidebar(TranyxAppState s) {
    final isDark = s.isDark;
    final bg = isDark ? 'bg-zinc-950 border-zinc-800' : 'bg-white border-[#e4e4e7]';
    final muted = isDark ? 'text-zinc-500' : 'text-[#71717a]';
    final secondary = isDark ? 'text-zinc-400' : 'text-[#52525b]';
    final primary = isDark ? 'text-zinc-50' : 'text-[#18181b]';
    final isNyxian = s.currentViewMode == AccountType.nyxian;
    final tyxBal = s.userProfile?.tyxBalance ?? 0.0;
    final pendingTotal = s.pendingHoldbacks.fold<double>(
      0.0,
      (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0.0),
    );

    return nav(
      classes:
          'hidden md:flex flex-col border-r py-5 px-3 lg:px-4 transition-colors duration-500 font-dm-sans '
          'w-20 lg:w-[248px] $bg',
      [
        // Brand
        div(classes: 'flex items-center gap-2.5 px-2 pb-5', [
          img(
            src: '/images/w05/fef74.png',
            classes: 'h-8 w-10 object-contain shrink-0',
            attributes: {'alt': 'Tranyx'},
          ),
          span(classes: 'hidden lg:inline font-semibold text-xl tracking-tight $primary', [
            Component.text('Tranyx'),
          ]),
        ]),

        // Role action (Find gigs / Post a gig)
        button(
          classes:
              'mb-3 w-full h-[52px] rounded-[14px] font-semibold text-sm text-white border-0 cursor-pointer '
              'flex items-center justify-center lg:justify-start gap-2.5 px-0 lg:px-4 '
              'bg-gradient-to-br from-[#4f46e5] to-[#7c3aed] shadow-[0_8px_10px_rgba(79,70,229,0.25)] '
              'hover:opacity-95 active:scale-[0.99] transition-all',
          attributes: {
            'type': 'button',
            'title': isNyxian ? 'Find gigs' : 'Post a gig',
          },
          events: {
            'click': (_) {
              if (isNyxian) {
                s.openJobsBrowse();
              } else {
                s.setState(() {
                  s.activeTab = AppTab.jobs;
                  s.jobsView = JobsView.create;
                });
              }
            },
          },
          [
            lIcon('zap', cls: 'w-5 h-5 shrink-0'),
            span(classes: 'hidden lg:inline flex-1 text-left', [
              Component.text(isNyxian ? 'Find gigs' : 'Post a gig'),
            ]),
            span(classes: 'hidden lg:inline text-xs font-mono text-white/85', [
              Component.text(isNyxian ? 'N' : 'E'),
            ]),
          ],
        ),

        p(
          classes:
              'hidden lg:block px-3 mb-1 text-[11px] font-semibold uppercase tracking-[0.8px] $muted',
          [Component.text('Menu')],
        ),

        div(classes: 'flex-1 space-y-1 w-full', [
          _authNav(AppTab.home, 'home', 'Dashboard', s),
          _authNav(AppTab.jobs, 'briefcase', 'Jobs', s),
          _authNav(AppTab.transit, 'key', 'Rentals', s),
          _authNav(AppTab.messages, 'message-circle', 'Messages', s),
          _authNav(AppTab.profile, 'user', 'Profile', s),
        ]),

        // Tyxbit mini (desktop labels; compact on rail)
        button(
          classes:
              'mt-auto w-full text-left rounded-2xl p-3 lg:p-4 border cursor-pointer transition-colors '
              '${isDark ? "bg-zinc-900 border-zinc-800 hover:border-indigo-500/40" : "bg-[#fafafa] border-[#e4e4e7] hover:border-indigo-200"}',
          attributes: {'type': 'button', 'title': 'Wallet'},
          events: {
            'click': (_) => s.setState(() => s.showWalletActionMenu = true),
          },
          [
            div(classes: 'flex items-center gap-1.5 justify-center lg:justify-start', [
              lIcon('wallet', cls: 'w-4 h-4 ${isDark ? "text-indigo-300" : "text-[#52525b]"}'),
              span(classes: 'hidden lg:inline text-xs font-medium $secondary', [
                Component.text('Tyxbit balance'),
              ]),
            ]),
            p(
              classes:
                  'm-0 mt-1 text-center lg:text-left text-sm lg:text-[17px] font-semibold $primary tabular-nums',
              [Component.text('₱ ${tyxBal.toStringAsFixed(2)}')],
            ),
            if (pendingTotal > 0)
              p(
                classes:
                    'hidden lg:block m-0 mt-0.5 text-xs font-medium text-[#7c3aed]',
                [Component.text('+ ₱${pendingTotal.toStringAsFixed(2)} Pending')],
              ),
          ],
        ),

        button(
          classes:
              'mt-2 w-full flex items-center justify-center lg:justify-start gap-3 h-11 px-0 lg:px-3 rounded-xl '
              'text-sm $secondary hover:bg-red-500/10 hover:text-red-500 transition-colors border-0 bg-transparent cursor-pointer',
          attributes: {'type': 'button', 'title': 'Log Out'},
          events: {'click': (_) => s.handleLogout()},
          [
            lIcon('log-out', cls: 'w-5 h-5'),
            span(classes: 'hidden lg:inline', [Component.text('Log Out')]),
          ],
        ),

        p(classes: 'hidden lg:block mt-3 px-3 text-xs font-medium $muted', [
          Component.text('Powered by Terra'),
        ]),
      ],
    );
  }

  Component _authNav(AppTab tab, String icon, String label, TranyxAppState s) {
    final isDark = s.isDark;
    final isActive = s.activeTab == tab;
    final active = isDark
        ? 'bg-indigo-500/20 text-indigo-300'
        : 'bg-[#eef2ff] text-[#4f46e5]';
    final inactive = isDark
        ? 'text-zinc-400 hover:bg-zinc-900'
        : 'text-[#52525b] hover:bg-zinc-50';

    int unreadCount = 0;
    if (tab == AppTab.jobs) {
      unreadCount = s.unreadJobChatsCount;
    } else if (tab == AppTab.transit) {
      unreadCount = s.unreadRentalChatsCount;
    } else if (tab == AppTab.messages) {
      unreadCount = s.unreadJobChatsCount + s.unreadRentalChatsCount;
    }
    final hasDot = (tab == AppTab.jobs && s.jobsHasUpdates) ||
        (tab == AppTab.transit && s.transitHasUpdates) ||
        unreadCount > 0;

    return button(
      classes:
          'w-full flex items-center justify-center lg:justify-start gap-3 h-11 px-0 lg:px-3 rounded-xl text-sm '
          'transition-colors cursor-pointer border-0 bg-transparent '
          '${isActive ? "$active font-semibold" : inactive}',
      attributes: {'type': 'button', 'title': label},
      events: {'click': (_) => s.switchTab(tab)},
      [
        div(classes: 'relative shrink-0', [
          lIcon(icon, cls: 'w-5 h-5'),
          if (unreadCount <= 0 && hasDot)
            span(
              classes:
                  'absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-red-500 border border-white dark:border-zinc-950',
              [],
            ),
        ]),
        span(classes: 'hidden lg:inline flex-1 text-left', [Component.text(label)]),
        if (unreadCount > 0)
          span(
            classes:
                'hidden lg:inline min-w-[20px] h-5 px-[7px] rounded-full bg-[#dc2626] text-white text-xs font-medium '
                'flex items-center justify-center',
            [Component.text('$unreadCount')],
          ),
      ],
    );
  }

  Component _buildGuestSidebar(TranyxAppState s) {
    final isDark = s.isDark;
    final bg = isDark ? 'bg-zinc-950 border-zinc-800' : 'bg-white border-[#e4e4e7]';
    final muted = isDark ? 'text-zinc-400' : 'text-[#52525b]';
    return nav(
      classes: 'hidden md:flex flex-col w-[240px] border-r py-6 px-4 transition-colors duration-500 font-dm-sans $bg',
      [
        div(classes: 'flex items-center gap-2 px-2 mb-6', [
          img(src: '/images/w05/fef74.png', classes: 'h-8 w-10 object-contain', attributes: {'alt': 'Tranyx'}),
        ]),
        button(
          classes:
              'mb-6 w-full h-11 rounded-xl font-semibold text-sm border cursor-pointer '
              '${isDark ? "border-indigo-400/40 text-indigo-300 bg-zinc-900 hover:bg-zinc-800" : "border-[#4f46e5]/40 text-[#4f46e5] bg-zinc-50 hover:bg-indigo-50"}',
          attributes: {'type': 'button'},
          events: {'click': (_) => s.promptGuestSignUp()},
          [Component.text('Sign up to post')],
        ),
        div(classes: 'flex-1 space-y-1', [
          _guestNav(AppTab.home, 'home', 'Dashboard', s, locked: false),
          _guestNav(AppTab.jobs, 'briefcase', 'Jobs', s, locked: false),
          _guestNav(AppTab.transit, 'key', 'Rentals', s, locked: false),
          _guestNav(AppTab.messages, 'message-circle', 'Messages', s, locked: true),
          _guestNav(AppTab.profile, 'user', 'Profile', s, locked: true),
        ]),
        div(
          classes:
              'mt-auto rounded-2xl p-4 ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-[#eef2ff] border border-indigo-100"}',
          [
            p(classes: 'm-0 text-sm font-semibold ${isDark ? "text-zinc-50" : "text-[#18181b]"}', [
              Component.text('Join Tranyx to apply, book and get paid'),
            ]),
            button(
              classes:
                  'mt-3 w-full h-10 rounded-xl font-semibold text-sm text-white bg-[#4f46e5] border-0 cursor-pointer hover:opacity-90',
              attributes: {'type': 'button'},
              events: {'click': (_) => s.promptGuestSignUp()},
              [Component.text('Create account')],
            ),
            button(
              classes:
                  'mt-2 w-full text-sm font-semibold text-[#4f46e5] bg-transparent border-0 cursor-pointer hover:underline',
              attributes: {'type': 'button'},
              events: {'click': (_) => s.promptGuestSignIn()},
              [Component.text('Sign In')],
            ),
          ],
        ),
        p(classes: 'mt-4 text-[10px] font-semibold uppercase tracking-wider text-center $muted', [
          Component.text('Powered by Terra'),
        ]),
      ],
    );
  }

  Component _guestNav(AppTab tab, String icon, String label, TranyxAppState s, {required bool locked}) {
    final isDark = s.isDark;
    final isActive = s.activeTab == tab;
    final active = isDark ? 'bg-indigo-500/20 text-indigo-300' : 'bg-[#eef2ff] text-[#4f46e5]';
    final inactive = isDark ? 'text-zinc-400 hover:bg-zinc-900' : 'text-[#52525b] hover:bg-zinc-50';
    return button(
      classes:
          'w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-semibold transition-colors cursor-pointer border-0 bg-transparent ${isActive ? active : inactive}',
      attributes: {'type': 'button'},
      events: {'click': (_) => s.switchTab(tab)},
      [
        lIcon(icon, cls: 'w-5 h-5'),
        span(classes: 'flex-1 text-left', [Component.text(label)]),
        if (locked)
          img(
            src: '/images/w05/295b0.svg',
            classes: 'size-3.5 ${isDark ? "opacity-70 invert" : ""}',
            attributes: {'alt': ''},
          ),
      ],
    );
  }
}
