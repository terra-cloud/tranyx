import 'package:flutter_riverpod/legacy.dart';
import 'package:tranyx_mobile/features/profile/providers/profile_provider.dart';
import 'package:tranyx_mobile/features/jobs/providers/jobs_provider.dart';

final activeTabProvider = StateProvider<String>((ref) => 'home');

class NavigationNotifier {
  static void switchTab(dynamic ref, String tab) {
    ref.read(activeTabProvider.notifier).state = tab;
    if (tab != 'profile') ref.read(profileViewProvider.notifier).state = 'main';
    if (tab != 'jobs') ref.read(jobsViewProvider.notifier).state = 'list';
  }
}
