import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import 'package:tranyx_web/components/map_picker.dart';
import 'package:tranyx_web/components/navigation_map.dart';
import 'package:tranyx_web/services/web_interop.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
import '../utils/geo_helper.dart';
import 'package:shared/shared.dart';

class JobsViewComponent extends StatelessComponent {
  final TranyxAppState state;
  const JobsViewComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final isNyxian = s.currentViewMode == AccountType.nyxian;

    if (isNyxian && s.activeJobPane == 'active') {
      s.activeJobPane = 'browse';
    }

    if (s.jobsView == JobsView.list) {
      final displayJobs = isNyxian ? _getFilteredJobs(s.availableJobs, s) : _getFilteredJobs(s.myJobs, s);

      return div(classes: 'flex flex-col md:flex-row gap-6 animate-fade-up', [
        // Left list pane
        div(classes: 'w-full md:w-80 flex-shrink-0 space-y-4', [
          div(classes: 'flex items-center justify-between', [
            h2(classes: 'text-xl font-bold', [
              Component.text(
                isNyxian
                    ? (s.activeJobPane == 'active'
                          ? 'Active Gigs'
                          : (s.activeJobPane == 'history' ? 'Past Gigs' : 'Available Gigs'))
                    : (s.activeJobPane == 'history' ? 'Past History' : 'My Postings'),
              ),
            ]),
            if (!isNyxian)
              button(
                classes:
                    'flex items-center gap-1 px-4 py-2 rounded-xl text-sm font-semibold text-white logo-gradient ${!s.canPostJob ? "opacity-60 cursor-not-allowed" : ""}',
                events: {
                  'click': (_) {
                    if (!s.canPostJob) {
                      s.showAppToast('Posting Locked', 'Normal accounts are limited to 1 active job.');
                    } else {
                      s.setState(() => s.jobsView = JobsView.create);
                    }
                  },
                },
                [lIcon('plus', cls: 'w-4 h-4'), Component.text(' New')],
              ),
          ]),

          // Beautiful premium Segmented Tab Switcher
          div(
            classes:
                'flex p-1 rounded-2xl ${isDark ? "bg-zinc-800/40" : "bg-zinc-100"} border ${isDark ? "border-zinc-800" : "border-zinc-200"}',
            [
              if (isNyxian) ...[
                button(
                  classes:
                      'flex-1 py-2.5 text-xs font-bold rounded-xl transition-all '
                      '${s.activeJobPane == 'browse' || (s.activeJobPane != 'history' && s.activeJobPane != 'applied') ? (isDark ? "bg-zinc-900 text-white shadow" : "bg-white text-zinc-900 shadow") : "text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"}',
                  events: {'click': (_) => s.setState(() => s.activeJobPane = 'browse')},
                  [Component.text('Browse Gigs')],
                ),
                button(
                  classes:
                      'flex-1 py-2.5 text-xs font-bold rounded-xl transition-all '
                      '${s.activeJobPane == 'applied' ? (isDark ? "bg-zinc-900 text-white shadow" : "bg-white text-zinc-900 shadow") : "text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"}',
                  events: {'click': (_) => s.setState(() => s.activeJobPane = 'applied')},
                  [Component.text('Applied')],
                ),
                button(
                  classes:
                      'flex-1 py-2.5 text-xs font-bold rounded-xl transition-all '
                      '${s.activeJobPane == 'history' ? (isDark ? "bg-zinc-900 text-white shadow" : "bg-white text-zinc-900 shadow") : "text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"}',
                  events: {'click': (_) => s.setState(() => s.activeJobPane = 'history')},
                  [Component.text('Completed')],
                ),
              ] else ...[
                button(
                  classes:
                      'flex-1 py-2.5 text-xs font-bold rounded-xl transition-all '
                      '${s.activeJobPane != 'history' ? (isDark ? "bg-zinc-900 text-white shadow" : "bg-white text-zinc-900 shadow") : "text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"}',
                  events: {'click': (_) => s.setState(() => s.activeJobPane = 'active')},
                  [Component.text('Active')],
                ),
                button(
                  classes:
                      'flex-1 py-2.5 text-xs font-bold rounded-xl transition-all '
                      '${s.activeJobPane == 'history' ? (isDark ? "bg-zinc-900 text-white shadow" : "bg-white text-zinc-900 shadow") : "text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"}',
                  events: {'click': (_) => s.setState(() => s.activeJobPane = 'history')},
                  [Component.text('Completed')],
                ),
              ],
            ],
          ),

          if (s.homeSearchQuery.isNotEmpty)
            div(
              classes: 'p-3 rounded-xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-between',
              [
                div(classes: 'flex items-center gap-2', [
                  lIcon('search', cls: 'w-4 h-4 text-indigo-400'),
                  span(classes: 'text-sm font-medium ${isDark ? "text-indigo-300" : "text-indigo-600"}', [
                    Component.text('Search: "${s.homeSearchQuery}"'),
                  ]),
                ]),
                button(
                  classes: 'text-xs font-semibold text-indigo-400 hover:text-indigo-300',
                  events: {
                    'click': (_) => s.setState(() {
                      s.homeSearchQuery = '';
                      s.activeJobFilter = 'Recommended';
                    }),
                  },
                  [Component.text('Clear')],
                ),
              ],
            ),

          // Filters for Nyxian browse pane
          if (isNyxian &&
              s.activeJobPane != 'my_gigs' &&
              s.activeJobPane != 'active' &&
              s.activeJobPane != 'history' &&
              s.activeJobPane != 'applied') ...[
            div(classes: 'flex gap-2 flex-wrap mb-2', [
              _filterChip('Recommended', s.activeJobFilter == 'Recommended', isDark, s),
              _filterChip('High Paying', s.activeJobFilter == 'High Paying', isDark, s),
              _filterChip('All', s.activeJobFilter == 'All', isDark, s),
            ]),
            // Geofence distance row
            div(classes: 'flex flex-wrap items-center gap-3 mb-2', [
              div(classes: 'flex items-center gap-2 text-xs', [
                span(
                  classes: 'font-semibold ${isDark ? "text-zinc-500" : "text-zinc-400"} flex items-center gap-1',
                  [
                    lIcon('map-pin', cls: 'w-3.5 h-3.5 text-purple-400'),
                    Component.text('Distance:'),
                  ],
                ),
                select(
                  classes:
                      'text-xs p-1.5 rounded-xl border ${isDark ? "bg-zinc-800 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
                  events: {
                    'change': (e) {
                      final val = getInputValue(e.target);
                      s.setState(() => s.geofenceRadius = double.parse(val));
                    },
                  },
                  [
                    option(value: '5.0', selected: s.geofenceRadius == 5.0, [Component.text('Within 5 km')]),
                    option(value: '15.0', selected: s.geofenceRadius == 15.0, [Component.text('Within 15 km')]),
                    option(
                      value: '30.0',
                      selected: s.geofenceRadius == 30.0,
                      [Component.text('Within 30 km')],
                    ),
                    option(
                      value: '50.0',
                      selected: s.geofenceRadius == 50.0,
                      [Component.text('Within 50 km')],
                    ),
                    option(
                      value: '100.0',
                      selected: s.geofenceRadius == 100.0,
                      [Component.text('Within 100 km')],
                    ),
                    option(
                      value: '9999.0',
                      selected: s.geofenceRadius >= 999.0,
                      [Component.text('Any Distance')],
                    ),
                  ],
                ),
              ]),
              // Remote toggle
              button(
                classes:
                    'flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold border transition-all cursor-pointer '
                    '${s.includeRemoteJobs ? "bg-indigo-600 border-indigo-500 text-white" : (isDark ? "bg-zinc-800 border-zinc-700 text-zinc-400 hover:bg-zinc-700" : "bg-zinc-100 border-zinc-200 text-zinc-500 hover:bg-zinc-200")}',
                events: {
                  'click': (_) => s.setState(() => s.includeRemoteJobs = !s.includeRemoteJobs),
                },
                [
                  lIcon('wifi', cls: 'w-3 h-3'),
                  Component.text('Remote Gigs'),
                ],
              ),
            ]),
          ],

          div(classes: 'space-y-3', [
            if (s.isLoadingJobs)
              div(classes: 'flex justify-center p-4', [lIcon('loader-2', cls: 'w-6 h-6 animate-spin text-indigo-500')])
            else if (s.jobsError != null)
              div(classes: 'p-4 text-sm text-red-500 bg-red-500/10 rounded-xl', [Component.text(s.jobsError!)])
            else if (isNyxian) ...[
              if (s.activeJobPane == 'browse')
                Builder(
                  builder: (context) {
                    final ongoingJobs = s.myJobs.where((j) {
                      final stat = (j['status'] as String?)?.toLowerCase() ?? '';
                      return stat != 'completed' && stat != 'closed' && stat != 'cancelled';
                    }).toList();
                    if (ongoingJobs.isEmpty) return div([]);
                    return div(
                      classes: 'mb-4 space-y-3 border-b pb-4 ${isDark ? "border-zinc-800" : "border-zinc-200"}',
                      [
                        div(classes: 'flex items-center gap-2 px-1', [
                          lIcon('pin', cls: 'w-3.5 h-3.5 text-purple-400 rotate-45'),
                          span(classes: 'text-[10px] font-bold uppercase tracking-wider text-purple-400', [
                            Component.text('Ongoing Gigs (Pinned)'),
                          ]),
                        ]),
                        div(classes: 'grid grid-cols-1 gap-2.5', [
                          for (final j in ongoingJobs) _pinnedOngoingCard(j, isDark, s),
                        ]),
                      ],
                    );
                  },
                ),
              if (displayJobs.isEmpty)
                div(classes: 'p-4 text-center text-zinc-500 text-sm', [
                  Component.text(
                    s.activeJobPane == 'applied'
                        ? 'You have not applied to any gigs yet.'
                        : (s.activeJobPane == 'active' || s.activeJobPane == 'history'
                              ? 'You have no active or completed gigs yet.'
                              : 'No available gigs match your filters.'),
                  ),
                ])
              else
                for (final j in displayJobs) _nyxianCard(j, isDark, s),
            ] else ...[
              _draftCard(isDark, s),
              if (displayJobs.isEmpty)
                div(classes: 'p-4 text-center text-zinc-500 text-sm', [
                  Component.text('No postings match your filters.'),
                ])
              else
                for (final j in displayJobs) _employerCard(j, isDark, s),
            ],
          ]),
        ]),

        // Right detail placeholder
        div(
          classes:
              'flex-1 hidden md:flex items-center justify-center rounded-3xl border ${isDark ? "border-zinc-800 bg-zinc-900/40" : "border-zinc-200 bg-zinc-50"}',
          [
            div(classes: 'text-center', [
              lIcon('briefcase', cls: 'w-12 h-12 mx-auto mb-3 ${isDark ? "text-zinc-700" : "text-zinc-300"}'),
              p(classes: '${isDark ? "text-zinc-600" : "text-zinc-400"} text-sm', [
                Component.text('Select a job to view details'),
              ]),
            ]),
          ],
        ),
      ]);
    }

