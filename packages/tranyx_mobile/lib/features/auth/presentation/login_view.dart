import 'dart:async';
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
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';

/// Checks if a wallet app is installed by seeing if its native URI scheme
/// can be resolved by the OS (requires queries entries in AndroidManifest).
Future<bool> _isWalletInstalled(WalletInfo wallet) async {
  try {
    return await canLaunchUrl(Uri.parse(wallet.nativeScheme));
  } catch (_) {
    return false;
  }
}

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
          const SizedBox(height: 16),
          AuthUiHelper.buildWalletButton(
            isDarkMode: isDarkMode,
            onPressed: _handleWalletSignIn,
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
                  color: isDarkMode
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
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

  void _handleWalletSignIn() {
    final isDarkMode = ref.read(themeModeProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: isDarkMode ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final isDarkMode = ref.watch(themeModeProvider);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Select a Wallet",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? AppColors.darkText
                            : AppColors.lightText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Choose which Solana wallet application you want to continue with.",
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: kSupportedWallets.map((wallet) {
                          return _buildWalletOptionAsync(
                            context: context,
                            wallet: wallet,
                            isDarkMode: isDarkMode,
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWalletOptionAsync({
    required BuildContext context,
    required WalletInfo wallet,
    required bool isDarkMode,
  }) {
    return FutureBuilder<bool>(
      future: _isWalletInstalled(wallet),
      builder: (context, snapshot) {
        final isInstalled = snapshot.data ?? false;
        final isChecking = !snapshot.hasData;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.darkBg : AppColors.lightCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                wallet.assetPath,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.account_balance_wallet,
                  color: isDarkMode ? Colors.white : AppColors.lightText,
                ),
              ),
            ),
            title: Text(
              wallet.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDarkMode ? AppColors.darkText : AppColors.lightText,
              ),
            ),
            subtitle: isChecking
                ? null
                : Text(
                    isInstalled ? 'Tap to connect' : 'Not installed',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
            trailing: isChecking
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.indigo,
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isInstalled
                          ? AppColors.indigo.withValues(alpha: 0.12)
                          : Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isInstalled ? 'Connect' : 'Install',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isInstalled ? AppColors.indigo : Colors.orange,
                      ),
                    ),
                  ),
            onTap: () async {
              Navigator.of(context).pop();
              if (isInstalled) {
                await _connectWallet(wallet.id);
              } else {
                await _openStore(wallet.id);
              }
            },
          ),
        );
      },
    );
  }

  Future<void> _connectWallet(String walletId) async {
    setState(() => _isLoading = true);
    try {
      final phantomService = ref.read(phantomServiceProvider);
      final connectUri = await phantomService.generateConnectUri(
        walletType: walletId,
      );

      debugPrint('Launching wallet connect URI: $connectUri');

      final launched = await launchUrl(
        connectUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw 'Could not launch $walletId. Make sure the wallet app is installed.';
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openStore(String walletId) async {
    final phantomService = ref.read(phantomServiceProvider);
    final storeUrl = phantomService.storeUrlFor(walletId);
    final uri = Uri.parse(storeUrl);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showError('Could not open store for $walletId');
      }
    } catch (e) {
      _showError('Could not open store: $e');
    }
  }
}
