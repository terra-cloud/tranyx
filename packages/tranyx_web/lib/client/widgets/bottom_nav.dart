import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
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

    return nav(
      classes: 'md:hidden fixed bottom-0 left-0 right-0 border-t backdrop-blur-sm pb-safe z-40 $bgCls',
      [
        div(classes: 'flex items-center justify-around px-2 py-2', [
          _navItem(AppTab.home, 'home', 'Home', s, isDark),
          _navItem(AppTab.jobs, 'briefcase', 'Jobs', s, isDark),
          _navItem(AppTab.transit, 'key', 'Rentals', s, isDark),
          _navItem(AppTab.profile, 'user', 'Profile', s, isDark),
        ]),
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
    }

    return button(
      classes:
          'flex flex-col items-center gap-1 px-4 py-2 rounded-2xl transition-colors ${isActive ? activeTxt : inactiveTxt}',
      events: {'click': (_) => s.switchTab(tab)},
      [
        div(classes: 'relative', [
          lIcon(icon, cls: 'w-5 h-5'),
          if (isActive)
            div([], classes: 'absolute -bottom-1.5 left-1/2 -translate-x-1/2 w-1.5 h-1.5 rounded-full bg-indigo-500'),
          if (unreadCount > 0)
            div(
              [Component.text('$unreadCount')],
              classes:
                  'absolute -top-2 -right-2 flex items-center justify-center min-w-[16px] h-4 px-1 rounded-full bg-red-500 text-white text-[8px] font-black border border-white dark:border-zinc-950 animate-pulse',
            )
          else if (showBadge)
            div([], classes: 'absolute -top-1 -right-1 w-2 h-2 rounded-full bg-red-500 border border-white dark:border-zinc-955 animate-pulse'),
        ]),
        span(classes: 'text-[10px] font-semibold', [Component.text(label)]),
      ],
    );
  }
}
