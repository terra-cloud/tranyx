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
              'id': 'home-search-input',
              'name': 'search',
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

      if (isNyxian) ...[
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
        _realEstateTeaser(isDark: isDark, s: s),
      ] else ...[
        // Employer view: Proximity-sorted rentals carousels
        _nearMeRentalsSection(
          title: '🚗 Vehicles Near Me',
          items: s.realtimeRentals
              .where((r) => r['status'] == 'Available' && r['hostId'] != s.userProfile?.uid)
              .take(4)
              .toList(),
          isProperty: false,
          isDark: isDark,
          s: s,
        ),

        _nearMeRentalsSection(
          title: '🏢 Real Estate Near Me',
          items: s.realtimeProperties
              .where((p) => p.status == 'Available' && p.hostId != s.userProfile?.uid)
              .take(4)
              .toList(),
          isProperty: true,
          isDark: isDark,
          s: s,
        ),
      ],
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

  Component _nearMeRentalsSection({
    required String title,
    required List<dynamic> items,
    required bool isProperty,
    required bool isDark,
    required TranyxAppState s,
  }) {
    final headerCls = isDark ? "text-white" : "text-zinc-900";

    return div([
      div(classes: 'flex items-center justify-between mb-4', [
        h2(classes: 'text-lg font-bold $headerCls', [Component.text(title)]),
        button(
          classes:
              'text-sm font-semibold text-indigo-400 hover:underline flex items-center gap-1 bg-transparent border-0 cursor-pointer',
          events: {
            'click': (_) {
              s.setState(() {
                s.activeTab = AppTab.transit;
                s.activeRentalCategory = isProperty ? RentalCategory.properties : RentalCategory.vehicles;
              });
            },
          },
          [Component.text('View All'), lIcon('chevron-right', cls: 'w-4 h-4')],
        ),
      ]),
      if (items.isEmpty)
        div(
          classes:
              'p-8 rounded-2xl border border-dashed border-zinc-800 text-zinc-500 bg-zinc-900/10 text-center font-medium text-sm',
          [Component.text('No listings available near you.')],
        )
      else
        div(classes: 'grid grid-cols-2 lg:grid-cols-4 gap-4', [
          for (final item in items) _nearMeCard(item, isProperty, isDark, s),
        ]),
    ]);
  }

  Component _nearMeCard(dynamic item, bool isProperty, bool isDark, TranyxAppState s) {
    final cardCls = isDark
        ? "bg-zinc-900 border-zinc-800 hover:border-purple-500/40"
        : "bg-white border-zinc-200 shadow-sm hover:shadow-md";

    if (isProperty) {
      final prop = item as PropertyRental;
      final hasPhoto = prop.photoUrls.isNotEmpty && prop.photoUrls.first.isNotEmpty;
      final dist = ((prop.id.hashCode).abs() % 80) / 10.0 + 0.5;

      return div(
        classes: 'p-4 rounded-2xl border transition-all cursor-pointer $cardCls',
        events: {
          'click': (_) => s.setState(() {
            s.selectedPropertyData = prop.toMap();
            s.showBookPropertyModal = true;
          }),
        },
        [
          div(
            classes: 'aspect-video w-full rounded-xl mb-3 overflow-hidden bg-zinc-800 relative',
            [
              if (hasPhoto)
                img(src: prop.photoUrls.first, classes: 'w-full h-full object-cover', attributes: {'alt': prop.title})
              else
                div(classes: 'w-full h-full flex items-center justify-center bg-zinc-850', [
                  lIcon('home', cls: 'w-8 h-8 text-zinc-650'),
                ]),
            ],
          ),
          h4(classes: 'font-bold text-sm line-clamp-1 text-zinc-200', [Component.text(prop.title)]),
          p(classes: 'text-[10px] text-zinc-500 mt-1 capitalize', [
            Component.text('${prop.category.name} • ${prop.type.name}'),
          ]),
          div(classes: 'flex items-center justify-between mt-3', [
            span(classes: 'font-extrabold text-purple-400 text-sm', [
              Component.text('₱ ${prop.priceMonthly.toStringAsFixed(0)}/mo'),
            ]),
            span(classes: 'text-[10px] text-zinc-500 flex items-center gap-0.5', [
              lIcon('map-pin', cls: 'w-3 h-3 text-purple-400'),
              Component.text('${dist.toStringAsFixed(1)} km'),
            ]),
          ]),
        ],
      );
    } else {
      final r = item as Map<String, dynamic>;
      final model = r['model'] ?? 'Vehicle';
      final brand = r['brand'] ?? 'Unknown';
      final photoUrl = r['frontPhotoUrl'] ?? r['frontPhoto'] ?? r['photoUrl'];
      final hasPhoto = photoUrl != null && photoUrl.toString().isNotEmpty && photoUrl.toString() != 'null';
      final dist = ((r['id']?.toString().hashCode ?? 0).abs() % 80) / 10.0 + 0.5;
      final priceVal = r['priceDaily'] ?? r['dailyRate'];

      return div(
        classes: 'p-4 rounded-2xl border transition-all cursor-pointer $cardCls',
        events: {
          'click': (_) => s.setState(() {
            s.selectedRentalData = r;
            s.showBookVehicleModal = true;
          }),
        },
        [
          div(
            classes: 'aspect-video w-full rounded-xl mb-3 overflow-hidden bg-zinc-850 relative',
            [
              if (hasPhoto)
                img(
                  src: photoUrl.toString(),
                  classes: 'w-full h-full object-cover',
                  attributes: {'alt': '$brand $model'},
                )
              else
                div(classes: 'w-full h-full flex items-center justify-center bg-zinc-800', [
                  lIcon('car', cls: 'w-8 h-8 text-zinc-650'),
                ]),
            ],
          ),
          h4(classes: 'font-bold text-sm line-clamp-1 text-zinc-200', [Component.text('$brand $model')]),
          p(classes: 'text-[10px] text-zinc-500 mt-1 capitalize', [
            Component.text(r['type'] ?? r['vehicleType'] ?? 'car'),
          ]),
          div(classes: 'flex items-center justify-between mt-3', [
            span(classes: 'font-extrabold text-purple-400 text-sm', [Component.text('₱ $priceVal/day')]),
            span(classes: 'text-[10px] text-zinc-500 flex items-center gap-0.5', [
              lIcon('map-pin', cls: 'w-3 h-3 text-purple-400'),
              Component.text('${dist.toStringAsFixed(1)} km'),
            ]),
          ]),
        ],
      );
    }
  }

  Component _categoryCard(CategoryItem cat, bool isDark, TranyxAppState s, int index, bool isNyxian) {
    final cardCls = isDark
        ? 'bg-zinc-900 border-zinc-800 hover:border-indigo-500/50'
        : 'bg-white border-zinc-200 shadow-sm hover:shadow-md';
    return button(
      classes:
          'flex flex-col items-center justify-center gap-3 p-5 rounded-2xl border transition-all card-hover text-center stagger-${index + 1} animate-fade-up cursor-pointer bg-transparent $cardCls',
      events: {
        'click': (_) {
          if (isNyxian) {
            s.handleHomeSearch(cat.label);
          } else {
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
      classes:
          'w-full p-6 rounded-2xl border card-hover transition-all text-left cursor-pointer bg-transparent $cardCls',
      events: {'click': (_) => onTap()},
      [
        div(classes: 'flex items-center justify-between', [
          div(classes: 'flex items-center gap-4', [
            div(classes: 'p-3 rounded-2xl bg-purple-500/10 border border-purple-500/20', [
              lIcon('car', cls: 'w-7 h-7 text-purple-400'),
            ]),
            div([
              h3(classes: 'font-bold text-lg text-zinc-200', [Component.text('Vehicles Rentals')]),
              p(classes: 'text-sm ${isDark ? "text-zinc-550" : "text-zinc-500"}', [
                Component.text('Rent or host cars, motorbikes, or logistics trucks near you'),
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

  Component _realEstateTeaser({required bool isDark, required TranyxAppState s}) {
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    return button(
      classes:
          'w-full p-6 rounded-2xl border card-hover transition-all text-left cursor-pointer bg-transparent $cardCls',
      events: {
        'click': (_) {
          s.setState(() {
            s.activeTab = AppTab.transit;
            s.activeRentalCategory = RentalCategory.properties;
          });
        },
      },
      [
        div(classes: 'flex items-center justify-between', [
          div(classes: 'flex items-center gap-4', [
            div(classes: 'p-3 rounded-2xl bg-amber-500/10 border border-amber-500/20', [
              lIcon('home', cls: 'w-7 h-7 text-amber-400'),
            ]),
            div([
              h3(classes: 'font-bold text-lg text-zinc-200', [Component.text('Real Estate Rentals')]),
              p(classes: 'text-sm ${isDark ? "text-zinc-550" : "text-zinc-500"}', [
                Component.text('Rent apartments, bedspaces, private rooms, and commercial offices directly'),
              ]),
            ]),
          ]),
          div(classes: 'flex items-center gap-2 text-amber-450 font-semibold text-sm', [
            Component.text('Rent Spaces'),
            lIcon('arrow-right', cls: 'w-4 h-4'),
          ]),
        ]),
      ],
    );
  }
}
