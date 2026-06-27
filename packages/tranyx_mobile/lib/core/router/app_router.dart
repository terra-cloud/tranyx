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
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
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
          final phantomPub = queryParams['phantom_encryption_public_key'] ??
              queryParams['solflare_encryption_public_key'] ??
              queryParams['trust_encryption_public_key'] ??
              queryParams['trustwallet_encryption_public_key'] ??
              queryParams['backpack_encryption_public_key'] ??
              queryParams['wallet_encryption_public_key'] ??
              queryParams['encryption_public_key'];
          final data = queryParams['data'];
          final nonce = queryParams['nonce'];

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final user = ref.read(userProvider);
            if (user != null) {
              // Switch to profile tab where payment/wallet UI is located
              NavigationNotifier.switchTab(ref, 'profile');
            }

            // Retrieve keyBytes and walletType from RAM or fallback to SecureStorage
            var keyBytes = ref.read(phantomSessionPrivateKeyProvider);
            var walletType = ref.read(connectingWalletTypeProvider);

            if (keyBytes == null) {
              keyBytes = await SecureStorageHelper.getPhantomSessionKey();
              debugPrint("Retrieved phantom session key from SecureStorage: ${keyBytes != null}");
            }
            if (walletType == null) {
              walletType = await SecureStorageHelper.getConnectingWalletType();
              debugPrint("Retrieved connecting wallet type from SecureStorage: $walletType");
            }

            walletType ??= 'phantom';

            // Clear session key state in RAM
            ref.read(phantomSessionPrivateKeyProvider.notifier).state = null;
            ref.read(connectingWalletTypeProvider.notifier).state = null;

            // Clear connecting wallet type in SecureStorage (keep persistent session key)
            await SecureStorageHelper.deleteConnectingWalletType();

            if (error != null) {
              debugPrint("Phantom connection error: $error");
              await SecureStorageHelper.deletePhantomSessionKey();
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
            final sessionToken = decrypted['session'] as String?;
            if (sessionToken != null) {
              await SecureStorageHelper.savePhantomSessionToken(sessionToken);
            }
            await SecureStorageHelper.savePhantomEncryptionPublicKey(phantomPub);
            ref.invalidate(hasLocalSolanaSessionProvider);

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

                final providers = user.providerData.map((p) => p.providerId).toList();
                final provider = providers.contains('google.com') ? 'google.com' : 'password';

                final linkData = <String, dynamic>{
                  'uid': user.uid,
                  'email': user.email,
                  'provider': provider,
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
                  final provider = linkData?['provider'] as String?;

                  if (provider == 'google.com') {
                    // Google Sign-In Required
                    if (context.mounted) {
                      final proceed = await showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) {
                          return AlertDialog(
                            backgroundColor: isDarkMode ? AppColors.darkCard : Colors.white,
                            title: Text(
                              'Google Sign-In Required',
                              style: TextStyle(
                                color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                              ),
                            ),
                            content: Text(
                              'This wallet is linked to the Google account $email. Please sign in with Google to authorize this device.',
                              style: TextStyle(
                                color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('Sign in with Google'),
                              ),
                            ],
                          );
                        },
                      );
                      if (proceed == true) {
                        await ref.read(authControllerProvider).signInWithGoogle();
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
                      }
                    }
                  } else if (provider == 'password') {
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
                  } else {
                    // Legacy case (provider is null) — show choice dialog
                    if (context.mounted) {
                      final choice = await showDialog<String>(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) {
                          return AlertDialog(
                            backgroundColor: isDarkMode ? AppColors.darkCard : Colors.white,
                            title: Text(
                              'Authorize Device',
                              style: TextStyle(
                                color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                              ),
                            ),
                            content: Text(
                              'This wallet is linked to the email $email. Please choose how you want to authorize this device.',
                              style: TextStyle(
                                color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop('cancel'),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop('password'),
                                child: const Text('Use Password'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.of(ctx).pop('google'),
                                child: const Text('Sign in with Google'),
                              ),
                            ],
                          );
                        },
                      );

                      if (choice == 'google') {
                        await ref.read(authControllerProvider).signInWithGoogle();
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
                      } else if (choice == 'password') {
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
      GoRoute(
        path: '/onSignAndSendTransaction',
        name: 'on_sign_and_send_transaction',
        builder: (context, state) {
          final queryParams = state.uri.queryParameters;
          final error = queryParams['errorMessage'] ?? queryParams['errorCode'];
          final data = queryParams['data'];
          final nonce = queryParams['nonce'];

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final user = ref.read(userProvider);
            if (user != null) {
              NavigationNotifier.switchTab(ref, 'profile');
            }

            var keyBytes = ref.read(phantomSessionPrivateKeyProvider);
            var walletType = ref.read(connectingWalletTypeProvider);

            if (keyBytes == null) {
              keyBytes = await SecureStorageHelper.getPhantomSessionKey();
            }
            if (walletType == null) {
              walletType = await SecureStorageHelper.getConnectingWalletType();
            }

            walletType ??= 'phantom';

            // Clear session key state in RAM
            ref.read(phantomSessionPrivateKeyProvider.notifier).state = null;
            ref.read(connectingWalletTypeProvider.notifier).state = null;

            // Clear connecting wallet type in SecureStorage (keep persistent session key)
            await SecureStorageHelper.deleteConnectingWalletType();

            if (error != null) {
              debugPrint("Transaction signing error: $error");
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Transaction cancelled or failed: $error'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            final savedPhantomPub = await SecureStorageHelper.getPhantomEncryptionPublicKey();

            if (data == null || nonce == null || keyBytes == null || savedPhantomPub == null) {
              debugPrint("Missing required deep link parameters or session key.");
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Transaction failed: Missing decryption parameters.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            // Decrypt response
            final service = ref.read(phantomServiceProvider);
            final decrypted = service.decryptConnectResponse(
              phantomPubB58: savedPhantomPub,
              dataB58: data,
              nonceB58: nonce,
              sessionPrivateKeyBytes: keyBytes,
            );

            if (decrypted == null) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to decrypt transaction signature response.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            final signature = decrypted['signature'] as String?;
            if (signature == null || signature.isEmpty) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to retrieve transaction signature.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            // Show a progress indicator/dialog while verifying the transaction
            if (context.mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) => const AlertDialog(
                  content: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Verifying transaction on Solana network...',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            try {
              final confirmed = await service.confirmTransaction(signature);
              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pop(); // Close progress dialog
              }
              if (!confirmed) {
                throw Exception('Transaction confirmation timed out. Please check your wallet.');
              }
            } catch (rpcErr) {
              debugPrint("Solana RPC error verifying transaction: $rpcErr");
              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pop(); // Close progress dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Transaction verification failed: $rpcErr'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            // Successfully received transaction signature from wallet!
            final phpAmount = await SecureStorageHelper.getPendingDepositPhpAmount();
            final cryptoAmount = await SecureStorageHelper.getPendingDepositCryptoAmount();
            final currency = await SecureStorageHelper.getPendingDepositCurrency();

            // Clear pending deposit state
            await SecureStorageHelper.deletePendingDepositPhpAmount();
            await SecureStorageHelper.deletePendingDepositCryptoAmount();
            await SecureStorageHelper.deletePendingDepositCurrency();

            if (phpAmount == null || cryptoAmount == null || currency == null || user == null) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Transaction signature received, but pending deposit details were missing.'),
                    backgroundColor: Colors.amber,
                  ),
                );
              }
              return;
            }

            try {
              // Confirm & Update balance in Firestore and record the deposit transaction
              final repo = ref.read(transitRepositoryProvider);
              final userProfile = await repo.getUser(user.uid);
              if (userProfile != null) {
                final newBalance = userProfile.tyxBalance + phpAmount;
                await repo.updateTyxBalance(user.uid, newBalance);

                final txId = 'deposit_sol_$signature';
                await ref.read(firestoreProvider).collection('transactions').doc(txId).set({
                  'uid': user.uid,
                  'type': 'deposit',
                  'amount': phpAmount,
                  'title': 'Wallet Top-Up ($currency)',
                  'desc': 'Crypto deposit of ${cryptoAmount.toStringAsFixed(4)} $currency via Solana',
                  'method': 'Solana',
                  'solanaTxSignature': signature,
                  'createdAt': DateTime.now().millisecondsSinceEpoch,
                });

                ref.invalidate(userProfileProvider);
                ref.invalidate(userTransactionsProvider);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Successfully deposited ₱ ${phpAmount.toStringAsFixed(2)} via Solana ($currency)'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error updating wallet balance: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          });

          return const MainWrapper();
        },
      ),
      GoRoute(
        path: '/onSignTransaction',
        name: 'on_sign_transaction',
        builder: (context, state) {
          final queryParams = state.uri.queryParameters;
          final error = queryParams['errorMessage'] ?? queryParams['errorCode'];
          final data = queryParams['data'];
          final nonce = queryParams['nonce'];

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final user = ref.read(userProvider);
            if (user != null) {
              NavigationNotifier.switchTab(ref, 'profile');
            }

            var keyBytes = ref.read(phantomSessionPrivateKeyProvider);
            var walletType = ref.read(connectingWalletTypeProvider);

            if (keyBytes == null) {
              keyBytes = await SecureStorageHelper.getPhantomSessionKey();
            }
            if (walletType == null) {
              walletType = await SecureStorageHelper.getConnectingWalletType();
            }

            walletType ??= 'phantom';

            // Clear session key state in RAM
            ref.read(phantomSessionPrivateKeyProvider.notifier).state = null;
            ref.read(connectingWalletTypeProvider.notifier).state = null;

            // Clear connecting wallet type in SecureStorage (keep persistent session key)
            await SecureStorageHelper.deleteConnectingWalletType();

            if (error != null) {
              debugPrint("Transaction signing error: $error");
              final isSessionError = error.toString().contains('-32603') || error.toString().toLowerCase().contains('unexpected');
              final displayMessage = isSessionError
                  ? 'Transaction failed (Session expired or out of sync). Please disconnect and reconnect your wallet from the profile tab.'
                  : 'Transaction cancelled or failed: $error';
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(displayMessage),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
              return;
            }

            final savedPhantomPub = await SecureStorageHelper.getPhantomEncryptionPublicKey();

            if (data == null || nonce == null || keyBytes == null || savedPhantomPub == null) {
              debugPrint("Missing required deep link parameters or session key.");
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Transaction failed: Missing decryption parameters.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            // Decrypt response
            final service = ref.read(phantomServiceProvider);
            final decrypted = service.decryptConnectResponse(
              phantomPubB58: savedPhantomPub,
              dataB58: data,
              nonceB58: nonce,
              sessionPrivateKeyBytes: keyBytes,
            );

            if (decrypted == null) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to decrypt transaction signature response.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            final base58Tx = decrypted['transaction'] as String?;
            if (base58Tx == null || base58Tx.isEmpty) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to retrieve signed transaction from response.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            // Show a progress indicator/dialog while broadcasting and verifying the transaction
            if (context.mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) => const AlertDialog(
                  content: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Broadcasting and verifying transaction on Solana network...',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            String? signature;
            try {
              signature = await service.sendTransaction(base58Tx);
              final confirmed = await service.confirmTransaction(signature);
              if (!confirmed) {
                throw Exception('Transaction confirmation timed out. Please check your wallet.');
              }
            } catch (rpcErr) {
              debugPrint("Solana RPC error broadcasting transaction: $rpcErr");
              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pop(); // Close progress dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Transaction verification failed: $rpcErr'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            if (context.mounted) {
              Navigator.of(context, rootNavigator: true).pop(); // Close progress dialog
            }

            // Successfully received transaction signature from wallet!
            final phpAmount = await SecureStorageHelper.getPendingDepositPhpAmount();
            final cryptoAmount = await SecureStorageHelper.getPendingDepositCryptoAmount();
            final currency = await SecureStorageHelper.getPendingDepositCurrency();

            // Clear pending deposit state
            await SecureStorageHelper.deletePendingDepositPhpAmount();
            await SecureStorageHelper.deletePendingDepositCryptoAmount();
            await SecureStorageHelper.deletePendingDepositCurrency();

            if (phpAmount == null || cryptoAmount == null || currency == null || user == null) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Transaction broadcasted, but pending deposit details were missing.'),
                    backgroundColor: Colors.amber,
                  ),
                );
              }
              return;
            }

            try {
              // Confirm & Update balance in Firestore and record the deposit transaction
              final repo = ref.read(transitRepositoryProvider);
              final userProfile = await repo.getUser(user.uid);
              if (userProfile != null) {
                final newBalance = userProfile.tyxBalance + phpAmount;
                await repo.updateTyxBalance(user.uid, newBalance);

                final txId = 'deposit_sol_$signature';
                await ref.read(firestoreProvider).collection('transactions').doc(txId).set({
                  'uid': user.uid,
                  'type': 'deposit',
                  'amount': phpAmount,
                  'title': 'Wallet Top-Up ($currency)',
                  'desc': 'Crypto deposit of ${cryptoAmount.toStringAsFixed(4)} $currency via Solana',
                  'method': 'Solana',
                  'solanaTxSignature': signature,
                  'createdAt': DateTime.now().millisecondsSinceEpoch,
                });

                ref.invalidate(userProfileProvider);
                ref.invalidate(userTransactionsProvider);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Successfully deposited ₱ ${phpAmount.toStringAsFixed(2)} via Solana ($currency)'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error updating wallet balance: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
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
