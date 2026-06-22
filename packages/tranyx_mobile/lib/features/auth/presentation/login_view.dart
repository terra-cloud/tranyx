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
                        color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Choose which Solana wallet application you want to continue with.",
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          _buildWalletOption('phantom', 'Phantom', 'assets/images/PhantomWallet.png'),
                          _buildWalletOption('solflare', 'Solflare', 'assets/images/Solflare.png'),
                          _buildWalletOption('backpack', 'Backpack', 'assets/images/BackPack.png'),
                          _buildWalletOption('trust', 'Trust Wallet', 'assets/images/TrustWallet.jpeg'),
                        ],
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

  Widget _buildWalletOption(String id, String name, String assetPath) {
    final isDarkMode = ref.watch(themeModeProvider);
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            assetPath,
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
          name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDarkMode ? AppColors.darkText : AppColors.lightText,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
        ),
        onTap: () async {
          Navigator.of(context).pop();
          await _connectWallet(id);
        },
      ),
    );
  }

  Future<void> _connectWallet(String walletId) async {
    setState(() => _isLoading = true);
    try {
      final phantomService = ref.read(phantomServiceProvider);
      final connectUri = await phantomService.generateConnectUri(walletType: walletId);
      
      debugPrint('Launching wallet deep link connect URI: $connectUri');
      
      final launched = await launchUrl(
        connectUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw 'Could not launch wallet application. Make sure the wallet app is installed.';
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
