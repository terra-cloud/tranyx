import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';

class TopHeaderComponent extends StatelessComponent {
  final TranyxAppState state;
  const TopHeaderComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final borderCls = isDark ? 'border-zinc-800 bg-zinc-900/60' : 'border-zinc-200 bg-white/80';

    return header(
      classes: 'flex items-center justify-between px-6 py-4 border-b $borderCls backdrop-blur-sm flex-shrink-0',
      [
        // Mobile logo (hidden on desktop where sidebar shows it)
        div(classes: 'flex items-center gap-3 md:hidden', [
          svgLogo(size: 'w-5 h-5'),
          span(classes: 'font-bold text-lg', [Component.text('Tranyx')]),
        ]),

        // Page title on desktop
        div(classes: 'hidden md:flex items-center gap-3', [
          h1(classes: 'text-xl font-bold', [Component.text(_tabLabel(s.activeTab))]),
          span(
            classes: 'px-3 py-1 rounded-md text-xs font-bold ${s.accountType.badgeClasses}',
            [Component.text(s.accountType.label)],
          ),
        ]),

        // Right side actions
        div(classes: 'flex items-center gap-2 ml-auto', [
          // Dark mode toggle
          button(
            classes:
                'p-2.5 rounded-xl transition-colors ${isDark ? "bg-zinc-800 text-zinc-400 hover:text-yellow-400" : "bg-zinc-100 text-zinc-500 hover:text-indigo-600"}',
            events: {'click': (_) => s.setState(() => s.isDark = !s.isDark)},
            attributes: {'title': isDark ? 'Light mode' : 'Dark mode'},
            [lIcon(isDark ? 'sun' : 'moon', cls: 'w-4 h-4')],
          ),

          // Notifications
          button(
            classes:
                'relative p-2.5 rounded-xl transition-colors ${isDark ? "bg-zinc-800 text-zinc-400 hover:text-white" : "bg-zinc-100 text-zinc-500 hover:text-zinc-900"}',
            events: {},
            [
              lIcon('bell', cls: 'w-4 h-4'),
              span([], classes: 'absolute top-1.5 right-1.5 w-2 h-2 rounded-full bg-indigo-500'),
            ],
          ),

          // Avatar
          div(
            classes: 'w-9 h-9 rounded-full overflow-hidden border-2 border-indigo-500/40 cursor-pointer ml-1 flex items-center justify-center ${s.userPhotoUrl == null ? "bg-indigo-600" : ""}',
            events: {'click': (_) => s.switchTab(AppTab.profile)},
            [
              if (s.userPhotoUrl != null)
                img(src: s.userPhotoUrl!, classes: 'w-full h-full object-cover')
              else
                span(classes: 'text-sm font-bold text-white', [
                  Component.text(s.userName.isNotEmpty ? s.userName[0].toUpperCase() : '?'),
                ]),
            ],
          ),
        ]),
      ],
    );
  }

  String _tabLabel(AppTab tab) {
    return switch (tab) {
      AppTab.home => 'Dashboard',
      AppTab.jobs => 'Jobs & Gigs',
      AppTab.transit => 'Transit Hub',
      AppTab.profile => 'My Profile',
    };
  }
}