    if (s.jobsView == JobsView.create) return _CreateJob(state: s);
    if (s.jobsView == JobsView.details) return _JobDetails(state: s);
    if (s.jobsView == JobsView.apply) return _ApplyJob(state: s);
    if (s.jobsView == JobsView.review) return _ReviewApplicants(state: s);
    if (s.jobsView == JobsView.success) return _SuccessScreen(state: s);
    return div([]);
  }

  List<Map<String, dynamic>> _getFilteredJobs(List<Map<String, dynamic>> jobs, TranyxAppState s) {
    final isNyxian = s.currentViewMode == AccountType.nyxian;
    final isBrowsePane = isNyxian && s.activeJobPane == 'browse';
    final myUid = s.userProfile?.uid ?? SessionStorage.uid ?? '';

    // Apply the active tab/pane filter
    if (isNyxian) {
      if (s.activeJobPane == 'history') {
        jobs = s.myJobs.where((j) {
          final isWorker = j['acceptedApplicantId'] == myUid;
          final stat = (j['status'] as String?)?.toLowerCase() ?? 'open';
          final isTerminal = stat == 'completed' || stat == 'closed' || stat == 'cancelled';
          return isWorker && isTerminal;
        }).toList();
      } else if (s.activeJobPane == 'active') {
        jobs = s.myJobs.where((j) {
          final isWorker = j['acceptedApplicantId'] == myUid;
          final stat = (j['status'] as String?)?.toLowerCase() ?? 'open';
          final isActive = stat != 'completed' && stat != 'closed' && stat != 'cancelled';
          return isWorker && isActive;
        }).toList();
      } else if (s.activeJobPane == 'applied') {
        jobs = s.appliedJobs.where((j) {
          final acceptedId = j['acceptedApplicantId'] as String?;
          // Display only pending or rejected applications (not chosen)
          return acceptedId != myUid;
        }).toList();
      } else {
        jobs = s.availableJobs;
      }
    } else {
      if (s.activeJobPane == 'history') {
        jobs = s.myJobs.where((j) {
          final isCreator = j['creatorId'] == myUid;
          final stat = (j['status'] as String?)?.toLowerCase() ?? 'open';
          final isTerminal = stat == 'completed' || stat == 'closed' || stat == 'cancelled' || stat == 'done';
          return isCreator && isTerminal;
        }).toList();
      } else {
        jobs = s.myJobs.where((j) {
          final isCreator = j['creatorId'] == myUid;
          final stat = (j['status'] as String?)?.toLowerCase() ?? 'open';
          final isActive = stat != 'completed' && stat != 'closed' && stat != 'cancelled' && stat != 'done';
          return isCreator && isActive;
        }).toList();
      }
    }

    // Always apply home search query first if present
    if (s.homeSearchQuery.isNotEmpty) {
      final q = s.homeSearchQuery.toLowerCase();
      jobs = jobs.where((j) {
        final title = (j['title'] as String?)?.toLowerCase() ?? '';
        final desc = (j['description'] as String?)?.toLowerCase() ?? '';
        final cat = (j['category'] as String?)?.toLowerCase() ?? '';
        final catLabel = (j['categoryLabel'] as String?)?.toLowerCase() ?? '';
        return title.contains(q) || desc.contains(q) || cat.contains(q) || catLabel.contains(q);
      }).toList();
    }

    if (!isNyxian) {
      return jobs;
    }

    // ── Geofence + Remote filter (browse pane only) ──────────────
    if (isBrowsePane) {
      jobs = jobs.where((j) {
        final locationType = (j['locationType'] as String?)?.toLowerCase() ?? 'on-site';
        final isRemote = locationType == 'remote';

        if (isRemote) {
          // Remote gigs: show only when includeRemoteJobs is enabled
          return s.includeRemoteJobs;
        } else {
          // On-site gigs: apply geofence distance filter
          final jobLat = (j['latitude'] as num?)?.toDouble() ?? (j['pickupLat'] as num?)?.toDouble();
          final jobLng = (j['longitude'] as num?)?.toDouble() ?? (j['pickupLng'] as num?)?.toDouble();
          if (jobLat == null || jobLng == null) {
            // No coordinates stored — include if radius is broad enough
            return s.geofenceRadius >= 999.0;
          }
          if (s.geofenceRadius < 999.0) {
            final dist = calculateDistance(s.userLatitude, s.userLongitude, jobLat, jobLng);
            return dist <= s.geofenceRadius;
          }
          return true;
        }
      }).toList();

      // Sort: latest to oldest
      jobs.sort((a, b) {
        final aTime = a['createdAt'] as int? ?? 0;
        final bTime = b['createdAt'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });
    }

    final result = <Map<String, dynamic>>[];
    if (!isBrowsePane) {
      result.addAll(jobs);
    } else if (s.activeJobFilter == 'All') {
      result.addAll(jobs);
    } else if (s.activeJobFilter == 'Recommended') {
      var skills = s.userProfile?.skills ?? [];
      if (skills.isEmpty) {
        skills = ['Electrical', 'Plumbing', 'Painting', 'Carpentry', 'Cleaning', 'IT'];
      }
      result.addAll(
        jobs.where((j) {
          final cat = (j['category'] as String?)?.toLowerCase() ?? '';
          final catLabel = (j['categoryLabel'] as String?)?.toLowerCase() ?? '';
          final desc = (j['description'] as String?)?.toLowerCase() ?? '';
          final title = (j['title'] as String?)?.toLowerCase() ?? '';
          return skills.any((skill) {
            final sLower = skill.toLowerCase();
            return cat.contains(sLower) || catLabel.contains(sLower) || desc.contains(sLower) || title.contains(sLower);
          });
        }),
      );
    } else if (s.activeJobFilter == 'High Paying') {
      result.addAll(
        jobs.where((j) {
          final val = (j['pricingValue'] as num?)?.toDouble() ?? 0.0;
          return val >= 1000;
        }),
      );
    } else {
      result.addAll(jobs);
    }

    // Sort all final listings from latest to oldest
    result.sort((a, b) {
      final aTime = a['createdAt'] as int? ?? 0;
      final bTime = b['createdAt'] as int? ?? 0;
      return bTime.compareTo(aTime);
    });

    return result;
  }

  Component _filterChip(String label, bool active, bool isDark, TranyxAppState s) {
    final cls = active
        ? 'bg-indigo-600 text-white'
        : (isDark ? 'bg-zinc-800 text-zinc-400 hover:bg-zinc-700' : 'bg-zinc-100 text-zinc-600 hover:bg-zinc-200');
    return button(
      classes: 'px-3 py-1.5 rounded-lg text-xs font-semibold $cls transition-colors cursor-pointer',
      events: {'click': (_) => s.setState(() => s.activeJobFilter = label)},
      [Component.text(label)],
    );
  }

  Component _draftCard(bool isDark, TranyxAppState s) {
    final canPost = s.canPostJob;
    if (!canPost) {
      final activeJobTitle = s.firstActiveJob?['title'] as String? ?? 'Active Job';
      return div(
        classes:
            'w-full p-6 rounded-2xl border-2 border-dashed ${isDark ? "border-zinc-800 bg-zinc-950/40" : "border-zinc-200 bg-zinc-50/50"} flex flex-col items-center justify-center gap-3 text-center',
        [
          div(
            classes:
                'w-10 h-10 rounded-full bg-amber-500/15 text-amber-500 flex items-center justify-center border border-amber-500/20',
            [lIcon('lock', cls: 'w-5 h-5')],
          ),
          h4(classes: 'text-sm font-bold ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
            Component.text('Posting Locked'),
          ]),
          p(classes: 'text-xs max-w-md ${isDark ? "text-zinc-500" : "text-zinc-400"} leading-relaxed', [
            Component.text(
              'Normal accounts are limited to 1 active job at a time. Please complete your current ongoing job ("$activeJobTitle") to unlock posting new gigs.',
            ),
          ]),
          button(
            classes:
                'mt-1 px-4 py-2 rounded-xl text-xs font-semibold text-amber-400 bg-amber-500/10 border border-amber-500/20 hover:bg-amber-500/20 transition-colors cursor-pointer',
            events: {
              'click': (_) {
                final activeJob = s.firstActiveJob;
                if (activeJob != null) {
                  s.selectJobAndLoadDetails(activeJob);
                }
              },
            },
            [Component.text('View Ongoing Job')],
          ),
        ],
      );
    }

    return button(
      classes:
          'w-full p-4 rounded-2xl border-2 border-dashed ${isDark ? "border-zinc-700 hover:border-indigo-500" : "border-zinc-300 hover:border-indigo-400"} transition-colors flex items-center justify-center gap-2 ${isDark ? "text-zinc-500 hover:text-indigo-400" : "text-zinc-400 hover:text-indigo-500"}',
      events: {'click': (_) => s.setState(() => s.jobsView = JobsView.create)},
      [lIcon('plus', cls: 'w-5 h-5'), Component.text('Create New Listing')],
    );
  }

  Component _employerCard(Map<String, dynamic> j, bool isDark, TranyxAppState s) {
    var title = j['title'] as String? ?? '';
    if (title.isEmpty || title == 'Untitled') {
      final category = j['category'] as String? ?? '';
      final categoryLabel = j['categoryLabel'] as String? ?? '';
      final nameToNormalize = categoryLabel.isNotEmpty ? categoryLabel : category;
      title = nameToNormalize.isNotEmpty ? normalizeCategoryName(nameToNormalize) : 'Untitled Gig';
    }
    final status = j['status'] as String? ?? 'Open';
    final applicants = (j['applicantCount'] as int?) ?? 0;
    final pricingValue = (j['pricingValue'] as num?)?.toDouble() ?? 0.0;
    final pricingType = j['pricingType'] as String? ?? '';
    final rate = pricingValue > 0
        ? '₱ ${pricingValue.toStringAsFixed(0)}${pricingType.isNotEmpty ? " / $pricingType" : ""}'
        : 'Negotiable';
    final category = j['category'] as String? ?? '';
    final categoryLabel = j['categoryLabel'] as String? ?? '';
    final categoryNameNormalized = normalizeCategoryName(category.isNotEmpty ? category : categoryLabel);
    final isActive = status == 'Active' || status == 'Open';
    final statusCls = status == 'Completed'
        ? 'bg-zinc-700/50 text-zinc-400'
        : (isActive ? 'bg-green-500/20 text-green-400' : 'bg-amber-500/20 text-amber-400');
    final cardCls = isDark
        ? 'bg-zinc-900 border-zinc-800 hover:border-zinc-700'
        : 'bg-white border-zinc-200 shadow-sm hover:shadow-md';
    return div(classes: 'p-4 rounded-2xl border transition-all $cardCls', [
      div(classes: 'flex items-start justify-between mb-3', [
        div(classes: 'flex-1 pr-2', [
          p(classes: 'font-semibold text-sm', [Component.text(title)]),
          if (categoryNameNormalized.isNotEmpty)
            p(classes: 'text-xs text-zinc-550 dark:text-zinc-400 font-medium mt-0.5', [
              Component.text(categoryNameNormalized),
            ]),
        ]),
        span(classes: 'px-2 py-0.5 rounded text-[10px] font-bold $statusCls', [Component.text(status.toUpperCase())]),
      ]),
      div(classes: 'flex items-center gap-2 mb-2', [
        span(classes: 'text-xs ${isDark ? "text-indigo-400" : "text-indigo-600"} font-semibold', [
          Component.text(rate),
        ]),
        if (categoryLabel.isNotEmpty)
          span(
            classes:
                'px-2 py-0.5 rounded text-[9px] font-bold ${isDark ? "bg-zinc-800 text-zinc-555" : "bg-zinc-100 text-zinc-500"}',
            [Component.text(categoryLabel)],
          ),
      ]),
      if (status == 'Completed' && pricingValue > 0)
        Builder(
          builder: (context) {
            final txFee = pricingValue * 0.07;
            final convFee = pricingValue * 0.03;
            final totalPaid = pricingValue + txFee + convFee;
            return div(
              classes:
                  'mt-2.5 mb-2.5 p-3 rounded-xl border ${isDark ? "border-zinc-800/80 bg-zinc-950/20" : "border-zinc-150 bg-zinc-50/50"} space-y-1',
              [
                div(classes: 'flex justify-between items-center text-[10px] text-zinc-500', [
                  span([Component.text('Base Gig Price:')]),
                  span(classes: 'font-semibold ${isDark ? "text-zinc-350" : "text-zinc-650"}', [
                    Component.text('₱ ${pricingValue.toStringAsFixed(2)}'),
                  ]),
                ]),
                div(classes: 'flex justify-between items-center text-[10px] text-zinc-505', [
                  span([Component.text('Transaction Fee (7%):')]),
                  span(classes: 'font-semibold text-amber-500', [Component.text('+ ₱ ${txFee.toStringAsFixed(2)}')]),
                ]),
                div(
                  classes:
                      'flex justify-between items-center text-[10px] text-zinc-505 border-b ${isDark ? "border-zinc-800/40" : "border-zinc-200/40"} pb-1',
                  [
                    span([Component.text('Convenience Fee (3%):')]),
                    span(classes: 'font-semibold text-amber-500', [
                      Component.text('+ ₱ ${convFee.toStringAsFixed(2)}'),
                    ]),
                  ],
                ),
                div(classes: 'flex justify-between items-center pt-0.5', [
                  span(classes: 'text-[10px] font-bold text-indigo-400', [Component.text('Total Paid:')]),
                  span(classes: 'text-xs font-black logo-gradient-text', [
                    Component.text('₱ ${totalPaid.toStringAsFixed(2)}'),
                  ]),
                ]),
              ],
            );
          },
        ),
      div(classes: 'flex items-center justify-between', [
        div(classes: 'flex items-center gap-2 text-xs', [
          div(classes: 'flex items-center gap-1 text-zinc-500', [
            lIcon('users', cls: 'w-3 h-3'),
            Component.text(' $applicants applicants'),
          ]),
          if (applicants > 0 && (status == 'Open' || status == 'Active'))
            span(
              classes: 'flex h-2 w-2 relative',
              [
                span(
                  classes: 'animate-ping absolute inline-flex h-full w-full rounded-full bg-indigo-400 opacity-75',
                  [],
                ),
                span(classes: 'relative inline-flex rounded-full h-2 w-2 bg-indigo-500', []),
              ],
            ),
        ]),
        button(
          classes: 'px-3 py-1.5 rounded-lg text-xs font-semibold logo-gradient text-white',
          events: {'click': (_) => s.selectJobAndLoadDetails(j)},
          [Component.text('Manage')],
        ),
      ]),
    ]);
  }

  Component _nyxianCard(Map<String, dynamic> j, bool isDark, TranyxAppState s) {
    var title = j['title'] as String? ?? '';
    if (title.isEmpty || title == 'Untitled') {
      final category = j['category'] as String? ?? '';
      final categoryLabel = j['categoryLabel'] as String? ?? '';
      final nameToNormalize = categoryLabel.isNotEmpty ? categoryLabel : category;
      title = nameToNormalize.isNotEmpty ? normalizeCategoryName(nameToNormalize) : 'Untitled Gig';
    }
    final status = j['status'] as String? ?? 'Open';
    final pricingValue = (j['pricingValue'] as num?)?.toDouble() ?? 0.0;
    final pricingType = j['pricingType'] as String? ?? '';
    final rate = pricingValue > 0
        ? '₱ ${pricingValue.toStringAsFixed(0)}${pricingType.isNotEmpty ? " / $pricingType" : ""}'
        : 'Negotiable';
    final locationType = j['locationType'] as String? ?? 'Remote';
    final dateReq = j['dateRequirement'] as String? ?? 'Flexible';
    final isUrgent = dateReq == 'On Date';
    final isRemote = locationType.toLowerCase() == 'remote';
    final category = j['category'] as String? ?? '';
    final categoryLabel = j['categoryLabel'] as String? ?? '';
    final categoryNameNormalized = normalizeCategoryName(category.isNotEmpty ? category : categoryLabel);

    // Compute distance for on-site gigs
    String? distanceLabel;
    if (!isRemote) {
      final jobLat = (j['latitude'] as num?)?.toDouble() ?? (j['pickupLat'] as num?)?.toDouble();
      final jobLng = (j['longitude'] as num?)?.toDouble() ?? (j['pickupLng'] as num?)?.toDouble();
      if (jobLat != null && jobLng != null) {
        final dist = calculateDistance(s.userLatitude, s.userLongitude, jobLat, jobLng);
        distanceLabel = dist < 1.0 ? '${(dist * 1000).round()} m away' : '${dist.toStringAsFixed(1)} km away';
      }
    }

    final badgeText = status == 'Open' ? dateReq.toUpperCase() : status.toUpperCase();
    final badgeCls = status == 'In Progress'
        ? 'bg-green-500/20 text-green-400 animate-pulse'
        : status == 'Completed'
        ? 'bg-zinc-700/50 text-zinc-400'
        : (isUrgent ? 'bg-red-500/20 text-red-400' : 'bg-zinc-700 text-zinc-300');

    String? appliedStatusText;
    String? appliedStatusCls;
    if (s.activeJobPane == 'applied') {
      final acceptedId = j['acceptedApplicantId'] as String?;
      final jobStatus = (j['status'] as String? ?? 'Open').toLowerCase();
      final myUid = s.userProfile?.uid ?? '';

      if (acceptedId == myUid) {
        appliedStatusText = jobStatus == 'completed' ? 'ACCEPTED (COMPLETED)' : 'ACCEPTED';
        appliedStatusCls = 'bg-green-500/20 text-green-400';
      } else if (acceptedId != null) {
        appliedStatusText = 'NOT CHOSEN';
        appliedStatusCls = 'bg-red-500/20 text-red-400';
      } else if (jobStatus == 'closed' || jobStatus == 'cancelled') {
        appliedStatusText = 'NOT CHOSEN';
        appliedStatusCls = 'bg-red-500/20 text-red-400';
      } else {
        appliedStatusText = 'PENDING';
        appliedStatusCls = 'bg-indigo-500/20 text-indigo-400';
      }
    }

    final cardCls = isDark
        ? 'bg-zinc-900 border-zinc-800 hover:border-zinc-700'
        : 'bg-white border-zinc-200 shadow-sm hover:shadow-md';
    return div(classes: 'p-4 rounded-2xl border transition-all $cardCls', [
      div(classes: 'flex items-start justify-between mb-3', [
        div(classes: 'flex-1 pr-2', [
          p(classes: 'font-semibold text-sm', [Component.text(title)]),
          if (categoryNameNormalized.isNotEmpty)
            p(classes: 'text-xs text-zinc-550 dark:text-zinc-400 font-medium mt-0.5', [
              Component.text(categoryNameNormalized),
            ]),
        ]),
        div(classes: 'flex flex-col items-end gap-1.5', [
          span(classes: 'px-2 py-0.5 rounded text-[10px] font-bold $badgeCls', [Component.text(badgeText)]),
          if (appliedStatusText != null)
            span(
              classes: 'px-2 py-0.5 rounded text-[9px] font-bold $appliedStatusCls',
              [Component.text(appliedStatusText)],
            ),
        ]),
      ]),
      if (status == 'Completed' && pricingValue > 0)
        Builder(
          builder: (context) {
            final commFee = pricingValue * 0.03;
            final netPayout = pricingValue - commFee;
            return div(
              classes:
                  'mt-2.5 mb-2.5 p-3 rounded-xl border ${isDark ? "border-zinc-800/80 bg-zinc-950/20" : "border-zinc-150 bg-zinc-50/50"} space-y-1',
              [
                div(classes: 'flex justify-between items-center text-[10px] text-zinc-500', [
                  span([Component.text('Base Payout:')]),
                  span(classes: 'font-semibold ${isDark ? "text-zinc-350" : "text-zinc-650"}', [
                    Component.text('₱ ${pricingValue.toStringAsFixed(2)}'),
                  ]),
                ]),
                div(
                  classes:
                      'flex justify-between items-center text-[10px] text-zinc-555 border-b ${isDark ? "border-zinc-800/40" : "border-zinc-200/40"} pb-1',
                  [
                    span([Component.text('Platform Commission (3%):')]),
                    span(classes: 'font-semibold text-red-400', [Component.text('− ₱ ${commFee.toStringAsFixed(2)}')]),
                  ],
                ),
                div(classes: 'flex justify-between items-center pt-0.5', [
                  span(classes: 'text-[10px] font-bold text-indigo-400', [Component.text('Net Earnings:')]),
                  span(classes: 'text-xs font-black logo-gradient-text', [
                    Component.text('₱ ${netPayout.toStringAsFixed(2)}'),
                  ]),
                ]),
              ],
            );
          },
        ),
      div(classes: 'flex items-center justify-between', [
        div(classes: 'flex items-center gap-3 text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
          span(classes: 'font-bold text-indigo-400 text-sm', [Component.text(rate)]),
          if (categoryLabel.isNotEmpty)
            span(
              classes:
                  'px-2 py-0.5 rounded text-[9px] font-bold ${isDark ? "bg-zinc-800 text-zinc-555" : "bg-zinc-100 text-zinc-500"}',
              [Component.text(categoryLabel)],
            ),
          if (isRemote)
            span(
              classes:
                  'flex items-center gap-1 px-2 py-0.5 rounded-lg text-[10px] font-bold bg-indigo-500/15 text-indigo-400',
              [lIcon('wifi', cls: 'w-3 h-3'), Component.text('Remote')],
            )
          else ...[
            div(
              classes: 'flex items-center gap-1',
              [lIcon('map-pin', cls: 'w-3 h-3'), Component.text(locationType)],
            ),
            if (distanceLabel != null)
              span(
                classes:
                    'flex items-center gap-1 px-2 py-0.5 rounded-lg text-[10px] font-semibold bg-purple-500/15 text-purple-400',
                [lIcon('navigation', cls: 'w-3 h-3'), Component.text(distanceLabel)],
              ),
          ],
        ]),
        button(
          classes: 'px-3 py-1.5 rounded-lg text-xs font-semibold logo-gradient text-white',
          events: {'click': (_) => s.selectJobAndLoadDetails(j)},
          [Component.text('View')],
        ),
      ]),
    ]);
  }

  Component _pinnedOngoingCard(Map<String, dynamic> j, bool isDark, TranyxAppState s) {
    var title = j['title'] as String? ?? '';
    if (title.isEmpty || title == 'Untitled') {
      final category = j['category'] as String? ?? '';
      final categoryLabel = j['categoryLabel'] as String? ?? '';
      final nameToNormalize = categoryLabel.isNotEmpty ? categoryLabel : category;
      title = nameToNormalize.isNotEmpty ? normalizeCategoryName(nameToNormalize) : 'Untitled Gig';
    }
    final status = j['status'] as String? ?? 'In Progress';
    final pricingValue = (j['pricingValue'] as num?)?.toDouble() ?? 0.0;
    final pricingType = j['pricingType'] as String? ?? '';
    final rate = pricingValue > 0
        ? '₱ ${pricingValue.toStringAsFixed(0)}${pricingType.isNotEmpty ? " / $pricingType" : ""}'
        : 'Negotiable';
    final category = j['category'] as String? ?? '';
    final categoryLabel = j['categoryLabel'] as String? ?? '';
    final categoryNameNormalized = normalizeCategoryName(category.isNotEmpty ? category : categoryLabel);

    final cardCls = isDark
        ? 'bg-purple-950/20 border-purple-500/30 hover:border-purple-500/50 text-white'
        : 'bg-purple-50/50 border-purple-200 hover:border-purple-300 text-purple-950 shadow-sm';

    return div(
      classes: 'p-3.5 rounded-2xl border transition-all flex items-center justify-between $cardCls',
      [
        div(classes: 'flex-1 min-w-0 pr-3', [
          div(classes: 'flex items-center gap-2 flex-wrap mb-1', [
            span(
              classes:
                  'px-2 py-0.5 rounded text-[9px] font-extrabold uppercase bg-purple-500/10 text-purple-400 border border-purple-500/20 animate-pulse',
              [Component.text(status.toUpperCase())],
            ),
            if (categoryNameNormalized.isNotEmpty)
              span(
                classes:
                    'px-1.5 py-0.5 rounded text-[9px] font-semibold bg-zinc-500/10 ${isDark ? "text-zinc-400" : "text-zinc-650"}',
                [Component.text(categoryNameNormalized)],
              ),
          ]),
          p(classes: 'font-semibold text-xs truncate', [Component.text(title)]),
          if (categoryNameNormalized.isNotEmpty)
            p(classes: 'text-[10px] text-zinc-500 mt-0.5 truncate', [
              Component.text(categoryNameNormalized),
            ]),
        ]),
        div(classes: 'flex items-center gap-3', [
          span(classes: 'text-xs font-bold text-purple-400', [Component.text(rate)]),
          button(
            classes:
                'px-2.5 py-1.5 rounded-xl text-xs font-bold bg-purple-500 text-white hover:bg-purple-600 transition-colors',
            events: {'click': (_) => s.selectJobAndLoadDetails(j)},
            [Component.text('Go')],
          ),
        ]),
      ],
    );
  }
}

