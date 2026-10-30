import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/core/services/cloud_function_client.dart';

// Ids, notes, results and document shapes live in packages/shared so the web
// client writes exactly the same thing. Re-exported for existing imports.
export 'package:shared/shared.dart'
    show
        OnchainCommitResult,
        OnchainCommitResultX,
        OnchainCreditKind,
        OnchainCreditResponse,
        OnchainSupportException,
        kContentionNote,
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

/// Asks the `creditOnchainPayment` Cloud Function to credit [signature] once.
///
/// The app no longer writes balances or markers: the server reads the FINALIZED transaction,
/// checks the payer is the linked wallet and the destination is the treasury, recomputes the PHP
/// value from its own rate source and writes the markers + credit in one Admin SDK transaction.
/// While the transaction is not finalized yet the call is repeated. A refusal leaves a note on the
/// caller's pending record (server side) and is returned as
/// [OnchainCommitResult.heldByAnotherAccount] / [OnchainCommitResult.rejectedByServer] so the UI shows
/// "Contact support with signature ...". Network failures rethrow [CloudFunctionException].
Future<OnchainCommitResult> creditOnchainOnServer({
  required FirebaseFirestore firestore,
  required String uid,
  required String signature,
  required OnchainCreditKind kind,
  String? plan,
  CreditInvoker? invoke,
}) async {
  try {
    final res = await creditOnchainViaServer(
      invoke: invoke ?? (data) => callCloudFunction('creditOnchainPayment', data),
      signature: signature,
      kind: kind,
      plan: plan,
    );
    if (res.result.needsSupport) {
      // The server already noted rejections; a foreign marker is noted here (own pending record only).
      if (res.result == OnchainCommitResult.heldByAnotherAccount) {
        await notePendingOnchain(
          firestore: firestore,
          uid: uid,
          signature: signature,
          note: kMarkerHeldNote,
          kind: kind.pendingKind,
        );
      }
    }
    return res.result;
  } on OnchainSupportException {
    await notePendingOnchain(
      firestore: firestore,
      uid: uid,
      signature: signature,
      note: 'not finalized in time, retry',
      kind: kind.pendingKind,
    );
    rethrow;
  }
}

/// Credits a SOL/USDT deposit for [signature]. The PHP amount is computed by the server.
Future<OnchainCommitResult> creditOnchainDeposit({
  required FirebaseFirestore firestore,
  required String uid,
  required String signature,
  required bool isUsdt,
  CreditInvoker? invoke,
}) => creditOnchainOnServer(
  firestore: firestore,
  uid: uid,
  signature: signature,
  kind: isUsdt ? OnchainCreditKind.depositUsdt : OnchainCreditKind.depositSol,
  invoke: invoke,
);

/// Activates Hybrid PRO for [uid] after an on-chain SOL payment, once per signature (server side).
/// The expiry extends from max(now, premiumUntil); the server checks the paid value covers the plan.
Future<OnchainCommitResult> activateSubscriptionOnce({
  required FirebaseFirestore firestore,
  required String uid,
  required String signature,
  required String plan, // 'yearly' | 'monthly'
  CreditInvoker? invoke,
}) => creditOnchainOnServer(
  firestore: firestore,
  uid: uid,
  signature: signature,
  kind: OnchainCreditKind.subscriptionSol,
  plan: plan,
  invoke: invoke,
);
