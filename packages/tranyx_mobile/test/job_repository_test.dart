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

    group('Job Application Counter-Offer Restrictions (80% - 150%)', () {
      setUp(() {
        firestore.db['jobs/job_counter_test'] = {
          'id': 'job_counter_test',
          'creatorId': 'employer999',
          'title': 'Electrical Wiring',
          'pricingValue': 1000.0,
          'status': 'Open',
          'applicantCount': 0,
          'applicantUids': <String>[],
          'recentApplicantPhotos': <String>[],
        };
      });

      test('allows counter offer within 80% to 150% range', () async {
        final app = JobApplication(
          id: 'app_valid',
          jobId: 'job_counter_test',
          applicantUid: 'nyxian_valid',
          applicantName: 'Good Electrician',
          coverNote: 'I can do this well.',
          proposalRate: 1200.0,
          isCounterOffer: true,
          createdAt: DateTime.now(),
        );

        await repo.applyToJob(app);

        final appDoc = await firestore
            .collection('jobs')
            .doc('job_counter_test')
            .collection('applications')
            .doc('nyxian_valid')
            .get();
        expect(appDoc.exists, isTrue);
        expect(appDoc.data()!['proposalRate'], equals(1200.0));
        expect(appDoc.data()!['isCounterOffer'], isTrue);

        // Verify original employer offer remains unchanged
        final jobDoc = await firestore.collection('jobs').doc('job_counter_test').get();
        expect(jobDoc.data()!['pricingValue'], equals(1000.0));
      });

      test('rejects counter offer below 80% of original offer', () async {
        final app = JobApplication(
          id: 'app_low',
          jobId: 'job_counter_test',
          applicantUid: 'nyxian_low',
          applicantName: 'Cheap Electrician',
          coverNote: 'Very low bid.',
          proposalRate: 799.0,
          isCounterOffer: true,
          createdAt: DateTime.now(),
        );

        expect(
          () => repo.applyToJob(app),
          throwsA(predicate((e) =>
              e.toString().contains("Your counter offer must be between ₱800 and ₱1,500 based on the employer's original offer of ₱1,000."))),
        );
      });

      test('rejects counter offer above 150% of original offer', () async {
        final app = JobApplication(
          id: 'app_high',
          jobId: 'job_counter_test',
          applicantUid: 'nyxian_high',
          applicantName: 'Expensive Electrician',
          coverNote: 'High bid.',
          proposalRate: 1501.0,
          isCounterOffer: true,
          createdAt: DateTime.now(),
        );

        expect(
          () => repo.applyToJob(app),
          throwsA(predicate((e) =>
              e.toString().contains("Your counter offer must be between ₱800 and ₱1,500 based on the employer's original offer of ₱1,000."))),
        );
      });

      test('rejects ₱0 or negative counter offer amounts', () async {
        final appZero = JobApplication(
          id: 'app_zero',
          jobId: 'job_counter_test',
          applicantUid: 'nyxian_zero',
          applicantName: 'Zero Bidder',
          coverNote: 'Free labor.',
          proposalRate: 0.0,
          isCounterOffer: true,
          createdAt: DateTime.now(),
        );

        expect(
          () => repo.applyToJob(appZero),
          throwsA(predicate((e) => e.toString().contains('Counter offer cannot be ₱0 or negative.'))),
        );

        final appNegative = JobApplication(
          id: 'app_neg',
          jobId: 'job_counter_test',
          applicantUid: 'nyxian_neg',
          applicantName: 'Negative Bidder',
          coverNote: 'Negative bid.',
          proposalRate: -50.0,
          isCounterOffer: true,
          createdAt: DateTime.now(),
        );

        expect(
          () => repo.applyToJob(appNegative),
          throwsA(predicate((e) => e.toString().contains('Counter offer cannot be ₱0 or negative.'))),
        );
      });

      test('rejects acceptApplication if counter offer is invalid or zero', () async {
        firestore.db['users/employer999'] = {
          'uid': 'employer999',
          'tyxBalance': 5000.0,
        };

        final invalidApp = JobApplication(
          id: 'app_corrupt',
          jobId: 'job_counter_test',
          applicantUid: 'nyxian_corrupt',
          applicantName: 'Corrupted App',
          coverNote: 'Corrupted rate.',
          proposalRate: 0.0,
          isCounterOffer: true,
          createdAt: DateTime.now(),
        );

        expect(
          () => repo.acceptApplicant(
            jobId: 'job_counter_test',
            application: invalidApp,
            employerUid: 'employer999',
          ),
          throwsA(predicate((e) => e.toString().contains('Cannot accept counter offer'))),
        );
      });

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

    test('Verify submitJobRating creates ratings/{jobId}_{raterUid} and marks the job rated (users doc untouched)', () async {
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

      await repo.submitJobRating(
        jobId: 'job123',
        targetId: 'nyxian123',
        reviewerUid: 'employer123',
        reviewerName: 'Test Employer',
        score: 5,
        comment: 'Great work!',
        currentViewMode: AccountType.employer,
      );

      final ratingDoc = await firestore.collection('ratings').doc('job123_employer123').get();
      expect(ratingDoc.exists, isTrue);
      expect(ratingDoc.data()!['jobId'], equals('job123'));
      expect(ratingDoc.data()!['raterId'], equals('employer123'));
      expect(ratingDoc.data()!['rateeId'], equals('nyxian123'));
      expect(ratingDoc.data()!['rating'], equals(5));
      expect(ratingDoc.data()!['comment'], equals('Great work!'));
      expect(ratingDoc.data()!.keys.toSet(),
          equals({'jobId', 'raterId', 'rateeId', 'rating', 'comment', 'createdAt'}));

      // The rated user's profile is not written by the rater any more (aggregation: KAN-126).
      final nyxDoc = await firestore.collection('users').doc('nyxian123').get();
      expect(nyxDoc.data()!['rating'], equals(4.0));
      expect(nyxDoc.data()!['ratingCount'], equals(1));

      final jobDoc = await firestore.collection('jobs').doc('job123').get();
      expect(jobDoc.data()!['employerRated'], isTrue);
      expect(jobDoc.data()!['nyxianRated'], isFalse);
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

      final ratingDoc = await firestore.collection('ratings').doc('job_new_employer123').get();
      expect(ratingDoc.data()!['rating'], equals(5));
      expect(ratingDoc.data()!['rateeId'], equals('newuser123'));
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

    group('reclaimInactiveJob (48-Hour Inactivity Guardrail)', () {
    });

    group('Ongoing Job Application Restriction Guardrail', () {
      test('Nyxian with ongoing accepted job is blocked from applying to another job', () async {
        // Active job where nyxian999 is accepted
        firestore.db['jobs/ongoing_job_1'] = {
          'id': 'ongoing_job_1',
          'creatorId': 'employer1',
          'title': 'Active Task',
          'status': 'In Progress',
          'acceptedApplicantId': 'nyxian999',
        };

        // Open job nyxian999 wants to apply to
        firestore.db['jobs/target_job'] = {
          'id': 'target_job',
          'creatorId': 'employer2',
          'title': 'New Target Job',
          'status': 'Open',
          'applicantCount': 0,
          'applicantUids': <String>[],
          'recentApplicantPhotos': <String>[],
        };

        final app = JobApplication(
          id: 'app_new',
          jobId: 'target_job',
          applicantUid: 'nyxian999',
          applicantName: 'Busy Nyxian',
          coverNote: 'I want this gig too',
          proposalRate: 1000.0,
          isCounterOffer: false,
          createdAt: DateTime.now(),
        );

        expect(
          () => repo.applyToJob(app),
          throwsA(predicate((e) =>
              e.toString().contains(ongoingJobRestrictionMessage))),
        );

        // Verify target job was NOT updated with this application
        final targetDoc = await firestore.collection('jobs').doc('target_job').get();
        expect(targetDoc.data()!['applicantCount'], equals(0));
        expect(List<String>.from(targetDoc.data()!['applicantUids']), isEmpty);
      });

      test('Nyxian with only terminal accepted jobs (Completed, Cancelled, Abandoned) CAN apply', () async {
        firestore.db['jobs/finished_job_1'] = {
          'id': 'finished_job_1',
          'creatorId': 'employer1',
          'title': 'Completed Task',
          'status': 'Completed',
          'acceptedApplicantId': 'nyxian999',
        };

        firestore.db['jobs/cancelled_job_2'] = {
          'id': 'cancelled_job_2',
          'creatorId': 'employer2',
          'title': 'Cancelled Task',
          'status': 'Cancelled',
          'acceptedApplicantId': 'nyxian999',
        };

        firestore.db['jobs/abandoned_job_3'] = {
          'id': 'abandoned_job_3',
          'creatorId': 'employer3',
          'title': 'Abandoned Task',
          'status': 'Abandoned',
          'acceptedApplicantId': 'nyxian999',
        };

        firestore.db['jobs/target_job_free'] = {
          'id': 'target_job_free',
          'creatorId': 'employer4',
          'title': 'Free Target Job',
          'status': 'Open',
          'applicantCount': 0,
          'applicantUids': <String>[],
          'recentApplicantPhotos': <String>[],
        };

        final app = JobApplication(
          id: 'app_free',
          jobId: 'target_job_free',
          applicantUid: 'nyxian999',
          applicantName: 'Available Nyxian',
          coverNote: 'Ready to work',
          proposalRate: 800.0,
          isCounterOffer: false,
          createdAt: DateTime.now(),
        );

        await repo.applyToJob(app);

        final targetDoc = await firestore.collection('jobs').doc('target_job_free').get();
        expect(targetDoc.data()!['applicantCount'], equals(1));
        expect(List<String>.from(targetDoc.data()!['applicantUids']), contains('nyxian999'));
      });

      test('Nyxian with pending applications on other jobs (not accepted) CAN apply', () async {
        // Nyxian applied to another job, but is NOT accepted (acceptedApplicantId is null)
        firestore.db['jobs/applied_job_1'] = {
          'id': 'applied_job_1',
          'creatorId': 'employer1',
          'title': 'Pending Job',
          'status': 'Open',
          'acceptedApplicantId': null,
          'applicantUids': ['nyxian999'],
        };

        firestore.db['jobs/target_job_multi'] = {
          'id': 'target_job_multi',
          'creatorId': 'employer2',
          'title': 'Another Target Job',
          'status': 'Open',
          'applicantCount': 0,
          'applicantUids': <String>[],
          'recentApplicantPhotos': <String>[],
        };

        final app = JobApplication(
          id: 'app_multi',
          jobId: 'target_job_multi',
          applicantUid: 'nyxian999',
          applicantName: 'Multi Applicant Nyxian',
          coverNote: 'Applying to multiple open jobs',
          proposalRate: 1200.0,
          isCounterOffer: false,
          createdAt: DateTime.now(),
        );

        await repo.applyToJob(app);

        final targetDoc = await firestore.collection('jobs').doc('target_job_multi').get();
        expect(targetDoc.data()!['applicantCount'], equals(1));
        expect(List<String>.from(targetDoc.data()!['applicantUids']), contains('nyxian999'));
      });
    });
  });
}

