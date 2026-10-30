/// Platform-neutral pieces of the "credit an on-chain payment exactly once" flow,
/// shared by the mobile (Firestore SDK) and web (Firestore REST) clients.
///
/// One marker per signature: every flow that turns a Solana payment into balance
/// or a subscription creates `transactions/onchain_<sig>` in the same Firestore
/// transaction as its credit, after reading it first. The IO (transactions) stays
/// in each client; ids, document shapes, notes and results live here so both
/// clients write exactly what the Firestore rules accept.
library;

/// Shared marker doc id: one per on-chain signature.
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

/// Note left on the caller's pending record when the shared (or per-flow) marker
/// belongs to another account.
const kMarkerHeldNote = 'marker held by another account';

/// Note left when the rules refused the credit (permission-denied) without a
/// foreign marker having been read.
const kRefusedByRulesNote = 'credit refused by rules (permission-denied)';

/// Note left when the credit transaction kept aborting on contention (409 /
/// `aborted`) and every retry failed. Nothing was credited.
const kContentionNote = 'contention, retry';

/// The only keys the rules accept on `onchain_<sig>`.
const kOnchainMarkerKeys = {
  'uid',
  'type',
  'solanaTxSignature',
  'markerId',
  'markedAt',
};

/// Outcome of an on-chain credit attempt.
enum OnchainCommitResult {
  /// Balance / subscription updated and markers written.
  credited,

  /// This account already processed the signature (replay, double tap).
  alreadyProcessed,

  /// A marker for this signature belongs to ANOTHER account (it was read).
  /// Nothing was credited; the caller's pending record stays open with a note.
  heldByAnotherAccount,

  /// The rules refused the credit (permission-denied) and no foreign marker was
  /// read. Nothing was credited; the pending record stays open with a note.
  refusedByRules,

  /// The server verified the transaction and refused it (wrong wallet, wrong
  /// destination or amount, failed transaction, ...). Nothing was credited; the
  /// server left a note on the pending record for support.
  rejectedByServer,
}

/// Shown instead of a silent refusal when a credit could not be applied and
/// needs support.
class OnchainSupportException implements Exception {
  OnchainSupportException(this.signature);
  final String signature;
  String get message =>
      'This payment could not be credited automatically. Contact support with signature $signature.';
  @override
  String toString() => message;
}

extension OnchainCommitResultX on OnchainCommitResult {
  /// Whether the user has to contact support (nothing was credited and no replay).
  bool get needsSupport =>
      this == OnchainCommitResult.heldByAnotherAccount ||
      this == OnchainCommitResult.refusedByRules ||
      this == OnchainCommitResult.rejectedByServer;

  /// Throws [OnchainSupportException] (the UI shows "Contact support with
  /// signature <sig>") for [OnchainCommitResult.heldByAnotherAccount] and
  /// [OnchainCommitResult.refusedByRules] and [OnchainCommitResult.rejectedByServer].
  void throwIfHeldElsewhere(String signature) {
    if (needsSupport) throw OnchainSupportException(signature);
  }

  /// The note stored on the pending record for this outcome (null when none).
  String? get pendingNote => switch (this) {
    OnchainCommitResult.heldByAnotherAccount => kMarkerHeldNote,
    OnchainCommitResult.refusedByRules => kRefusedByRulesNote,
    _ => null,
  };
}

/// Exactly the five keys the rules allow on `onchain_<sig>`, `type` fixed.
Map<String, dynamic> onchainMarkerData({
  required String uid,
  required String signature,
  required String markerId,
  required int markedAt,
}) => {
  'uid': uid,
  'type': 'onchain_marker',
  'solanaTxSignature': signature,
  'markerId': markerId,
  'markedAt': markedAt,
};

/// The pending record for an in-flight payment. No `createdAt`: the history
/// query orders by it, so bookkeeping docs never show as transactions.
Map<String, dynamic> pendingOnchainData({
  required String uid,
  required String signature,
  required String kind, // 'deposit' | 'subscription'
  required int startedAt,
  double? phpAmount,
  double? cryptoAmount,
  String? currency,
  String? note,
}) => {
  'uid': uid,
  'type': 'onchain_pending',
  'kind': kind,
  'status': 'pending',
  'solanaTxSignature': signature,
  if (phpAmount != null) 'phpAmount': phpAmount,
  if (cryptoAmount != null) 'cryptoAmount': cryptoAmount,
  if (currency != null) 'currency': currency,
  'startedAt': startedAt,
  if (note != null) 'note': note,
};

/// Subscription expiry: extends from max(now, current premiumUntil) so paying
/// while still subscribed never shortens or resets the plan.
int nextPremiumUntilMs({
  required int? currentPremiumUntilMs,
  required int nowMs,
  required String plan,
}) {
  final days = plan == 'yearly' ? 365 : 30;
  final current = currentPremiumUntilMs ?? 0;
  final base = current > nowMs ? current : nowMs;
  return base + Duration(days: days).inMilliseconds;
}
