import 'package:headless_nav_core/src/math/geo_math.dart';
import 'package:headless_nav_core/src/models/nav_position.dart'
    show NavPosition;
import 'package:headless_nav_core/src/models/osrm_payload.dart';
import 'package:headless_nav_core/src/platform/isolate_runner.dart';
import 'package:meta/meta.dart';

/// Carries input data across isolate boundaries for heavy route computations.
class _ComputationPayload {
  final Map<String, dynamic> rawPositionJson;
  final List<List<double>> routeCoordinates;
  final List<Map<String, dynamic>> stepsJson;
  final int currentStepIndex;
  final double routeTotalDistance;
  final double routeTotalDuration;
  final double offRouteThresholdMeters;
  final double arrivalThresholdMeters;
  final List<double>? currentStopCoords;
  final double stopTotalDistance;
  final double stopTotalDuration;

  _ComputationPayload({
    required this.rawPositionJson,
    required this.routeCoordinates,
    required this.stepsJson,
    required this.currentStepIndex,
    required this.routeTotalDistance,
    required this.routeTotalDuration,
    required this.offRouteThresholdMeters,
    required this.arrivalThresholdMeters,
    this.currentStopCoords,
    this.stopTotalDistance = 0.0,
    this.stopTotalDuration = 0.0,
  });
}

/// The output emitted by [GeoComputationDispatcher] after processing a GPS tick.
@immutable
class NavigationComputationResult {
  final NavPosition snappedPosition;
  final double bearing;
  final double distanceFromRoute;
  final bool isOffRoute;
  final bool hasArrived;
  final double distanceToNextTurn;
  final int evaluatedStepIndex;
  final double remainingDistance;
  final double remainingDuration;
  final double distanceToCurrentStop;
  final double durationToCurrentStop;
  final DateTime currentStopEta;
  final double currentSpeedKmh;
  final List<List<double>> slicedRouteCoordinates;

  const NavigationComputationResult({
    required this.snappedPosition,
    required this.bearing,
    required this.distanceFromRoute,
    required this.isOffRoute,
    required this.hasArrived,
    required this.distanceToNextTurn,
    required this.evaluatedStepIndex,
    required this.remainingDistance,
    required this.remainingDuration,
    required this.distanceToCurrentStop,
    required this.durationToCurrentStop,
    required this.currentStopEta,
    required this.currentSpeedKmh,
    required this.slicedRouteCoordinates,
  });
}

/// Offloads heavy Turf operations (polyline snapping, line slicing, distance metrics)
/// off the main UI isolate to a background isolate using [Isolate.run].
class GeoComputationDispatcher {
  final bool enableBackgroundIsolates;

  const GeoComputationDispatcher({
    this.enableBackgroundIsolates = true,
  });

  /// Dispatches the geometry calculations to a background isolate.
  Future<NavigationComputationResult> computeTick({
    required NavPosition rawPosition,
    required List<List<double>> routeCoordinates,
    required List<OsrmStep> steps,
    required int currentStepIndex,
    required double routeTotalDistance,
    required double routeTotalDuration,
    required double offRouteThresholdMeters,
    required double arrivalThresholdMeters,
    List<double>? currentStopCoords,
    double stopTotalDistance = 0.0,
    double stopTotalDuration = 0.0,
  }) async {
    final payload = _ComputationPayload(
      rawPositionJson: rawPosition.toJson(),
      routeCoordinates: routeCoordinates,
      stepsJson: steps.map((s) => s.toJson()).toList(),
      currentStepIndex: currentStepIndex,
      routeTotalDistance: routeTotalDistance,
      routeTotalDuration: routeTotalDuration,
      offRouteThresholdMeters: offRouteThresholdMeters,
      arrivalThresholdMeters: arrivalThresholdMeters,
      currentStopCoords: currentStopCoords,
      stopTotalDistance: stopTotalDistance,
      stopTotalDuration: stopTotalDuration,
    );

    if (enableBackgroundIsolates) {
      try {
        return await runCompute(() => _executeCalculation(payload));
      } catch (_) {
        // Fallback to synchronous in-isolate calculation (e.g., on web or test harness)
        return _executeCalculation(payload);
      }
    } else {
      return _executeCalculation(payload);
    }
  }

