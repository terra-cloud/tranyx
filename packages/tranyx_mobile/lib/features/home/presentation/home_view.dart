import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/core/utils/enums.dart';
import 'package:tranyx_mobile/features/jobs/providers/jobs_provider.dart';
import 'package:tranyx_mobile/features/jobs/providers/job_repository.dart';
import 'package:tranyx_mobile/features/profile/providers/profile_provider.dart';
import 'package:tranyx_mobile/features/jobs/presentation/widgets/job_list_view.dart';
import 'package:tranyx_mobile/features/navigation/providers/navigation_provider.dart';
import 'package:tranyx_mobile/features/jobs/presentation/categories_bottom_sheet.dart';

class HomeView extends ConsumerWidget {
  final bool isTablet;

  const HomeView({super.key, required this.isTablet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);
    final accountType = ref.watch(accountTypeProvider);
    final hybridToggle = ref.watch(hybridToggleProvider);
    final currentViewMode = ref.watch(currentViewModeProvider);

    Widget buildToggleBtn(
      String text,
      IconData icon,
      bool isActive,
      VoidCallback onTap,
    ) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? (isDarkMode ? AppColors.darkBorder : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive
                    ? (isDarkMode ? Colors.white : AppColors.lightText)
                    : (isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted),
              ),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? (isDarkMode ? Colors.white : AppColors.lightText)
                      : (isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildCategoryCard(JobCategory category) {
      return GestureDetector(
        onTap: () {
          ref.read(jobSearchFilterProvider.notifier).state = category;
          ref.read(jobsViewProvider.notifier).state = 'list';
          ref.read(activeTabProvider.notifier).state = 'jobs';
        },
        child: Container(
          width: 100,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.indigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(category.iconData, color: AppColors.indigo, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                category.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    Widget searchBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          currentViewMode == AccountType.employer
              ? "What do you need done?"
              : "Find your next gig.",
          style: TextStyle(
            fontSize: isTablet ? 35 : 25,
            // height: 1,
            fontWeight: FontWeight.w700,
            color: isDarkMode ? AppColors.darkText : AppColors.lightText,
          ),
        ),
        // const SizedBox(height: 24),
        UIHelpers.buildTextField(
          LucideIcons.search,
          currentViewMode == AccountType.employer
              ? "Search plumbers, car rentals..."
              : "Search odd jobs in your area...",
          isDarkMode,
          onSubmitted: (val) {
            if (val.isNotEmpty) {
              ref.read(searchQueryProvider.notifier).state = val;
              ref.read(activeTabProvider.notifier).state = 'jobs';
              ref.read(jobsViewProvider.notifier).state = 'list';
            }
          },
        ),
      ],
    );

    Widget ongoingWidget = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDarkMode
            ? (currentViewMode == AccountType.employer
                  ? AppColors.blue.withValues(alpha: 0.1)
                  : AppColors.green.withValues(alpha: 0.1))
            : (currentViewMode == AccountType.employer
                  ? AppColors.blue.withValues(alpha: 0.05)
                  : AppColors.green.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: currentViewMode == AccountType.employer
              ? AppColors.blue.withValues(alpha: 0.3)
              : AppColors.green.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: currentViewMode == AccountType.employer
                          ? AppColors.blue
                          : AppColors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    currentViewMode == AccountType.employer
                        ? "ONGOING JOB"
                        : "CURRENT GIG",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: currentViewMode == AccountType.employer
                          ? AppColors.blue
                          : AppColors.green,
                    ),
                  ),
                ],
              ),
              Text(
                currentViewMode == AccountType.employer
                    ? "Started 1h ago"
                    : "01:24:05",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            currentViewMode == AccountType.employer
                ? "Emergency Plumber"
                : "Backyard Fence Repair",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            currentViewMode == AccountType.employer
                ? "Alex (Nyxian) is currently working on this task."
                : "1280 Silicon Ave",
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 24),
          currentViewMode == AccountType.employer
              ? Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.blue.withValues(
                            alpha: 0.2,
                          ),
                          foregroundColor: AppColors.blue,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text("View Details"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDarkMode ? AppColors.darkBorder : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.message, size: 20),
                    ),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "Complete Gig",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
        ],
      ),
    );

    return Column(
      children: [
        if (accountType == AccountType.hybrid) ...[
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? AppColors.darkCard
                  : AppColors.lightBorder.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: buildToggleBtn(
                    "Find Services",
                    Icons.bolt,
                    hybridToggle == AccountType.employer,
                    () => ref.read(hybridToggleProvider.notifier).state =
                        AccountType.employer,
                  ),
                ),
                Expanded(
                  child: buildToggleBtn(
                    "Work as Nyxian",
                    Icons.build,
                    hybridToggle == AccountType.nyxian,
                    () => ref.read(hybridToggleProvider.notifier).state =
                        AccountType.nyxian,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        _buildQuickStatsBar(context, ref, isDarkMode, currentViewMode, isTablet),
        const SizedBox(height: 24),

        if (isTablet)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: searchBlock),
              const SizedBox(width: 32),
              Expanded(flex: 1, child: ongoingWidget),
            ],
          )
        else ...[
          ongoingWidget,
          const SizedBox(height: 32),
          searchBlock,
        ],

        const SizedBox(height: 48),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Top Services",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? AppColors.darkText : AppColors.lightText,
              ),
            ),
            GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const CategoriesBottomSheet(),
                );
              },
              child: const Text(
                "See all",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.indigo,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              buildCategoryCard(JobCategory.plumber),
              const SizedBox(width: 16),
              buildCategoryCard(JobCategory.carpenter),
              const SizedBox(width: 16),
              buildCategoryCard(JobCategory.electrician),
              const SizedBox(width: 16),
              buildCategoryCard(JobCategory.houseCleaning),
              const SizedBox(width: 16),
              buildCategoryCard(JobCategory.gardener),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStatsBar(
    BuildContext context,
    WidgetRef ref,
    bool isDarkMode,
    AccountType currentViewMode,
    bool isTablet,
  ) {
    final profile = ref.watch(userProfileProvider).value;
    final myJobs = ref.watch(myJobsProvider).value ?? [];

    final tyxBal = profile?.tyxBalance ?? 0.0;
    final jobsDone = profile?.jobsDone ?? 0;
    final totalEarned = profile?.totalEarned ?? 0.0;
    final rating = profile?.rating ?? 5.0;

    final postedCount = myJobs.length;
    final activeHires = myJobs.where((j) => j.status == 'In Progress').length;

    final isNyxian = currentViewMode == AccountType.nyxian;

    final int crossAxisCount = isTablet ? 4 : 2;
    final double childAspectRatio = isTablet ? 1.5 : 1.35;

    Widget buildStatCard({
      required String title,
      required String value,
      required String subtitle,
      required IconData icon,
      required Color iconColor,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(icon, color: iconColor, size: 16),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: iconColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: crossAxisCount,
      childAspectRatio: childAspectRatio,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        if (isNyxian) ...[
          // Wallet Balance
          buildStatCard(
            title: "Balance",
            value: "₱ ${tyxBal.toStringAsFixed(2)}",
            subtitle: "Top-up Tyx",
            icon: LucideIcons.wallet,
            iconColor: AppColors.indigo,
            onTap: () {
              ref.read(activeTabProvider.notifier).state = 'profile';
              ref.read(profileViewProvider.notifier).state = 'payment';
            },
          ),
          // Completed Gigs
          buildStatCard(
            title: "Gigs Done",
            value: "$jobsDone",
            subtitle: "View Profile",
            icon: Icons.check_circle_outline,
            iconColor: AppColors.purple,
            onTap: () {
              ref.read(activeTabProvider.notifier).state = 'profile';
              ref.read(profileViewProvider.notifier).state = 'main';
            },
          ),
          // Total Earned
          buildStatCard(
            title: "Total Earned",
            value: "₱ ${totalEarned.toStringAsFixed(0)}",
            subtitle: "View Earnings",
            icon: Icons.trending_up,
            iconColor: AppColors.green,
            onTap: () {
              ref.read(activeTabProvider.notifier).state = 'profile';
              ref.read(profileViewProvider.notifier).state = 'history';
            },
          ),
          // Rating
          buildStatCard(
            title: "Trust Rating",
            value: rating.toStringAsFixed(1),
            subtitle: "View Reviews",
            icon: Icons.star_outline,
            iconColor: AppColors.amber,
            onTap: () {
              ref.read(activeTabProvider.notifier).state = 'profile';
              ref.read(profileViewProvider.notifier).state = 'trust';
            },
          ),
        ] else ...[
          // Wallet Balance
          buildStatCard(
            title: "Balance",
            value: "₱ ${tyxBal.toStringAsFixed(2)}",
            subtitle: "Top-up Tyx",
            icon: LucideIcons.wallet,
            iconColor: AppColors.indigo,
            onTap: () {
              ref.read(activeTabProvider.notifier).state = 'profile';
              ref.read(profileViewProvider.notifier).state = 'payment';
            },
          ),
          // Posted Gigs
          buildStatCard(
            title: "Gigs Posted",
            value: "$postedCount",
            subtitle: "Manage Gigs",
            icon: Icons.business_center_outlined,
            iconColor: AppColors.purple,
            onTap: () {
              ref.read(activeTabProvider.notifier).state = 'jobs';
              ref.read(jobListTabProvider.notifier).state = 1;
            },
          ),
          // Active Hires
          buildStatCard(
            title: "Active Gigs",
            value: "$activeHires",
            subtitle: "View Workers",
            icon: Icons.people_outline,
            iconColor: AppColors.green,
            onTap: () {
              ref.read(activeTabProvider.notifier).state = 'jobs';
              ref.read(jobListTabProvider.notifier).state = 1;
            },
          ),
          // Rating
          buildStatCard(
            title: "Trust Rating",
            value: rating.toStringAsFixed(1),
            subtitle: "View Reviews",
            icon: Icons.star_outline,
            iconColor: AppColors.amber,
            onTap: () {
              ref.read(activeTabProvider.notifier).state = 'profile';
              ref.read(profileViewProvider.notifier).state = 'trust';
            },
          ),
        ],
      ],
    );
  }
}
