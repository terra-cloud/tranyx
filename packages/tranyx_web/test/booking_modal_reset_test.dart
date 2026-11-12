import 'dart:io';

import 'package:test/test.dart';

/// Source contract: the booking modals are Jaspr web components that can't be
/// mounted in the VM, so check that the selection-change reset block clears
/// all per-rental booking state.
String _resetBlock(String path, String guard) {
  final src = File(path).readAsStringSync();
  final start = src.indexOf(guard);
  expect(start, isNot(-1), reason: 'reset guard not found in $path');
  final end = src.indexOf('\n    }\n', start);
  return src.substring(start, end);
}

void main() {
  test('property booking modal resets state when the property changes', () {
    final block = _resetBlock('lib/client/components/book_property_modal.dart', 'if (_lastPropertyId != propertyId) {');
    for (final s in [
      '_multiplier = 1;',
      '_startDate = null;',
      '_calendarMonth = DateTime.now();',
      '_approvedRequests = [];',
      '_error = null;',
      '_step = 1;',
    ]) {
      expect(block, contains(s));
    }
  });

  test('vehicle booking modal resets _error when the vehicle changes', () {
    final block = _resetBlock('lib/client/components/book_vehicle_modal.dart', 'if (_lastRentalId != rentalId) {');
    expect(block, contains('_error = null;'));
    expect(block, contains('_approvedRequests = [];'));
  });
}
