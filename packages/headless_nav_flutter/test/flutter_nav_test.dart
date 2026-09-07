import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:headless_nav_flutter/headless_nav_flutter.dart';

void main() {
  test('headless_nav_flutter providers and models instantiate correctly', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Initial state check
    expect(container.read(navEngineProvider), isNull);
    expect(container.read(travelModeProvider), equals(NavTravelMode.car));
    expect(container.read(isBroadcastingActiveProvider), isFalse);
    expect(container.read(activeBroadcastChannelProvider), isNull);

    // Travel mode update
    container.read(travelModeProvider.notifier).state = NavTravelMode.motorcycle;
    expect(container.read(travelModeProvider), equals(NavTravelMode.motorcycle));
  });

  test('GeolocatorAdapter is defined and instantiable', () {
    final adapter = GeolocatorAdapter();
    expect(adapter.distanceFilter, equals(2));
  });
}
