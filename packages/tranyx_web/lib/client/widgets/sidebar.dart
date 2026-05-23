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

  Component _navItem(AppTab tab, String iconName, String label, TranyxAppState s) {
    final isActive = s.activeTab == tab;
    final activeCls = s.isDark
        ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-500/20'
        : 'bg-indigo-100 text-indigo-700 font-bold';
    final inactiveCls = s.isDark
        ? 'text-zinc-400 hover:bg-zinc-800 hover:text-zinc-200'
        : 'text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900';
    return button(
      classes: 'w-full flex justify-center p-4 rounded-2xl transition-all ${isActive ? activeCls : inactiveCls}',
      events: {'click': (_) => s.switchTab(tab)},
      attributes: {'title': label},
      [lIcon(iconName, cls: 'w-6 h-6')],
    );
  }
}
