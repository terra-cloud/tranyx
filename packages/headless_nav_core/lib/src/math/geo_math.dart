import 'dart:math' as math;
import 'package:turf/turf.dart' as turf;
import '../models/nav_position.dart';

/// Comprehensive spatial math utilities wrapping package:turf and high-performance
/// geodesic algorithms.
class GeoMath {
  GeoMath._();

  /// Earth radius in meters (WGS 84 mean radius).
  static const double earthRadiusMeters = 6371008.8;

  static const double _degToRad = math.pi / 180.0;
  static const double _radToDeg = 180.0 / math.pi;

  /// Calculates the Haversine distance between two coordinates in meters.
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = (lat2 - lat1) * _degToRad;
    final dLon = (lon2 - lon1) * _degToRad;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * _degToRad) *
            math.cos(lat2 * _degToRad) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Calculates the geographic bearing in degrees [0, 360) from (lat1, lon1) to (lat2, lon2).
  static double calculateBearing(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final y = math.sin((lon2 - lon1) * _degToRad) * math.cos(lat2 * _degToRad);
    final x = math.cos(lat1 * _degToRad) * math.sin(lat2 * _degToRad) -
        math.sin(lat1 * _degToRad) *
            math.cos(lat2 * _degToRad) *
            math.cos((lon2 - lon1) * _degToRad);
    final bearing = math.atan2(y, x) * _radToDeg;
    return (bearing + 360.0) % 360.0;
  }

  /// Projects a raw [NavPosition] onto a route coordinate polyline [[lon, lat], ...].
  static SnapResult snapToRoute(
    NavPosition rawPosition,
    List<List<double>> routeCoordinates,
  ) {
    if (routeCoordinates.isEmpty) {
      return SnapResult(
        snappedPosition: rawPosition,
        distanceFromRouteMeters: 0.0,
        segmentIndex: 0,
        bearing: rawPosition.heading ?? 0.0,
      );
    }

    if (routeCoordinates.length == 1) {
      final single = routeCoordinates.first;
      final dist = distanceMeters(
        rawPosition.latitude,
        rawPosition.longitude,
        single[1],
        single[0],
      );
      return SnapResult(
        snappedPosition: rawPosition.copyWith(
          latitude: single[1],
          longitude: single[0],
        ),
        distanceFromRouteMeters: dist,
        segmentIndex: 0,
        bearing: rawPosition.heading ?? 0.0,
      );
    }

    try {
      final turfLine = turf.LineString(
        coordinates: routeCoordinates
            .map((c) => turf.Position(c[0], c[1]))
            .toList(),
      );

      final turfPoint = turf.Point(
        coordinates: turf.Position(rawPosition.longitude, rawPosition.latitude),
      );
      final nearestFeature = turf.nearestPointOnLine(turfLine, turfPoint);

      final snappedCoord = nearestFeature.geometry?.coordinates;
      final snappedLon = snappedCoord?[0]?.toDouble() ?? rawPosition.longitude;
      final snappedLat = snappedCoord?[1]?.toDouble() ?? rawPosition.latitude;

      final props = nearestFeature.properties;
      final distKm = (props?['distanceToPoint'] as num?)?.toDouble() ??
          (distanceMeters(rawPosition.latitude, rawPosition.longitude, snappedLat, snappedLon) / 1000.0);
      final segmentIdx = (props?['index'] as num?)?.toInt() ?? 0;

      // Bearing of the current segment
      final nextIdx = (segmentIdx + 1 < routeCoordinates.length)
          ? segmentIdx + 1
          : segmentIdx;
      final p1 = routeCoordinates[segmentIdx];
      final p2 = routeCoordinates[nextIdx];
      final segmentBearing = calculateBearing(p1[1], p1[0], p2[1], p2[0]);

      return SnapResult(
        snappedPosition: rawPosition.copyWith(
          latitude: snappedLat,
          longitude: snappedLon,
          heading: segmentBearing,
        ),
        distanceFromRouteMeters: distKm * 1000.0,
        segmentIndex: segmentIdx,
        bearing: segmentBearing,
      );
    } catch (_) {
      return _manualSnap(rawPosition, routeCoordinates);
    }
  }

  /// Slices the remaining portion of a route from a snapped position to the route's end.
  static List<List<double>> sliceRemainingRoute(
    NavPosition snappedPosition,
    List<List<double>> routeCoordinates,
    int segmentIndex,
  ) {
    if (routeCoordinates.length < 2) return routeCoordinates;

    try {
      final turfLine = turf.LineString(
        coordinates: routeCoordinates
            .map((c) => turf.Position(c[0], c[1]))
            .toList(),
      );

      final startFeature = turf.Feature<turf.Point>(
        geometry: turf.Point(
          coordinates: turf.Position(
            snappedPosition.longitude,
            snappedPosition.latitude,
          ),
        ),
      );

      final endCoord = routeCoordinates.last;
      final endFeature = turf.Feature<turf.Point>(
        geometry: turf.Point(
          coordinates: turf.Position(endCoord[0], endCoord[1]),
        ),
      );

      final lineFeature = turf.Feature<turf.LineString>(geometry: turfLine);

      final sliced = turf.lineSlice(startFeature, endFeature, lineFeature);
      final coords = sliced.geometry?.coordinates;
      if (coords != null && coords.isNotEmpty) {
        return coords
            .map((p) => [
                  (p[0] ?? 0.0).toDouble(),
                  (p[1] ?? 0.0).toDouble(),
                ])
            .toList();
      }
    } catch (_) {
      // Fallback
    }

    final remaining = <List<double>>[];
    remaining.add([snappedPosition.longitude, snappedPosition.latitude]);
    final nextIdx = math.min(segmentIndex + 1, routeCoordinates.length);
    for (int i = nextIdx; i < routeCoordinates.length; i++) {
      remaining.add(routeCoordinates[i]);
    }
    return remaining;
  }

  static SnapResult _manualSnap(
    NavPosition raw,
    List<List<double>> coords,
  ) {
    double minDistance = double.infinity;
    List<double> closest = coords.first;
    int bestSegment = 0;

    for (int i = 0; i < coords.length - 1; i++) {
      final p1 = coords[i];
      final dist = distanceMeters(raw.latitude, raw.longitude, p1[1], p1[0]);
      if (dist < minDistance) {
        minDistance = dist;
        closest = p1;
        bestSegment = i;
      }
    }

    final pNext = coords[math.min(bestSegment + 1, coords.length - 1)];
    final bearing = calculateBearing(closest[1], closest[0], pNext[1], pNext[0]);

    return SnapResult(
      snappedPosition: raw.copyWith(
        latitude: closest[1],
        longitude: closest[0],
        heading: bearing,
      ),
      distanceFromRouteMeters: minDistance,
      segmentIndex: bestSegment,
      bearing: bearing,
    );
  }
}

class SnapResult {
  final NavPosition snappedPosition;
  final double distanceFromRouteMeters;
  final int segmentIndex;
  final double bearing;

  const SnapResult({
    required this.snappedPosition,
    required this.distanceFromRouteMeters,
    required this.segmentIndex,
    required this.bearing,
  });
}
