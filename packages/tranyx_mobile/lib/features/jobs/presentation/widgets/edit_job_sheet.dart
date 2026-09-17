import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/utils/enums.dart';
import 'package:tranyx_mobile/core/utils/num_extension.dart';
import 'package:tranyx_mobile/features/jobs/providers/job_repository.dart';
import 'package:tranyx_mobile/features/jobs/providers/jobs_provider.dart';

class EditJobSheet extends ConsumerStatefulWidget {
  final Job job;

  const EditJobSheet({super.key, required this.job});

  @override
  ConsumerState<EditJobSheet> createState() => _EditJobSheetState();
}

class _EditJobSheetState extends ConsumerState<EditJobSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _addressController;
  late TextEditingController _landmarkController;
  late TextEditingController _pickupAddressController;
  late TextEditingController _destAddressController;

  late JobCategory _selectedCategory;
  late JobCategoryGroup _selectedCategoryGroup;
  late String _dateRequirement;
  DateTime? _jobDate;
  late String _timePreference;
  late String _locationType;
  late List<String> _imageUrls;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final j = widget.job;
    _titleController = TextEditingController(text: j.title);
    _descController = TextEditingController(text: j.description);
    _addressController = TextEditingController(text: j.address ?? '');
    _landmarkController = TextEditingController(text: j.landmark ?? '');
    _pickupAddressController = TextEditingController(text: j.pickupAddress ?? '');
    _destAddressController = TextEditingController(text: j.destinationAddress ?? '');

    _selectedCategory = j.category;
    _selectedCategoryGroup = j.categoryGroup;
    _dateRequirement = j.dateRequirement.isNotEmpty ? j.dateRequirement : 'Flexible';
    _jobDate = j.jobDate;
    _timePreference = j.timePreference.isNotEmpty ? j.timePreference : 'Morning';
    _locationType = j.locationType.isNotEmpty ? j.locationType : 'On-site';
    _imageUrls = List<String>.from(j.imageUrls);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _addressController.dispose();
    _landmarkController.dispose();
    _pickupAddressController.dispose();
    _destAddressController.dispose();
    super.dispose();
  }

  Future<void> _selectJobDate(BuildContext context, bool isDarkMode) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _jobDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: isDarkMode
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppColors.indigo,
                    onPrimary: Colors.white,
                    surface: AppColors.darkCard,
                    onSurface: AppColors.darkText,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AppColors.indigo,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: AppColors.lightText,
                  ),
                ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _jobDate = picked;
      });
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    if (_locationType == 'On-site' && _addressController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please provide an address for on-site jobs.';
      });
      return;
    }

    if (_dateRequirement != 'Flexible' && _jobDate == null) {
      setState(() {
        _errorMessage = 'Please select a target date.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final nowEpoch = DateTime.now().millisecondsSinceEpoch;
      final updates = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'category': _selectedCategory.name,
        'categoryGroup': _selectedCategoryGroup.name,
        'dateRequirement': _dateRequirement,
        'timePreference': _timePreference,
        'locationType': _locationType,
        'address': _addressController.text.trim(),
        'landmark': _landmarkController.text.trim(),
        if (_jobDate != null) 'jobDate': _jobDate!.millisecondsSinceEpoch,
        if (_pickupAddressController.text.trim().isNotEmpty)
          'pickupAddress': _pickupAddressController.text.trim(),
        if (_destAddressController.text.trim().isNotEmpty)
          'destinationAddress': _destAddressController.text.trim(),
        'imageUrls': _imageUrls,
        'updatedAt': nowEpoch,
      };

      await ref.read(jobRepositoryProvider).updateJobDetails(widget.job.id, updates);

      // Update the active selected job in Riverpod
      final updatedJob = widget.job.copyWith(
        title: updates['title'] as String,
        description: updates['description'] as String,
        category: _selectedCategory,
        categoryGroup: _selectedCategoryGroup,
        dateRequirement: updates['dateRequirement'] as String,
        timePreference: updates['timePreference'] as String,
        locationType: updates['locationType'] as String,
        address: updates['address'] as String,
        landmark: updates['landmark'] as String,
        jobDate: _jobDate,
        pickupAddress: updates['pickupAddress'] as String?,
        destinationAddress: updates['destinationAddress'] as String?,
        imageUrls: _imageUrls,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(nowEpoch),
      );

      ref.read(selectedJobProvider.notifier).state = updatedJob;

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job posting updated successfully.'),
            backgroundColor: AppColors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkBg : AppColors.lightBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.indigo.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    LucideIcons.pencil,
                    color: AppColors.indigo,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit Job Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      Text(
                        'Update scope before a Nyxian is accepted',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  color: isDarkMode
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Scrollable Form Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              physics: const BouncingScrollPhysics(),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Error message if any
                    if (_errorMessage != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: AppColors.red,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: AppColors.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Pre-hire Applicant Notice
                    if (widget.job.applicantCount > 0) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.amber.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: AppColors.amber,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'This job has ${widget.job.applicantCount} active applicant(s). Changes will be marked with an "Edited" badge so applicants stay informed of scope updates.',
                                style: TextStyle(
                                  color: isDarkMode
                                      ? AppColors.amber
                                      : const Color(0xFFB45309),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Section 1: Title & Description
                    _buildSectionHeader('Basic Information', LucideIcons.fileText, isDarkMode),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _titleController,
                      style: TextStyle(
                        color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Job Title',
                        hintText: 'e.g. Need Plumber for Kitchen Leak',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Title is required' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _descController,
                      maxLines: 4,
                      style: TextStyle(
                        color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Job Description',
                        hintText: 'Describe details, requirements, tools needed...',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Description is required' : null,
                    ),

                    const SizedBox(height: 20),

                    // Section 2: Category & Group
                    _buildSectionHeader('Category', LucideIcons.layers, isDarkMode),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<JobCategoryGroup>(
                      initialValue: _selectedCategoryGroup,
                      decoration: InputDecoration(
                        labelText: 'Category Group',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      dropdownColor: isDarkMode
                          ? AppColors.darkCard
                          : AppColors.lightCard,
                      items: JobCategoryGroup.values.map((group) {
                        return DropdownMenuItem(
                          value: group,
                          child: Text(
                            group.label,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDarkMode
                                  ? AppColors.darkText
                                  : AppColors.lightText,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (newGroup) {
                        if (newGroup == null) return;
                        setState(() {
                          _selectedCategoryGroup = newGroup;
                          final list = JobCategoryGroupExtension
                                  .categoryMap[newGroup] ??
                              [];
                          _selectedCategory = list.isNotEmpty
                              ? list.first
                              : JobCategory.others;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<JobCategory>(
                      initialValue: _selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Specific Category',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      dropdownColor: isDarkMode
                          ? AppColors.darkCard
                          : AppColors.lightCard,
                      items: (JobCategoryGroupExtension
                                  .categoryMap[_selectedCategoryGroup] ??
                              [])
                          .map((cat) {
                        return DropdownMenuItem(
                          value: cat,
                          child: Text(
                            cat.label,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDarkMode
                                  ? AppColors.darkText
                                  : AppColors.lightText,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (newCat) {
                        if (newCat == null) return;
                        setState(() {
                          _selectedCategory = newCat;
                        });
                      },
                    ),

                    const SizedBox(height: 20),

                    // Section 3: Schedule
                    _buildSectionHeader('Schedule & Timing', LucideIcons.calendar, isDarkMode),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _dateRequirement,
                            decoration: InputDecoration(
                              labelText: 'Requirement',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            dropdownColor: isDarkMode
                                ? AppColors.darkCard
                                : AppColors.lightCard,
                            items: const [
                              DropdownMenuItem(value: 'Flexible', child: Text('Flexible')),
                              DropdownMenuItem(value: 'On Date', child: Text('On Date')),
                              DropdownMenuItem(value: 'Before', child: Text('Before Date')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _dateRequirement = v);
                              }
                            },
                          ),
                        ),
                        if (_dateRequirement != 'Flexible') ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () => _selectJobDate(context, isDarkMode),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isDarkMode
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _jobDate != null
                                          ? DateFormat('MMM d, yyyy')
                                              .format(_jobDate!)
                                          : 'Select Date',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDarkMode
                                            ? AppColors.darkText
                                            : AppColors.lightText,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.calendar_month_outlined,
                                      size: 18,
                                      color: AppColors.indigo,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _timePreference,
                      decoration: InputDecoration(
                        labelText: 'Time Preference',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      dropdownColor: isDarkMode
                          ? AppColors.darkCard
                          : AppColors.lightCard,
                      items: const [
                        DropdownMenuItem(
                          value: 'Morning',
                          child: Text('Morning (8 AM - 12 PM)'),
                        ),
                        DropdownMenuItem(
                          value: 'Midday',
                          child: Text('Midday (12 PM - 2 PM)'),
                        ),
                        DropdownMenuItem(
                          value: 'Afternoon',
                          child: Text('Afternoon (2 PM - 6 PM)'),
                        ),
                        DropdownMenuItem(
                          value: 'Evening',
                          child: Text('Evening (6 PM onwards)'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _timePreference = v);
                        }
                      },
                    ),

                    const SizedBox(height: 20),

                    // Section 4: Location & Landmark
                    _buildSectionHeader('Location & Landmarks', LucideIcons.mapPin, isDarkMode),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _locationType,
                      decoration: InputDecoration(
                        labelText: 'Location Type',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      dropdownColor: isDarkMode
                          ? AppColors.darkCard
                          : AppColors.lightCard,
                      items: const [
                        DropdownMenuItem(value: 'On-site', child: Text('On-site')),
                        DropdownMenuItem(value: 'Remote', child: Text('Remote')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _locationType = v);
                        }
                      },
                    ),
                    if (_locationType == 'On-site') ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _addressController,
                        style: TextStyle(
                          color: isDarkMode
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Address',
                          hintText: 'Street, Barangay, City',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _landmarkController,
                        style: TextStyle(
                          color: isDarkMode
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Landmark / Instructions',
                          hintText: 'e.g. Near Shell station, Gate 2',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Section 5: Escrow / Budget Locked Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? AppColors.darkCard
                            : AppColors.lightCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDarkMode
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            color: AppColors.indigo,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Budget & Escrow Locked',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: isDarkMode
                                            ? AppColors.darkText
                                            : AppColors.lightText,
                                      ),
                                    ),
                                    Text(
                                      '₱${widget.job.pricingValue.toAmount(length: 0)}',
                                      style: const TextStyle(
                                        fontFamily: 'Bebas',
                                        fontSize: 18,
                                        color: AppColors.indigo,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Pre-hire pricing terms are committed to escrow to protect applicants. To change the budget, please cancel and repost the gig.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDarkMode
                                        ? AppColors.darkTextMuted
                                        : AppColors.lightTextMuted,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Submit buttons
                    Row(
                      children: [
                        Expanded(
                          child: UIHelpers.buildPrimaryButton(
                            'Cancel',
                            () => Navigator.pop(context),
                            isDarkMode,
                            isOutlined: true,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: UIHelpers.buildPrimaryButton(
                            _isSaving ? 'Saving...' : 'Save Changes',
                            _isSaving ? () {} : _saveChanges,
                            isDarkMode,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, bool isDarkMode) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.indigo),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isDarkMode ? AppColors.darkText : AppColors.lightText,
          ),
        ),
      ],
    );
  }
}
