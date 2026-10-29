import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';

class BottomNavComponent extends StatelessComponent {
  final TranyxAppState state;
  const BottomNavComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final bgCls = isDark ? 'bg-zinc-900/90 border-zinc-800' : 'bg-white/90 border-zinc-200';

    final isEmployerRole = s.currentViewMode == AccountType.employer && !s.isGuestBrowse;
    final locked = s.isGuestBrowse;
    final fabLabel = locked ? 'Locked' : (isEmployerRole ? 'Post a gig' : 'Find gigs');
    final fabIcon = locked ? 'plus' : (isEmployerRole ? 'plus' : 'zap');

    // W14 floating bar: Home · Jobs · [role action] · Rentals · Profile. Messages lives in the app bar.
    return nav(
      classes: 'md:hidden fixed bottom-3 left-3 right-3 z-40 pb-safe',
      [
        div(
          classes:
              'relative flex items-center justify-around px-2 py-1.5 rounded-[28px] border backdrop-blur-sm shadow-lg $bgCls',
          [
            _navItem(AppTab.home, 'home', 'Home', s, isDark),
            _navItem(AppTab.jobs, 'briefcase', 'Jobs', s, isDark),
            div(classes: 'w-20 shrink-0', []), // slot for the raised role button
            _navItem(AppTab.transit, 'key', 'Rentals', s, isDark),
            _navItem(AppTab.profile, 'user', 'Profile', s, isDark),
            div(classes: 'absolute left-1/2 -translate-x-1/2 -top-5 flex flex-col items-center', [
              button(
                classes:
                    'size-14 rounded-full border-4 flex items-center justify-center cursor-pointer text-white '
                    '${locked ? (isDark ? "bg-zinc-700 border-zinc-900" : "bg-zinc-400 border-white") : "bg-gradient-to-br from-[#4f46e5] to-[#7c3aed] shadow-[0_8px_16px_rgba(79,70,229,0.35)] ${isDark ? "border-zinc-900" : "border-white"}"}',
                attributes: {'type': 'button', 'title': fabLabel, 'aria-label': fabLabel},
                events: {
                  'click': (_) {
                    if (locked) {
                      s.openGuestGate();
                    } else if (isEmployerRole) {
                      s.setState(() {
                        s.activeTab = AppTab.jobs;
                        s.jobsView = JobsView.create;
                      });
                    } else {
                      s.openJobsBrowse();
                    }
                  },
                },
                [lIcon(fabIcon, cls: 'w-6 h-6')],
              ),
              span(
                classes: 'mt-0.5 text-[10px] font-semibold ${isDark ? "text-zinc-400" : "text-[#52525b]"}',
                [Component.text(fabLabel)],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  Component _navItem(AppTab tab, String icon, String label, TranyxAppState s, bool isDark) {
    final isActive = s.activeTab == tab;
    final activeTxt = 'text-indigo-500';
    final inactiveTxt = isDark ? 'text-zinc-500' : 'text-zinc-400';
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
      classes:
          'flex flex-col items-center gap-1 px-3 py-1.5 rounded-2xl transition-colors cursor-pointer ${isActive ? activeTxt : inactiveTxt}',
      events: {'click': (_) => s.switchTab(tab)},
      attributes: {'type': 'button', 'title': label},
      [
        div(classes: 'relative pointer-events-none flex flex-col items-center', [
          lIcon(icon, cls: 'w-5 h-5 pointer-events-none'),
          if (isActive)
            div([], classes: 'absolute -bottom-1.5 left-1/2 -translate-x-1/2 w-1.5 h-1.5 rounded-full bg-indigo-500 pointer-events-none'),
          if (unreadCount > 0)
            div(
              [Component.text('$unreadCount')],
              classes:
                  'absolute -top-2 -right-2 flex items-center justify-center min-w-[16px] h-4 px-1 rounded-full bg-red-500 text-white text-[8px] font-black border border-white dark:border-zinc-950 animate-pulse pointer-events-none',
            )
          else if (showBadge)
            div([], classes: 'absolute -top-1 -right-1 w-2 h-2 rounded-full bg-red-500 border border-white dark:border-zinc-955 animate-pulse pointer-events-none'),
        ]),
        span(classes: 'text-[10px] font-semibold pointer-events-none', [Component.text(label)]),
      ],
    );
  }
}
