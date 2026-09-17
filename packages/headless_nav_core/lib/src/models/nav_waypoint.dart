import 'package:meta/meta.dart';
import 'nav_position.dart';

/// Represents a designated intermediate stop or final destination along a multi-stop route.
@immutable
class NavWaypoint {
  /// Optional unique identifier (e.g. orderId, stopId).
  final String? id;

  /// Human-readable title or purpose (e.g. "Pickup: John Doe", "Errand: Supermarket", "Drop-off").
  final String title;

  /// Target geographic location of this stop.
  final NavPosition position;

  /// Optional arbitrary domain metadata (notes, contact number, packages, etc.).
  final Map<String, dynamic>? metadata;

  const NavWaypoint({
    this.id,
    required this.title,
    required this.position,
    this.metadata,
  });

  /// Creates a simple waypoint from coordinates.
  factory NavWaypoint.fromCoords({
    required double latitude,
    required double longitude,
    String? title,
    String? id,
  }) {
    return NavWaypoint(
      id: id,
      title: title ?? 'Stop',
      position: NavPosition(
        latitude: latitude,
        longitude: longitude,
        timestamp: DateTime.now(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'title': title,
        'position': position.toJson(),
        if (metadata != null) 'metadata': metadata,
      };

  factory NavWaypoint.fromJson(Map<String, dynamic> json) {
    return NavWaypoint(
      id: json['id'] as String?,
      title: json['title'] as String? ?? 'Stop',
      position: NavPosition.fromJson(json['position'] as Map<String, dynamic>),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() => 'NavWaypoint(title: $title, lat: ${position.latitude}, lon: ${position.longitude})';
}
