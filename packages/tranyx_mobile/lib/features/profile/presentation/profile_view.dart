import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/jobs/providers/job_repository.dart';
import 'package:tranyx_mobile/features/profile/providers/profile_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tranyx_mobile/core/utils/image_utils.dart';
import 'package:tranyx_mobile/core/providers/image_upload_provider.dart';
import 'package:tranyx_mobile/features/profile/presentation/nyx_chat_view.dart';
import 'package:tranyx_mobile/features/profile/presentation/widgets/payment_pane.dart';
import 'package:tranyx_mobile/features/profile/presentation/widgets/trust_pane.dart';
import 'package:tranyx_mobile/features/profile/presentation/widgets/history_pane.dart';
import 'package:tranyx_mobile/features/profile/presentation/widgets/reviews_pane.dart';
import 'package:tranyx_mobile/features/profile/presentation/widgets/security_pane.dart';
import 'package:tranyx_mobile/features/profile/presentation/widgets/rewards_pane.dart';
import 'package:tranyx_mobile/features/profile/presentation/widgets/subscription_pane.dart';
import 'package:tranyx_mobile/core/widgets/user_avatar.dart';

class ProfileView extends ConsumerStatefulWidget {
  final bool isTablet;

  const ProfileView({super.key, required this.isTablet});

  @override
  ConsumerState<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<ProfileView> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;

  late TextEditingController _headlineController;
  late TextEditingController _hourlyRateController;

  late TextEditingController _companyNameController;
  late TextEditingController _industryController;
  late TextEditingController _taxIdController;

