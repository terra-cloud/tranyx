import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
import '../../services/web_interop.dart';
import 'package:shared/shared.dart';


// ── Top-services computation helper ──────────────────────────────────────────
/// Returns the top [limit] JobCategoryGroups ranked by how many jobs exist
/// for each group in [allJobs]. Falls back to the first static groups when
/// the list is empty.
List<({JobCategoryGroup group, int count})> _computeTopGroups(
  List<Map<String, dynamic>> allJobs, {
  int limit = 4,
}) {
  // Tally jobs per category group
  final tally = <String, int>{};
  for (final job in allJobs) {
    final raw = job['categoryGroup'] as String?;
    if (raw != null && raw.isNotEmpty) {
      tally[raw] = (tally[raw] ?? 0) + 1;
    }
  }

  if (tally.isEmpty) {
    // Fall back to first [limit] static groups with zero count
    return JobCategoryGroup.values.take(limit).map((g) => (group: g, count: 0)).toList();
  }

  // Resolve to enum values and sort descending by count
  final entries = tally.entries
      .map((e) {
        final grp = JobCategoryGroup.values.where((g) => g.name == e.key).firstOrNull;
        if (grp == null) return null;
        return (group: grp, count: e.value);
      })
      .whereType<({JobCategoryGroup group, int count})>()
      .toList()
    ..sort((grpA, grpB) => grpB.count.compareTo(grpA.count));

  // Pad with unseen groups when fewer than [limit] distinct groups appear
  if (entries.length < limit) {
    final seen = entries.map((e) => e.group).toSet();
    for (final g in JobCategoryGroup.values) {
      if (!seen.contains(g)) {
        entries.add((group: g, count: 0));
      }
      if (entries.length >= limit) break;
    }
  }

  return entries.take(limit).toList();
}

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
          onChange: (v) {
            s.setState(() => s.hybridToggle = v == 'nyxian' ? AccountType.nyxian : AccountType.employer);
            s.loadHoldbacks();
          },
        ),

      // ── Hero header ──────────────────────────────────────
      div(classes: 'space-y-3', [
        h1(classes: 'text-3xl md:text-4xl font-extrabold tracking-tight leading-tight logo-gradient bg-clip-text text-transparent', [
          Component.text('Hire Services. Find Jobs. Rent Anything.'),
        ]),
        p(classes: 'text-base md:text-lg ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
          Component.text(
            isNyxian
                ? 'Browse available jobs in your area, track transit routes, and start earning.'
                : 'Connect with verified Nyxians, rent assets, and get tasks done safely.',
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
                s.setState(() => s.homeSearchQuery = getInputValue(e.target));
              },
              'keydown': (e) {
                final key = (e as web.KeyboardEvent).key;
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

      // ── Quick Stats Bar ───────────────────────────────────
      _quickStatsBar(isDark: isDark, isNyxian: isNyxian, s: s),

      // ── Ongoing / Current Gig Widget ──────────────────────
      _ongoingWidget(isDark: isDark, isNyxian: isNyxian, s: s),

      // ── Active Trackers & Trips ───────────────────────────
      _activeTrackersSection(isDark: isDark, s: s),

      if (isNyxian) ...[
        // ── Top Services Grid (Firebase-synced) ───────────────
        _topServicesSection(isDark: isDark, s: s),

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
              .where((prop) => prop.status == 'Available' && prop.hostId != s.userProfile?.uid)
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
              div(classes: 'flex items-center gap-2', [
                button(
                  classes:
                      'px-4 py-2.5 rounded-xl text-sm font-semibold text-white bg-green-500 hover:bg-green-400 transition-colors',
                  events: {'click': (_) => s.selectJobAndLoadDetails(job)},
                  [Component.text('View Details')],
                ),
                button(
                  classes:
                      'px-4 py-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800 text-zinc-350" : "border-zinc-200 hover:bg-zinc-100 text-zinc-700"} transition-colors relative',
                  events: {'click': (_) => s.openChat(job['id'] as String)},
                  [
                    lIcon('message-square', cls: 'w-4 h-4'),
                    if (s.getUnreadChatCount(job['id'] as String) > 0)
                      span(
                        classes:
                            'absolute -top-1.5 -right-1.5 px-2 py-0.5 text-[10px] font-black text-white bg-red-500 rounded-full border-2 ${isDark ? "border-zinc-900" : "border-white"} animate-pulse',
                        [Component.text('${s.getUnreadChatCount(job['id'] as String)}')],
                      ),
                  ],
                ),
              ]),
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
            div(classes: 'flex items-center gap-2', [
              button(
                classes:
                    'flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm font-semibold logo-gradient text-white transition-opacity',
                events: {'click': (_) => s.selectJobAndLoadDetails(job)},
                [lIcon('users', cls: 'w-4 h-4'), Component.text(' Manage')],
              ),
              button(
                classes:
                    'px-4 py-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800 text-zinc-350" : "border-zinc-200 hover:bg-zinc-100 text-zinc-700"} transition-colors relative',
                events: {'click': (_) => s.openChat(job['id'] as String)},
                [
                  lIcon('message-square', cls: 'w-4 h-4'),
                  if (s.getUnreadChatCount(job['id'] as String) > 0)
                    span(
                      classes:
                          'absolute -top-1.5 -right-1.5 px-2 py-0.5 text-[10px] font-black text-white bg-red-500 rounded-full border-2 ${isDark ? "border-zinc-900" : "border-white"} animate-pulse',
                      [Component.text('${s.getUnreadChatCount(job['id'] as String)}')],
                    ),
                ],
              ),
            ]),
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

  /// Renders the Firebase-synced Top Services grid for Nyxian home view.
  Component _topServicesSection({required bool isDark, required TranyxAppState s}) {
    final allJobs = [...s.availableJobs, ...s.myJobs];
    final isLoading = s.isLoadingJobs && allJobs.isEmpty;
    final topGroups = _computeTopGroups(allJobs);

    final cardBase = isDark
        ? 'bg-zinc-900 border-zinc-800'
        : 'bg-white border-zinc-200 shadow-sm';

    return div([
      div(classes: 'flex items-center justify-between mb-5', [
        div(classes: 'flex items-center gap-2', [
          h2(classes: 'text-lg font-bold', [Component.text('Top Services')]),
          if (!isLoading && allJobs.isNotEmpty)
            span(
              classes: 'px-2 py-0.5 rounded-full text-[10px] font-bold bg-indigo-500/15 text-indigo-400 border border-indigo-500/20',
              [Component.text('LIVE')],
            ),
        ]),
        button(
          classes:
              'text-sm font-semibold ${isDark ? "text-indigo-400" : "text-indigo-600"} hover:underline flex items-center gap-1 bg-transparent border-0 cursor-pointer',
          events: {'click': (_) => s.setState(() => s.showCategoryModal = true)},
          [Component.text('See All'), lIcon('chevron-right', cls: 'w-4 h-4')],
        ),
      ]),

      if (isLoading)
        // Shimmer skeleton while jobs load
        div(classes: 'grid grid-cols-2 md:grid-cols-4 gap-4', [
          for (int i = 0; i < 4; i++)
            div(
              classes: 'animate-pulse rounded-2xl border $cardBase p-5 flex flex-col items-center gap-3',
              [
                div(classes: 'w-12 h-12 rounded-xl ${isDark ? "bg-zinc-800" : "bg-zinc-100"}', []),
                div(classes: 'w-20 h-3 rounded-full ${isDark ? "bg-zinc-800" : "bg-zinc-200"}', []),
                div(classes: 'w-12 h-2 rounded-full ${isDark ? "bg-zinc-800" : "bg-zinc-200"}', []),
              ],
            ),
        ])
      else
        div(classes: 'grid grid-cols-2 md:grid-cols-4 gap-4', [
          for (int i = 0; i < topGroups.length; i++)
            _categoryGroupCard(topGroups[i].group, topGroups[i].count, isDark, s, i),
        ]),
    ]);
  }

  /// Renders a single category group card with a live job count badge.
  Component _categoryGroupCard(
    JobCategoryGroup group,
    int jobCount,
    bool isDark,
    TranyxAppState s,
    int index,
  ) {
    final cardCls = isDark
        ? 'bg-zinc-900 border-zinc-800 hover:border-indigo-500/50'
        : 'bg-white border-zinc-200 shadow-sm hover:shadow-md';

    return button(
      classes:
          'relative flex flex-col items-center justify-center gap-3 p-5 rounded-2xl border transition-all card-hover text-center stagger-${index + 1} animate-fade-up cursor-pointer bg-transparent $cardCls',
      events: {
        'click': (_) => s.handleHomeSearch(group.label),
      },
      [
        // Live job count badge (only if > 0)
        if (jobCount > 0)
          div(
            classes: 'absolute top-3 right-3 px-1.5 py-0.5 rounded-full text-[9px] font-bold bg-indigo-500 text-white leading-tight',
            [Component.text('$jobCount')],
          ),
        div(classes: 'p-3 rounded-xl ${isDark ? "bg-zinc-800" : "bg-zinc-100"}', [
          lIcon(group.icon, cls: 'w-6 h-6 text-indigo-400'),
        ]),
        span(classes: 'text-sm font-semibold leading-tight', [Component.text(group.label)]),
        if (jobCount > 0)
          span(
            classes: 'text-[10px] ${isDark ? "text-zinc-500" : "text-zinc-400"}',
            [Component.text('$jobCount job${jobCount == 1 ? "" : "s"} open')],
          )
        else
          span(
            classes: 'text-[10px] ${isDark ? "text-zinc-600" : "text-zinc-400"}',
            [Component.text('Browse')],
          ),
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
              p(classes: 'text-sm ${isDark ? "text-zinc-555" : "text-zinc-500"}', [
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

  Component _quickStatsBar({required bool isDark, required bool isNyxian, required TranyxAppState s}) {
    final cardBg = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    final labelColor = isDark ? 'text-zinc-500' : 'text-zinc-400';
    final titleColor = isDark ? 'text-zinc-150' : 'text-zinc-800';

    final pendingTotal = s.pendingHoldbacks.fold<double>(0.0, (sum, item) {
      final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
      return sum + amt;
    });

    Component buildPendingReleaseBreakdown() {
      if (pendingTotal <= 0) return div([]);
      return div(classes: 'mt-2 space-y-1 border-t border-zinc-500/10 pt-2', [
        for (final holdback in s.pendingHoldbacks)
          Builder(builder: (context) {
            final amt = (holdback['amount'] as num?)?.toDouble() ?? 0.0;
            final relAt = holdback['releaseAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;
            final hrs = ((relAt - DateTime.now().millisecondsSinceEpoch) / (1000 * 60 * 60)).ceil();
            final hrsStr = hrs <= 0 ? 'processing release' : 'releases in $hrs hr${hrs == 1 ? "" : "s"}';
            return p(classes: 'text-[9px] text-amber-500/80 font-bold text-left', [
              Component.text('• Php ${amt.toStringAsFixed(2)} $hrsStr'),
            ]);
          }),
      ]);
    }

    if (isNyxian) {
      final tyxBal = s.userProfile?.tyxBalance ?? 0.0;
      final jobsDone = s.userProfile?.jobsDone ?? 0;
      final totalEarned = s.userProfile?.totalEarned ?? 0.0;
      final rating = s.userProfile?.rating ?? 5.0;

      return div(classes: 'grid grid-cols-2 lg:grid-cols-4 gap-4', [
        // Wallet Balance
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-indigo-500/40 cursor-pointer $cardBg',
          events: {'click': (_) => s.setState(() => s.showDepositModal = true)},
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [Component.text('Balance')]),
              lIcon('wallet', cls: 'w-4 h-4 text-indigo-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor', [
              Component.text('₱ ${tyxBal.toStringAsFixed(2)}'),
            ]),
            if (pendingTotal > 0) ...[
              p(classes: 'text-[9px] text-amber-500 font-bold mt-1.5 flex items-center gap-0.5 animate-pulse', [
                lIcon('clock', cls: 'w-2.5 h-2.5'),
                Component.text('+ ₱${pendingTotal.toStringAsFixed(2)} Pending'),
              ]),
              buildPendingReleaseBreakdown(),
            ] else
              p(classes: 'text-[9px] text-zinc-500 mt-1 font-semibold hover:text-indigo-400 transition-colors', [Component.text('Deposit Tyx')],),
          ],
        ),
        // Completed Gigs
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-purple-500/40 cursor-pointer $cardBg',
          events: {'click': (_) => s.setState(() {
            s.activeTab = AppTab.profile;
            s.profileView = ProfileView.main;
          })},
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [Component.text('Gigs Done')]),
              lIcon('check-circle', cls: 'w-4 h-4 text-purple-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor', [
              Component.text('$jobsDone'),
            ]),
            p(classes: 'text-[9px] text-purple-450 font-semibold mt-1', [Component.text('View Profile')]),
          ],
        ),
        // Total Earnings
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-emerald-500/40 cursor-pointer $cardBg',
          events: {'click': (_) => s.setState(() {
            s.activeTab = AppTab.profile;
            s.profileView = ProfileView.history;
          })},
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [Component.text('Total Earned')]),
              lIcon('trending-up', cls: 'w-4 h-4 text-emerald-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor', [
              Component.text('₱ ${totalEarned.toStringAsFixed(0)}'),
            ]),
            p(classes: 'text-[9px] text-emerald-450 font-semibold mt-1', [Component.text('View Earnings')]),
          ],
        ),
        // Rating
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-amber-500/40 cursor-pointer $cardBg',
          events: {'click': (_) => s.setState(() {
            s.activeTab = AppTab.profile;
            s.profileView = ProfileView.reviews;
          })},
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [Component.text('Trust Rating')]),
              lIcon('star', cls: 'w-4 h-4 text-amber-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor flex items-center gap-1', [
              Component.text(rating.toStringAsFixed(1)),
              span(classes: 'text-xs text-amber-400', [Component.text('★')]),
            ]),
            p(classes: 'text-[9px] text-amber-500 font-semibold mt-1', [Component.text('View Reviews')]),
          ],
        ),
      ]);
    } else {
      // Employer Mode
      final tyxBal = s.userProfile?.tyxBalance ?? 0.0;
      final postedCount = s.myJobs.length;
      final activeHires = s.myJobs.where((j) => j['status'] == 'In Progress').length;
      final rating = s.userProfile?.rating ?? 5.0;

      return div(classes: 'grid grid-cols-2 lg:grid-cols-4 gap-4', [
        // Wallet Balance
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-indigo-500/40 cursor-pointer $cardBg',
          events: {'click': (_) => s.setState(() => s.showDepositModal = true)},
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [Component.text('Balance')]),
              lIcon('wallet', cls: 'w-4 h-4 text-indigo-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor', [
              Component.text('₱ ${tyxBal.toStringAsFixed(2)}'),
            ]),
            if (pendingTotal > 0) ...[
              p(classes: 'text-[9px] text-amber-500 font-bold mt-1.5 flex items-center gap-0.5 animate-pulse', [
                lIcon('clock', cls: 'w-2.5 h-2.5'),
                Component.text('+ ₱${pendingTotal.toStringAsFixed(2)} Pending'),
              ]),
              buildPendingReleaseBreakdown(),
            ] else
              p(classes: 'text-[9px] text-zinc-500 mt-1 font-semibold hover:text-indigo-400 transition-colors', [Component.text('Deposit Tyx')]),
          ],
        ),
        // Posted Gigs
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-purple-500/40 cursor-pointer $cardBg',
          events: {'click': (_) => s.setState(() {
            s.activeTab = AppTab.jobs;
            s.activeJobPane = 'active';
          })},
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [Component.text('Gigs Posted')]),
              lIcon('briefcase', cls: 'w-4 h-4 text-purple-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor', [
              Component.text('$postedCount'),
            ]),
            p(classes: 'text-[9px] text-purple-450 font-semibold mt-1', [Component.text('Manage Gigs')]),
          ],
        ),
        // Active Hires
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-emerald-500/40 cursor-pointer $cardBg',
          events: {'click': (_) => s.setState(() {
            s.activeTab = AppTab.jobs;
            s.activeJobPane = 'active';
          })},
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [Component.text('Active Gigs')]),
              lIcon('users', cls: 'w-4 h-4 text-emerald-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor', [
              Component.text('$activeHires'),
            ]),
            p(classes: 'text-[9px] text-emerald-450 font-semibold mt-1', [Component.text('View Active Workers')]),
          ],
        ),
        // Rating
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-amber-500/40 cursor-pointer $cardBg',
          events: {'click': (_) => s.setState(() {
            s.activeTab = AppTab.profile;
            s.profileView = ProfileView.reviews;
          })},
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [Component.text('Employer Score')]),
              lIcon('star', cls: 'w-4 h-4 text-amber-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor flex items-center gap-1', [
              Component.text(rating.toStringAsFixed(1)),
              span(classes: 'text-xs text-amber-400', [Component.text('★')]),
            ]),
            p(classes: 'text-[9px] text-amber-500 font-semibold mt-1', [Component.text('View Reviews')]),
          ],
        ),
      ]);
    }
  }

  Component _activeTrackersSection({required bool isDark, required TranyxAppState s}) {
    final currentUid = s.userProfile?.uid;
    if (currentUid == null) return div([]);

    final activeRentals = s.realtimeRentals
        .where((r) =>
            r['renteeId'] == currentUid &&
            r['status'] != 'Available' &&
            r['status'] != 'Completed' &&
            r['status'] != 'Complete')
        .toList();

    final activeLeases = s.realtimeProperties
        .where((leaseItem) => leaseItem.renteeId == currentUid && leaseItem.status != 'Available' && leaseItem.status != 'Completed')
        .toList();

    final hasActiveRentals = activeRentals.isNotEmpty || activeLeases.isNotEmpty;

    if (!hasActiveRentals) return div([]);

    return div(classes: 'space-y-4', [
      h2(classes: 'text-lg font-bold flex items-center gap-2', [
        lIcon('compass', cls: 'w-5 h-5 text-purple-400'),
        Component.text('Active Rentals & Trips'),
      ]),
      div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4', [
        for (final r in activeRentals)
          div(
            classes: 'p-4 rounded-2xl border border-purple-500/20 bg-purple-500/5 hover:bg-purple-500/10 cursor-pointer transition-all flex items-center justify-between',
            events: {
              'click': (_) => s.setState(() {
                s.selectedRentalData = r;
                s.showRentalTrackerMap = true;
              }),
            },
            [
              div(classes: 'flex items-center gap-3', [
                div(classes: 'p-2 rounded-xl bg-purple-500/20', [
                  lIcon('car', cls: 'w-5 h-5 text-purple-400'),
                ]),
                div([
                  p(classes: 'text-xs font-semibold text-purple-400 uppercase tracking-wider', [
                    Component.text('Transit Rental • ${r['status']}'),
                  ]),
                  p(classes: 'font-bold text-sm text-zinc-200', [
                    Component.text('${r['brand']} ${r['model']}'),
                  ]),
                  p(classes: 'text-[10px] text-zinc-500 mt-0.5', [
                    Component.text('Click to view GPS route & tracking map'),
                  ]),
                ]),
              ]),
              lIcon('chevron-right', cls: 'w-5 h-5 text-purple-400'),
            ],
          ),
        for (final lease in activeLeases)
          div(
            classes: 'p-4 rounded-2xl border border-indigo-500/20 bg-indigo-500/5 hover:bg-indigo-500/10 cursor-pointer transition-all flex items-center justify-between',
            events: {
              'click': (_) => s.setState(() {
                s.activeTab = AppTab.transit;
                s.activeRentalCategory = RentalCategory.properties;
              }),
            },
            [
              div(classes: 'flex items-center gap-3', [
                div(classes: 'p-2 rounded-xl bg-indigo-500/20', [
                  lIcon('home', cls: 'w-5 h-5 text-indigo-400'),
                ]),
                div([
                  p(classes: 'text-xs font-semibold text-indigo-400 uppercase tracking-wider', [
                    Component.text('Real Estate Lease • ${lease.status}'),
                  ]),
                  p(classes: 'font-bold text-sm text-zinc-200', [
                    Component.text(lease.title),
                  ]),
                  p(classes: 'text-[10px] text-zinc-500 mt-0.5', [
                    Component.text('Click to manage lease agreement & chat'),
                  ]),
                ]),
              ]),
              lIcon('chevron-right', cls: 'w-5 h-5 text-indigo-400'),
            ],
          ),
      ]),
    ]);
  }
}
