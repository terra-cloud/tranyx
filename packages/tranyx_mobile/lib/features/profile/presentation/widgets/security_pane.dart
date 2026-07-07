import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/providers/biometric_provider.dart';
import 'package:tranyx_mobile/core/services/biometric_service.dart';

class SecurityPane extends ConsumerStatefulWidget {
  final VoidCallback onBack;

  const SecurityPane({super.key, required this.onBack});

  @override
  ConsumerState<SecurityPane> createState() => _SecurityPaneState();
}

class _SecurityPaneState extends ConsumerState<SecurityPane> {
  bool _isCheckingHardware = true;
  bool _isBiometricSupported = false;

  @override
  void initState() {
    super.initState();
    _checkHardwareSupport();
  }

  Future<void> _checkHardwareSupport() async {
    final supported = await BiometricService.isAvailable();
    if (mounted) {
      setState(() {
        _isBiometricSupported = supported;
        _isCheckingHardware = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final biometricEnabled = ref.watch(biometricEnabledProvider);

    final cardBgColor = isDarkMode ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDarkMode ? AppColors.darkBorder : AppColors.lightBorder;
    final textColor = isDarkMode ? AppColors.darkText : AppColors.lightText;
    final subTextColor = isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
              onPressed: widget.onBack,
            ),
            const SizedBox(width: 8),
            Text(
              'Security Settings',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Information/Shield Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.indigo.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.indigo.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.security,
                  size: 32,
                  color: AppColors.indigo,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'App Lock Protection',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enable biometric lock to require fingerprint or face recognition when opening or resuming Tranyx. This helps secure your digital assets.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: subTextColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Toggle Control Card
        if (_isCheckingHardware)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.indigo),
              ),
            ),
          )
        else if (!_isBiometricSupported)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1C1917) : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDarkMode ? AppColors.darkBorder : Colors.orange.shade200,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Biometrics Unavailable',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your device does not support biometric authentication or has no credentials registered.',
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDarkMode ? AppColors.darkBorder : AppColors.lightBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fingerprint,
                    color: AppColors.indigo,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Use Biometrics',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Lock app with Face ID / Fingerprint',
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: biometricEnabled,
                  activeTrackColor: AppColors.indigo,
                  onChanged: (val) async {
                    if (val) {
                      // Attempt to authenticate once to verify it works before enabling
                      final authenticated = await BiometricService.authenticate();
                      if (authenticated) {
                        await ref.read(biometricEnabledProvider.notifier).setEnabled(true);
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Authentication failed. Biometric lock was not enabled.'),
                              backgroundColor: AppColors.red,
                            ),
                          );
                        }
                      }
                    } else {
                      await ref.read(biometricEnabledProvider.notifier).setEnabled(false);
                    }
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}
