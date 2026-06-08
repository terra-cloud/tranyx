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
  });
}
