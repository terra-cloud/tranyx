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

  @override
  String toString() => message;
}
