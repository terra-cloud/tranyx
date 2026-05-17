import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/features/auth/presentation/auth_ui_helper.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/core/utils/formatters.dart';

class RegisterCompleteProfileView extends ConsumerStatefulWidget {
  const RegisterCompleteProfileView({super.key});

  @override
  ConsumerState<RegisterCompleteProfileView> createState() =>
      _RegisterCompleteProfileViewState();
}

class _RegisterCompleteProfileViewState
    extends ConsumerState<RegisterCompleteProfileView> {
  final _nameController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _businessPermitController = TextEditingController();
  EmployerType _employerType = EmployerType.personal;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(userProvider);
      if (user?.displayName != null) {
        _nameController.text = user!.displayName!;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _businessNameController.dispose();
    _businessPermitController.dispose();
    super.dispose();
  }

  Future<void> _handleComplete() async {
    final pendingType =
        ref.read(pendingAccountTypeProvider) ?? AccountType.employer;
    final name = _nameController.text.trim();
    final businessName = _businessNameController.text.trim();
    final businessPermit = _businessPermitController.text.trim();
    final baseType = ref.read(pendingBaseAccountTypeProvider);

    if (name.isEmpty &&
        (_employerType == EmployerType.personal ||
            pendingType == AccountType.nyxian)) {
      _showError('Please enter your name');
      return;
    }

    if (pendingType == AccountType.hybrid && baseType == null) {
      _showError('Please select a base account type');
      return;
    }

    if (pendingType == AccountType.employer &&
        _employerType == EmployerType.business) {
      if (businessName.isEmpty) {
        _showError('Please enter business name');
        return;
      }
      if (businessPermit.isEmpty) {
        _showError('Please enter business permit');
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      await ref
          .read(authControllerProvider)
          .completeProfile(
            name: _employerType == EmployerType.business ? businessName : name,
            accountType: pendingType,
            baseType: baseType,
            employerType: (pendingType == AccountType.nyxian)
                ? null
                : _employerType,
            businessName: _employerType == EmployerType.business
                ? businessName
                : null,
            businessPermit: _employerType == EmployerType.business
                ? businessPermit
                : null,
          );
      // Refresh user profile provider
      ref.invalidate(userProfileProvider);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Widget _buildBaseTypeCard(String label, AccountType type, bool isDarkMode) {
    final isSelected = ref.watch(pendingBaseAccountTypeProvider) == type;
    return GestureDetector(
      onTap: () =>
          ref.read(pendingBaseAccountTypeProvider.notifier).state = type,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? (type == AccountType.employer
                        ? AppColors.blue
                        : AppColors.green)
                    .withValues(alpha: 0.1)
              : (isDarkMode ? AppColors.darkCard : AppColors.lightCard),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? (type == AccountType.employer
                      ? AppColors.blue
                      : AppColors.green)
                : (isDarkMode ? AppColors.darkBorder : AppColors.lightBorder),
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected
                ? (type == AccountType.employer
                      ? AppColors.blue
                      : AppColors.green)
                : (isDarkMode ? AppColors.darkText : AppColors.lightText),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final pendingType =
        ref.watch(pendingAccountTypeProvider) ?? AccountType.employer;

    return AuthUiHelper.buildAuthScaffold(
      context: context,
      isDarkMode: isDarkMode,
      isLoading: _isLoading,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Complete Profile",
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Just a few more details to get started.",
            style: TextStyle(
              fontSize: 16,
              color: isDarkMode
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 32),
          if (pendingType != AccountType.nyxian) ...[
            if (pendingType == AccountType.employer) ...[
              Text(
                "Account Type",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTypeCard(
                      "Personal",
                      EmployerType.personal,
                      isDarkMode,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTypeCard(
                      "Business",
                      EmployerType.business,
                      isDarkMode,
                    ),
                  ),
                ],
              ),
            ],
            if (pendingType == AccountType.hybrid) ...[
              Row(
                children: [
                  Text(
                    "Choose Base Account",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDarkMode
                          ? AppColors.darkText
                          : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message:
                        "This will be your account type if your Hybrid subscription ends.",
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildBaseTypeCard(
                      "Employer",
                      AccountType.employer,
                      isDarkMode,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildBaseTypeCard(
                      "Nyxian",
                      AccountType.nyxian,
                      isDarkMode,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
          ],
          if (_employerType == EmployerType.personal ||
              pendingType == AccountType.nyxian)
            UIHelpers.buildTextField(
              Icons.person_outline,
              "Your Name",
              isDarkMode,
              controller: _nameController,
            )
          else ...[
            UIHelpers.buildTextField(
              Icons.business_outlined,
              "Business Name",
              isDarkMode,
              controller: _businessNameController,
            ),
            const SizedBox(height: 16),
            UIHelpers.buildTextField(
              Icons.description_outlined,
              "Business Permit Number (e.g. 2024-1234567)",
              isDarkMode,
              controller: _businessPermitController,
              inputFormatters: [BusinessPermitFormatter()],
              keyboardType: TextInputType.number,
            ),
          ],
          const SizedBox(height: 32),
          UIHelpers.buildPrimaryButton(
            "Finish Registration",
            _handleComplete,
            isDarkMode,
          ),
        ],
      ),
    );
  }

  Widget _buildTypeCard(String label, EmployerType type, bool isDarkMode) {
    final isSelected = _employerType == type;
    return GestureDetector(
      onTap: () => setState(() => _employerType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.indigo.withValues(alpha: 0.1)
              : (isDarkMode ? AppColors.darkCard : AppColors.lightCard),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.indigo
                : (isDarkMode ? AppColors.darkBorder : AppColors.lightBorder),
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected
                ? AppColors.indigo
                : (isDarkMode ? AppColors.darkText : AppColors.lightText),
          ),
        ),
      ),
    );
  }
}