  /// Top-level or static function suitable for execution inside [Isolate.run].
  static NavigationComputationResult _executeCalculation(
      _ComputationPayload payload) {
    final rawPos = NavPosition.fromJson(payload.rawPositionJson);
    final routeCoords = payload.routeCoordinates;
    final steps = payload.stepsJson.map((s) => OsrmStep.fromJson(s)).toList();

    // 1. Snap to Route Polyline
    final snapResult = GeoMath.snapToRoute(rawPos, routeCoords);
    final isOffRoute =
        snapResult.distanceFromRouteMeters > payload.offRouteThresholdMeters;

    // 2. Check Arrival (distance to destination end point)
    double distanceToDest = double.infinity;
    if (routeCoords.isNotEmpty) {
      final dest = routeCoords.last;
      distanceToDest = GeoMath.distanceMeters(
        rawPos.latitude,
        rawPos.longitude,
        dest[1],
        dest[0],
      );
    }
    final hasArrived = !isOffRoute && distanceToDest <= payload.arrivalThresholdMeters;

    // 3. Step progression calculation
    int stepIdx = payload.currentStepIndex;
    double distToNextTurn = 0.0;

    if (steps.isNotEmpty && stepIdx < steps.length) {
      if (stepIdx < steps.length - 1) {
        final nextManeuver = steps[stepIdx + 1].maneuver;
        distToNextTurn = GeoMath.distanceMeters(
          snapResult.snappedPosition.latitude,
          snapResult.snappedPosition.longitude,
          nextManeuver.latitude,
          nextManeuver.longitude,
        );

        // Auto-advance step if within 20m of upcoming turn
        if (distToNextTurn < 20.0) {
          stepIdx++;
          if (stepIdx < steps.length - 1) {
            final futureManeuver = steps[stepIdx + 1].maneuver;
            distToNextTurn = GeoMath.distanceMeters(
              snapResult.snappedPosition.latitude,
              snapResult.snappedPosition.longitude,
              futureManeuver.latitude,
              futureManeuver.longitude,
            );
          } else {
            distToNextTurn = distanceToDest;
          }
        }
      } else {
        distToNextTurn = distanceToDest;
      }
    }

    // 4. Slice remaining route
    final slicedCoords = GeoMath.sliceRemainingRoute(
      snapResult.snappedPosition,
      routeCoords,
      snapResult.segmentIndex,
    );

    // 5. Calculate remaining distance along sliced coordinates
    double remainingDist = 0.0;
    for (int i = 0; i < slicedCoords.length - 1; i++) {
      final p1 = slicedCoords[i];
      final p2 = slicedCoords[i + 1];
      remainingDist += GeoMath.distanceMeters(p1[1], p1[0], p2[1], p2[0]);
    }

    // 6. Stop-specific distance (measure from actual GPS rawPosition to prevent false arrival)
    double distToStop = remainingDist;
    if (payload.currentStopCoords != null && payload.currentStopCoords!.length >= 2) {
      final stopLon = payload.currentStopCoords![0];
      final stopLat = payload.currentStopCoords![1];
      distToStop = GeoMath.distanceMeters(
        rawPos.latitude,
        rawPos.longitude,
        stopLat,
        stopLon,
      );
    }

    // 7. Dynamic Speed & Real-time ETA Calculation
    final speedMps = rawPos.speed ?? 0.0;
    final speedKmh = speedMps * 3.6;

    // Estimate remaining duration proportionally from OSRM baseline
    final durationRatio = payload.routeTotalDistance > 0
        ? remainingDist / payload.routeTotalDistance
        : 0.0;
    final osrmRemainingDuration = payload.routeTotalDuration * durationRatio;

    final stopDurationRatio = payload.stopTotalDistance > 0
        ? distToStop / payload.stopTotalDistance
        : durationRatio;
    final osrmStopDuration = payload.stopTotalDuration > 0
        ? payload.stopTotalDuration * stopDurationRatio
        : osrmRemainingDuration;

    // If moving at meaningful speed (> 5 km/h), dynamically blend realtime speed with OSRM baseline
    double durationToStop = osrmStopDuration;
    if (speedMps > 1.4) {
      final liveSpeedDuration = distToStop / speedMps;
      durationToStop = (0.7 * liveSpeedDuration) + (0.3 * osrmStopDuration);
    }

    final stopEta = DateTime.now().add(Duration(seconds: durationToStop.round()));

    return NavigationComputationResult(
      snappedPosition: snapResult.snappedPosition,
      bearing: snapResult.bearing,
      distanceFromRoute: snapResult.distanceFromRouteMeters,
      isOffRoute: isOffRoute,
      hasArrived: hasArrived,
      distanceToNextTurn: distToNextTurn,
      evaluatedStepIndex: stepIdx,
      remainingDistance: remainingDist,
      remainingDuration: osrmRemainingDuration,
      distanceToCurrentStop: distToStop,
      durationToCurrentStop: durationToStop,
      currentStopEta: stopEta,
      currentSpeedKmh: speedKmh,
      slicedRouteCoordinates: slicedCoords,
    );
  }
}
