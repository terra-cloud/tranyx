import 'package:meta/meta.dart';
import '../models/nav_position.dart';
import '../models/navigation_state.dart';
import '../models/nav_travel_mode.dart';

/// Geospatial telemetry packet broadcasted over WebSocket or Serverless (Firebase/Supabase).
@immutable
class BroadcasterTelemetry {
  /// Unique identifier of the trip session / tracking channel.
  final String channelId;

  /// Unique identifier of the vehicle or broadcaster device.
  final String broadcasterId;

  /// Raw GPS position recorded by hardware.
  final NavPosition rawPosition;

  /// Road-snapped position along the active route (if navigating).
  final NavPosition? snappedPosition;

  /// Direction of travel / compass heading in degrees [0, 360).
  final double? currentBearing;

  /// Remaining distance to destination in meters (if route is active).
  final double? remainingDistance;

  /// Estimated seconds remaining until arrival.
  final double? remainingDuration;

  /// Active turn-by-turn guidance text (e.g., "In 200m, turn left").
  final String? currentInstruction;

  /// Sliced remaining route coordinates [[lon, lat], ...] for the subscriber map.
  final List<List<double>>? routeCoordinates;

  /// Active travel profile of this broadcaster.
  final NavTravelMode? travelMode;

  /// Index of the current target stop (0-indexed).
  final int? currentStopIndex;

  /// Total count of stops along the journey.
  final int? totalStopsCount;

  /// Title of the active stop (e.g. "Pickup").
  final String? currentStopTitle;

  /// Remaining distance to active stop in meters.
  final double? distanceToCurrentStop;

  /// Speed-adjusted duration to active stop in seconds.
  final double? durationToCurrentStop;

  /// Real-time calculated arrival timestamp for the active stop.
  final DateTime? currentStopEta;

  /// Live vehicle speedometer reading in km/h.
  final double? currentSpeedKmh;

  /// Timestamp when this telemetry was produced.
  final DateTime timestamp;

  /// Optional telemetry metadata (speed limit, battery, vehicle type, etc.).
  final Map<String, dynamic>? metadata;

  const BroadcasterTelemetry({
    required this.channelId,
    required this.broadcasterId,
    required this.rawPosition,
    this.snappedPosition,
    this.currentBearing,
    this.remainingDistance,
    this.remainingDuration,
    this.currentInstruction,
    this.routeCoordinates,
    this.travelMode,
    this.currentStopIndex,
    this.totalStopsCount,
    this.currentStopTitle,
    this.distanceToCurrentStop,
    this.durationToCurrentStop,
    this.currentStopEta,
    this.currentSpeedKmh,
    required this.timestamp,
    this.metadata,
  });

  /// Convenient factory to create telemetry directly from an active [NavigationState].
  factory BroadcasterTelemetry.fromNavigationState({
    required String channelId,
    required String broadcasterId,
    required NavigationState state,
    NavTravelMode? travelMode,
    Map<String, dynamic>? metadata,
  }) {
    return BroadcasterTelemetry(
      channelId: channelId,
      broadcasterId: broadcasterId,
      rawPosition: state.rawLocation,
      snappedPosition: state.snappedLocation,
      currentBearing: state.currentBearing,
      remainingDistance: state.remainingDistance,
      remainingDuration: state.remainingDuration,
      currentInstruction: state.currentInstruction,
      routeCoordinates: state.slicedRouteCoordinates,
      travelMode: travelMode,
      currentStopIndex: state.currentStopIndex,
      totalStopsCount: state.totalStopsCount,
      currentStopTitle: state.currentStopTitle,
      distanceToCurrentStop: state.distanceToCurrentStop,
      durationToCurrentStop: state.durationToCurrentStop,
      currentStopEta: state.currentStopEta,
      currentSpeedKmh: state.currentSpeedKmh,
      timestamp: DateTime.now().toUtc(),
      metadata: metadata,
    );
  }

  /// Converts this telemetry to a standard wire-format JSON Map.
  Map<String, dynamic> toJson() => {
        'channelId': channelId,
        'broadcasterId': broadcasterId,
        'rawPosition': rawPosition.toJson(),
        if (snappedPosition != null)
          'snappedPosition': snappedPosition!.toJson(),
        if (currentBearing != null) 'currentBearing': currentBearing,
        if (remainingDistance != null) 'remainingDistance': remainingDistance,
        if (remainingDuration != null) 'remainingDuration': remainingDuration,
        if (currentInstruction != null)
          'currentInstruction': currentInstruction,
        if (routeCoordinates != null) 'routeCoordinates': routeCoordinates,
        if (travelMode != null) 'travelMode': travelMode!.id,
        if (currentStopIndex != null) 'currentStopIndex': currentStopIndex,
        if (totalStopsCount != null) 'totalStopsCount': totalStopsCount,
        if (currentStopTitle != null) 'currentStopTitle': currentStopTitle,
        if (distanceToCurrentStop != null)
          'distanceToCurrentStop': distanceToCurrentStop,
        if (durationToCurrentStop != null)
          'durationToCurrentStop': durationToCurrentStop,
        if (currentStopEta != null)
          'currentStopEta': currentStopEta!.toIso8601String(),
        if (currentSpeedKmh != null) 'currentSpeedKmh': currentSpeedKmh,
        'timestamp': timestamp.toIso8601String(),
        if (metadata != null) 'metadata': metadata,
      };

  /// Parses a wire-format JSON Map into [BroadcasterTelemetry].
  factory BroadcasterTelemetry.fromJson(Map<String, dynamic> json) {
    return BroadcasterTelemetry(
      channelId: json['channelId'] as String,
      broadcasterId: json['broadcasterId'] as String,
      rawPosition:
          NavPosition.fromJson(json['rawPosition'] as Map<String, dynamic>),
      snappedPosition: json['snappedPosition'] != null
          ? NavPosition.fromJson(
              json['snappedPosition'] as Map<String, dynamic>)
          : null,
      currentBearing: (json['currentBearing'] as num?)?.toDouble(),
      remainingDistance: (json['remainingDistance'] as num?)?.toDouble(),
      remainingDuration: (json['remainingDuration'] as num?)?.toDouble(),
      currentInstruction: json['currentInstruction'] as String?,
      routeCoordinates: json['routeCoordinates'] != null
          ? (json['routeCoordinates'] as List<dynamic>)
              .map((c) => (c as List<dynamic>)
                  .map((n) => (n as num).toDouble())
                  .toList())
              .toList()
          : null,
      travelMode: json['travelMode'] != null
          ? NavTravelMode.fromJson(json['travelMode'] as String)
          : null,
      currentStopIndex: (json['currentStopIndex'] as num?)?.toInt(),
      totalStopsCount: (json['totalStopsCount'] as num?)?.toInt(),
      currentStopTitle: json['currentStopTitle'] as String?,
      distanceToCurrentStop:
          (json['distanceToCurrentStop'] as num?)?.toDouble(),
      durationToCurrentStop:
          (json['durationToCurrentStop'] as num?)?.toDouble(),
      currentStopEta: json['currentStopEta'] != null
          ? DateTime.parse(json['currentStopEta'] as String)
          : null,
      currentSpeedKmh: (json['currentSpeedKmh'] as num?)?.toDouble(),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now().toUtc(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() =>
      'BroadcasterTelemetry(channel: $channelId, broadcaster: $broadcasterId, lat: ${rawPosition.latitude}, lon: ${rawPosition.longitude})';
}
