import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared/shared.dart';

// Ids, notes, results and document shapes live in packages/shared so the web
// client writes exactly the same thing. Re-exported for existing imports.
export 'package:shared/shared.dart'
    show
        OnchainCommitResult,
        OnchainCommitResultX,
        OnchainSupportException,
        kMarkerHeldNote,
        kRefusedByRulesNote,
        onchainMarkerId,
        pendingOnchainId;

/// Records that [signature] was sent for [uid] and is awaiting finalization.
/// Never overwrites an existing record. Best effort: the payment already left
/// the wallet, so a failure here must not stop the flow.
Future<void> writePendingOnchain({
  required FirebaseFirestore firestore,
  required String uid,
  required String signature,
  required String kind, // 'deposit' | 'subscription'
  required double phpAmount,
  required double cryptoAmount,
  required String currency,
}) async {
  try {
    final ref = firestore
        .collection('transactions')
        .doc(pendingOnchainId(uid, signature));
    await firestore.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return;
      tx.set(
        ref,
        pendingOnchainData(
          uid: uid,
          signature: signature,
          kind: kind,
          phpAmount: phpAmount,
          cryptoAmount: cryptoAmount,
          currency: currency,
          startedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
  } catch (_) {}
}

/// Leaves the pending record pending and notes why, for support. Creates a
/// minimal one when none exists yet. Never touches a `done` record. Best effort.
Future<void> notePendingOnchain({
  required FirebaseFirestore firestore,
  required String uid,
  required String signature,
  required String note,
  String kind = 'deposit',
}) async {
  try {
    final ref = firestore
        .collection('transactions')
        .doc(pendingOnchainId(uid, signature));
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set(
        pendingOnchainData(
          uid: uid,
          signature: signature,
          kind: kind,
          startedAt: DateTime.now().millisecondsSinceEpoch,
          note: note,
        ),
      );
    } else if (snap.data()?['status'] == 'pending') {
      await ref.update({'note': note});
    }
  } catch (_) {}
}

/// In ONE Firestore transaction: applies the user update built from the CURRENT
/// user doc, creates [markerId] and the shared `onchain_<signature>` marker, and
/// marks the caller's pending record done.
///
/// `onchain_<signature>` is read FIRST and decides the outcome by its owner:
/// - another uid (someone squatted or previously used the signature): the
///   per-flow marker is not even read (the rules keep it owner-only); nothing is
///   credited, the caller's own pending record is created/kept open with a note
///   and [OnchainCommitResult.heldByAnotherAccount] is returned, so the UI can
///   tell the user to contact support;
/// - same uid: [OnchainCommitResult.alreadyProcessed] (replay / double tap);
/// - missing: the per-flow marker is read; if it exists it is a replay of an
///   older credit ([OnchainCommitResult.alreadyProcessed]), or foreign
///   ([OnchainCommitResult.heldByAnotherAccount]).
///
/// A `permission-denied` from the rules is NOT a foreign marker: it is reported
/// as [OnchainCommitResult.refusedByRules] with its own pending note, so support
/// can tell the two apart. heldByAnotherAccount means a foreign marker was read.
Future<OnchainCommitResult> commitOnceByMarker({
  required FirebaseFirestore firestore,
  required String uid,
  required String signature,
  required String markerId,
  required Map<String, dynamic> markerData,
  required Map<String, dynamic> Function(Map<String, dynamic> user)
  buildUserUpdate,
}) async {
  final kind = markerData['type'] == 'subscription'
      ? 'subscription'
      : 'deposit';
  try {
    return await firestore.runTransaction<OnchainCommitResult>((tx) async {
      final userRef = firestore.collection('users').doc(uid);
      final markerRef = firestore.collection('transactions').doc(markerId);
      final onchainRef = firestore
          .collection('transactions')
          .doc(onchainMarkerId(signature));
      final pendingRef = firestore
          .collection('transactions')
          .doc(pendingOnchainId(uid, signature));

      // All reads first, shared marker before anything else.
      final onchainSnap = await tx.get(onchainRef);

      // Leaves the caller's own pending record open with a note (no balance change).
      Future<OnchainCommitResult> held() async {
        final pendingSnap = await tx.get(pendingRef);
        if (!pendingSnap.exists) {
          tx.set(
            pendingRef,
            pendingOnchainData(
              uid: uid,
              signature: signature,
              kind: kind,
              startedAt: DateTime.now().millisecondsSinceEpoch,
              note: kMarkerHeldNote,
            ),
          );
        } else if (pendingSnap.data()?['status'] != 'done') {
          tx.update(pendingRef, {'note': kMarkerHeldNote});
        }
        return OnchainCommitResult.heldByAnotherAccount;
      }

      if (onchainSnap.exists && onchainSnap.data()?['uid'] != uid)
        return held();
      if (onchainSnap.exists) return OnchainCommitResult.alreadyProcessed;

      final markerSnap = await tx.get(markerRef);
      if (markerSnap.exists) {
        return markerSnap.data()?['uid'] == uid
            ? OnchainCommitResult.alreadyProcessed
            : held();
      }
      final userSnap = await tx.get(userRef);
      final pendingSnap = await tx.get(pendingRef);

      final user = userSnap.data();
      if (user == null) throw StateError('User profile not found.');

      tx.update(userRef, buildUserUpdate(user));
      tx.set(markerRef, markerData);
      // Exactly these keys: the rules reject anything else.
      tx.set(
        onchainRef,
        onchainMarkerData(
          uid: uid,
          signature: signature,
          markerId: markerId,
          markedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (pendingSnap.exists) {
        tx.update(pendingRef, {
          'status': 'done',
          'completedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
      return OnchainCommitResult.credited;
    });
  } on FirebaseException catch (e) {
    if (e.code != 'permission-denied') rethrow;
    await notePendingOnchain(
      firestore: firestore,
      uid: uid,
      signature: signature,
      note: kRefusedByRulesNote,
      kind: kind,
    );
    return OnchainCommitResult.refusedByRules;
  }
}

/// Credits a deposit: shared marker + deposit marker + `FieldValue.increment`
/// (never read-then-add), all in one transaction.
Future<OnchainCommitResult> creditOnchainDeposit({
  required FirebaseFirestore firestore,
  required String uid,
  required String signature,
  required String markerId,
  required double phpAmount,
  required Map<String, dynamic> markerData,
}) => commitOnceByMarker(
  firestore: firestore,
  uid: uid,
  signature: signature,
  markerId: markerId,
  markerData: markerData,
  buildUserUpdate: (_) => {'tyxBalance': FieldValue.increment(phpAmount)},
);

/// Activates Hybrid PRO for [uid] after an on-chain payment, once per signature.
/// Same user fields and `sub_sol_<signature>` record as the original Solana
/// flow, but the new expiry extends from max(now, current premiumUntil) so
/// paying while already subscribed never shortens or resets the plan.
Future<OnchainCommitResult> activateSubscriptionOnce({
  required FirebaseFirestore firestore,
  required String uid,
  required String signature,
  required String plan, // 'yearly' | 'monthly'
  required double phpAmount,
  required double cryptoAmount,
  String method = 'Solana Mobile Wallet',
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final yearly = plan == 'yearly';
  return commitOnceByMarker(
    firestore: firestore,
    uid: uid,
    signature: signature,
    markerId: 'sub_sol_$signature',
    markerData: {
      'uid': uid,
      'type': 'subscription',
      'amount': phpAmount,
      'title': 'Hybrid PRO Subscription (${yearly ? 'Yearly' : 'Monthly'})',
      'desc': 'Subscribed via $method (${cryptoAmount.toStringAsFixed(4)} SOL)',
      'method': method,
      'solanaTxSignature': signature,
      'createdAt': at.millisecondsSinceEpoch,
    },
    buildUserUpdate: (user) => {
      'isPremium': true,
      'premiumUntil': nextPremiumUntilMs(
        currentPremiumUntilMs: (user['premiumUntil'] as num?)?.toInt(),
        nowMs: at.millisecondsSinceEpoch,
        plan: plan,
      ),
      'accountType': 'hybrid',
    },
  );
}
