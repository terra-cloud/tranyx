import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
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
import 'package:shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';

final homeTabProvider = StateProvider<String>((ref) => 'dashboard');

class HomeView extends ConsumerWidget {
  final bool isTablet;

  const HomeView({super.key, required this.isTablet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);
    final profile = ref.watch(userProfileProvider).value;
    final accountType = profile?.accountType ?? ref.watch(accountTypeProvider);
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
                child: Icon(
                  category.iconData,
                  color: AppColors.indigo,
                  size: 24,
                ),
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

    final user = ref.watch(userProvider);
    final myJobs = ref.watch(myJobsProvider).value ?? [];
    Job? activeJob;
    if (user != null) {
      for (final job in myJobs) {
        if (job.status == 'In Progress') {
          if (currentViewMode == AccountType.employer &&
              job.creatorId == user.uid) {
            activeJob = job;
            break;
          } else if (currentViewMode == AccountType.nyxian &&
              job.acceptedApplicantId == user.uid) {
            activeJob = job;
            break;
          }
        }
      }
    }

    Widget? ongoingWidget;
    if (activeJob != null) {
      final duration = DateTime.now().difference(activeJob.createdAt);
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);
      final timeStr = hours > 0
          ? "${hours}h ${minutes}m ago"
          : "${minutes}m ago";

      ongoingWidget = GestureDetector(
        onTap: () {
          ref.read(selectedJobProvider.notifier).state = activeJob;
          ref.read(jobsViewProvider.notifier).state = 'details';
          ref.read(activeTabProvider.notifier).state = 'jobs';
        },
        child: Container(
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
                    timeStr,
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
                activeJob.title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                currentViewMode == AccountType.employer
                    ? activeJob.description
                    : (activeJob.address ?? "No address specified"),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
                            onPressed: () {
                              ref.read(selectedJobProvider.notifier).state =
                                  activeJob;
                              ref.read(jobsViewProvider.notifier).state =
                                  'details';
                              ref.read(activeTabProvider.notifier).state =
                                  'jobs';
                            },
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
                        GestureDetector(
                          onTap: () {
                            ref.read(selectedJobProvider.notifier).state =
                                activeJob;
                            ref.read(jobsViewProvider.notifier).state =
                                'details';
                            ref.read(activeTabProvider.notifier).state = 'jobs';
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? AppColors.darkBorder
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.message, size: 20),
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          ref.read(selectedJobProvider.notifier).state =
                              activeJob;
                          ref.read(jobsViewProvider.notifier).state = 'details';
                          ref.read(activeTabProvider.notifier).state = 'jobs';
                        },
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
        ),
      );
    }

    final homeTab = ref.watch(homeTabProvider);

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

