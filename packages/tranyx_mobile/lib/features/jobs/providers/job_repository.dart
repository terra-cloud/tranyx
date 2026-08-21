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
    final docId = job.id.isEmpty ? _firestore.collection('jobs').doc().id : job.id;
    final jobDocRef = _firestore.collection('jobs').doc(docId);
    final userRef = _firestore.collection('users').doc(job.creatorId);
    final escrowRef = _firestore.collection('escrow').doc(docId);

    await _firestore.runTransaction((transaction) async {
      final userSnap = await transaction.get(userRef);
      if (!userSnap.exists) throw Exception('Employer profile not found.');
      final userData = userSnap.data()!;

      final double currentBal = (userData['tyxBalance'] as num?)?.toDouble() ?? 0.0;
      final double price = job.pricingValue;
      final double discount = job.discountAmount ?? 0.0;
      final double discountedPrice = (price - discount).clamp(0.0, 999999.0);

      if (currentBal < discountedPrice) {
        throw Exception('Insufficient balance. Please deposit at least ₱${(discountedPrice - currentBal).toStringAsFixed(2)} to post this job.');
      }

      // 1. Deduct balance
      transaction.update(userRef, {
        'tyxBalance': currentBal - discountedPrice,
      });

      // 2. Set job doc
      transaction.set(jobDocRef, {
        ...job.toMap(),
        'id': docId,
      });

      // 3. Set escrow doc
      transaction.set(escrowRef, {
        'amount': discountedPrice,
        'employerId': job.creatorId,
        'status': 'held',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'hasInspectionHoldback': job.hasTracker, // On mobile, hasTracker matches inspection
        if (job.hasTracker) 'holdbackAmount': price * 0.10,
      });

      // 4. Increment promo usage if any
      final String? promoCode = job.promoCode;
      if (promoCode != null && promoCode.trim().isNotEmpty) {
        final promoRef = _firestore.collection('promos').doc(promoCode.trim().toUpperCase());
        final promoSnap = await transaction.get(promoRef);
        if (promoSnap.exists) {
          final usedBy = List<String>.from(promoSnap.data()?['usedBy'] ?? []);
          if (!usedBy.contains(job.creatorId)) {
            usedBy.add(job.creatorId);
          }
          final usedCount = (promoSnap.data()?['usedCount'] as num? ?? 0).toInt() + 1;
          transaction.update(promoRef, {
            'usedBy': usedBy,
            'usedCount': usedCount,
          });
        }
      }
    });
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
      if (!snapshot.exists) throw Exception('Job not found.');

      final data = snapshot.data()!;
      final status = (data['status'] as String? ?? '').toLowerCase();
      if (status == 'cancelled' ||
          status == 'admin_cancelled' ||
          status == 'completed') {
        throw Exception('Cannot apply to a $status job.');
      }

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
      final double discount = (jobData['discountAmount'] as num?)?.toDouble() ?? 0.0;
      final double discountedPrice = (finalPrice - discount).clamp(0.0, 999999.0);

      transaction.set(escrowRef, {
        'amount': discountedPrice,
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
      ...?additionalFields,
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
      double actualPlatformFee = platformFee;

      // 1. Fetch Nyxian to check for profile-based promo
      double immediatePayout = 0.0;
      double nyxianPayout = price - platformFee;
      final bool hasHoldback = jobData['hasInspectionHoldback'] as bool? ?? false;
      final double holdbackAmount = hasHoldback ? price * 0.10 : 0.0;

      String? redeemedPromoCode;
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

          redeemedPromoCode = nyxData['activePromoCode'] as String?;
          if (redeemedPromoCode != null) {
            final double discountVal = (nyxData['activePromoDiscountValue'] as num?)?.toDouble() ?? 0.0;
            final String discountType = nyxData['activePromoDiscountType'] as String? ?? 'flat';
            double discountAmt = 0.0;
            if (discountType == 'percentage') {
              discountAmt = platformFee * (discountVal / 100.0);
            } else {
              discountAmt = discountVal;
            }
            actualPlatformFee = (platformFee - discountAmt).clamp(0.0, platformFee);
          }

          nyxianPayout = price - actualPlatformFee;
          immediatePayout = nyxianPayout - holdbackAmount;

          transaction.update(nyxRef, {
            'tyxBalance': currentNyxBal + immediatePayout,
            'jobsDone': currentJobsDone + 1,
            'totalEarned': currentEarned + immediatePayout,
            'completedGigsCount': newGigsCount,
            'repeatHireRate': repeatHireRate,
            if (redeemedPromoCode != null) 'activePromoCode': null,
            if (redeemedPromoCode != null) 'activePromoDiscountType': null,
            if (redeemedPromoCode != null) 'activePromoDiscountValue': null,
          });

          // Increment profile promo usage in transaction
          if (redeemedPromoCode != null) {
            final promoRef = _firestore.collection('promos').doc(redeemedPromoCode.trim().toUpperCase());
            final promoSnap = await transaction.get(promoRef);
            if (promoSnap.exists) {
              final usedBy = List<String>.from(promoSnap.data()?['usedBy'] ?? []);
              if (!usedBy.contains(nyxianId)) {
                usedBy.add(nyxianId);
              }
              final usedCount = (promoSnap.data()?['usedCount'] as num? ?? 0).toInt() + 1;
              transaction.update(promoRef, {
                'usedBy': usedBy,
                'usedCount': usedCount,
              });
            }
          }
        }

        // Log payout transaction for Nyxian
        final payoutTxRef = _firestore.collection('transactions').doc('payout_nyx_$jobId');
        transaction.set(payoutTxRef, {
          'uid': nyxianId,
          'title': 'Gig Payout Released',
          'desc': 'Payout for completing job $jobId (3% commission deducted${redeemedPromoCode != null ? ' - Promo $redeemedPromoCode applied' : ''})',
          'amount': immediatePayout,
          'status': 'Successful',
          'method': 'Tranyx Wallet',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'type': 'payout',
        });
      }

      // 2. Delete escrow record
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

      // 2.1 Deduct fees from Employer Wallet (7% Transaction Fee + 3% Convenience Fee = 10%)
      final double discount = (jobData['discountAmount'] as num?)?.toDouble() ?? 0.0;
      final double discountedPrice = (price - discount).clamp(0.0, 999999.0);
      final double txFee = discountedPrice * 0.07;
      final double convFee = discountedPrice * 0.03;
      final double totalFees = txFee + convFee;

      if (employerId != null) {
        final empRef = _firestore.collection('users').doc(employerId);
        final empSnap = await transaction.get(empRef);
        if (empSnap.exists) {
          final empData = empSnap.data()!;
          final double currentBal = (empData['tyxBalance'] as num?)?.toDouble() ?? 0.0;

          transaction.update(empRef, {
            'tyxBalance': currentBal - totalFees,
          });
        }

        // Log fee deduction transaction for Employer
        final feeTxRef = _firestore.collection('transactions').doc('fees_emp_$jobId');
        transaction.set(feeTxRef, {
          'uid': employerId,
          'title': 'Job Completion Fees (10%)',
          'desc': '7% Transaction Fee (${txFee.toStringAsFixed(2)}) & 3% Convenience Fee (${convFee.toStringAsFixed(2)}) for job $jobId${discount > 0 ? ' (Discounted base of ₱${discountedPrice.toStringAsFixed(2)} applied)' : ''}',
          'amount': totalFees,
          'status': 'Successful',
          'method': 'Tranyx Wallet',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'type': 'fee_deduction',
        });
      }

      // 3. Record all platform fees and company income (total 13% of base price)
      final double totalCompanyIncome = actualPlatformFee + txFee + convFee;
      final platformFeesRef = _firestore.collection('platform_fees').doc(jobId);
      transaction.set(platformFeesRef, {
        'jobId': jobId,
        'amount': totalCompanyIncome,
        'commissionFee': actualPlatformFee, // 3% from Nyxian
        'transactionFee': txFee, // 7% from Employer
        'convenienceFee': convFee, // 3% from Employer
        'employerFees': txFee + convFee, // 10% total from Employer
        'nyxianFee': actualPlatformFee, // 3% total from Nyxian
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

      final String currentStatus = (jobData['status'] as String? ?? '').toLowerCase();
      if (currentStatus == 'completed') {
        throw Exception('INVALID_STATE_TRANSITION: Cannot cancel a completed job.');
      }

      final String? acceptedNyxian = jobData['acceptedApplicantId'] as String? ?? jobData['nyxianId'] as String?;
      final bool hasAcceptedNyxian = acceptedNyxian != null && acceptedNyxian.trim().isNotEmpty;
      final bool isCommitted = hasAcceptedNyxian ||
          currentStatus == 'in progress' ||
          currentStatus == 'in_progress' ||
          currentStatus == 'accepted' ||
          jobData['status'] == 'MUTUAL_CANCEL_PENDING';

      if (isCommitted) {
        throw Exception('JOB_ALREADY_COMMITTED: Employer cannot unilaterally cancel a job once a Nyxian has been accepted.');
      }

      final String employerId = jobData['creatorId'] as String? ?? '';
      final escrowSnap = await transaction.get(escrowRef);
      if (escrowSnap.exists) {
        final double totalEscrow = (escrowSnap.data()!['amount'] as num?)?.toDouble() ?? 0.0;
        // 100% refund to Employer on unilateral open cancellation
        if (totalEscrow > 0.0 && employerId.isNotEmpty) {
          final empRef = _firestore.collection('users').doc(employerId);
          final empSnap = await transaction.get(empRef);
          if (empSnap.exists) {
            final double currentBal = (empSnap.data()!['tyxBalance'] as num?)?.toDouble() ?? 0.0;
            transaction.update(empRef, {
              'tyxBalance': currentBal + totalEscrow,
            });
          }
        }
        transaction.delete(escrowRef);
      }

      // Update status to Cancelled
      transaction.update(jobRef, {
        'status': 'Cancelled',
      });

      // Update pending applications to REJECTED_JOB_CANCELLED
      final applicationsSnap = await _firestore.collection('jobs').doc(jobId).collection('applications').get();
      for (final appDoc in applicationsSnap.docs) {
        transaction.update(appDoc.reference, {
          'status': 'REJECTED_JOB_CANCELLED',
        });
      }

      // Write to job_cancellation_logs
      final logRef = _firestore.collection('job_cancellation_logs').doc();
      transaction.set(logRef, {
        'jobId': jobId,
        'cancelledBy': currentUserUid,
        'role': 'employer',
        'action': 'UNILATERAL_CANCEL',
        'status': 'CANCELLED',
        'reason': 'Employer cancelled open job posting',
        'previousStatus': jobData['status'] ?? 'Open',
        'acceptedApplicantId': null,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Decrement promo usage if any
      final String? promoCode = jobData['promoCode'] as String?;
      if (promoCode != null && promoCode.trim().isNotEmpty) {
        final promoRef = _firestore.collection('promos').doc(promoCode.trim().toUpperCase());
        final promoSnap = await transaction.get(promoRef);
        if (promoSnap.exists) {
          final usedBy = List<String>.from(promoSnap.data()?['usedBy'] ?? []);
          usedBy.remove(employerId);
          final usedCount = ((promoSnap.data()?['usedCount'] as num? ?? 1).toInt() - 1).clamp(0, 999999);
          transaction.update(promoRef, {
            'usedBy': usedBy,
            'usedCount': usedCount,
          });
        }
      }
    });
  }

  Future<void> adminOverrideCancelJob({
    required String jobId,
    required String adminUid,
    required String reason,
  }) async {
    if (reason.trim().length < 20) {
      throw Exception('Admin override requires a justification reason of at least 20 characters.');
    }

    final jobRef = _firestore.collection('jobs').doc(jobId);
    final escrowRef = _firestore.collection('escrow').doc(jobId);

    await _firestore.runTransaction((transaction) async {
      final jobSnap = await transaction.get(jobRef);
      if (!jobSnap.exists) throw Exception('Job not found.');
      final jobData = jobSnap.data()!;

      final String employerId = jobData['creatorId'] as String? ?? '';
      final String? nyxianId = jobData['acceptedApplicantId'] as String? ?? jobData['nyxianId'] as String?;
      final String prevStatus = jobData['status'] as String? ?? 'Unknown';

      final escrowSnap = await transaction.get(escrowRef);
      if (escrowSnap.exists) {
        final double totalEscrow = (escrowSnap.data()!['amount'] as num?)?.toDouble() ?? 0.0;
        if (totalEscrow > 0.0 && employerId.isNotEmpty) {
          final empRef = _firestore.collection('users').doc(employerId);
          final empSnap = await transaction.get(empRef);
          if (empSnap.exists) {
            final double currentBal = (empSnap.data()!['tyxBalance'] as num?)?.toDouble() ?? 0.0;
            transaction.update(empRef, {
              'tyxBalance': currentBal + totalEscrow,
            });
          }
        }
        transaction.delete(escrowRef);
      }

      transaction.update(jobRef, {
        'status': 'ADMIN_CANCELLED',
      });

      final logRef = _firestore.collection('job_cancellation_logs').doc();
      transaction.set(logRef, {
        'jobId': jobId,
        'adminUid': adminUid,
        'cancelledBy': adminUid,
        'role': 'admin',
        'action': 'ADMIN_OVERRIDE_CANCEL',
        'status': 'ADMIN_CANCELLED',
        'reason': reason.trim(),
        'previousStatus': prevStatus,
        'acceptedApplicantId': nyxianId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Notify Employer
      if (employerId.isNotEmpty) {
        final prefix = employerId.length > 5 ? employerId.substring(0, 5) : employerId;
        final notifRef = _firestore.collection('notifications').doc('notif_admin_cancel_${DateTime.now().millisecondsSinceEpoch}_$prefix');
        transaction.set(notifRef, {
          'uid': employerId,
          'title': 'Job Admin Cancelled ⚠️',
          'message': 'Admin cancelled "${jobData['title']}". Reason: ${reason.trim()}',
          'type': 'admin_job_cancelled',
          'jobId': jobId,
          'isRead': false,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      }

      // Notify Nyxian if assigned
      if (nyxianId != null && nyxianId.isNotEmpty) {
        final prefix = nyxianId.length > 5 ? nyxianId.substring(0, 5) : nyxianId;
        final notifRef = _firestore.collection('notifications').doc('notif_admin_cancel_nyx_${DateTime.now().millisecondsSinceEpoch}_$prefix');
        transaction.set(notifRef, {
          'uid': nyxianId,
          'title': 'Gig Cancelled by Admin ⚠️',
          'message': 'Admin has cancelled job "${jobData['title']}". Reason: ${reason.trim()}',
          'type': 'admin_job_cancelled',
          'jobId': jobId,
          'isRead': false,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      }

      // Decrement promo usage if any
      final String? promoCode = jobData['promoCode'] as String?;
      if (promoCode != null && promoCode.trim().isNotEmpty) {
        final promoRef = _firestore.collection('promos').doc(promoCode.trim().toUpperCase());
        final promoSnap = await transaction.get(promoRef);
        if (promoSnap.exists) {
          final usedBy = List<String>.from(promoSnap.data()?['usedBy'] ?? []);
          usedBy.remove(employerId);
          final usedCount = ((promoSnap.data()?['usedCount'] as num? ?? 1).toInt() - 1).clamp(0, 999999);
          transaction.update(promoRef, {
            'usedBy': usedBy,
            'usedCount': usedCount,
          });
        }
      }
    });
  }

  Future<String> submitDispute({
    required String jobId,
    required String jobTitle,
    required String employerId,
    required String? acceptedNyxianId,
    required String reason,
    required double escrowAmount,
    required String openedByUid,
  }) async {
    final disputeId = 'disp_${DateTime.now().millisecondsSinceEpoch}_${jobId.substring(0, jobId.length > 6 ? 6 : jobId.length)}';
    await _firestore.collection('disputes').doc(disputeId).set({
      'id': disputeId,
      'jobId': jobId,
      'jobTitle': jobTitle,
      'employerId': employerId,
      'acceptedNyxianId': acceptedNyxianId,
      'openedBy': openedByUid,
      'openedByRole': openedByUid == acceptedNyxianId ? 'nyxian' : 'employer',
      'status': 'OPEN',
      'reason': reason.trim(),
      'escrowAmount': escrowAmount,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'resolvedAt': null,
      'resolutionType': null,
      'resolutionNotes': null,
    });
    return disputeId;
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
