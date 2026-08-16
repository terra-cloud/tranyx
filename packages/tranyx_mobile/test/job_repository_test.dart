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

    test('Verify cancelJob handles 100% refund when early cancellation', () async {
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
      };

      firestore.db['jobs/job123'] = {
        'id': 'job123',
        'creatorId': 'employer123',
        'acceptedApplicantId': 'nyxian123',
        'status': 'In Progress',
        'hasTracker': true,
      };

      firestore.db['escrow/job123'] = {
        'amount': 2000.0,
        'employerId': 'employer123',
        'status': 'held',
      };

      // 2. Cancel job
      await repo.cancelJob(
        jobId: 'job123',
        currentUserUid: 'employer123',
      );

      // 3. Assertions
      // Verify job status is Cancelled
      final jobDoc = await firestore.collection('jobs').doc('job123').get();
      expect(jobDoc.data()!['status'], equals('Cancelled'));

      // Verify escrow document is deleted
      final escrowDoc = await firestore.collection('escrow').doc('job123').get();
      expect(escrowDoc.exists, isFalse);

      // Verify Employer balance has been refunded full 2000
      final empDoc = await firestore.collection('users').doc('employer123').get();
      expect(empDoc.data()!['tyxBalance'], equals(7000.0));

      // Verify Nyxian balance remains the same
      final nyxDoc = await firestore.collection('users').doc('nyxian123').get();
      expect(nyxDoc.data()!['tyxBalance'], equals(1000.0));
    });

    test('Verify cancelJob handles 20 Tyxbits worker compensation when late cancellation', () async {
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
      };

      firestore.db['jobs/job123'] = {
        'id': 'job123',
        'creatorId': 'employer123',
        'acceptedApplicantId': 'nyxian123',
        'status': 'arrived_pickup', // reached first point
        'hasTracker': true,
      };

      firestore.db['escrow/job123'] = {
        'amount': 2000.0,
        'employerId': 'employer123',
        'status': 'held',
      };

      // 2. Cancel job
      await repo.cancelJob(
        jobId: 'job123',
        currentUserUid: 'employer123',
      );

      // 3. Assertions
      // Verify job status is Cancelled
      final jobDoc = await firestore.collection('jobs').doc('job123').get();
      expect(jobDoc.data()!['status'], equals('Cancelled'));

      // Verify escrow document is deleted
      final escrowDoc = await firestore.collection('escrow').doc('job123').get();
      expect(escrowDoc.exists, isFalse);

      // Verify Nyxian balance has been credited 20 tyxbits compensation
      final nyxDoc = await firestore.collection('users').doc('nyxian123').get();
      expect(nyxDoc.data()!['tyxBalance'], equals(1020.0));

      // Verify Employer balance has been refunded 2000 - 20 = 1980
      final empDoc = await firestore.collection('users').doc('employer123').get();
      expect(empDoc.data()!['tyxBalance'], equals(6980.0));
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
  });
}
