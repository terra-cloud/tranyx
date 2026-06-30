import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/providers/ai_provider.dart';
import 'package:tranyx_mobile/core/utils/enums.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/features/jobs/providers/job_repository.dart';
import 'package:tranyx_mobile/features/jobs/providers/jobs_provider.dart';

class CreateJobWizard extends ConsumerStatefulWidget {
  const CreateJobWizard({super.key});

  @override
  ConsumerState<CreateJobWizard> createState() => _CreateJobWizardState();
}

class _CreateJobWizardState extends ConsumerState<CreateJobWizard> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _addressController;
  late TextEditingController _landmarkController;
  late TextEditingController _pricingController;

  bool _showCategoryError = false;
  bool _showDateError = false;
  String? _validationErrorMessage;

  Widget _buildErrorWidget(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.red, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.red,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: ref.read(newJobTitleProvider),
    );
    _descController = TextEditingController(text: ref.read(newJobDescProvider));
    _addressController = TextEditingController(
      text: ref.read(jobAddressProvider),
    );
    _landmarkController = TextEditingController(
      text: ref.read(jobLandmarkProvider),
    );
    _pricingController = TextEditingController(
      text: ref.read(pricingValueProvider).toString(),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _addressController.dispose();
    _landmarkController.dispose();
    _pricingController.dispose();
    super.dispose();
  }

  void resetCreateJobState() {
    ref.read(newJobTitleProvider.notifier).state = '';
    ref.read(newJobDescProvider.notifier).state = '';
    ref.read(selectedCategoryProvider.notifier).state = null;
    ref.read(selectedCategoryGroupProvider.notifier).state = null;
    ref.read(categoryPickerStepProvider.notifier).state = 1;
    ref.read(employmentTypeProvider.notifier).state = 'One-time Gig';
    ref.read(dateRequirementProvider.notifier).state = 'Flexible';
    ref.read(jobDateProvider.notifier).state = null;
    ref.read(timePreferenceProvider.notifier).state = 'Morning';
    ref.read(pricingTypeProvider.notifier).state = 'Package (Fixed)';
    ref.read(pricingValueProvider.notifier).state = 0.0;
    ref.read(createJobStepProvider.notifier).state = 1;
    ref.read(workLocationTypeProvider.notifier).state = 'On-site';
    ref.read(jobLandmarkProvider.notifier).state = '';
    ref.read(jobAddressProvider.notifier).state = '';
    _titleController.clear();
    _descController.clear();
    _addressController.clear();
    _landmarkController.clear();
  }

  Widget _buildEmploymentAndSchedule(bool isDarkMode) {
    final employmentType = ref.watch(employmentTypeProvider);
    final jobDate = ref.watch(jobDateProvider);
    final dateReq = ref.watch(dateRequirementProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Employment Type",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDarkMode ? AppColors.darkText : AppColors.lightText,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.darkCard : Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: ['One-time Gig', 'Part-time', 'Contract'].map((type) {
              final isSelected = employmentType == type;
              return Expanded(
                child: GestureDetector(
                  onTap: () =>
                      ref.read(employmentTypeProvider.notifier).state = type,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDarkMode ? Colors.white10 : Colors.white)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isSelected && !isDarkMode
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      type,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? (isDarkMode ? Colors.white : AppColors.indigo)
                            : (isDarkMode
                                  ? AppColors.darkTextMuted
                                  : AppColors.lightTextMuted),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "Date Requirement",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDarkMode ? AppColors.darkText : AppColors.lightText,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.darkCard : Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: ['On Date', 'Before', 'Flexible'].map((type) {
              final isSelected = dateReq == type;
              return Expanded(
                child: GestureDetector(
                  onTap: () =>
                      ref.read(dateRequirementProvider.notifier).state = type,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDarkMode ? Colors.white10 : Colors.white)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isSelected && !isDarkMode
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      type,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? (isDarkMode ? Colors.white : AppColors.indigo)
                            : (isDarkMode
                                  ? AppColors.darkTextMuted
                                  : AppColors.lightTextMuted),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        if (dateReq != 'Flexible') ...[
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: jobDate ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                ref.read(jobDateProvider.notifier).state = picked;
              }
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDarkMode
                      ? AppColors.darkBorder
                      : AppColors.lightBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.calendar,
                    size: 18,
                    color: jobDate == null ? Colors.grey : AppColors.indigo,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    jobDate == null
                        ? "Select Date"
                        : DateFormat('MMM dd, yyyy').format(jobDate),
                    style: TextStyle(
                      color: jobDate == null
                          ? Colors.grey
                          : (isDarkMode
                                ? AppColors.darkText
                                : AppColors.lightText),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showDateError && jobDate == null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                "Please select a date",
                style: TextStyle(color: AppColors.red, fontSize: 12),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildPricingTypeButton(
    String type,
    String currentType,
    bool isDarkMode, {
    bool isFullWidth = false,
  }) {
    final isSelected = currentType == type;
    return GestureDetector(
      onTap: () => ref.read(pricingTypeProvider.notifier).state = type,
      child: Container(
        width: isFullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.indigo
              : (isDarkMode ? AppColors.darkBg : AppColors.lightBg),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.indigo
                : (isDarkMode ? AppColors.darkBorder : AppColors.lightBorder),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          type,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Colors.white
                : (isDarkMode ? AppColors.darkText : AppColors.lightText),
          ),
        ),
      ),
    );
  }

  Widget buildPricingSection(bool isDarkMode) {
    final pricingType = ref.watch(pricingTypeProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkCard : Colors.white,
        border: Border.all(
          color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.dollarSign, size: 18, color: AppColors.indigo),
              const SizedBox(width: 10),
              Text(
                "Budget & Pricing",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          GridView.count(
            padding: EdgeInsets.zero,
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
            childAspectRatio: 3.5,
            children: ['Daily', 'Weekly', 'Fortnightly', 'Monthly']
                .map(
                  (type) =>
                      _buildPricingTypeButton(type, pricingType, isDarkMode),
                )
                .toList(),
          ),
          const SizedBox(height: 5),
          _buildPricingTypeButton(
            'Package (Fixed)',
            pricingType,
            isDarkMode,
            isFullWidth: true,
          ),
          const SizedBox(height: 24),
          Text(
            "Total Budget",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDarkMode
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "₱",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _pricingController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) {
                    final val = double.tryParse(v) ?? 0.0;
                    ref.read(pricingValueProvider.notifier).state = val;
                  },
                  validator: (v) {
                    final val = double.tryParse(v ?? '') ?? 0.0;
                    if (val <= 0) return "Required";
                    return null;
                  },
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode
                        ? AppColors.darkText
                        : AppColors.lightText,
                  ),
                  decoration: InputDecoration(
                    hintText: "0.00",
                    hintStyle: TextStyle(
                      color:
                          (isDarkMode
                                  ? AppColors.darkTextMuted
                                  : AppColors.lightTextMuted)
                              .withValues(alpha: 0.3),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    errorStyle: TextStyle(color: AppColors.red, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final selectedCategoryGroup = ref.watch(selectedCategoryGroupProvider);
    final categoryStep = ref.watch(categoryPickerStepProvider);
    final isGeneratingDesc = ref.watch(isGeneratingDescProvider);
    final currentStep = ref.watch(createJobStepProvider);
    final workLocationType = ref.watch(workLocationTypeProvider);
    final jobAddress = ref.watch(jobAddressProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          _validationErrorMessage = null;
        });
        if (currentStep > 1) {
          ref.read(createJobStepProvider.notifier).state--;
        } else {
          ref.read(jobsViewProvider.notifier).state = 'list';
          resetCreateJobState();
        }
      },
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton.filled(
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(
                      (isDarkMode
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted)
                          .withValues(alpha: .25),
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _validationErrorMessage = null;
                    });
                    if (currentStep > 1) {
                      ref.read(createJobStepProvider.notifier).state--;
                    } else {
                      ref.read(jobsViewProvider.notifier).state = 'list';
                      resetCreateJobState();
                    }
                  },
                  icon: Icon(
                    LucideIcons.arrowLeft,
                    color: isDarkMode
                        ? AppColors.darkText
                        : AppColors.lightText,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  currentStep == 1
                      ? "Job Details"
                      : currentStep == 2
                      ? "Location"
                      : "Pricing & Review",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  "Step $currentStep of 3",
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_showCategoryError && selectedCategory == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  "Please select a category",
                  style: TextStyle(color: AppColors.red, fontSize: 12),
                ),
              ),
            if (currentStep == 1) ...[
              // Category Selector
              if (selectedCategory == null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Select Category",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? AppColors.darkText
                            : AppColors.lightText,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.9,
                          ),
                      itemCount: categoryStep == 1
                          ? JobCategoryGroup.values.length
                          : (JobCategoryGroupExtension
                                    .categoryMap[selectedCategoryGroup]
                                    ?.length ??
                                0),
                      itemBuilder: (context, index) {
                        if (categoryStep == 1) {
                          final group = JobCategoryGroup.values[index];
                          return GestureDetector(
                            onTap: () {
                              ref
                                      .read(
                                        selectedCategoryGroupProvider.notifier,
                                      )
                                      .state =
                                  group;
                              ref
                                      .read(categoryPickerStepProvider.notifier)
                                      .state =
                                  2;
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? AppColors.darkCard
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isDarkMode
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder,
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    group.iconData,
                                    color: group.colorValue,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    group.label,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode
                                          ? AppColors.darkText
                                          : AppColors.lightText,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        } else {
                          final categories =
                              JobCategoryGroupExtension
                                  .categoryMap[selectedCategoryGroup] ??
                              [];
                          final cat = categories[index];
                          return GestureDetector(
                            onTap: () {
                              ref
                                      .read(selectedCategoryProvider.notifier)
                                      .state =
                                  cat;
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? AppColors.darkCard
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isDarkMode
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder,
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    cat.iconData,
                                    color: AppColors.indigo,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    cat.label,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDarkMode
                                          ? AppColors.darkText
                                          : AppColors.lightText,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? const Color(0xFF121214)
                        : AppColors.indigo.withValues(alpha: 0.05),
                    border: Border.all(
                      color: AppColors.indigo.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selectedCategory.iconData,
                        color: AppColors.indigo,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedCategory.label,
                              style: TextStyle(
                                color: isDarkMode
                                    ? AppColors.darkText
                                    : AppColors.lightText,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              selectedCategoryGroup?.label ??
                                  "Professional Service",
                              style: TextStyle(
                                color: isDarkMode
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          ref.read(selectedCategoryProvider.notifier).state =
                              null;
                          ref.read(categoryPickerStepProvider.notifier).state =
                              1;
                          ref
                                  .read(selectedCategoryGroupProvider.notifier)
                                  .state =
                              null;
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.indigo,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text("Change"),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              // Job Title
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDarkMode ? AppColors.darkCard : Colors.white,
                  border: Border.all(
                    color: isDarkMode
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Job Title",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _titleController,
                      onChanged: (v) =>
                          ref.read(newJobTitleProvider.notifier).state = v,
                      validator: (v) => (v == null || v.isEmpty)
                          ? "Please enter a job title"
                          : null,
                      style: TextStyle(
                        color: isDarkMode
                            ? AppColors.darkText
                            : AppColors.lightText,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: "What needs to be done?",
                        hintStyle: TextStyle(
                          color: isDarkMode
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        errorStyle: TextStyle(
                          color: AppColors.red,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Job Description
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDarkMode ? AppColors.darkCard : Colors.white,
                  border: Border.all(
                    color: isDarkMode
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Description",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode
                                ? AppColors.darkTextMuted
                                : AppColors.lightTextMuted,
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            if (_titleController.text.isEmpty ||
                                isGeneratingDesc) {
                              return;
                            }
                            ref.read(isGeneratingDescProvider.notifier).state =
                                true;
                            try {
                              final aiService = ref.read(aiServiceProvider);
                              final desc = await aiService
                                  .generateJobDescription(
                                    _titleController.text,
                                  );
                              ref.read(newJobDescProvider.notifier).state =
                                  desc;
                              _descController.text = desc;
                            } finally {
                              ref
                                      .read(isGeneratingDescProvider.notifier)
                                      .state =
                                  false;
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.indigo.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                if (isGeneratingDesc)
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
                                    size: 12,
                                    color: AppColors.indigo,
                                  ),
                                const SizedBox(width: 4),
                                const Text(
                                  "Auto-Draft",
                                  style: TextStyle(
                                    fontSize: 11,
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
                    TextFormField(
                      controller: _descController,
                      onChanged: (v) =>
                          ref.read(newJobDescProvider.notifier).state = v,
                      validator: (v) => (v == null || v.isEmpty)
                          ? "Please enter a description"
                          : null,
                      maxLines: 4,
                      style: TextStyle(
                        color: isDarkMode
                            ? AppColors.darkText
                            : AppColors.lightText,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: "What are the requirements?",
                        hintStyle: TextStyle(
                          color: isDarkMode
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        errorStyle: TextStyle(
                          color: AppColors.red,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildEmploymentAndSchedule(isDarkMode),
              const SizedBox(height: 32),
              if (_validationErrorMessage != null && currentStep == 1) ...[
                _buildErrorWidget(_validationErrorMessage!),
                const SizedBox(height: 16),
              ],
              UIHelpers.buildPrimaryButton("Next Step: Location", () {
                setState(() {
                  _showCategoryError = selectedCategory == null;
                });

                final isFormValid = _formKey.currentState!.validate();
                final titleText = _titleController.text.trim();
                final descText = _descController.text.trim();
                final hasProfanity = checkProfanity(titleText) || checkProfanity(descText);

                if (isFormValid && selectedCategory != null && !hasProfanity) {
                  setState(() {
                    _validationErrorMessage = null;
                  });
                  ref.read(createJobStepProvider.notifier).state = 2;
                } else {
                  setState(() {
                    List<String> errors = [];
                    if (selectedCategory == null) errors.add("Select a category");
                    if (_titleController.text.isEmpty) errors.add("Job title is required");
                    if (_descController.text.isEmpty) errors.add("Description is required");
                    if (hasProfanity) {
                      errors.add("Your job title or description contains inappropriate language");
                    }
                    _validationErrorMessage = "Please correct the following:\n• " + errors.join("\n• ");
                  });
                }
              }, isDarkMode),

            ] else if (currentStep == 2) ...[
              // Work Location Type
              Text(
                "Work Location Type",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? const Color(0xFF121214)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDarkMode
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
                child: Row(
                  children: ['On-site', 'Remote'].map((type) {
                    final isSelected = workLocationType == type;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            ref.read(workLocationTypeProvider.notifier).state =
                                type,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isDarkMode
                                      ? const Color(0xFF2D2D30)
                                      : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: isSelected && !isDarkMode
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.05,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            type,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? (isDarkMode
                                        ? Colors.white
                                        : AppColors.indigo)
                                  : (isDarkMode
                                        ? AppColors.darkTextMuted
                                        : AppColors.lightTextMuted),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (workLocationType == 'On-site') ...[
                const SizedBox(height: 20),
                const Text(
                  "Where is the job located?",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "Select the service address for this project.",
                  style: TextStyle(
                    color: isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => _AddressSearchSheet(
                        isDarkMode: isDarkMode,
                        onAddressSelected: (address) {
                          ref.read(jobAddressProvider.notifier).state = address;
                          _addressController.text = address;
                        },
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDarkMode ? AppColors.darkBg : Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDarkMode
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.search,
                          size: 18,
                          color: AppColors.indigo,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            jobAddress.isEmpty
                                ? "Search for address..."
                                : jobAddress,
                            style: TextStyle(
                              fontSize: 14,
                              color: jobAddress.isEmpty
                                  ? Colors.grey
                                  : (isDarkMode
                                        ? AppColors.darkText
                                        : AppColors.lightText),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Icon(LucideIcons.mapPin, size: 18, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDarkMode ? AppColors.darkBg : Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDarkMode
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: TextField(
                    controller: _landmarkController,
                    onChanged: (v) =>
                        ref.read(jobLandmarkProvider.notifier).state = v,
                    style: TextStyle(
                      color: isDarkMode
                          ? AppColors.darkText
                          : AppColors.lightText,
                      fontSize: 14,
                    ),
                    decoration: const InputDecoration(
                      icon: Icon(
                        LucideIcons.building,
                        size: 18,
                        color: Colors.grey,
                      ),
                      hintText:
                          "e.g. Near the blue gate, opposite the bakery...",
                      hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ] else
                Container(
                  margin: const EdgeInsets.only(top: 24),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: isDarkMode ? AppColors.darkCard : AppColors.lightBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDarkMode
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        LucideIcons.globe,
                        size: 48,
                        color: AppColors.indigo.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "Remote Job",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "This job will be performed remotely. No physical address is required.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDarkMode
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 32),
              if (_validationErrorMessage != null && currentStep == 2) ...[
                _buildErrorWidget(_validationErrorMessage!),
                const SizedBox(height: 16),
              ],
              UIHelpers.buildPrimaryButton(
                "Next Step: Pricing",
                () {
                  final jobAddress = ref.read(jobAddressProvider);
                  if (workLocationType == 'On-site' && jobAddress.isEmpty) {
                    setState(() {
                      _validationErrorMessage = "Please select or search for an address";
                    });
                  } else {
                    setState(() {
                      _validationErrorMessage = null;
                    });
                    ref.read(createJobStepProvider.notifier).state = 3;
                  }
                },
                isDarkMode,
              ),
            ] else if (currentStep == 3) ...[
              buildPricingSection(isDarkMode),
              const SizedBox(height: 32),
              if (_validationErrorMessage != null && currentStep == 3) ...[
                _buildErrorWidget(_validationErrorMessage!),
                const SizedBox(height: 16),
              ],
              UIHelpers.buildPrimaryButton("Post Job Listing", () async {
                final jobDate = ref.read(jobDateProvider);
                final dateReq = ref.read(dateRequirementProvider);

                setState(() {
                  _showDateError = dateReq != 'Flexible' && jobDate == null;
                });

                final isFormValid = _formKey.currentState!.validate();
                if (isFormValid && !_showDateError) {
                  setState(() {
                    _validationErrorMessage = null;
                  });
                  final userProfile = ref.read(userProfileProvider).value;
                  final currentViewMode = ref.read(currentViewModeProvider);

                  if (userProfile == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("User profile not found. Please log in."),
                      ),
                    );
                    return;
                  }

                  final newJob = Job(
                    id: '', // Firestore will generate ID
                    creatorId: userProfile.uid,
                    creatorName: userProfile.name,
                    creatorPhotoUrl: userProfile.photoUrl,
                    creatorType: currentViewMode,
                    title: _titleController.text.trim(),
                    description: _descController.text.trim(),
                    category:
                        ref.read(selectedCategoryProvider) ??
                        JobCategory.others,
                    categoryGroup:
                        ref.read(selectedCategoryGroupProvider) ??
                        JobCategoryGroup.miscellaneousEvents,
                    employmentType: ref.read(employmentTypeProvider),
                    dateRequirement: dateReq,
                    jobDate: jobDate,
                    timePreference: ref.read(timePreferenceProvider),
                    pricingType: ref.read(pricingTypeProvider),
                    pricingValue: ref.read(pricingValueProvider),
                    locationType: ref.read(workLocationTypeProvider),
                    address: _addressController.text.trim(),
                    landmark: _landmarkController.text.trim(),
                    createdAt: DateTime.now(),
                  );
                  debugPrint(newJob.toMap().toString());

                  try {
                    await ref.read(jobRepositoryProvider).createJob(newJob);
                    resetCreateJobState();
                    ref.read(jobsViewProvider.notifier).state = 'list';
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Job posted successfully!"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Error posting job: $e"),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  setState(() {
                    List<String> errors = [];
                    if (!isFormValid) errors.add("Total budget must be greater than ₱0");
                    if (_showDateError) errors.add("Please select a job date");
                    _validationErrorMessage = "Please correct the following:\n• " + errors.join("\n• ");
                  });
                }
              }, isDarkMode),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
}
}

class _AddressSearchSheet extends StatefulWidget {
  final bool isDarkMode;
  final Function(String) onAddressSelected;

  const _AddressSearchSheet({
    required this.isDarkMode,
    required this.onAddressSelected,
  });

  @override
  State<_AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<_AddressSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _searchResults = [];
    });

    try {
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(trimmedQuery)}&limit=5'),
        headers: {'User-Agent': 'TranyxMobile/1.0 (contact@tranyx.com)'},
      );

      if (response.statusCode == 200) {
        final List decoded = jsonDecode(response.body);
        setState(() {
          _searchResults = decoded.map((item) => Map<String, dynamic>.from(item as Map)).toList();
          _isLoading = false;
          if (_searchResults.isEmpty) {
            _errorMessage = "No locations found. Try a different search.";
          }
        });
      } else {
        setState(() {
          _errorMessage = "Failed to load locations. Code: ${response.statusCode}";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Connection error. Please check your internet connection.";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: isDarkMode ? AppColors.darkCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            // Handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Search Address",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Search Input Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? AppColors.darkBorder.withValues(alpha: 0.5)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.search, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              textInputAction: TextInputAction.search,
                              onSubmitted: _performSearch,
                              onChanged: (val) {
                                setState(() {});
                              },
                              decoration: const InputDecoration(
                                hintText: "Enter street, city, or business...",
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 12),
                              ),
                              style: TextStyle(
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          if (_searchController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() {
                                  _searchResults = [];
                                  _errorMessage = null;
                                });
                              },
                              child: const Icon(LucideIcons.x, size: 18),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.indigo,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onPressed: _isLoading
                        ? null
                        : () => _performSearch(_searchController.text),
                    child: const Text(
                      "Search",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Loading indicator or results
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.indigo),
                  ),
                ),
              )
            else if (_errorMessage != null)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.amber),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  itemCount: _searchResults.length,
                  separatorBuilder: (context, index) => Divider(
                    color: isDarkMode ? AppColors.darkBorder : Colors.grey[200],
                    height: 1,
                  ),
                  itemBuilder: (context, index) {
                    final res = _searchResults[index];
                    final displayName = res['display_name'] as String? ?? '';
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      leading: const Icon(LucideIcons.mapPin, color: AppColors.indigo),
                      title: Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      onTap: () {
                        widget.onAddressSelected(displayName);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
