import 'dart:io';

import 'package:test/test.dart';

/// Source contracts for the W37 manage view (Jaspr web components can't be mounted in the VM).
void main() {
  final app = File('lib/client/tranyx_app.dart').readAsStringSync();
  final book = File('lib/client/components/book_vehicle_modal.dart').readAsStringSync();
  final view = File('lib/client/views/transit_view.dart').readAsStringSync();

  test('vehicle details no longer render empty for the owner', () {
    expect(book, isNot(contains("r['hostId'] == currentUid) {\n      return div([]);")));
    expect(book, contains("You cannot book your own listing."));
  });

  test('browse Manage buttons open W37 through the owner-checked helpers', () {
    expect(view, contains('s.openManageVehicle(r)'));
    expect(view, contains('s.openManageProperty(prop.toMap())'));
    expect(app, contains('if (bookingLockId != null || !ownsListing(r)) return;'));
    expect(app, contains('if (bookingLockId != null || !ownsListing(prop)) return;'));
  });

  test('manage renders in the side panel at >=1024 and as a page below', () {
    expect(app, contains("showManageVehicleModal && !rentalsPanelMode"));
    expect(app, contains("showManagePropertyModal && !rentalsPanelMode"));
    expect(app, contains("(showManageVehicleModal && selectedRentalData != null) ||"));
  });

  test('deep link #/rentals/<id>/manage is recognised', () {
    final re = RegExp(r'^#/rentals/([A-Za-z0-9_\-]{1,128})(/manage)?$');
    expect(app, contains(r"(/manage)?$"));
    expect(re.firstMatch('#/rentals/abc_1/manage')?.group(2), '/manage');
    expect(re.firstMatch('#/rentals/abc_1')?.group(2), isNull);
    expect(re.hasMatch('#/rentals/abc/manage/x'), isFalse);
  });

  test('one owner check (hostId ?? ownerId) shared by manage and booking', () {
    expect(app, contains("data?['hostId'] ?? data?['ownerId']"));
    for (final f in ['manage_vehicle_modal.dart', 'manage_property_modal.dart', 'book_vehicle_modal.dart', 'book_property_modal.dart']) {
      final s = File('lib/client/components/$f').readAsStringSync();
      expect(s, contains('component.appState.ownsListing('), reason: f);
    }
    final bp = File('lib/client/components/book_property_modal.dart').readAsStringSync();
    expect(bp, contains('You cannot book your own listing.'));
  });

  for (final f in ['manage_vehicle_modal.dart', 'manage_property_modal.dart']) {
    test('$f drops stale results and has a back arrow', () {
      final s = File('lib/client/components/$f').readAsStringSync();
      expect(s, contains('bool get _stillSelected'));
      expect(s, contains('if (!_stillSelected) return;'));
      expect(s, contains('component.appState.backFromManage()'));
      expect(s, contains('component.appState.closeManage()'));
    });
  }
}
