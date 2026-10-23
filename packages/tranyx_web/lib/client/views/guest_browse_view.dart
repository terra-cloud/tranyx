import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';

/// W05 Guest · Browse home — public listings + signup CTAs (light & dark).
class GuestBrowseViewComponent extends StatelessComponent {
  final TranyxAppState state;
  const GuestBrowseViewComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final textPrimary = isDark ? 'text-zinc-50' : 'text-[#18181b]';
    final textSecondary = isDark ? 'text-zinc-400' : 'text-[#52525b]';
    final textMuted = isDark ? 'text-zinc-500' : 'text-[#71717a]';
    final card = isDark
        ? 'bg-zinc-900 border border-zinc-800'
        : 'bg-white border border-[#e4e4e7] shadow-[0px_4px_12px_0px_rgba(9,9,11,0.04)]';
    final link = 'text-[#4f46e5]';

    return div(classes: 'w05-guest space-y-10 animate-fade-up font-dm-sans', [
      // Hero
      div(classes: 'flex flex-col gap-3 max-w-3xl', [
        p(classes: 'm-0 text-sm font-semibold $link', [Component.text('Guest browse.')]),
        h1(
          classes: 'm-0 text-3xl md:text-4xl font-bold tracking-tight $textPrimary',
          [Component.text('Find Jobs. Hire Services. Rent Anything.')],
        ),
        p(
          classes: 'm-0 text-base leading-6 $textSecondary max-w-2xl',
          [
            Component.text(
              'Public listings near Makati. Exact address and contact unlock after you join and get hired.',
            ),
          ],
        ),
      ]),

      // CTA banner
      div(
        classes:
            'rounded-2xl p-5 md:p-6 flex flex-col md:flex-row md:items-center gap-4 md:gap-6 '
            '${isDark ? "bg-gradient-to-r from-indigo-950/80 to-violet-950/60 border border-indigo-500/20" : "bg-gradient-to-r from-[#eef2ff] to-[#e0e7ff]"}',
        [
          div(classes: 'flex-1', [
            p(
              classes: 'm-0 font-semibold text-base $textPrimary',
              [Component.text('Create a free account to apply, chat, and rent.')],
            ),
          ]),
          div(classes: 'flex flex-wrap items-center gap-2', [
            button(
              classes:
                  'h-11 px-5 rounded-xl font-semibold text-sm text-white bg-[#4f46e5] border-0 cursor-pointer hover:opacity-90',
              attributes: {'type': 'button'},
              events: {'click': (_) => s.promptGuestSignUp()},
              [Component.text('Create account')],
            ),
            button(
              classes:
                  'h-11 px-5 rounded-xl font-semibold text-sm border cursor-pointer '
                  '${isDark ? "bg-zinc-900 border-zinc-700 text-zinc-100 hover:bg-zinc-800" : "bg-white border-[#d4d4d8] text-[#18181b] hover:bg-zinc-50"}',
              attributes: {'type': 'button'},
              events: {'click': (_) => s.promptGuestSignIn()},
              [Component.text('Sign In')],
            ),
            button(
              classes: 'h-11 px-3 font-semibold text-sm $link bg-transparent border-0 cursor-pointer hover:underline',
              attributes: {'type': 'button'},
              events: {'click': (_) {}},
              [Component.text('Continue browsing')],
            ),
          ]),
        ],
      ),

      // Top Services
      _sectionHeader(
        title: 'Top Services',
        action: 'See All',
        onAction: () => s.switchTab(AppTab.jobs),
        textPrimary: textPrimary,
        link: link,
      ),
      div(classes: 'grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3', [
        for (final item in _topServices)
          div(
            classes: '$card rounded-2xl p-4 flex flex-col gap-3 cursor-pointer hover:border-[#4f46e5]/40 transition-colors',
            events: {'click': (_) => s.switchTab(AppTab.jobs)},
            [
              div(
                classes:
                    'size-10 rounded-xl flex items-center justify-center ${isDark ? "bg-indigo-500/15" : "bg-[#eef2ff]"}',
                [lIcon(item.$2, cls: 'w-5 h-5 text-[#4f46e5]')],
              ),
              div([
                p(classes: 'm-0 font-semibold text-sm $textPrimary', [Component.text(item.$1)]),
                p(classes: 'm-0 text-xs mt-0.5 $textMuted', [Component.text('${item.$3} jobs open')]),
              ]),
            ],
          ),
      ]),

      // Open gigs
      _sectionHeader(
        title: 'Open Gigs Near You',
        action: 'Browse Jobs',
        onAction: () => s.switchTab(AppTab.jobs),
        textPrimary: textPrimary,
        link: link,
      ),
      div(classes: 'grid grid-cols-1 md:grid-cols-3 gap-4', [
        for (final g in _sampleGigs)
          div(
            classes: '$card rounded-2xl p-5 flex flex-col gap-3 cursor-pointer hover:border-[#4f46e5]/40 transition-colors',
            events: {'click': (_) => s.promptGuestSignUp()},
            [
              p(classes: 'm-0 font-semibold text-[15px] $textPrimary', [Component.text(g.$1)]),
              div(classes: 'flex flex-wrap gap-2', [
                for (final tag in g.$2)
                  span(
                    classes:
                        'px-2.5 py-1 rounded-full text-xs font-semibold ${isDark ? "bg-zinc-800 text-zinc-300" : "bg-zinc-100 text-zinc-600"}',
                    [Component.text(tag)],
                  ),
              ]),
              div(classes: 'flex items-center justify-between mt-1', [
                p(classes: 'm-0 font-semibold text-base $textPrimary', [Component.text(g.$3)]),
                p(classes: 'm-0 text-xs $textMuted', [Component.text(g.$4)]),
              ]),
            ],
          ),
      ]),

      // Nearby rentals
      _sectionHeader(
        title: 'Nearby Rentals',
        action: 'View All',
        onAction: () => s.switchTab(AppTab.transit),
        textPrimary: textPrimary,
        link: link,
      ),
      div(classes: 'grid grid-cols-1 md:grid-cols-3 gap-4', [
        for (final r in _sampleRentals)
          div(
            classes: '$card rounded-[20px] overflow-hidden flex flex-col cursor-pointer hover:border-[#4f46e5]/40 transition-colors',
            events: {'click': (_) => s.promptGuestSignUp()},
            [
              div(
                classes:
                    'relative h-[140px] bg-gradient-to-r ${r.$5 ? "from-sky-200 to-violet-300" : "from-indigo-200 to-violet-400"} ${isDark ? "opacity-80" : ""}',
                [
                  span(
                    classes:
                        'absolute top-3 left-3 px-2.5 h-6 inline-flex items-center rounded-full text-xs font-semibold bg-emerald-50 text-emerald-700',
                    [Component.text('Available')],
                  ),
                ],
              ),
              div(classes: 'p-4 flex flex-col gap-1.5', [
                p(classes: 'm-0 font-semibold text-[15px] $textPrimary', [Component.text(r.$1)]),
                p(classes: 'm-0 text-xs font-medium $textSecondary', [Component.text(r.$2)]),
                div(classes: 'flex items-center gap-1 $textMuted', [
                  img(src: '/images/w05/3a723.svg', classes: 'size-3.5 ${isDark ? "opacity-70 invert" : ""}', attributes: {'alt': ''}),
                  span(classes: 'text-xs', [Component.text(r.$3)]),
                ]),
                div(classes: 'flex items-center justify-between pt-1.5', [
                  p(classes: 'm-0 font-semibold text-[17px] $textPrimary', [Component.text(r.$4)]),
                  div(classes: 'flex items-center gap-1', [
                    img(src: '/images/w05/f1da2.svg', classes: 'size-3.5', attributes: {'alt': ''}),
                    span(classes: 'text-xs font-medium $textSecondary', [Component.text(r.$6)]),
                  ]),
                ]),
              ]),
            ],
          ),
      ]),

      // Locked features
      p(classes: 'm-0 text-sm font-medium $textMuted', [Component.text('Locked until you join.')]),
      div(classes: 'flex flex-col gap-3', [
        _lockedRow(
          isDark: isDark,
          icon: 'message-circle',
          title: 'Messages',
          body: 'Chat with employers and hosts after you create an account.',
          onSignUp: () => s.promptGuestSignUp(),
          textPrimary: textPrimary,
          textSecondary: textSecondary,
        ),
        _lockedRow(
          isDark: isDark,
          icon: 'user',
          title: 'Profile & wallet',
          body: 'KYC, escrow payouts, and account settings stay private until you join.',
          onSignUp: () => s.promptGuestSignUp(),
          textPrimary: textPrimary,
          textSecondary: textSecondary,
        ),
      ]),
    ]);
  }

  Component _sectionHeader({
    required String title,
    required String action,
    required void Function() onAction,
    required String textPrimary,
    required String link,
  }) {
    return div(classes: 'flex items-center justify-between', [
      h2(classes: 'm-0 text-lg font-bold $textPrimary', [Component.text(title)]),
      button(
        classes: 'font-semibold text-sm $link bg-transparent border-0 cursor-pointer hover:underline flex items-center gap-1',
        attributes: {'type': 'button'},
        events: {'click': (_) => onAction()},
        [
          Component.text(action),
          img(src: '/images/w05/b5f41.svg', classes: 'size-4', attributes: {'alt': ''}),
        ],
      ),
    ]);
  }

  Component _lockedRow({
    required bool isDark,
    required String icon,
    required String title,
    required String body,
    required void Function() onSignUp,
    required String textPrimary,
    required String textSecondary,
  }) {
    return div(
      classes:
          'rounded-2xl px-4 py-4 flex flex-col sm:flex-row sm:items-center gap-3 '
          '${isDark ? "bg-zinc-900/80 border border-zinc-800" : "bg-zinc-100 border border-zinc-200"}',
      [
        div(classes: 'flex items-start gap-3 flex-1 min-w-0', [
          div(
            classes:
                'size-10 rounded-xl flex items-center justify-center shrink-0 ${isDark ? "bg-zinc-800 text-zinc-400" : "bg-white text-zinc-500 border border-zinc-200"}',
            [lIcon(icon, cls: 'w-5 h-5')],
          ),
          div(classes: 'min-w-0', [
            div(classes: 'flex items-center gap-2', [
              p(classes: 'm-0 font-semibold text-sm $textPrimary', [Component.text(title)]),
              img(src: '/images/w05/295b0.svg', classes: 'size-3.5 ${isDark ? "opacity-70 invert" : ""}', attributes: {'alt': 'Locked'}),
            ]),
            p(classes: 'm-0 text-xs mt-0.5 $textSecondary', [Component.text(body)]),
          ]),
        ]),
        button(
          classes:
              'h-10 px-4 rounded-xl font-semibold text-sm text-[#4f46e5] border border-[#4f46e5]/30 bg-transparent cursor-pointer hover:bg-[#4f46e5]/10 shrink-0',
          attributes: {'type': 'button'},
          events: {'click': (_) => onSignUp()},
          [Component.text('Sign up')],
        ),
      ],
    );
  }
}

