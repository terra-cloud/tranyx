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

final jobListTabProvider = StateProvider<int>(
  (ref) => 0,
); // 0: Available/Discover, 1: My Postings

class JobListView extends ConsumerWidget {
  final bool isTablet;
  final GlobalKey? headerKey;

  const JobListView({super.key, required this.isTablet, this.headerKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);
    final currentViewMode = ref.watch(currentViewModeProvider);
    final currentTab = ref.watch(jobListTabProvider);

    final AsyncValue<List<Job>> jobsAsync = currentTab == 0
        ? ref.watch(availableJobsProvider)
        : ref.watch(myJobsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          key: headerKey,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentViewMode == AccountType.employer
                      ? (currentTab == 0 ? "Available Gigs" : "My Postings")
                      : (currentTab == 0 ? "Available Jobs" : "My Gigs"),
                  style: TextStyle(
                    fontSize: isTablet ? 24 : 28,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode
                        ? AppColors.darkText
                        : AppColors.lightText,
                  ),
                ),
                const SizedBox(height: 12),
                _buildAnimatedTabs(ref, isDarkMode),
              ],
            ),
            if (!isTablet)
              GestureDetector(
                onTap: () =>
                    ref.read(jobsViewProvider.notifier).state = 'create',
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.indigo,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 20),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (isTablet) ...[
          UIHelpers.buildPrimaryButton(
            "+ Create New Listing",
            () => ref.read(jobsViewProvider.notifier).state = 'create',
            isDarkMode,
            isOutlined: true,
          ),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: jobsAsync.when(
            data: (jobs) {
              if (jobs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.work_off_outlined,
                        size: 48,
                        color: Colors.grey.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "No jobs found",
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: jobs.length,
                padding: const EdgeInsets.only(bottom: 24),
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final job = jobs[index];
                  if (job.creatorType == AccountType.employer) {
                    return JobEmployerCard(
                      job: job,
                      isDarkMode: isDarkMode,
                      onClick: () {
                        ref.read(selectedJobProvider.notifier).state = job;
                        ref.read(jobsViewProvider.notifier).state = 'details';
                      },
                    );
                  } else {
                    return JobNyxianCard(
                      job: job,
                      isDarkMode: isDarkMode,
                      onClick: () {
                        ref.read(selectedJobProvider.notifier).state = job;
                        ref.read(jobsViewProvider.notifier).state = 'details';
                      },
                    );
                  }
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) {
              debugPrint(err.toString());
              return Center(child: Text("Error: $err"));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedTabs(WidgetRef ref, bool isDarkMode) {
    final currentTab = ref.watch(jobListTabProvider);

    return Container(
      height: 38,
      width: 220,
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
          // Animated Background
          AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: Curves.elasticOut,
            alignment: currentTab == 0
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
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
          // Tab Items
          Row(
            children: [
              _buildTabItem(ref, "Discover", 0, isDarkMode),
              _buildTabItem(ref, "My Postings", 1, isDarkMode),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(
    WidgetRef ref,
    String label,
    int index,
    bool isDarkMode,
  ) {
    final active = ref.watch(jobListTabProvider) == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(jobListTabProvider.notifier).state = index,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 12,
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
}
