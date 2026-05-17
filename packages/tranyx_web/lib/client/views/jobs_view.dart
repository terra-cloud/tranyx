import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:tranyx_web/components/map_picker.dart';
import 'package:tranyx_web/components/navigation_map.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
import 'package:shared/shared.dart';

class JobsViewComponent extends StatelessComponent {
  final TranyxAppState state;
  const JobsViewComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final isNyxian = s.currentViewMode == AccountType.nyxian;

    if (s.jobsView == JobsView.list) {
      final displayJobs = isNyxian ? _getFilteredJobs(s.availableJobs, s) : _getFilteredJobs(s.myJobs, s);

      return div(classes: 'flex flex-col md:flex-row gap-6 animate-fade-up', [
        // Left list pane
        div(classes: 'w-full md:w-80 flex-shrink-0 space-y-4', [
          div(classes: 'flex items-center justify-between', [
            h2(classes: 'text-xl font-bold', [Component.text(isNyxian ? 'Available Gigs' : 'My Postings')]),
            if (!isNyxian)
              button(
                classes: 'flex items-center gap-1 px-4 py-2 rounded-xl text-sm font-semibold text-white logo-gradient',
                events: {'click': (_) => s.setState(() => s.jobsView = JobsView.create)},
                [lIcon('plus', cls: 'w-4 h-4'), Component.text(' New')],
              ),
          ]),

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

          // Filters for both
          div(classes: 'flex gap-2 flex-wrap', [
            _filterChip('Recommended', s.activeJobFilter == 'Recommended', isDark, s),
            _filterChip('High Paying', s.activeJobFilter == 'High Paying', isDark, s),
            _filterChip('Near Me', s.activeJobFilter == 'Near Me', isDark, s),
            _filterChip('All', s.activeJobFilter == 'All', isDark, s),
          ]),

          div(classes: 'space-y-3', [
            if (s.isLoadingJobs)
              div(classes: 'flex justify-center p-4', [lIcon('loader-2', cls: 'w-6 h-6 animate-spin text-indigo-500')])
            else if (s.jobsError != null)
              div(classes: 'p-4 text-sm text-red-500 bg-red-500/10 rounded-xl', [Component.text(s.jobsError!)])
            else if (isNyxian)
              if (displayJobs.isEmpty)
                div(classes: 'p-4 text-center text-zinc-500 text-sm', [
                  Component.text('No available gigs match your filters.'),
                ])
              else
                for (final j in displayJobs) _nyxianCard(j, isDark, s)
            else ...[
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

    if (s.jobsView == JobsView.create) return _CreateJob(state: s).build(context);
    if (s.jobsView == JobsView.details) return _JobDetails(state: s).build(context);
    if (s.jobsView == JobsView.apply) return _ApplyJob(state: s).build(context);
    if (s.jobsView == JobsView.review) return _ReviewApplicants(state: s).build(context);
    if (s.jobsView == JobsView.success) return _SuccessScreen(state: s).build(context);
    return div([]);
  }

  List<Map<String, dynamic>> _getFilteredJobs(List<Map<String, dynamic>> jobs, TranyxAppState s) {
    if (s.activeJobFilter == 'All') return jobs;

    if (s.activeJobFilter == 'Recommended') {
      var skills = s.userProfile?.skills ?? [];
      if (skills.isEmpty) {
        skills = ['Electrical', 'Plumbing', 'Painting', 'Carpentry', 'Cleaning', 'IT'];
      }
      return jobs.where((j) {
        final cat = (j['category'] as String?)?.toLowerCase() ?? '';
        final catLabel = (j['categoryLabel'] as String?)?.toLowerCase() ?? '';
        final desc = (j['description'] as String?)?.toLowerCase() ?? '';
        final title = (j['title'] as String?)?.toLowerCase() ?? '';
        return skills.any((skill) {
          final sLower = skill.toLowerCase();
          return cat.contains(sLower) || catLabel.contains(sLower) || desc.contains(sLower) || title.contains(sLower);
        });
      }).toList();
    }

    if (s.activeJobFilter == 'High Paying') {
      return jobs.where((j) {
        final val = (j['pricingValue'] as num?)?.toDouble() ?? 0.0;
        return val >= 1000;
      }).toList();
    }

    // Apply home search query text filter
    if (s.homeSearchQuery.isNotEmpty) {
      final q = s.homeSearchQuery.toLowerCase();
      return jobs.where((j) {
        final title = (j['title'] as String?)?.toLowerCase() ?? '';
        final desc = (j['description'] as String?)?.toLowerCase() ?? '';
        final cat = (j['category'] as String?)?.toLowerCase() ?? '';
        return title.contains(q) || desc.contains(q) || cat.contains(q);
      }).toList();
    }

    return jobs;
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
    return button(
      classes:
          'w-full p-4 rounded-2xl border-2 border-dashed ${isDark ? "border-zinc-700 hover:border-indigo-500" : "border-zinc-300 hover:border-indigo-400"} transition-colors flex items-center justify-center gap-2 ${isDark ? "text-zinc-500 hover:text-indigo-400" : "text-zinc-400 hover:text-indigo-500"}',
      events: {'click': (_) => s.setState(() => s.jobsView = JobsView.create)},
      [lIcon('plus', cls: 'w-5 h-5'), Component.text('Create New Listing')],
    );
  }

  Component _employerCard(Map<String, dynamic> j, bool isDark, TranyxAppState s) {
    final title = j['title'] as String? ?? 'Untitled';
    final status = j['status'] as String? ?? 'Open';
    final applicants = (j['applicantCount'] as int?) ?? 0;
    final pricingValue = (j['pricingValue'] as num?)?.toDouble() ?? 0.0;
    final pricingType = j['pricingType'] as String? ?? '';
    final rate = pricingValue > 0
        ? '₱ ${pricingValue.toStringAsFixed(0)}${pricingType.isNotEmpty ? " / $pricingType" : ""}'
        : 'Negotiable';
    final isActive = status == 'Active' || status == 'Open';
    final statusCls = isActive ? 'bg-green-500/20 text-green-400' : 'bg-amber-500/20 text-amber-400';
    final cardCls = isDark
        ? 'bg-zinc-900 border-zinc-800 hover:border-zinc-700'
        : 'bg-white border-zinc-200 shadow-sm hover:shadow-md';
    return div(classes: 'p-4 rounded-2xl border transition-all $cardCls', [
      div(classes: 'flex items-start justify-between mb-3', [
        p(classes: 'font-semibold text-sm flex-1 pr-2', [Component.text(title)]),
        span(classes: 'px-2 py-0.5 rounded text-[10px] font-bold $statusCls', [Component.text(status.toUpperCase())]),
      ]),
      p(classes: 'text-xs ${isDark ? "text-indigo-400" : "text-indigo-600"} font-semibold mb-2', [
        Component.text(rate),
      ]),
      div(classes: 'flex items-center justify-between', [
        div(classes: 'flex items-center gap-1 text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
          lIcon('users', cls: 'w-3 h-3'),
          Component.text(' $applicants applicants'),
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
    final title = j['title'] as String? ?? 'Untitled';
    final status = j['status'] as String? ?? 'Open';
    final pricingValue = (j['pricingValue'] as num?)?.toDouble() ?? 0.0;
    final pricingType = j['pricingType'] as String? ?? '';
    final rate = pricingValue > 0
        ? '₱ ${pricingValue.toStringAsFixed(0)}${pricingType.isNotEmpty ? " / $pricingType" : ""}'
        : 'Negotiable';
    final locationType = j['locationType'] as String? ?? 'Remote';
    final dateReq = j['dateRequirement'] as String? ?? 'Flexible';
    final isUrgent = dateReq == 'On Date';

    final badgeText = status == 'Open' ? dateReq.toUpperCase() : status.toUpperCase();
    final badgeCls = status == 'In Progress'
        ? 'bg-green-500/20 text-green-400 animate-pulse'
        : status == 'Completed'
        ? 'bg-zinc-700/50 text-zinc-400'
        : (isUrgent ? 'bg-red-500/20 text-red-400' : 'bg-zinc-700 text-zinc-300');

    final cardCls = isDark
        ? 'bg-zinc-900 border-zinc-800 hover:border-zinc-700'
        : 'bg-white border-zinc-200 shadow-sm hover:shadow-md';
    return div(classes: 'p-4 rounded-2xl border transition-all $cardCls', [
      div(classes: 'flex items-start justify-between mb-3', [
        p(classes: 'font-semibold text-sm flex-1 pr-2', [Component.text(title)]),
        span(classes: 'px-2 py-0.5 rounded text-[10px] font-bold $badgeCls', [Component.text(badgeText)]),
      ]),
      div(classes: 'flex items-center justify-between', [
        div(classes: 'flex items-center gap-3 text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
          span(classes: 'font-bold text-indigo-400 text-sm', [Component.text(rate)]),
          div(classes: 'flex items-center gap-1', [lIcon('map-pin', cls: 'w-3 h-3'), Component.text(locationType)]),
        ]),
        button(
          classes: 'px-3 py-1.5 rounded-lg text-xs font-semibold logo-gradient text-white',
          events: {'click': (_) => s.selectJobAndLoadDetails(j)},
          [Component.text('View')],
        ),
      ]),
    ]);
  }
}

// ── Job Details ───────────────────────────────────────────────
class _JobDetails extends StatelessComponent {
  final TranyxAppState state;
  const _JobDetails({required this.state});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final job = s.selectedJob;
    final isNyxian = s.currentViewMode == AccountType.nyxian;
    final status = s.selectedJobData?['status'] as String? ?? 'Open';
    if (job == null) return div([]);

    final applicantUids = List<String>.from(s.selectedJobData?['applicantUids'] as List? ?? []);
    final hasApplied = applicantUids.contains(s.userProfile?.uid);

    final reportedBy = List<String>.from(s.selectedJobData?['reportedByUids'] as List? ?? []);
    final hasReported = reportedBy.contains(s.userProfile?.uid);

    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    return div(classes: 'space-y-6 animate-fade-up', [
      subViewHeader(
        title: job.title,
        isDark: isDark,
        onBack: () => s.setState(() {
          s.jobsView = JobsView.list;
          s.selectedJob = null;
        }),
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

      // Creator info
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
                if ((s.selectedJobData?['creatorPhotoUrl'] as String?)?.isNotEmpty ?? false)
                  img(src: s.selectedJobData!['creatorPhotoUrl'] as String, classes: 'w-full h-full object-cover')
                else
                  span(classes: 'text-sm font-bold text-white', [
                    Component.text(
                      ((s.selectedJobData?['creatorName'] as String?) ?? '?').isNotEmpty
                          ? (s.selectedJobData!['creatorName'] as String)[0].toUpperCase()
                          : '?',
                    ),
                  ]),
              ],
            ),
            div([
              p(classes: 'font-semibold text-sm', [
                Component.text(s.selectedJobData?['creatorName'] as String? ?? 'Unknown'),
              ]),
              p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                Component.text(s.selectedJobData?['category'] as String? ?? ''),
              ]),
            ]),
          ]),
          lIcon('chevron-right', cls: 'w-4 h-4 ${isDark ? "text-zinc-600" : "text-zinc-400"}'),
        ],
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

      if (s.selectedJobData?['imageUrls'] != null && (s.selectedJobData!['imageUrls'] as List).isNotEmpty)
        div(classes: 'p-5 rounded-2xl border $cardCls overflow-hidden', [
          p(classes: 'font-semibold mb-3', [Component.text('Attachments')]),
          div(classes: 'flex gap-3 overflow-x-auto pb-2 snap-x', [
            for (final url in s.selectedJobData!['imageUrls'] as List)
              div(
                classes:
                    'w-48 h-32 flex-shrink-0 snap-center rounded-xl overflow-hidden border ${isDark ? "border-zinc-800" : "border-zinc-200"}',
                [
                  img(
                    src: url as String,
                    classes:
                        'w-full h-full object-cover hover:scale-105 transition-transform duration-300 cursor-pointer',
                  ),
                ],
              ),
          ]),
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

          if (isNyxian) {
            // --- NYXIAN VIEW ---
            if (isAccepted && status == 'In Progress') {
              // Show completion QR for the Nyxian to display at job site
              return div(classes: 'space-y-3', [
                div(
                  classes: 'p-4 rounded-2xl border border-green-500/30 bg-green-500/10 flex items-center gap-3',
                  [
                    lIcon('zap', cls: 'w-5 h-5 text-green-400'),
                    div([
                      p(classes: 'font-bold text-green-400 text-sm', [Component.text('Job In Progress')]),
                      p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                        Component.text(
                          'Show the QR code or code below to the employer to release payment upon completion.',
                        ),
                      ]),
                    ]),
                  ],
                ),
                div(classes: 'flex gap-3', [
                  button(
                    classes: hasReported
                        ? 'py-4 px-5 rounded-2xl font-semibold border border-zinc-500 text-zinc-500 opacity-50 cursor-not-allowed'
                        : 'py-4 px-5 rounded-2xl font-semibold border ${isDark ? "border-red-500/30 text-red-400 hover:bg-red-500/10" : "border-red-200 text-red-500 hover:bg-red-50"} transition-colors',
                    attributes: hasReported ? {'disabled': 'true'} : {},
                    events: hasReported ? {} : {'click': (_) => s.handleReportJob()},
                    [lIcon('flag', cls: 'w-5 h-5')],
                  ),
                  button(
                    classes:
                        'flex-1 py-4 rounded-2xl font-semibold text-white bg-green-600 hover:bg-green-500 transition-colors flex items-center justify-center gap-2',
                    events: {'click': (_) => s.generateCompletionCode()},
                    [lIcon('qr-code', cls: 'w-5 h-5'), Component.text(' Show Completion Code')],
                  ),
                ]),
                // Navigation map — shown when employer enabled tracker
                if ((s.selectedJobData?['hasTracker'] as bool? ?? false) &&
                    s.selectedJobData?['pickupLat'] != null &&
                    s.selectedJobData?['destinationLat'] != null)
                  NavigationMapComponent(state: s, isNyxian: true),
              ]);
            }

            if (status == 'Completed') {
              return div(
                classes: 'p-4 rounded-2xl border border-zinc-700 bg-zinc-800/40 flex items-center gap-3',
                [
                  lIcon('check-circle', cls: 'w-6 h-6 text-green-400'),
                  div([
                    p(classes: 'font-bold text-green-400 text-sm', [Component.text('Job Completed')]),
                    p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                      Component.text('Payment has been transferred to your Tyxbit wallet.'),
                    ]),
                  ]),
                ],
              );
            }

            // Default: Open / Applied
            return div(classes: 'flex gap-3', [
              button(
                classes: hasReported
                    ? 'py-4 px-6 rounded-2xl font-semibold border bg-zinc-400 opacity-50 cursor-not-allowed border-zinc-500 text-zinc-100'
                    : 'py-4 px-6 rounded-2xl font-semibold border ${isDark ? "border-red-500/30 text-red-400 hover:bg-red-500/10" : "border-red-200 text-red-500 hover:bg-red-50"} transition-colors',
                attributes: hasReported ? {'disabled': 'true'} : {},
                events: hasReported ? {} : {'click': (_) => s.handleReportJob()},
                [lIcon('flag', cls: 'w-5 h-5')],
              ),
              button(
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
              ),
            ]);
          } else {
            if (status == 'In Progress') {
              return button(
                classes:
                    'w-full py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity',
                events: {'click': (_) => s.handleUpdateNyxianSubStatus('arrived_destination')},
                [Component.text('Mark as Done')],
              );
            }

            if (status == 'Done') {
              return div(classes: 'space-y-3', [
                div(classes: 'p-4 rounded-2xl border border-indigo-500/30 bg-indigo-500/10 flex items-center gap-3', [
                  lIcon('check-circle', cls: 'w-5 h-5 text-indigo-400'),
                  div([
                    p(classes: 'font-bold text-indigo-400 text-sm', [Component.text('Task Completed')]),
                    p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                      Component.text('Waiting for Employer to generate payment code.'),
                    ]),
                  ]),
                ]),
                button(
                  classes:
                      'w-full py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
                  events: {'click': (_) => s.setState(() => s.showCompletionScanner = true)},
                  [lIcon('key', cls: 'w-5 h-5'), Component.text('Enter Payment Code')],
                ),
              ]);
            }

            if (status == 'Completed') {
              return div(
                classes: 'p-4 rounded-2xl border border-green-500/30 bg-green-500/10 flex items-center gap-3',
                [
                  lIcon('heart', cls: 'w-6 h-6 text-green-400'),
                  div([
                    p(classes: 'font-bold text-green-400 text-sm', [Component.text('Job Completed & Paid')]),
                    p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                      Component.text('Payment has been transferred to your Tyxbit wallet.'),
                    ]),
                  ]),
                ],
              );
            }

            // --- EMPLOYER VIEW ---
            if (status == 'In Progress') {
              return div(classes: 'p-4 rounded-2xl border border-blue-500/30 bg-blue-500/10 flex items-center gap-3', [
                lIcon('clock', cls: 'w-5 h-5 text-blue-400'),
                div([
                  p(classes: 'font-bold text-blue-400 text-sm', [Component.text('Work In Progress')]),
                  p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                    Component.text('Nyxian is currently working on your task.'),
                  ]),
                ]),
              ]);
            }