// ── Job Details ───────────────────────────────────────────────
class _JobDetails extends StatelessComponent {
  final TranyxAppState state;
  const _JobDetails({required this.state});

  int _getStepperStep(String status, String? acceptedId) {
    final lStatus = status.toLowerCase();
    if (lStatus == 'completed' || lStatus == 'done' || lStatus == 'arrived_dropoff') {
      return 4;
    }
    if (lStatus == 'in progress' ||
        lStatus == 'in_progress' ||
        lStatus == 'ongoing' ||
        lStatus == 'heading_to_pickup' ||
        lStatus == 'arrived_pickup' ||
        lStatus == 'paid_cashier' ||
        lStatus == 'in_transit') {
      return 3;
    }
    if (acceptedId != null && acceptedId.isNotEmpty) {
      return 2;
    }
    return 1; // Default/Applied
  }

  Component _jobStepper(int currentStep, bool isDark) {
    final steps = ['Applied', 'Hired', 'In Progress', 'Complete'];
    return div(
      classes:
          'w-full py-4 px-6 rounded-3xl border ${isDark ? "bg-zinc-900/50 border-zinc-800" : "bg-zinc-50 border-zinc-200"} flex items-center justify-between gap-2 overflow-x-auto',
      [
        for (int i = 0; i < steps.length; i++) ...[
          // Step node
          div(classes: 'flex items-center gap-2.5', [
            div(
              classes:
                  'w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold transition-all duration-300 '
                  '${(i + 1) <= currentStep ? "bg-indigo-500 text-white shadow-md shadow-indigo-500/20" : (isDark ? "bg-zinc-800 text-zinc-500 border border-zinc-700" : "bg-zinc-200 text-zinc-400 border border-zinc-300")}',
              [if ((i + 1) < currentStep) lIcon('check', cls: 'w-4 h-4 text-white') else Component.text('${i + 1}')],
            ),
            span(
              classes:
                  'text-xs font-semibold whitespace-nowrap transition-colors duration-300 '
                  '${(i + 1) <= currentStep ? (isDark ? "text-zinc-100" : "text-zinc-900") : (isDark ? "text-zinc-650" : "text-zinc-400")}',
              [Component.text(steps[i])],
            ),
          ]),
          // Connector line (except after the last step)
          if (i < steps.length - 1)
            div(
              classes:
                  'flex-1 h-0.5 min-w-[20px] transition-all duration-500 '
                  '${(i + 1) < currentStep ? "bg-indigo-500" : (isDark ? "bg-zinc-800" : "bg-zinc-200")}',
              [],
            ),
        ],
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final job = s.selectedJob;
    final isNyxian = s.selectedJobData?['creatorId'] != (s.userProfile?.uid ?? SessionStorage.uid);
    final status = s.selectedJobData?['status'] as String? ?? 'Open';
    final catName = (s.selectedJobData?['category'] as String? ?? '').toLowerCase();
    final cat = JobCategory.values.firstWhere(
      (e) => e.name.toLowerCase() == catName || e.label.toLowerCase() == catName,
      orElse: () => JobCategory.others,
    );
    final hasTracker =
        s.hasTracker ||
        s.selectedJobData?['hasTracker'] == true ||
        s.selectedJobData?['hasTracker'] == 'true' ||
        cat.hasTracker;

    if (job == null) return div([]);

    final applicantUids = List<String>.from(s.selectedJobData?['applicantUids'] as List? ?? []);
    final hasApplied = applicantUids.contains(s.userProfile?.uid);

    final reportedBy = List<String>.from(s.selectedJobData?['reportedByUids'] as List? ?? []);
    final hasReported = reportedBy.contains(s.userProfile?.uid);

    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    final acceptedId = s.selectedJobData?['acceptedApplicantId'] as String?;
    final currentStep = _getStepperStep(status, acceptedId);

    return div(classes: 'space-y-6 animate-fade-up', [
      subViewHeader(
        title: job.title,
        isDark: isDark,
        onBack: () => s.exitJobDetails(),
      ),

      _jobStepper(currentStep, isDark),

      // Image Carousel above content
      if (s.selectedJobData?['imageUrls'] != null && (s.selectedJobData!['imageUrls'] as List).isNotEmpty)
        Builder(
          builder: (context) {
            final urls = List<String>.from(s.selectedJobData!['imageUrls'] as List);
            final activeIdx = s.selectedJobImageCarouselIndex;
            return div(
              classes:
                  'w-full h-72 rounded-3xl overflow-hidden relative group border ${isDark ? "border-zinc-800 bg-zinc-950" : "border-zinc-200 bg-zinc-100"} shadow-xl',
              [
                img(
                  src: urls[activeIdx],
                  classes:
                      'w-full h-full object-cover transition-all duration-700 ease-in-out transform scale-100 hover:scale-105',
                ),
                div(
                  [],
                  classes:
                      'absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-black/20 pointer-events-none',
                ),
                if (urls.length > 1)
                  button(
                    classes:
                        'absolute left-4 top-1/2 -translate-y-1/2 w-10 h-10 rounded-full flex items-center justify-center bg-black/40 hover:bg-black/60 text-white backdrop-blur-md transition-all opacity-0 group-hover:opacity-100 border border-white/10 cursor-pointer',
                    events: {
                      'click': (_) => s.setState(() {
                        s.selectedJobImageCarouselIndex = (activeIdx - 1 + urls.length) % urls.length;
                      }),
                    },
                    [lIcon('chevron-left', cls: 'w-6 h-6')],
                  ),
                if (urls.length > 1)
                  button(
                    classes:
                        'absolute right-4 top-1/2 -translate-y-1/2 w-10 h-10 rounded-full flex items-center justify-center bg-black/40 hover:bg-black/60 text-white backdrop-blur-md transition-all opacity-0 group-hover:opacity-100 border border-white/10 cursor-pointer',
                    events: {
                      'click': (_) => s.setState(() {
                        s.selectedJobImageCarouselIndex = (activeIdx + 1) % urls.length;
                      }),
                    },
                    [lIcon('chevron-right', cls: 'w-6 h-6')],
                  ),
                div(
                  classes:
                      'absolute bottom-4 left-1/2 -translate-x-1/2 flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-black/40 backdrop-blur-md border border-white/10',
                  [
                    for (var i = 0; i < urls.length; i++)
                      div(
                        [],
                        classes:
                            'h-1.5 rounded-full transition-all duration-300 '
                            '${i == activeIdx ? "w-4 bg-indigo-400" : "w-1.5 bg-white/40"}',
                      ),
                  ],
                ),
              ],
            );
          },
        ),

      // Job meta chips
      div(classes: 'flex flex-wrap gap-2', [
        tagChip(job.rate, isDark),
        tagChip(job.status, isDark),
        tagChip(job.urgency, isDark),
        if (s.selectedJobData?['locationType'] != null) tagChip(s.selectedJobData!['locationType'] as String, isDark),
        if (s.selectedJobData?['employmentType'] != null)
          tagChip(s.selectedJobData!['employmentType'] as String, isDark),
        if (s.selectedJobData?['timePreference'] != null)
          tagChip(s.selectedJobData!['timePreference'] as String, isDark),
        if ((s.selectedJobData?['reportCount'] as int? ?? 0) > 0)
          span(
            classes:
                'px-3 py-1 rounded-full text-xs font-semibold bg-red-500/10 text-red-500 border border-red-500/20 flex items-center gap-1',
            [lIcon('flag', cls: 'w-3 h-3'), Component.text('${s.selectedJobData!['reportCount']} Reports')],
          ),
      ]),

      if (isNyxian)
        button(
          classes:
              'w-full p-4 rounded-2xl border border-yellow-500/30 bg-yellow-500/10 flex items-start gap-3 text-left hover:bg-yellow-500/20 transition-colors',
          events: {'click': (_) => s.checkJobAuthenticity()},
          [
            lIcon('shield-alert', cls: 'w-5 h-5 text-yellow-500 flex-shrink-0 mt-0.5'),
            div(classes: 'flex-1', [
              div(classes: 'flex items-center justify-between', [
                p(classes: 'font-bold text-yellow-500 text-sm', [Component.text('Check Authenticity')]),
                lIcon('chevron-right', cls: 'w-4 h-4 text-yellow-500'),
              ]),
              p(classes: 'text-xs mt-1 ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                Component.text(
                  'Click to get an AI-powered authenticity score based on platform data, description, and intent.',
                ),
              ]),
            ]),
          ],
        ),

      Builder(
        builder: (context) {
          final acceptedId = s.selectedJobData?['acceptedApplicantId'] as String?;
          final isAccepted = acceptedId == s.userProfile?.uid;
          final isChatActive = status != 'Completed' && status != 'Complete' && status != 'Cancelled';
          final creatorName =
              (s.selectedJobCreatorProfile?['name'] ??
                      s.selectedJobCreatorProfile?['displayName'] ??
                      s.selectedJobData?['creatorName'])
                  as String? ??
              'Employer';
          final creatorPhotoUrl =
              (s.selectedJobCreatorProfile?['photoUrl'] ?? s.selectedJobData?['creatorPhotoUrl']) as String? ?? '';
          final creatorInitials = creatorName.isNotEmpty ? creatorName[0].toUpperCase() : '?';

          if (isNyxian) {
            // Nyxian View: Show Employer Card
            return div(classes: 'space-y-3', [
              // Employer info card
              button(
                classes:
                    'w-full p-4 rounded-2xl border $cardCls flex items-center justify-between text-left hover:opacity-80 transition-opacity',
                events: {'click': (_) => s.viewEmployerProfile(s.selectedJobData!['creatorId'] as String)},
                [
                  div(classes: 'flex items-center gap-3', [
                    div(
                      classes:
                          'w-10 h-10 rounded-full flex items-center justify-center bg-indigo-600 flex-shrink-0 overflow-hidden',
                      [
                        if (creatorPhotoUrl.isNotEmpty)
                          img(
                            src: creatorPhotoUrl,
                            classes: 'w-full h-full object-cover',
                          )
                        else
                          span(classes: 'text-sm font-bold text-white', [
                            Component.text(creatorInitials),
                          ]),
                      ],
                    ),
                    div([
                      p(classes: 'font-semibold text-sm', [
                        Component.text(creatorName),
                      ]),
                      p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                        Component.text('Employer'),
                      ]),
                    ]),
                  ]),
                  lIcon('chevron-right', cls: 'w-4 h-4 ${isDark ? "text-zinc-600" : "text-zinc-400"}'),
                ],
              ),
              // Chat with Employer button
              if (acceptedId != null && isAccepted && isChatActive)
                button(
                  classes:
                      'w-full py-3.5 rounded-2xl font-bold text-white logo-gradient hover:opacity-95 transition-opacity flex items-center justify-center gap-2 shadow-lg shadow-indigo-500/20 relative',
                  events: {'click': (_) => s.openChat(s.selectedJobData!['id'] as String)},
                  [
                    lIcon('message-square', cls: 'w-5 h-5'),
                    Component.text('Chat with Employer'),
                    if (s.getUnreadChatCount(s.selectedJobData!['id'] as String) > 0)
                      span(
                        classes:
                            'absolute -top-1.5 -right-1.5 px-2 py-0.5 text-xs font-black text-white bg-red-500 rounded-full border-2 border-white animate-pulse',
                        [Component.text('${s.getUnreadChatCount(s.selectedJobData!['id'] as String)}')],
                      ),
                  ],
                ),
            ]);
          } else {
            // Employer View
            final showWorkerCard = acceptedId != null && acceptedId.isNotEmpty;
            final workerName =
                s.acceptedApplicantProfile?['name'] as String? ??
                s.selectedJobData?['acceptedApplicantName'] as String? ??
                'Nyxian';
            final workerPhotoUrl =
                s.acceptedApplicantProfile?['photoUrl'] as String? ??
                s.selectedJobData?['acceptedApplicantPhotoUrl'] as String? ??
                '';

            return div(classes: 'space-y-3', [
              // Creator info card (shows Employer themselves)
              div(
                classes: 'w-full p-4 rounded-2xl border $cardCls flex items-center justify-between',
                [
                  div(classes: 'flex items-center gap-3', [
                    div(
                      classes:
                          'w-10 h-10 rounded-full flex items-center justify-center bg-zinc-700 flex-shrink-0 overflow-hidden',
                      [
                        if (creatorPhotoUrl.isNotEmpty)
                          img(
                            src: creatorPhotoUrl,
                            classes: 'w-full h-full object-cover',
                          )
                        else
                          span(classes: 'text-sm font-bold text-white', [
                            Component.text(creatorInitials),
                          ]),
                      ],
                    ),
                    div([
                      p(classes: 'font-semibold text-sm', [
                        Component.text(creatorName),
                      ]),
                      p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                        Component.text('You (Employer)'),
                      ]),
                    ]),
                  ]),
                ],
              ),
              // Worker info card (if accepted)
              if (showWorkerCard)
                div(
                  classes: 'w-full p-4 rounded-2xl border $cardCls flex flex-col gap-3',
                  [
                    div(classes: 'flex items-center justify-between', [
                      div(classes: 'flex items-center gap-3', [
                        div(
                          classes:
                              'w-10 h-10 rounded-full flex items-center justify-center bg-indigo-600 flex-shrink-0 overflow-hidden',
                          [
                            if (workerPhotoUrl.isNotEmpty)
                              img(src: workerPhotoUrl, classes: 'w-full h-full object-cover')
                            else
                              span(classes: 'text-sm font-bold text-white', [
                                Component.text(workerName.isNotEmpty ? workerName[0].toUpperCase() : 'N'),
                              ]),
                          ],
                        ),
                        div([
                          p(classes: 'font-semibold text-sm', [
                            Component.text(workerName),
                          ]),
                          p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                            Component.text('Accepted Nyxian'),
                          ]),
                        ]),
                      ]),
                    ]),
                    // Chat button
                    if (isChatActive)
                      button(
                        classes:
                            'w-full py-3.5 rounded-2xl font-bold text-white logo-gradient hover:opacity-95 transition-opacity flex items-center justify-center gap-2 shadow-lg shadow-indigo-500/20 relative',
                        events: {'click': (_) => s.openChat(s.selectedJobData!['id'] as String)},
                        [
                          lIcon('message-square', cls: 'w-5 h-5'),
                          Component.text('Chat with Nyxian'),
                          if (s.getUnreadChatCount(s.selectedJobData!['id'] as String) > 0)
                            span(
                              classes:
                                  'absolute -top-1.5 -right-1.5 px-2 py-0.5 text-xs font-black text-white bg-red-500 rounded-full border-2 border-white animate-pulse',
                              [Component.text('${s.getUnreadChatCount(s.selectedJobData!['id'] as String)}')],
                            ),
                        ],
                      ),
                  ],
                ),
            ]);
          }
        },
      ),

      // Description
      div(classes: 'p-5 rounded-2xl border $cardCls', [
        p(classes: 'font-semibold mb-2', [Component.text('Job Description')]),
        p(classes: 'text-sm leading-relaxed ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
          Component.text(
            s.selectedJobData?['description'] as String? ?? 'No description provided.',
          ),
        ]),
        if ((s.selectedJobData?['address'] as String?)?.isNotEmpty ?? false) ...[
          div(classes: 'mt-3 flex items-start gap-2 text-sm ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
            lIcon('map-pin', cls: 'w-4 h-4 flex-shrink-0 mt-0.5 text-indigo-400'),
            div([
              Component.text(s.selectedJobData!['address'] as String),
              if ((s.selectedJobData?['landmark'] as String?)?.isNotEmpty ?? false)
                Component.text(' — ${s.selectedJobData!['landmark']}'),
            ]),
          ]),
        ],
        Builder(
          builder: (context) {
            final createdAt = s.selectedJobData?['createdAt'] as int?;
            final updatedAt = s.selectedJobData?['updatedAt'] as int?;
            if (createdAt == null) return span([]);
            final cd = DateTime.fromMillisecondsSinceEpoch(createdAt);
            final cStr =
                'Posted on ${cd.year}-${cd.month.toString().padLeft(2, '0')}-${cd.day.toString().padLeft(2, '0')} at ${cd.hour.toString().padLeft(2, '0')}:${cd.minute.toString().padLeft(2, '0')}';

            String? uStr;
            if (updatedAt != null && updatedAt != createdAt) {
              final ud = DateTime.fromMillisecondsSinceEpoch(updatedAt);
              uStr =
                  'Edited on ${ud.year}-${ud.month.toString().padLeft(2, '0')}-${ud.day.toString().padLeft(2, '0')} at ${ud.hour.toString().padLeft(2, '0')}:${ud.minute.toString().padLeft(2, '0')}';
            }

            return div(
              classes:
                  'mt-4 pt-4 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex flex-col gap-1 text-[10px] ${isDark ? "text-zinc-500" : "text-zinc-400"}',
              [
                span([Component.text(cStr)]),
                if (uStr != null) span([Component.text(uStr)]),
              ],
            );
          },
        ),
      ]),

      // Q&A section
      _qaSection(s, isDark),

      if (!isNyxian &&
          (s.selectedJobData?['reports'] as List?) != null &&
          (s.selectedJobData!['reports'] as List).isNotEmpty)
        div(classes: 'p-4 rounded-2xl border border-red-500/30 bg-red-500/10 space-y-3', [
          p(classes: 'font-bold text-red-500 text-sm flex items-center gap-2', [
            lIcon('alert-triangle', cls: 'w-4 h-4'),
            Component.text('Job Reports (${(s.selectedJobData!['reports'] as List).length})'),
          ]),
          ul(classes: 'list-disc pl-5 text-xs text-red-400 space-y-1', [
            for (final report in s.selectedJobData!['reports'] as List)
              li([Component.text((report as Map)['reason'] as String? ?? 'Unknown Reason')]),
          ]),
        ]),

      // Action buttons
      Builder(
        builder: (context) {
          final acceptedId = s.selectedJobData?['acceptedApplicantId'] as String?;
          final isAccepted = acceptedId == s.userProfile?.uid;
          final isOngoingStatus =
              status == 'In Progress' || status == 'in_progress' || status == 'onGoing' || status == 'ongoing';

          if (isNyxian) {
            // --- NYXIAN VIEW ---
            if (isAccepted) {
              if (isOngoingStatus && !hasTracker) {
                // STANDARD JOB (No Tracker): Nyxian triggers 'Done' state
                return div(classes: 'space-y-3', [
                  div(
                    classes: 'p-4 rounded-2xl border border-green-500/30 bg-green-500/10 flex items-center gap-3',
                    [
                      lIcon('zap', cls: 'w-5 h-5 text-green-400'),
                      div([
                        p(classes: 'font-bold text-green-400 text-sm', [Component.text('Job In Progress')]),
                        p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                          Component.text('Tap the button below when you have finished the task.'),
                        ]),
                      ]),
                    ],
                  ),
                  div(classes: 'flex gap-3', [
                    button(
                      classes:
                          'flex-1 py-4 rounded-2xl font-semibold text-red-500 border border-red-500/30 bg-red-500/10 hover:bg-red-500/20 transition-all flex items-center justify-center gap-2',
                      events: {
                        'click': (_) {
                          final confirmed = confirmDialog('Are you sure you want to cancel this job?');
                          if (confirmed) {
                            s.handleCancelJob();
                          }
                        },
                      },
                      [
                        if (s.isUpdatingJobStatus) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                        lIcon('x-circle', cls: 'w-5 h-5'),
                        Component.text(s.isUpdatingJobStatus ? 'Cancelling...' : 'Cancel Job'),
                      ],
                    ),
                    button(
                      classes:
                          'flex-1 py-4 rounded-2xl font-semibold text-white bg-green-600 hover:bg-green-500 transition-colors flex items-center justify-center gap-2',
                      events: {'click': (_) => s.handleMarkJobDone()},
                      [
                        if (s.isUpdatingSubStatus) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                        lIcon('check-circle', cls: 'w-5 h-5'),
                        Component.text(s.isUpdatingSubStatus ? 'Updating...' : 'Mark as Done'),
                      ],
                    ),
                  ]),
                ]);
              } else if (isOngoingStatus && hasTracker) {
                // DELIVERY JOB: Step 1 (In Progress -> Arrived at First Point)
                // Blueprint: from in_progress, Nyxian taps "Arrived at First Point" directly
                final firstPointLabel =
                    s.selectedJobData?['routing']?['firstPoint']?['label'] as String? ??
                    s.selectedJobData?['pickupAddress'] as String? ??
                    'First Point';
                return div(classes: 'space-y-3', [
                  div(
                    classes: 'p-4 rounded-2xl border border-blue-500/30 bg-blue-500/10 flex items-center gap-3',
                    [
                      lIcon('map-pin', cls: 'w-5 h-5 text-blue-400'),
                      div([
                        p(classes: 'font-bold text-blue-400 text-sm', [Component.text('Delivery In Progress')]),
                        p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                          Component.text('Tap below when you arrive at the pickup point: $firstPointLabel'),
                        ]),
                      ]),
                    ],
                  ),
                  div(classes: 'flex gap-3', [
                    button(
                      classes:
                          'flex-1 py-4 rounded-2xl font-semibold text-red-500 border border-red-500/30 bg-red-500/10 hover:bg-red-500/20 transition-all flex items-center justify-center gap-2',
                      events: {
                        'click': (_) {
                          final confirmed = confirmDialog('Are you sure you want to cancel this job?');
                          if (confirmed) {
                            s.handleCancelJob();
                          }
                        },
                      },
                      [
                        if (s.isUpdatingJobStatus) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                        lIcon('x-circle', cls: 'w-5 h-5'),
                        Component.text(s.isUpdatingJobStatus ? 'Cancelling...' : 'Cancel Job'),
                      ],
                    ),
                    button(
                      classes:
                          'flex-1 py-4 rounded-2xl font-semibold text-white bg-blue-600 hover:bg-blue-500 transition-colors flex items-center justify-center gap-2',
                      events: {'click': (_) => s.handleUpdateNyxianSubStatus('arrived_pickup')},
                      [
                        if (s.isUpdatingSubStatus) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                        lIcon('map-pin', cls: 'w-5 h-5'),
                        Component.text(s.isUpdatingSubStatus ? 'Updating...' : 'Arrived at First Point'),
                      ],
                    ),
                  ]),
                ]);
              } else if (status == 'arrived_pickup') {
                // DELIVERY JOB: Step 3 (Arrived Pickup -> Paid Cashier)
                return div(classes: 'space-y-3', [
                  div(
                    classes: 'p-4 rounded-2xl border border-yellow-500/30 bg-yellow-500/10 flex items-center gap-3',
                    [
                      lIcon('shopping-bag', cls: 'w-5 h-5 text-yellow-400'),
                      div([
                        p(classes: 'font-bold text-yellow-400 text-sm', [Component.text('At Pickup Point')]),
                        p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                          Component.text('Please upload receipt/photo to continue.'),
                        ]),
                      ]),
                    ],
                  ),
                  div(
                    classes:
                        'relative w-full py-4 rounded-2xl font-semibold border-2 border-dashed ${s.receiptPhotoUrl != null ? "border-green-500 text-green-500" : "border-zinc-500 text-zinc-500"} flex items-center justify-center gap-2 cursor-pointer hover:bg-zinc-500/10 transition-colors',
                    [
                      if (s.isUploadingReceipt) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                      lIcon(s.receiptPhotoUrl != null ? 'check' : 'upload', cls: 'w-5 h-5'),
                      Component.text(
                        s.isUploadingReceipt
                            ? 'Uploading...'
                            : s.receiptPhotoUrl != null
                            ? 'Receipt Uploaded'
                            : 'Upload Receipt/Photo',
                      ),
                      input(
                        type: InputType.file,
                        attributes: {
                          'accept': 'image/*',
                          'capture': 'environment',
                          'id': 'receipt-upload-input',
                          'name': 'receipt_upload',
                        },
                        classes: 'absolute inset-0 opacity-0 cursor-pointer',
                        events: {'change': (e) => s.handleReceiptUpload(e)},
                      ),
                    ],
                  ),
                  button(
                    classes:
                        'w-full py-4 rounded-2xl font-semibold text-white bg-yellow-600 hover:bg-yellow-500 transition-colors disabled:opacity-50 disabled:cursor-not-allowed',
                    attributes: s.receiptPhotoUrl == null ? {'disabled': 'true'} : {},
                    events: s.receiptPhotoUrl == null
                        ? {}
                        : {'click': (_) => s.handleUpdateNyxianSubStatus('paid_cashier')},
                    [Component.text('Mark as Picked Up / Paid')],
                  ),
                ]);
              } else if (status == 'paid_cashier') {
                // DELIVERY JOB: Step 4 (Paid Cashier -> Going to Destination)
                final destName =
                    s.selectedJobData?['routing']?['secondPoint']?['label'] as String? ??
                    s.selectedJobData?['destinationAddress'] as String? ??
                    'Destination';
                return div(classes: 'space-y-3', [
                  div(
                    classes: 'p-4 rounded-2xl border border-indigo-500/30 bg-indigo-500/10 flex items-center gap-3',
                    [
                      lIcon('truck', cls: 'w-5 h-5 text-indigo-400'),
                      div([
                        p(classes: 'font-bold text-indigo-400 text-sm', [Component.text('Items Secured')]),
                        p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                          Component.text('Tap the button below when you start heading to the destination.'),
                        ]),
                      ]),
                    ],
                  ),
                  button(
                    classes:
                        'w-full py-4 rounded-2xl font-semibold text-white bg-indigo-600 hover:bg-indigo-500 transition-colors',
                    events: {'click': (_) => s.handleUpdateNyxianSubStatus('in_transit')},
                    [
                      if (s.isUpdatingSubStatus) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                      Component.text(s.isUpdatingSubStatus ? 'Updating...' : 'Going to $destName'),
                    ],
                  ),
                ]);
              } else if (status == 'in_transit') {
                // DELIVERY JOB: Step 5 (In Transit -> Arrived Destination)
                return div(classes: 'space-y-3', [
                  div(
                    classes: 'p-4 rounded-2xl border border-indigo-500/30 bg-indigo-500/10 flex items-center gap-3',
                    [
                      lIcon('truck', cls: 'w-5 h-5 text-indigo-400'),
                      div([
                        p(classes: 'font-bold text-indigo-400 text-sm', [Component.text('In Transit')]),
                        p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                          Component.text('Deliver the item to the destination.'),
                        ]),
                      ]),
                    ],
                  ),
                  button(
                    classes:
                        'w-full py-4 rounded-2xl font-semibold text-white bg-indigo-600 hover:bg-indigo-500 transition-colors',
                    events: {'click': (_) => s.handleUpdateNyxianSubStatus('arrived_dropoff')},
                    [
                      if (s.isUpdatingSubStatus) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                      Component.text(s.isUpdatingSubStatus ? 'Updating...' : 'Arrived at Destination'),
                    ],
                  ),
                ]);
              } else if (status == 'Done' || status == 'done' || status == 'arrived_dropoff') {
                if (hasTracker) {
                  // DELIVERY JOB (Tracker): Nyxian generates code
                  return div(classes: 'space-y-3', [
                    div(
                      classes: 'p-4 rounded-2xl border border-indigo-500/30 bg-indigo-500/10 flex items-center gap-3',
                      [
                        lIcon('check-circle', cls: 'w-5 h-5 text-indigo-400'),
                        div([
                          p(classes: 'font-bold text-indigo-400 text-sm', [Component.text('Arrived at Destination')]),
                          p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                            Component.text('Generate a completion code for the employer/recipient to scan or enter.'),
                          ]),
                        ]),
                      ],
                    ),
                    button(
                      classes:
                          'w-full py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
                      events: {'click': (_) => s.generateCompletionCode()},
                      [
                        if (s.isGeneratingCode) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                        lIcon('qr-code', cls: 'w-5 h-5'),
                        Component.text(s.isGeneratingCode ? 'Generating...' : 'Generate Completion QR / Code'),
                      ],
                    ),
                  ]);
                } else {
                  // STANDARD JOB (No Tracker): Employer generates code, Nyxian enters
                  return div(classes: 'space-y-3', [
                    div(
                      classes: 'p-4 rounded-2xl border border-indigo-500/30 bg-indigo-500/10 flex items-center gap-3',
                      [
                        lIcon('check-circle', cls: 'w-5 h-5 text-indigo-400'),
                        div([
                          p(classes: 'font-bold text-indigo-400 text-sm', [Component.text('Task Completed')]),
                          p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                            Component.text(
                              'Waiting for Employer to generate payment code. Click below to enter or scan it.',
                            ),
                          ]),
                        ]),
                      ],
                    ),
                    button(
                      classes:
                          'w-full py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
                      events: {'click': (_) => s.setState(() => s.showCompletionScanner = true)},
                      [lIcon('key', cls: 'w-5 h-5'), Component.text('Enter Payment Code')],
                    ),
                  ]);
                }
              } else if (status == 'Completed' || status == 'completed') {
                final nyxianRated = s.selectedJobData?['nyxianRated'] == true;
                return div(classes: 'space-y-3', [
                  div(
                    classes: 'p-4 rounded-2xl border border-green-500/30 bg-green-500/10 flex items-center gap-3',
                    [
                      lIcon('check-circle', cls: 'w-6 h-6 text-green-400'),
                      div([
                        p(classes: 'font-bold text-green-400 text-sm', [Component.text('Job Completed')]),
                        p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                          Component.text('Payment has been transferred to your Tyxbit wallet.'),
                        ]),
                      ]),
                    ],
                  ),
                  if (!nyxianRated)
                    button(
                      classes:
                          'w-full py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
                      events: {
                        'click': (_) {
                          s.setState(() {
                            s.showRatingPopup = true;
                            s.ratingTargetId = s.selectedJobData?['creatorId'] as String?;
                            s.ratingTargetName = s.selectedJobData?['creatorName'] as String? ?? 'Employer';
                            s.ratingScore = 0;
                            s.ratingComment = '';
                          });
                        },
                      },
                      [
                        lIcon('star', cls: 'w-5 h-5 fill-white'),
                        Component.text('Rate Employer'),
                      ],
                    ),
                ]);
              } else if (status == 'Cancelled') {
                return div(
                  classes: 'p-4 rounded-2xl border border-red-500/30 bg-red-500/10 flex items-center gap-3',
                  [
                    lIcon('x-circle', cls: 'w-6 h-6 text-red-400'),
                    div([
                      p(classes: 'font-bold text-red-400 text-sm', [Component.text('Gig Cancelled')]),
                      p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                        Component.text('This gig has been cancelled.'),
                      ]),
                    ]),
                  ],
                );
              }
            }

            // Default: Open / Applied (for Nyxian)
            return div(classes: 'flex gap-3', [
              button(
                classes: hasReported
                    ? 'py-4 px-6 rounded-2xl font-semibold border bg-zinc-400 opacity-50 cursor-not-allowed border-zinc-500 text-zinc-100'
                    : 'py-4 px-6 rounded-2xl font-semibold border ${isDark ? "border-red-500/30 text-red-400 hover:bg-red-500/10" : "border-red-200 text-red-500 hover:bg-red-50"} transition-colors',
                attributes: hasReported ? {'disabled': 'true'} : {},
                events: hasReported ? {} : {'click': (_) => s.handleReportJob()},
                [lIcon('flag', cls: 'w-5 h-5')],
              ),
              Builder(
                builder: (context) {
                  final isFilled = s.selectedJobData?['acceptedApplicantId'] != null;
                  if (isFilled) {
                    return button(
                      classes:
                          'flex-1 py-4 rounded-2xl font-semibold text-white bg-zinc-400 opacity-50 cursor-not-allowed',
                      attributes: {'disabled': 'true'},
                      events: {},
                      [Component.text('Position Filled')],
                    );
                  }
                  return button(
                    classes: (hasApplied || hasReported)
                        ? 'flex-1 py-4 rounded-2xl font-semibold text-white bg-zinc-400 opacity-50 cursor-not-allowed'
                        : 'flex-1 py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity',
                    attributes: (hasApplied || hasReported) ? {'disabled': 'true'} : {},
                    events: (hasApplied || hasReported)
                        ? {}
                        : {'click': (_) => s.setState(() => s.jobsView = JobsView.apply)},
                    [
                      Component.text(
                        hasApplied
                            ? 'Already Applied'
                            : hasReported
                            ? 'Cannot Apply'
                            : 'Proceed to Apply',
                      ),
                    ],
                  );
                },
              ),
            ]);
          } else {
            // --- EMPLOYER VIEW ---
            if (status == 'In Progress' ||
                status == 'onGoing' ||
                status == 'ongoing' ||
                status == 'in_progress' ||
                status == 'heading_to_pickup' ||
                status == 'arrived_pickup' ||
                status == 'paid_cashier' ||
                status == 'in_transit') {
              return div(classes: 'space-y-3', [
                div(classes: 'p-4 rounded-2xl border border-blue-500/30 bg-blue-500/10 flex items-center gap-3', [
                  lIcon('clock', cls: 'w-5 h-5 text-blue-400'),
                  div([
                    p(classes: 'font-bold text-blue-400 text-sm', [
                      Component.text(hasTracker ? 'Delivery In Progress' : 'Work In Progress'),
                    ]),
                    p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                      Component.text(
                        hasTracker
                            ? 'Nyxian is fulfilling your delivery order.'
                            : 'Nyxian is currently working on your task.',
                      ),
                    ]),
                  ]),
                ]),
                Builder(
                  builder: (context) {
                    final statusLower = status.toLowerCase();
                    final reachedFirstPoint =
                        hasTracker &&
                        (statusLower == 'arrived_pickup' ||
                            statusLower == 'paid_cashier' ||
                            statusLower == 'in_transit' ||
                            statusLower == 'arrived_dropoff' ||
                            statusLower == 'done' ||
                            statusLower == 'completed');

                    final msg = reachedFirstPoint
                        ? 'The Nyxian has reached/passed the first point. If you cancel, the Nyxian will be compensated 20 tyxbits from the escrow, and the remaining escrow will be refunded to you. Are you sure you want to cancel?'
                        : 'Are you sure you want to cancel this job? You will receive a 100% refund of the escrow.';

                    return button(
                      classes:
                          'w-full py-4 rounded-2xl font-semibold text-red-500 border border-red-500/30 bg-red-500/10 hover:bg-red-500/20 transition-all flex items-center justify-center gap-2',
                      events: {
                        'click': (_) {
                          final confirmed = confirmDialog(msg);
                          if (confirmed) {
                            s.handleCancelJob();
                          }
                        },
                      },
                      [
                        if (s.isUpdatingJobStatus) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                        lIcon('x-circle', cls: 'w-5 h-5'),
                        Component.text(s.isUpdatingJobStatus ? 'Cancelling...' : 'Cancel Job'),
                      ],
                    );
                  },
                ),
                if ((s.selectedJobData?['receiptUrl'] as String?) != null)
                  div(classes: 'mt-2 p-3 rounded-xl border ${isDark ? "border-zinc-800" : "border-zinc-200"}', [
                    p(classes: 'text-xs font-bold text-indigo-400 mb-2', [Component.text('Receipt / Item Photo')]),
                    img(
                      src: s.selectedJobData!['receiptUrl'] as String,
                      classes: 'w-full h-auto rounded-lg cursor-zoom-in hover:opacity-90 transition-opacity',
                      events: {
                        'click': (_) => s.showFullScreenPhoto(s.selectedJobData!['receiptUrl'] as String),
                      },
                    ),
                  ]),
              ]);
            }

            if (status == 'Done' || status == 'arrived_dropoff') {
              if (hasTracker) {
                // DELIVERY JOB (Tracker): Nyxian generated, Employer enters code
                return div(classes: 'space-y-3', [
                  div(classes: 'p-4 rounded-2xl border border-green-500/30 bg-green-500/10 flex items-center gap-3', [
                    lIcon('check-circle', cls: 'w-5 h-5 text-green-400'),
                    div([
                      p(classes: 'font-bold text-green-400 text-sm', [
                        Component.text('Delivery Ready for Verification'),
                      ]),
                      p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                        Component.text(
                          'The Nyxian has arrived at the destination. Enter their completion code to verify and release payment.',
                        ),
                      ]),
                    ]),
                  ]),
                  if ((s.selectedJobData?['receiptUrl'] as String?) != null)
                    div(classes: 'mt-2 p-3 rounded-xl border ${isDark ? "border-zinc-800" : "border-zinc-200"}', [
                      p(classes: 'text-xs font-bold text-indigo-400 mb-2', [Component.text('Receipt / Item Photo')]),
                      img(
                        src: s.selectedJobData!['receiptUrl'] as String,
                        classes: 'w-full h-auto rounded-lg cursor-zoom-in hover:opacity-90 transition-opacity',
                        events: {
                          'click': (_) => s.showFullScreenPhoto(s.selectedJobData!['receiptUrl'] as String),
                        },
                      ),
                    ]),
                  button(
                    classes:
                        'w-full py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
                    events: {'click': (_) => s.setState(() => s.showCompletionScanner = true)},
                    [lIcon('key', cls: 'w-5 h-5'), Component.text('Enter Completion Code')],
                  ),
                ]);
              } else {
                // STANDARD JOB (No Tracker): Employer generates code, Nyxian enters
                return div(classes: 'space-y-3', [
                  div(classes: 'p-4 rounded-2xl border border-green-500/30 bg-green-500/10 flex items-center gap-3', [
                    lIcon('check-circle', cls: 'w-5 h-5 text-green-400'),
                    div([
                      p(classes: 'font-bold text-green-400 text-sm', [Component.text('Task Ready for Payment')]),
                      p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                        Component.text(
                          'The Nyxian has completed the task. Generate a payment code to release the escrow.',
                        ),
                      ]),
                    ]),
                  ]),
                  if ((s.selectedJobData?['receiptUrl'] as String?) != null)
                    div(classes: 'mt-2 p-3 rounded-xl border ${isDark ? "border-zinc-800" : "border-zinc-200"}', [
                      p(classes: 'text-xs font-bold text-indigo-400 mb-2', [Component.text('Receipt / Item Photo')]),
                      img(
                        src: s.selectedJobData!['receiptUrl'] as String,
                        classes: 'w-full h-auto rounded-lg cursor-zoom-in hover:opacity-90 transition-opacity',
                        events: {
                          'click': (_) => s.showFullScreenPhoto(s.selectedJobData!['receiptUrl'] as String),
                        },
                      ),
                    ]),
                  button(
                    classes:
                        'w-full py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
                    events: {'click': (_) => s.generateCompletionCode()},
                    [
                      if (s.isGeneratingCode) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                      lIcon('qr-code', cls: 'w-5 h-5'),
                      Component.text(s.isGeneratingCode ? 'Generating...' : 'Generate Payment QR / Code'),
                    ],
                  ),
                ]);
              }
            }

            if (status == 'Completed') {
              final employerRated = s.selectedJobData?['employerRated'] == true;
              return div(classes: 'space-y-3', [
                div(
                  classes: 'p-4 rounded-2xl border border-green-500/30 bg-green-500/10 flex items-center gap-3',
                  [
                    lIcon('heart', cls: 'w-6 h-6 text-green-400'),
                    div([
                      p(classes: 'font-bold text-green-400 text-sm', [Component.text('Job Completed & Paid')]),
                      p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                        Component.text('Payment has been transferred to the Nyxian.'),
                      ]),
                    ]),
                  ],
                ),
                if (!employerRated)
                  button(
                    classes:
                        'w-full py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
                    events: {
                      'click': (_) {
                        s.setState(() {
                          s.showRatingPopup = true;
                          s.ratingTargetId = s.selectedJobData?['acceptedApplicantId'] as String?;
                          s.ratingTargetName = s.selectedJobData?['acceptedApplicantName'] as String? ?? 'Nyxian';
                          s.ratingScore = 0;
                          s.ratingComment = '';
                        });
                      },
                    },
                    [
                      lIcon('star', cls: 'w-5 h-5 fill-white'),
                      Component.text('Rate Nyxian'),
                    ],
                  ),
              ]);
            }

            if (status == 'Cancelled') {
              return div(
                classes: 'p-4 rounded-2xl border border-red-500/30 bg-red-500/10 flex items-center gap-3',
                [
                  lIcon('x-circle', cls: 'w-6 h-6 text-red-400'),
                  div([
                    p(classes: 'font-bold text-red-400 text-sm', [Component.text('Gig Cancelled')]),
                    p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                      Component.text('This job posting has been cancelled.'),
                    ]),
                  ]),
                ],
              );
            }

            // Default: Open job employer management buttons
            return div(classes: 'flex gap-3', [
              button(
                classes:
                    'py-4 px-6 rounded-2xl font-semibold border ${isDark ? "border-red-500/30 text-red-400 hover:bg-red-500/10" : "border-red-200 text-red-500 hover:bg-red-50"} transition-colors flex items-center justify-center cursor-pointer',
                events: {
                  'click': (_) => s.setState(() => s.showDeleteConfirm = true),
                },
                [lIcon('trash-2', cls: 'w-5 h-5')],
              ),
              if (job.applicants == 0)
                button(
                  classes:
                      'flex-1 py-4 rounded-2xl font-semibold ${isDark ? "bg-zinc-800 hover:bg-zinc-700 text-zinc-200" : "bg-zinc-100 hover:bg-zinc-200 text-zinc-700"} transition-colors flex items-center justify-center gap-2 cursor-pointer',
                  events: {},
                  [lIcon('edit-2', cls: 'w-4 h-4'), Component.text(' Edit')],
                ),
              button(
                classes:
                    'flex-1 py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2 cursor-pointer',
                events: {
                  'click': (_) {
                    s.loadApplicants(s.selectedJobData!['id'] as String);
                    s.setState(() => s.jobsView = JobsView.review);
                  },
                },
                [lIcon('users', cls: 'w-4 h-4'), Component.text(' Review (${job.applicants})')],
              ),
            ]);
          }
        },
      ),

      // QR Completion Scanner / Code Modal
      if (s.showCompletionScanner)
        div(classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm', [
          div(
            classes:
                'w-full max-w-md p-6 rounded-3xl ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"} shadow-2xl animate-fade-up flex flex-col gap-5',
            [
              div(classes: 'flex items-center justify-between', [
                div(classes: 'flex items-center gap-3', [
                  div(classes: 'p-3 bg-indigo-500/20 rounded-xl', [lIcon('key', cls: 'w-6 h-6 text-indigo-500')]),
                  h3(classes: 'text-xl font-bold', [Component.text('Verify Completion')]),
                ]),
                button(
                  classes: 'p-2 rounded-full hover:bg-zinc-500/20 transition-colors',
                  events: {'click': (_) => s.setState(() => s.showCompletionScanner = false)},
                  [lIcon('x', cls: 'w-5 h-5 ${isDark ? "text-zinc-400" : "text-zinc-600"}')],
                ),
              ]),
              Builder(
                builder: (context) {
                  final basePrice = (s.selectedJobData?['pricingValue'] as num?)?.toDouble() ?? 0.0;
                  if (isNyxian) {
                    final commFee = basePrice * 0.03;
                    final netPayout = basePrice - commFee;
                    return div(
                      classes:
                          'p-4 rounded-xl border ${isDark ? "border-zinc-800 bg-zinc-800/50" : "border-zinc-200 bg-zinc-50"} space-y-2',
                      [
                        div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                          span([Component.text('Base Payout:')]),
                          span(classes: 'font-semibold', [Component.text('₱ ${basePrice.toStringAsFixed(2)}')]),
                        ]),
                        div(
                          classes:
                              'flex justify-between items-center text-xs text-zinc-400 border-b ${isDark ? "border-zinc-800/60" : "border-zinc-200/60"} pb-2',
                          [
                            span([Component.text('Platform Commission (3%):')]),
                            span(classes: 'font-semibold text-red-400', [
                              Component.text('− ₱ ${commFee.toStringAsFixed(2)}'),
                            ]),
                          ],
                        ),
                        div(classes: 'flex justify-between items-center pt-1', [
                          span(classes: 'text-xs font-semibold text-indigo-400', [
                            Component.text('Net Payout Amount:'),
                          ]),
                          span(classes: 'text-2xl font-black logo-gradient-text', [
                            Component.text('₱ ${netPayout.toStringAsFixed(2)}'),
                          ]),
                        ]),
                      ],
                    );
                  } else {
                    final txFee = basePrice * 0.07;
                    final convFee = basePrice * 0.03;
                    final totalPaid = basePrice + txFee + convFee;
                    return div(
                      classes:
                          'p-4 rounded-xl border ${isDark ? "border-zinc-800 bg-zinc-800/50" : "border-zinc-200 bg-zinc-50"} space-y-2',
                      [
                        div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                          span([Component.text('Base Gig Price:')]),
                          span(classes: 'font-semibold', [Component.text('₱ ${basePrice.toStringAsFixed(2)}')]),
                        ]),
                        div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                          span([Component.text('Transaction Fee (7%):')]),
                          span(classes: 'font-semibold text-amber-500', [
                            Component.text('+ ₱ ${txFee.toStringAsFixed(2)}'),
                          ]),
                        ]),
                        div(
                          classes:
                              'flex justify-between items-center text-xs text-zinc-400 border-b ${isDark ? "border-zinc-800/60" : "border-zinc-200/60"} pb-2',
                          [
                            span([Component.text('Convenience Fee (3%):')]),
                            span(classes: 'font-semibold text-amber-500', [
                              Component.text('+ ₱ ${convFee.toStringAsFixed(2)}'),
                            ]),
                          ],
                        ),
                        div(classes: 'flex justify-between items-center pt-1', [
                          span(classes: 'text-xs font-semibold text-indigo-400', [Component.text('Total Cost:')]),
                          span(classes: 'text-2xl font-black logo-gradient-text', [
                            Component.text('₱ ${totalPaid.toStringAsFixed(2)}'),
                          ]),
                        ]),
                      ],
                    );
                  }
                },
              ),
              div(classes: 'space-y-2', [
                p(
                  classes: 'text-sm font-semibold ${isDark ? "text-zinc-300" : "text-zinc-700"}',
                  [Component.text('Enter the 6-digit code:')],
                ),
                input<String>(
                  type: InputType.text,
                  classes:
                      'w-full px-4 py-4 text-center text-3xl font-black tracking-widest rounded-xl border ${isDark ? "bg-zinc-800 border-zinc-700 text-white focus:border-indigo-500" : "bg-white border-zinc-200 text-zinc-900 focus:border-indigo-500"} outline-none transition-colors',
                  attributes: {
                    'placeholder': '------',
                    'maxlength': '6',
                    'id': 'job-completion-code',
                    'name': 'completion_code',
                  },
                  value: s.completionScanInput,
                  onInput: (String v) => s.setState(() {
                    s.completionScanInput = v;
                  }),
                ),
              ]),
              div(classes: 'flex gap-3', [
                button(
                  classes:
                      'flex-1 py-4 rounded-2xl font-bold ${isDark ? "bg-zinc-800 text-zinc-300" : "bg-zinc-100 text-zinc-700"}',
                  events: {'click': (_) => s.setState(() => s.showCompletionScanner = false)},
                  [Component.text('Cancel')],
                ),
                button(
                  classes: (s.completionScanInput.length < 6 || s.isCompletingJob)
                      ? 'flex-1 py-4 rounded-2xl font-bold text-white bg-indigo-500/50 cursor-not-allowed'
                      : 'flex-1 py-4 rounded-2xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
                  events: (s.completionScanInput.length < 6 || s.isCompletingJob)
                      ? {}
                      : {'click': (_) => s.handleCompleteJob()},
                  [
                    if (s.isCompletingJob) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
                    Component.text(
                      s.isCompletingJob
                          ? 'Verifying...'
                          : (hasTracker ? 'Verify & Release Payment' : 'Release Payment'),
                    ),
                  ],
                ),
              ]),
            ],
          ),
        ]),

      // Display Generated Code
      if (s.generatedCompletionCode != null)
        div(classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm', [
          div(
            classes:
                'w-full max-w-md p-8 rounded-[2.5rem] ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"} shadow-2xl animate-fade-up flex flex-col items-center gap-6',
            [
              div(classes: 'text-center', [
                h3(classes: 'text-2xl font-black mb-2', [Component.text('Payment Code')]),
                p(classes: 'text-sm text-zinc-500', [
                  Component.text('Ask the other party to enter this code on their device.'),
                ]),
              ]),

              // QR Code
              Builder(
                builder: (context) {
                  final qrUrl =
                      '${getUrlOrigin()}/?action=verify_qr&jobId=${s.selectedJobData?['id']}&code=${s.generatedCompletionCode}';
                  final encodedQrUrl = Uri.encodeComponent(qrUrl);
                  return div(classes: 'p-4 bg-white rounded-3xl shadow-inner', [
                    img(
                      src: 'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=$encodedQrUrl',
                      classes: 'w-48 h-48',
                    ),
                  ]);
                },
              ),

              div(classes: 'text-center flex flex-col items-center gap-3', [
                div([
                  p(classes: 'text-[10px] font-black uppercase tracking-widest text-zinc-500 mb-1', [
                    Component.text('Manual Code'),
                  ]),
                  p(classes: 'text-4xl font-black tracking-[0.5em] text-indigo-500 pl-4', [
                    Component.text(s.generatedCompletionCode!),
                  ]),
                ]),
                div(classes: 'flex gap-3 mt-1', [
                  button(
                    classes:
                        'px-4 py-2.5 rounded-xl text-xs font-bold border border-indigo-500/30 text-indigo-400 bg-indigo-500/5 hover:bg-indigo-500/10 transition-all flex items-center gap-1.5 cursor-pointer',
                    events: {
                      'click': (_) {
                        final code = s.generatedCompletionCode!;
                        web.window.navigator.clipboard.writeText(code);
                        s.showAppToast('Code Copied', 'Verification code $code copied.');
                      },
                    },
                    [
                      lIcon('copy', cls: 'w-3.5 h-3.5'),
                      Component.text('Copy Code'),
                    ],
                  ),
                  button(
                    classes:
                        'px-4 py-2.5 rounded-xl text-xs font-bold border border-green-500/30 text-green-400 bg-green-500/5 hover:bg-green-500/10 transition-all flex items-center gap-1.5 cursor-pointer',
                    events: {
                      'click': (_) => s.sendCompletionCodeToWorker(),
                    },
                    [
                      lIcon('send', cls: 'w-3.5 h-3.5'),
                      Component.text(isNyxian ? 'Send to Employer' : 'Send to Worker'),
                    ],
                  ),
                ]),
              ]),

              button(
                classes:
                    'w-full py-4 rounded-2xl font-bold ${isDark ? "bg-zinc-800 text-zinc-200" : "bg-zinc-100 text-zinc-700"} transition-colors',
                events: {'click': (_) => s.setState(() => s.generatedCompletionCode = null)},
                [Component.text('Close')],
              ),
            ],
          ),
        ]),

      if (s.showReportModal)
        div(classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm', [
          div(
            classes:
                'w-full max-w-md p-6 rounded-3xl ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"} shadow-2xl animate-fade-up',
            [
              h3(classes: 'text-xl font-bold mb-2', [Component.text('Report Job')]),
              p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-600"} mb-6', [
                Component.text('Please select a reason for reporting this gig. This will be reviewed by our team.'),
              ]),
              div(classes: 'space-y-3 mb-6', [
                for (final reason in ['Scam / Fake Job', 'Spam', 'Fraud / Suspicious Payment', 'Inappropriate Content'])
                  button(
                    classes:
                        'w-full px-4 py-3 text-left rounded-xl border transition-colors ${s.selectedReportReason == reason ? (isDark ? "bg-red-500/20 border-red-500/50 text-red-400" : "bg-red-50 border-red-200 text-red-600") : (isDark ? "border-zinc-800 hover:border-zinc-700" : "border-zinc-200 hover:bg-zinc-50")}',
                    events: {'click': (_) => s.setState(() => s.selectedReportReason = reason)},
                    [Component.text(reason)],
                  ),
              ]),
              div(classes: 'flex gap-3', [
                button(
                  classes:
                      'flex-1 py-3 rounded-xl font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-200 hover:bg-zinc-50"}',
                  events: {
                    'click': (_) => s.setState(() {
                      s.showReportModal = false;
                      s.selectedReportReason = '';
                    }),
                  },
                  [Component.text('Cancel')],
                ),
                button(
                  classes:
                      'flex-1 py-3 rounded-xl font-semibold text-white bg-red-500 hover:bg-red-600 transition-colors flex items-center justify-center gap-2',
                  attributes: s.selectedReportReason.isEmpty ? {'disabled': 'true'} : {},
                  events: s.selectedReportReason.isEmpty ? {} : {'click': (_) => s.submitJobReport()},
                  [
                    if (s.isSubmittingReport) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
                    Component.text('Submit Report'),
                  ],
                ),
              ]),
            ],
          ),
        ]),

      if (s.showEmployerFeePopup)
        div(classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm', [
          div(
            classes:
                'w-full max-w-md p-8 rounded-[2.5rem] ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"} shadow-2xl animate-fade-up flex flex-col items-center gap-6',
            [
              div(classes: 'text-center', [
                div(classes: 'p-4 bg-green-500/10 rounded-full inline-flex mb-3 text-green-500', [
                  lIcon('check-circle', cls: 'w-10 h-10'),
                ]),
                h3(classes: 'text-2xl font-black mb-2', [Component.text('Job Completed & Paid')]),
                p(classes: 'text-sm text-zinc-500', [
                  Component.text('The escrow funds have been successfully released to the Nyxian.'),
                ]),
              ]),

              Builder(
                builder: (context) {
                  final basePrice = (s.selectedJobData?['pricingValue'] as num?)?.toDouble() ?? 0.0;
                  final txFee = basePrice * 0.07;
                  final convFee = basePrice * 0.03;
                  final totalFees = txFee + convFee;

                  return div(
                    classes:
                        'w-full p-5 rounded-3xl border ${isDark ? "border-zinc-800 bg-zinc-800/30" : "border-zinc-200 bg-zinc-50"} space-y-3',
                    [
                      p(classes: 'text-xs font-bold text-indigo-400 uppercase tracking-wider', [
                        Component.text('Employer Fee Deduction Notice'),
                      ]),
                      div(classes: 'space-y-2', [
                        div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                          span([Component.text('Base Gig Price:')]),
                          span(classes: 'font-semibold ${isDark ? "text-zinc-200" : "text-zinc-700"}', [
                            Component.text('₱ ${basePrice.toStringAsFixed(2)}'),
                          ]),
                        ]),
                        div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                          span([Component.text('Transaction Fee (7%):')]),
                          span(classes: 'font-semibold text-amber-500', [
                            Component.text('+ ₱ ${txFee.toStringAsFixed(2)}'),
                          ]),
                        ]),
                        div(
                          classes:
                              'flex justify-between items-center text-xs text-zinc-400 border-b ${isDark ? "border-zinc-800/60" : "border-zinc-200/60"} pb-2.5',
                          [
                            span([Component.text('Convenience Fee (3%):')]),
                            span(classes: 'font-semibold text-amber-500', [
                              Component.text('+ ₱ ${convFee.toStringAsFixed(2)}'),
                            ]),
                          ],
                        ),
                        div(classes: 'flex justify-between items-center pt-1.5', [
                          span(classes: 'text-xs font-bold text-indigo-400', [
                            Component.text('Total Fees Charged (10%):'),
                          ]),
                          span(classes: 'text-xl font-black logo-gradient-text', [
                            Component.text('₱ ${totalFees.toStringAsFixed(2)}'),
                          ]),
                        ]),
                      ]),
                    ],
                  );
                },
              ),

              p(classes: 'text-[11px] text-zinc-500 text-center leading-relaxed px-2', [
                Component.text(
                  'A total fee of 10% was automatically deducted from your wallet to cover secure transaction processing and platform convenience.',
                ),
              ]),

              button(
                classes:
                    'w-full py-4 rounded-2xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity',
                events: {'click': (_) => s.setState(() => s.showEmployerFeePopup = false)},
                [Component.text('Got It, Thanks!')],
              ),
            ],
          ),
        ]),

      if (s.showAuthenticityModal)
        div(classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm', [
          div(
            classes:
                'w-full max-w-md p-6 rounded-3xl ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"} shadow-2xl animate-fade-up flex flex-col',
            [
              div(classes: 'flex items-center gap-3 mb-4', [
                lIcon('shield-check', cls: 'w-6 h-6 text-yellow-500'),
                h3(classes: 'text-xl font-bold', [Component.text('Authenticity Analysis')]),
              ]),
              if (s.isCheckingAuthenticity)
                div(classes: 'py-12 flex flex-col items-center justify-center gap-4 text-yellow-500', [
                  lIcon('loader-2', cls: 'w-8 h-8 animate-spin'),
                  p(classes: 'text-sm font-semibold', [Component.text('Analyzing job intent and data...')]),
                ])
              else if (s.authenticityResult != null)
                div(
                  classes: 'p-4 rounded-xl border border-yellow-500/20 bg-yellow-500/5 mb-6 max-h-64 overflow-y-auto',
                  [
                    p(classes: 'text-sm leading-relaxed ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                      Component.text(s.authenticityResult!),
                    ]),
                  ],
                ),
              button(
                classes:
                    'w-full py-3 rounded-xl font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800 text-zinc-300" : "border-zinc-200 hover:bg-zinc-50 text-zinc-700"}',
                events: {
                  'click': (_) => s.setState(() {
                    s.showAuthenticityModal = false;
                  }),
                },
                [Component.text('Close')],
              ),
            ],
          ),
        ]),

      if ((s.selectedJobData?['pickupLat'] != null) && (s.selectedJobData?['destinationLat'] != null))
        NavigationMapComponent(state: s, isNyxian: isNyxian),
    ]);
  }

  Component _qaSection(TranyxAppState s, bool isDark) {
    final status = (s.selectedJobData?['status'] as String? ?? '').toLowerCase();
    final isOngoing =
        status == 'in progress' ||
        status == 'in_progress' ||
        status == 'ongoing' ||
        status == 'heading_to_pickup' ||
        status == 'arrived_pickup' ||
        status == 'paid_cashier' ||
        status == 'in_transit' ||
        status == 'arrived_dropoff';
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    final isOwner = s.selectedJobData?['creatorId'] == s.userProfile?.uid;
    return div(classes: 'p-5 rounded-2xl border space-y-4 $cardCls', [
      p(classes: 'font-semibold', [Component.text('Public Q&A')]),
      if (isOngoing)
        div(
          classes:
              'p-4 rounded-xl border border-amber-500/20 bg-amber-500/5 text-amber-500 text-xs font-semibold flex items-center gap-2',
          [
            lIcon('lock', cls: 'w-4 h-4'),
            Component.text('Public Q&A is disabled because this job is currently in progress.'),
          ],
        )
      else ...[
        if (s.isLoadingQuestions)
          div(classes: 'flex justify-center py-4', [lIcon('loader-2', cls: 'w-5 h-5 animate-spin text-indigo-400')])
        else if (s.jobQuestions.isEmpty)
          p(classes: 'text-sm ${isDark ? "text-zinc-600" : "text-zinc-400"}', [
            Component.text('No questions yet. Be the first to ask!'),
          ])
        else
          for (final qa in s.jobQuestions) _qaItem(qa, isOwner, s, isDark),

        if (!isOwner)
          div(classes: 'flex gap-2 pt-2', [
            input(
              classes:
                  'flex-1 px-4 py-2.5 rounded-xl border text-sm ${isDark ? "bg-zinc-800 border-zinc-700 text-zinc-200" : "bg-zinc-50 border-zinc-200 text-zinc-800"} outline-none',
              type: InputType.text,
              attributes: {
                'placeholder': 'Ask a question...',
                'value': s.newQuestionText,
                'id': 'qa-question-input',
                'name': 'qa_question',
              },
              events: {
                'input': (e) {
                  s.setState(() => s.newQuestionText = getInputValue(e.target));
                },
              },
            ),
            button(
              classes: 'px-4 py-2.5 rounded-xl logo-gradient text-white',
              events: {'click': (_) => s.handleAskQuestion()},
              [lIcon('send', cls: 'w-4 h-4')],
            ),
          ]),
      ],
    ]);
  }

  Component _qaItem(Map<String, dynamic> qa, bool isOwner, TranyxAppState s, bool isDark) {
    final qid = qa['id'] as String? ?? '';
    final author = qa['authorName'] as String? ?? 'Anonymous';
    final question = qa['questionText'] as String? ?? '';
    final answer = qa['answerText'] as String?;
    final isAnswering = s.activeAnswerQuestionId == qid;
    return div(classes: 'space-y-2', [
      div(classes: 'flex items-start gap-3', [
        div(classes: 'w-8 h-8 rounded-full bg-indigo-600/20 flex items-center justify-center flex-shrink-0', [
          span(classes: 'text-xs font-bold text-indigo-400', [
            Component.text(author.isNotEmpty ? author[0].toUpperCase() : '?'),
          ]),
        ]),
        div(classes: 'flex-1', [
          p(classes: 'text-sm font-semibold', [Component.text(author)]),
          p(classes: 'text-sm mt-1 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [Component.text(question)]),
          if (answer != null)
            div(classes: 'mt-2 pl-3 border-l-2 border-indigo-500/50', [
              p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [Component.text(answer)]),
            ])
          else if (isOwner && !isAnswering)
            button(
              classes: 'mt-1 text-xs text-indigo-400 hover:underline',
              events: {'click': (_) => s.setState(() => s.activeAnswerQuestionId = qid)},
              [Component.text('Answer')],
            )
          else if (isOwner && isAnswering)
            div(classes: 'mt-2 flex gap-2', [
              input(
                classes:
                    'flex-1 px-3 py-2 rounded-lg border text-xs ${isDark ? "bg-zinc-800 border-zinc-700 text-zinc-200" : "bg-zinc-50 border-zinc-200"} outline-none',
                type: InputType.text,
                attributes: {
                  'placeholder': 'Type your answer...',
                  'value': s.answerDrafts[qid] ?? '',
                  'id': 'qa-answer-input-$qid',
                  'name': 'qa_answer',
                },
                events: {
                  'input': (e) {
                    s.setState(() => s.answerDrafts[qid] = getInputValue(e.target));
                  },
                },
              ),
              button(
                classes: 'px-3 py-2 rounded-lg logo-gradient text-white text-xs',
                events: {'click': (_) async => s.handleAnswerQuestion(qid)},
                [Component.text('Post')],
              ),
            ]),

          div(classes: 'mt-2 flex items-center gap-4', [
            Builder(
              builder: (context) {
                final likes = List<String>.from(qa['likedByUids'] as List? ?? []);
                final hasLiked = s.userProfile?.uid != null && likes.contains(s.userProfile!.uid);
                return button(
                  classes:
                      'flex items-center gap-1.5 text-xs font-semibold transition-colors ${hasLiked ? "text-indigo-500" : (isDark ? "text-zinc-500 hover:text-zinc-300" : "text-zinc-400 hover:text-zinc-600")}',
                  events: {'click': (_) => s.handleLikeQuestion(qid, !hasLiked)},
                  [
                    lIcon('heart', cls: 'w-3.5 h-3.5 ${hasLiked ? "fill-current" : ""}'),
                    Component.text(likes.isNotEmpty ? '${likes.length}' : 'Like'),
                  ],
                );
              },
            ),
            if (s.userProfile?.uid == qa['authorId'] && answer == null)
              button(
                classes:
                    'flex items-center gap-1 text-xs font-semibold text-red-500/70 hover:text-red-500 transition-colors',
                events: {'click': (_) => s.handleDeleteQuestion(qid)},
                [lIcon('trash-2', cls: 'w-3.5 h-3.5'), Component.text('Delete')],
              ),
          ]),
        ]),
      ]),
    ]);
  }
}

