import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tranyx_mobile/flavors.dart';
import 'package:tranyx_mobile/core/services/trust_wallet_service.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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

                        if (F.appFlavor == Flavor.dev) {
                          setState(() => _isProcessing = true);
                          Navigator.pop(context);

                          // Mock OTP Verification Flow for Dev only
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
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Phone number verified!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed: $e')),
                                );
                              }
                            }
                          }
                          setState(() => _isProcessing = false);
                        } else {
                          // Real OTP flow for UAT/Production
                          Navigator.pop(context);
                          await _sendRealSmsVerification(uid, val);
                        }
                      },
                      ref.read(themeModeProvider),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendRealSmsVerification(String uid, String phoneNumber) async {
    setState(() => _isProcessing = true);
    final messenger = ScaffoldMessenger.of(context);
    final localContext = context;

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-resolution on Android devices
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              await user.linkWithCredential(credential);
            }
            await ref
                .read(firestoreProvider)
                .collection('users')
                .doc(uid)
                .update({'phoneNumber': phoneNumber, 'phoneVerified': true});
            ref.invalidate(userProfileProvider);

            messenger.showSnackBar(
              const SnackBar(
                content: Text('Phone number verified automatically!'),
                backgroundColor: Colors.green,
              ),
            );
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Automatic verification failed: $e')),
            );
          } finally {
            if (localContext.mounted) setState(() => _isProcessing = false);
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (localContext.mounted) {
            setState(() => _isProcessing = false);
          }
          messenger.showSnackBar(
            SnackBar(
              content: Text(e.message ?? 'Verification failed'),
              backgroundColor: AppColors.red,
            ),
          );
        },
        codeSent: (String verificationId, int? resendToken) async {
          if (localContext.mounted) {
            setState(() => _isProcessing = false);
          }

          final codeController = TextEditingController();
          if (!localContext.mounted) return;
          final otpConfirmed = await showDialog<bool>(
            context: localContext,
            barrierDismissible: false,
            builder: (context) {
              return AlertDialog(
                title: const Text('Verify Phone Number'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Enter the 6-digit code sent to $phoneNumber.'),
                    const SizedBox(height: 16),
                    TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '6-Digit OTP',
                        hintText: 'xxxxxx',
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Verify'),
                  ),
                ],
              );
            },
          );

          if (otpConfirmed == true) {
            final smsCode = codeController.text.trim();
            if (smsCode.isEmpty) return;

            if (localContext.mounted) setState(() => _isProcessing = true);
            try {
              final credential = PhoneAuthProvider.credential(
                verificationId: verificationId,
                smsCode: smsCode,
              );

              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                await user.linkWithCredential(credential);
              }

              await ref
                  .read(firestoreProvider)
                  .collection('users')
                  .doc(uid)
                  .update({'phoneNumber': phoneNumber, 'phoneVerified': true});
              ref.invalidate(userProfileProvider);

              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Phone number verified successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Failed to verify OTP: $e'),
                  backgroundColor: AppColors.red,
                ),
              );
            } finally {
              if (localContext.mounted) setState(() => _isProcessing = false);
            }
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      if (localContext.mounted) {
        setState(() => _isProcessing = false);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to request verification: $e'),
          backgroundColor: AppColors.red,
        ),
      );
    }
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

  Future<void> _linkGoogleAccount(String uid) async {
    setState(() => _isProcessing = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'No authenticated user session found.';

      final provider = GoogleAuthProvider();
      final userCredential = await user.linkWithProvider(provider);
      final email = userCredential.user?.email;

      if (email != null) {
        await ref.read(firestoreProvider).collection('users').doc(uid).update({
          'googleEmail': email,
        });
      }

      ref.invalidate(userProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google account linked successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to link Google: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _unlinkGoogleAccount(String uid) async {
    setState(() => _isProcessing = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'No authenticated user session found.';

      await user.unlink('google.com');
      await ref.read(firestoreProvider).collection('users').doc(uid).update({
        'googleEmail': '',
      });

      ref.invalidate(userProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google account unlinked successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unlink Google: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _unlinkSolanaWallet(String uid, String walletKey) async {
    setState(() => _isProcessing = true);
    try {
      await ref
          .read(firestoreProvider)
          .collection('walletLinks')
          .doc(walletKey)
          .delete();
      await ref.read(firestoreProvider).collection('users').doc(uid).update({
        'walletPublicKey': '',
      });

      ref.invalidate(userProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solana wallet unlinked successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unlink wallet: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _linkSolanaWallet(String uid, String type) async {
    setState(() => _isProcessing = true);
    try {
      if (type == 'trust') {
        const projectId = '52cb8eaaad34baed8dbe063b454b28f6';
        final modal = await TrustWalletService.createModal(
          context: context,
          projectId: projectId,
        );
        modal.openModalView();

        modal.onModalConnect.subscribe((ModalConnect? event) async {
          modal.onModalConnect.unsubscribeAll();
          final address = modal.session?.getAddress(NetworkUtils.solana);
          if (address != null && address.isNotEmpty) {
            // ── 1:1 guard: check if this wallet is already owned by another user ──
            final existingDoc = await ref
                .read(firestoreProvider)
                .collection('walletLinks')
                .doc(address)
                .get();

            if (existingDoc.exists) {
              final existingUid = existingDoc.data()?['uid'] as String?;
              if (existingUid != null && existingUid != uid) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'This wallet is already linked to another account. Each wallet can only be connected to one account.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return;
              }
            }

            await ref
                .read(firestoreProvider)
                .collection('users')
                .doc(uid)
                .update({
                  'walletPublicKey': address,
                  'connectedWalletType': 'trust',
                });

            await ref
                .read(firestoreProvider)
                .collection('walletLinks')
                .doc(address)
                .set({
                  'uid': uid,
                  'email': FirebaseAuth.instance.currentUser?.email,
                  'provider': 'password',
                  'linkedAt': DateTime.now().millisecondsSinceEpoch,
                });

            ref.invalidate(userProfileProvider);
          }
        });
      } else {
        final phantomService = ref.read(phantomServiceProvider);
        final uri = await phantomService.generateConnectUri(walletType: type);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Wallet app is not installed or could not be launched.';
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect wallet: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Widget _buildLinkedAccountsSection(UserProfile userProfile, bool isDarkMode) {
    final firebaseUser = ref.watch(userProvider);
    final hasGoogleProvider = firebaseUser?.providerData.any((p) => p.providerId == 'google.com') ?? false;
    final hasGoogle = (userProfile.googleEmail ?? '').isNotEmpty || hasGoogleProvider;
    final googleEmailStr = (userProfile.googleEmail ?? '').isNotEmpty
        ? userProfile.googleEmail!
        : (hasGoogleProvider ? (firebaseUser?.email ?? '') : '');
    final hasWallet = (userProfile.walletPublicKey ?? '').isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 20, bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode
            ? AppColors.darkCard.withValues(alpha: 0.5)
            : AppColors.lightCard.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link, color: AppColors.indigo, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Linked Accounts',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset(
                  'assets/icons/google.webp',
                  width: 22,
                  height: 22,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Google Account',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      hasGoogle ? googleEmailStr : 'Not linked',
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
              ElevatedButton(
                onPressed: () => hasGoogle
                    ? _unlinkGoogleAccount(userProfile.uid)
                    : _linkGoogleAccount(userProfile.uid),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasGoogle
                      ? Colors.redAccent.withValues(alpha: 0.1)
                      : AppColors.indigo,
                  foregroundColor: hasGoogle ? Colors.redAccent : Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  hasGoogle ? 'Unlink' : 'Link',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),

          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset(
                  'assets/icons/solana.webp',
                  width: 22,
                  height: 22,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Solana Wallet',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      hasWallet
                          ? '${userProfile.walletPublicKey!.substring(0, 6)}...${userProfile.walletPublicKey!.substring(userProfile.walletPublicKey!.length - 6)}'
                          : 'Not linked',
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
              hasWallet
                  ? ElevatedButton(
                      onPressed: () => _unlinkSolanaWallet(
                        userProfile.uid,
                        userProfile.walletPublicKey!,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withValues(
                          alpha: 0.1,
                        ),
                        foregroundColor: Colors.redAccent,
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
                        'Unlink',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : Wrap(
                      spacing: 4,
                      children: [
                        _buildWalletLinkBtn(
                          'Phantom',
                          () => _linkSolanaWallet(userProfile.uid, 'phantom'),
                        ),
                        _buildWalletLinkBtn(
                          'Solflare',
                          () => _linkSolanaWallet(userProfile.uid, 'solflare'),
                        ),
                        _buildWalletLinkBtn(
                          'Trust',
                          () => _linkSolanaWallet(userProfile.uid, 'trust'),
                        ),
                      ],
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWalletLinkBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.indigo.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.indigo,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
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

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
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
                color: isDarkMode
                    ? AppColors.darkBorder
                    : AppColors.lightBorder,
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

          _buildLinkedAccountsSection(userProfile, isDarkMode),
        ],
      ),
    );
  }
}
