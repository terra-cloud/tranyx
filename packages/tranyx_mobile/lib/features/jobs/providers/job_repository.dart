import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart' hide JobQuestion;
import 'package:tranyx_mobile/core/services/money_callable.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/jobs/models/job_question.dart';

class JobRepository {
  final FirebaseFirestore _firestore;

  /// Server-side money callables (gig escrow funding / hiring / release / refunds). Overridable in tests.
  final Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data) _money;

  JobRepository(
    this._firestore, {
    Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data)? moneyCaller,
  }) : _money = moneyCaller ?? ((name, data) => callMoney(name, data));

  Future<void> createJob(Job job) async {
    // The server recomputes price, fees and discount from authoritative config, debits the employer
    // and creates the gig + its escrow in one transaction (balances/escrow are Admin-SDK only).
    final data = job.toMap()
      ..remove('id')
      ..['hasInspectionHoldback'] = job.hasTracker; // On mobile, hasTracker matches inspection
    await _money('jobAction', {'action': 'create', 'job': data});
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
    // Check if Nyxian already has an ongoing accepted job
    final existingAcceptedQuery = await _firestore
        .collection('jobs')
        .where('acceptedApplicantId', isEqualTo: application.applicantUid)
        .get();

    final hasOngoing = existingAcceptedQuery.docs.any((doc) {
      final data = doc.data();
      final s = (data['status'] as String? ?? '').trim().toLowerCase();
      return s.isNotEmpty &&
          s != 'completed' &&
          s != 'cancelled' &&
          s != 'admin_cancelled' &&
          s != 'abandoned';
    });

    if (hasOngoing) {
      throw Exception(ongoingJobRestrictionMessage);
    }

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

      // Backend / Repository Counter-Offer Validation (80% - 150% and strictly > 0)
      if (application.isCounterOffer) {
        final double originalJobPrice = (data['pricingValue'] as num?)?.toDouble() ?? 0.0;
        final validation = JobCounterOfferValidator.validate(
          originalOffer: originalJobPrice,
          counterOfferInput: application.proposalRate,
          isCounterOffer: true,
        );
        if (!validation.isValid) {
          throw Exception(validation.errorMessage ?? 'Invalid counter offer.');
        }
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
    final jobSnap = await _firestore.collection('jobs').doc(jobId).get();
    if (!jobSnap.exists) throw Exception('Job not found.');
    final jobData = jobSnap.data()!;
    final double originalPrice = (jobData['pricingValue'] as num?)?.toDouble() ?? 0.0;

    if (application.isCounterOffer) {
      final validation = JobCounterOfferValidator.validate(
        originalOffer: originalPrice,
        counterOfferInput: application.proposalRate,
        isCounterOffer: true,
      );
      if (!validation.isValid) {
        throw Exception('Cannot accept counter offer: ${validation.errorMessage}');
      }
    }

    // Categorize and determine acknowledgment SLA
    final now = DateTime.now().millisecondsSinceEpoch;
    final category = JobSlaHelper.classifyJob(jobData);
    final slaMinutes = category.defaultSlaMinutes;
    final deadline = JobSlaHelper.calculateDeadline(
      job: jobData,
      hiredAt: DateTime.fromMillisecondsSinceEpoch(now),
    ).millisecondsSinceEpoch;

    // Server-side: re-validates the counter offer against the held escrow, charges/refunds the
    // difference (price + fees), moves the escrow to the worker and flips the gig to hired.
    await _money('jobAction', {
      'action': 'accept',
      'jobId': jobId,
      'applicantUid': application.applicantUid,
      'jobPatch': {
        'acknowledgmentStatus': 'pending',
        'acknowledgmentCategory': category.id,
        'acknowledgmentSlaMinutes': slaMinutes,
        'acknowledgmentDeadline': deadline,
        'acknowledgmentReminderSent': false,
      },
    });

    // Post acknowledgment request system message to the job chat
    final durationLabel = JobSlaHelper.formatSlaDurationLabel(slaMinutes);
    final msgId = 'msg_ack_req_$now';
    final scopedJobChatId = 'job_${jobId}_${application.applicantUid}';
    final ackPayload = {
      'senderId': 'system',
      'senderName': 'Tranyx System',
      'type': 'acknowledgment_request',
      'text':
          '🎉 You have been hired for this task.\nPlease acknowledge that you have received the job and are ready to proceed.\n\nPlease respond within $durationLabel.',
      'category': category.id,
      'deadline': deadline,
      'slaMinutes': slaMinutes,
      'createdAt': now,
    };
    final batch = _firestore.batch();
    batch.set(_firestore.collection('chats').doc(scopedJobChatId).collection('messages').doc(msgId), ackPayload);
    batch.set(_firestore.collection('chats').doc(scopedJobChatId), {
      'userIds': [jobData['creatorId'], application.applicantUid],
      'jobId': jobId,
      'applicantId': application.applicantUid,
      'updatedAt': now,
    }, SetOptions(merge: true));
    batch.set(_firestore.collection('chats').doc(jobId).collection('messages').doc(msgId), ackPayload);
    batch.set(_firestore.collection('chats').doc(jobId), {'updatedAt': now}, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> acknowledgeJob(String jobId, String nyxianUid) async {
    final jobRef = _firestore.collection('jobs').doc(jobId);
    final snap = await jobRef.get();
    if (!snap.exists) throw Exception('Job not found.');
    final data = snap.data()!;
    if (data['acceptedApplicantId'] != nyxianUid) {
      throw Exception('UNAUTHORIZED: Only the hired Nyxian can acknowledge this job.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await jobRef.update({
      'status': 'In Progress',
      'acknowledgmentStatus': 'acknowledged',
      'acknowledgedAt': now,
    });
  }

  Future<void> resetJobForNewApplicants(String jobId, String employerUid) async {
    final jobRef = _firestore.collection('jobs').doc(jobId);
    final snap = await jobRef.get();
    if (!snap.exists) throw Exception('Job not found.');
    final data = snap.data()!;
    if (data['creatorId'] != employerUid) {
      throw Exception('UNAUTHORIZED: Only the job creator can reset this job.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await jobRef.update({
      'status': 'Open',
      'acceptedApplicantId': null,
      'acknowledgmentStatus': 'reset',
      'acknowledgmentDeadline': null,
      'acknowledgmentReminderSent': false,
      'updatedAt': now,
    });
  }

  Future<void> updateJobStatus(String jobId, String status, {Map<String, dynamic>? additionalFields}) async {
    await _firestore.collection('jobs').doc(jobId).update({
      'status': status,
      ...?additionalFields,
    });
  }

  /// Updates open/reviewing job listing details pre-hire.
  /// Throws if a Nyxian is already hired or if the job is not in Open/Reviewing status.
  Future<void> updateJobDetails(String jobId, Map<String, dynamic> updates) async {
    final jobDocRef = _firestore.collection('jobs').doc(jobId);
    final snap = await jobDocRef.get();
    if (!snap.exists) {
      throw Exception('Job not found.');
    }
    final data = snap.data()!;
    final status = (data['status'] as String? ?? '').toLowerCase();
    final acceptedApplicantId = data['acceptedApplicantId'] as String?;

    if (acceptedApplicantId != null && acceptedApplicantId.trim().isNotEmpty) {
      throw Exception('Editing locked: A Nyxian has already been hired for this gig.');
    }
    if (status != 'open' && status != 'reviewing') {
      throw Exception('Editing locked: Job status must be Open or Reviewing to edit.');
    }

    const allowedKeys = {
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
      'pickupLat',
      'pickupLng',
      'destinationAddress',
      'destinationLat',
      'destinationLng',
      'imageUrls',
      'updatedAt',
    };

    final filteredUpdates = <String, dynamic>{};
    for (final entry in updates.entries) {
      if (allowedKeys.contains(entry.key) && entry.value != null) {
        filteredUpdates[entry.key] = entry.value;
      }
    }

    if (!filteredUpdates.containsKey('updatedAt')) {
      filteredUpdates['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    }

    await jobDocRef.update(filteredUpdates);
  }

  Future<void> completeJob({
    required String jobId,
    required String verificationCodeEntered,
    required String currentUserUid,
    required String currentUserName,
  }) async {
    // Server verifies the code and the caller's role, releases the escrow (worker payout, 48h
    // holdback, commission/fees incl. any promo), marks the gig Completed and notifies the other party.
    await _money('jobAction', {
      'action': 'complete',
      'jobId': jobId,
      'verificationCode': verificationCodeEntered.trim(),
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
    // Create-only ratings/{jobId}_{raterUid} (KAN-145): never writes the other user's profile.
    // The rating average is aggregated server-side (KAN-126).
    final ratingRef = _firestore.collection('ratings').doc('${jobId}_$reviewerUid');
    final jobRef = _firestore.collection('jobs').doc(jobId);

    final batch = _firestore.batch();
    batch.set(ratingRef, {
      'jobId': jobId,
      'raterId': reviewerUid,
      'rateeId': targetId,
      'rating': score,
      'comment': comment.length > 500 ? comment.substring(0, 500) : comment,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final isEmployerRole = currentViewMode == AccountType.employer;
    final isNyxianRole = currentViewMode == AccountType.nyxian;
    batch.update(jobRef, {
      if (isEmployerRole) 'employerRated': true,
      if (isNyxianRole) 'nyxianRated': true,
    });
    await batch.commit();
  }

  Future<void> cancelJob({
    required String jobId,
    required String currentUserUid,
  }) async {
    await _money('jobAction', {'action': 'cancel', 'jobId': jobId});
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
      final bool isAlreadyRefunded = escrowSnap.exists && (escrowSnap.data()!['status'] as String? ?? '').toLowerCase() == 'refunded';

      DocumentSnapshot<Map<String, dynamic>>? empSnap;
      final empRef = employerId.isNotEmpty ? _firestore.collection('users').doc(employerId) : null;
      if (empRef != null) {
        empSnap = await transaction.get(empRef);
      }

      final String? promoCode = jobData['promoCode'] as String?;
      DocumentSnapshot<Map<String, dynamic>>? promoSnap;
      DocumentReference<Map<String, dynamic>>? promoRef;
      if (promoCode != null && promoCode.trim().isNotEmpty) {
        promoRef = _firestore.collection('promos').doc(promoCode.trim().toUpperCase());
        promoSnap = await transaction.get(promoRef);
      }

      // 2. All writes after reads
      if (!isAlreadyRefunded && employerId.isNotEmpty) {
        double totalEscrow = 0.0;
        if (escrowSnap.exists) {
          totalEscrow = (escrowSnap.data()!['amount'] as num?)?.toDouble() ?? 0.0;
        }
        if (totalEscrow <= 0.0) {
          final double price = (jobData['pricingValue'] as num?)?.toDouble() ?? 0.0;
          final double discount = (jobData['discountAmount'] as num?)?.toDouble() ?? 0.0;
          totalEscrow = (price - discount).clamp(0.0, 999999.0);
        }

        if (totalEscrow > 0.0) {
          if (empRef != null && empSnap != null && empSnap.exists) {
            final double currentBal = (empSnap.data()!['tyxBalance'] as num?)?.toDouble() ?? 0.0;
            transaction.update(empRef, {
              'tyxBalance': currentBal + totalEscrow,
            });
          }

          transaction.set(escrowRef, {
            if (escrowSnap.exists) ...escrowSnap.data()!,
            'jobId': jobId,
            'employerId': employerId,
            'amount': totalEscrow,
            'refundAmount': totalEscrow,
            'status': 'refunded',
            'refundedAt': DateTime.now().millisecondsSinceEpoch,
            'refundedTo': employerId,
          });

          final txRef = _firestore.collection('transactions').doc('refund_job_$jobId');
          final jobTitle = (jobData['title'] as String?) ?? 'Job';
          transaction.set(txRef, {
            'id': 'refund_job_$jobId',
            'uid': employerId,
            'jobId': jobId,
            'type': 'refund',
            'category': 'refund',
            'amount': totalEscrow,
            'title': 'Job Escrow Refund (Admin Override)',
            'desc': '100% Escrow refund via admin override for cancelled job "$jobTitle"',
            'status': 'Completed',
            'method': 'Tranyx Escrow',
            'originRail': 'internal_balance',
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });
        }
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
      if (promoRef != null && promoSnap != null && promoSnap.exists) {
        final usedBy = List<String>.from(promoSnap.data()?['usedBy'] ?? []);
        usedBy.remove(employerId);
        final usedCount = ((promoSnap.data()?['usedCount'] as num? ?? 1).toInt() - 1).clamp(0, 999999);
        transaction.update(promoRef, {
          'usedBy': usedBy,
          'usedCount': usedCount,
        });
      }
    });
  }

  Future<void> reclaimInactiveJob({
    required String jobId,
    required String employerUid,
    String? reason,
  }) async {
    await _money('jobAction', {'action': 'reclaim', 'jobId': jobId, if (reason != null) 'reason': reason});
  }

  Future<void> deleteJob({
    required String jobId,
    required String currentUserUid,
  }) async {
    await _money('jobAction', {'action': 'delete', 'jobId': jobId});
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

final hasOngoingNyxianJobProvider = Provider<bool>((ref) {
  final user = ref.watch(userProvider);
  if (user == null) return false;
  final myJobsAsync = ref.watch(myJobsProvider);
  return myJobsAsync.maybeWhen(
    data: (jobs) => jobs.any((job) => job.isOngoingForNyxian(user.uid)),
    orElse: () => false,
  );
});

