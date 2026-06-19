import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tranyx_mobile/features/navigation/presentation/main_wrapper.dart';
import 'package:tranyx_mobile/features/navigation/providers/navigation_provider.dart';
import 'package:tranyx_mobile/features/jobs/providers/jobs_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/jobs/models/job.dart';
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';

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
                final doc = await ref.read(firestoreProvider).collection('jobs').doc(jobId).get();
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
            // Switch to profile tab where payment/wallet UI is located
            NavigationNotifier.switchTab(ref, 'profile');
            
            final keyBytes = ref.read(phantomSessionPrivateKeyProvider);
            final walletType = ref.read(connectingWalletTypeProvider) ?? 'phantom';

            // Clear session key state
            ref.read(phantomSessionPrivateKeyProvider.notifier).state = null;
            ref.read(connectingWalletTypeProvider.notifier).state = null;

            if (error != null) {
              debugPrint("Phantom connection error: $error");
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Wallet connection cancelled or failed: $error'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            if (phantomPub == null || data == null || nonce == null || keyBytes == null) {
              debugPrint("Missing required deep link parameters or session key is missing.");
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Wallet connection failed: Missing parameters.'),
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
                    content: Text('Failed to retrieve public key from decrypted payload.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }

            final user = ref.read(userProvider);
            if (user != null) {
              try {
                await ref.read(firestoreProvider).collection('users').doc(user.uid).update({
                  'walletPublicKey': userSolanaPublicKey,
                  'connectedWalletType': walletType,
                });
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
            }
          });

          return const MainWrapper();
        },
      ),
    ],
  );
});