  bool _initialized = false;
  bool _isSaving = false;
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _headlineController = TextEditingController();
    _hourlyRateController = TextEditingController();
    _companyNameController = TextEditingController();
    _industryController = TextEditingController();
    _taxIdController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _headlineController.dispose();
    _hourlyRateController.dispose();
    _companyNameController.dispose();
    _industryController.dispose();
    _taxIdController.dispose();
    super.dispose();
  }

  Future<void> _showImageSourceSheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Select Image Source',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSourceOption(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(context);
                    _processAndUploadImage(ImageSource.camera);
                  },
                ),
                _buildSourceOption(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: () {
                    Navigator.pop(context);
                    _processAndUploadImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? AppColors.indigo.withValues(alpha: 0.2)
                  : AppColors.indigo.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.indigo, size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDarkMode ? AppColors.darkText : AppColors.lightText,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processAndUploadImage(ImageSource source) async {
    try {
      final processedFile = await ImageUtils.pickAndProcessImage(
        context: context,
        source: source,
      );

      if (processedFile == null) return;

      setState(() => _isUploadingImage = true);

      final uploadService = ref.read(imgBBServiceProvider);
      final photoUrl = await uploadService.uploadImage(processedFile);

      if (photoUrl != null && mounted) {
        final profile = ref.read(userProfileProvider).value;
        if (profile != null) {
          final updatedProfile = UserProfile(
            uid: profile.uid,
            name: profile.name,
            email: profile.email,
            phoneNumber: profile.phoneNumber,
            photoUrl: photoUrl,
            accountType: profile.accountType,
            employerType: profile.employerType,
            businessName: profile.businessName,
            industry: profile.industry,
            taxId: profile.taxId,
            headline: profile.headline,
            hourlyRate: profile.hourlyRate,
            skills: profile.skills,
            rating: profile.rating,
            createdAt: profile.createdAt,
          );
          await ref.read(authControllerProvider).updateProfile(updatedProfile);

          // Update denormalized locations (creator photo in jobs, applicant photo in applications)
          await ref
              .read(jobRepositoryProvider)
              .updateUserPhotoInDenormalizedLocations(
                profile.uid,
                photoUrl,
                oldPhotoUrl: profile.photoUrl,
              );

          // Refresh user profile to reflect change immediately in UI
          ref.invalidate(userProfileProvider);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile photo updated successfully!'),
              ),
            );
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to upload image. Please try again.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        debugPrint(e.toString());
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  void _initFields(UserProfile profile) {
    if (_initialized) return;
    _nameController.text = profile.name;
    _emailController.text = profile.email;
    _phoneController.text = profile.phoneNumber ?? '';

    if (profile.accountType == AccountType.nyxian) {
      _headlineController.text = profile.headline ?? '';
      _hourlyRateController.text = profile.hourlyRate?.toString() ?? '';
    } else if (profile.accountType == AccountType.employer) {
      _companyNameController.text = profile.businessName ?? '';
      _industryController.text = profile.industry ?? '';
      _taxIdController.text = profile.taxId ?? '';
    } else if (profile.accountType == AccountType.hybrid) {
      _headlineController.text = profile.headline ?? '';
      _hourlyRateController.text = profile.hourlyRate?.toString() ?? '';
      _companyNameController.text = profile.businessName ?? '';
      _industryController.text = profile.industry ?? '';
      _taxIdController.text = profile.taxId ?? '';
    }
    _initialized = true;
  }

  void _saveProfile(UserProfile currentProfile) async {
    setState(() {
      _isSaving = true;
    });

    try {
      final updatedProfile = UserProfile(
        uid: currentProfile.uid,
        name: _nameController.text,
        email: _emailController.text,
        phoneNumber: _phoneController.text,
        photoUrl: currentProfile.photoUrl,
        accountType: currentProfile.accountType,
        employerType: currentProfile.employerType,
        businessName: currentProfile.accountType == AccountType.nyxian
            ? currentProfile.businessName
            : _companyNameController.text,
        industry: currentProfile.accountType == AccountType.nyxian
            ? currentProfile.industry
            : _industryController.text,
        taxId: currentProfile.accountType == AccountType.nyxian
            ? currentProfile.taxId
            : _taxIdController.text,
        headline: currentProfile.accountType == AccountType.employer
            ? currentProfile.headline
            : _headlineController.text,
        hourlyRate: currentProfile.accountType == AccountType.employer
            ? currentProfile.hourlyRate
            : (double.tryParse(_hourlyRateController.text) ?? 0),
        skills: currentProfile.skills,
        rating: currentProfile.rating,
        createdAt: currentProfile.createdAt,
      );

      await ref.read(authControllerProvider).updateProfile(updatedProfile);
      ref.invalidate(userProfileProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update profile: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final userProfileAsync = ref.watch(userProfileProvider);
    final profile = userProfileAsync.value;
    final AccountType accountType =
        profile?.accountType ?? ref.watch(accountTypeProvider);
    final profileView = ref.watch(profileViewProvider);
    final user = ref.watch(userProvider);

    return userProfileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text("Error: $err")),
      data: (profile) {
        if (profile != null) {
          _initFields(profile);
        }

        final displayName =
            profile?.name ?? user?.displayName ?? user?.email ?? "Alex Mercer";
        final AccountType currentAccountType =
            profile?.accountType ?? accountType;

        Widget buildTestBtn(
          String label,
          bool isActive,
          Color color,
          VoidCallback onTap,
        ) {
          return GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? color
                    : (isDarkMode ? AppColors.darkBg : Colors.white),
                border: isActive
                    ? null
                    : Border.all(
                        color: isDarkMode
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? Colors.white
                      : (isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightText),
                ),
              ),
            ),
          );
        }

        Widget buildProfileMenu(
          IconData icon,
          String label,
          String viewKey, {
          bool isDestructive = false,
        }) {
          Color itemColor = isDestructive
              ? AppColors.red
              : (isDarkMode ? AppColors.darkText : AppColors.lightText);
          Color iconBg = isDarkMode ? AppColors.darkBorder : AppColors.lightBg;
          bool isActive = profileView == viewKey;

          return GestureDetector(
            onTap: () {
              if (isDestructive && viewKey == 'logout') {
                ref.read(authControllerProvider).signOut();
                ref.read(authViewProvider.notifier).state = 'login';
                ref.read(profileViewProvider.notifier).state = 'main';
              } else {
                ref.read(profileViewProvider.notifier).state = viewKey;
              }
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isActive
                    ? (isDarkMode ? AppColors.darkBorder : AppColors.lightBg)
                    : (isDarkMode ? AppColors.darkCard : AppColors.lightCard),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isActive
                      ? AppColors.indigo
                      : (isDarkMode
                            ? AppColors.darkBorder
                            : AppColors.lightBorder),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: isDestructive
                          ? AppColors.red
                          : (isDarkMode
                                ? AppColors.darkTextMuted
                                : AppColors.lightTextMuted),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: itemColor,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: isDarkMode
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ],
              ),
            ),
          );
        }

        Widget buildSubHeader(String title, VoidCallback onBack) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: isDarkMode
                        ? AppColors.darkText
                        : AppColors.lightText,
                  ),
                  onPressed: onBack,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode
                        ? AppColors.darkText
                        : AppColors.lightText,
                  ),
                ),
              ],
            ),
          );
        }

        Widget menuPane = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Account",
              style: TextStyle(
                fontSize: widget.isTablet ? 24 : 28,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? AppColors.darkText : AppColors.lightText,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.indigo, AppColors.purple],
                    ),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(3),
                  child: GestureDetector(
                    onTap: _isUploadingImage ? null : _showImageSourceSheet,
                    child: Stack(
                      children: [
                        UserAvatar(
                          name: displayName,
                          photoUrl: profile?.photoUrl,
                          radius: 32,
                          backgroundColor: AppColors.indigo,
                        ),
                        if (_isUploadingImage)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )
                        else
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: AppColors.indigo,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? AppColors.darkText
                            : AppColors.lightText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (currentAccountType == AccountType.hybrid
                                    ? AppColors.amber
                                    : (currentAccountType ==
                                              AccountType.employer
                                          ? AppColors.blue
                                          : AppColors.green))
                                .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "${currentAccountType.label} ACCOUNT".toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: currentAccountType == AccountType.hybrid
                              ? AppColors.amber
                              : (currentAccountType == AccountType.employer
                                    ? AppColors.blue
                                    : AppColors.green),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),
            buildProfileMenu(
              Icons.person_outline,
              "Personal Information",
              'personal',
            ),
            const SizedBox(height: 12),
            buildProfileMenu(
              Icons.work_outline,
              currentAccountType == AccountType.nyxian
                  ? "Nyxian Profile"
                  : "Professional Info",
              'professional',
            ),
            const SizedBox(height: 12),
            buildProfileMenu(Icons.credit_card, "Payment Methods", 'payment'),
            const SizedBox(height: 12),
            buildProfileMenu(Icons.star_rounded, "Hybrid PRO Subscription", 'subscription'),
            const SizedBox(height: 12),
            buildProfileMenu(Icons.security, "Trust & Verification", 'trust'),
            const SizedBox(height: 12),
            buildProfileMenu(Icons.history, "History & Earnings", 'history'),
            const SizedBox(height: 12),
            buildProfileMenu(
              Icons.star_outline,
              "Ratings & Reviews",
              'reviews',
            ),
            const SizedBox(height: 12),
            buildProfileMenu(Icons.lock_outline, "Security Settings", 'security'),
            const SizedBox(height: 12),
            buildProfileMenu(Icons.help_outline, "Help & Support", 'support'),
            const SizedBox(height: 12),
            buildProfileMenu(Icons.card_giftcard, "Terra Rewards", 'rewards'),
            if (!widget.isTablet) ...[
              const SizedBox(height: 24),
              buildProfileMenu(
                Icons.logout,
                "Log Out",
                'logout',
                isDestructive: true,
              ),
            ],
          ],
        );

        Widget rightPane;
        if (profileView == 'main') {
          rightPane = Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
              border: Border.all(
                color: isDarkMode
                    ? AppColors.darkBorder
                    : AppColors.lightBorder,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Prototype Tools",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    buildTestBtn(
                      "Employer",
                      currentAccountType == AccountType.employer,
                      AppColors.blue,
                      () {
                        ref.read(accountTypeProvider.notifier).state =
                            AccountType.employer;
                        ref.read(hybridToggleProvider.notifier).state =
                            AccountType.employer;
                      },
                    ),
                    buildTestBtn(
                      "Nyxian",
                      currentAccountType == AccountType.nyxian,
                      AppColors.green,
                      () {
                        ref.read(accountTypeProvider.notifier).state =
                            AccountType.nyxian;
                        ref.read(hybridToggleProvider.notifier).state =
                            AccountType.nyxian;
                      },
                    ),
                    buildTestBtn(
                      "Hybrid PRO",
                      currentAccountType == AccountType.hybrid,
                      AppColors.amber,
                      () {
                        ref.read(accountTypeProvider.notifier).state =
                            AccountType.hybrid;
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        } else if (profileView == 'personal') {
          rightPane = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildSubHeader(
                "Personal Information",
                () => ref.read(profileViewProvider.notifier).state = 'main',
              ),
              UIHelpers.buildTextField(
                Icons.person,
                "Full Name",
                isDarkMode,
                controller: _nameController,
              ),
              const SizedBox(height: 16),
              UIHelpers.buildTextField(
                Icons.email,
                "Email Address",
                isDarkMode,
                controller: _emailController,
              ),
              const SizedBox(height: 16),
              UIHelpers.buildTextField(
                Icons.phone,
                "Phone Number",
                isDarkMode,
                controller: _phoneController,
              ),
              const SizedBox(height: 32),
              _isSaving
                  ? const Center(child: CircularProgressIndicator())
                  : UIHelpers.buildPrimaryButton(
                      "Save Changes",
                      () => _saveProfile(profile!),
                      isDarkMode,
                    ),
            ],
          );
        } else if (profileView == 'professional') {
          Widget buildSkillChip(String label, bool isDarkMode) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF27272A)
                    : AppColors.lightCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.transparent
                      : AppColors.lightBorder,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
              ),
            );
          }

          Widget buildAddSkillChip(bool isDarkMode) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDarkMode
                      ? const Color(0xFF3F3F46)
                      : AppColors.lightTextMuted.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add,
                    size: 16,
                    color: isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "Add Skill",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                ],
              ),
            );
          }

          Widget buildSkillsCard() {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF121214) : AppColors.lightBg,
                border: Border.all(
                  color: isDarkMode
                      ? const Color(0xFF1E1E20)
                      : AppColors.lightBorder,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Skills & Services",
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      buildSkillChip("Plumbing", isDarkMode),
                      buildSkillChip("Electrical", isDarkMode),
                      buildSkillChip("HVAC", isDarkMode),
                      buildAddSkillChip(isDarkMode),
                    ],
                  ),
                ],
              ),
            );
          }

          rightPane = SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildSubHeader(
                  currentAccountType == AccountType.nyxian
                      ? "Nyxian Profile"
                      : currentAccountType == AccountType.employer
                      ? "Professional Info"
                      : "Hybrid Profile",
                  () => ref.read(profileViewProvider.notifier).state = 'main',
                ),
                if (currentAccountType == AccountType.nyxian ||
                    currentAccountType == AccountType.hybrid) ...[
                  Text(
                    "NYXIAN WORKER PROFILE",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: AppColors.green,
                    ),
                  ),
                  const SizedBox(height: 16),
                  UIHelpers.buildTextField(
                    Icons.work,
                    "Headline / Title",
                    isDarkMode,
                    controller: _headlineController,
                  ),
                  const SizedBox(height: 16),
                  UIHelpers.buildTextField(
                    Icons.attach_money,
                    "Standard Hourly Rate",
                    isDarkMode,
                    controller: _hourlyRateController,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  buildSkillsCard(),
                ],
                if (currentAccountType == AccountType.hybrid)
                  const SizedBox(height: 24),
                if (currentAccountType == AccountType.employer ||
                    currentAccountType == AccountType.hybrid) ...[
                  Text(
                    "COMPANY / EMPLOYER INFO",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: AppColors.blue,
                    ),
                  ),
                  const SizedBox(height: 16),
                  UIHelpers.buildTextField(
                    Icons.business,
                    "Company Name",
                    isDarkMode,
                    controller: _companyNameController,
                  ),
                  const SizedBox(height: 16),
                  UIHelpers.buildTextField(
                    Icons.category,
                    "Industry",
                    isDarkMode,
                    controller: _industryController,
                  ),
                  const SizedBox(height: 16),
                  UIHelpers.buildTextField(
                    Icons.description_outlined,
                    "Tax ID / EIN",
                    isDarkMode,
                    controller: _taxIdController,
                  ),
                ],
                const SizedBox(height: 32),
                _isSaving
                    ? const Center(child: CircularProgressIndicator())
                    : UIHelpers.buildPrimaryButton(
                        "Update Profile",
                        () => _saveProfile(profile!),
                        isDarkMode,
                      ),
              ],
            ),
          );
        } else if (profileView == 'support') {
          final screenHeight = MediaQuery.of(context).size.height;
          final availableHeight = screenHeight - (widget.isTablet ? 200 : 300);
          rightPane = SizedBox(
            height: availableHeight,
            child: NyxChatView(
              onBack: () =>
                  ref.read(profileViewProvider.notifier).state = 'main',
            ),
          );
        } else if (profileView == 'payment') {
          rightPane = PaymentPane(
            onBack: () => ref.read(profileViewProvider.notifier).state = 'main',
          );
        } else if (profileView == 'subscription') {
          rightPane = SubscriptionPane(
            onBack: () => ref.read(profileViewProvider.notifier).state = 'main',
          );
        } else if (profileView == 'trust') {
          rightPane = TrustPane(
            onBack: () => ref.read(profileViewProvider.notifier).state = 'main',
          );
        } else if (profileView == 'history') {
          rightPane = HistoryPane(
            onBack: () => ref.read(profileViewProvider.notifier).state = 'main',
          );
        } else if (profileView == 'reviews') {
          rightPane = ReviewsPane(
            onBack: () => ref.read(profileViewProvider.notifier).state = 'main',
          );
        } else if (profileView == 'security') {
          rightPane = SecurityPane(
            onBack: () => ref.read(profileViewProvider.notifier).state = 'main',
          );
        } else if (profileView == 'rewards') {
          rightPane = RewardsPane(
            onBack: () => ref.read(profileViewProvider.notifier).state = 'main',
          );
        } else {
          rightPane = Center(
            child: Text(
              "Select an option",
              style: TextStyle(
                color: isDarkMode
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          );
        }

        if (widget.isTablet) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 1, child: menuPane),
              const SizedBox(width: 32),
              Container(
                width: 1,
                color: isDarkMode
                    ? AppColors.darkBorder
                    : AppColors.lightBorder,
              ),
              const SizedBox(width: 32),
              Expanded(flex: 2, child: rightPane),
            ],
          );
        } else {
          return profileView == 'main' ? menuPane : rightPane;
        }
      },
    );
  }
}
