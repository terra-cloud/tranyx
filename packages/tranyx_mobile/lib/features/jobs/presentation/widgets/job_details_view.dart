import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:tranyx_mobile/core/widgets/user_avatar.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tranyx_mobile/core/providers/image_upload_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class JobDetailsView extends ConsumerStatefulWidget {
  const JobDetailsView({super.key});

  @override
  ConsumerState<JobDetailsView> createState() => _JobDetailsViewState();
}

class _JobDetailsViewState extends ConsumerState<JobDetailsView> {
  final TextEditingController _newQuestionController = TextEditingController();
  final TextEditingController _replyController = TextEditingController();
  bool _isLoading = false;
  bool _isUploadingReceipt = false;
  String? _uploadedReceiptUrl;

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

  void _showRatingDialog({
    required BuildContext context,
    required Job job,
    required String targetId,
    required String targetName,
    required AccountType currentViewMode,
  }) {
    int rating = 5;
    final commentController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = ref.read(themeModeProvider);
            return AlertDialog(
              backgroundColor: isDark ? AppColors.darkCard : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                'Rate $targetName',
                style: TextStyle(
                  color: isDark ? AppColors.darkText : AppColors.lightText,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'How was your experience working with $targetName?',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starScore = index + 1;
                      return IconButton(
                        icon: Icon(
                          Icons.star,
                          size: 36,
                          color: rating >= starScore
                              ? AppColors.indigo
                              : Colors.grey[400],
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () {
                                setDialogState(() {
                                  rating = starScore;
                                });
                              },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: commentController,
                    maxLines: 3,
                    enabled: !isSubmitting,
                    style: TextStyle(
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Write a review...',
                      hintStyle: TextStyle(
                        color: isDark
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                      filled: true,
                      fillColor: isDark ? AppColors.darkBg : Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() {
                            isSubmitting = true;
                          });
                          try {
                            final userProfile = ref
                                .read(userProfileProvider)
                                .value;
                            await ref
                                .read(jobRepositoryProvider)
                                .submitJobRating(
                                  jobId: job.id,
                                  targetId: targetId,
                                  reviewerUid: userProfile?.uid ?? '',
                                  reviewerName: userProfile?.name ?? 'User',
                                  score: rating,
                                  comment: commentController.text.trim(),
                                  currentViewMode: currentViewMode,
                                );
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Rating submitted successfully!',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: ${e.toString()}'),
                                ),
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEnterCodeDialog({required BuildContext context, required Job job}) {
    final codeController = TextEditingController();
    bool isSubmitting = false;
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = ref.read(themeModeProvider);
            return AlertDialog(
              backgroundColor: isDark ? AppColors.darkCard : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text(
                'Enter Completion Code',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Please enter the 6-digit completion code provided by the other party to complete the job and release the escrow.',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    enabled: !isSubmitting,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      hintText: '000000',
                      counterText: '',
                      filled: true,
                      fillColor: isDark ? AppColors.darkBg : Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMessage!,
                      style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final code = codeController.text.trim();
                          if (code.length != 6) {
                            setDialogState(() {
                              errorMessage = 'Please enter a 6-digit code.';
                            });
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                            errorMessage = null;
                          });

                          try {
                            final userProfile = ref
                                .read(userProfileProvider)
                                .value;
                            await ref
                                .read(jobRepositoryProvider)
                                .completeJob(
                                  jobId: job.id,
                                  verificationCodeEntered: code,
                                  currentUserUid: userProfile?.uid ?? '',
                                  currentUserName: userProfile?.name ?? 'User',
                                );
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Escrow released and job completed successfully! 🎉',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() {
                              errorMessage = e
                                  .toString()
                                  .replaceAll('Exception:', '')
                                  .trim();
                            });
                          } finally {
                            setDialogState(() {
                              isSubmitting = false;
                            });
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Verify & Complete'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickAndUploadReceiptImage(BuildContext context, Job job) async {
    final ImagePicker picker = ImagePicker();
    final isDark = ref.read(themeModeProvider);

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.indigo),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: AppColors.indigo,
                ),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera permission denied')),
          );
        }
        return;
      }
    }

