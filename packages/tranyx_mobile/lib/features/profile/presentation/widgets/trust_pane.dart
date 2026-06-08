import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';

class TrustPane extends ConsumerStatefulWidget {
  final VoidCallback onBack;

  const TrustPane({super.key, required this.onBack});

  @override
  ConsumerState<TrustPane> createState() => _TrustPaneState();
}

class _TrustPaneState extends ConsumerState<TrustPane> {
  bool _isProcessing = false;
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _verifyEmail(String uid) async {
    setState(() => _isProcessing = true);
    try {
      final user = ref.read(userProvider);
      if (user != null) {
        // In mobile, we trigger verification mail if email isn't verified
        // But for mock consistency with web, we can also set the flag directly
        await ref.read(firestoreProvider).collection('users').doc(uid).update({
          'emailVerified': true,
        });
        ref.invalidate(userProfileProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email verified successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Verification failed: $e')));
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showPhoneVerifySheet(String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Verify Phone Number',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '+63 917 123 4567',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _isProcessing
                  ? const Center(child: CircularProgressIndicator())
                  : UIHelpers.buildPrimaryButton(
                      'Send Verification SMS',
                      () async {
                        final val = _phoneController.text.trim();
                        if (val.isEmpty) return;

                        setState(() => _isProcessing = true);
                        Navigator.pop(context);

                        // Mock OTP Verification Flow
                        final otpConfirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) {
                            final codeController = TextEditingController();
                            return AlertDialog(
                              title: const Text('Enter Verification Code'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'We sent a verification code to your number. Enter "123456" to verify.',
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: codeController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '6-Digit OTP',
                                      hintText: '123456',
                                    ),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    if (codeController.text.trim() ==
                                        '123456') {
                                      Navigator.pop(context, true);
                                    } else {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Invalid code'),
                                        ),
                                      );
                                    }
                                  },
                                  child: const Text('Verify'),
                                ),
                              ],
                            );
                          },
                        );

                        if (otpConfirmed == true) {
                          try {
                            await ref
                                .read(firestoreProvider)
                                .collection('users')
                                .doc(uid)
                                .update({
                                  'phoneNumber': val,
                                  'phoneVerified': true,
                                });
                            ref.invalidate(userProfileProvider);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Phone number verified!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed: $e')),
                              );
                            }
                          }
                        }
                        setState(() => _isProcessing = false);
                      },
                      ref.read(themeModeProvider),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  void _showIdVerificationSheet(String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Verify Identity',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Upload a government-issued ID (Passport, Driver\'s License, UMID) to verify your account identity.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            const Center(
              child: Icon(
                Icons.badge_outlined,
                size: 64,
                color: AppColors.indigo,
              ),
            ),
            const SizedBox(height: 24),
            _isProcessing
                ? const Center(child: CircularProgressIndicator())
                : UIHelpers.buildPrimaryButton(
                    'Submit Mock Verification',
                    () async {
                      setState(() => _isProcessing = true);
                      Navigator.pop(context);
                      try {
                        // Kyc details
                        final data = {
                          'idType': 'Drivers License',
                          'idNumber': 'DL-123-456-789',
                          'status': 'Approved',
                        };
                        await ref
                            .read(transitRepositoryProvider)
                            .saveKycSubmission(uid, data);
                        await ref
                            .read(firestoreProvider)
                            .collection('users')
                            .doc(uid)
                            .update({'idVerified': true});
                        ref.invalidate(userProfileProvider);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'ID Verification approved instantly!',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Failed: $e')));
                        }
                      } finally {
                        setState(() => _isProcessing = false);
                      }
                    },
                    ref.read(themeModeProvider),
                  ),
          ],
        ),
      ),
    );
  }

  void _showBgCheckSheet(String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Background Check Consent',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Give consent to run a secure background check. This verifies criminal records and increases your Trust Badge to Fully Verified.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            const Center(
              child: Icon(Icons.security, size: 64, color: AppColors.indigo),
            ),
            const SizedBox(height: 24),
            _isProcessing
                ? const Center(child: CircularProgressIndicator())
                : UIHelpers.buildPrimaryButton(
                    'Give Consent & Run Check',
                    () async {
                      setState(() => _isProcessing = true);
                      Navigator.pop(context);
                      try {
                        await ref
                            .read(firestoreProvider)
                            .collection('users')
                            .doc(uid)
                            .update({
                              'bgChecked': true,
                              'verificationLevel': 2,
                            });
                        ref.invalidate(userProfileProvider);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Background Check cleared! You are now Fully Verified (Level 2).',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Failed: $e')));
                        }
                      } finally {
                        setState(() => _isProcessing = false);
                      }
                    },
                    ref.read(themeModeProvider),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required String desc,
    required bool isVerified,
    required VoidCallback onTap,
  }) {
    final isDarkMode = ref.read(themeModeProvider);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isVerified ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isVerified ? Colors.green : Colors.grey,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          isVerified
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Verified',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.indigo,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Verify',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final userProfile = ref.watch(userProfileProvider).value;

    if (userProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final isEmail = userProfile.emailVerified;
    final isPhone = userProfile.phoneVerified;
    final isId = userProfile.idVerified;
    final isBg = userProfile.bgChecked;
    final level = userProfile.verificationLevel;

    double progress = 0.0;
    if (isEmail) progress += 0.25;
    if (isPhone) progress += 0.25;
    if (isId) progress += 0.25;
    if (isBg) progress += 0.25;

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
            const Text(
              'Trust & Verification',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Shield Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: level == 2
                      ? Colors.green.withValues(alpha: 0.1)
                      : level == 1
                      ? Colors.blue.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: level == 2
                        ? Colors.green.withValues(alpha: 0.3)
                        : level == 1
                        ? Colors.blue.withValues(alpha: 0.3)
                        : Colors.grey.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  level > 0 ? Icons.verified_user : Icons.gpp_maybe,
                  size: 32,
                  color: level == 2
                      ? Colors.green
                      : level == 1
                      ? Colors.blue
                      : Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                level == 2
                    ? 'Fully Verified (Level 2)'
                    : level == 1
                    ? 'Basic Verified (Level 1)'
                    : 'Unverified (Level 0)',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                level == 2
                    ? 'Amazing! You have completed all verification levels. You get maximum trust badge visibility!'
                    : level == 1
                    ? 'You have verified email & phone number. Complete ID & Background checks to become Fully Verified.'
                    : 'Get started by verifying your profile details to gain trust from the community.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDarkMode
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
                ),
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: isDarkMode
                      ? Colors.black26
                      : Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.indigo,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Steps List
        _buildCard(
          title: 'Email Address',
          desc: userProfile.email,
          isVerified: isEmail,
          onTap: () => _verifyEmail(userProfile.uid),
        ),
        _buildCard(
          title: 'Phone Number',
          desc: userProfile.phoneNumber ?? 'Not registered yet',
          isVerified: isPhone,
          onTap: () => _showPhoneVerifySheet(userProfile.uid),
        ),
        _buildCard(
          title: 'Identity Verification',
          desc: 'Verify with passport or license card',
          isVerified: isId,
          onTap: () => _showIdVerificationSheet(userProfile.uid),
        ),
        _buildCard(
          title: 'Background Records Check',
          desc: 'Verify background records cleared status',
          isVerified: isBg,
          onTap: () => _showBgCheckSheet(userProfile.uid),
        ),
      ],
    );
  }
}
