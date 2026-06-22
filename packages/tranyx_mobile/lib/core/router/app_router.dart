import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tranyx_mobile/features/navigation/presentation/main_wrapper.dart';
import 'package:tranyx_mobile/features/navigation/providers/navigation_provider.dart';
import 'package:tranyx_mobile/features/jobs/providers/jobs_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/jobs/models/job.dart';
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';
import 'package:tranyx_mobile/core/utils/secure_storage_helper.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';

// Provides the GoRouter instance
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    // Added observers or deeper routing can go here for universal links
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const MainWrapper(),
      ),
      // Example of a dynamic route that would handle a deep link to a specific job
      GoRoute(
        path: '/job/:id',
        name: 'job_details',
        builder: (context, state) {
          final jobId = state.pathParameters['id'];

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (jobId != null) {
              // Switch to the jobs tab — the stream providers will load the job
              NavigationNotifier.switchTab(ref, 'jobs');
              ref.read(jobsViewProvider.notifier).state = 'details';

              try {
                final doc = await ref
                    .read(firestoreProvider)
                    .collection('jobs')
                    .doc(jobId)
                    .get();
                if (doc.exists && doc.data() != null) {
                  final job = Job.fromMap(doc.data()!, doc.id);
                  ref.read(selectedJobProvider.notifier).state = job;
                }
              } catch (e) {
                debugPrint("Error fetching job details in router: $e");
              }
            }
          });

          return const MainWrapper();
        },
      ),
      // Handle wallet connection redirect
      GoRoute(
        path: '/onConnect',
        name: 'on_connect',
        builder: (context, state) {
          final queryParams = state.uri.queryParameters;
          final error = queryParams['errorMessage'] ?? queryParams['errorCode'];
          final phantomPub = queryParams['phantom_encryption_public_key'];
          final data = queryParams['data'];
          final nonce = queryParams['nonce'];

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final user = ref.read(userProvider);
            if (user != null) {
              // Switch to profile tab where payment/wallet UI is located
              NavigationNotifier.switchTab(ref, 'profile');
            }

            final keyBytes = ref.read(phantomSessionPrivateKeyProvider);
            final walletType =
                ref.read(connectingWalletTypeProvider) ?? 'phantom';

            // Clear session key state
            ref.read(phantomSessionPrivateKeyProvider.notifier).state = null;
            ref.read(connectingWalletTypeProvider.notifier).state = null;

            if (error != null) {
              debugPrint("Phantom connection error: $error");
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Wallet connection cancelled or failed: $error',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            if (phantomPub == null ||
                data == null ||
                nonce == null ||
                keyBytes == null) {
              debugPrint(
                "Missing required deep link parameters or session key is missing.",
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Wallet connection failed: Missing parameters.',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            // Decrypt response
            final service = ref.read(phantomServiceProvider);
            final decrypted = service.decryptConnectResponse(
              phantomPubB58: phantomPub,
              dataB58: data,
              nonceB58: nonce,
              sessionPrivateKeyBytes: keyBytes,
            );

            if (decrypted == null) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to decrypt wallet response.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            final userSolanaPublicKey = decrypted['public_key'] as String?;
            if (userSolanaPublicKey == null || userSolanaPublicKey.isEmpty) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Failed to retrieve public key from decrypted payload.',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            final isDarkMode = ref.read(themeModeProvider);

            if (user != null) {
              try {
                await ref
                    .read(firestoreProvider)
                    .collection('users')
                    .doc(user.uid)
                    .update({
                      'walletPublicKey': userSolanaPublicKey,
                      'connectedWalletType': walletType,
                    });
                ref.invalidate(userProfileProvider);

                // Write link to walletLinks collection as well (for cross-platform login support)
                final password = await SecureStorageHelper.getPassword();
                final obfuscatedPassword = password != null
                    ? SecureStorageHelper.obfuscate(password)
                    : null;

                final linkData = <String, dynamic>{
                  'uid': user.uid,
                  'email': user.email,
                  'linkedAt': DateTime.now().millisecondsSinceEpoch,
                };
                if (obfuscatedPassword != null) {
                  linkData['password'] = obfuscatedPassword;
                }

                await ref
                    .read(firestoreProvider)
                    .collection('walletLinks')
                    .doc(userSolanaPublicKey)
                    .set(linkData);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Wallet Connected: $userSolanaPublicKey'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to update wallet address: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            } else {
              // Sign in with Solana Wallet
              try {
                final walletLinkDoc = await ref
                    .read(firestoreProvider)
                    .collection('walletLinks')
                    .doc(userSolanaPublicKey)
                    .get();
                if (!walletLinkDoc.exists) {
                  ref.read(pendingWalletPublicKeyProvider.notifier).state =
                      userSolanaPublicKey;
                  ref.read(authViewProvider.notifier).state = 'register-path';
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Wallet connected! Please register or sign in to link your account.',
                        ),
                        backgroundColor: Colors.indigo,
                      ),
                    );
                  }
                  return;
                }

                final linkData = walletLinkDoc.data();
                var email = linkData?['email'] as String?;
                final uid = linkData?['uid'] as String?;
                final obfuscatedPassword = linkData?['password'] as String?;

                if ((email == null || email.isEmpty) && uid != null) {
                  final userDoc = await ref
                      .read(firestoreProvider)
                      .collection('users')
                      .doc(uid)
                      .get();
                  email = userDoc.data()?['email'] as String?;
                }

                if (email == null || email.isEmpty) {
                  throw 'No email associated with this wallet link.';
                }

                if (obfuscatedPassword != null &&
                    obfuscatedPassword.isNotEmpty) {
                  final password = SecureStorageHelper.deobfuscate(
                    obfuscatedPassword,
                  );
                  await ref
                      .read(firebaseAuthProvider)
                      .signInWithEmailAndPassword(
                        email: email,
                        password: password,
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Logged in successfully via Solana wallet!',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } else {
                  // Prompt user to enter their password to link/authorize this device
                  if (context.mounted) {
                    final password = await _showPasswordPromptDialog(
                      context,
                      email,
                      isDarkMode,
                    );
                    if (password != null && password.isNotEmpty) {
                      await ref
                          .read(firebaseAuthProvider)
                          .signInWithEmailAndPassword(
                            email: email,
                            password: password,
                          );

                      // Save password locally and update Firestore walletLinks with obfuscated password
                      await SecureStorageHelper.savePassword(password);
                      await ref
                          .read(firestoreProvider)
                          .collection('walletLinks')
                          .doc(userSolanaPublicKey)
                          .update({
                            'password': SecureStorageHelper.obfuscate(password),
                          });

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Logged in successfully and authorized device!',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Wallet Sign-In failed: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }
          });

          return const MainWrapper();
        },
      ),
    ],
  );
});

Future<String?> _showPasswordPromptDialog(
  BuildContext context,
  String email,
  bool isDarkMode,
) async {
  final controller = TextEditingController();
  bool obscureText = true;

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final textStyle = TextStyle(
            color: isDarkMode ? AppColors.darkText : AppColors.lightText,
          );
          return AlertDialog(
            backgroundColor: isDarkMode ? AppColors.darkCard : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            title: Text(
              'Authorize Device',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDarkMode ? AppColors.darkText : AppColors.lightText,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Please enter your password for $email to authorize wallet sign-in on this device.',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  obscureText: obscureText,
                  style: textStyle,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: TextStyle(
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: isDarkMode
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.indigo,
                        width: 2,
                      ),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureText ? Icons.visibility : Icons.visibility_off,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                      onPressed: () =>
                          setState(() => obscureText = !obscureText),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                onPressed: () {
                  final pwd = controller.text.trim();
                  if (pwd.isNotEmpty) {
                    Navigator.of(context).pop(pwd);
                  }
                },
                child: const Text(
                  'Authorize',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
