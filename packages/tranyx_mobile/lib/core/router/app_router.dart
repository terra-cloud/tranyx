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
import 'package:tranyx_mobile/core/services/onchain_credit.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';

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

            if (user != null) {
              try {
                // ── 1:1 guard: check if this wallet is already owned by another user ──
                final existingDoc = await ref
                    .read(firestoreProvider)
                    .collection('walletLinks')
                    .doc(userSolanaPublicKey)
                    .get();

                if (existingDoc.exists) {
                  final existingUid = existingDoc.data()?['uid'] as String?;
                  if (existingUid != null && existingUid != user.uid) {
                    if (context.mounted) {
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

                // One-wallet-one-account index and profile key in one batch, so a rejected link never
                // leaves walletPublicKey set without its walletLinks doc. uid + linkedAt only: never
                // credentials (KAN-124).
                final firestore = ref.read(firestoreProvider);
                await (firestore.batch()
                      ..set(firestore.collection('walletLinks').doc(userSolanaPublicKey),
                          {'uid': user.uid, 'linkedAt': DateTime.now().millisecondsSinceEpoch})
                      ..update(firestore.collection('users').doc(user.uid), {
                        'walletPublicKey': userSolanaPublicKey,
                        'connectedWalletType': walletType,
                      }))
                    .commit();
                ref.invalidate(userProfileProvider);

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
              // Wallet sign-in was removed (KAN-124): it signed users in with credentials stored in
              // walletLinks. Keep the key so it links after a normal email/Google sign-in.
              ref.read(pendingWalletPublicKeyProvider.notifier).state = userSolanaPublicKey;
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Wallet sign-in is turned off. Sign in with email or Google and your wallet will be linked.',
                    ),
                    backgroundColor: Colors.indigo,
                  ),
                );
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

            keyBytes ??= await SecureStorageHelper.getPhantomSessionKey();
            walletType ??= await SecureStorageHelper.getConnectingWalletType();

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
              {
                // Credit once per signature: shared on-chain marker + deposit marker +
                // balance increment in one Firestore transaction.
                (await creditOnchainDeposit(
                  firestore: ref.read(firestoreProvider),
                  uid: user.uid,
                  signature: signature,
                  isUsdt: currency.toUpperCase() == 'USDT',
                )).throwIfHeldElsewhere(signature);

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

            keyBytes ??= await SecureStorageHelper.getPhantomSessionKey();
            walletType ??= await SecureStorageHelper.getConnectingWalletType();

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
            final pendingAction = await SecureStorageHelper.getPendingAction();
            await SecureStorageHelper.deletePendingAction();

            if (pendingAction == 'subscription') {
              final subType = await SecureStorageHelper.getPendingSubscriptionType();
              await SecureStorageHelper.deletePendingSubscriptionType();

              final phpAmount = await SecureStorageHelper.getPendingDepositPhpAmount();
              final cryptoAmount = await SecureStorageHelper.getPendingDepositCryptoAmount();

              await SecureStorageHelper.deletePendingDepositPhpAmount();
              await SecureStorageHelper.deletePendingDepositCryptoAmount();
              await SecureStorageHelper.deletePendingDepositCurrency();

              if (phpAmount == null || cryptoAmount == null || user == null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Transaction broadcasted, but subscription details were missing.'),
                      backgroundColor: Colors.amber,
                    ),
                  );
                }
                return;
              }

              try {
                // Activate once per signature; expiry extends from max(now, premiumUntil).
                (await activateSubscriptionOnce(
                  firestore: ref.read(firestoreProvider),
                  uid: user.uid,
                  signature: signature,
                  plan: subType == 'yearly' ? 'yearly' : 'monthly',
                )).throwIfHeldElsewhere(signature);

                ref.invalidate(userProfileProvider);
                ref.invalidate(userTransactionsProvider);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Successfully subscribed to Hybrid PRO (${subType == 'yearly' ? 'Yearly' : 'Monthly'})!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error activating subscription: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
              return;
            }

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
              {
                // Credit once per signature: shared on-chain marker + deposit marker +
                // balance increment in one Firestore transaction.
                (await creditOnchainDeposit(
                  firestore: ref.read(firestoreProvider),
                  uid: user.uid,
                  signature: signature,
                  isUsdt: currency.toUpperCase() == 'USDT',
                )).throwIfHeldElsewhere(signature);

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