// ── Create Job ────────────────────────────────────────────────
class _CreateJob extends StatelessComponent {
  final TranyxAppState state;
  const _CreateJob({required this.state});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final step = s.createStep;

    return div(classes: 'space-y-6 animate-fade-up', [
      subViewHeader(
        title: 'Create Job — Step $step of 3',
        isDark: isDark,
        onBack: () => s.setState(() {
          if (step > 1) {
            s.createStep = step - 1;
          } else {
            s.jobsView = JobsView.list;
            s.createStep = 1;
          }
        }),
      ),

      // Progress bar
      div(classes: 'flex gap-2', [
        for (int i = 1; i <= 3; i++)
          div(
            [],
            classes:
                'flex-1 h-1.5 rounded-full ${i <= step ? "logo-gradient" : (isDark ? "bg-zinc-800" : "bg-zinc-200")}',
          ),
      ]),

      if (step == 1) _step1(s, isDark),
      if (step == 2) _step2(s, isDark),
      if (step == 3) _step3(s, isDark),

      if (s.postJobError != null)
        div(
          classes:
              'p-4 rounded-2xl bg-red-500/10 border border-red-500/20 text-red-500 text-sm flex items-center gap-2 animate-fade-up',
          [
            lIcon('alert-circle', cls: 'w-5 h-5 flex-shrink-0 text-red-500'),
            span([Component.text(s.postJobError!)]),
          ],
        ),

      button(
        classes:
            'w-full py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex justify-center items-center',
        events: {
          'click': (_) async {
            s.setState(() => s.postJobError = null); // Reset error on click

            if (step == 1) {
              if (s.selectedCategory == null) {
                s.setState(() => s.postJobError = 'Please select a job category.');
                return;
              }
              if (s.newJobTitle.trim().isEmpty) {
                s.setState(() => s.postJobError = 'Please enter a job title.');
                return;
              }
              if (s.newJobDesc.trim().isEmpty) {
                s.setState(() => s.postJobError = 'Please enter a job description.');
                return;
              }
              s.setState(() => s.createStep = 2);
            } else if (step == 2) {
              if (s.locType == LocType.onsite) {
                if (s.pickupAddress.trim().isEmpty || s.pickupLat == null || s.pickupLng == null) {
                  final label = (s.selectedCategory?.hasTracker ?? false) ? '1st Point' : 'Site Location';
                  s.setState(() => s.postJobError = 'Please pin the $label on the map.');
                  return;
                }
                if ((s.selectedCategory?.hasTracker ?? false) &&
                    (s.destinationAddress.trim().isEmpty || s.destinationLat == null || s.destinationLng == null)) {
                  s.setState(() => s.postJobError = 'Please pin the Delivery Point on the map.');
                  return;
                }
              }
              if (s.jobDateType != JobDateType.flexible && s.jobDate.trim().isEmpty) {
                s.setState(() => s.postJobError = 'Please specify a job/target date.');
                return;
              }
              s.setState(() => s.createStep = 3);
            } else {
              final price = double.tryParse(s.priceRate) ?? 0.0;
              if (price <= 0) {
                s.setState(() => s.postJobError = 'Please enter a valid amount / rate greater than 0.');
                return;
              }
              if (s.isPostingJob) return;

              final txFee = price * 0.07;
              final convFee = price * 0.03;
              final total = price + txFee + convFee;
              final msg =
                  'Confirm Posting:\n\n'
                  'Escrow Deposit: ₱${price.toStringAsFixed(2)}\n'
                  '7% Transaction Fee: ₱${txFee.toStringAsFixed(2)}\n'
                  '3% Convenience Fee: ₱${convFee.toStringAsFixed(2)}\n'
                  'Total Cost: ₱${total.toStringAsFixed(2)}\n\n'
                  'Only the base price of ₱${price.toStringAsFixed(2)} will be deducted from your wallet now to fund the escrow. '
                  'The fees will be charged automatically upon successful job completion. Do you want to proceed?';

              final confirmed = confirmDialog(msg);
              if (confirmed) {
                await s.handlePostJob();
              }
            }
          },
        },
        [
          if (step == 3 && s.isPostingJob) lIcon('loader-2', cls: 'w-5 h-5 mr-2 animate-spin'),
          Component.text(step == 3 ? (s.isPostingJob ? 'Posting...' : 'Post Job') : 'Continue'),
        ],
      ),
    ]);
  }

  Component _step1(TranyxAppState s, bool isDark) {
    return div(classes: 'space-y-4', [
      // Category selector
      button(
        classes:
            'w-full flex items-center justify-between p-5 rounded-2xl border ${isDark ? "bg-zinc-900 border-zinc-800 hover:border-indigo-500" : "bg-white border-zinc-200 hover:border-indigo-400"} transition-colors',
        events: {
          'click': (_) => s.setState(() {
            s.showCategoryModal = true;
            s.categoryModalForSelect = true;
          }),
        },
        [
          div(classes: 'flex items-center gap-3', [
            lIcon(
              s.selectedCategory?.iconName ?? 'layout-grid',
              cls: 'w-5 h-5 ${isDark ? "text-zinc-500" : "text-zinc-400"}',
            ),
            span(classes: '${isDark ? "text-zinc-400" : "text-zinc-500"} text-sm', [
              Component.text(s.selectedCategory?.label ?? 'Select a Category'),
            ]),
          ]),
          lIcon('chevron-right', cls: 'w-4 h-4 ${isDark ? "text-zinc-600" : "text-zinc-400"}'),
        ],
      ),
      inputField(
        label: 'Job Title',
        placeholder: 'e.g. Fix leaking kitchen sink',
        iconName: 'briefcase',
        isDark: isDark,
        value: s.newJobTitle,
        onChange: (v) => s.setState(() => s.newJobTitle = v),
      ),
      // AI auto-draft
      div(classes: 'relative', [
        div(classes: 'p-4 rounded-2xl border ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200"}', [
          span(classes: 'block text-xs font-medium mb-2 ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
            Component.text('Job Description'),
          ]),
          div(classes: 'flex justify-end mb-2', [
            button(
              classes:
                  'flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold ${isDark ? "bg-indigo-600/20 text-indigo-400 hover:bg-indigo-600/30" : "bg-indigo-50 text-indigo-600 hover:bg-indigo-100"} transition-colors',
              events: {
                'click': (_) async {
                  if (s.isGeneratingDesc || s.newJobTitle.trim().isEmpty) return;
                  s.setState(() => s.isGeneratingDesc = true);
                  final desc = await s.generateJobDesc(s.newJobTitle);
                  s.setState(() {
                    s.newJobDesc = desc;
                    s.isGeneratingDesc = false;
                  });
                },
              },
              [
                if (s.isGeneratingDesc)
                  lIcon('loader-2', cls: 'w-3 h-3 animate-spin')
                else
                  lIcon('sparkles', cls: 'w-3 h-3'),
                Component.text(s.isGeneratingDesc ? ' Generating...' : ' Auto-Draft'),
              ],
            ),
          ]),
          textarea(
            classes:
                'w-full bg-transparent border-none outline-none text-sm ${isDark ? "text-zinc-300" : "text-zinc-700"} min-h-[100px]',
            attributes: {'placeholder': 'Describe the job requirements...'},
            onInput: (value) => s.setState(() => s.newJobDesc = value),
            [Component.text(s.newJobDesc)],
          ),
        ]),
      ]),

      div(classes: 'space-y-2', [
        p(classes: 'text-sm font-semibold', [Component.text('Images (Optional, Max 5)')]),
        div(classes: 'flex flex-wrap gap-2', [
          for (final url in s.jobImageUrls)
            div(
              classes:
                  'relative w-20 h-20 rounded-xl overflow-hidden border ${isDark ? "border-zinc-800" : "border-zinc-200"}',
              [
                img(src: url, classes: 'w-full h-full object-cover'),
                button(
                  classes: 'absolute top-1 right-1 p-1 bg-black/50 rounded-full hover:bg-black/70',
                  events: {'click': (_) => s.setState(() => s.jobImageUrls.remove(url))},
                  [lIcon('x', cls: 'w-3 h-3 text-white')],
                ),
              ],
            ),

          if (s.isUploadingImages)
            div(
              classes:
                  'w-20 h-20 rounded-xl border-2 border-dashed flex items-center justify-center ${isDark ? "border-zinc-700 text-zinc-500" : "border-zinc-300 text-zinc-400"}',
              [
                lIcon('loader-2', cls: 'w-6 h-6 animate-spin'),
              ],
            )
          else if (s.jobImageUrls.length < 5)
            div(
              classes:
                  'relative w-20 h-20 rounded-xl border-2 border-dashed flex items-center justify-center cursor-pointer hover:bg-zinc-500/10 transition-colors ${isDark ? "border-zinc-700 text-zinc-500" : "border-zinc-300 text-zinc-400"}',
              [
                lIcon('camera', cls: 'w-6 h-6'),
                input(
                  type: InputType.file,
                  classes: 'absolute inset-0 opacity-0 cursor-pointer',
                  attributes: {
                    'accept': 'image/*',
                    'multiple': 'true',
                    'id': 'job-photo-upload',
                    'name': 'job_photo_upload',
                  },
                  events: {'change': (e) => s.handleImageUpload(e)},
                ),
              ],
            ),
        ]),
      ]),
      segmentedControl(
        options: const [('Full-time', 'fulltime'), ('Part-time', 'parttime'), ('Contractual', 'contractual')],
        selected: s.empType.name,
        isDark: isDark,
        onChange: (v) => s.setState(() => s.empType = EmpType.values.firstWhere((e) => e.name == v)),
      ),
    ]);
  }

  Component _step2(TranyxAppState s, bool isDark) {
    final isOnSiteOnly = s.selectedJobCategory?.onSiteOnly ?? false;
    if (isOnSiteOnly && s.locType != LocType.onsite) {
      s.locType = LocType.onsite;
    }

    return div(classes: 'space-y-4', [
      segmentedControl(
        options: isOnSiteOnly ? const [('On-site', 'onsite')] : const [('On-site', 'onsite'), ('Remote', 'remote')],
        selected: s.locType.name,
        isDark: isDark,
        onChange: (v) => s.setState(() => s.locType = v == 'onsite' ? LocType.onsite : LocType.remote),
      ),
      if (s.locType == LocType.onsite) ...[
        // Map picker for on-site jobs
        MapPickerComponent(state: s, key: ValueKey('map-${s.hasTracker}-${s.selectedCategory?.id}')),

        inputField(
          label: 'Landmark / Additional Notes (Optional)',
          placeholder: 'e.g. Near SM Mall, gate 2',
          iconName: 'map-pin',
          value: s.jobLandmark,
          onChange: (v) => s.setState(() => s.jobLandmark = v),
          isDark: isDark,
        ),
      ],
      segmentedControl(
        options: const [('Flexible', 'flexible'), ('On Date', 'onDate'), ('Before Date', 'beforeDate')],
        selected: s.jobDateType.name,
        isDark: isDark,
        onChange: (v) => s.setState(() => s.jobDateType = JobDateType.values.firstWhere((e) => e.name == v)),
      ),
      if (s.jobDateType != JobDateType.flexible)
        inputField(
          label: s.jobDateType == JobDateType.onDate ? 'Date of Job' : 'Target Date',
          placeholder: 'YYYY-MM-DD',
          iconName: 'calendar',
          type: 'date',
          value: s.jobDate,
          onChange: (v) => s.setState(() => s.jobDate = v),
          isDark: isDark,
        ),
      segmentedControl(
        options: const [
          ('Morning', 'morning'),
          ('Midday', 'midday'),
          ('Afternoon', 'afternoon'),
          ('Evening', 'evening'),
        ],
        selected: s.timePref.name,
        isDark: isDark,
        onChange: (v) => s.setState(() => s.timePref = TimePref.values.firstWhere((e) => e.name == v)),
      ),
    ]);
  }

  Component _step3(TranyxAppState s, bool isDark) {
    final paymentOpts = [
      ('Daily', 'daily'),
      ('Weekly', 'weekly'),
      ('Fortnightly', 'fortnightly'),
      ('Monthly', 'monthly'),
      ('Package/Fixed', 'packageFixed'),
    ];
    return div(classes: 'space-y-4', [
      div(classes: 'grid grid-cols-2 md:grid-cols-3 gap-2', [
        for (final opt in paymentOpts)
          button(
            classes:
                'py-3 px-3 rounded-xl border text-sm font-medium transition-all ${s.paymentType.name == opt.$2 ? "logo-gradient text-white border-transparent" : (isDark ? "bg-zinc-900 border-zinc-800 text-zinc-400 hover:border-zinc-600" : "bg-white border-zinc-200 text-zinc-600 hover:border-zinc-400")}',
            events: {
              'click': (_) => s.setState(() => s.paymentType = PaymentType.values.firstWhere((e) => e.name == opt.$2)),
            },
            [Component.text(opt.$1)],
          ),
      ]),
      inputField(
        label: 'Amount / Rate (₱)',
        placeholder: '0.00',
        iconName: 'wallet',
        isDark: isDark,
        value: s.priceRate,
        onChange: (v) => s.setState(() => s.priceRate = v),
      ),

      // 48-Hour Inspection Holdback Checkbox
      div(
        classes:
            'flex items-start gap-3 p-4 rounded-2xl border ${isDark ? "bg-zinc-950/40 border-zinc-850" : "bg-zinc-50 border-zinc-150"}',
        [
          input(
            type: InputType.checkbox,
            classes: 'w-5 h-5 rounded-lg border-zinc-300 text-indigo-600 focus:ring-indigo-500 cursor-pointer mt-0.5',
            attributes: s.hasInspectionHoldback ? {'checked': 'true'} : {},
            events: {
              'change': (e) {
                final val = getInputChecked(e.target);
                s.setState(() => s.hasInspectionHoldback = val);
              },
            },
          ),
          div(classes: 'flex-1', [
            p(classes: 'text-xs font-bold ${isDark ? "text-white" : "text-zinc-900"}', [
              Component.text('Enable 48-Hour Inspection Holdback'),
            ]),
            p(classes: 'text-[10px] text-zinc-500 mt-0.5 leading-relaxed', [
              Component.text(
                'Holds 10% of the funds in escrow for 48 hours post-completion to verify services/appliances work before final release to protect your investment.',
              ),
            ]),
          ]),
        ],
      ),

      Builder(
        builder: (context) {
          final basePrice = double.tryParse(s.priceRate) ?? 0.0;
          if (basePrice <= 0) return div([]);
          final txFee = basePrice * 0.07;
          final convFee = basePrice * 0.03;
          final totalFees = txFee + convFee;
          final totalCost = basePrice + totalFees;

          return div(
            classes:
                'p-4 rounded-2xl border ${isDark ? "border-zinc-800 bg-zinc-900/50" : "border-zinc-200 bg-zinc-50"} space-y-3',
            [
              p(classes: 'text-xs font-bold text-indigo-400', [Component.text('Estimated Payment Breakdown')]),
              div(classes: 'space-y-1.5', [
                div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                  span([Component.text('Escrow Deposit (Base Price):')]),
                  span(classes: 'font-semibold ${isDark ? "text-zinc-200" : "text-zinc-700"}', [
                    Component.text('₱ ${basePrice.toStringAsFixed(2)}'),
                  ]),
                ]),
                div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                  span([Component.text('Transaction Fee (7%):')]),
                  span(classes: 'font-semibold text-amber-500', [Component.text('+ ₱ ${txFee.toStringAsFixed(2)}')]),
                ]),
                div(
                  classes:
                      'flex justify-between items-center text-xs text-zinc-400 border-b ${isDark ? "border-zinc-800/60" : "border-zinc-200/60"} pb-2',
                  [
                    span([Component.text('Convenience Fee (3%):')]),
                    span(classes: 'font-semibold text-amber-500', [
                      Component.text('+ ₱ ${convFee.toStringAsFixed(2)}'),
                    ]),
                  ],
                ),
                div(classes: 'flex justify-between items-center pt-1.5', [
                  span(classes: 'text-xs font-semibold text-indigo-400', [Component.text('Total Cost:')]),
                  span(classes: 'text-lg font-black logo-gradient-text', [
                    Component.text('₱ ${totalCost.toStringAsFixed(2)}'),
                  ]),
                ]),
              ]),
              p(classes: 'text-[9px] text-zinc-500 leading-normal', [
                Component.text(
                  'Notice: Only the base price of ₱${basePrice.toStringAsFixed(2)} is deducted from your wallet to fund the escrow now. The 10% platform fee (₱${totalFees.toStringAsFixed(2)}) will only be charged from your wallet upon successful completion of the job.',
                ),
              ]),
            ],
          );
        },
      ),
    ]);
  }
}

