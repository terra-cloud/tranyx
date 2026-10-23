import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../../state/app_state.dart';
import '../../components/ui_helpers.dart';
import '../tranyx_app.dart';

class SidebarComponent extends StatelessComponent {
  final TranyxAppState state;
  const SidebarComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    if (s.isGuestBrowse) return _buildGuestSidebar(s);
    final isDark = s.isDark;
    final borderCls = isDark ? 'bg-zinc-900/50 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    return nav(
      classes: 'hidden md:flex flex-col w-24 border-r py-6 items-center transition-colors duration-500 $borderCls',
      [
        // Logo
        div(classes: 'mb-10', [svgLogo()]),

        // Nav items
        div(classes: 'flex-1 space-y-4 w-full px-4', [
          _navItem(AppTab.home, 'home', 'Dashboard', s),
          _navItem(AppTab.jobs, 'briefcase', 'Jobs', s),
          _navItem(AppTab.transit, 'key', 'Rentals', s),
          _navItem(AppTab.messages, 'message-circle', 'Messages', s),
          _navItem(AppTab.profile, 'user', 'Profile', s),
        ]),

        // Logout
        div(classes: 'mt-auto px-4 w-full', [
          button(
            classes:
                'w-full flex justify-center p-4 rounded-2xl hover:bg-red-500/10 hover:text-red-500 transition-colors ${isDark ? 'text-zinc-500' : 'text-zinc-400'}',
            events: {'click': (_) => s.handleLogout()},
            attributes: {'title': 'Log Out'},
            [lIcon('log-out', cls: 'w-6 h-6')],
          ),
        ]),
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
              classes: 'mt-2 w-full text-sm font-semibold text-[#4f46e5] bg-transparent border-0 cursor-pointer hover:underline',
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
          img(src: '/images/w05/295b0.svg', classes: 'size-3.5 ${isDark ? "opacity-70 invert" : ""}', attributes: {'alt': ''}),
      ],
    );
  }

  Component _navItem(AppTab tab, String iconName, String label, TranyxAppState s) {
    final isActive = s.activeTab == tab;
    final activeCls = s.isDark
        ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-500/20'
        : 'bg-indigo-100 text-indigo-700 font-bold';
    final inactiveCls = s.isDark
        ? 'text-zinc-400 hover:bg-zinc-800 hover:text-zinc-200'
        : 'text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900';
    final hasUnreadChats = (tab == AppTab.jobs && s.hasUnreadJobChats) || (tab == AppTab.transit && s.hasUnreadRentalChats);
    final showBadge = (tab == AppTab.jobs && s.jobsHasUpdates) || (tab == AppTab.transit && s.transitHasUpdates) || hasUnreadChats;

    int unreadCount = 0;
    if (tab == AppTab.jobs) {
      unreadCount = s.unreadJobChatsCount;
    } else if (tab == AppTab.transit) {
      unreadCount = s.unreadRentalChatsCount;
    } else if (tab == AppTab.messages) {
      unreadCount = s.unreadJobChatsCount + s.unreadRentalChatsCount;
    }

    return button(
      classes: 'w-full flex justify-center p-4 rounded-2xl transition-all cursor-pointer ${isActive ? activeCls : inactiveCls}',
      events: {'click': (_) => s.switchTab(tab)},
      attributes: {'title': label, 'type': 'button'},
      [
        div(classes: 'relative pointer-events-none flex items-center justify-center', [
          lIcon(iconName, cls: 'w-6 h-6 pointer-events-none'),
          if (unreadCount > 0)
            div(
              [Component.text('$unreadCount')],
              classes:
                  'absolute -top-2 -right-2 flex items-center justify-center min-w-[16px] h-4 px-1.5 rounded-full bg-red-500 text-white text-[8px] font-black border border-white dark:border-zinc-900 animate-pulse pointer-events-none',
            )
          else if (showBadge)
            div([], classes: 'absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full bg-red-500 border border-white dark:border-zinc-900 animate-pulse pointer-events-none'),
        ]),
      ],
    );
  }
}
