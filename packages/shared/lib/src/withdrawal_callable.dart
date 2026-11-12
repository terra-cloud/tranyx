import 'dart:math';

/// Server-side withdrawal rejection (KAN-146) from the `requestWithdrawal` Cloud Function.
/// [status] is the callable error status (FAILED_PRECONDITION, RESOURCE_EXHAUSTED, ...), or
/// NETWORK when the outcome is unknown: retry with the SAME idempotency key.
class WithdrawalException implements Exception {
  final String status;
  final String message;
  const WithdrawalException(this.status, this.message);

  bool get isIndeterminate =>
      status == 'NETWORK' ||
      status == 'INTERNAL' ||
      status == 'UNAVAILABLE' ||
      status == 'DEADLINE_EXCEEDED';

  @override
  String toString() => message;
}

/// User-facing text for the generic `failureReason` code returned by the `requestWithdrawal` function
/// (KAN-146 K6: the server never returns internal error text; details stay in server logs).
String withdrawalFailureMessage(Object? code) {
  switch (code?.toString()) {
    case 'PREPARE_FAILED':
      return 'The transfer could not be prepared.';
    case 'ONCHAIN_ERROR':
      return 'The network rejected the transfer.';
    case 'EXPIRED_NOT_LANDED':
      return 'The transfer did not confirm in time.';
    default:
      return 'The transfer failed.';
  }
}

/// RFC 4122 v4 UUID used as the withdrawal idempotency key (becomes the request doc id).
String newIdempotencyKey() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-${h(8)}${h(9)}-'
      '${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}
