import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('CloudFunctionException.forMoneyUi', () {
    test('a network failure says retrying is safe and keeps the indeterminate status', () {
      final e = const CloudFunctionException('NETWORK', 'Network error. Please retry.').forMoneyUi();
      expect(e.status, 'NETWORK');
      expect(e.isIndeterminate, isTrue);
      expect(e.message, contains('retrying is safe'));
    });

    test('a missing function (HTTP 404) says the service is not available, never "network error"', () {
      final e = const CloudFunctionException('INTERNAL', 'Unexpected server response (404).').forMoneyUi();
      expect(e.message, contains('not available in this environment'));
      expect(e.message.toLowerCase(), isNot(contains('network')));
    });

    test('server answers (permission, balance, state) pass through untouched', () {
      const a = CloudFunctionException('FAILED_PRECONDITION', 'Insufficient available balance.');
      const b = CloudFunctionException('PERMISSION_DENIED', 'Only the employer can hire.');
      expect(identical(a.forMoneyUi(), a), isTrue);
      expect(b.forMoneyUi().message, 'Only the employer can hire.');
    });
  });
}
