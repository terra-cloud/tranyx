import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/providers/ai_provider.dart';
import 'package:tranyx_mobile/core/utils/num_extension.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/jobs/providers/job_repository.dart';
import 'package:tranyx_mobile/features/jobs/providers/jobs_provider.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/features/jobs/presentation/widgets/job_sub_header.dart';

class ApplyJobView extends ConsumerStatefulWidget {
  const ApplyJobView({super.key});

  @override
  ConsumerState<ApplyJobView> createState() => _ApplyJobViewState();
}

class _ApplyJobViewState extends ConsumerState<ApplyJobView> {
  final TextEditingController _coverController = TextEditingController();
  final TextEditingController _counterOfferController = TextEditingController();
  bool _isSubmitting = false;
  String? _counterOfferError;

  void _validateCounterOffer(double originalPrice, String value) {
    if (value.trim().isEmpty) {
      setState(() => _counterOfferError = null);
      return;
    }
    final res = JobCounterOfferValidator.validate(
      originalOffer: originalPrice,
      counterOfferInput: value,
      isCounterOffer: true,
    );
    setState(() {
      _counterOfferError = res.isValid ? null : res.errorMessage;
    });
  }

  @override
  void initState() {
    super.initState();
    _coverController.text = ref.read(coverNoteProvider);
  }

  @override
  void dispose() {
    _coverController.dispose();
    _counterOfferController.dispose();
    super.dispose();
  }