            if (status == 'Done') {
              return div(classes: 'space-y-3', [
                div(classes: 'p-4 rounded-2xl border border-green-500/30 bg-green-500/10 flex items-center gap-3', [
                  lIcon('check-circle', cls: 'w-5 h-5 text-green-400'),
                  div([
                    p(classes: 'font-bold text-green-400 text-sm', [Component.text('Task Ready for Payment')]),
                    p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                      Component.text('The Nyxian has marked the task as done. Generate a code to release escrow.'),
                    ]),
                  ]),
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

            // Default: Open job employer management buttons
            return div(classes: 'flex gap-3', [
              if (job.applicants == 0)
                button(
                  classes:
                      'flex-1 py-4 rounded-2xl font-semibold ${isDark ? "bg-zinc-800 hover:bg-zinc-700 text-zinc-200" : "bg-zinc-100 hover:bg-zinc-200 text-zinc-700"} transition-colors flex items-center justify-center gap-2',
                  events: {},
                  [lIcon('edit-2', cls: 'w-4 h-4'), Component.text(' Edit')],
                ),
              button(
                classes:
                    'flex-1 py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
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

      // QR Completion Scanner / Code Modal (for Nyxian to ENTER code)
      if (s.showCompletionScanner && isNyxian)
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
              div(
                classes:
                    'p-4 rounded-xl border ${isDark ? "border-zinc-800 bg-zinc-800/50" : "border-zinc-200 bg-zinc-50"}',
                [
                  p(
                    classes: 'text-xs font-semibold uppercase tracking-wider text-indigo-400 mb-1',
                    [Component.text('Payout Amount')],
                  ),
                  p(classes: 'text-3xl font-bold logo-gradient-text', [
                    Component.text(
                      '${((s.selectedJobData?['pricingValue'] as num?)?.toDouble() ?? 0.0 * 0.97).toStringAsFixed(2)} Tyxbits',
                    ),
                  ]),
                  p(classes: 'text-[10px] text-zinc-500 mt-1', [Component.text('3% convenience fee included')]),
                ],
              ),
              div(classes: 'space-y-2', [
                p(
                  classes: 'text-sm font-semibold ${isDark ? "text-zinc-300" : "text-zinc-700"}',
                  [Component.text('Enter the 6-digit code from the Employer:')],
                ),
                input(
                  type: InputType.text,
                  classes:
                      'w-full px-4 py-4 text-center text-3xl font-black tracking-widest rounded-xl border ${isDark ? "bg-zinc-800 border-zinc-700 text-white focus:border-indigo-500" : "bg-white border-zinc-200 text-zinc-900 focus:border-indigo-500"} outline-none transition-colors',
                  attributes: {'placeholder': '------', 'maxlength': '6'},
                  events: {
                    'input': (e) => s.setState(() {
                      // ignore: avoid_dynamic_calls
                      s.completionScanInput = (e as dynamic).target?.value as String? ?? '';
                    }),
                  },
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
                    Component.text(s.isCompletingJob ? 'Verifying...' : 'Release Payment'),
                  ],
                ),
              ]),
            ],
          ),
        ]),

      // Display Generated Code for Employer
      if (s.generatedCompletionCode != null && !isNyxian && status == 'Done')
        div(classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm', [
          div(
            classes:
                'w-full max-w-md p-8 rounded-[2.5rem] ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"} shadow-2xl animate-fade-up flex flex-col items-center gap-6',
            [
              div(classes: 'text-center', [
                h3(classes: 'text-2xl font-black mb-2', [Component.text('Payment Code')]),
                p(classes: 'text-sm text-zinc-500', [
                  Component.text('Ask the Nyxian to enter this code on their device.'),
                ]),
              ]),

              // QR Code
              div(classes: 'p-4 bg-white rounded-3xl shadow-inner', [
                img(
                  src: 'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${s.generatedCompletionCode}',
                  classes: 'w-48 h-48',
                ),
              ]),

              div(classes: 'text-center', [
                p(classes: 'text-[10px] font-black uppercase tracking-widest text-zinc-500 mb-1', [
                  Component.text('Manual Code'),
                ]),
                p(classes: 'text-4xl font-black tracking-[0.5em] text-indigo-500', [
                  Component.text(s.generatedCompletionCode!),
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

      if (s.showDepositModal)
        div(classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm', [
          div(
            classes:
                'w-full max-w-md p-6 rounded-3xl ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"} shadow-2xl animate-fade-up flex flex-col',
            [
              div(classes: 'flex items-center gap-3 mb-4', [
                div(classes: 'p-3 bg-blue-500/20 rounded-xl', [lIcon('wallet', cls: 'w-6 h-6 text-blue-500')]),
                h3(classes: 'text-xl font-bold', [Component.text('Deposit Required')]),
              ]),
              p(classes: 'text-sm mb-6 ${isDark ? "text-zinc-300" : "text-zinc-600"}', [
                Component.text(
                  'To ensure platform quality and security, the full job amount is held in escrow. You can top up your Tyxbit balance (1 Tyxbit = 1 PHP) securely powered by Xendit.',
                ),
              ]),
              div(
                classes:
                    'p-4 rounded-xl mb-6 flex items-center justify-between border ${isDark ? "border-zinc-800 bg-zinc-800/50" : "border-zinc-200 bg-zinc-50"}',
                [
                  p(classes: 'font-semibold ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                    Component.text('Amount due'),
                  ]),
                  p(classes: 'text-2xl font-bold logo-gradient-text', [
                    Component.text('${s.depositAmount.toStringAsFixed(2)} Tyxbits'),
                  ]),
                ],
              ),
              div(classes: 'flex gap-3', [
                button(
                  classes:
                      'flex-1 py-3 rounded-xl font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800 text-zinc-300" : "border-zinc-200 hover:bg-zinc-50 text-zinc-700"}',
                  events: {
                    'click': (_) => s.setState(() {
                      s.showDepositModal = false;
                      s.isDepositing = false;
                      s.isPostingJob = false;
                    }),
                  },
                  [Component.text('Cancel')],
                ),
                button(
                  classes:
                      'flex-1 py-3 rounded-xl font-semibold text-white bg-blue-600 hover:bg-blue-500 transition-colors flex items-center justify-center gap-2',
                  events: s.isDepositing ? {} : {'click': (_) => s.handlePostJob()},
                  [
                    if (s.isDepositing) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
                    Component.text('Pay with Xendit'),
                  ],
                ),
              ]),
            ],
          ),
        ]),

      if (s.showEmployerProfileModal)
        div(classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm', [
          div(
            classes:
                'w-full max-w-md p-6 rounded-3xl ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"} shadow-2xl animate-fade-up flex flex-col relative',
            [
              button(
                classes: 'absolute top-4 right-4 p-2 rounded-full hover:bg-zinc-500/20 transition-colors',
                events: {'click': (_) => s.setState(() => s.showEmployerProfileModal = false)},
                [lIcon('x', cls: 'w-5 h-5 ${isDark ? "text-zinc-400" : "text-zinc-600"}')],
              ),

              if (s.isLoadingEmployerProfile)
                div(classes: 'py-12 flex justify-center', [
                  lIcon('loader-2', cls: 'w-8 h-8 animate-spin text-indigo-500'),
                ])
              else if (s.employerProfileData != null)
                Builder(
                  builder: (context) {
                    final emp = s.employerProfileData!;
                    final rating = (emp['rating'] as num?)?.toDouble() ?? 5.0;
                    final about = emp['about'] as String? ?? 'No description provided.';
                    final phone = emp['mobileNumber'] as String? ?? 'Not provided';
                    return div(classes: 'flex flex-col', [
                      div(classes: 'flex items-center gap-4 mb-6 mt-2', [
                        div(
                          classes:
                              'w-16 h-16 rounded-full flex items-center justify-center bg-indigo-600 flex-shrink-0 overflow-hidden',
                          [
                            if ((emp['profile_photo'] as String?)?.isNotEmpty ?? false)
                              img(src: emp['profile_photo'] as String, classes: 'w-full h-full object-cover')
                            else
                              span(classes: 'text-2xl font-bold text-white', [
                                Component.text(
                                  ((emp['displayName'] as String?) ?? '?').isNotEmpty
                                      ? (emp['displayName'] as String)[0].toUpperCase()
                                      : '?',
                                ),
                              ]),
                          ],
                        ),
                        div([
                          h3(classes: 'text-xl font-bold', [
                            Component.text(emp['displayName'] as String? ?? 'Unknown'),
                          ]),
                          div(
                            classes:
                                'flex items-center gap-1 mt-1 text-sm font-medium ${isDark ? "text-zinc-400" : "text-zinc-600"}',
                            [
                              lIcon('star', cls: 'w-4 h-4 text-yellow-500 fill-current'),
                              Component.text(rating.toStringAsFixed(1)),
                            ],
                          ),
                        ]),
                      ]),

                      div(classes: 'space-y-4 mb-2', [
                        div([
                          p(classes: 'text-xs font-semibold uppercase tracking-wider text-indigo-500 mb-1', [
                            Component.text('About'),
                          ]),
                          p(classes: 'text-sm ${isDark ? "text-zinc-300" : "text-zinc-700"}', [Component.text(about)]),
                        ]),
                        div([
                          p(classes: 'text-xs font-semibold uppercase tracking-wider text-indigo-500 mb-1', [
                            Component.text('Contact'),
                          ]),
                          p(classes: 'text-sm ${isDark ? "text-zinc-300" : "text-zinc-700"} flex items-center gap-2', [
                            lIcon('phone', cls: 'w-4 h-4 opacity-70'),
                            Component.text(phone),
                          ]),
                        ]),
                        if (emp['skills'] != null && (emp['skills'] as List).isNotEmpty)
                          div([
                            p(classes: 'text-xs font-semibold uppercase tracking-wider text-indigo-500 mb-2', [
                              Component.text('Preferred Skills'),
                            ]),
                            div(classes: 'flex flex-wrap gap-2', [
                              for (final skill in emp['skills'] as List)
                                span(
                                  classes:
                                      'px-2 py-1 rounded-md text-xs font-medium border ${isDark ? "border-zinc-700 bg-zinc-800 text-zinc-300" : "border-zinc-200 bg-zinc-100 text-zinc-700"}',
                                  [
                                    Component.text(skill.toString()),
                                  ],
                                ),
                            ]),
                          ]),
                      ]),
                    ]);
                  },
                )
              else
                div(classes: 'py-12 flex justify-center text-red-500 text-sm font-semibold', [
                  Component.text('Failed to load profile.'),
                ]),
            ],
          ),
        ]),
    ]);
  }

  Component _qaSection(TranyxAppState s, bool isDark) {
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    final isOwner = s.selectedJobData?['creatorId'] == s.userProfile?.uid;
    return div(classes: 'p-5 rounded-2xl border space-y-4 $cardCls', [
      p(classes: 'font-semibold', [Component.text('Public Q&A')]),
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
            attributes: {'placeholder': 'Ask a question...', 'value': s.newQuestionText},
            events: {
              'input': (e) {
                // ignore: avoid_dynamic_calls
                final v = (e as dynamic).target?.value as String? ?? '';
                s.setState(() => s.newQuestionText = v);
              },
            },
          ),
          button(
            classes: 'px-4 py-2.5 rounded-xl logo-gradient text-white',
            events: {'click': (_) => s.handleAskQuestion()},
            [lIcon('send', cls: 'w-4 h-4')],
          ),
        ]),
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
                attributes: {'placeholder': 'Type your answer...', 'value': s.answerDrafts[qid] ?? ''},
                events: {
                  'input': (e) {
                    // ignore: avoid_dynamic_calls
                    final v = (e as dynamic).target?.value as String? ?? '';
                    s.setState(() => s.answerDrafts[qid] = v);
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

      button(
        classes:
            'w-full py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex justify-center items-center',
        events: {
          'click': (_) async {
            if (step < 3) {
              s.setState(() => s.createStep = step + 1);
            } else {
              if (s.isPostingJob) return;
              await s.handlePostJob();
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
            events: {
              'input': (e) {
                // ignore: avoid_dynamic_calls
                s.setState(() => s.newJobDesc = (e as dynamic).target?.value as String? ?? '');
              },
            },
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
                  attributes: {'accept': 'image/*', 'multiple': 'true'},
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
    return div(classes: 'space-y-4', [
      segmentedControl(
        options: const [('On-site', 'onsite'), ('Remote', 'remote')],
        selected: s.locType.name,
        isDark: isDark,
        onChange: (v) => s.setState(() => s.locType = v == 'onsite' ? LocType.onsite : LocType.remote),
      ),
      if (s.locType == LocType.onsite) ...[
        // Map picker for on-site jobs
        MapPickerComponent(state: s, key: ValueKey('map-${s.hasTracker}-${s.selectedCategory?.id}')),

        inputField(
          label: 'Landmark / Additional Notes',
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
          events: {
            'input': (e) {
              // ignore: avoid_dynamic_calls
              s.setState(() => s.coverNote = (e as dynamic).target?.value as String? ?? '');
            },
          },
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
    final hasTracker = job?['hasTracker'] as bool? ?? false;

    return div(classes: 'space-y-6 animate-fade-up max-w-3xl', [
      subViewHeader(
        title: 'Review & Manage Job',
        isDark: isDark,
        onBack: () => s.setState(() => s.jobsView = JobsView.details),
      ),

      if (status == 'Open') ...[
        h2(classes: 'text-xl font-bold mb-4', [Component.text('Applicants')]),
        if (s.isLoadingApplicants)
          div(classes: 'flex justify-center p-8', [lIcon('loader-2', cls: 'w-8 h-8 animate-spin text-indigo-500')])
        else if (s.jobApplicants.isEmpty)
          div(
            classes:
                'p-8 text-center text-zinc-500 rounded-2xl border border-dashed ${isDark ? "border-zinc-800" : "border-zinc-200"}',
            [Component.text('No applicants yet.')],
          )
        else
          div(classes: 'space-y-4', [
            for (final app in s.jobApplicants)
              div(
                classes:
                    'p-5 rounded-2xl border ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200 shadow-sm"} flex flex-col md:flex-row md:items-center justify-between gap-4',
                [
                  div(classes: 'flex items-center gap-3', [
                    div(classes: 'w-12 h-12 rounded-full overflow-hidden bg-zinc-800', [
                      if ((app['applicantPhotoUrl'] as String?)?.isNotEmpty ?? false)
                        img(src: app['applicantPhotoUrl'] as String, classes: 'w-full h-full object-cover')
                      else
                        div(
                          classes: 'w-full h-full flex items-center justify-center logo-gradient text-white font-bold',
                          [Component.text((app['applicantName'] as String?)?.substring(0, 1).toUpperCase() ?? '?')],
                        ),
                    ]),
                    div([
                      p(classes: 'font-bold', [Component.text(app['applicantName'] as String? ?? 'Anonymous')]),
                      if (app['isCounterOffer'] == true)
                        p(classes: 'text-sm font-semibold text-orange-400', [
                          Component.text('Counter Offer: ₱ ${app['proposalRate']}'),
                        ])
                      else
                        p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                          Component.text('Standard Rate'),
                        ]),
                    ]),
                  ]),
                  div(classes: 'flex-1 text-sm ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                    Component.text(app['coverNote'] as String? ?? 'No cover note provided.'),
                  ]),
                  button(
                    classes:
                        'px-6 py-2 rounded-xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity whitespace-nowrap flex items-center gap-2',
                    events: {'click': (_) => s.acceptApplicant(job!['id'], app)},
                    [
                      if (s.isUpdatingJobStatus) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
                      Component.text('Accept'),
                    ],
                  ),
                ],
              ),
          ]),
      ] else if (status == 'In Progress') ...[
        div(classes: 'p-8 rounded-3xl border border-blue-500/30 bg-blue-500/10 text-center space-y-4', [
          lIcon('briefcase', cls: 'w-12 h-12 text-blue-400 mx-auto'),
          h2(classes: 'text-2xl font-bold text-blue-400', [Component.text('Job is In Progress')]),
          p(classes: isDark ? "text-zinc-300" : "text-zinc-700", [
            Component.text('An applicant has been accepted and is working on this gig.'),
          ]),
          p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
            Component.text('Ask the employer for the 6-digit payment code to release your Tyxbit payout.'),
          ]),
          button(
            classes:
                'px-8 py-3 rounded-2xl font-bold text-white bg-green-500 hover:bg-green-400 transition-colors inline-flex items-center gap-2',
            events: {
              'click': (_) => s.setState(() {
                s.showCompletionScanner = true;
                s.completionScanInput = '';
              }),
            },
            [
              if (s.isUpdatingJobStatus) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
              lIcon('scan-line', cls: 'w-5 h-5'),
              Component.text(' Release Payment via Code'),
            ],
          ),
        ]),
        if (hasTracker && (job?['pickupLat'] != null) && (job?['destinationLat'] != null))
          NavigationMapComponent(state: s, isNyxian: false),
      ] else if (status == 'Completed') ...[
        div(classes: 'p-8 rounded-3xl border border-green-500/30 bg-green-500/10 text-center space-y-4', [
          lIcon('check-circle', cls: 'w-12 h-12 text-green-400 mx-auto'),
          h2(classes: 'text-2xl font-bold text-green-400', [Component.text('Job Completed')]),
          p(classes: isDark ? "text-zinc-300" : "text-zinc-700", [
            Component.text('This job has been successfully finished.'),
          ]),
        ]),
      ],
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
