import 'package:test/test.dart';
import 'package:headless_nav_core/headless_nav_core.dart';

void main() {
  group('GeoComputationDispatcher', () {
    test('computes navigation tick via background isolate without errors', () async {
      final dispatcher = const GeoComputationDispatcher(enableBackgroundIsolates: true);

      final routeCoords = [
        [121.000, 14.500],
        [121.010, 14.500],
        [121.020, 14.500],
      ];

      final steps = [
        const OsrmStep(
          distance: 1000.0,
          duration: 100.0,
          name: 'First St',
          geometryCoordinates: [
            [121.000, 14.500],
            [121.010, 14.500],
          ],
          maneuver: OsrmManeuver(
            type: 'depart',
            location: [121.000, 14.500],
          ),
        ),
        const OsrmStep(
          distance: 1000.0,
          duration: 100.0,
          name: 'Second St',
          geometryCoordinates: [
            [121.010, 14.500],
            [121.020, 14.500],
          ],
          maneuver: OsrmManeuver(
            type: 'turn',
            modifier: 'right',
            location: [121.010, 14.500],
          ),
        ),
      ];

      final rawPos = NavPosition.now(latitude: 14.5005, longitude: 121.005);

      final result = await dispatcher.computeTick(
        rawPosition: rawPos,
        routeCoordinates: routeCoords,
        steps: steps,
        currentStepIndex: 0,
        routeTotalDistance: 2000.0,
        routeTotalDuration: 200.0,
        offRouteThresholdMeters: 40.0,
        arrivalThresholdMeters: 15.0,
      );

      expect(result.snappedPosition.latitude, closeTo(14.500, 0.0005));
      expect(result.isOffRoute, isTrue); // ~55m away from 14.500
      expect(result.hasArrived, isFalse);
      expect(result.remainingDistance, greaterThan(1000.0));
      expect(result.slicedRouteCoordinates.isNotEmpty, isTrue);
    });
  });
}
