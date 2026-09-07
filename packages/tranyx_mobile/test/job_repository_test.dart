import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart' hide JobQuestion;
import 'package:tranyx_mobile/features/jobs/providers/job_repository.dart';
import 'package:tranyx_mobile/features/jobs/models/job_question.dart';
import 'helpers/fake_firestore.dart';

void main() {
  group('JobRepository Collection & Flow Integration Tests', () {
    late FakeFirebaseFirestore firestore;
    late JobRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = JobRepository(firestore);
    });

    test('Verify job creation & listing collection references', () async {
      firestore.db['users/employer123'] = {
        'uid': 'employer123',
        'name': 'Test Employer',
        'tyxBalance': 2000.0,
      };

      final job = Job(
        id: 'job123',
        creatorId: 'employer123',
        creatorName: 'Test Employer',
        creatorType: AccountType.employer,
        title: 'Need Plumber',
        description: 'Fixing kitchen sink leak',
        category: JobCategory.plumber,
        categoryGroup: JobCategoryGroup.homeRepair,
        employmentType: 'Gig',
        dateRequirement: 'Today',
        timePreference: 'Morning',
        pricingType: 'Fixed',
        pricingValue: 1500.0,
        locationType: 'On-site',
        createdAt: DateTime.now(),
        status: 'Open',
      );

      await repo.createJob(job);

      final doc = await firestore.collection('jobs').doc('job123').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['title'], equals('Need Plumber'));
      expect(doc.data()!['creatorId'], equals('employer123'));

      expect(firestore.collectionQueries, contains('jobs'));
    });

    test('Verify apply to job flow updates job stats and creates application doc', () async {
      // 1. Post job first
      firestore.db['jobs/job123'] = {
        'id': 'job123',
        'creatorId': 'employer123',
        'title': 'Need Plumber',
        'applicantCount': 0,
        'applicantUids': <String>[],
        'recentApplicantPhotos': <String>[],
      };

      final application = JobApplication(
        id: 'app123',
        jobId: 'job123',
        applicantUid: 'nyxian123',
        applicantName: 'Professional Plumber',
        applicantPhotoUrl: 'plumber.png',
        coverNote: 'I can fix it quickly.',
        proposalRate: 1500.0,
        isCounterOffer: false,
        createdAt: DateTime.now(),
      );

      // 2. Apply to job
      await repo.applyToJob(application);

      // Verify job stats updated
      final jobDoc = await firestore.collection('jobs').doc('job123').get();
      expect(jobDoc.data()!['applicantCount'], equals(1));
      expect(List<String>.from(jobDoc.data()!['applicantUids']), contains('nyxian123'));
      expect(List<String>.from(jobDoc.data()!['recentApplicantPhotos']), contains('plumber.png'));

      // Verify application document created
      final appDoc = await firestore
          .collection('jobs')
          .doc('job123')
          .collection('applications')
          .doc('nyxian123')
          .get();
      expect(appDoc.exists, isTrue);
      expect(appDoc.data()!['applicantName'], equals('Professional Plumber'));
      expect(appDoc.data()!['proposalRate'], equals(1500.0));

      expect(firestore.collectionQueries, contains('jobs'));
    });

    test('Verify job questions and answers subcollections', () async {
      firestore.db['jobs/job123'] = {
        'id': 'job123',
        'title': 'Need Plumber',
      };

      final question = JobQuestion(
        id: '',
        jobId: 'job123',
        authorId: 'user123',
        authorName: 'Curious User',
        questionText: 'Is the material provided?',
        createdAt: DateTime.now(),
      );

      // 1. Add question
      await repo.addJobQuestion('job123', question);

      final qDocs = await firestore.collection('jobs').doc('job123').collection('questions').get();
      expect(qDocs.docs.length, equals(1));
      expect(qDocs.docs.first.data()['questionText'], equals('Is the material provided?'));
      final questionId = qDocs.docs.first.id;

      // 2. Answer question
      await repo.answerJobQuestion('job123', questionId, 'Yes, materials are on site.');

      final updatedQDoc = await firestore
          .collection('jobs')
          .doc('job123')
          .collection('questions')
          .doc(questionId)
          .get();
      expect(updatedQDoc.data()!['answerText'], equals('Yes, materials are on site.'));
      expect(updatedQDoc.data()!['answeredAt'], isNotNull);

      expect(firestore.collectionQueries, contains('jobs'));
    });

    test('Verify denormalized user photo updates across jobs, applications, and questions', () async {
      // 1. Setup initial DB with old photo URL
      firestore.db['jobs/job1'] = {
        'id': 'job1',
        'creatorId': 'user123',
        'creatorPhotoUrl': 'old_photo.png',
        'applicantUids': ['user123'],
        'recentApplicantPhotos': ['old_photo.png'],
      };
      
      // Application document in subcollection
      firestore.db['jobs/job2/applications/user123'] = {
        'id': 'user123',
        'applicantUid': 'user123',
        'applicantPhotoUrl': 'old_photo.png',
      };

      // Question document in subcollection
      firestore.db['jobs/job3/questions/q1'] = {
        'jobId': 'job3',
        'authorId': 'user123',
        'authorPhotoUrl': 'old_photo.png',
      };

      // 2. Run update
      await repo.updateUserPhotoInDenormalizedLocations(
        'user123',
        'new_photo.png',
        oldPhotoUrl: 'old_photo.png',
      );

      // Verify all documents updated to new photo url
      final jobDoc = await firestore.collection('jobs').doc('job1').get();
      expect(jobDoc.data()!['creatorPhotoUrl'], equals('new_photo.png'));
      expect(List<String>.from(jobDoc.data()!['recentApplicantPhotos']), contains('new_photo.png'));

      final appDoc = await firestore
          .collection('jobs')
          .doc('job2')
          .collection('applications')
          .doc('user123')
          .get();
      expect(appDoc.data()!['applicantPhotoUrl'], equals('new_photo.png'));

      final qDoc = await firestore
          .collection('jobs')
          .doc('job3')
          .collection('questions')
          .doc('q1')
          .get();
      expect(qDoc.data()!['authorPhotoUrl'], equals('new_photo.png'));

      expect(firestore.collectionQueries, contains('jobs'));
      expect(firestore.collectionQueries, contains('applications'));
      expect(firestore.collectionQueries, contains('questions'));
    });

    test('Verify completeJob releases escrow and processes correct payouts & fees', () async {
      // 1. Setup initial DB state
      firestore.db['users/employer123'] = {
        'uid': 'employer123',
        'name': 'Test Employer',
        'tyxBalance': 5000.0,
      };

      firestore.db['users/nyxian123'] = {
        'uid': 'nyxian123',
        'name': 'Test Nyxian',
        'tyxBalance': 1000.0,
        'jobsDone': 0,
        'totalEarned': 0.0,
        'completedGigsCount': 0,
      };

      firestore.db['jobs/job123'] = {
        'id': 'job123',
        'title': 'Plumbing job',
        'status': 'In Progress',
        'pricingValue': 2000.0,
        'acceptedApplicantId': 'nyxian123',
        'creatorId': 'employer123',
        'hasTracker': false,
        'completionCode': '123456',
      };

      firestore.db['escrow/job123'] = {
        'amount': 2000.0,
        'employerId': 'employer123',
        'status': 'held',
      };

      // 2. Complete job (worker enters the code '123456')
      await repo.completeJob(
        jobId: 'job123',
        verificationCodeEntered: '123456',
        currentUserUid: 'nyxian123', // worker triggers verification
        currentUserName: 'Test Nyxian',
      );

      // 3. Assertions
      // Verify job status is Completed
      final jobDoc = await firestore.collection('jobs').doc('job123').get();
      expect(jobDoc.data()!['status'], equals('Completed'));

      // Verify escrow document is deleted
      final escrowDoc = await firestore.collection('escrow').doc('job123').get();
      expect(escrowDoc.exists, isFalse);

      // Verify Nyxian balance and stats
      // 3% Platform fee = 60. Payout = 2000 - 60 = 1940. New balance = 1000 + 1940 = 2940.
      final nyxDoc = await firestore.collection('users').doc('nyxian123').get();
      expect(nyxDoc.data()!['tyxBalance'], equals(2940.0));
      expect(nyxDoc.data()!['jobsDone'], equals(1));
      expect(nyxDoc.data()!['totalEarned'], equals(1940.0));
      expect(nyxDoc.data()!['completedGigsCount'], equals(1));

      // Verify Employer balance
      // 7% tx + 3% conv = 10% total fees = 200. New balance = 5000 - 200 = 4800.
      final empDoc = await firestore.collection('users').doc('employer123').get();
      expect(empDoc.data()!['tyxBalance'], equals(4800.0));

      // Verify Platform Fees
      // Total company income = 3% commission (60) + 7% tx (140) + 3% conv (60) = 260.
      final feeDoc = await firestore.collection('platform_fees').doc('job123').get();
      expect(feeDoc.exists, isTrue);
      expect(feeDoc.data()!['amount'], equals(260.0));
      expect(feeDoc.data()!['commissionFee'], equals(60.0));
      expect(feeDoc.data()!['transactionFee'], equals(140.0));
      expect(feeDoc.data()!['convenienceFee'], equals(60.0));
      expect(feeDoc.data()!['employerFees'], equals(200.0));
      expect(feeDoc.data()!['nyxianFee'], equals(60.0));

      // Verify Transactions logged
      final payoutTx = await firestore.collection('transactions').doc('payout_nyx_job123').get();
      expect(payoutTx.exists, isTrue);
      expect(payoutTx.data()!['amount'], equals(1940.0));
      expect(payoutTx.data()!['type'], equals('payout'));

      final feeTx = await firestore.collection('transactions').doc('fees_emp_job123').get();
      expect(feeTx.exists, isTrue);
      expect(feeTx.data()!['amount'], equals(200.0));
      expect(feeTx.data()!['type'], equals('fee_deduction'));
    });

    test('Verify submitJobRating updates rating, review subcollection, and job rated fields', () async {
      // 1. Setup initial DB state
      firestore.db['users/nyxian123'] = {
        'uid': 'nyxian123',
        'name': 'Test Nyxian',
        'rating': 4.0,
        'ratingCount': 1,
      };

      firestore.db['jobs/job123'] = {
        'id': 'job123',
        'title': 'Plumbing job',
        'status': 'Completed',
        'employerRated': false,
        'nyxianRated': false,
      };

      // 2. Submit rating (employer rates worker with 5 stars)
      await repo.submitJobRating(
        jobId: 'job123',
        targetId: 'nyxian123',
        reviewerUid: 'employer123',
        reviewerName: 'Test Employer',
        score: 5,
        comment: 'Great work!',
        currentViewMode: AccountType.employer,
      );

      // 3. Assertions
      // New rating = ((4.0 * 1) + 5) / 2 = 4.5
      final nyxDoc = await firestore.collection('users').doc('nyxian123').get();
      expect(nyxDoc.data()!['rating'], equals(4.5));
      expect(nyxDoc.data()!['ratingCount'], equals(2));

      // Verify review subcollection record
      final reviewDoc = await firestore
          .collection('users')
          .doc('nyxian123')
          .collection('reviews')
          .doc('job123')
          .get();
      expect(reviewDoc.exists, isTrue);
      expect(reviewDoc.data()!['score'], equals(5));
      expect(reviewDoc.data()!['comment'], equals('Great work!'));
      expect(reviewDoc.data()!['reviewerId'], equals('employer123'));

      // Verify job doc updated
      final jobDoc = await firestore.collection('jobs').doc('job123').get();
      expect(jobDoc.data()!['employerRated'], isTrue);
      expect(jobDoc.data()!['nyxianRated'], isFalse);
    });

    test('TC-CNCL-01 & TC-CNCL-02: Unilateral cancel when open -> 100% refund, CANCELLED, pending bids rejected, audit logged', () async {
      // Setup initial DB state
      firestore.db['users/employer123'] = {
        'uid': 'employer123',
        'name': 'Test Employer',
        'tyxBalance': 5000.0,
      };

      firestore.db['jobs/job123'] = {
        'id': 'job123',
        'creatorId': 'employer123',
        'title': 'Plumbing Help',
        'status': 'Open',
        'applicantCount': 2,
        'applicantUids': ['applicant1', 'applicant2'],
      };

      firestore.db['jobs/job123/applications/applicant1'] = {
        'jobId': 'job123',
        'applicantUid': 'applicant1',
        'status': 'PENDING',
      };

      firestore.db['jobs/job123/applications/applicant2'] = {
        'jobId': 'job123',
        'applicantUid': 'applicant2',
        'status': 'PENDING',
      };

      firestore.db['escrow/job123'] = {
        'amount': 2000.0,
        'employerId': 'employer123',
        'status': 'held',
      };

      // Employer cancels open job
      await repo.cancelJob(
        jobId: 'job123',
        currentUserUid: 'employer123',
      );

      // Verify job status is Cancelled
      final jobDoc = await firestore.collection('jobs').doc('job123').get();
      expect(jobDoc.data()!['status'], equals('Cancelled'));

      // Verify escrow document status transitioned to refunded and 100% refunded
      final escrowDoc = await firestore.collection('escrow').doc('job123').get();
      expect(escrowDoc.exists, isTrue);
      expect(escrowDoc.data()!['status'], equals('refunded'));
      expect(escrowDoc.data()!['refundAmount'], equals(2000.0));

      final empDoc = await firestore.collection('users').doc('employer123').get();
      expect(empDoc.data()!['tyxBalance'], equals(7000.0));

      // Verify refund transaction document created in transactions collection
      final txDoc = await firestore.collection('transactions').doc('refund_job_job123').get();
      expect(txDoc.exists, isTrue);
      expect(txDoc.data()!['type'], equals('refund'));
      expect(txDoc.data()!['category'], equals('refund'));
      expect(txDoc.data()!['amount'], equals(2000.0));
      expect(txDoc.data()!['status'], equals('Completed'));

      // Verify pending applications set to REJECTED_JOB_CANCELLED (TC-CNCL-02)
      final app1 = await firestore.collection('jobs').doc('job123').collection('applications').doc('applicant1').get();
      expect(app1.data()!['status'], equals('REJECTED_JOB_CANCELLED'));

      final app2 = await firestore.collection('jobs').doc('job123').collection('applications').doc('applicant2').get();
      expect(app2.data()!['status'], equals('REJECTED_JOB_CANCELLED'));

      // Verify cancellation log written to job_cancellation_logs
      final logs = firestore.db.entries
          .where((e) => e.key.startsWith('job_cancellation_logs/'))
          .map((e) => e.value)
          .toList();
      expect(logs, isNotEmpty);
      expect(logs.first['jobId'], equals('job123'));
      expect(logs.first['action'], equals('UNILATERAL_CANCEL'));
      expect(logs.first['status'], equals('CANCELLED'));
      expect(logs.first['cancelledBy'], equals('employer123'));
    });

    test('TC-CNCL-03: Model & UI Lock checks on Nyxian acceptance', () {
      final openJob = Job(
        id: 'job_open',
        creatorId: 'emp1',
        creatorName: 'Employer',
        creatorType: AccountType.employer,
        title: 'Open Job',
        description: 'Desc',
        category: JobCategory.plumber,
        categoryGroup: JobCategoryGroup.homeRepair,
        employmentType: 'Gig',
        dateRequirement: 'Today',
        timePreference: 'Morning',
        pricingType: 'Fixed',
        pricingValue: 500.0,
        locationType: 'On-site',
        createdAt: DateTime.now(),
        status: 'Open',
      );
      expect(openJob.isCancellationLocked, isFalse);
      expect(openJob.isHired, isFalse);

      final hiredJob = openJob.copyWith(
        acceptedApplicantId: 'nyxian123',
        status: 'In Progress',
      );
      expect(hiredJob.isCancellationLocked, isTrue);
      expect(hiredJob.isHired, isTrue);
    });

    test('TC-CNCL-04: Direct cancel attempt when hired throws JOB_ALREADY_COMMITTED', () async {
      firestore.db['users/employer123'] = {
        'uid': 'employer123',
        'tyxBalance': 1000.0,
      };

      firestore.db['jobs/job123'] = {
        'id': 'job123',
        'creatorId': 'employer123',
        'acceptedApplicantId': 'nyxian123',
        'status': 'In Progress',
      };

      expect(
        () => repo.cancelJob(jobId: 'job123', currentUserUid: 'employer123'),
        throwsA(predicate((e) => e.toString().contains('JOB_ALREADY_COMMITTED'))),
      );
    });

    test('TC-CNCL-05: Concurrency race condition serialization (Accept commits first, Cancel blocks)', () async {
      firestore.db['users/employer123'] = {
        'uid': 'employer123',
        'tyxBalance': 1000.0,
      };
      firestore.db['jobs/job123'] = {
        'id': 'job123',
        'creatorId': 'employer123',
        'status': 'Open',
        'acceptedApplicantId': null,
      };

      // 1. Accept applicant commits
      await repo.updateJobStatus('job123', 'In Progress', additionalFields: {
        'acceptedApplicantId': 'nyxian123',
      });

      // 2. Subsequent cancel attempt by employer
      expect(
        () => repo.cancelJob(jobId: 'job123', currentUserUid: 'employer123'),
        throwsA(predicate((e) => e.toString().contains('JOB_ALREADY_COMMITTED'))),
      );
    });

    test('TC-CNCL-06: Admin override with valid reason (>= 20 chars) cancels job and writes audit log', () async {
      firestore.db['users/employer123'] = {
        'uid': 'employer123',
        'tyxBalance': 1000.0,
      };
      firestore.db['users/nyxian123'] = {
        'uid': 'nyxian123',
        'tyxBalance': 500.0,
      };
      firestore.db['jobs/job123'] = {
        'id': 'job123',
        'creatorId': 'employer123',
        'acceptedApplicantId': 'nyxian123',
        'title': 'Emergency Repair',
        'status': 'In Progress',
      };
      firestore.db['escrow/job123'] = {
        'amount': 1500.0,
        'employerId': 'employer123',
        'status': 'held',
      };

      // Admin reason < 20 chars throws exception
      expect(
        () => repo.adminOverrideCancelJob(
          jobId: 'job123',
          adminUid: 'admin_zeus',
          reason: 'Too short',
        ),
        throwsA(predicate((e) => e.toString().contains('at least 20 characters'))),
      );

      // Valid admin override cancellation
      await repo.adminOverrideCancelJob(
        jobId: 'job123',
        adminUid: 'admin_zeus',
        reason: 'Customer dispute resolved: safety violation verified on site.',
      );

      // Verify job status
      final jobDoc = await firestore.collection('jobs').doc('job123').get();
      expect(jobDoc.data()!['status'], equals('ADMIN_CANCELLED'));

      // Verify escrow refund
      final empDoc = await firestore.collection('users').doc('employer123').get();
      expect(empDoc.data()!['tyxBalance'], equals(2500.0));

      final escrowDoc = await firestore.collection('escrow').doc('job123').get();
      expect(escrowDoc.exists, isTrue);
      expect(escrowDoc.data()!['status'], equals('refunded'));

      final txDoc = await firestore.collection('transactions').doc('refund_job_job123').get();
      expect(txDoc.exists, isTrue);
      expect(txDoc.data()!['type'], equals('refund'));
      expect(txDoc.data()!['amount'], equals(1500.0));

      // Verify audit log
      final logs = firestore.db.entries
          .where((e) => e.key.startsWith('job_cancellation_logs/'))
          .map((e) => e.value)
          .toList();
      expect(logs, isNotEmpty);
      final adminLog = logs.firstWhere((l) => l['action'] == 'ADMIN_OVERRIDE_CANCEL');
      expect(adminLog['status'], equals('ADMIN_CANCELLED'));
      expect(adminLog['role'], equals('admin'));
      expect(adminLog['acceptedApplicantId'], equals('nyxian123'));
    });

    test('TC-CNCL-07: Cancelled and Admin Cancelled jobs reject new applications', () async {
      firestore.db['jobs/job_cancelled'] = {
        'id': 'job_cancelled',
        'status': 'Cancelled',
      };

      final app = JobApplication(
        id: 'app1',
        jobId: 'job_cancelled',
        applicantUid: 'nyxian1',
        applicantName: 'Applicant',
        coverNote: 'Note',
        proposalRate: 500.0,
        isCounterOffer: false,
        createdAt: DateTime.now(),
      );

      expect(
        () => repo.applyToJob(app),
        throwsA(predicate((e) => e.toString().contains('Cannot apply to a cancelled job'))),
      );
    });

    test('TC-CNCL-08: Escrow refund fallback and duplicate cancellation protection', () async {
      firestore.db['users/employer999'] = {
        'uid': 'employer999',
        'tyxBalance': 1000.0,
      };
      firestore.db['jobs/job999'] = {
        'id': 'job999',
        'creatorId': 'employer999',
        'title': 'Plumbing Repair',
        'status': 'Open',
        'pricingValue': 1200.0,
        'discountAmount': 200.0,
      };
      // No escrow document in db initially (fallback test)

      await repo.cancelJob(jobId: 'job999', currentUserUid: 'employer999');

      // Balance refunded via fallback (1200 - 200 = 1000) -> 1000 + 1000 = 2000
      final empDoc = await firestore.collection('users').doc('employer999').get();
      expect(empDoc.data()!['tyxBalance'], equals(2000.0));

      final escrowDoc = await firestore.collection('escrow').doc('job999').get();
      expect(escrowDoc.exists, isTrue);
      expect(escrowDoc.data()!['status'], equals('refunded'));
      expect(escrowDoc.data()!['amount'], equals(1000.0));

      final txDoc = await firestore.collection('transactions').doc('refund_job_job999').get();
      expect(txDoc.exists, isTrue);
      expect(txDoc.data()!['type'], equals('refund'));
      expect(txDoc.data()!['amount'], equals(1000.0));

      // Attempting to cancel again should fail with INVALID_STATE_TRANSITION
      expect(
        () => repo.cancelJob(jobId: 'job999', currentUserUid: 'employer999'),
        throwsA(predicate((e) => e.toString().contains('Job is already cancelled'))),
      );
    });

    test('Cannot cancel completed job throws INVALID_STATE_TRANSITION', () async {
      firestore.db['jobs/job_done'] = {
        'id': 'job_done',
        'status': 'Completed',
        'creatorId': 'employer123',
      };

      expect(
        () => repo.cancelJob(jobId: 'job_done', currentUserUid: 'employer123'),
        throwsA(predicate((e) => e.toString().contains('INVALID_STATE_TRANSITION'))),
      );
    });

    test('Verify initial rating state is unrated (null) and first review sets explicit score', () async {
      // 1. Initial user profile without reviews has null rating
      final newProfile = UserProfile(
        uid: 'newuser123',
        name: 'New User',
        email: 'new@tranyx.app',
        accountType: AccountType.nyxian,
      );
      expect(newProfile.rating, isNull);
      expect(newProfile.renterRating, isNull);
      expect(newProfile.hostRating, isNull);

      final map = newProfile.toMap();
      expect(map['rating'], isNull);

      // 2. Setup user in DB without rating (unrated)
      firestore.db['users/newuser123'] = {
        'uid': 'newuser123',
        'name': 'New User',
      };
      firestore.db['jobs/job_new'] = {
        'id': 'job_new',
        'title': 'Delivery',
        'status': 'Completed',
        'employerRated': false,
        'nyxianRated': false,
      };

      // 3. Submit first rating (score: 5)
      await repo.submitJobRating(
        jobId: 'job_new',
        targetId: 'newuser123',
        reviewerUid: 'employer123',
        reviewerName: 'Test Employer',
        score: 5,
        comment: 'First review!',
        currentViewMode: AccountType.employer,
      );

      final userDoc = await firestore.collection('users').doc('newuser123').get();
      expect(userDoc.data()!['rating'], equals(5.0));
      expect(userDoc.data()!['ratingCount'], equals(1));
    });

    group('updateJobDetails Pre-Hire & Anti-Exploitation Contract', () {
      test('Scenario 1: Pre-hire edit on Open job with 0 applicants updates whitelisted fields and sets updatedAt', () async {
        firestore.db['jobs/open_job_1'] = {
          'id': 'open_job_1',
          'creatorId': 'employer123',
          'title': 'Original Title',
          'description': 'Original Description',
          'category': 'plumber',
          'categoryGroup': 'homeRepair',
          'dateRequirement': 'Flexible',
          'timePreference': 'Morning',
          'pricingValue': 1500.0,
          'status': 'Open',
          'applicantCount': 0,
          'acceptedApplicantId': null,
          'locationType': 'On-site',
          'address': '123 Old St',
          'landmark': 'Old Landmark',
        };

        await repo.updateJobDetails('open_job_1', {
          'title': 'Updated Title',
          'description': 'Updated Description with detailed scope',
          'landmark': 'Near Blue Gate',
          'timePreference': 'Afternoon',
          'imageUrls': ['https://example.com/photo1.jpg'],
          // Illegal keys attempting to alter pricing or ownership
          'pricingValue': 9999.0,
          'creatorId': 'hacker',
          'status': 'Completed',
        });

        final jobDoc = await firestore.collection('jobs').doc('open_job_1').get();
        expect(jobDoc.exists, isTrue);
        final data = jobDoc.data()!;

        // Whitelisted fields successfully updated
        expect(data['title'], equals('Updated Title'));
        expect(data['description'], equals('Updated Description with detailed scope'));
        expect(data['landmark'], equals('Near Blue Gate'));
        expect(data['timePreference'], equals('Afternoon'));
        expect(data['imageUrls'], equals(['https://example.com/photo1.jpg']));
        expect(data['updatedAt'], isNotNull);

        // Disallowed / non-whitelisted keys ignored
        expect(data['pricingValue'], equals(1500.0));
        expect(data['creatorId'], equals('employer123'));
        expect(data['status'], equals('Open'));
      });

      test('Scenario 2: Pre-hire edit on Reviewing job with applicants updates scope and stamps updatedAt', () async {
        firestore.db['jobs/reviewing_job_2'] = {
          'id': 'reviewing_job_2',
          'creatorId': 'employer123',
          'title': 'Reviewing Job',
          'description': 'Need help with plumbing',
          'status': 'Reviewing',
          'applicantCount': 4,
          'acceptedApplicantId': null,
        };

        await repo.updateJobDetails('reviewing_job_2', {
          'description': 'Updated: Tools will be provided on-site',
          'timePreference': 'Morning',
        });

        final jobDoc = await firestore.collection('jobs').doc('reviewing_job_2').get();
        final data = jobDoc.data()!;
        expect(data['description'], equals('Updated: Tools will be provided on-site'));
        expect(data['timePreference'], equals('Morning'));
        expect(data['updatedAt'], isNotNull);
      });

      test('Scenario 3: Post-hire lock - throws exception if Nyxian already accepted/hired', () async {
        firestore.db['jobs/hired_job_3'] = {
          'id': 'hired_job_3',
          'creatorId': 'employer123',
          'title': 'Grave Digger Needed',
          'description': 'Original scope',
          'status': 'In Progress',
          'applicantCount': 2,
          'acceptedApplicantId': 'nyxian_winner_999',
        };

        expect(
          () => repo.updateJobDetails('hired_job_3', {
            'description': 'Tampered scope after hiring',
          }),
          throwsA(predicate((e) =>
              e.toString().contains('A Nyxian has already been hired'))),
        );

        // Verify document unchanged
        final jobDoc = await firestore.collection('jobs').doc('hired_job_3').get();
        expect(jobDoc.data()!['description'], equals('Original scope'));
      });

      test('Scenario 4: Hard status lockout for Done, Completed, or Cancelled jobs', () async {
        final invalidStatuses = ['In Progress', 'Done', 'Completed', 'Cancelled', 'Admin Cancelled'];

        for (final st in invalidStatuses) {
          final jobId = 'job_st_${st.replaceAll(' ', '_')}';
          firestore.db['jobs/$jobId'] = {
            'id': jobId,
            'creatorId': 'employer123',
            'title': 'Status test job',
            'description': 'Original',
            'status': st,
            'acceptedApplicantId': null,
          };

          expect(
            () => repo.updateJobDetails(jobId, {'title': 'Attempted Hack'}),
            throwsA(predicate((e) =>
                e.toString().contains('Job status must be Open or Reviewing'))),
            reason: 'Job with status $st must not be editable',
          );
        }
      });

      test('Scenario 5: Throws exception if job does not exist', () async {
        expect(
          () => repo.updateJobDetails('non_existent_id', {'title': 'New'}),
          throwsA(predicate((e) => e.toString().contains('Job not found'))),
        );
      });
    });
  });
}