    try {
      final XFile? pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 80,
      );

      if (pickedFile == null) return;

      setState(() {
        _isUploadingReceipt = true;
      });

      final uploadService = ref.read(imgBBServiceProvider);
      final url = await uploadService.uploadImage(File(pickedFile.path));

      if (url != null && mounted) {
        setState(() {
          _uploadedReceiptUrl = url;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt uploaded successfully!')),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload receipt image.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingReceipt = false;
        });
      }
    }
  }

  Future<void> _handleCancelJob(Job job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDark = ref.read(themeModeProvider);

        final bool reachedFirstPoint =
            job.hasTracker &&
            (job.status == 'arrived_pickup' ||
                job.status == 'paid_cashier' ||
                job.status == 'in_transit' ||
                job.status == 'arrived_dropoff' ||
                job.status == 'done' ||
                job.status == 'completed');

        final String message = reachedFirstPoint
            ? 'The Nyxian has reached/passed the first point. If you cancel, the Nyxian will be compensated 20 tyxbits from the escrow, and the remaining escrow will be refunded to you. Are you sure you want to cancel?'
            : 'Are you sure you want to cancel this job? You will receive a 100% refund of the escrow.';

        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkCard : Colors.white,
          title: const Text(
            'Cancel Job',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            message,
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Yes, Cancel',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      setState(() => _isLoading = true);
      try {
        final userProfile = ref.read(userProfileProvider).value;
        await ref
            .read(jobRepositoryProvider)
            .cancelJob(jobId: job.id, currentUserUid: userProfile?.uid ?? '');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Job cancelled successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error cancelling job: $e')));
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final job = ref.watch(selectedJobProvider);
    final currentViewMode = ref.watch(currentViewModeProvider);
    final user = ref.watch(userProfileProvider).value;
    final questionsAsync = ref.watch(jobQuestionsStreamProvider(job?.id ?? ''));
    final currentUser = ref.watch(userProvider);

    if (job == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref
          .watch(firestoreProvider)
          .collection('jobs')
          .doc(job.id)
          .snapshots(),
      builder: (context, snapshot) {
        final Job activeJob;
        if (snapshot.hasData && snapshot.data!.exists) {
          activeJob = Job.fromMap(snapshot.data!.data()!, snapshot.data!.id);
        } else {
          activeJob = job;
        }

        final isCreator = user?.uid == activeJob.creatorId;
        final hasApplied = activeJob.applicantUids.contains(currentUser?.uid);
        final activeReplyId = ref.watch(activeReplyIdProvider);
        final replyText = ref.watch(replyTextProvider);
        final newQuestionText = ref.watch(newQuestionTextProvider);
        final urgencyColor = _urgencyColor(activeJob);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
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
                              activeJob.title.isEmpty
                                  ? "Untitled Job"
                                  : activeJob.title.capitalize(),
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
                              _formatRate(activeJob),
                              style: const TextStyle(
                                fontSize: 55,
                                fontFamily: "Bebas",
                                fontWeight: FontWeight.bold,
                                color: AppColors.indigo,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Creator chip
                          Row(
                            children: [
                              UserAvatar(
                                name: activeJob.creatorName,
                                photoUrl: activeJob.creatorPhotoUrl,
                                radius: 12,
                                backgroundColor: AppColors.indigo.withValues(
                                  alpha: 0.1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Posted by ${activeJob.creatorName}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode
                                      ? AppColors.darkTextMuted
                                      : AppColors.lightTextMuted,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                DateFormat(
                                  'MMM d, y',
                                ).format(activeJob.createdAt),
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
                                _formatLocation(activeJob),
                                isDarkMode,
                              ),
                              _metaChip(
                                Icons.schedule,
                                _formatUrgency(activeJob),
                                isDarkMode,
                                color: urgencyColor,
                              ),
                              _metaChip(
                                Icons.work_outline,
                                activeJob.employmentType,
                                isDarkMode,
                              ),
                              _metaChip(
                                Icons.access_time,
                                activeJob.timePreference,
                                isDarkMode,
                              ),
                              _metaChip(
                                Icons.category_outlined,
                                activeJob.category.label,
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
                      activeJob.description.isNotEmpty
                          ? activeJob.description
                          : "No description provided.",
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Delivery Tracker Timeline ─────────────────────────────────────
                    if (activeJob.hasTracker) ...[
                      _buildDeliveryTrackerTimeline(activeJob, isDarkMode),
                      const SizedBox(height: 24),
                    ],

                    // Proof of Payment / Receipt display
                    if (activeJob.receiptUrl != null &&
                        activeJob.receiptUrl!.isNotEmpty) ...[
                      Text(
                        "Receipt / Proof of Payment",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: 12),
                       GestureDetector(
                         onTap: () => UIHelpers.showFullScreenImage(context, activeJob.receiptUrl!),
                         child: ClipRRect(
                           borderRadius: BorderRadius.circular(16),
                           child: Image.network(
                             activeJob.receiptUrl!,
                             width: double.infinity,
                             height: 220,
                             fit: BoxFit.cover,
                             errorBuilder: (context, error, stackTrace) =>
                                 Container(
                                   height: 120,
                                   color: isDarkMode
                                       ? Colors.grey[800]
                                       : Colors.grey[200],
                                   child: const Center(
                                     child: Text("Error loading receipt"),
                                   ),
                                 ),
                           ),
                         ),
                       ),
                      const SizedBox(height: 24),
                    ],

                    // ── Applicants Summary (Employer view) ────────────────────────────
                    if (activeJob.creatorType == AccountType.employer &&
                        activeJob.status.toLowerCase() == 'open') ...[
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
                                    activeJob.applicantCount == 0
                                        ? "No applicants yet."
                                        : "${activeJob.applicantCount} Nyxian${activeJob.applicantCount == 1 ? '' : 's'} have applied.",
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
                            if (activeJob.applicantCount > 0) ...[
                              const SizedBox(width: 16),
                              AvatarStack(
                                photos:
                                    activeJob.recentApplicantPhotos.isNotEmpty
                                    ? activeJob.recentApplicantPhotos
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Question Bubble
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            UserAvatar(
                                              name: q.authorName,
                                              photoUrl: q.authorPhotoUrl,
                                              radius: 16,
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
                                                                      alpha:
                                                                          0.1,
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
                                                            fontWeight:
                                                                isReplying
                                                                ? FontWeight
                                                                      .bold
                                                                : FontWeight
                                                                      .w600,
                                                            color: isReplying
                                                                ? AppColors
                                                                      .indigo
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
                                                    padding:
                                                        const EdgeInsets.all(
                                                          12,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isDarkMode
                                                          ? AppColors.darkBg
                                                          : AppColors.lightBg,
                                                      borderRadius:
                                                          const BorderRadius.only(
                                                            topRight:
                                                                Radius.circular(
                                                                  12,
                                                                ),
                                                            bottomLeft:
                                                                Radius.circular(
                                                                  12,
                                                                ),
                                                            bottomRight:
                                                                Radius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                    ),
                                                    child:
                                                        _buildHighlightedText(
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
                                                  Icons
                                                      .subdirectory_arrow_right,
                                                  size: 16,
                                                  color: AppColors.indigo,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        "Author's Reply",
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: isDarkMode
                                                              ? AppColors
                                                                    .darkText
                                                              : AppColors
                                                                    .lightText,
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
                                            padding: const EdgeInsets.only(
                                              top: 12,
                                            ),
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
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                      border: Border.all(
                                                        color: isDarkMode
                                                            ? AppColors
                                                                  .darkBorder
                                                            : AppColors
                                                                  .lightBorder,
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
                                                                color:
                                                                    isDarkMode
                                                                    ? AppColors
                                                                          .darkTextMuted
                                                                    : AppColors
                                                                          .lightTextMuted,
                                                                fontSize: 14,
                                                              ),
                                                              border:
                                                                  InputBorder
                                                                      .none,
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
                                                                  activeJob.id,
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
                                                                AppColors
                                                                    .indigo,
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  8,
                                                                ),
                                                            minimumSize:
                                                                const Size(
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
                                                      backgroundColor:
                                                          isDarkMode
                                                          ? AppColors.darkCard
                                                          : Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        side: BorderSide(
                                                          color: isDarkMode
                                                              ? AppColors
                                                                    .darkBorder
                                                              : AppColors
                                                                    .lightBorder,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      "Reply to ${q.authorName}",
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: isDarkMode
                                                            ? AppColors.darkText
                                                            : AppColors
                                                                  .lightText,
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
                                      if (newQuestionText.trim().isEmpty)
                                        return;
                                      if (user == null) return;

                                      final question = JobQuestion(
                                        id: '', // Firestore will generate
                                        jobId: activeJob.id,
                                        authorId: user.uid,
                                        authorName: user.name,
                                        authorPhotoUrl: user.photoUrl,
                                        questionText: newQuestionText,
                                        createdAt: DateTime.now(),
                                      );

                                      await ref
                                          .read(jobRepositoryProvider)
                                          .addJobQuestion(
                                            activeJob.id,
                                            question,
                                          );

                                      ref
                                              .read(
                                                newQuestionTextProvider
                                                    .notifier,
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
            // ── Action Buttons ──────────────────────────────────────────────
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDarkMode
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
              ),
              child: _buildLifecycleActions(
                job: activeJob,
                isDarkMode: isDarkMode,
                currentViewMode: currentViewMode,
                user: user,
                hasApplied: hasApplied,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLifecycleActions({
    required Job job,
    required bool isDarkMode,
    required AccountType currentViewMode,
    required UserProfile? user,
    required bool hasApplied,
  }) {
    final String status = job.status;
    final bool hasTracker = job.hasTracker;
    final isAssignedWorker = job.acceptedApplicantId == user?.uid;
    final isEmployer = job.creatorId == user?.uid;

    if (status.toLowerCase() == 'cancelled') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel, color: AppColors.red),
            SizedBox(width: 8),
            Text(
              'This gig has been cancelled.',
              style: TextStyle(
                color: AppColors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    if (currentViewMode == AccountType.employer && isEmployer) {
      if (status.toLowerCase() == 'open') {
        return Row(
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
                () => ref.read(jobsViewProvider.notifier).state = 'review',
                isDarkMode,
              ),
            ),
          ],
        );
      } else if (status == 'In Progress' || status == 'in_progress') {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.indigo.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.indigo.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.indigo),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasTracker
                          ? 'Delivery in progress. Nyxian is fulfilling your delivery order.'
                          : 'Work in progress. Nyxian is currently working on your task.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDarkMode
                            ? AppColors.darkText
                            : AppColors.lightText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            UIHelpers.buildPrimaryButton(
              "Cancel Job",
              () => _handleCancelJob(job),
              isDarkMode,
              isOutlined: true,
            ),
          ],
        );
      } else if (status == 'heading_to_pickup' ||
          status == 'arrived_pickup' ||
          status == 'paid_cashier' ||
          status == 'in_transit') {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.indigo.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.indigo.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    color: AppColors.indigo,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      status == 'heading_to_pickup'
                          ? 'Nyxian is heading to the pickup location.'
                          : status == 'arrived_pickup'
                          ? 'Nyxian has arrived at the pickup location.'
                          : status == 'paid_cashier'
                          ? 'Nyxian has paid at the pickup location.'
                          : 'Nyxian is in transit to destination.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDarkMode
                            ? AppColors.darkText
                            : AppColors.lightText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            UIHelpers.buildPrimaryButton(
              "Cancel Job",
              () => _handleCancelJob(job),
              isDarkMode,
              isOutlined: true,
            ),
          ],
        );
      } else if (status.toLowerCase() == 'done') {
        if (hasTracker) {
          return UIHelpers.buildPrimaryButton(
            "Enter Completion Code",
            () => _showEnterCodeDialog(context: context, job: job),
            isDarkMode,
          );
        } else {
          if (job.completionCode != null && job.completionCode!.isNotEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.green.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Completion Code Generated',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      MockQrCode(data: job.completionCode!),
                      const SizedBox(height: 16),
                      Text(
                        job.completionCode!,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                          color: isDarkMode
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Share this code with the Nyxian to release escrow.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return UIHelpers.buildPrimaryButton(
            _isLoading ? "Generating..." : "Generate Payment Code",
            _isLoading
                ? null
                : () async {
                    setState(() => _isLoading = true);
                    try {
                      final code =
                          (100000 +
                                  (DateTime.now().millisecondsSinceEpoch %
                                      900000))
                              .toString();
                      await ref
                          .read(jobRepositoryProvider)
                          .updateJobStatus(
                            job.id,
                            'done',
                            additionalFields: {'completionCode': code},
                          );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Payment code generated!'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error generating code: $e')),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _isLoading = false);
                      }
                    }
                  },
            isDarkMode,
          );
        }
      } else if (status == 'arrived_dropoff') {
        return UIHelpers.buildPrimaryButton(
          "Enter Completion Code",
          () => _showEnterCodeDialog(context: context, job: job),
          isDarkMode,
        );
      } else if (status.toLowerCase() == 'completed') {
        if (!job.employerRated) {
          final String targetName = job.acceptedApplicantId != null
              ? 'Nyxian'
              : 'Worker';
          return UIHelpers.buildPrimaryButton(
            "Rate Nyxian",
            () => _showRatingDialog(
              context: context,
              job: job,
              targetId: job.acceptedApplicantId ?? '',
              targetName: targetName,
              currentViewMode: currentViewMode,
            ),
            isDarkMode,
          );
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: AppColors.green),
              SizedBox(width: 8),
              Text(
                'Job Completed & Rated',
                style: TextStyle(
                  color: AppColors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }
    } else if (currentViewMode == AccountType.nyxian && isAssignedWorker) {
      if (status == 'In Progress' || status == 'in_progress') {
        if (hasTracker) {
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.indigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.indigo.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'Tap below to start your delivery route.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDarkMode
                        ? AppColors.darkText
                        : AppColors.lightText,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: UIHelpers.buildPrimaryButton(
                      "Cancel Job",
                      () => _handleCancelJob(job),
                      isDarkMode,
                      isOutlined: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: UIHelpers.buildPrimaryButton(
                      _isLoading ? "Updating..." : "Start Delivery",
                      _isLoading
                          ? null
                          : () async {
                              setState(() => _isLoading = true);
                              try {
                                await ref
                                    .read(jobRepositoryProvider)
                                    .updateJobStatus(
                                      job.id,
                                      'heading_to_pickup',
                                    );
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error updating status: $e',
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _isLoading = false);
                                }
                              }
                            },
                      isDarkMode,
                    ),
                  ),
                ],
              ),
            ],
          );
        } else {
          return Row(
            children: [
              Expanded(
                child: UIHelpers.buildPrimaryButton(
                  "Cancel Job",
                  () => _handleCancelJob(job),
                  isDarkMode,
                  isOutlined: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: UIHelpers.buildPrimaryButton(
                  _isLoading ? "Updating..." : "Mark as Done",
                  _isLoading
                      ? null
                      : () async {
                          setState(() => _isLoading = true);
                          try {
                            await ref
                                .read(jobRepositoryProvider)
                                .updateJobStatus(job.id, 'done');
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _isLoading = false);
                            }
                          }
                        },
                  isDarkMode,
                ),
              ),
            ],
          );
        }
      } else if (status == 'heading_to_pickup') {
        final firstPointLabel = job.pickupAddress ?? 'First Point';
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.indigo.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.indigo.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                'Tap below when you arrive at the pickup location: $firstPointLabel',
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: UIHelpers.buildPrimaryButton(
                    "Cancel Job",
                    () => _handleCancelJob(job),
                    isDarkMode,
                    isOutlined: true,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: UIHelpers.buildPrimaryButton(
                    _isLoading ? "Updating..." : "Arrived at First Point",
                    _isLoading
                        ? null
                        : () async {
                            setState(() => _isLoading = true);
                            try {
                              await ref
                                  .read(jobRepositoryProvider)
                                  .updateJobStatus(job.id, 'arrived_pickup');
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error updating status: $e'),
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _isLoading = false);
                              }
                            }
                          },
                    isDarkMode,
                  ),
                ),
              ],
            ),
          ],
        );
      } else if (status == 'arrived_pickup') {
        final photoUrl = _uploadedReceiptUrl ?? job.receiptUrl;
        final isPhotoAvailable = photoUrl != null && photoUrl.isNotEmpty;

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.amber.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                'Please upload the receipt/item photo to proceed.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
              ),
            ),
            GestureDetector(
              onTap: _isUploadingReceipt
                  ? null
                  : () => _pickAndUploadReceiptImage(context, job),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isPhotoAvailable
                        ? AppColors.green
                        : (isDarkMode
                              ? AppColors.darkBorder
                              : AppColors.lightBorder),
                    style: BorderStyle.solid,
                  ),
                  color: isDarkMode ? AppColors.darkCard : Colors.grey[50],
                ),
                child: Column(
                  children: [
                    if (_isUploadingReceipt) ...[
                      const CircularProgressIndicator(color: AppColors.indigo),
                      const SizedBox(height: 8),
                      const Text(
                        'Uploading Proof...',
                        style: TextStyle(fontSize: 12),
                      ),
                    ] else if (isPhotoAvailable) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          photoUrl,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap to change receipt photo',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ] else ...[
                      const Icon(
                        Icons.cloud_upload_outlined,
                        size: 36,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Upload Receipt / Photo',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: UIHelpers.buildPrimaryButton(
                    "Cancel Job",
                    () => _handleCancelJob(job),
                    isDarkMode,
                    isOutlined: true,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: UIHelpers.buildPrimaryButton(
                    _isLoading ? "Updating..." : "Mark as Picked Up / Paid",
                    (!isPhotoAvailable || _isLoading)
                        ? null
                        : () async {
                            setState(() => _isLoading = true);
                            try {
                              await ref
                                  .read(jobRepositoryProvider)
                                  .updateJobStatus(
                                    job.id,
                                    'paid_cashier',
                                    additionalFields: {'receiptUrl': photoUrl},
                                  );
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error updating status: $e'),
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _isLoading = false);
                              }
                            }
                          },
                    isDarkMode,
                  ),
                ),
              ],
            ),
          ],
        );
      } else if (status == 'paid_cashier') {
        final destName = job.destinationAddress ?? 'Destination';
        return Row(
          children: [
            Expanded(
              child: UIHelpers.buildPrimaryButton(
                "Cancel Job",
                () => _handleCancelJob(job),
                isDarkMode,
                isOutlined: true,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: UIHelpers.buildPrimaryButton(
                _isLoading ? "Updating..." : "Going to $destName",
                _isLoading
                    ? null
                    : () async {
                        setState(() => _isLoading = true);
                        try {
                          await ref
                              .read(jobRepositoryProvider)
                              .updateJobStatus(job.id, 'in_transit');
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error updating status: $e'),
                              ),
                            );
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isLoading = false);
                          }
                        }
                      },
                isDarkMode,
              ),
            ),
          ],
        );
      } else if (status == 'in_transit') {
        return Row(
          children: [
            Expanded(
              child: UIHelpers.buildPrimaryButton(
                "Cancel Job",
                () => _handleCancelJob(job),
                isDarkMode,
                isOutlined: true,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: UIHelpers.buildPrimaryButton(
                _isLoading ? "Updating..." : "Arrived at Destination",
                _isLoading
                    ? null
                    : () async {
                        setState(() => _isLoading = true);
                        try {
                          await ref
                              .read(jobRepositoryProvider)
                              .updateJobStatus(job.id, 'arrived_dropoff');
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error updating status: $e'),
                              ),
                            );
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isLoading = false);
                          }
                        }
                      },
                isDarkMode,
              ),
            ),
          ],
        );
      } else if (status == 'arrived_dropoff') {
        if (job.completionCode != null && job.completionCode!.isNotEmpty) {
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Completion Code Generated',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    MockQrCode(data: job.completionCode!),
                    const SizedBox(height: 16),
                    Text(
                      job.completionCode!,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        color: isDarkMode
                            ? AppColors.darkText
                            : AppColors.lightText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Share this code with the Employer to verify and complete delivery.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              UIHelpers.buildPrimaryButton(
                "Cancel Job",
                () => _handleCancelJob(job),
                isDarkMode,
                isOutlined: true,
              ),
            ],
          );
        }
        return Column(
          children: [
            UIHelpers.buildPrimaryButton(
              _isLoading ? "Generating..." : "Generate Completion QR / Code",
              _isLoading
                  ? null
                  : () async {
                      setState(() => _isLoading = true);
                      try {
                        final code =
                            (100000 +
                                    (DateTime.now().millisecondsSinceEpoch %
                                        900000))
                                .toString();
                        await ref
                            .read(jobRepositoryProvider)
                            .updateJobStatus(
                              job.id,
                              'arrived_dropoff',
                              additionalFields: {'completionCode': code},
                            );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Completion code generated!'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error generating code: $e'),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isLoading = false);
                        }
                      }
                    },
              isDarkMode,
            ),
            const SizedBox(height: 12),
            UIHelpers.buildPrimaryButton(
              "Cancel Job",
              () => _handleCancelJob(job),
              isDarkMode,
              isOutlined: true,
            ),
          ],
        );
      } else if (status.toLowerCase() == 'done') {
        return UIHelpers.buildPrimaryButton(
          "Enter Payment Code",
          () => _showEnterCodeDialog(context: context, job: job),
          isDarkMode,
        );
      } else if (status.toLowerCase() == 'completed') {
        if (!job.nyxianRated) {
          return UIHelpers.buildPrimaryButton(
            "Rate Employer",
            () => _showRatingDialog(
              context: context,
              job: job,
              targetId: job.creatorId,
              targetName: job.creatorName,
              currentViewMode: currentViewMode,
            ),
            isDarkMode,
          );
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: AppColors.green),
              SizedBox(width: 8),
              Text(
                'Job Completed & Rated',
                style: TextStyle(
                  color: AppColors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }
    }

    return Row(
      children: [
        if (currentViewMode == AccountType.nyxian &&
            job.creatorType == AccountType.employer)
          Expanded(
            child: hasApplied
                ? UIHelpers.buildPrimaryButton(
                    "Already applied",
                    null,
                    isDarkMode,
                    isOutlined: true,
                  )
                : UIHelpers.buildPrimaryButton("Proceed to application", () {
                    ref.read(isCounterOfferProvider.notifier).state = false;
                    ref.read(jobsViewProvider.notifier).state = 'apply';
                  }, isDarkMode),
          ),
        if (currentViewMode == AccountType.employer &&
            job.creatorType == AccountType.nyxian)
          Expanded(
            child: hasApplied
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
          Icon(icon, size: 20, color: effectiveColor),
          const SizedBox(width: 5),
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: effectiveColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryTrackerTimeline(Job job, bool isDarkMode) {
    final List<(String, String)> steps = [
      ('heading_to_pickup', 'Heading to Pickup'),
      ('arrived_pickup', 'Arrived at Pickup'),
      ('paid_cashier', 'Items Secured / Paid'),
      ('in_transit', 'In Transit to Destination'),
      ('arrived_dropoff', 'Arrived at Destination'),
    ];

    final String status = job.status.toLowerCase();
    int currentStepIndex = -1;
    for (int i = 0; i < steps.length; i++) {
      if (status == steps[i].$1) {
        currentStepIndex = i;
        break;
      }
    }
    if (status == 'completed') {
      currentStepIndex = steps.length - 1;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode
            ? AppColors.darkCard.withValues(alpha: 0.5)
            : AppColors.lightBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                color: AppColors.indigo,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                "Delivery Tracker",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children: List.generate(steps.length, (index) {
              final stepLabel = steps[index].$2;
              final isCompleted =
                  index < currentStepIndex || status == 'completed';
              final isCurrent =
                  index == currentStepIndex && status != 'completed';

              final stepColor = isCompleted
                  ? AppColors.green
                  : (isCurrent ? AppColors.indigo : Colors.grey[400]);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: stepColor!.withValues(alpha: 0.1),
                          border: Border.all(color: stepColor, width: 2),
                        ),
                        child: Center(
                          child: isCompleted
                              ? const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: AppColors.green,
                                )
                              : Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isCurrent
                                        ? AppColors.indigo
                                        : Colors.transparent,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        stepLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: (isCurrent || isCompleted)
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isCurrent
                              ? (isDarkMode
                                    ? AppColors.darkText
                                    : AppColors.lightText)
                              : (isCompleted
                                    ? (isDarkMode
                                          ? AppColors.darkText
                                          : AppColors.lightText)
                                    : (isDarkMode
                                          ? AppColors.darkTextMuted
                                          : AppColors.lightTextMuted)),
                        ),
                      ),
                    ],
                  ),
                  if (index < steps.length - 1)
                    Container(
                      margin: const EdgeInsets.only(left: 11),
                      width: 2,
                      height: 16,
                      color: isCompleted
                          ? AppColors.green.withValues(alpha: 0.5)
                          : (isDarkMode
                                ? AppColors.darkBorder
                                : AppColors.lightBorder),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class MockQrCode extends StatelessWidget {
  final String data;
  final double size;
  final Color color;

  const MockQrCode({
    super.key,
    required this.data,
    this.size = 180,
    this.color = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: CustomPaint(
          painter: QrCustomPainter(data: data, color: color),
        ),
      ),
    );
  }
}

class QrCustomPainter extends CustomPainter {
  final String data;
  final Color color;

  QrCustomPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw finder patterns (3 corner squares)
    _drawFinderPattern(canvas, const Offset(0, 0), size.width * 0.25, paint);
    _drawFinderPattern(
      canvas,
      Offset(size.width * 0.75, 0),
      size.width * 0.25,
      paint,
    );
    _drawFinderPattern(
      canvas,
      Offset(0, size.height * 0.75),
      size.width * 0.25,
      paint,
    );

    // Draw mock tiny data blocks
    final int rows = 18;
    final double blockW = size.width / rows;
    final double blockH = size.height / rows;

    // A deterministic random generator based on the data string hash
    final seed = data.hashCode;
    final random = math.Random(seed);

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < rows; c++) {
        // Skip finder pattern zones
        if (r < 6 && c < 6) continue;
        if (r < 6 && c >= rows - 6) continue;
        if (r >= rows - 6 && c < 6) continue;

        // Skip some spaces to look like a real QR code (about 50% density)
        if (random.nextBool()) {
          canvas.drawRect(
            Rect.fromLTWH(
              c * blockW + 1,
              r * blockH + 1,
              blockW - 2,
              blockH - 2,
            ),
            paint,
          );
        }
      }
    }
  }

  void _drawFinderPattern(
    Canvas canvas,
    Offset offset,
    double size,
    Paint paint,
  ) {
    // Outer square
    canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy, size, size), paint);
    // Inner white space
    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final double innerOffset = size * 0.15;
    final double innerSize = size * 0.7;
    canvas.drawRect(
      Rect.fromLTWH(
        offset.dx + innerOffset,
        offset.dy + innerOffset,
        innerSize,
        innerSize,
      ),
      whitePaint,
    );
    // Center solid square
    final double centerOffset = size * 0.3;
    final double centerSize = size * 0.4;
    canvas.drawRect(
      Rect.fromLTWH(
        offset.dx + centerOffset,
        offset.dy + centerOffset,
        centerSize,
        centerSize,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
