import 'package:test/test.dart';
import 'package:headless_nav_core/headless_nav_core.dart';

void main() {
  group('GeoMath', () {
    test('calculates accurate Haversine distance between two coordinates', () {
      // Coordinates: Manila (14.5995, 120.9842) to Makati (14.5547, 121.0244)
      final dist = GeoMath.distanceMeters(14.5995, 120.9842, 14.5547, 121.0244);
      expect(dist, greaterThan(6500.0));
      expect(dist, lessThan(7500.0));
    });

    test('calculates accurate compass bearing', () {
      // Due North
      final northBearing = GeoMath.calculateBearing(0.0, 0.0, 1.0, 0.0);
      expect(northBearing, closeTo(0.0, 0.5));

      // Due East
      final eastBearing = GeoMath.calculateBearing(0.0, 0.0, 0.0, 1.0);
      expect(eastBearing, closeTo(90.0, 0.5));

      // Due South
      final southBearing = GeoMath.calculateBearing(1.0, 0.0, 0.0, 0.0);
      expect(southBearing, closeTo(180.0, 0.5));

      // Due West
      final westBearing = GeoMath.calculateBearing(0.0, 1.0, 0.0, 0.0);
      expect(westBearing, closeTo(270.0, 0.5));
    });

    test('snaps raw GPS point to the closest coordinate on a route line', () {
      final lineCoords = [
        [121.000, 14.500],
        [121.010, 14.500],
      ];

      // Point slightly north of the line segment
      final rawPos = NavPosition.now(latitude: 14.501, longitude: 121.005);
      final snapResult = GeoMath.snapToRoute(rawPos, lineCoords);

      expect(snapResult.snappedPosition.latitude, closeTo(14.500, 0.0005));
      expect(snapResult.snappedPosition.longitude, closeTo(121.005, 0.0005));
      expect(snapResult.distanceFromRouteMeters, greaterThan(50.0));
      expect(snapResult.distanceFromRouteMeters, lessThan(150.0));
      expect(snapResult.bearing, closeTo(90.0, 1.0)); // Segment goes due East
    });

    test('slices remaining route geometry from snapped position', () {
      final lineCoords = [
        [121.000, 14.500],
        [121.005, 14.500],
        [121.010, 14.500],
      ];

      final snappedPos = NavPosition.now(latitude: 14.500, longitude: 121.005);
      final sliced = GeoMath.sliceRemainingRoute(snappedPos, lineCoords, 1);

      expect(sliced.isNotEmpty, isTrue);
      expect(sliced.last, equals([121.010, 14.500]));
    });
  });
}