        // Home Tab Selector
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
                  "Dashboard",
                  Icons.dashboard,
                  homeTab == 'dashboard',
                  () => ref.read(homeTabProvider.notifier).state = 'dashboard',
                ),
              ),
              Expanded(
                child: buildToggleBtn(
                  "News & Promos",
                  Icons.campaign,
                  homeTab == 'news',
                  () => ref.read(homeTabProvider.notifier).state = 'news',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        if (homeTab == 'dashboard') ...[
          _buildQuickStatsBar(
            context,
            ref,
            isDarkMode,
            currentViewMode,
            isTablet,
          ),
          const SizedBox(height: 24),

          if (ongoingWidget != null) ...[
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
          ] else ...[
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
        ] else ...[
          // News, Promos & Ad Feed
          PromoCodeRedeemCard(isDarkMode: isDarkMode),
          const SizedBox(height: 24),
          ref
              .watch(activeNewsPostsProvider)
              .when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (err, stack) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      "Error loading feed: $err",
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
                data: (posts) {
                  if (posts.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.feed_outlined,
                              size: 48,
                              color: isDarkMode
                                  ? Colors.white30
                                  : Colors.black26,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "No news or promotions available",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDarkMode
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: posts.map((post) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: isDarkMode ? AppColors.darkCard : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDarkMode
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDarkMode ? 0.2 : 0.05,
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (post.imageUrl.isNotEmpty)
                                LayoutBuilder(
                                  builder: (context, imgConstraints) {
                                    final width = imgConstraints.maxWidth;
                                    final height = width * (9.0 / 16.0);

                                    return Stack(
                                      children: [
                                        GestureDetector(
                                          onTap: () => _handleNewsPostAction(
                                            context,
                                            ref,
                                            post,
                                          ),
                                          child: Image.network(
                                            post.imageUrl,
                                            width: width,
                                            height: height,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Container(
                                                      width: width,
                                                      height: height,
                                                      color: isDarkMode
                                                          ? Colors.white10
                                                          : Colors.black12,
                                                      child: const Icon(
                                                        Icons.broken_image,
                                                        size: 40,
                                                      ),
                                                    ),
                                          ),
                                        ),
                                        if (post.buttonText != null &&
                                            post.buttonText!.isNotEmpty &&
                                            post.buttonX != null &&
                                            post.buttonY != null &&
                                            post.buttonWidth != null &&
                                            post.buttonHeight != null)
                                          Positioned(
                                            left:
                                                (post.buttonX! / 100.0) * width,
                                            top:
                                                (post.buttonY! / 100.0) *
                                                height,
                                            width:
                                                (post.buttonWidth! / 100.0) *
                                                width,
                                            height:
                                                (post.buttonHeight! / 100.0) *
                                                height,
                                            child: ElevatedButton(
                                              onPressed: () =>
                                                  _handleNewsPostAction(
                                                    context,
                                                    ref,
                                                    post,
                                                  ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.indigo,
                                                foregroundColor: Colors.white,
                                                elevation: 4,
                                                padding: EdgeInsets.zero,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                              child: Text(
                                                post.buttonText!,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getCategoryColor(
                                              post.category,
                                            ).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            post.category.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: _getCategoryColor(
                                                post.category,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          _formatNewsDate(post.createdAt),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDarkMode
                                                ? AppColors.darkTextMuted
                                                : AppColors.lightTextMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      post.title,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isDarkMode
                                            ? AppColors.darkText
                                            : AppColors.lightText,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      post.content,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDarkMode
                                            ? AppColors.darkTextMuted
                                            : AppColors.lightTextMuted,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
        ],
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
    final rating = profile?.rating;
    final ratingDisplay = rating != null ? rating.toStringAsFixed(1) : "Unrated";

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
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                  Icon(icon, color: iconColor, size: 18),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode
                          ? AppColors.darkText
                          : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: iconColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return GridView.count(
      padding: const EdgeInsets.all(0),
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
            title: "Wallet",
            value: "₱ ${tyxBal.toStringAsFixed(2)}",
            subtitle: "Manage Wallet",
            icon: LucideIcons.wallet,
            iconColor: AppColors.indigo,
            onTap: () => _showWalletActionMenu(context, ref, tyxBal),
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
            value: ratingDisplay,
            subtitle: "View Reviews",
            icon: Icons.star_outline,
            iconColor: AppColors.amber,
            onTap: () {
              ref.read(activeTabProvider.notifier).state = 'profile';
              ref.read(profileViewProvider.notifier).state = 'reviews';
            },
          ),
        ] else ...[
          // Wallet Balance
          buildStatCard(
            title: "Balance",
            value: "₱ ${tyxBal.toStringAsFixed(2)}",
            subtitle: "Manage Wallet",
            icon: LucideIcons.wallet,
            iconColor: AppColors.indigo,
            onTap: () => _showWalletActionMenu(context, ref, tyxBal),
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
            value: ratingDisplay,
            subtitle: "View Reviews",
            icon: Icons.star_outline,
            iconColor: AppColors.amber,
            onTap: () {
              ref.read(activeTabProvider.notifier).state = 'profile';
              ref.read(profileViewProvider.notifier).state = 'reviews';
            },
          ),
        ],
      ],
    );
  }

  void _showWalletActionMenu(
    BuildContext context,
    WidgetRef ref,
    double balance,
  ) {
    final isDarkMode = ref.read(themeModeProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.grey[700] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.indigo.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        LucideIcons.wallet,
                        color: AppColors.indigo,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Wallet Options',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode
                                  ? AppColors.darkText
                                  : AppColors.lightText,
                            ),
                          ),
                          Text(
                            'Available Balance: ₱ ${balance.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.indigo,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // 1. Deposit / Cash In
                _WalletActionTile(
                  icon: Icons.add_circle_outline,
                  iconColor: Colors.green,
                  iconBgColor: Colors.green.withValues(alpha: 0.12),
                  title: 'Deposit / Cash In',
                  subtitle: 'Top-up Tyx via GCash, Crypto, or Bank',
                  isDarkMode: isDarkMode,
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(activeTabProvider.notifier).state = 'profile';
                    ref.read(profileViewProvider.notifier).state = 'payment';
                  },
                ),
                const SizedBox(height: 10),
                // 2. Withdraw / Cash Out
                _WalletActionTile(
                  icon: Icons.arrow_circle_up_outlined,
                  iconColor: AppColors.purple,
                  iconBgColor: AppColors.purple.withValues(alpha: 0.12),
                  title: 'Withdraw / Cash Out',
                  subtitle: 'Transfer funds to connected wallet or bank',
                  isDarkMode: isDarkMode,
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(activeTabProvider.notifier).state = 'profile';
                    ref.read(profileViewProvider.notifier).state = 'withdraw';
                  },
                ),
                const SizedBox(height: 10),
                // 3. Show All Transaction History
                _WalletActionTile(
                  icon: Icons.receipt_long_outlined,
                  iconColor: AppColors.indigo,
                  iconBgColor: AppColors.indigo.withValues(alpha: 0.12),
                  title: 'Show All Transaction History',
                  subtitle: 'View ledger, escrow logs, and payment activity',
                  isDarkMode: isDarkMode,
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(activeTabProvider.notifier).state = 'profile';
                    ref.read(profileViewProvider.notifier).state = 'history';
                  },
                ),
                const SizedBox(height: 12),
                // Cancel button
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WalletActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final bool isDarkMode;
  final VoidCallback onTap;

  const _WalletActionTile({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    required this.isDarkMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDarkMode ? AppColors.darkBg : Colors.grey[50],
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode
                          ? AppColors.darkText
                          : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDarkMode
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class PromoCodeRedeemCard extends ConsumerStatefulWidget {
  final bool isDarkMode;
  const PromoCodeRedeemCard({super.key, required this.isDarkMode});

  @override
  ConsumerState<PromoCodeRedeemCard> createState() =>
      _PromoCodeRedeemCardState();
}

class _PromoCodeRedeemCardState extends ConsumerState<PromoCodeRedeemCard> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _feedback;
  bool _isSuccess = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _redeem() async {
    final cleanCode = _controller.text.trim().toUpperCase();
    if (cleanCode.isEmpty) return;

    setState(() {
      _isLoading = true;
      _feedback = null;
      _isSuccess = false;
    });

    try {
      final repo = ref.read(transitRepositoryProvider);
      final promo = await repo.getPromo(cleanCode);
      if (promo == null) {
        setState(() {
          _feedback = 'Promo code not found.';
          _isSuccess = false;
        });
        return;
      }

      final user = ref.read(userProfileProvider).value;
      if (user == null) throw Exception('User profile not loaded');

      final now = DateTime.now();
      if (!promo.isActive) {
        setState(() {
          _feedback = 'This promo code is inactive.';
          _isSuccess = false;
        });
        return;
      }

      if (promo.expirationDate != null && promo.expirationDate!.isBefore(now)) {
        setState(() {
          _feedback = 'This promo code has expired.';
          _isSuccess = false;
        });
        return;
      }

      if (promo.maxUsers != null && promo.usedCount >= promo.maxUsers!) {
        setState(() {
          _feedback = 'This promo code has reached its usage limit.';
          _isSuccess = false;
        });
        return;
      }

      if (user.disabledPromos.contains(cleanCode)) {
        setState(() {
          _feedback =
              'You have disabled this promotion and cannot re-enable it.';
          _isSuccess = false;
        });
        return;
      }

      if (promo.isSingleUsePerUser && promo.usedBy.contains(user.uid)) {
        setState(() {
          _feedback = 'You have already used this promo code.';
          _isSuccess = false;
        });
        return;
      }

      if (promo.eligibleUserUids != null &&
          promo.eligibleUserUids!.isNotEmpty &&
          !promo.eligibleUserUids!.contains(user.uid)) {
        setState(() {
          _feedback = 'You are not eligible for this promotion.';
          _isSuccess = false;
        });
        return;
      }

      if (promo.onlyForSubscribed && !user.isPremium) {
        setState(() {
          _feedback =
              'This promo code is only for premium subscribed accounts.';
          _isSuccess = false;
        });
        return;
      }

      if (promo.onlyForHybrid && user.accountType != AccountType.hybrid) {
        setState(() {
          _feedback = 'This promo code is only for Hybrid PRO accounts.';
          _isSuccess = false;
        });
        return;
      }

      await repo.redeemPromoToProfile(user.uid, promo);
      ref.invalidate(userProfileProvider);

      setState(() {
        _feedback = 'Promo code "${promo.code}" redeemed successfully!';
        _isSuccess = true;
        _controller.clear();
      });
    } catch (e) {
      setState(() {
        _feedback = 'Failed to redeem promo code: $e';
        _isSuccess = false;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: widget.isDarkMode ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: widget.isDarkMode
              ? AppColors.darkBorder
              : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Have a Promo Code?",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: widget.isDarkMode
                  ? AppColors.darkText
                  : AppColors.lightText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Enter it below to apply discounts directly to your account.",
            style: TextStyle(
              fontSize: 12,
              color: widget.isDarkMode
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: UIHelpers.buildTextField(
                  Icons.tag,
                  "Enter Promo Code...",
                  widget.isDarkMode,
                  controller: _controller,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isLoading ? null : _redeem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Redeem',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
          if (_feedback != null) ...[
            const SizedBox(height: 8),
            Text(
              _feedback!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _isSuccess ? Colors.green : Colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

void _handleNewsPostAction(
  BuildContext context,
  WidgetRef ref,
  NewsPost post,
) async {
  if (post.actionType == 'promo' && post.promoCode != null) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final repo = ref.read(transitRepositoryProvider);
      final promo = await repo.getPromo(post.promoCode!);
      if (context.mounted) Navigator.pop(context);

      if (promo == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Promo code not found.')),
          );
        }
        return;
      }
      final user = ref.read(userProfileProvider).value;
      if (user == null) return;

      if (user.disabledPromos.contains(promo.code)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You have disabled this promotion and cannot re-enable it.',
              ),
            ),
          );
        }
        return;
      }

      final now = DateTime.now();
      if (!promo.isActive ||
          (promo.expirationDate != null &&
              promo.expirationDate!.isBefore(now))) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This promo is inactive or expired.')),
          );
        }
        return;
      }

      await repo.redeemPromoToProfile(user.uid, promo);
      ref.invalidate(userProfileProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Promo code "${promo.code}" applied successfully!'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to apply promo: $e')));
      }
    }
  } else if ((post.actionType == 'link' || post.actionType == 'promo') &&
      post.actionUrl != null) {
    final url = post.actionUrl!.trim();
    if (url.startsWith('/') || url.startsWith('tranyx://')) {
      final cleanPath = url.replaceAll('tranyx://', '/');
      if (cleanPath.startsWith('/profile')) {
        ref.read(activeTabProvider.notifier).state = 'profile';
      } else if (cleanPath.startsWith('/transit')) {
        ref.read(activeTabProvider.notifier).state = 'transit';
      } else if (cleanPath.startsWith('/jobs')) {
        ref.read(activeTabProvider.notifier).state = 'jobs';
      } else {
        ref.read(activeTabProvider.notifier).state = 'home';
      }
    } else {
      try {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not open link: $url')),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Invalid link: $url')));
        }
      }
    }
  }
}

Color _getCategoryColor(String category) {
  switch (category.toLowerCase()) {
    case 'promo':
      return Colors.green;
    case 'news':
      return AppColors.indigo;
    case 'advertisement':
    case 'ad':
      return Colors.purple;
    case 'announcement':
      return Colors.orange;
    default:
      return Colors.grey;
  }
}

String _formatNewsDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inDays == 0) {
    if (diff.inHours == 0) {
      if (diff.inMinutes == 0) return "Just now";
      return "${diff.inMinutes}m ago";
    }
    return "${diff.inHours}h ago";
  }
  if (diff.inDays == 1) return "Yesterday";
  if (diff.inDays < 7) return "${diff.inDays}d ago";
  return "${date.month}/${date.day}/${date.year}";
}
