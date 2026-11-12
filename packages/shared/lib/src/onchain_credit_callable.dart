/// Client side of the server-side crediting of on-chain payments (the `creditOnchainPayment` Cloud
/// Function). The clients no longer write balances or markers: they send `{signature, kind, plan?}`
/// and the server verifies the finalized transaction, recomputes the PHP value and credits once.
library;

import 'cloud_function_exception.dart';
import 'onchain_credit.dart';

/// What the payment is for. The wire value is the callable's `kind`.
enum OnchainCreditKind {
  depositSol('deposit_sol'),
  depositUsdt('deposit_usdt'),
  subscriptionSol('subscription_sol');

  const OnchainCreditKind(this.wire);
  final String wire;

  String get pendingKind => this == subscriptionSol ? 'subscription' : 'deposit';
}

/// Parsed `creditOnchainPayment` response.
class OnchainCreditResponse {
  const OnchainCreditResponse({
    required this.status,
    this.reason,
    this.phpAmount,
    this.cryptoAmount,
    this.currency,
    this.premiumUntil,
  });

  /// credited | already_processed | held_by_another_account | not_finalized | rejected
  final String status;

  /// Fixed code when [status] is `rejected` (e.g. NO_MATCHING_TRANSFER). Never internal error text.
  final String? reason;
  final double? phpAmount;
  final double? cryptoAmount;
  final String? currency;
  final int? premiumUntil;

  factory OnchainCreditResponse.fromMap(Map<String, dynamic> m) => OnchainCreditResponse(
    status: (m['status'] ?? '').toString(),
    reason: m['reason']?.toString(),
    phpAmount: (m['phpAmount'] as num?)?.toDouble(),
    cryptoAmount: (m['cryptoAmount'] as num?)?.toDouble(),
    currency: m['currency']?.toString(),
    premiumUntil: (m['premiumUntil'] as num?)?.toInt(),
  );

  bool get isNotFinalized => status == 'not_finalized';

  /// Maps the server status onto the result the UI already understands. Unknown statuses are
  /// treated as a refusal (nothing credited, contact support).
  OnchainCommitResult get result => switch (status) {
    'credited' => OnchainCommitResult.credited,
    'already_processed' => OnchainCommitResult.alreadyProcessed,
    'held_by_another_account' => OnchainCommitResult.heldByAnotherAccount,
    _ => OnchainCommitResult.rejectedByServer,
  };
}

/// Sends one request to the server (platform specific: mobile http + App Check, web REST).
typedef CreditInvoker = Future<Map<String, dynamic>> Function(Map<String, dynamic> data);

/// Asks the server to credit [signature], polling while the transaction is not finalized yet.
/// Throws [OnchainSupportException] when it is still not finalized after [timeout] (the pending
/// record stays open for support), and rethrows [CloudFunctionException] for hard failures.
Future<OnchainCreditResponse> creditOnchainViaServer({
  required CreditInvoker invoke,
  required String signature,
  required OnchainCreditKind kind,
  String? plan, // 'monthly' | 'yearly' (subscription only)
  Duration pollEvery = const Duration(seconds: 3),
  Duration timeout = const Duration(seconds: 150),
  Future<void> Function(Duration)? sleep,
  DateTime Function()? clock,
}) async {
  final wait = sleep ?? (Duration d) => Future<void>.delayed(d);
  final now = clock ?? DateTime.now;
  final deadline = now().add(timeout);
  while (true) {
    final map = await invoke({
      'signature': signature,
      'kind': kind.wire,
      if (kind == OnchainCreditKind.subscriptionSol) 'plan': plan == 'yearly' ? 'yearly' : 'monthly',
    });
    final res = OnchainCreditResponse.fromMap(map);
    if (!res.isNotFinalized) return res;
    if (!now().isBefore(deadline)) throw OnchainSupportException(signature);
    await wait(pollEvery);
  }
}
