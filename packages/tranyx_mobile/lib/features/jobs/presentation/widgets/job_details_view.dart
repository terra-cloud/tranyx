import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/utils/num_extension.dart';
import 'package:tranyx_mobile/core/utils/string_extension.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/jobs/models/job.dart';
import 'package:tranyx_mobile/features/jobs/models/job_question.dart';
import 'package:tranyx_mobile/features/jobs/providers/job_repository.dart';
import 'package:tranyx_mobile/features/jobs/providers/jobs_provider.dart';
import 'package:tranyx_mobile/features/jobs/presentation/widgets/job_cards.dart';
import 'package:tranyx_mobile/features/jobs/presentation/widgets/job_sub_header.dart';

class JobDetailsView extends ConsumerStatefulWidget {
  const JobDetailsView({super.key});

  @override
  ConsumerState<JobDetailsView> createState() => _JobDetailsViewState();
}

class _JobDetailsViewState extends ConsumerState<JobDetailsView> {
  final TextEditingController _newQuestionController = TextEditingController();
  final TextEditingController _replyController = TextEditingController();

  @override
  void dispose() {
    _newQuestionController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  String _formatRate(Job job) {
    final value = job.pricingValue.toAmount(length: 0);
    if (job.pricingType.contains('Fixed') ||
        job.pricingType.contains('Package')) {
      return '$value flat';
    }
    return '$value / hr';
  }

  String _formatLocation(Job job) {
    if (job.locationType == 'Remote') return 'Remote';
    final parts = <String>[];
    if (job.address != null && job.address!.isNotEmpty) parts.add(job.address!);
    if (job.landmark != null && job.landmark!.isNotEmpty) {
      parts.add(job.landmark!);
    }
    return parts.isNotEmpty ? parts.join(', ') : 'On-site';
  }

  String _formatUrgency(Job job) {
    if (job.dateRequirement == 'Flexible') return 'Flexible';
    if (job.jobDate != null) {
      return 'By ${DateFormat('MMM d, yyyy').format(job.jobDate!)}';
    }
    return job.dateRequirement;
  }

  Color _urgencyColor(Job job) {
    if (job.dateRequirement == 'Flexible') return AppColors.green;
    if (job.jobDate != null) {
      final daysLeft = job.jobDate!.difference(DateTime.now()).inDays;
      if (daysLeft <= 3) return AppColors.red;
      if (daysLeft <= 7) return AppColors.amber;
    }
    return AppColors.amber;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final job = ref.watch(selectedJobProvider);
    final currentViewMode = ref.watch(currentViewModeProvider);
    final user = ref.watch(userProfileProvider).value;
    final isCreator = user?.uid == job?.creatorId;

    final questionsAsync = ref.watch(jobQuestionsStreamProvider(job?.id ?? ''));
    final currentUser = ref.watch(userProvider);
    final hasApplied = job?.applicantUids.contains(currentUser?.uid) ?? false;

    final activeReplyId = ref.watch(activeReplyIdProvider);
    final replyText = ref.watch(replyTextProvider);
    final newQuestionText = ref.watch(newQuestionTextProvider);

    if (job == null) return const SizedBox.shrink();

    final urgencyColor = _urgencyColor(job);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                JobSubHeader(
                  title: "Job Details",
                  onBack: () =>
                      ref.read(jobsViewProvider.notifier).state = 'list',
                  isDarkMode: isDarkMode,
                ),

                // ── Hero Card ─────────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDarkMode
                          ? [
                              AppColors.indigo.withValues(alpha: 0.15),
                              Colors.transparent,
                            ]
                          : [
                              AppColors.indigo.withValues(alpha: 0.05),
                              Colors.transparent,
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDarkMode
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          job.title.isEmpty
                              ? "Untitled Job"
                              : job.title.capitalize(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode
                                ? AppColors.darkText
                                : AppColors.lightText,
                          ),
                        ),
                      ),
                      Center(
                        child: Text(
                          _formatRate(job),
                          style: const TextStyle(
                            fontSize: 55,
                            fontFamily: "Bebas",
                            fontWeight: FontWeight.bold,
                            color: AppColors.indigo,
                          ),
                        ),
                      ),
                      // Row(
                      //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      //   crossAxisAlignment: CrossAxisAlignment.start,
                      //   children: [
                      //     Expanded(
                      // child: Text(
                      //   job.title.isEmpty
                      //       ? "Untitled Job"
                      //       : job.title.capitalize(),
                      //   style: TextStyle(
                      //     fontSize: 24,
                      //     fontWeight: FontWeight.bold,
                      //     color: isDarkMode
                      //         ? AppColors.darkText
                      //         : AppColors.lightText,
                      //   ),
                      // ),
                      //     ),
                      //     // const SizedBox(width: 12),
                      // Text(
                      //   _formatRate(job),
                      //   style: const TextStyle(
                      //     fontSize: 22,
                      //     fontWeight: FontWeight.bold,
                      //     color: AppColors.indigo,
                      //   ),
                      // ),
                      //   ],
                      // ),
                      const SizedBox(height: 8),

                      // Creator chip
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundImage:
                                (job.creatorPhotoUrl != null &&
                                    job.creatorPhotoUrl!.isNotEmpty)
                                ? NetworkImage(job.creatorPhotoUrl!)
                                      as ImageProvider
                                : const AssetImage(
                                        'assets/images/default-avatar.jpg',
                                      )
                                      as ImageProvider,
                            backgroundColor: AppColors.indigo.withValues(
                              alpha: 0.1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Posted by ${job.creatorName}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode
                                  ? AppColors.darkTextMuted
                                  : AppColors.lightTextMuted,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            DateFormat('MMM d, y').format(job.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode
                                  ? AppColors.darkTextMuted
                                  : AppColors.lightTextMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Meta chips
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _metaChip(
                            Icons.location_on,
                            _formatLocation(job),
                            isDarkMode,
                          ),
                          _metaChip(
                            Icons.schedule,
                            _formatUrgency(job),
                            isDarkMode,
                            color: urgencyColor,
                          ),
                          _metaChip(
                            Icons.work_outline,
                            job.employmentType,
                            isDarkMode,
                          ),
                          _metaChip(
                            Icons.access_time,
                            job.timePreference,
                            isDarkMode,
                          ),
                          _metaChip(
                            Icons.category_outlined,
                            job.category.label,
                            isDarkMode,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Description ───────────────────────────────────────────────────
                Text(
                  "Description",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode
                        ? AppColors.darkText
                        : AppColors.lightText,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  job.description.isNotEmpty
                      ? job.description
                      : "No description provided.",
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
                const SizedBox(height: 32),

                // ── Applicants Summary (Employer view) ────────────────────────────
                if (job.creatorType == AccountType.employer) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? AppColors.darkCard.withValues(alpha: 0.5)
                          : AppColors.lightBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDarkMode
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Applicants",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  color: isDarkMode
                                      ? AppColors.darkText
                                      : AppColors.lightText,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                job.applicantCount == 0
                                    ? "No applicants yet."
                                    : "${job.applicantCount} Nyxian${job.applicantCount == 1 ? '' : 's'} have applied.",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode
                                      ? AppColors.darkTextMuted
                                      : AppColors.lightTextMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (job.applicantCount > 0) ...[
                          const SizedBox(width: 16),
                          AvatarStack(
                            photos: job.recentApplicantPhotos.isNotEmpty
                                ? job.recentApplicantPhotos
                                : [''],
                            size: 36,
                            maxVisible: 4,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // ── Public Q&A ────────────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.only(bottom: 32),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? AppColors.darkCard.withValues(alpha: 0.5)
                        : AppColors.lightBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDarkMode
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Public Q&A",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: 16),
                      questionsAsync.when(
                        data: (questions) {
                          if (questions.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Text(
                                isCreator
                                    ? "No questions yet."
                                    : "No questions yet. Be the first to ask!",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode
                                      ? AppColors.darkTextMuted
                                      : AppColors.lightTextMuted,
                                ),
                              ),
                            );
                          }
                          return Column(
                            children: questions.map((q) {
                              final isReplying = activeReplyId == q.id;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Question Bubble
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundImage:
                                              (q.authorPhotoUrl != null &&
                                                  q.authorPhotoUrl!.isNotEmpty)
                                              ? NetworkImage(q.authorPhotoUrl!)
                                                    as ImageProvider
                                              : const AssetImage(
                                                      'assets/images/default-avatar.jpg',
                                                    )
                                                    as ImageProvider,
                                          backgroundColor: isDarkMode
                                              ? AppColors.darkBorder
                                              : AppColors.lightBorder,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: isReplying
                                                        ? const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          )
                                                        : EdgeInsets.zero,
                                                    decoration: isReplying
                                                        ? BoxDecoration(
                                                            color: AppColors
                                                                .indigo
                                                                .withValues(
                                                                  alpha: 0.1,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                          )
                                                        : null,
                                                    child: Text(
                                                      q.authorName,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: isReplying
                                                            ? FontWeight.bold
                                                            : FontWeight.w600,
                                                        color: isReplying
                                                            ? AppColors.indigo
                                                            : (isDarkMode
                                                                  ? AppColors
                                                                        .darkText
                                                                  : AppColors
                                                                        .lightText),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    _formatTimestamp(
                                                      q.createdAt,
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: isDarkMode
                                                          ? AppColors
                                                                .darkTextMuted
                                                          : AppColors
                                                                .lightTextMuted,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isDarkMode
                                                      ? AppColors.darkBg
                                                      : AppColors.lightBg,
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                        topRight:
                                                            Radius.circular(12),
                                                        bottomLeft:
                                                            Radius.circular(12),
                                                        bottomRight:
                                                            Radius.circular(12),
                                                      ),
                                                ),
                                                child: _buildHighlightedText(
                                                  q.questionText,
                                                  isDarkMode,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (q.answerText != null) ...[
                                      const SizedBox(height: 12),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 20,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.subdirectory_arrow_right,
                                              size: 16,
                                              color: AppColors.indigo,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    "Author's Reply",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: isDarkMode
                                                          ? AppColors.darkText
                                                          : AppColors.lightText,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    q.answerText!,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: isDarkMode
                                                          ? AppColors
                                                                .darkTextMuted
                                                          : AppColors
                                                                .lightTextMuted,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    // Reply section for job creator
                                    if (isCreator && q.answerText == null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: isReplying
                                            ? Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isDarkMode
                                                      ? AppColors.darkCard
                                                      : Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: isDarkMode
                                                        ? AppColors.darkBorder
                                                        : AppColors.lightBorder,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      child: TextField(
                                                        controller:
                                                            _replyController,
                                                        autofocus: true,
                                                        onChanged: (val) =>
                                                            ref
                                                                    .read(
                                                                      replyTextProvider
                                                                          .notifier,
                                                                    )
                                                                    .state =
                                                                val,
                                                        decoration: InputDecoration(
                                                          hintText:
                                                              "Reply to ${q.authorName}...",
                                                          hintStyle: TextStyle(
                                                            color: isDarkMode
                                                                ? AppColors
                                                                      .darkTextMuted
                                                                : AppColors
                                                                      .lightTextMuted,
                                                            fontSize: 14,
                                                          ),
                                                          border:
                                                              InputBorder.none,
                                                          isDense: true,
                                                        ),
                                                        style: TextStyle(
                                                          color: isDarkMode
                                                              ? AppColors
                                                                    .darkText
                                                              : AppColors
                                                                    .lightText,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.send,
                                                        size: 16,
                                                        color: Colors.white,
                                                      ),
                                                      onPressed: () async {
                                                        if (replyText
                                                            .trim()
                                                            .isEmpty) {
                                                          return;
                                                        }
                                                        await ref
                                                            .read(
                                                              jobRepositoryProvider,
                                                            )
                                                            .answerJobQuestion(
                                                              job.id,
                                                              q.id,
                                                              replyText,
                                                            );
                                                        ref
                                                                .read(
                                                                  replyTextProvider
                                                                      .notifier,
                                                                )
                                                                .state =
                                                            '';
                                                        ref
                                                                .read(
                                                                  activeReplyIdProvider
                                                                      .notifier,
                                                                )
                                                                .state =
                                                            null;
                                                        _replyController
                                                            .clear();
                                                      },
                                                      style: IconButton.styleFrom(
                                                        backgroundColor:
                                                            AppColors.indigo,
                                                        padding:
                                                            const EdgeInsets.all(
                                                              8,
                                                            ),
                                                        minimumSize: const Size(
                                                          32,
                                                          32,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : TextButton(
                                                onPressed: () {
                                                  ref
                                                      .read(
                                                        activeReplyIdProvider
                                                            .notifier,
                                                      )
                                                      .state = q
                                                      .id;
                                                  _replyController.text =
                                                      "@${q.authorName} ";
                                                  ref
                                                          .read(
                                                            replyTextProvider
                                                                .notifier,
                                                          )
                                                          .state =
                                                      _replyController.text;
                                                },
                                                style: TextButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8,
                                                      ),
                                                  backgroundColor: isDarkMode
                                                      ? AppColors.darkCard
                                                      : Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    side: BorderSide(
                                                      color: isDarkMode
                                                          ? AppColors.darkBorder
                                                          : AppColors
                                                                .lightBorder,
                                                    ),
                                                  ),
                                                ),
                                                child: Text(
                                                  "Reply to ${q.authorName}",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: isDarkMode
                                                        ? AppColors.darkText
                                                        : AppColors.lightText,
                                                  ),
                                                ),
                                              ),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                        loading: () => const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.indigo,
                          ),
                        ),
                        error: (err, stack) => Center(
                          child: Text(
                            "Error loading questions",
                            style: TextStyle(
                              color: Colors.red[300],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      // Nyxian can ask questions (if not already applied)
                      if (currentViewMode == AccountType.nyxian &&
                          !hasApplied) ...[
                        Divider(
                          color: isDarkMode
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Ask the author a question:",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode
                                ? AppColors.darkTextMuted
                                : AppColors.lightTextMuted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? AppColors.darkCard
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDarkMode
                                  ? AppColors.darkBorder
                                  : AppColors.lightBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _newQuestionController,
                                  onChanged: (val) =>
                                      ref
                                              .read(
                                                newQuestionTextProvider
                                                    .notifier,
                                              )
                                              .state =
                                          val,
                                  decoration: InputDecoration(
                                    hintText: "Type your question...",
                                    hintStyle: TextStyle(
                                      color: isDarkMode
                                          ? AppColors.darkTextMuted
                                          : AppColors.lightTextMuted,
                                      fontSize: 14,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                  style: TextStyle(
                                    color: isDarkMode
                                        ? AppColors.darkText
                                        : AppColors.lightText,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.send,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                onPressed: () async {
                                  if (newQuestionText.trim().isEmpty) return;
                                  if (user == null) return;

                                  final question = JobQuestion(
                                    id: '', // Firestore will generate
                                    jobId: job.id,
                                    authorId: user.uid,
                                    authorName: user.name,
                                    authorPhotoUrl: user.photoUrl,
                                    questionText: newQuestionText,
                                    createdAt: DateTime.now(),
                                  );

                                  await ref
                                      .read(jobRepositoryProvider)
                                      .addJobQuestion(job.id, question);

                                  ref
                                          .read(
                                            newQuestionTextProvider.notifier,
                                          )
                                          .state =
                                      '';
                                  _newQuestionController.clear();
                                },
                                style: IconButton.styleFrom(
                                  backgroundColor: AppColors.indigo,
                                  padding: const EdgeInsets.all(8),
                                  minimumSize: const Size(32, 32),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Action Buttons (Sticky at bottom) ────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.darkBg : AppColors.lightBg,
            border: Border(
              top: BorderSide(
                color: isDarkMode
                    ? AppColors.darkBorder
                    : AppColors.lightBorder,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCreator)
                // Employer sees their own job → Review applicants
                if (currentViewMode == AccountType.employer)
                  Row(
                    children: [
                      Expanded(
                        child: UIHelpers.buildPrimaryButton(
                          "Edit Listing",
                          () {},
                          isDarkMode,
                          isOutlined: true,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: UIHelpers.buildPrimaryButton(
                          "Review Applicants (${job.applicantCount})",
                          () => ref.read(jobsViewProvider.notifier).state =
                              'review',
                          isDarkMode,
                        ),
                      ),
                    ],
                  )
                else
                  // Nyxian sees their own gig
                  UIHelpers.buildPrimaryButton(
                    "Edit Gig",
                    () {},
                    isDarkMode,
                    isOutlined: true,
                  )
              // Nyxian sees the job created by an Employer → Apply button
              else if (currentViewMode == AccountType.nyxian &&
                  job.creatorType == AccountType.employer)
                hasApplied
                    ? UIHelpers.buildPrimaryButton(
                        "Already applied",
                        null,
                        isDarkMode,
                        isOutlined: true,
                      )
                    : UIHelpers.buildPrimaryButton(
                        "Proceed to application",
                        () {
                          ref.read(isCounterOfferProvider.notifier).state =
                              false;
                          ref.read(jobsViewProvider.notifier).state = 'apply';
                        },
                        isDarkMode,
                      )
              // Employer sees a Nyxian gig → Contact/Hire button
              else if (currentViewMode == AccountType.employer &&
                  job.creatorType == AccountType.nyxian)
                hasApplied
                    ? UIHelpers.buildPrimaryButton(
                        "Already Contacted",
                        null,
                        isDarkMode,
                        isOutlined: true,
                      )
                    : UIHelpers.buildPrimaryButton("Contact Nyxian", () {
                        ref.read(isCounterOfferProvider.notifier).state = false;
                        ref.read(jobsViewProvider.notifier).state = 'apply';
                      }, isDarkMode),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHighlightedText(
    String text,
    bool isDarkMode, {
    bool isMuted = false,
  }) {
    final List<TextSpan> spans = [];
    final words = text.split(' ');

    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final spacing = i < words.length - 1 ? ' ' : '';

      if (word.startsWith('@')) {
        spans.add(
          TextSpan(
            text: '$word$spacing',
            style: const TextStyle(
              color: AppColors.indigo,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: '$word$spacing',
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode
                  ? (isMuted ? AppColors.darkTextMuted : AppColors.darkText)
                  : (isMuted ? AppColors.lightTextMuted : AppColors.lightText),
            ),
          ),
        );
      }
    }

    return RichText(text: TextSpan(children: spans));
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return "Just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    return "${dt.day}/${dt.month}";
  }

  Widget _metaChip(
    IconData icon,
    String label,
    bool isDarkMode, {
    Color? color,
  }) {
    final effectiveColor =
        color ??
        (isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: effectiveColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: effectiveColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: effectiveColor,
            ),
          ),
        ],
      ),
    );
  }
}
