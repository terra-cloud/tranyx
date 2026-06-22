import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/features/auth/presentation/auth_ui_helper.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tranyx_mobile/flavors.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _launchUrl(String path) async {
    final String domain;
    switch (F.appFlavor) {
      case Flavor.dev:
        domain = 'dev.tranyx.app';
        break;
      case Flavor.uat:
        domain = 'uat.tranyx.app';
        break;
      case Flavor.production:
        domain = 'tranyx.app';
        break;
    }
    final url = Uri.parse('https://$domain$path');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        _showError('Could not launch $url');
      }
    } catch (e) {
      _showError('Could not launch $url: $e');
    }
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref
          .read(authControllerProvider)
          .signInWithEmailAndPassword(email, password);
      // Success will trigger state change in authControllerProvider which will be handled by the main app wrapper
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'An error occurred during login');
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(authControllerProvider).signInWithGoogle();
      // On successful Google Sign-In, we might need to set a default account type if it's a new user
      // But for login, it usually just signs them in.
    } catch (e) {
      _showError('Google Sign-In failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);

    return AuthUiHelper.buildAuthScaffold(
      context: context,
      isDarkMode: isDarkMode,
      isLoading: _isLoading,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthUiHelper.buildHeader(
            title: "Welcome back",
            subtitle: "Enter your details to access your account.",
            isDarkMode: isDarkMode,
            icon: Icons.widgets,
          ),
          const SizedBox(height: 32),
          UIHelpers.buildTextField(
            Icons.mail_outline,
            "Email address",
            isDarkMode,
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          UIHelpers.buildTextField(
            Icons.lock_outline,
            "Password",
            isDarkMode,
            isPassword: true,
            controller: _passwordController,
            keyboardType: TextInputType.visiblePassword,
          ),
          const SizedBox(height: 32),
          UIHelpers.buildPrimaryButton("Log In", _handleLogin, isDarkMode),
          const SizedBox(height: 16),
          AuthUiHelper.buildGoogleButton(
            isDarkMode: isDarkMode,
            onPressed: _handleGoogleSignIn,
          ),
          const SizedBox(height: 24),
          RichText(
            text: TextSpan(
              text: "New to Tranyx? ",
              style: TextStyle(
                color: isDarkMode
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
                fontWeight: FontWeight.w600,
              ),
              children: [
                TextSpan(
                  text: "Create an account",
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : AppColors.indigo,
                    fontWeight: FontWeight.bold,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => ref.read(authViewProvider.notifier).state =
                        'register-path',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _launchUrl('/terms-of-use'),
                child: Text(
                  "Terms of Use",
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : AppColors.indigo,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "•",
                style: TextStyle(
                  color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _launchUrl('/privacy-policy'),
                child: Text(
                  "Privacy Policy",
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : AppColors.indigo,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
