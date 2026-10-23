import 'package:jaspr/dom.dart';
import 'package:web/web.dart' as web;
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
    if (s.isGuestBrowse) return _buildGuestHeader(s);
    final isDark = s.isDark;
    final borderCls = isDark ? 'border-zinc-800 bg-zinc-900/60' : 'border-zinc-200 bg-white/80';

    return header(
      classes:
          'relative flex items-center justify-between px-6 py-4 border-b $borderCls backdrop-blur-sm flex-shrink-0 z-50',
      [
        // Mobile logo (hidden on desktop where sidebar shows it)
        div(classes: 'flex items-center gap-3 md:hidden', [
          svgLogo(size: 'w-5 h-5'),
          span(classes: 'font-bold text-lg', [Component.text('Tranyx')]),
        ]),

        // Page title on desktop
        div(classes: 'hidden md:flex items-center gap-3 shrink-0', [
          h1(classes: 'text-xl font-bold m-0', [Component.text(_tabLabel(s.activeTab))]),
          span(
            classes: 'px-3 py-1 rounded-full text-xs font-bold ${s.accountType.badgeClasses}',
            [Component.text(s.accountType.label)],
          ),
        ]),

        // Global search (W10/W20) — filters live Jobs browse
        div(
          classes:
              'hidden lg:flex flex-1 max-w-sm ml-6 h-11 items-center gap-2 px-3 rounded-xl border '
              '${isDark ? "bg-zinc-900 border-zinc-700" : "bg-[#fafafa] border-[#e4e4e7]"}',
          [
            lIcon('search', cls: 'w-4 h-4 ${isDark ? "text-zinc-500" : "text-zinc-400"}'),
            input(
              classes:
                  'bg-transparent border-0 outline-none flex-1 text-sm min-w-0 '
                  '${isDark ? "text-zinc-200 placeholder-zinc-500" : "text-[#18181b] placeholder-[#71717a]"}',
              type: InputType.search,
              attributes: {
                'placeholder': 'Search gigs, vehicles, spaces',
                'value': s.homeSearchQuery,
                'id': 'topbar-search',
                'name': 'topbar-search',
              },
              events: {
                'input': (e) => s.setState(() => s.homeSearchQuery = getInputValue(e.target)),
                'keydown': (e) {
                  final key = (e as web.KeyboardEvent).key;
                  if (key == 'Enter') s.handleHomeSearch(s.homeSearchQuery);
                },
              },
            ),
            span(
              classes:
                  'text-[11px] font-semibold px-1.5 py-0.5 rounded border shrink-0 '
                  '${isDark ? "border-zinc-700 text-zinc-500" : "border-[#e4e4e7] text-[#71717a]"}',
              [Component.text('⌘K')],
            ),
          ],
        ),

        // Right side actions
        div(classes: 'flex items-center gap-2 ml-auto', [
          // Dark mode toggle
          button(
            classes:
                'p-2.5 rounded-xl transition-colors ${isDark ? "bg-zinc-800 text-zinc-400 hover:text-yellow-400" : "bg-zinc-100 text-zinc-500 hover:text-indigo-600"}',
            events: {'click': (_) => s.toggleTheme()},
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
            if (s.showNotificationsDropdown) _NotificationsDropdown(state: s, isDark: isDark),
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


  Component _buildGuestHeader(TranyxAppState s) {
    final isDark = s.isDark;
    final borderCls = isDark ? 'border-zinc-800 bg-zinc-950/80' : 'border-[#e4e4e7] bg-white/90';
    return header(
      classes:
          'relative flex items-center gap-4 px-6 py-3 border-b $borderCls backdrop-blur-sm flex-shrink-0 z-50 font-dm-sans',
      [
        div(classes: 'flex items-center gap-2 shrink-0', [
          h1(classes: 'text-lg font-bold ${isDark ? "text-zinc-50" : "text-[#18181b]"} m-0', [
            Component.text(s.activeTab == AppTab.home ? 'Home' : _tabLabel(s.activeTab)),
          ]),
          span(
            classes:
                'px-2.5 py-0.5 rounded-full text-[11px] font-semibold ${isDark ? "bg-zinc-800 text-zinc-300" : "bg-zinc-100 text-zinc-600"}',
            [Component.text('Guest')],
          ),
        ]),
        div(
          classes:
              'hidden md:flex flex-1 max-w-xl mx-auto h-11 items-center gap-2 px-3 rounded-xl border '
              '${isDark ? "bg-zinc-900 border-zinc-700 text-zinc-400" : "bg-zinc-100 border-zinc-200 text-zinc-500"}',
          [
            img(src: '/images/w05/ec717.svg', classes: 'size-4 ${isDark ? "opacity-70 invert" : ""}', attributes: {'alt': ''}),
            span(classes: 'flex-1 text-sm', [Component.text('Search gigs, vehicles, spaces')]),
            span(
              classes:
                  'text-[10px] font-semibold px-1.5 py-0.5 rounded border ${isDark ? "border-zinc-700 text-zinc-500" : "border-zinc-300 text-zinc-400"}',
              [Component.text('⌘K')],
            ),
          ],
        ),
        div(classes: 'flex items-center gap-2 ml-auto shrink-0', [
          button(
            classes:
                'p-2.5 rounded-xl transition-colors ${isDark ? "bg-zinc-800 text-zinc-400 hover:text-yellow-400" : "bg-zinc-100 text-zinc-500 hover:text-indigo-600"}',
            events: {'click': (_) => s.toggleTheme()},
            attributes: {'title': isDark ? 'Light mode' : 'Dark mode', 'type': 'button'},
            [lIcon(isDark ? 'sun' : 'moon', cls: 'w-4 h-4')],
          ),
          button(
            classes:
                'h-10 px-4 rounded-xl font-semibold text-sm border cursor-pointer '
                '${isDark ? "bg-zinc-900 border-zinc-700 text-zinc-100" : "bg-white border-[#d4d4d8] text-[#18181b]"}',
            attributes: {'type': 'button'},
            events: {'click': (_) => s.promptGuestSignIn()},
            [Component.text('Sign In')],
          ),
          button(
            classes:
                'h-10 px-4 rounded-xl font-semibold text-sm text-white bg-[#4f46e5] border-0 cursor-pointer hover:opacity-90',
            attributes: {'type': 'button'},
            events: {'click': (_) => s.promptGuestSignUp()},
            [Component.text('Create account')],
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
      AppTab.messages => 'Messages & Conversations',
      AppTab.profile => 'My Profile',
    };
  }
}

class _NotificationsDropdown extends StatelessComponent {
  final TranyxAppState state;
  final bool isDark;
  const _NotificationsDropdown({required this.state, required this.isDark});

  Component _buildNotificationItem(Map<String, dynamic> n, TranyxAppState s) {
    final type = n['type'] as String?;
    final chatId = n['chatId']?.toString() ?? '';
    final title = (n['title'] as String? ?? '').toLowerCase();
    final message = (n['message'] as String? ?? '').toLowerCase();

    final isProperty = type == 'property' ||
        chatId.startsWith('property_') ||
        title.contains('property') ||
        title.contains('lease') ||
        title.contains('tenant') ||
        message.contains('property') ||
        message.contains('lease') ||
        message.contains('tenant');

    final isVehicle = !isProperty && (type == 'rental' ||
        chatId.startsWith('rental_') ||
        title.contains('rental') ||
        title.contains('vehicle') ||
        title.contains('booking') ||
        title.contains('contract') ||
        title.contains('garage') ||
        message.contains('rental') ||
        message.contains('vehicle') ||
        message.contains('booking') ||
        message.contains('contract') ||
        message.contains('garage'));

    final isHost = title.contains('received') ||
        message.contains('your vehicle') ||
        message.contains('your property') ||
        message.contains('your listing') ||
        message.contains('your garage') ||
        message.contains('awaiting tenant') ||
        message.contains('awaiting renter') ||
        message.contains('credited to your wallet') ||
        message.contains('for your');

    return div(
      classes: 'p-4 hover:${isDark ? "bg-zinc-800/50" : "bg-zinc-50"} transition-colors cursor-pointer flex gap-3 items-start',
      events: {
        'click': (_) {
          final id = n['id'] as String?;
          if (id != null) {
            markNotificationReadJs(id);
          }

          if (isVehicle) {
            s.activeRentalCategory = RentalCategory.vehicles;
            s.transitMode = isHost ? TransitMode.host : TransitMode.rent;
            s.switchTab(AppTab.transit);
          } else if (isProperty) {
            s.activeRentalCategory = RentalCategory.properties;
            s.transitMode = isHost ? TransitMode.host : TransitMode.rent;
            s.switchTab(AppTab.transit);
          } else {
            s.switchTab(AppTab.jobs);
          }
          s.setState(() => s.showNotificationsDropdown = false);
        },
      },
      [
        // Icon container
        div(
          classes: 'p-2 rounded-xl flex-shrink-0 ${
            isVehicle ? (isDark ? "bg-indigo-950 text-indigo-400" : "bg-indigo-50 text-indigo-600") :
            isProperty ? (isDark ? "bg-emerald-950 text-emerald-400" : "bg-emerald-50 text-emerald-600") :
            (isDark ? "bg-zinc-800 text-zinc-400" : "bg-zinc-100 text-zinc-600")
          }',
          [
            lIcon(
              isVehicle ? 'car' :
              isProperty ? 'home' :
              'briefcase',
              cls: 'w-4 h-4'
            )
          ],
        ),
        // Content
        div(classes: 'flex-1 min-w-0', [
          // Badge & Title Row
          div(classes: 'flex items-center gap-1.5 flex-wrap mb-1', [
            span(
              classes: 'px-1.5 py-0.5 rounded text-[9px] font-bold uppercase tracking-wider ${
                isVehicle ? "bg-indigo-500/10 text-indigo-400 border border-indigo-500/20" :
                isProperty ? "bg-emerald-500/10 text-emerald-400 border border-emerald-500/20" :
                "bg-zinc-500/10 text-zinc-400 border border-zinc-500/20"
              }',
              [
                Component.text(
                  isVehicle ? 'Vehicle' :
                  isProperty ? 'Property' :
                  'Gig'
                )
              ]
            ),
            span(classes: 'text-xs font-semibold text-zinc-400', [Component.text('•')]),
            span(classes: 'text-sm font-bold ${isDark ? "text-zinc-200" : "text-zinc-800"} truncate', [
              Component.text(n['title'] as String? ?? 'Notification'),
            ]),
          ]),
          p(classes: 'text-xs leading-relaxed ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
            Component.text(n['message'] as String? ?? ''),
          ]),
          p(classes: 'text-[10px] mt-2 font-medium opacity-50 ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
            Component.text(
              DateTime.fromMillisecondsSinceEpoch(
                n['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
              ).toString().substring(0, 16),
            ),
          ]),
        ]),
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final s = state;
    final notifications = s.notifications;

    return div(
      classes:
          'absolute right-0 top-full mt-2 w-80 max-h-96 overflow-y-auto rounded-2xl shadow-xl border z-[100] animate-fade-down ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200"}',
      [
        div(
          classes:
              'p-4 border-b ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center justify-between sticky top-0 ${isDark ? "bg-zinc-900/90" : "bg-white/90"} backdrop-blur-md',
          [
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
          ],
        ),
        if (notifications.isEmpty)
          div(classes: 'p-8 text-center', [
            lIcon('bell-off', cls: 'w-8 h-8 mx-auto mb-3 opacity-20 ${isDark ? "text-white" : "text-zinc-900"}'),
            p(classes: 'text-sm font-medium ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
              Component.text('No new notifications'),
            ]),
          ])
        else
          div(classes: 'divide-y ${isDark ? "divide-zinc-800" : "divide-zinc-100"}', [
            for (final n in notifications)
              _buildNotificationItem(n, s),
          ]),
      ],
    );
  }
}
