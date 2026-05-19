import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
import 'package:shared/shared.dart';
import '../../constants/category_data.dart';

class HomeViewComponent extends StatelessComponent {
  final TranyxAppState state;
  const HomeViewComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final isNyxian = s.currentViewMode == AccountType.nyxian;
    final isHybrid = s.accountType == AccountType.hybrid;

    return div(classes: 'space-y-8 animate-fade-up', [
      // ── Hybrid mode switcher ──────────────────────────────
      if (isHybrid)
        segmentedControl(
          options: const [('Find Services', 'employer'), ('Work as Nyxian', 'nyxian')],
          selected: s.hybridToggle == AccountType.nyxian ? 'nyxian' : 'employer',
          isDark: isDark,
          onChange: (v) => s.setState(() => s.hybridToggle = v == 'nyxian' ? AccountType.nyxian : AccountType.employer),
        ),

      // ── Hero header ──────────────────────────────────────
      div(classes: 'space-y-3', [
        h1(classes: 'text-3xl md:text-4xl font-extrabold tracking-tight leading-tight', [
          Component.text(isNyxian ? 'Find your next gig.' : 'What do you need done?'),
        ]),
        p(classes: 'text-base md:text-lg ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
          Component.text(
            isNyxian
                ? 'Browse available jobs in your area and apply instantly.'
                : 'Post a job and connect with skilled Nyxians near you.',
          ),
        ]),
      ]),

      // ── Global Search Bar ─────────────────────────────────
      div(
        classes:
            'flex items-center gap-3 p-4 rounded-2xl border transition-colors ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200 shadow-sm"}',
        [
          lIcon('search', cls: 'w-5 h-5 ${isDark ? "text-zinc-600" : "text-zinc-400"} flex-shrink-0'),
          input(
            classes:
                'bg-transparent border-none outline-none flex-1 text-sm md:text-base ${isDark ? "text-zinc-200 placeholder-zinc-600" : "text-zinc-800 placeholder-zinc-400"}',
            type: InputType.search,
            attributes: {
              'placeholder': isNyxian ? 'Search available gigs...' : 'Search for a service or Nyxian...',
              'value': s.homeSearchQuery,
            },
            events: {
              'input': (e) {
                // ignore: avoid_dynamic_calls
                final v = (e as dynamic).target?.value as String? ?? '';
                s.setState(() => s.homeSearchQuery = v);
              },
              'keydown': (e) {
                // ignore: avoid_dynamic_calls
                final key = (e as dynamic).key as String? ?? '';
                if (key == 'Enter') s.handleHomeSearch(s.homeSearchQuery);
              },
            },
          ),
          button(
            classes:
                'flex-shrink-0 px-4 py-2 rounded-xl text-sm font-semibold text-white logo-gradient hover:opacity-90 transition-opacity',
            events: {'click': (_) => s.handleHomeSearch(s.homeSearchQuery)},
            [Component.text('Search')],
          ),
        ],
      ),

      // ── Ongoing / Current Gig Widget ──────────────────────
      _ongoingWidget(isDark: isDark, isNyxian: isNyxian, s: s),

      // ── Top Services Grid ─────────────────────────────────
      div([
        div(classes: 'flex items-center justify-between mb-5', [
          h2(classes: 'text-lg font-bold', [Component.text('Top Services')]),
          button(
            classes:
                'text-sm font-semibold ${isDark ? "text-indigo-400" : "text-indigo-600"} hover:underline flex items-center gap-1',
            events: {'click': (_) => s.setState(() => s.showCategoryModal = true)},
            [Component.text('See All'), lIcon('chevron-right', cls: 'w-4 h-4')],
          ),
        ]),
        div(classes: 'grid grid-cols-2 md:grid-cols-4 gap-4', [
          for (int i = 0; i < 4 && i < categoryMap.values.first.length; i++)
            _categoryCard(
              CategoryItem(
                id: categoryMap.values.first[i].id,
                label: categoryMap.values.first[i].label,
                icon: categoryMap.values.first[i].icon,
              ),
              isDark,
              s,
              i,
              isNyxian,
            ),
        ]),
      ]),

      // ── Transit Teaser ────────────────────────────────────
      _transitTeaser(isDark: isDark, onTap: () => s.switchTab(AppTab.transit)),

      // ── Real Estate Teaser ────────────────────────────────
      _realEstateTeaser(isDark: isDark),
    ]);
  }

  Component _ongoingWidget({required bool isDark, required bool isNyxian, required TranyxAppState s}) {
    final job = s.ongoingJob;

    if (isNyxian) {
      if (job != null) {
        final title = job['title'] as String? ?? 'Current Gig';
        final rate = '\u20b1 ${(job['pricingValue'] as num?)?.toStringAsFixed(0) ?? "0"}';
        return div(
          classes: 'p-5 rounded-2xl border border-green-500/30 bg-green-500/10 card-hover',
          [
            div(classes: 'flex items-center justify-between mb-3', [
              div(classes: 'flex items-center gap-3', [
                div(classes: 'p-2 rounded-xl bg-green-500/20', [lIcon('zap', cls: 'w-5 h-5 text-green-400')]),
                div([
                  p(classes: 'text-xs font-semibold text-green-400 uppercase tracking-wider', [
                    Component.text('Current Gig'),
                  ]),
                  p(classes: 'font-bold text-base', [Component.text(title)]),
                ]),
              ]),
              span(classes: 'px-3 py-1.5 rounded-lg text-xs font-bold bg-green-500/20 text-green-400 animate-pulse', [
                Component.text('LIVE'),
              ]),
            ]),
            div(classes: 'flex items-center justify-between', [
              span(classes: 'font-bold text-green-300 text-lg', [Component.text(rate)]),
              button(
                classes:
                    'px-4 py-2.5 rounded-xl text-sm font-semibold text-white bg-green-500 hover:bg-green-400 transition-colors',
                events: {'click': (_) => s.selectJobAndLoadDetails(job)},
                [Component.text('View Details')],
              ),
            ]),
          ],
        );
      }
      // No ongoing gig
      return div(
        classes:
            'p-5 rounded-2xl border ${isDark ? "border-zinc-800 bg-zinc-900/40" : "border-zinc-200 bg-zinc-50"} flex items-center gap-3',
        [
          div(classes: 'p-2 rounded-xl bg-zinc-700/30', [lIcon('zap', cls: 'w-5 h-5 text-zinc-500')]),
          p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
            Component.text('No active gig. Browse available jobs below.'),
          ]),
        ],
      );
    }

    // Employer
    if (job != null) {
      final title = job['title'] as String? ?? 'Active Job';
      final applicants = (job['applicantCount'] as int?) ?? 0;
      return div(
        classes: 'p-5 rounded-2xl border border-blue-500/30 bg-blue-500/10 card-hover',
        [
          div(classes: 'flex items-center justify-between mb-3', [
            div(classes: 'flex items-center gap-3', [
              div(classes: 'p-2 rounded-xl bg-blue-500/20', [lIcon('briefcase', cls: 'w-5 h-5 text-blue-400')]),
              div([
                p(classes: 'text-xs font-semibold text-blue-400 uppercase tracking-wider', [
                  Component.text('Ongoing Job'),
                ]),
                p(classes: 'font-bold text-base', [Component.text(title)]),
              ]),
            ]),
            span(classes: 'px-3 py-1.5 rounded-lg text-xs font-bold bg-blue-500/20 text-blue-400', [
              Component.text('ACTIVE'),
            ]),
          ]),
          div(classes: 'flex items-center justify-between', [
            p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
              Component.text('$applicants applicant${applicants == 1 ? "" : "s"}'),
            ]),
            button(
              classes:
                  'flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm font-semibold logo-gradient text-white transition-opacity',
              events: {'click': (_) => s.selectJobAndLoadDetails(job)},
              [lIcon('users', cls: 'w-4 h-4'), Component.text(' Manage')],
            ),
          ]),
        ],
      );
    }

    // No ongoing employer job
    return div(
      classes:
          'p-5 rounded-2xl border ${isDark ? "border-zinc-800 bg-zinc-900/40" : "border-zinc-200 bg-zinc-50"} flex items-center gap-3',
      [
        div(classes: 'p-2 rounded-xl bg-zinc-700/30', [lIcon('briefcase', cls: 'w-5 h-5 text-zinc-500')]),
        p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
          Component.text('No jobs in progress. Post a new job to get started.'),
        ]),
      ],
    );
  }

  Component _categoryCard(CategoryItem cat, bool isDark, TranyxAppState s, int index, bool isNyxian) {
    final cardCls = isDark
        ? 'bg-zinc-900 border-zinc-800 hover:border-indigo-500/50'
        : 'bg-white border-zinc-200 shadow-sm hover:shadow-md';
    return button(
      classes:
          'flex flex-col items-center justify-center gap-3 p-5 rounded-2xl border transition-all card-hover text-center stagger-${index + 1} animate-fade-up $cardCls',
      events: {
        'click': (_) {
          if (isNyxian) {
            // For Nyxians, clicking a category searches for it
            s.handleHomeSearch(cat.label);
          } else {
            // For Employers, clicking a category opens the posting modal
            s.selectedCategory = SelectedCategory(
              id: cat.id,
              label: cat.label,
              iconName: cat.icon,
              hasTracker: cat.hasTracker,
              color: 'text-indigo-400',
            );
            s.showCategoryModal = true;
          }
        },
      },
      [
        div(classes: 'p-3 rounded-xl ${isDark ? "bg-zinc-800" : "bg-zinc-100"}', [
          lIcon(cat.icon, cls: 'w-6 h-6 text-indigo-400'),
        ]),
        span(classes: 'text-sm font-semibold', [Component.text(cat.label)]),
      ],
    );
  }

  Component _transitTeaser({required bool isDark, required void Function() onTap}) {
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    return button(
      classes: 'w-full p-6 rounded-2xl border card-hover transition-all text-left $cardCls',
      events: {'click': (_) => onTap()},
      [
        div(classes: 'flex items-center justify-between', [
          div(classes: 'flex items-center gap-4', [
            div(classes: 'p-3 rounded-2xl bg-purple-500/10 border border-purple-500/20', [
              lIcon('car', cls: 'w-7 h-7 text-purple-400'),
            ]),
            div([
              h3(classes: 'font-bold text-lg', [Component.text('Transit Hub')]),
              p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
                Component.text('Rent or host a vehicle near you'),
              ]),
            ]),
          ]),
          div(classes: 'flex items-center gap-2 text-purple-400 font-semibold text-sm', [
            Component.text('Explore'),
            lIcon('arrow-right', cls: 'w-4 h-4'),
          ]),
        ]),
      ],
    );
  }

  Component _realEstateTeaser({required bool isDark}) {
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    return div(
      classes: 'p-6 rounded-2xl border $cardCls',
      [
        div(classes: 'flex items-center justify-between', [
          div(classes: 'flex items-center gap-4', [
            div(classes: 'p-3 rounded-2xl bg-amber-500/10 border border-amber-500/20', [
              lIcon('building', cls: 'w-7 h-7 text-amber-400'),
            ]),
            div([
              div(classes: 'flex items-center gap-2', [
                h3(classes: 'font-bold text-lg', [Component.text('Real Estate on Chain')]),
                span(classes: 'px-2 py-0.5 rounded text-[10px] font-bold bg-amber-500/20 text-amber-400', [
                  Component.text('V2.0'),
                ]),
              ]),
              p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
                Component.text('Tokenized property listings coming soon'),
              ]),
            ]),
          ]),
          button(
            classes:
                'px-4 py-2 rounded-xl text-xs font-bold bg-amber-500/20 text-amber-400 hover:bg-amber-500/30 transition-colors',
            events: {},
            [Component.text('Join Waitlist')],
          ),
        ]),
      ],
    );
  }
}
