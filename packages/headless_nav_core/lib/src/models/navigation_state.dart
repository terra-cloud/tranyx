import 'package:meta/meta.dart';
import 'nav_position.dart';

/// Immutable UI-ready state emitted by [NavigationEngine] on every GPS tick.
@immutable
class NavigationState {
  /// The GPS position snapped to the closest point along the route line.
  final NavPosition snappedLocation;

  /// The original unsnapped raw GPS position.
  final NavPosition rawLocation;

  /// The directional bearing in degrees [0, 360) along the current route line segment.
  final double currentBearing;

  /// Distance in meters to the upcoming maneuver point.
  final double distanceToNextTurn;

  /// Human-readable spoken/visual instruction for the current step.
  final String currentInstruction;

  /// Secondary preview instruction for the following maneuver (e.g. "Then turn left").
  final String? nextInstruction;

  /// Current step index within the active leg.
  final int currentStepIndex;

  /// Total number of steps in the active leg.
  final int totalSteps;

  /// Index of the current target stop (0-indexed).
  final int currentStopIndex;

  /// Total count of stops along the journey.
  final int totalStopsCount;

  /// Optional descriptive title of the active stop (e.g. "Pickup: John", "Stop 1: Grocery").
  final String? currentStopTitle;

  /// Remaining distance in meters to the active stop.
  final double distanceToCurrentStop;

  /// Speed-adjusted estimated duration in seconds to the active stop.
  final double durationToCurrentStop;

  /// Real-time calculated arrival timestamp for the active stop.
  final DateTime currentStopEta;

  /// Live vehicle speedometer reading in km/h.
  final double currentSpeedKmh;

  /// Total remaining distance in meters to the final destination across all stops.
  final double remainingDistance;

  /// Total speed-adjusted estimated duration in seconds to the final destination.
  final double remainingDuration;

  /// Perpendicular distance in meters between the raw GPS position and the snapped line point.
  final double distanceFromRoute;

  /// Whether the user has drifted beyond the off-route threshold.
  final bool isOffRoute;

  /// Coordinates [[lon, lat], ...] representing the sliced remaining route to destination.
  final List<List<double>> slicedRouteCoordinates;

  /// Whether the vehicle is currently heading to the final stop of the journey.
  bool get isFinalStop => currentStopIndex >= totalStopsCount - 1;

  const NavigationState({
    required this.snappedLocation,
    required this.rawLocation,
    required this.currentBearing,
    required this.distanceToNextTurn,
    required this.currentInstruction,
    this.nextInstruction,
    required this.currentStepIndex,
    required this.totalSteps,
    this.currentStopIndex = 0,
    this.totalStopsCount = 1,
    this.currentStopTitle,
    required this.distanceToCurrentStop,
    required this.durationToCurrentStop,
    required this.currentStopEta,
    required this.currentSpeedKmh,
    required this.remainingDistance,
    required this.remainingDuration,
    required this.distanceFromRoute,
    required this.isOffRoute,
    required this.slicedRouteCoordinates,
  });

  /// Formatted GeoJSON Map representing the remaining sliced route for MapLibre GL sources.
  Map<String, dynamic> get slicedRouteGeoJson => {
        'type': 'Feature',
        'properties': {},
        'geometry': {
          'type': 'LineString',
          'coordinates': slicedRouteCoordinates,
        },
      };

  /// Serializes this state into a JSON Map.
  Map<String, dynamic> toJson() => {
        'snappedLocation': snappedLocation.toJson(),
        'rawLocation': rawLocation.toJson(),
        'currentBearing': currentBearing,
        'distanceToNextTurn': distanceToNextTurn,
        'currentInstruction': currentInstruction,
        if (nextInstruction != null) 'nextInstruction': nextInstruction,
        'currentStepIndex': currentStepIndex,
        'totalSteps': totalSteps,
        'currentStopIndex': currentStopIndex,
        'totalStopsCount': totalStopsCount,
        if (currentStopTitle != null) 'currentStopTitle': currentStopTitle,
        'distanceToCurrentStop': distanceToCurrentStop,
        'durationToCurrentStop': durationToCurrentStop,
        'currentStopEta': currentStopEta.toIso8601String(),
        'currentSpeedKmh': currentSpeedKmh,
        'remainingDistance': remainingDistance,
        'remainingDuration': remainingDuration,
        'distanceFromRoute': distanceFromRoute,
        'isOffRoute': isOffRoute,
        'slicedRouteCoordinates': slicedRouteCoordinates,
      };

  /// Constructs [NavigationState] from a JSON Map.
  factory NavigationState.fromJson(Map<String, dynamic> json) {
    return NavigationState(
      snappedLocation: NavPosition.fromJson(
          json['snappedLocation'] as Map<String, dynamic>),
      rawLocation:
          NavPosition.fromJson(json['rawLocation'] as Map<String, dynamic>),
      currentBearing: (json['currentBearing'] as num).toDouble(),
      distanceToNextTurn: (json['distanceToNextTurn'] as num).toDouble(),
      currentInstruction: json['currentInstruction'] as String,
      nextInstruction: json['nextInstruction'] as String?,
      currentStepIndex: (json['currentStepIndex'] as num).toInt(),
      totalSteps: (json['totalSteps'] as num).toInt(),
      currentStopIndex: (json['currentStopIndex'] as num?)?.toInt() ?? 0,
      totalStopsCount: (json['totalStopsCount'] as num?)?.toInt() ?? 1,
      currentStopTitle: json['currentStopTitle'] as String?,
      distanceToCurrentStop: (json['distanceToCurrentStop'] as num?)?.toDouble() ??
          (json['remainingDistance'] as num).toDouble(),
      durationToCurrentStop: (json['durationToCurrentStop'] as num?)?.toDouble() ??
          (json['remainingDuration'] as num).toDouble(),
      currentStopEta: json['currentStopEta'] != null
          ? DateTime.parse(json['currentStopEta'] as String)
          : DateTime.now().add(Duration(
              seconds: (json['remainingDuration'] as num?)?.round() ?? 0)),
      currentSpeedKmh: (json['currentSpeedKmh'] as num?)?.toDouble() ?? 0.0,
      remainingDistance: (json['remainingDistance'] as num).toDouble(),
      remainingDuration: (json['remainingDuration'] as num).toDouble(),
      distanceFromRoute: (json['distanceFromRoute'] as num).toDouble(),
      isOffRoute: json['isOffRoute'] as bool? ?? false,
      slicedRouteCoordinates: (json['slicedRouteCoordinates'] as List<dynamic>)
          .map((c) => (c as List<dynamic>)
              .map((n) => (n as num).toDouble())
              .toList())
          .toList(),
    );
  }
}
