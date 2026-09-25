import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Ongoing Job Application Restriction Guardrail (Shared & Web)', () {
    const workerUid = 'nyxian_123';

    test('ongoingJobRestrictionMessage matches exact required copy', () {
      expect(
        ongoingJobRestrictionMessage,
        equals(
          'You have an ongoing job to complete. Please complete your current task before applying for another job to avoid conflicts in your responsibilities.',
        ),
      );
    });

    test('Job.isTerminal correctly identifies terminal statuses including Abandoned and Admin_Cancelled', () {
      Job createWithStatus(String status) => Job(
            id: 'job_test',
            creatorId: 'emp_1',
            creatorName: 'Employer',
            creatorType: AccountType.employer,
            title: 'Test',
            description: 'Desc',
            category: JobCategory.others,
            categoryGroup: JobCategoryGroup.miscellaneousEvents,
            employmentType: 'Gig',
            dateRequirement: 'Today',
            timePreference: 'Morning',
            pricingType: 'Fixed',
            pricingValue: 500.0,
            locationType: 'On-site',
            createdAt: DateTime.now(),
            status: status,
          );

      expect(createWithStatus('Completed').isTerminal, isTrue);
      expect(createWithStatus('completed').isTerminal, isTrue);
      expect(createWithStatus('Cancelled').isTerminal, isTrue);
      expect(createWithStatus('cancelled').isTerminal, isTrue);
      expect(createWithStatus('Admin_Cancelled').isTerminal, isTrue);
      expect(createWithStatus('ADMIN_CANCELLED').isTerminal, isTrue);
      expect(createWithStatus('Abandoned').isTerminal, isTrue);
      expect(createWithStatus('abandoned').isTerminal, isTrue);

      expect(createWithStatus('Open').isTerminal, isFalse);
      expect(createWithStatus('Reviewing').isTerminal, isFalse);
      expect(createWithStatus('In Progress').isTerminal, isFalse);
    });

    test('job.isOngoingForNyxian returns true only when accepted and non-terminal', () {
      final activeJob = Job(
        id: 'job_active',
        creatorId: 'emp_1',
        creatorName: 'Employer',
        creatorType: AccountType.employer,
        title: 'Active Repair',
        description: 'Fixing pipes',
        category: JobCategory.plumber,
        categoryGroup: JobCategoryGroup.homeRepair,
        employmentType: 'Gig',
        dateRequirement: 'Today',
        timePreference: 'Morning',
        pricingType: 'Fixed',
        pricingValue: 1200.0,
        locationType: 'On-site',
        createdAt: DateTime.now(),
        status: 'In Progress',
        acceptedApplicantId: workerUid,
      );

      // Matches worker and active -> ongoing
      expect(activeJob.isOngoingForNyxian(workerUid), isTrue);

      // Other worker is accepted -> not ongoing for workerUid
      expect(activeJob.isOngoingForNyxian('other_worker'), isFalse);

      // Terminal statuses are not ongoing even if accepted
      expect(
        activeJob.copyWith(status: 'Completed').isOngoingForNyxian(workerUid),
        isFalse,
      );
      expect(
        activeJob.copyWith(status: 'Cancelled').isOngoingForNyxian(workerUid),
        isFalse,
      );
      expect(
        activeJob.copyWith(status: 'ADMIN_CANCELLED').isOngoingForNyxian(workerUid),
        isFalse,
      );
      expect(
        activeJob.copyWith(status: 'Abandoned').isOngoingForNyxian(workerUid),
        isFalse,
      );
    });

    test('Applied jobs without acceptedApplicantId do NOT count as ongoing obligation', () {
      final appliedJob = Job(
        id: 'job_applied',
        creatorId: 'emp_1',
        creatorName: 'Employer',
        creatorType: AccountType.employer,
        title: 'Open Job',
        description: 'Waiting for hire',
        category: JobCategory.others,
        categoryGroup: JobCategoryGroup.miscellaneousEvents,
        employmentType: 'Gig',
        dateRequirement: 'Today',
        timePreference: 'Morning',
        pricingType: 'Fixed',
        pricingValue: 600.0,
        locationType: 'On-site',
        createdAt: DateTime.now(),
        status: 'Open',
        applicantUids: [workerUid],
        acceptedApplicantId: null,
      );

      expect(appliedJob.isOngoingForNyxian(workerUid), isFalse);
    });

    test('Collection evaluation correctly calculates hasOngoingNyxianJob flag', () {
      final jobList = <Job>[
        Job(
          id: 'job_1',
          creatorId: 'emp_1',
          creatorName: 'Emp',
          creatorType: AccountType.employer,
          title: 'Job 1',
          description: '',
          category: JobCategory.others,
          categoryGroup: JobCategoryGroup.miscellaneousEvents,
          employmentType: 'Gig',
          dateRequirement: 'Today',
          timePreference: 'Morning',
          pricingType: 'Fixed',
          pricingValue: 500.0,
          locationType: 'On-site',
          createdAt: DateTime.now(),
          status: 'Completed',
          acceptedApplicantId: workerUid,
        ),
        Job(
          id: 'job_2',
          creatorId: 'emp_2',
          creatorName: 'Emp',
          creatorType: AccountType.employer,
          title: 'Job 2',
          description: '',
          category: JobCategory.others,
          categoryGroup: JobCategoryGroup.miscellaneousEvents,
          employmentType: 'Gig',
          dateRequirement: 'Today',
          timePreference: 'Morning',
          pricingType: 'Fixed',
          pricingValue: 700.0,
          locationType: 'On-site',
          createdAt: DateTime.now(),
          status: 'Cancelled',
          acceptedApplicantId: workerUid,
        ),
      ];

      // With only completed & cancelled jobs -> false
      bool hasOngoing = jobList.any((j) => j.isOngoingForNyxian(workerUid));
      expect(hasOngoing, isFalse);

      // Add in-progress job -> true
      final activeJob = Job(
        id: 'job_3',
        creatorId: 'emp_3',
        creatorName: 'Emp',
        creatorType: AccountType.employer,
        title: 'Job 3',
        description: '',
        category: JobCategory.others,
        categoryGroup: JobCategoryGroup.miscellaneousEvents,
        employmentType: 'Gig',
        dateRequirement: 'Today',
        timePreference: 'Morning',
        pricingType: 'Fixed',
        pricingValue: 1500.0,
        locationType: 'On-site',
        createdAt: DateTime.now(),
        status: 'In Progress',
        acceptedApplicantId: workerUid,
      );
      jobList.add(activeJob);

      hasOngoing = jobList.any((j) => j.isOngoingForNyxian(workerUid));
      expect(hasOngoing, isTrue);
    });
  });

  group('Job Application Counter-Offer Restrictions (80% - 150%) (Web & Shared)', () {
    const double originalOffer = 1000.0;

    test('valid counter offers between 80% and 150% pass validation', () {
      final minRes = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: '800',
        isCounterOffer: true,
      );
      expect(minRes.isValid, isTrue);
      expect(minRes.sanitizedRate, equals(800.0));

      final midRes = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: 1200.0,
        isCounterOffer: true,
      );
      expect(midRes.isValid, isTrue);
      expect(midRes.sanitizedRate, equals(1200.0));

      final maxRes = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: '₱1,500',
        isCounterOffer: true,
      );
      expect(maxRes.isValid, isTrue);
      expect(maxRes.sanitizedRate, equals(1500.0));
    });

    test('counter offers below 80% are rejected with exact error message', () {
      final res = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: 799.0,
        isCounterOffer: true,
      );
      expect(res.isValid, isFalse);
      expect(
        res.errorMessage,
        equals("Your counter offer must be between ₱800 and ₱1,500 based on the employer's original offer of ₱1,000."),
      );
    });

    test('counter offers above 150% are rejected with exact error message', () {
      final res = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: 1501.0,
        isCounterOffer: true,
      );
      expect(res.isValid, isFalse);
      expect(
        res.errorMessage,
        equals("Your counter offer must be between ₱800 and ₱1,500 based on the employer's original offer of ₱1,000."),
      );
    });

    test('counter offers with ₱0 or negative are rejected', () {
      final resZero = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: '0',
        isCounterOffer: true,
      );
      expect(resZero.isValid, isFalse);
      expect(resZero.errorMessage, equals('Counter offer cannot be ₱0 or negative.'));

      final resNeg = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: -100.0,
        isCounterOffer: true,
      );
      expect(resNeg.isValid, isFalse);
      expect(resNeg.errorMessage, equals('Counter offer cannot be ₱0 or negative.'));
    });

    test('blank, whitespace, or invalid string inputs are rejected', () {
      final resBlank = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: '   ',
        isCounterOffer: true,
      );
      expect(resBlank.isValid, isFalse);
      expect(resBlank.errorMessage, equals('Please enter a valid counter offer amount.'));

      final resText = JobCounterOfferValidator.validate(
        originalOffer: originalOffer,
        counterOfferInput: 'invalid_price',
        isCounterOffer: true,
      );
      expect(resText.isValid, isFalse);
      expect(resText.errorMessage, equals('Please enter a valid counter offer amount.'));
    });

    test('permitted range display text formats correctly', () {
      final display = JobCounterOfferValidator.getPermittedRangeDisplay(originalOffer);
      expect(
        display,
        equals("Allowed counter offer: ₱800 – ₱1,500 (80% – 150% of original offer ₱1,000)"),
      );
    });
  });
}