/// Shown when a guest hits a locked tab (Messages / Profile).
class GuestLockedPane extends StatelessComponent {
  final TranyxAppState state;
  final String title;
  final String body;
  const GuestLockedPane({required this.state, required this.title, required this.body, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    return div(
      classes:
          'w05-locked max-w-lg mx-auto mt-16 text-center space-y-4 font-dm-sans animate-fade-up '
          '${isDark ? "text-zinc-50" : "text-[#18181b]"}',
      [
        div(
          classes:
              'mx-auto size-14 rounded-2xl flex items-center justify-center ${isDark ? "bg-zinc-800" : "bg-[#eef2ff]"}',
          [lIcon('lock', cls: 'w-6 h-6 text-[#4f46e5]')],
        ),
        h2(classes: 'm-0 text-2xl font-bold', [Component.text(title)]),
        p(classes: 'm-0 text-sm ${isDark ? "text-zinc-400" : "text-[#52525b]"}', [Component.text(body)]),
        div(classes: 'flex items-center justify-center gap-3 pt-2', [
          button(
            classes:
                'h-11 px-5 rounded-xl font-semibold text-sm text-white bg-[#4f46e5] border-0 cursor-pointer',
            attributes: {'type': 'button'},
            events: {'click': (_) => s.promptGuestSignUp()},
            [Component.text('Create account')],
          ),
          button(
            classes:
                'h-11 px-5 rounded-xl font-semibold text-sm border cursor-pointer '
                '${isDark ? "bg-zinc-900 border-zinc-700 text-zinc-100" : "bg-white border-[#d4d4d8] text-[#18181b]"}',
            attributes: {'type': 'button'},
            events: {'click': (_) => s.promptGuestSignIn()},
            [Component.text('Sign In')],
          ),
        ]),
      ],
    );
  }
}

// Sample public listings mirroring Figma W05 copy (static until guest reads ship).
const _topServices = <(String, String, int)>[
  ('Cleaning', 'sparkles', 12),
  ('Plumbing', 'activity', 8),
  ('Electrical', 'zap', 6),
  ('Carpentry', 'pen-tool', 5),
  ('Laundry', 'refresh-cw', 4),
  ('Delivery', 'truck', 9),
];

const _sampleGigs = <(String, List<String>, String, String)>[
  ('Aircon cleaning · 2 units', ['Cleaning', '2.1 km'], 'Php 1,500.00', '12 min ago'),
  ('Fix leaking kitchen sink', ['Plumbing', '3.4 km'], 'Php 900.00', '28 min ago'),
  ('Logo vector clean-up', ['Remote', 'Design'], 'Php 2,000.00', '1 hr ago'),
];

// title, meta, area, price, isProperty, rating
const _sampleRentals = <(String, String, String, String, bool, String)>[
  ('Toyota Vios 2022', 'Sedan • Automatic • 5 seats', 'Approx. area · Makati · 2.4 km', '₱ 1,800/day', false, '4.9'),
  ('Studio near BGC', 'Furnished • Wi‑Fi • 1 bath', 'Approx. area · Taguig · 3.1 km', '₱ 18,000/mo', true, '4.8'),
  ('Honda Click 125', 'Scooter • Automatic', 'Approx. area · Makati · 1.2 km', '₱ 450/day', false, '4.7'),
];
