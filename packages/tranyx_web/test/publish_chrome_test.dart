import 'dart:io';

import 'package:test/test.dart';
import 'package:tranyx_web/client/publish_chrome.dart';

void main() {
  test('hides the mobile bar while a publish form is open', () {
    expect(
      hideMobileChromeForPublish(
        jobTracking: false,
        creatingJob: true,
        listingVehicle: false,
        listingProperty: false,
        editingVehicle: false,
        editingProperty: false,
      ),
      isTrue,
    );
    expect(
      hideMobileChromeForPublish(
        jobTracking: false,
        creatingJob: false,
        listingVehicle: true,
        listingProperty: false,
        editingVehicle: false,
        editingProperty: false,
      ),
      isTrue,
    );
    expect(
      hideMobileChromeForPublish(
        jobTracking: false,
        creatingJob: false,
        listingVehicle: false,
        listingProperty: true,
        editingVehicle: false,
        editingProperty: false,
      ),
      isTrue,
    );
    expect(
      hideMobileChromeForPublish(
        jobTracking: false,
        creatingJob: false,
        listingVehicle: false,
        listingProperty: false,
        editingVehicle: false,
        editingProperty: false,
      ),
      isFalse,
    );
  });

  test('publish actions are docked above the safe area on a phone', () {
    final css = File('web/styles.css').readAsStringSync();
    expect(css, contains('.publish-dock'));
    expect(css, contains('env(safe-area-inset-bottom, 0px)'));
    expect(css, contains('@media (max-width: 767px)'));
    for (final path in [
      'lib/client/views/jobs_view.dart',
      'lib/client/components/list_vehicle_modal.dart',
      'lib/client/components/list_property_modal.dart',
    ]) {
      expect(File(path).readAsStringSync(), contains('publish-dock'), reason: path);
    }
  });
}
