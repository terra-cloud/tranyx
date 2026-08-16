import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/utils/num_extension.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/jobs/providers/jobs_provider.dart';
import 'package:tranyx_mobile/features/jobs/providers/job_repository.dart';
import 'package:tranyx_mobile/features/jobs/presentation/widgets/job_sub_header.dart';
import 'package:tranyx_mobile/core/widgets/user_avatar.dart';

class ReviewApplicantsView extends ConsumerStatefulWidget {
  const ReviewApplicantsView({super.key});

  @override
  ConsumerState<ReviewApplicantsView> createState() => _ReviewApplicantsViewState();
}

class _ReviewApplicantsViewState extends ConsumerState<ReviewApplicantsView> {
  String? _hiringApplicantId;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final selectedJob = ref.watch(selectedJobProvider);

    if (selectedJob == null) return const SizedBox.shrink();

    final applicationsAsync = ref.watch(
      jobApplicationsProvider(selectedJob.id),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobSubHeader(
            title: "Review Applicants (${selectedJob.applicantCount})",
            onBack: () => ref.read(jobsViewProvider.notifier).state = 'details',
            isDarkMode: isDarkMode,
          ),
          applicationsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, stack) => Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Error loading applicants: $err",
                style: const TextStyle(color: Colors.red),
              ),
            ),
            data: (applications) {
              if (applications.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Center(
                    child: Text(
                      "No applicants yet.",
                      style: TextStyle(
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: applications.map((applicant) {
                  final isCounter = applicant.isCounterOffer;
                  final isHiringThisOne = _hiringApplicantId == applicant.applicantUid;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? AppColors.darkCard
                          : AppColors.lightCard,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDarkMode
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  UserAvatar(
                                    name: applicant.applicantName,
                                    photoUrl: applicant.applicantPhotoUrl,
                                    radius: 24,
                                    border: Border.all(
                                      color: isDarkMode
                                          ? AppColors.darkBorder
                                          : AppColors.lightBg,
                                      width: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          applicant.applicantName,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: isDarkMode
                                                ? AppColors.darkText
                                                : AppColors.lightText,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.star_outline,
                                              color: isDarkMode
                                                  ? AppColors.darkTextMuted
                                                  : AppColors.lightTextMuted,
                                              size: 14,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              "Unrated",
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
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  applicant.proposalRate.toAmount(length: 0),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.indigo,
                                  ),
                                ),
                                Text(
                                  isCounter ? "COUNTER OFFER" : "STANDARD RATE",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                    color: isCounter
                                        ? AppColors.amber
                                        : (isDarkMode
                                              ? AppColors.darkTextMuted
                                              : AppColors.lightTextMuted),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (applicant.coverNote.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? AppColors.darkBg
                                  : AppColors.lightBg,
                              border: Border.all(
                                color: isDarkMode
                                    ? AppColors.darkBorder.withValues(
                                        alpha: 0.5,
                                      )
                                    : AppColors.lightBorder,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              "\"${applicant.coverNote}\"",
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                fontSize: 14,
                                color: isDarkMode
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: isHiringThisOne
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(vertical: 8.0),
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  : UIHelpers.buildPrimaryButton(
                                      "Accept Nyxian",
                                      () async {
                                        final userProfile = ref.read(userProfileProvider).value;
                                        if (userProfile == null) return;

                                        setState(() {
                                          _hiringApplicantId = applicant.applicantUid;
                                        });

                                        try {
                                          await ref.read(jobRepositoryProvider).acceptApplicant(
                                            jobId: selectedJob.id,
                                            application: applicant,
                                            employerUid: userProfile.uid,
                                          );

                                          ref.invalidate(userProfileProvider);
                                          ref.read(jobsViewProvider.notifier).state = 'success';
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text("Error: ${e.toString().replaceAll("Exception: ", "")}"),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() {
                                              _hiringApplicantId = null;
                                            });
                                          }
                                        }
                                      },
                                      isDarkMode,
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isDarkMode
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: IconButton(
                                icon: Icon(
                                  Icons.chat_bubble_outline,
                                  color: isDarkMode
                                      ? AppColors.darkText
                                      : AppColors.lightText,
                                ),
                                onPressed: () {},
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
