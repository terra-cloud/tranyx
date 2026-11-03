/// A Cloud Function (callable) call that did not return a result. [status] is the callable error
/// status (UNAUTHENTICATED, FAILED_PRECONDITION, RESOURCE_EXHAUSTED, ...), or NETWORK when the
/// outcome is unknown and the same request can safely be retried.
class CloudFunctionException implements Exception {
  const CloudFunctionException(this.status, this.message);
  final String status;
  final String message;

  bool get isIndeterminate =>
      status == 'NETWORK' ||
      status == 'INTERNAL' ||
      status == 'UNAVAILABLE' ||
      status == 'DEADLINE_EXCEEDED';

  /// The same exception with text a person can act on, for money callables (job posting, hiring,
  /// bookings). A network failure or a missing function (HTTP 404) means the outcome is unknown or
  /// the service is not reachable; retrying with the same idempotency key is always safe.
  CloudFunctionException forMoneyUi() {
    if (status == 'NETWORK') {
      return CloudFunctionException(
        status,
        'Could not reach the Tranyx payment service. Nothing was charged twice and retrying is safe. If it keeps failing, contact support.',
      );
    }
    if (status == 'INTERNAL' && message.contains('(404)')) {
      return CloudFunctionException(
        status,
        'The payment service is not available in this environment yet. Nothing was charged. Please contact support.',
      );
    }
    return this;
  }

  @override
  String toString() => message;
}
