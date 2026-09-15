import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Job Edit Contract & Pre-Hire Guardrails (Web & Shared)', () {
    test('Open job with 0 applicants is editable and pre-hire', () {
      final job = Job(
        id: 'job_open_1',
        creatorId: 'emp_1',
        creatorName: 'Employer One',
        creatorType: AccountType.employer,
        title: 'Move Furniture',
        description: 'Need help moving sofa',
        category: JobCategory.others,
        categoryGroup: JobCategoryGroup.miscellaneousEvents,
        employmentType: 'Gig',
        dateRequirement: 'Flexible',
        timePreference: 'Morning',
        pricingType: 'Fixed',
        pricingValue: 500.0,
        locationType: 'On-site',
        createdAt: DateTime.now(),
        status: 'Open',
        applicantCount: 0,
        acceptedApplicantId: null,
      );

      expect(job.isPreHire, isTrue);
      expect(job.canEdit, isTrue);
      expect(job.isEdited, isFalse);
      expect(job.formattedEditedDate, isNull);
    });

    test('Reviewing job with applicants is editable and pre-hire before hire', () {
      final job = Job(
        id: 'job_reviewing_2',
        creatorId: 'emp_1',
        creatorName: 'Employer One',
        creatorType: AccountType.employer,
        title: 'Gardening Help',
        description: 'Mow lawn',
        category: JobCategory.plumber,
        categoryGroup: JobCategoryGroup.homeRepair,
        employmentType: 'Gig',
        dateRequirement: 'Flexible',
        timePreference: 'Morning',
        pricingType: 'Fixed',
        pricingValue: 800.0,
        locationType: 'On-site',
        createdAt: DateTime.now(),
        status: 'Reviewing',
        applicantCount: 3,
        acceptedApplicantId: null,
      );

      expect(job.isPreHire, isTrue);
      expect(job.canEdit, isTrue);
    });

    test('Strict Post-Hire Lockout: acceptedApplicantId locks editing immediately', () {
      final job = Job(
        id: 'job_hired_3',
        creatorId: 'emp_1',
        creatorName: 'Employer One',
        creatorType: AccountType.employer,
        title: 'Roof Repair',
        description: 'Fix tiles',
        category: JobCategory.others,
        categoryGroup: JobCategoryGroup.miscellaneousEvents,
        employmentType: 'Gig',
        dateRequirement: 'Flexible',
        timePreference: 'Morning',
        pricingType: 'Fixed',
        pricingValue: 3000.0,
        locationType: 'On-site',
        createdAt: DateTime.now(),
        status: 'In Progress',
        applicantCount: 5,
        acceptedApplicantId: 'nyxian_accepted_42',
      );

      expect(job.isPreHire, isFalse);
      expect(job.canEdit, isFalse);
    });

    test('Status lockout: In Progress, Done, Completed, Cancelled cannot be edited even if acceptedApplicantId is null', () {
      final lockedStatuses = ['In Progress', 'Done', 'Completed', 'Cancelled', 'Admin Cancelled'];

      for (final st in lockedStatuses) {
        final job = Job(
          id: 'job_status_$st',
          creatorId: 'emp_1',
          creatorName: 'Employer One',
          creatorType: AccountType.employer,
          title: 'Test Job',
          description: 'Desc',
          category: JobCategory.others,
          categoryGroup: JobCategoryGroup.miscellaneousEvents,
          employmentType: 'Gig',
          dateRequirement: 'Flexible',
          timePreference: 'Morning',
          pricingType: 'Fixed',
          pricingValue: 1000.0,
          locationType: 'On-site',
          createdAt: DateTime.now(),
          status: st,
          acceptedApplicantId: null,
        );

        expect(job.isPreHire, isFalse, reason: 'Status $st must not be pre-hire');
        expect(job.canEdit, isFalse, reason: 'Status $st must not be editable');
      }
    });

    test('Edited job displays isEdited and formattedEditedDate correctly', () {
      final editedDate = DateTime(2026, 9, 5, 14, 30);
      final job = Job(
        id: 'job_edited_4',
        creatorId: 'emp_1',
        creatorName: 'Employer One',
        creatorType: AccountType.employer,
        title: 'House Cleaning',
        description: 'Updated scope with supplies',
        category: JobCategory.houseCleaning,
        categoryGroup: JobCategoryGroup.cleaning,
        employmentType: 'Gig',
        dateRequirement: 'Flexible',
        timePreference: 'Morning',
        pricingType: 'Fixed',
        pricingValue: 1200.0,
        locationType: 'On-site',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        status: 'Reviewing',
        applicantCount: 2,
        acceptedApplicantId: null,
        updatedAt: editedDate,
      );

      expect(job.isEdited, isTrue);
      expect(job.formattedEditedDate, isNotNull);
      expect(job.formattedEditedDate, contains('Sep 5, 2026'));
    });

    test('Whitelist validation: only allowed keys are recognized', () {
      const allowedKeys = [
        'title',
        'description',
        'category',
        'categoryGroup',
        'dateRequirement',
        'jobDate',
        'timePreference',
        'locationType',
        'address',
        'landmark',
        'pickupAddress',
        'destinationAddress',
        'pickupLat',
        'pickupLng',
        'destinationLat',
        'destinationLng',
        'imageUrls',
        'updatedAt',
      ];

      final inputUpdates = {
        'title': 'New Title',
        'description': 'New Description',
        'landmark': 'Next to 7-Eleven',
        'pricingValue': 99999.0, // FORBIDDEN
        'creatorId': 'attacker_id', // FORBIDDEN
        'acceptedApplicantId': 'injected_worker', // FORBIDDEN
        'status': 'Completed', // FORBIDDEN
      };

      final sanitized = <String, dynamic>{};
      for (final key in allowedKeys) {
        if (inputUpdates.containsKey(key)) {
          sanitized[key] = inputUpdates[key];
        }
      }

      expect(sanitized.containsKey('title'), isTrue);
      expect(sanitized.containsKey('description'), isTrue);
      expect(sanitized.containsKey('landmark'), isTrue);
      expect(sanitized.containsKey('pricingValue'), isFalse);
      expect(sanitized.containsKey('creatorId'), isFalse);
      expect(sanitized.containsKey('acceptedApplicantId'), isFalse);
      expect(sanitized.containsKey('status'), isFalse);
    });
  });
}
