import 'package:flutter/material.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/services/biometric_service.dart';

class BiometricLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final bool isDarkMode;

  const BiometricLockScreen({
    super.key,
    required this.onUnlocked,
    required this.isDarkMode,
  });

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    // Auto-authenticate on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticate();
    });
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
    });

    final success = await BiometricService.authenticate();
    
    if (mounted) {
      setState(() {
        _isAuthenticating = false;
      });
      if (success) {
        widget.onUnlocked();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDarkMode ? AppColors.darkBg : AppColors.lightBg;
    final textColor = widget.isDarkMode ? AppColors.darkText : AppColors.lightText;
    final subTextColor = widget.isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    return Material(
      color: bgColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Icon/App Logo container
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: widget.isDarkMode ? const Color(0xFF1E1B4B) : Colors.indigo.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.indigo.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: AppColors.indigo,
                ),
              ),
              const SizedBox(height: 32),
              // App Title
              Text(
                "Tranyx DeFi",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 12),
              // Subtitle
              Text(
                "App Locked for Security",
                style: TextStyle(
                  fontSize: 16,
                  color: subTextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Verify your identity to access your wallet.",
                style: TextStyle(
                  fontSize: 14,
                  color: subTextColor,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              // Auth Trigger Button
              if (_isAuthenticating)
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.indigo),
                )
              else
                UIHelpers.buildPrimaryButton(
                  "Unlock App",
                  _authenticate,
                  widget.isDarkMode,
                ),
              const SizedBox(height: 16),
              // Mini helper text
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.security,
                    size: 14,
                    color: subTextColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "Secure Cryptographic Auth",
                    style: TextStyle(
                      fontSize: 12,
                      color: subTextColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
