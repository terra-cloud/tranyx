import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tranyx_mobile/features/navigation/presentation/main_wrapper.dart';
import 'package:tranyx_mobile/features/navigation/providers/navigation_provider.dart';
import 'package:tranyx_mobile/features/jobs/providers/jobs_provider.dart';

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

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (jobId != null) {
              // Switch to the jobs tab — the stream providers will load the job
              NavigationNotifier.switchTab(ref, 'jobs');
              // Navigate to the list; the user can select the job from the feed
              ref.read(jobsViewProvider.notifier).state = 'list';
              ref.read(selectedJobProvider.notifier).state = null;
            }
          });

          return const MainWrapper();
        },
      ),
    ],
  );
});
