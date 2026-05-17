import 'package:flutter_riverpod/legacy.dart';
import 'package:tranyx_mobile/core/utils/enums.dart';
import 'package:tranyx_mobile/features/jobs/models/job.dart';

final jobsViewProvider = StateProvider<String>((ref) => 'list');
final selectedJobProvider = StateProvider<Job?>((ref) => null);
final isCounterOfferProvider = StateProvider<bool>((ref) => false);

final newJobTitleProvider = StateProvider<String>((ref) => '');
final newJobDescProvider = StateProvider<String>((ref) => '');
final selectedCategoryProvider = StateProvider<JobCategory?>((ref) => null);
final selectedCategoryGroupProvider = StateProvider<JobCategoryGroup?>(
  (ref) => null,
);
final categoryPickerStepProvider = StateProvider<int>(
  (ref) => 1,
); // 1: Groups, 2: Categories
final jobSearchFilterProvider = StateProvider<JobCategory?>((ref) => null);
final searchQueryProvider = StateProvider<String>((ref) => '');

final isGeneratingTitleProvider = StateProvider<bool>((ref) => false);
final isGeneratingDescProvider = StateProvider<bool>((ref) => false);
final isValidatingJobProvider = StateProvider<bool>((ref) => false);
final titleCategoryMismatchProvider = StateProvider<bool>((ref) => false);
final createJobStepProvider = StateProvider<int>((ref) => 1);
final dateRequirementProvider = StateProvider<String>(
  (ref) => 'Flexible',
); // On Date, Before, Flexible

final coverNoteProvider = StateProvider<String>((ref) => '');
final isGeneratingCoverProvider = StateProvider<bool>((ref) => false);

final replyTextProvider = StateProvider<String>((ref) => '');
final activeReplyIdProvider = StateProvider<String?>((ref) => null);
final newQuestionTextProvider = StateProvider<String>((ref) => '');

final employmentTypeProvider = StateProvider<String>((ref) => 'One-time Gig');
final jobDateProvider = StateProvider<DateTime?>((ref) => null);
final timePreferenceProvider = StateProvider<String>(
  (ref) => 'Morning',
); // Morning, Midday, Afternoon, Evening
final pricingTypeProvider = StateProvider<String>((ref) => 'Package (Fixed)');
final pricingValueProvider = StateProvider<double>((ref) => 0.0);

final workLocationTypeProvider = StateProvider<String>(
  (ref) => 'On-site',
); // On-site, Remote
final jobLandmarkProvider = StateProvider<String>((ref) => '');
final jobAddressProvider = StateProvider<String>((ref) => '');
