import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/jobs/models/job.dart';
import 'package:tranyx_mobile/features/jobs/providers/job_repository.dart';
import 'package:tranyx_mobile/features/jobs/providers/jobs_provider.dart';
import 'package:tranyx_mobile/features/jobs/presentation/widgets/job_cards.dart';
import 'package:tranyx_mobile/core/utils/geo_helper.dart';
import 'package:shared/shared.dart';

final jobListTabProvider = StateProvider<int>(
  (ref) => 0,
); // 0: Active/Browse, 1: Completed/Applied, 2: Completed (nyxian)

class JobListView extends ConsumerWidget {
  final bool isTablet;
  final GlobalKey? headerKey;

  const JobListView({super.key, required this.isTablet, this.headerKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);
    final currentViewMode = ref.watch(currentViewModeProvider);
    final user = ref.watch(userProvider);

    final isEmployer = currentViewMode == AccountType.employer;
    final tabLabels = isEmployer
        ? ['Active', 'Completed']
        : ['Browse Gigs', 'Applied', 'Completed'];

    final currentTab = ref.watch(jobListTabProvider);
    final activeTab = currentTab >= tabLabels.length ? 0 : currentTab;

    // ── Filter state (Nyxian / Browse Gigs only) ──────────────────────────
    final activeFilter = ref.watch(jobActiveFilterProvider);
    final geofenceRadius = ref.watch(jobGeofenceRadiusProvider);
    final includeRemote = ref.watch(jobIncludeRemoteJobsProvider);
    final isBrowseTab = !isEmployer && activeTab == 0;

    // ── Data providers ────────────────────────────────────────────────────
    final AsyncValue<List<Job>> jobsAsync;
    if (isEmployer) {
      jobsAsync = ref.watch(myJobsProvider).whenData((list) {
        if (activeTab == 0) {
          return list
              .where(
                (j) =>
                    j.creatorId == user?.uid &&
                    j.status != 'Completed' &&
                    j.status != 'Cancelled',
              )
              .toList();
        } else {
          return list
              .where(
                (j) =>
                    j.creatorId == user?.uid &&
                    (j.status == 'Completed' || j.status == 'Cancelled'),
              )
              .toList();
        }
      });
    } else {
      if (activeTab == 0) {
        final userProfile = ref.watch(userProfileProvider).value;
        const userLat = 14.5995;
        const userLng = 120.9842;

        jobsAsync = ref.watch(availableJobsProvider).whenData((list) {
          final userProfile = ref.watch(userProfileProvider).value;
          const userLat = 14.5995;
          const userLng = 120.9842;
          final userSkills = userProfile?.skills ?? [];

          final rawList = list.map((j) => j.toMap()).toList();
          final filteredMaps = GigFilterEngine.filterGigList(
            gigs: rawList,
            categoryFilter: activeFilter,
            includeRemote: includeRemote,
            maxRadiusKm: geofenceRadius,
            userLat: userLat,
            userLng: userLng,
            userSkills: userSkills,
          );
          final filteredIds =
              filteredMaps.map((m) => m['id'] as String?).toSet();
          return list.where((j) => filteredIds.contains(j.id)).toList();
        });
      } else if (activeTab == 1) {
        jobsAsync = ref.watch(appliedJobsProvider).whenData((list) {
          return list
              .where((j) => j.status != 'Completed' && j.status != 'Cancelled')
              .toList();
        });
      } else {
        jobsAsync = ref.watch(myJobsProvider).whenData((list) {
          return list
              .where(
                (j) =>
                    j.acceptedApplicantId == user?.uid &&
                    j.status == 'Completed',
              )
              .toList();
        });
      }
    }

    // ── Layout:
    // • Sticky header (tabs + filters) — never scrolls
    // • Expanded list — scrolls underneath the sticky header
    // Both parent contexts (SizedBox on mobile, Expanded→Row on tablet) provide
    // bounded height, so Expanded is valid here.
    // GestureDetector(
    //               onTap:
    //               child: Container(
    //                 padding: const EdgeInsets.all(8),
    //                 decoration: BoxDecoration(
    //                   color: AppColors.indigo,
    //                   borderRadius: BorderRadius.circular(12),
    //                 ),
    //                 child: const Icon(Icons.add, color: Colors.white, size: 20),
    //               ),
    //             ),
    return Scaffold(
      floatingActionButton: (!isTablet && isEmployer)
          ? FloatingActionButton(
              backgroundColor: AppColors.indigo,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadiusGeometry.circular(12),
              ),
              onPressed: () =>
                  ref.read(jobsViewProvider.notifier).state = 'create',
              child: const Icon(Icons.add, color: Colors.white, size: 20),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Sticky header ──────────────────────────────────────────────────
          _buildStickyHeader(
            context,
            ref,
            isDarkMode,
            isEmployer,
            activeTab,
            currentViewMode,
            isBrowseTab,
            jobsAsync,
          ),

          // ── Tablet employer "Create" button ───────────────────────────────
          if (isTablet && isEmployer) ...[
            const SizedBox(height: 12),
            UIHelpers.buildPrimaryButton(
              '+ Create New Listing',
              () => ref.read(jobsViewProvider.notifier).state = 'create',
              isDarkMode,
              isOutlined: true,
            ),
            const SizedBox(height: 4),
          ],

          // ── Scrollable job list ────────────────────────────────────────────
          Expanded(
            child: jobsAsync.when(
              data: (jobs) {
                if (jobs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 52,
                            color: Colors.grey.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isBrowseTab
                                ? 'No available gigs match your current filters'
                                : 'No jobs found',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          if (isBrowseTab) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Try expanding your distance radius, enabling remote gigs, or viewing all job categories.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.purple,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                              ),
                              onPressed: () {
                                ref
                                    .read(jobActiveFilterProvider.notifier)
                                    .state = 'All';
                                ref
                                    .read(jobGeofenceRadiusProvider.notifier)
                                    .state = 9999.0;
                                ref
                                    .read(
                                      jobIncludeRemoteJobsProvider.notifier,
                                    )
                                    .state = true;
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text(
                                'Reset Filters',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(top: 4, bottom: 32),
                  physics: const BouncingScrollPhysics(),
                  itemCount: jobs.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 16),
                  itemBuilder: (context, index) => _buildJobCard(
                    ref,
                    jobs[index],
                    isEmployer,
                    activeTab,
                    isDarkMode,
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) {
                debugPrint(err.toString());
                return Center(child: Text('Error: $err'));
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Job card dispatcher ───────────────────────────────────────────────────
  Widget _buildJobCard(
    WidgetRef ref,
    Job job,
    bool isEmployer,
    int activeTab,
    bool isDarkMode,
  ) {
    void navigate() {
      ref.read(selectedJobProvider.notifier).state = job;
      ref.read(jobsViewProvider.notifier).state = 'details';
    }

    final isCompletedTab =
        (isEmployer && activeTab == 1) || (!isEmployer && activeTab == 2);

    if (isCompletedTab && job.status == 'Completed') {
      return isEmployer
          ? JobCompletedEmployerCard(
              job: job,
              isDarkMode: isDarkMode,
              onClick: navigate,
            )
          : JobCompletedNyxianCard(
              job: job,
              isDarkMode: isDarkMode,
              onClick: navigate,
            );
    }

    return job.creatorType == AccountType.employer
        ? JobEmployerCard(job: job, isDarkMode: isDarkMode, onClick: navigate)
        : JobNyxianCard(job: job, isDarkMode: isDarkMode, onClick: navigate);
  }

  // ── Sticky header (tabs row + optional filter bar) ────────────────────────
  Widget _buildStickyHeader(
    BuildContext context,
    WidgetRef ref,
    bool isDarkMode,
    bool isEmployer,
    int activeTab,
    AccountType currentViewMode,
    bool isBrowseTab,
    AsyncValue<List<Job>> jobsAsync,
  ) {
    return Container(
      key: headerKey,
      color: isDarkMode ? AppColors.darkBg : AppColors.lightBg,
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tabs row + mobile employer "+ create" button
          Row(
            children: [
              _buildAnimatedTabs(context, ref, isDarkMode, currentViewMode),
            ],
          ),
          // Filters — only for Nyxian on Browse Gigs tab
          if (isBrowseTab) ...[
            const SizedBox(height: 10),
            _buildFilterBar(ref, isDarkMode, jobsAsync.value?.length ?? 0),
          ],
        ],
      ),
    );
  }

  // ── Animated pill tab bar ─────────────────────────────────────────────────
  Widget _buildAnimatedTabs(
    BuildContext context,
    WidgetRef ref,
    bool isDarkMode,
    AccountType currentViewMode,
  ) {
    final isEmployer = currentViewMode == AccountType.employer;
    final tabLabels = isEmployer
        ? ['Active', 'Completed']
        : ['Browse Gigs', 'Applied', 'Completed'];

    final currentTab = ref.watch(jobListTabProvider);
    final activeTab = currentTab >= tabLabels.length ? 0 : currentTab;

    final double alignX = tabLabels.length > 1
        ? -1.0 + (activeTab * (2.0 / (tabLabels.length - 1)))
        : 0.0;

    return Container(
      height: 50,
      width: MediaQuery.sizeOf(context).width - 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkCard : Colors.grey[200],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? AppColors.darkBorder : Colors.transparent,
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: Curves.elasticOut,
            alignment: Alignment(alignX, 0.0),
            child: FractionallySizedBox(
              widthFactor: 1.0 / tabLabels.length,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.indigo,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.indigo.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: List.generate(tabLabels.length, (index) {
              return _buildTabItem(
                ref,
                tabLabels[index],
                index,
                activeTab,
                isDarkMode,
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(
    WidgetRef ref,
    String label,
    int index,
    int activeTab,
    bool isDarkMode,
  ) {
    final active = activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(jobListTabProvider.notifier).state = index,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: active
                  ? Colors.white
                  : (isDarkMode ? AppColors.darkTextMuted : Colors.grey[600]),
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  // ── Filter bar (Nyxian browse gigs only) ──────────────────────────────────
  Widget _buildFilterBar(WidgetRef ref, bool isDarkMode, int resultCount) {
    final activeFilter = ref.watch(jobActiveFilterProvider);
    final geofenceRadius = ref.watch(jobGeofenceRadiusProvider);
    final includeRemote = ref.watch(jobIncludeRemoteJobsProvider);

    final summaryInfo = GigFilterEngine.buildSummaryInfo(
      categoryFilter: activeFilter,
      includeRemote: includeRemote,
      maxRadiusKm: geofenceRadius,
      resultCount: resultCount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip(ref, 'All', activeFilter == 'All', isDarkMode),
              const SizedBox(width: 8),
              _buildFilterChip(
                ref,
                'Recommended',
                activeFilter == 'Recommended',
                isDarkMode,
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                ref,
                'High Paying',
                activeFilter == 'High Paying',
                isDarkMode,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Distance dropdown + Remote toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: isDarkMode ? Colors.purple[300] : AppColors.purple,
                ),
                const SizedBox(width: 4),
                DropdownButtonHideUnderline(
                  child: DropdownButton<double>(
                    value: geofenceRadius,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? AppColors.darkText
                          : AppColors.lightText,
                    ),
                    dropdownColor: isDarkMode
                        ? AppColors.darkCard
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(jobGeofenceRadiusProvider.notifier).state =
                            val;
                      }
                    },
                    items: const [
                      DropdownMenuItem(value: 5.0, child: Text('Within 5 km')),
                      DropdownMenuItem(
                        value: 15.0,
                        child: Text('Within 15 km'),
                      ),
                      DropdownMenuItem(
                        value: 30.0,
                        child: Text('Within 30 km'),
                      ),
                      DropdownMenuItem(
                        value: 50.0,
                        child: Text('Within 50 km'),
                      ),
                      DropdownMenuItem(
                        value: 100.0,
                        child: Text('Within 100 km'),
                      ),
                      DropdownMenuItem(
                        value: 9999.0,
                        child: Text('Any Distance'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: () {
                ref.read(jobIncludeRemoteJobsProvider.notifier).state =
                    !includeRemote;
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: includeRemote
                      ? AppColors.indigo
                      : (isDarkMode ? AppColors.darkCard : Colors.grey[200]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: includeRemote
                        ? Colors.transparent
                        : (isDarkMode
                              ? AppColors.darkBorder
                              : Colors.transparent),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.wifi,
                      size: 14,
                      color: includeRemote
                          ? Colors.white
                          : (isDarkMode ? Colors.grey : Colors.black87),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Remote Gigs',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: includeRemote
                            ? Colors.white
                            : (isDarkMode ? Colors.grey : Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Active Filter Summary Strip (Scenarios 1-8)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDarkMode
                ? AppColors.purple.withValues(alpha: 0.1)
                : AppColors.purple.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDarkMode
                  ? AppColors.purple.withValues(alpha: 0.25)
                  : AppColors.purple.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.filter_list_rounded,
                size: 15,
                color: isDarkMode ? Colors.purpleAccent : AppColors.purple,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 11,
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                    ),
                    children: [
                      TextSpan(
                        text: '${summaryInfo.categorySummary} ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(
                        text:
                            '• ${summaryInfo.distanceSummary} • ${summaryInfo.remoteSummary} ',
                        style: TextStyle(
                          color: isDarkMode
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                      TextSpan(
                        text: '(${summaryInfo.count} gigs found)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDarkMode
                              ? Colors.purpleAccent
                              : AppColors.purple,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!summaryInfo.isDefaultState)
                GestureDetector(
                  onTap: () {
                    ref.read(jobActiveFilterProvider.notifier).state = 'All';
                    ref.read(jobGeofenceRadiusProvider.notifier).state = 9999.0;
                    ref.read(jobIncludeRemoteJobsProvider.notifier).state = true;
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      'Clear All',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? Colors.purpleAccent
                            : AppColors.purple,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(
    WidgetRef ref,
    String label,
    bool active,
    bool isDarkMode,
  ) {
    return GestureDetector(
      onTap: () => ref.read(jobActiveFilterProvider.notifier).state = label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.indigo
              : (isDarkMode ? AppColors.darkCard : Colors.grey[200]),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? Colors.transparent
                : (isDarkMode ? AppColors.darkBorder : Colors.transparent),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: active
                ? Colors.white
                : (isDarkMode ? Colors.grey : Colors.black87),
          ),
        ),
      ),
    );
  }
}
