import 'package:test/test.dart';
import 'package:tranyx_web/services/firebase_service.dart';

void main() {
  test('permission ref is PD-XXXX-XX with 6 unambiguous chars', () {
    final re = RegExp(r'^PD-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{2}$');
    for (var i = 0; i < 200; i++) {
      expect(newPermissionRef(), matches(re));
    }
  });
  test('detects permission-denied errors', () {
    expect(isPermissionDeniedError(FirebaseException('x', 403)), isTrue);
    expect(isPermissionDeniedError(FirebaseException('Missing or insufficient permissions.')), isTrue);
    expect(isPermissionDeniedError(FirebaseException('PERMISSION_DENIED', 400)), isTrue);
    expect(isPermissionDeniedError(FirebaseException('Not found', 404)), isFalse);
  });
}