  Widget _buildRadioOption(
    String title,
    String trailing,
    bool isSelected,
    VoidCallback onTap,
    bool isDarkMode,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.indigo.withValues(alpha: 0.1)
              : (isDarkMode ? AppColors.darkCard : AppColors.lightCard),
          border: Border.all(
            color: isSelected
                ? AppColors.indigo
                : (isDarkMode ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected
                  ? AppColors.indigo
                  : (isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
              ),
            ),
            if (trailing.isNotEmpty)
              Text(
                trailing,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.indigo,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final selectedJob = ref.watch(selectedJobProvider);
    final isCounterOffer = ref.watch(isCounterOfferProvider);
    final isGeneratingCover = ref.watch(isGeneratingCoverProvider);

    if (selectedJob == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobSubHeader(
            title: "Submit Application",
            onBack: () => ref.read(jobsViewProvider.notifier).state = 'details',
            isDarkMode: isDarkMode,
          ),
          Text(
            "Proposal Rate",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          const SizedBox(height: 16),
          _buildRadioOption(
            "Standard Rate",
            selectedJob.pricingValue.toAmount(length: 0),
            !isCounterOffer,
            () {
              ref.read(isCounterOfferProvider.notifier).state = false;
              setState(() => _counterOfferError = null);
            },
            isDarkMode,
          ),
          const SizedBox(height: 12),
          _buildRadioOption(
            "Make a Counter Offer",
            "",
            isCounterOffer,
            () {
              ref.read(isCounterOfferProvider.notifier).state = true;
              if (_counterOfferController.text.trim().isNotEmpty) {
                _validateCounterOffer(selectedJob.pricingValue, _counterOfferController.text);
              }
            },
            isDarkMode,
          ),
          if (isCounterOffer) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? AppColors.darkPrimary.withOpacity(0.12)
                    : AppColors.lightPrimary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode
                      ? AppColors.darkPrimary.withOpacity(0.25)
                      : AppColors.lightPrimary.withOpacity(0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: isDarkMode ? AppColors.darkPrimary : AppColors.lightPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      JobCounterOfferValidator.getPermittedRangeDisplay(selectedJob.pricingValue),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? AppColors.darkPrimary : AppColors.lightPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _counterOfferError != null
                      ? Colors.redAccent
                      : (isDarkMode ? AppColors.darkBorder : AppColors.lightBorder),
                ),
              ),
              child: TextField(
                controller: _counterOfferController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: TextStyle(
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                  fontSize: 16,
                ),
                onChanged: (val) => _validateCounterOffer(selectedJob.pricingValue, val),
                decoration: InputDecoration(
                  icon: Icon(
                    Icons.payments_outlined,
                    color: _counterOfferError != null
                        ? Colors.redAccent
                        : (isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                  ),
                  hintText: "0.00",
                  hintStyle: TextStyle(
                    color: isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
            if (_counterOfferError != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _counterOfferError!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Cover Note",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
              ),
              GestureDetector(
                onTap: () async {
                  if (isGeneratingCover) return;
                  ref.read(isGeneratingCoverProvider.notifier).state = true;
                  try {
                    final aiService = ref.read(aiServiceProvider);
                    final generatedCover = await aiService.generateCoverNote(
                      selectedJob.title,
                    );

                    ref.read(coverNoteProvider.notifier).state = generatedCover;
                    _coverController.text = generatedCover;
                  } catch (e) {
                    // Handle error
                  } finally {
                    ref.read(isGeneratingCoverProvider.notifier).state = false;
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.indigo.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      if (isGeneratingCover)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.indigo,
                          ),
                        )
                      else
                        const Icon(
                          Icons.auto_awesome,
                          size: 14,
                          color: AppColors.indigo,
                        ),
                      const SizedBox(width: 6),
                      Text(
                        isGeneratingCover ? "Drafting..." : "Draft for me",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.indigo,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
              border: Border.all(
                color: isDarkMode
                    ? AppColors.darkBorder
                    : AppColors.lightBorder,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _coverController,
              onChanged: (v) => ref.read(coverNoteProvider.notifier).state = v,
              maxLines: 4,
              style: TextStyle(
                color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: "Why are you a good fit?",
                hintStyle: TextStyle(
                  color: isDarkMode
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          Builder(
            builder: (context) {
              final hasOngoingNyxianJob = ref.watch(hasOngoingNyxianJobProvider);
              if (!hasOngoingNyxianJob) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.amber.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'You have an ongoing job to complete.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Please complete your current task before applying for another job to avoid conflicts in your responsibilities.',
                            style: TextStyle(
                              fontSize: 12,
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
              );
            },
          ),
          const SizedBox(height: 32),
          _isSubmitting
              ? const Center(child: CircularProgressIndicator())
              : ref.watch(hasOngoingNyxianJobProvider)
              ? UIHelpers.buildPrimaryButton(
                  "Ongoing Task Incomplete",
                  null,
                  isDarkMode,
                  isOutlined: true,
                )
              : UIHelpers.buildPrimaryButton("Submit Application", () async {
                  final hasOngoing = ref.read(hasOngoingNyxianJobProvider);
                  if (hasOngoing) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ongoingJobRestrictionMessage),
                          backgroundColor: AppColors.amber,
                        ),
                      );
                    }
                    return;
                  }

                  final userProfile = ref.read(userProfileProvider).value;
                  if (userProfile == null) return;

                  if (selectedJob.creatorId == userProfile.uid) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("You cannot apply to your own job posting."),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                    return;
                  double rate = selectedJob.pricingValue;
                  if (isCounterOffer) {
                    final validation = JobCounterOfferValidator.validate(
                      originalOffer: selectedJob.pricingValue,
                      counterOfferInput: _counterOfferController.text,
                      isCounterOffer: true,
                    );
                    if (!validation.isValid) {
                      setState(() {
                        _counterOfferError = validation.errorMessage;
                        _isSubmitting = false;
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(validation.errorMessage ?? 'Invalid counter offer.'),
                            backgroundColor: Colors.redAccent,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                      return;
                    }
                    rate = validation.sanitizedRate!;
                  }

                  setState(() => _isSubmitting = true);

                  final application = JobApplication(
                    id: '', // Will be stored under userUid
                    jobId: selectedJob.id,
                    applicantUid: userProfile.uid,
                    applicantName: userProfile.name,
                    applicantPhotoUrl: userProfile.photoUrl,
                    coverNote: _coverController.text.trim(),
                    proposalRate: rate,
                    isCounterOffer: isCounterOffer,
                    createdAt: DateTime.now(),
                  );

                  try {
                    await ref
                        .read(jobRepositoryProvider)
                        .applyToJob(application);

                    // Update selected job state locally for immediate reactivity
                    final currentJob = ref.read(selectedJobProvider);
                    if (currentJob != null) {
                      final updatedUids = List<String>.from(
                        currentJob.applicantUids,
                      );
                      if (!updatedUids.contains(application.applicantUid)) {
                        updatedUids.add(application.applicantUid);
                      }

                      final updatedPhotos = List<String>.from(
                        currentJob.recentApplicantPhotos,
                      );
                      final photo = application.applicantPhotoUrl ?? "";
                      // Mirror repository logic for recent photos
                      if (photo.isEmpty || !updatedPhotos.contains(photo)) {
                        updatedPhotos.insert(0, photo);
                        if (updatedPhotos.length > 5) {
                          updatedPhotos.removeLast();
                        }
                      }

                      ref.read(selectedJobProvider.notifier).state = currentJob
                          .copyWith(
                            applicantUids: updatedUids,
                            applicantCount: currentJob.applicantCount + 1,
                            recentApplicantPhotos: updatedPhotos,
                          );
                    }

                    ref.read(jobsViewProvider.notifier).state = 'success';
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Failed to apply: $e"),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _isSubmitting = false);
                    }
                  }
                }, isDarkMode),
        ],
      ),
    );
  }
}
