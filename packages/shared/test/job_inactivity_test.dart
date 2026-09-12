import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('Job Inactivity & Abandonment Model Tests', () {
    test('Job isInactive detects >= 48 hours without update', () {
      final now = DateTime(2026, 9, 12, 12, 0);

      final freshJob = Job(
        id: 'job_fresh',
        creatorId: 'emp_1',
        creatorName: 'Employer',
        creatorType: AccountType.employer,
        title: 'Active Job',
        description: 'Test',
        category: JobCategory.others,
        categoryGroup: JobCategoryGroup.miscellaneousEvents,
        employmentType: 'oneTime',
        dateRequirement: 'flexible',
        timePreference: 'morning',
        pricingType: 'fixed',
        pricingValue: 500,
        locationType: 'onSite',
        createdAt: now.subtract(const Duration(hours: 24)),
        updatedAt: now.subtract(const Duration(hours: 12)),
      );

      expect(freshJob.isInactive(thresholdHours: 48, currentTime: now), isFalse);

      final staleJob = Job(
        id: 'job_stale',
        creatorId: 'emp_1',
        creatorName: 'Employer',
        creatorType: AccountType.employer,
        title: 'Stale Job',
        description: 'Test',
        category: JobCategory.others,
        categoryGroup: JobCategoryGroup.miscellaneousEvents,
        employmentType: 'oneTime',
        dateRequirement: 'flexible',
        timePreference: 'morning',
        pricingType: 'fixed',
        pricingValue: 500,
        locationType: 'onSite',
        createdAt: now.subtract(const Duration(hours: 72)),
        updatedAt: now.subtract(const Duration(hours: 49)),
      );

      expect(staleJob.isInactive(thresholdHours: 48, currentTime: now), isTrue);

      final staleByCreationJob = Job(
        id: 'job_stale_no_updated_at',
        creatorId: 'emp_1',
        creatorName: 'Employer',
        creatorType: AccountType.employer,
        title: 'Stale by creation',
        description: 'Test',
        category: JobCategory.others,
        categoryGroup: JobCategoryGroup.miscellaneousEvents,
        employmentType: 'oneTime',
        dateRequirement: 'flexible',
        timePreference: 'morning',
        pricingType: 'fixed',
        pricingValue: 500,
        locationType: 'onSite',
        createdAt: now.subtract(const Duration(hours: 50)),
        updatedAt: null,
      );

      expect(staleByCreationJob.isInactive(thresholdHours: 48, currentTime: now), isTrue);
    });

    test('Job isAbandoned matches status case-insensitively', () {
      final job1 = Job(
        id: 'j1',
        creatorId: 'emp_1',
        creatorName: 'Emp',
        creatorType: AccountType.employer,
        title: 'Title',
        description: 'Desc',
        category: JobCategory.others,
        categoryGroup: JobCategoryGroup.miscellaneousEvents,
        employmentType: 'oneTime',
        dateRequirement: 'flexible',
        timePreference: 'morning',
        pricingType: 'fixed',
        pricingValue: 100,
        locationType: 'onSite',
        createdAt: DateTime.now(),
        status: 'Abandoned',
      );

      expect(job1.isAbandoned, isTrue);

      final job2 = job1.copyWith(status: 'In Progress');
      expect(job2.isAbandoned, isFalse);
    });

    test('UserProfile abandonedJobs serializes and deserializes properly', () {
      final profile = UserProfile(
        uid: 'user_1',
        name: 'Worker',
        email: 'worker@tranyx.com',
        accountType: AccountType.nyxian,
        abandonedJobs: 3,
      );

      expect(profile.abandonedJobs, equals(3));

      final map = profile.toMap();
      expect(map['abandonedJobs'], equals(3));

      final deserialized = UserProfile.fromMap('user_1', map);
      expect(deserialized.abandonedJobs, equals(3));

      final updated = deserialized.copyWith(abandonedJobs: 4);
      expect(updated.abandonedJobs, equals(4));
    });
  });
}