// ── Apply ─────────────────────────────────────────────────────
class _ApplyJob extends StatelessComponent {
  final TranyxAppState state;
  const _ApplyJob({required this.state});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    return div(classes: 'space-y-6 animate-fade-up', [
      subViewHeader(
        title: 'Apply for Job',
        isDark: isDark,
        onBack: () => s.setState(() => s.jobsView = JobsView.details),
      ),
      segmentedControl(
        options: const [('Standard Rate', 'standard'), ('Counter-offer', 'counter')],
        selected: s.isCounterOffer ? 'counter' : 'standard',
        isDark: isDark,
        onChange: (v) => s.setState(() => s.isCounterOffer = v == 'counter'),
      ),
      if (s.isCounterOffer)
        inputField(
          label: 'Your Rate (₱)',
          placeholder: '0.00',
          iconName: 'wallet',
          isDark: isDark,
          value: s.applyPriceRate,
          onChange: (v) => s.setState(() => s.applyPriceRate = v),
        ),
      div(classes: 'p-4 rounded-2xl border ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200"}', [
        div(classes: 'flex justify-between items-center mb-2', [
          span(classes: 'text-xs font-medium ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
            Component.text('Cover Note'),
          ]),
          button(
            classes:
                'flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold ${isDark ? "bg-indigo-600/20 text-indigo-400 hover:bg-indigo-600/30" : "bg-indigo-50 text-indigo-600 hover:bg-indigo-100"} transition-colors',
            events: {
              'click': (_) async {
                if (s.isGeneratingCover || s.selectedJob == null) return;
                s.setState(() => s.isGeneratingCover = true);
                final cover = await s.generateCoverNote(s.selectedJob!.title);
                s.setState(() {
                  s.coverNote = cover;
                  s.isGeneratingCover = false;
                });
              },
            },
            [
              if (s.isGeneratingCover)
                lIcon('loader-2', cls: 'w-3 h-3 animate-spin')
              else
                lIcon('sparkles', cls: 'w-3 h-3'),
              Component.text(s.isGeneratingCover ? ' Generating...' : ' Auto-Draft'),
            ],
          ),
        ]),
        textarea(
          classes:
              'w-full bg-transparent border-none outline-none text-sm ${isDark ? "text-zinc-300" : "text-zinc-700"} min-h-[120px]',
          attributes: {'placeholder': 'Write a brief cover note...'},
          onInput: (value) => s.setState(() => s.coverNote = value),
          [Component.text(s.coverNote)],
        ),
      ]),
      button(
        classes:
            'w-full py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
        events: {'click': (_) => s.handleApplyJob()},
        [
          if (s.isSubmittingApplication) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
          Component.text(s.isSubmittingApplication ? 'Submitting...' : 'Submit Application'),
        ],
      ),
    ]);
  }
}

