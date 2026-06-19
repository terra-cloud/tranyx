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

  Stream<List<Job>> getAppliedJobs(String uid) {
    return _firestore
        .collection('jobs')
        .where('applicantUids', arrayContains: uid)
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
        .where('authorId', isEqualTo: uid)
        .get();

    for (var doc in questionsQuery.docs) {
      batch.update(doc.reference, {'authorPhotoUrl': newPhotoUrl});
    }

    await batch.commit();
  }

  Future<void> acceptApplicant({
    required String jobId,
    required JobApplication application,
    required String employerUid,
  }) async {
    final jobRef = _firestore.collection('jobs').doc(jobId);
    final userRef = _firestore.collection('users').doc(employerUid);
    final escrowRef = _firestore.collection('escrow').doc(jobId);

    await _firestore.runTransaction((transaction) async {
      final jobSnap = await transaction.get(jobRef);
      if (!jobSnap.exists) throw Exception('Job not found.');
      final jobData = jobSnap.data()!;

      final userSnap = await transaction.get(userRef);
      if (!userSnap.exists) throw Exception('Employer profile not found.');
      final userData = userSnap.data()!;

      final double originalPrice = (jobData['pricingValue'] as num?)?.toDouble() ?? 0.0;
      final double rate = application.proposalRate;
      double newEmployerBalance = (userData['tyxBalance'] as num?)?.toDouble() ?? 0.0;

      double finalPrice = originalPrice;

      if (application.isCounterOffer) {
        if (rate > originalPrice) {
          final diff = rate - originalPrice;
          if (newEmployerBalance < diff) {
            throw Exception('Insufficient balance to accept this counter offer.');
          }
          newEmployerBalance -= diff;
          finalPrice = rate;
        } else if (rate < originalPrice && rate > 0) {
          final diff = originalPrice - rate;
          newEmployerBalance += diff;
          finalPrice = rate;
        }
      }

      // Update employer's balance
      transaction.update(userRef, {
        'tyxBalance': newEmployerBalance,
      });

      // Create or update escrow record
      final now = DateTime.now().millisecondsSinceEpoch;
      final bool hasInspectionHoldback = jobData['hasInspectionHoldback'] as bool? ?? false;
      final holdbackAmount = hasInspectionHoldback ? finalPrice * 0.10 : 0.0;

      transaction.set(escrowRef, {
        'amount': finalPrice,
        'employerId': employerUid,
        'status': 'held',
        'createdAt': now,
        'hasInspectionHoldback': hasInspectionHoldback,
        if (hasInspectionHoldback) 'holdbackAmount': holdbackAmount,
      });

      // Update job status and accepted applicant details
      transaction.update(jobRef, {
        'status': 'In Progress',
        'acceptedApplicantId': application.applicantUid,
        'pricingValue': finalPrice,
      });
    });
  }

  Future<void> updateJobStatus(String jobId, String status, {Map<String, dynamic>? additionalFields}) async {
    await _firestore.collection('jobs').doc(jobId).update({
      'status': status,
      if (additionalFields != null) ...additionalFields,
    });
  }

  Future<void> completeJob({
    required String jobId,
    required String verificationCodeEntered,
    required String currentUserUid,
    required String currentUserName,
  }) async {
    final jobRef = _firestore.collection('jobs').doc(jobId);
    final escrowRef = _firestore.collection('escrow').doc(jobId);

    await _firestore.runTransaction((transaction) async {
      final jobSnap = await transaction.get(jobRef);
      if (!jobSnap.exists) throw Exception('Job not found.');
      final jobData = jobSnap.data()!;

      final String status = (jobData['status'] as String? ?? '').toLowerCase();
      if (status == 'completed') {
        throw Exception('This job is already completed.');
      }

      final correctCode = jobData['completionCode']?.toString() ?? jobData['verificationCode']?.toString();
      if (verificationCodeEntered.trim() != correctCode?.trim()) {
        throw Exception('Invalid or expired verification code.');
      }

      final bool hasTracker = jobData['hasTracker'] == true || jobData['hasTracker'] == 'true';
      final nyxianId = jobData['acceptedApplicantId'] as String? ?? jobData['nyxianId'] as String?;
      final employerId = jobData['creatorId'] as String?;

      if (hasTracker) {
        if (employerId != currentUserUid) {
          throw Exception('Verification failed: You are not the Employer for this job.');
        }
      } else {
        if (nyxianId != currentUserUid) {
          throw Exception('Verification failed: You are not the assigned Nyxian for this job.');
        }
      }

      final double price = (jobData['pricingValue'] as num?)?.toDouble() ?? 0.0;
      final double platformFee = price * 0.03;
      final double nyxianPayout = price - platformFee;
      final bool hasHoldback = jobData['hasInspectionHoldback'] as bool? ?? false;
      final double holdbackAmount = hasHoldback ? price * 0.10 : 0.0;
      final double immediatePayout = nyxianPayout - holdbackAmount;

      // 1. Delete escrow record
      transaction.delete(escrowRef);

      // 1.1 Create escrow holdback record if enabled
      if (hasHoldback && nyxianId != null) {
        final holdbackRef = _firestore.collection('escrow_holdbacks').doc(jobId);
        transaction.set(holdbackRef, {
          'jobId': jobId,
          'amount': holdbackAmount,
          'nyxianId': nyxianId,
          'employerId': employerId,
          'status': 'held',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'releaseAt': DateTime.now().add(const Duration(hours: 48)).millisecondsSinceEpoch,
        });
      }

      // 2. Add to Nyxian Wallet (Payout only, NO rebate)
      if (nyxianId != null) {
        final nyxRef = _firestore.collection('users').doc(nyxianId);
        final nyxSnap = await transaction.get(nyxRef);
        if (nyxSnap.exists) {
          final nyxData = nyxSnap.data()!;
          final double currentNyxBal = (nyxData['tyxBalance'] as num?)?.toDouble() ?? 0.0;
          final int currentJobsDone = nyxData['jobsDone'] as int? ?? 0;
          final double currentEarned = (nyxData['totalEarned'] as num?)?.toDouble() ?? 0.0;
          final int gigsCount = nyxData['completedGigsCount'] as int? ?? 0;
          final int newGigsCount = gigsCount + 1;
          final double repeatHireRate = newGigsCount > 1 ? 0.35 : 0.0;

          transaction.update(nyxRef, {
            'tyxBalance': currentNyxBal + immediatePayout,
            'jobsDone': currentJobsDone + 1,
            'totalEarned': currentEarned + immediatePayout,
            'completedGigsCount': newGigsCount,
            'repeatHireRate': repeatHireRate,
          });
        }

        // Log payout transaction for Nyxian
        final payoutTxRef = _firestore.collection('transactions').doc('payout_nyx_$jobId');
        transaction.set(payoutTxRef, {
          'uid': nyxianId,
          'title': 'Gig Payout Released',
          'desc': 'Payout for completing job $jobId (3% commission deducted)',
          'amount': immediatePayout,
          'status': 'Successful',
          'method': 'Tranyx Wallet',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'type': 'payout',
        });
      }

      // 2.1 Deduct fees from Employer Wallet (7% Transaction Fee + 3% Convenience Fee = 10%)
      if (employerId != null) {
        final empRef = _firestore.collection('users').doc(employerId);
        final empSnap = await transaction.get(empRef);
        if (empSnap.exists) {
          final empData = empSnap.data()!;
          final double currentBal = (empData['tyxBalance'] as num?)?.toDouble() ?? 0.0;
          final double txFee = price * 0.07;
          final double convFee = price * 0.03;
          final double totalFees = txFee + convFee;

          transaction.update(empRef, {
            'tyxBalance': currentBal - totalFees,
          });
        }

        // Log fee deduction transaction for Employer
        final feeTxRef = _firestore.collection('transactions').doc('fees_emp_$jobId');
        final double txFee = price * 0.07;
        final double convFee = price * 0.03;
        final double totalFees = txFee + convFee;
        transaction.set(feeTxRef, {
          'uid': employerId,
          'title': 'Job Completion Fees (10%)',
          'desc': '7% Transaction Fee (${txFee.toStringAsFixed(2)}) & 3% Convenience Fee (${convFee.toStringAsFixed(2)}) for job $jobId',
          'amount': totalFees,
          'status': 'Successful',
          'method': 'Tranyx Wallet',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'type': 'fee_deduction',
        });
      }

      // 3. Record all platform fees and company income (total 13% of base price)
      final double txFee = price * 0.07;
      final double convFee = price * 0.03;
      final double totalCompanyIncome = platformFee + txFee + convFee;
      final platformFeesRef = _firestore.collection('platform_fees').doc(jobId);
      transaction.set(platformFeesRef, {
        'jobId': jobId,
        'amount': totalCompanyIncome,
        'commissionFee': platformFee, // 3% from Nyxian
        'transactionFee': txFee, // 7% from Employer
        'convenienceFee': convFee, // 3% from Employer
        'employerFees': txFee + convFee, // 10% total from Employer
        'nyxianFee': platformFee, // 3% total from Nyxian
        'totalFees': totalCompanyIncome, // 13% total Company Funds
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // 4. Mark job as complete
      transaction.update(jobRef, {
        'status': 'Completed',
      });

      // 5. Send notification to the other party
      final String? targetUser = (currentUserUid == employerId) ? nyxianId : employerId;
      if (targetUser != null) {
        final prefix = targetUser.length > 5 ? targetUser.substring(0, 5) : targetUser;
        final notifDocId = 'notif_${DateTime.now().millisecondsSinceEpoch}_$prefix';
        final notifRef = _firestore.collection('notifications').doc(notifDocId);
        transaction.set(notifRef, {
          'uid': targetUser,
          'title': 'Gig Completed 🎉',
          'message': '$currentUserName has completed "${jobData['title']}". Click to rate them.',
          'type': 'job_completed',
          'jobId': jobId,
          'senderUid': currentUserUid,
          'senderName': currentUserName,
          'isRead': false,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  Future<void> submitJobRating({
    required String jobId,
    required String targetId,
    required String reviewerUid,
    required String reviewerName,
    required int score,
    required String comment,
    required AccountType currentViewMode,
  }) async {
    final targetRef = _firestore.collection('users').doc(targetId);
    final reviewRef = _firestore.collection('users').doc(targetId).collection('reviews').doc(jobId);
    final jobRef = _firestore.collection('jobs').doc(jobId);

    await _firestore.runTransaction((transaction) async {
      final targetSnap = await transaction.get(targetRef);
      if (!targetSnap.exists) throw Exception('Target user profile not found.');
      final targetDoc = targetSnap.data()!;

      final double currentRating = (targetDoc['rating'] as num?)?.toDouble() ?? 0.0;
      final int currentRatingCount = targetDoc['ratingCount'] as int? ?? 0;

      final double newRating;
      if (currentRatingCount == 0) {
        newRating = score.toDouble();
      } else {
        newRating = ((currentRating * currentRatingCount) + score) / (currentRatingCount + 1);
      }

      transaction.update(targetRef, {
        'rating': newRating,
        'ratingCount': currentRatingCount + 1,
      });

      transaction.set(reviewRef, {
        'reviewerId': reviewerUid,
        'reviewerName': reviewerName,
        'score': score,
        'comment': comment,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final isEmployerRole = currentViewMode == AccountType.employer;
      final isNyxianRole = currentViewMode == AccountType.nyxian;

      transaction.update(jobRef, {
        if (isEmployerRole) 'employerRated': true,
        if (isNyxianRole) 'nyxianRated': true,
      });
    });
  }

  Future<void> cancelJob({
    required String jobId,
    required String currentUserUid,
  }) async {
    final jobRef = _firestore.collection('jobs').doc(jobId);
    final escrowRef = _firestore.collection('escrow').doc(jobId);

    await _firestore.runTransaction((transaction) async {
      final jobSnap = await transaction.get(jobRef);
      if (!jobSnap.exists) throw Exception('Job not found.');
      final jobData = jobSnap.data()!;

      final String employerId = jobData['creatorId'] as String? ?? '';
      final String? nyxianId = jobData['acceptedApplicantId'] as String? ?? jobData['nyxianId'] as String?;

      final bool hasTracker = jobData['hasTracker'] == true || jobData['hasTracker'] == 'true';
      final String status = (jobData['status'] as String? ?? '').toLowerCase();

      final bool reachedFirstPoint = hasTracker &&
          (status == 'arrived_pickup' ||
              status == 'paid_cashier' ||
              status == 'in_transit' ||
              status == 'arrived_dropoff' ||
              status == 'done' ||
              status == 'completed');

      final escrowSnap = await transaction.get(escrowRef);
      if (escrowSnap.exists) {
        final double totalEscrow = (escrowSnap.data()!['amount'] as num?)?.toDouble() ?? 0.0;
        final double compensation = reachedFirstPoint ? (totalEscrow >= 20.0 ? 20.0 : totalEscrow) : 0.0;
        final double refundAmount = totalEscrow - compensation;

        // Refund to Employer
        if (refundAmount > 0.0 && employerId.isNotEmpty) {
          final empRef = _firestore.collection('users').doc(employerId);
          final empSnap = await transaction.get(empRef);
          if (empSnap.exists) {
            final double currentBal = (empSnap.data()!['tyxBalance'] as num?)?.toDouble() ?? 0.0;
            transaction.update(empRef, {
              'tyxBalance': currentBal + refundAmount,
            });
          }
        }

        // Compensation to Nyxian
        if (compensation > 0.0 && nyxianId != null && nyxianId.isNotEmpty) {
          final nyxRef = _firestore.collection('users').doc(nyxianId);
          final nyxSnap = await transaction.get(nyxRef);
          if (nyxSnap.exists) {
            final double currentBal = (nyxSnap.data()!['tyxBalance'] as num?)?.toDouble() ?? 0.0;
            transaction.update(nyxRef, {
              'tyxBalance': currentBal + compensation,
            });
          }
        }

        // Delete escrow
        transaction.delete(escrowRef);
      }

      // Update status to Cancelled
      transaction.update(jobRef, {
        'status': 'Cancelled',
      });
    });
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

final appliedJobsProvider = StreamProvider<List<Job>>((ref) {
  final user = ref.watch(userProvider);
  if (user == null) return Stream.value([]);
  return ref.watch(jobRepositoryProvider).getAppliedJobs(user.uid);
});

final jobApplicationsProvider =
    StreamProvider.family<List<JobApplication>, String>((ref, jobId) {
      return ref.watch(jobRepositoryProvider).getJobApplications(jobId);
    });

final jobQuestionsStreamProvider =
    StreamProvider.family<List<JobQuestion>, String>((ref, jobId) {
      return ref.watch(jobRepositoryProvider).getJobQuestions(jobId);
    });
