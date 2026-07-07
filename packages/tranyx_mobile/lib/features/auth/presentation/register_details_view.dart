import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/features/auth/presentation/auth_ui_helper.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';

class RegisterDetailsView extends ConsumerStatefulWidget {
  const RegisterDetailsView({super.key});

  @override
  ConsumerState<RegisterDetailsView> createState() =>
      _RegisterDetailsViewState();
}

class _RegisterDetailsViewState extends ConsumerState<RegisterDetailsView> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _validateForm() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty) {
      _showError('Please enter your full name');
      return false;
    }
    if (email.isEmpty || !email.contains('@')) {
      _showError('Please enter a valid email address');
      return false;
    }
    if (password.length < 6) {
      _showError('Password must be at least 6 characters');
      return false;
    }
    return true;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _handleRegister(AccountType pendingType) async {
    if (!_validateForm()) return;

    if (pendingType == AccountType.hybrid &&
        ref.read(pendingBaseAccountTypeProvider) == null) {
      _showError('Please select a base account type');
      return;
    }

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final baseType = ref.read(pendingBaseAccountTypeProvider);

    setState(() => _isLoading = true);
    try {
      await ref
          .read(authControllerProvider)
          .createUserWithEmailAndPassword(
            email: email,
            password: password,
            displayName: name,
            accountType: pendingType,
            baseType: baseType,
          );
      _updateAccountTypeAfterAuth(pendingType);
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'An error occurred during registration');
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn(AccountType? pendingType) async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(authControllerProvider)
          .signInWithGoogle(pendingType: pendingType);
      if (pendingType != null) {
        _updateAccountTypeAfterAuth(pendingType);
      }
    } catch (e) {
      _showError('Google Sign-In failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateAccountTypeAfterAuth(AccountType type) {
    ref.read(accountTypeProvider.notifier).state = type;
    ref.read(hybridToggleProvider.notifier).state = type == AccountType.nyxian
        ? AccountType.nyxian
        : AccountType.employer;
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
    final pendingAccountType = ref.watch(pendingAccountTypeProvider);

    return AuthUiHelper.buildAuthScaffold(
      context: context,
      isDarkMode: isDarkMode,
      isLoading: _isLoading,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back,
          color: isDarkMode
              ? AppColors.darkTextMuted
              : AppColors.lightTextMuted,
        ),
        onPressed: () =>
            ref.read(authViewProvider.notifier).state = 'register-path',
      ),
      actions: [
        IconButton(
          icon: Icon(
            isDarkMode ? Icons.light_mode : Icons.dark_mode,
            color: isDarkMode
                ? AppColors.darkTextMuted
                : AppColors.lightTextMuted,
          ),
          onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Create Account",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              color: isDarkMode ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          // AuthUiHelper.buildHeader(
          //   title: "Create Account",
          //   subtitle: "",
          //   isDarkMode: isDarkMode,
          // ),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                "Signing up as: ",
                style: TextStyle(
                  color: isDarkMode
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      (pendingAccountType == AccountType.employer
                              ? AppColors.blue
                              : pendingAccountType == AccountType.nyxian
                              ? AppColors.green
                              : AppColors.amber)
                          .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        (pendingAccountType == AccountType.employer
                                ? AppColors.blue
                                : pendingAccountType == AccountType.nyxian
                                ? AppColors.green
                                : AppColors.amber)
                            .withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  pendingAccountType?.label ?? '',
                  style: TextStyle(
                    color: (pendingAccountType == AccountType.employer
                        ? AppColors.blue
                        : pendingAccountType == AccountType.nyxian
                        ? AppColors.green
                        : AppColors.amber),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          Consumer(
            builder: (context, ref, _) {
              final pendingWalletKey = ref.watch(pendingWalletPublicKeyProvider);
              if (pendingWalletKey == null) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.indigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.indigo.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link, color: AppColors.indigo),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Wallet connected:\n${pendingWalletKey.substring(0, 6)}...${pendingWalletKey.substring(pendingWalletKey.length - 4)} (will be linked on sign up)",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode ? Colors.white : AppColors.lightText,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 40),
          UIHelpers.buildTextField(
            Icons.person,
            "Full name",
            isDarkMode,
            controller: _nameController,
          ),
          const SizedBox(height: 16),
          UIHelpers.buildTextField(
            Icons.mail_outline,
            "Email address",
            isDarkMode,
            controller: _emailController,
          ),
          const SizedBox(height: 16),
          UIHelpers.buildTextField(
            Icons.lock_outline,
            "Create a Password",
            isDarkMode,
            isPassword: true,
            controller: _passwordController,
          ),
          if (pendingAccountType == AccountType.hybrid) ...[
            const SizedBox(height: 24),
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
          const SizedBox(height: 32),
          UIHelpers.buildPrimaryButton(
            "Complete Registration",
            () => _handleRegister(pendingAccountType ?? AccountType.employer),
            isDarkMode,
          ),
          const SizedBox(height: 24),
          Text(
            "By registering, you agree to our Terms of Service and Privacy Policy.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDarkMode
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "OR",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 24),
          AuthUiHelper.buildGoogleButton(
            isDarkMode: isDarkMode,
            onPressed: () => _handleGoogleSignIn(pendingAccountType),
          ),
        ],
      ),
    );
  }
}
