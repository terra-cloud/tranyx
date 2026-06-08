import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/jobs/models/job.dart';
import 'package:tranyx_mobile/features/jobs/models/job_application.dart';
import 'package:tranyx_mobile/features/jobs/models/job_question.dart';

class JobRepository {
  final FirebaseFirestore _firestore;

  JobRepository(this._firestore);

  Future<void> createJob(Job job) async {
    await _firestore
        .collection('jobs')
        .doc(job.id.isEmpty ? null : job.id)
        .set(job.toMap());
  }

  Stream<List<Job>> getMyJobs(String uid) {
    return _firestore
        .collection('jobs')
        .where('creatorId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Job.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Stream<List<Job>> getGigsAccepted(String uid) {
    return _firestore
        .collection('jobs')
        .where('acceptedApplicantId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Job.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Stream<List<Job>> getAvailableJobs(AccountType viewerType) {
    // Visibility logic:
    // Employers see Nyxian postings
    // Nyxians see Employer postings
    final creatorTypeToFetch = viewerType == AccountType.nyxian
        ? AccountType.employer
        : AccountType.nyxian;

    return _firestore
        .collection('jobs')
        .where('creatorType', isEqualTo: creatorTypeToFetch.name)
        .where('status', isEqualTo: 'Open')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Job.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<void> applyToJob(JobApplication application) async {
    final jobRef = _firestore.collection('jobs').doc(application.jobId);
    final applicationRef = jobRef
        .collection('applications')
        .doc(application.applicantUid);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(jobRef);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final List<String> applicantUids = List<String>.from(
        data['applicantUids'] ?? [],
      );
      final List<String> recentPhotos = List<String>.from(
        data['recentApplicantPhotos'] ?? [],
      );

      if (applicantUids.contains(application.applicantUid)) {
        return; // Already applied
      }

      applicantUids.add(application.applicantUid);
      final photoToInsert = application.applicantPhotoUrl ?? "";
      // Only check contains if it's a real photo, otherwise always insert empty string for default avatar
      if (photoToInsert.isEmpty || !recentPhotos.contains(photoToInsert)) {
        recentPhotos.insert(0, photoToInsert);
        if (recentPhotos.length > 5) {
          recentPhotos.removeLast();
        }
      }

      transaction.set(applicationRef, application.toMap());

      transaction.update(jobRef, {
        'applicantUids': applicantUids,
        'applicantCount': FieldValue.increment(1),
        'recentApplicantPhotos': recentPhotos,
      });
    });
  }

  Stream<List<JobApplication>> getJobApplications(String jobId) {
    return _firestore
        .collection('jobs')
        .doc(jobId)
        .collection('applications')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => JobApplication.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<void> addJobQuestion(String jobId, JobQuestion question) async {
    await _firestore
        .collection('jobs')
        .doc(jobId)
        .collection('questions')
        .add(question.toMap());
  }

  Future<void> answerJobQuestion(
    String jobId,
    String questionId,
    String answer,
  ) async {
    await _firestore
        .collection('jobs')
        .doc(jobId)
        .collection('questions')
        .doc(questionId)
        .update({
          'answerText': answer,
          'answeredAt': DateTime.now().millisecondsSinceEpoch,
        });
  }

  Stream<List<JobQuestion>> getJobQuestions(String jobId) {
    return _firestore
        .collection('jobs')
        .doc(jobId)
        .collection('questions')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => JobQuestion.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<void> updateUserPhotoInDenormalizedLocations(
    String uid,
    String newPhotoUrl, {
    String? oldPhotoUrl,
  }) async {
    final batch = _firestore.batch();

    // 1. Update jobs created by this user
    final myJobsQuery = await _firestore
        .collection('jobs')
        .where('creatorId', isEqualTo: uid)
        .get();

    for (var doc in myJobsQuery.docs) {
      batch.update(doc.reference, {'creatorPhotoUrl': newPhotoUrl});
    }

    // 2. Update applications made by this user (Collection Group)
    final applicationsQuery = await _firestore
        .collectionGroup('applications')
        .where('applicantUid', isEqualTo: uid)
        .get();

    for (var doc in applicationsQuery.docs) {
      batch.update(doc.reference, {'applicantPhotoUrl': newPhotoUrl});
    }

    // 3. Update recentApplicantPhotos in jobs where this user is an applicant
    if (oldPhotoUrl != null && oldPhotoUrl.isNotEmpty) {
      final appliedJobsQuery = await _firestore
          .collection('jobs')
          .where('applicantUids', arrayContains: uid)
          .get();

      for (var doc in appliedJobsQuery.docs) {
        final List<dynamic> photos = List<dynamic>.from(
          doc.data()['recentApplicantPhotos'] ?? [],
        );
        final idx = photos.indexOf(oldPhotoUrl);
        if (idx != -1) {
          photos[idx] = newPhotoUrl;
          batch.update(doc.reference, {'recentApplicantPhotos': photos});
        }
      }
    }

    // 4. Update authorPhotoUrl in job questions asked by this user (Collection Group)
    final questionsQuery = await _firestore
        .collectionGroup('questions')
        .where('authorUid', isEqualTo: uid)
        .get();

    for (var doc in questionsQuery.docs) {
      batch.update(doc.reference, {'authorPhotoUrl': newPhotoUrl});
    }

    await batch.commit();
  }
}

final jobRepositoryProvider = Provider<JobRepository>((ref) {
  return JobRepository(ref.watch(firestoreProvider));
});

final myJobsProvider = StreamProvider<List<Job>>((ref) {
  final user = ref.watch(userProvider);
  if (user == null) return Stream.value([]);
  
  final repo = ref.watch(jobRepositoryProvider);
  final stream1 = repo.getMyJobs(user.uid);
  final stream2 = repo.getGigsAccepted(user.uid);

  final controller = StreamController<List<Job>>();
  List<Job> latest1 = [];
  List<Job> latest2 = [];

  void update() {
    if (controller.isClosed) return;
    final combined = <Job>{...latest1, ...latest2}.toList();
    combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    controller.add(combined);
  }

  final sub1 = stream1.listen(
    (data) {
      latest1 = data;
      update();
    },
    onError: (err) {
      if (!controller.isClosed) controller.addError(err);
    },
  );

  final sub2 = stream2.listen(
    (data) {
      latest2 = data;
      update();
    },
    onError: (err) {
      if (!controller.isClosed) controller.addError(err);
    },
  );

  controller.onCancel = () {
    sub1.cancel();
    sub2.cancel();
  };

  return controller.stream;
});

final availableJobsProvider = StreamProvider<List<Job>>((ref) {
  final currentViewMode = ref.watch(currentViewModeProvider);
  return ref.watch(jobRepositoryProvider).getAvailableJobs(currentViewMode);
});

final jobApplicationsProvider =
    StreamProvider.family<List<JobApplication>, String>((ref, jobId) {
      return ref.watch(jobRepositoryProvider).getJobApplications(jobId);
    });

final jobQuestionsStreamProvider =
    StreamProvider.family<List<JobQuestion>, String>((ref, jobId) {
      return ref.watch(jobRepositoryProvider).getJobQuestions(jobId);
    });
