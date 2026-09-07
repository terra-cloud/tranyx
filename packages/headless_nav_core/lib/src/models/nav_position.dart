import 'package:meta/meta.dart';

/// An immutable, platform-agnostic geographic position used across
/// navigation, telemetry broadcasting, and streaming listeners.
@immutable
class NavPosition {
  /// Latitude in decimal degrees [-90.0, 90.0].
  final double latitude;

  /// Longitude in decimal degrees [-180.0, 180.0].
  final double longitude;

  /// Heading / bearing direction in degrees [0.0, 360.0] where 0 is North.
  final double? heading;

  /// Speed in meters per second (m/s).
  final double? speed;

  /// Altitude in meters above the WGS 84 reference ellipsoid.
  final double? altitude;

  /// Horizontal accuracy in meters.
  final double? accuracy;

  /// Timestamp when the position was recorded.
  final DateTime timestamp;

  const NavPosition({
    required this.latitude,
    required this.longitude,
    this.heading,
    this.speed,
    this.altitude,
    this.accuracy,
    required this.timestamp,
  });

  /// Factory to instantiate a position at the current UTC time.
  factory NavPosition.now({
    required double latitude,
    required double longitude,
    double? heading,
    double? speed,
    double? altitude,
    double? accuracy,
  }) {
    return NavPosition(
      latitude: latitude,
      longitude: longitude,
      heading: heading,
      speed: speed,
      altitude: altitude,
      accuracy: accuracy,
      timestamp: DateTime.now().toUtc(),
    );
  }

  /// Converts this [NavPosition] to a JSON-serializable Map.
  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (heading != null) 'heading': heading,
        if (speed != null) 'speed': speed,
        if (altitude != null) 'altitude': altitude,
        if (accuracy != null) 'accuracy': accuracy,
        'timestamp': timestamp.toIso8601String(),
      };

  /// Creates a [NavPosition] from a JSON Map.
  factory NavPosition.fromJson(Map<String, dynamic> json) {
    return NavPosition(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now().toUtc(),
    );
  }

  NavPosition copyWith({
    double? latitude,
    double? longitude,
    double? heading,
    double? speed,
    double? altitude,
    double? accuracy,
    DateTime? timestamp,
  }) {
    return NavPosition(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      heading: heading ?? this.heading,
      speed: speed ?? this.speed,
      altitude: altitude ?? this.altitude,
      accuracy: accuracy ?? this.accuracy,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavPosition &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          heading == other.heading &&
          speed == other.speed &&
          altitude == other.altitude &&
          accuracy == other.accuracy &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      latitude.hashCode ^
      longitude.hashCode ^
      heading.hashCode ^
      speed.hashCode ^
      altitude.hashCode ^
      accuracy.hashCode ^
      timestamp.hashCode;

  @override
  String toString() =>
      'NavPosition(lat: $latitude, lon: $longitude, heading: $heading, speed: $speed)';
}
