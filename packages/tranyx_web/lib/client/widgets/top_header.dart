import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
import '../../services/web_interop.dart';
class TopHeaderComponent extends StatelessComponent {
  final TranyxAppState state;
  const TopHeaderComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final borderCls = isDark ? 'border-zinc-800 bg-zinc-900/60' : 'border-zinc-200 bg-white/80';

    return header(
      classes: 'relative flex items-center justify-between px-6 py-4 border-b $borderCls backdrop-blur-sm flex-shrink-0 z-50',
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
          div(classes: 'relative', [
            button(
              classes:
                  'relative p-2.5 rounded-xl transition-colors ${isDark ? "bg-zinc-800 text-zinc-400 hover:text-white" : "bg-zinc-100 text-zinc-500 hover:text-zinc-900"}',
              events: {
                'click': (_) => s.setState(() => s.showNotificationsDropdown = !s.showNotificationsDropdown),
              },
              [
                lIcon('bell', cls: 'w-4 h-4'),
                if (s.notifications.isNotEmpty)
                  span([], classes: 'absolute top-1.5 right-1.5 w-2 h-2 rounded-full bg-indigo-500'),
              ],
            ),
            if (s.showNotificationsDropdown)
              _NotificationsDropdown(state: s, isDark: isDark),
          ]),

          // Avatar
          div(
            classes:
                'w-9 h-9 rounded-full overflow-hidden border-2 border-indigo-500/40 cursor-pointer ml-1 flex items-center justify-center ${s.userPhotoUrl == null ? "bg-indigo-600" : ""}',
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
      AppTab.transit => 'Rentals Hub',
      AppTab.profile => 'My Profile',
    };
  }
}

class _NotificationsDropdown extends StatelessComponent {
  final TranyxAppState state;
  final bool isDark;
  const _NotificationsDropdown({required this.state, required this.isDark});

  @override
  Component build(BuildContext context) {
    final s = state;
    final notifications = s.notifications;

    return div(
      classes:
          'absolute right-0 top-full mt-2 w-80 max-h-96 overflow-y-auto rounded-2xl shadow-xl border z-[100] animate-fade-down ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200"}',
      [
        div(classes: 'p-4 border-b ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center justify-between sticky top-0 ${isDark ? "bg-zinc-900/90" : "bg-white/90"} backdrop-blur-md', [
          h3(classes: 'font-bold ${isDark ? "text-white" : "text-zinc-900"}', [Component.text('Notifications')]),
          button(
            classes: 'text-xs font-semibold text-indigo-500 hover:text-indigo-400',
            events: {
              'click': (_) {
                for (final n in notifications) {
                  final id = n['id'] as String?;
                  if (id != null) {
                    markNotificationReadJs(id);
                  }
                }
                s.setState(() {
                  s.notifications.clear();
                  s.showNotificationsDropdown = false;
                });
              },
            },
            [Component.text('Clear All')],
          ),
        ]),
        if (notifications.isEmpty)
          div(classes: 'p-8 text-center', [
            lIcon('bell-off', cls: 'w-8 h-8 mx-auto mb-3 opacity-20 ${isDark ? "text-white" : "text-zinc-900"}'),
            p(classes: 'text-sm font-medium ${isDark ? "text-zinc-500" : "text-zinc-400"}', [Component.text('No new notifications')]),
          ])
        else
          div(classes: 'divide-y ${isDark ? "divide-zinc-800" : "divide-zinc-100"}', [
            for (final n in notifications)
              div(
                classes: 'p-4 hover:${isDark ? "bg-zinc-800/50" : "bg-zinc-50"} transition-colors cursor-pointer',
                events: {
                  'click': (_) {
                    final id = n['id'] as String?;
                    if (id != null) {
                      markNotificationReadJs(id);
                    }
                    // Navigate to jobs tab if it's job related
                    s.switchTab(AppTab.jobs);
                    s.setState(() => s.showNotificationsDropdown = false);
                  },
                },
                [
                  p(classes: 'text-sm font-bold ${isDark ? "text-zinc-200" : "text-zinc-800"}', [Component.text(n['title'] as String? ?? 'Notification')]),
                  p(classes: 'text-xs mt-1 ${isDark ? "text-zinc-400" : "text-zinc-500"}', [Component.text(n['message'] as String? ?? '')]),
                  p(classes: 'text-[10px] mt-2 font-medium opacity-50', [
                    Component.text(DateTime.fromMillisecondsSinceEpoch(n['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch).toString().substring(0, 16)),
                  ]),
                ],
              ),
          ]),
      ],
    );
  }
}