// ── Review Applicants ───────────────────────────────────────────
class _ReviewApplicants extends StatelessComponent {
  final TranyxAppState state;
  const _ReviewApplicants({required this.state});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final job = s.selectedJobData;
    final status = job?['status'] as String? ?? 'Open';
    final catName = (job?['category'] as String? ?? '').toLowerCase();
    final cat = JobCategory.values.firstWhere(
      (e) => e.name.toLowerCase() == catName || e.label.toLowerCase() == catName,
      orElse: () => JobCategory.others,
    );
    final hasTracker = job?['hasTracker'] == true || job?['hasTracker'] == 'true' || cat.hasTracker;

    return div(classes: 'space-y-6 animate-fade-up max-w-3xl', [
      subViewHeader(
        title: 'Review & Manage Job',
        isDark: isDark,
        onBack: () => s.setState(() => s.jobsView = JobsView.details),
      ),

      if (s.isLoadingApplicants)
        div(classes: 'flex justify-center p-8', [lIcon('loader-2', cls: 'w-8 h-8 animate-spin text-indigo-500')])
      else
        Builder(
          builder: (context) {
            final acceptedId = job?['acceptedApplicantId'] as String?;
            final acceptedApp = s.jobApplicants.where((app) => app['applicantUid'] == acceptedId).firstOrNull;
            final otherApplicants = s.jobApplicants.where((app) => app['applicantUid'] != acceptedId).toList();

            return div(classes: 'space-y-6', [
              if (acceptedId != null) ...[
                h2(
                  classes: 'text-sm font-bold text-green-400 uppercase tracking-wider mb-2 flex items-center gap-1.5',
                  [
                    lIcon('check-circle', cls: 'w-4 h-4'),
                    Component.text('Hired Worker'),
                  ],
                ),
                Builder(
                  builder: (context) {
                    final workerName =
                        acceptedApp?['applicantName'] as String? ??
                        s.acceptedApplicantProfile?['name'] as String? ??
                        job?['acceptedApplicantName'] as String? ??
                        'Hired Nyxian';
                    final workerPhotoUrl =
                        acceptedApp?['applicantPhotoUrl'] as String? ??
                        s.acceptedApplicantProfile?['photoUrl'] as String? ??
                        job?['acceptedApplicantPhotoUrl'] as String? ??
                        '';
                    final propRate = acceptedApp?['proposalRate'] ?? job?['pricingValue'] ?? 0.0;
                    final isCounter = acceptedApp?['isCounterOffer'] == true;
                    final isBonded =
                        acceptedApp?['isBonded'] == true || s.acceptedApplicantProfile?['isBonded'] == true;
                    final coverNote = acceptedApp?['coverNote'] as String? ?? 'Currently working on this job.';

                    return div(
                      classes:
                          'p-5 rounded-2xl border border-green-500/30 bg-green-500/10 flex flex-col md:flex-row md:items-center justify-between gap-4 shadow-lg shadow-green-500/5',
                      [
                        button(
                          classes:
                              'flex items-center gap-3 text-left hover:opacity-85 transition-opacity cursor-pointer border-none bg-transparent p-0',
                          events: {'click': (_) => s.viewEmployerProfile(acceptedId)},
                          [
                            div(classes: 'w-12 h-12 rounded-full overflow-hidden bg-zinc-800 flex-shrink-0', [
                              if (workerPhotoUrl.isNotEmpty)
                                img(src: workerPhotoUrl, classes: 'w-full h-full object-cover')
                              else
                                div(
                                  classes:
                                      'w-full h-full flex items-center justify-center logo-gradient text-white font-bold',
                                  [Component.text(workerName.substring(0, 1).toUpperCase())],
                                ),
                            ]),
                            div([
                              p(classes: 'font-bold hover:underline text-zinc-150', [
                                Component.text(workerName),
                              ]),
                              p(classes: 'text-sm font-semibold text-green-400', [
                                Component.text(isCounter ? 'Counter Rate: ₱ $propRate' : 'Standard Rate: ₱ $propRate'),
                              ]),
                              div(classes: 'flex flex-wrap gap-1.5 mt-1.5', [
                                if (isBonded)
                                  span(
                                    classes:
                                        'px-2 py-0.5 rounded-lg text-[9px] font-bold bg-green-500/15 text-green-400 border border-green-500/25 flex items-center gap-0.5',
                                    [
                                      lIcon('shield-check', cls: 'w-2.5 h-2.5'),
                                      Component.text('Bonded & Protected'),
                                    ],
                                  ),
                              ]),
                            ]),
                          ],
                        ),
                        div(classes: 'flex-1 text-sm ${isDark ? "text-zinc-400" : "text-zinc-650"} md:px-4', [
                          Component.text(coverNote),
                        ]),
                        button(
                          classes:
                              'px-5 py-2.5 rounded-xl font-bold text-white bg-green-500 hover:bg-green-400 transition-colors flex items-center gap-2 text-sm whitespace-nowrap relative',
                          events: {'click': (_) => s.openChat(job!['id'] as String)},
                          [
                            lIcon('message-square', cls: 'w-4 h-4'),
                            Component.text('Chat with Worker'),
                            if (s.getUnreadChatCount(job!['id'] as String) > 0)
                              span(
                                classes:
                                    'absolute -top-1.5 -right-1.5 px-2 py-0.5 text-xs font-black text-white bg-red-500 rounded-full border-2 border-white animate-pulse',
                                [Component.text('${s.getUnreadChatCount(job['id'] as String)}')],
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],

              if (otherApplicants.isNotEmpty) ...[
                details(
                  classes:
                      'group border ${isDark ? "border-zinc-800 bg-zinc-900/10" : "border-zinc-200 bg-zinc-50/50"} rounded-2xl p-4',
                  attributes: acceptedId == null ? {'open': 'true'} : {},
                  [
                    summary(
                      classes:
                          'font-bold text-sm cursor-pointer select-none flex items-center justify-between outline-none text-zinc-400 hover:text-zinc-300 transition-colors',
                      [
                        Component.text(
                          acceptedId != null
                              ? 'Other Applicants (${otherApplicants.length})'
                              : 'Applicants (${otherApplicants.length})',
                        ),
                        lIcon('chevron-down', cls: 'w-4 h-4 group-open:rotate-180 transition-transform text-zinc-500'),
                      ],
                    ),
                    div(classes: 'mt-4 space-y-4', [
                      for (final app in otherApplicants)
                        div(
                          classes:
                              'p-5 rounded-2xl border ${isDark ? "bg-zinc-900 border-zinc-800/80" : "bg-white border-zinc-200 shadow-sm"} flex flex-col md:flex-row md:items-center justify-between gap-4',
                          [
                            button(
                              classes:
                                  'flex items-center gap-3 text-left hover:opacity-85 transition-opacity cursor-pointer border-none bg-transparent p-0',
                              events: {'click': (_) => s.viewEmployerProfile(app['applicantUid'] as String)},
                              [
                                div(classes: 'w-12 h-12 rounded-full overflow-hidden bg-zinc-800 flex-shrink-0', [
                                  if ((app['applicantPhotoUrl'] as String?)?.isNotEmpty ?? false)
                                    img(src: app['applicantPhotoUrl'] as String, classes: 'w-full h-full object-cover')
                                  else
                                    div(
                                      classes:
                                          'w-full h-full flex items-center justify-center logo-gradient text-white font-bold',
                                      [
                                        Component.text(
                                          (app['applicantName'] as String?)?.substring(0, 1).toUpperCase() ?? '?',
                                        ),
                                      ],
                                    ),
                                ]),
                                div([
                                  p(classes: 'font-bold hover:underline', [
                                    Component.text(app['applicantName'] as String? ?? 'Anonymous'),
                                  ]),
                                  if (app['isCounterOffer'] == true)
                                    p(classes: 'text-sm font-semibold text-orange-400', [
                                      Component.text('Counter Offer: ₱ ${app['proposalRate']}'),
                                    ])
                                  else
                                    p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-650"}', [
                                      Component.text('Standard Rate'),
                                    ]),
                                  div(classes: 'flex flex-wrap gap-1.5 mt-1.5', [
                                    if (app['isBonded'] == true)
                                      span(
                                        classes:
                                            'px-2 py-0.5 rounded-lg text-[9px] font-bold bg-green-500/15 text-green-400 border border-green-500/25 flex items-center gap-0.5',
                                        [
                                          lIcon('shield-check', cls: 'w-2.5 h-2.5'),
                                          Component.text('Bonded & Protected'),
                                        ],
                                      ),
                                    if (app['certificationUrls'] != null &&
                                        (app['certificationUrls'] as List).isNotEmpty)
                                      span(
                                        classes:
                                            'px-2 py-0.5 rounded-lg text-[9px] font-bold bg-indigo-500/15 text-indigo-400 border border-indigo-500/25 flex items-center gap-0.5',
                                        [
                                          lIcon('award', cls: 'w-2.5 h-2.5'),
                                          Component.text(
                                            'Credentials Verified (${(app['certificationUrls'] as List).length})',
                                          ),
                                        ],
                                      ),
                                  ]),
                                ]),
                              ],
                            ),
                            div(classes: 'flex-1 text-sm ${isDark ? "text-zinc-400" : "text-zinc-650"} md:px-4', [
                              Component.text(app['coverNote'] as String? ?? 'No cover note provided.'),
                            ]),
                            if (status == 'Open' && acceptedId == null)
                              button(
                                classes:
                                    'px-6 py-2 rounded-xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity whitespace-nowrap flex items-center gap-2',
                                events: {'click': (_) => s.acceptApplicant(job!['id'], app)},
                                [
                                  if (s.isUpdatingJobStatus) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
                                  Component.text('Accept'),
                                ],
                              )
                            else
                              span(classes: 'text-xs text-zinc-550 font-bold uppercase tracking-wider', [
                                Component.text('Not Selected'),
                              ]),
                          ],
                        ),
                    ]),
                  ],
                ),
              ] else if (acceptedId == null) ...[
                div(
                  classes:
                      'p-8 text-center text-zinc-500 rounded-2xl border border-dashed ${isDark ? "border-zinc-800" : "border-zinc-200"}',
                  [Component.text('No applicants yet.')],
                ),
              ],
            ]);
          },
        ),
      if (status == 'In Progress' ||
          status == 'onGoing' ||
          status == 'ongoing' ||
          status == 'in_progress' ||
          status == 'heading_to_pickup' ||
          status == 'arrived_pickup' ||
          status == 'paid_cashier' ||
          status == 'in_transit') ...[
        div(classes: 'p-8 rounded-3xl border border-blue-500/30 bg-blue-500/10 text-center space-y-4', [
          lIcon('briefcase', cls: 'w-12 h-12 text-blue-400 mx-auto'),
          h2(classes: 'text-2xl font-bold text-blue-400', [Component.text('Job is In Progress')]),
          p(classes: isDark ? "text-zinc-300" : "text-zinc-700", [
            Component.text('An applicant has been accepted and is working on this gig.'),
          ]),
        ]),
        if ((job?['receiptUrl'] as String?) != null)
          div(classes: 'p-6 rounded-3xl border border-indigo-500/20 bg-indigo-500/5 space-y-3', [
            div(classes: 'flex items-center gap-2 text-indigo-400 font-bold text-sm', [
              lIcon('receipt', cls: 'w-5 h-5'),
              Component.text('Receipt / Item Photo'),
            ]),
            div(classes: 'rounded-2xl overflow-hidden border ${isDark ? "border-zinc-800" : "border-zinc-200"}', [
              img(
                src: job!['receiptUrl'] as String,
                classes: 'w-full h-auto max-h-96 object-cover cursor-zoom-in hover:opacity-90 transition-opacity',
                events: {
                  'click': (_) => s.showFullScreenPhoto(job['receiptUrl'] as String),
                },
              ),
            ]),
          ]),
      ] else if (status == 'Done' || status == 'arrived_dropoff') ...[
        if (hasTracker) ...[
          div(classes: 'p-8 rounded-3xl border border-green-500/30 bg-green-500/10 text-center space-y-4', [
            lIcon('check-circle', cls: 'w-12 h-12 text-green-400 mx-auto'),
            h2(classes: 'text-2xl font-bold text-green-400', [Component.text('Delivery Ready for Verification')]),
            p(classes: isDark ? "text-zinc-300" : "text-zinc-700", [
              Component.text('The Nyxian has arrived at the destination.'),
            ]),
            p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
              Component.text("Enter the Nyxian's completion code to verify and release payment."),
            ]),
            button(
              classes:
                  'px-8 py-3 rounded-2xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity inline-flex items-center gap-2',
              events: {'click': (_) => s.setState(() => s.showCompletionScanner = true)},
              [
                lIcon('key', cls: 'w-5 h-5'),
                Component.text('Enter Completion Code'),
              ],
            ),
          ]),
        ] else ...[
          div(classes: 'p-8 rounded-3xl border border-green-500/30 bg-green-500/10 text-center space-y-4', [
            lIcon('check-circle', cls: 'w-12 h-12 text-green-400 mx-auto'),
            h2(classes: 'text-2xl font-bold text-green-400', [Component.text('Task Ready for Payment')]),
            p(classes: isDark ? "text-zinc-300" : "text-zinc-700", [
              Component.text('The Nyxian has completed the task.'),
            ]),
            p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
              Component.text('Generate the payment code and show it to the Nyxian to release the payout.'),
            ]),
            button(
              classes:
                  'px-8 py-3 rounded-2xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity inline-flex items-center gap-2',
              events: {'click': (_) => s.generateCompletionCode()},
              [
                if (s.isGeneratingCode) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                lIcon('qr-code', cls: 'w-5 h-5'),
                Component.text(s.isGeneratingCode ? 'Generating...' : ' Generate Payment Code'),
              ],
            ),
          ]),
        ],
        if ((job?['receiptUrl'] as String?) != null)
          div(classes: 'p-6 rounded-3xl border border-indigo-500/20 bg-indigo-500/5 space-y-3', [
            div(classes: 'flex items-center gap-2 text-indigo-400 font-bold text-sm', [
              lIcon('receipt', cls: 'w-5 h-5'),
              Component.text('Receipt / Item Photo'),
            ]),
            div(classes: 'rounded-2xl overflow-hidden border ${isDark ? "border-zinc-800" : "border-zinc-200"}', [
              img(
                src: job!['receiptUrl'] as String,
                classes: 'w-full h-auto max-h-96 object-cover cursor-zoom-in hover:opacity-90 transition-opacity',
                events: {
                  'click': (_) => s.showFullScreenPhoto(job['receiptUrl'] as String),
                },
              ),
            ]),
          ]),
      ] else if (status == 'Completed' || status == 'completed') ...[
        div(classes: 'p-8 rounded-3xl border border-green-500/30 bg-green-500/10 text-center space-y-4', [
          lIcon('check-circle', cls: 'w-12 h-12 text-green-400 mx-auto'),
          h2(classes: 'text-2xl font-bold text-green-400', [Component.text('Job Completed')]),
          p(classes: isDark ? "text-zinc-300" : "text-zinc-700", [
            Component.text('This job has been successfully finished.'),
          ]),
        ]),
        if ((job?['receiptUrl'] as String?) != null)
          div(classes: 'p-6 rounded-3xl border border-indigo-500/20 bg-indigo-500/5 space-y-3', [
            div(classes: 'flex items-center gap-2 text-indigo-400 font-bold text-sm', [
              lIcon('receipt', cls: 'w-5 h-5'),
              Component.text('Receipt / Item Photo'),
            ]),
            div(classes: 'rounded-2xl overflow-hidden border ${isDark ? "border-zinc-800" : "border-zinc-200"}', [
              img(
                src: job!['receiptUrl'] as String,
                classes: 'w-full h-auto max-h-96 object-cover cursor-zoom-in hover:opacity-90 transition-opacity',
                events: {
                  'click': (_) => s.showFullScreenPhoto(job['receiptUrl'] as String),
                },
              ),
            ]),
          ]),
      ],
      if ((job?['pickupLat'] != null) && (job?['destinationLat'] != null))
        NavigationMapComponent(state: s, isNyxian: false),
    ]);
  }
}

// ── Success ───────────────────────────────────────────────────
class _SuccessScreen extends StatelessComponent {
  final TranyxAppState state;
  const _SuccessScreen({required this.state});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final isNyxian = s.currentViewMode == AccountType.nyxian;
    return div(classes: 'flex flex-col items-center justify-center text-center py-20 animate-fade-up', [
      div(classes: 'p-6 rounded-3xl bg-green-500/10 border border-green-500/20 mb-6 inline-flex', [
        lIcon('check-circle-2', cls: 'w-14 h-14 text-green-400'),
      ]),
      h2(classes: 'text-2xl font-bold mb-2', [
        Component.text(isNyxian ? 'Application Sent!' : 'Job Posted!'),
      ]),
      p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-600"} max-w-xs mb-8', [
        Component.text(
          isNyxian
              ? 'Your application has been submitted. The employer will review it shortly.'
              : 'Your job listing is now live. Nyxians can start applying immediately.',
        ),
      ]),
      button(
        classes: 'px-8 py-3 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity',
        events: {
          'click': (_) => s.setState(() {
            s.jobsView = JobsView.list;
            s.createStep = 1;
          }),
        },
        [Component.text('Back to Jobs')],
      ),
    ]);
  }
}
