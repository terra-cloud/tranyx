import 'package:cloud_firestore/cloud_firestore.dart';

/// One shared marker per on-chain signature. Every flow that turns a Solana
/// payment into balance or a subscription (MWA, Phantom, Solflare, Trust Wallet;
/// deposit and subscription) creates `transactions/onchain_<sig>` inside the same
/// Firestore transaction as its credit and refuses when it already exists, so one
/// signature can be credited exactly once no matter which flow submits it.
///
/// The marker has no `createdAt` on purpose: the history query orders by
/// `createdAt`, so these bookkeeping docs never show up as transactions.
String onchainMarkerId(String signature) => 'onchain_$signature';

/// Bookkeeping record written as soon as the wallet returns a signature, before
/// we wait for finalization. `status` is `pending` until the credit commits
/// (then `done`); otherwise it stays `pending` (with `note`) for support.
///
/// The id carries the owner's uid (`pending_onchain_<uid>_<sig>`): the rules only
/// let that account create or update it, so nobody can squat another account's
/// pending record by guessing the signature.
String pendingOnchainId(String uid, String signature) =>
    'pending_onchain_${uid}_$signature';

/// Outcome of an on-chain credit attempt.
enum OnchainCommitResult {
  /// Balance / subscription updated and markers written.
  credited,

  /// This account already processed the signature (replay, double tap).
  alreadyProcessed,

  /// A marker for this signature belongs to ANOTHER account. Nothing was
  /// credited; the caller's pending record stays open with a note for support.
  heldByAnotherAccount,
}

/// Shown instead of a silent refusal when a signature's marker is held by
/// another account.
class OnchainSupportException implements Exception {
  OnchainSupportException(this.signature);
  final String signature;
  String get message =>
      'This payment could not be credited automatically. Contact support with signature $signature.';
  @override
  String toString() => message;
}

extension OnchainCommitResultX on OnchainCommitResult {
  /// Throws [OnchainSupportException] (the UI shows "Contact support with
  /// signature <sig>") when the marker is held by another account.
  void throwIfHeldElsewhere(String signature) {
    if (this == OnchainCommitResult.heldByAnotherAccount)
      throw OnchainSupportException(signature);
  }
}

const kMarkerHeldNote = 'marker held by another account';

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
      tx.set(ref, {
        'uid': uid,
        'type': 'onchain_pending',
        'kind': kind,
        'status': 'pending',
        'solanaTxSignature': signature,
        'phpAmount': phpAmount,
        'cryptoAmount': cryptoAmount,
        'currency': currency,
        'startedAt': DateTime.now().millisecondsSinceEpoch,
      });
    });
  } catch (_) {}
}

/// Leaves the pending record pending and notes why, for support. Best effort.
Future<void> notePendingOnchain({
  required FirebaseFirestore firestore,
  required String uid,
  required String signature,
  required String note,
}) async {
  try {
    final ref = firestore
        .collection('transactions')
        .doc(pendingOnchainId(uid, signature));
    final snap = await ref.get();
    if (snap.exists && snap.data()?['status'] == 'pending') {
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
///   older credit ([OnchainCommitResult.alreadyProcessed]).
///
/// If a legacy per-flow marker of another account can't be read (rules deny the
/// read), that is also reported as [OnchainCommitResult.heldByAnotherAccount]
/// and the pending record is noted, instead of surfacing a raw error.
Future<OnchainCommitResult> commitOnceByMarker({
  required FirebaseFirestore firestore,
  required String uid,
  required String signature,
  required String markerId,
  required Map<String, dynamic> markerData,
  required Map<String, dynamic> Function(Map<String, dynamic> user)
  buildUserUpdate,
}) async {
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
          tx.set(pendingRef, {
            'uid': uid,
            'type': 'onchain_pending',
            'kind': markerData['type'] == 'subscription'
                ? 'subscription'
                : 'deposit',
            'status': 'pending',
            'solanaTxSignature': signature,
            'startedAt': DateTime.now().millisecondsSinceEpoch,
            'note': kMarkerHeldNote,
          });
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
      tx.set(onchainRef, {
        'uid': uid,
        'type': 'onchain_marker',
        'solanaTxSignature': signature,
        'markerId': markerId,
        'markedAt': DateTime.now().millisecondsSinceEpoch,
      });
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
      note: '$kMarkerHeldNote (marker not readable)',
    );
    return OnchainCommitResult.heldByAnotherAccount;
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
  final days = Duration(days: yearly ? 365 : 30);
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
    buildUserUpdate: (user) {
      final current = (user['premiumUntil'] as num?)?.toInt() ?? 0;
      final base = current > at.millisecondsSinceEpoch
          ? current
          : at.millisecondsSinceEpoch;
      return {
        'isPremium': true,
        'premiumUntil': base + days.inMilliseconds,
        'accountType': 'hybrid',
      };
    },
  );
}
