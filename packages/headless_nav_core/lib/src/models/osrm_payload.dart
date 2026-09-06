import 'dart:convert';
import 'package:headless_nav_core/src/platform/isolate_runner.dart';
import 'package:meta/meta.dart';

/// Represents an OSRM v5 navigation response payload.
@immutable
class OsrmPayload {
  final String code;
  final List<OsrmRoute> routes;
  final List<OsrmWaypoint> waypoints;

  const OsrmPayload({
    required this.code,
    required this.routes,
    this.waypoints = const [],
  });

  /// Returns the primary route (routes.first) if available.
  OsrmRoute? get primaryRoute => routes.isNotEmpty ? routes.first : null;

  /// Returns total number of legs across the primary route.
  int get legCount => primaryRoute?.legs.length ?? 0;

  /// Asynchronously parses raw JSON off the UI thread via [runCompute] to prevent UI janks.
  static Future<OsrmPayload> fromRawJsonBackground(String rawJson) async {
    try {
      return await runCompute(() {
        final Map<String, dynamic> map =
            jsonDecode(rawJson) as Map<String, dynamic>;
        return OsrmPayload.fromJson(map);
      });
    } catch (_) {
      // Fallback for platforms/environments without isolate spawning
      final Map<String, dynamic> map =
          jsonDecode(rawJson) as Map<String, dynamic>;
      return OsrmPayload.fromJson(map);
    }
  }

  factory OsrmPayload.fromJson(Map<String, dynamic> json) {
    return OsrmPayload(
      code: json['code'] as String? ?? 'Ok',
      routes: (json['routes'] as List<dynamic>?)
              ?.map((e) => OsrmRoute.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      waypoints: (json['waypoints'] as List<dynamic>?)
              ?.map((e) => OsrmWaypoint.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'routes': routes.map((r) => r.toJson()).toList(),
        'waypoints': waypoints.map((w) => w.toJson()).toList(),
      };
}

/// A calculated route in an OSRM response.
@immutable
class OsrmRoute {
  final double distance;
  final double duration;
  final String? weightName;
  final double? weight;
  final List<List<double>> geometryCoordinates;
  final List<OsrmLeg> legs;

  const OsrmRoute({
    required this.distance,
    required this.duration,
    this.weightName,
    this.weight,
    required this.geometryCoordinates,
    required this.legs,
  });

  factory OsrmRoute.fromJson(Map<String, dynamic> json) {
    List<List<double>> coordinates = [];
    final geometryRaw = json['geometry'];
    if (geometryRaw is Map<String, dynamic>) {
      final coordsList = geometryRaw['coordinates'] as List<dynamic>?;
      if (coordsList != null) {
        coordinates = coordsList.map((c) {
          final pair = c as List<dynamic>;
          return [
            (pair[0] as num).toDouble(),
            (pair[1] as num).toDouble(),
          ];
        }).toList();
      }
    } else if (geometryRaw is List<dynamic>) {
      coordinates = geometryRaw.map((c) {
        final pair = c as List<dynamic>;
        return [
          (pair[0] as num).toDouble(),
          (pair[1] as num).toDouble(),
        ];
      }).toList();
    }

    return OsrmRoute(
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      weightName: json['weight_name'] as String?,
      weight: (json['weight'] as num?)?.toDouble(),
      geometryCoordinates: coordinates,
      legs: (json['legs'] as List<dynamic>?)
              ?.map((e) => OsrmLeg.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'distance': distance,
        'duration': duration,
        if (weightName != null) 'weight_name': weightName,
        if (weight != null) 'weight': weight,
        'geometry': {
          'type': 'LineString',
          'coordinates': geometryCoordinates,
        },
        'legs': legs.map((l) => l.toJson()).toList(),
      };
}

/// A leg between two waypoints on a route.
@immutable
class OsrmLeg {
  final double distance;
  final double duration;
  final String summary;
  final List<OsrmStep> steps;

  const OsrmLeg({
    required this.distance,
    required this.duration,
    required this.summary,
    required this.steps,
  });

  factory OsrmLeg.fromJson(Map<String, dynamic> json) {
    return OsrmLeg(
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      summary: json['summary'] as String? ?? '',
      steps: (json['steps'] as List<dynamic>?)
              ?.map((e) => OsrmStep.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'distance': distance,
        'duration': duration,
        'summary': summary,
        'steps': steps.map((s) => s.toJson()).toList(),
      };
}

/// A turn-by-turn navigation step.
@immutable
class OsrmStep {
  final double distance;
  final double duration;
  final String name;
  final String? ref;
  final String? pronunciation;
  final List<List<double>> geometryCoordinates;
  final OsrmManeuver maneuver;

  const OsrmStep({
    required this.distance,
    required this.duration,
    required this.name,
    this.ref,
    this.pronunciation,
    required this.geometryCoordinates,
    required this.maneuver,
  });

  factory OsrmStep.fromJson(Map<String, dynamic> json) {
    List<List<double>> coords = [];
    final geomRaw = json['geometry'];
    if (geomRaw is Map<String, dynamic>) {
      final list = geomRaw['coordinates'] as List<dynamic>?;
      if (list != null) {
        coords = list.map((c) {
          final pair = c as List<dynamic>;
          return [(pair[0] as num).toDouble(), (pair[1] as num).toDouble()];
        }).toList();
      }
    } else if (geomRaw is List<dynamic>) {
      coords = geomRaw.map((c) {
        final pair = c as List<dynamic>;
        return [(pair[0] as num).toDouble(), (pair[1] as num).toDouble()];
      }).toList();
    }

    return OsrmStep(
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      name: json['name'] as String? ?? '',
      ref: json['ref'] as String?,
      pronunciation: json['pronunciation'] as String?,
      geometryCoordinates: coords,
      maneuver: json['maneuver'] != null
          ? OsrmManeuver.fromJson(json['maneuver'] as Map<String, dynamic>)
          : const OsrmManeuver(
              type: 'depart',
              location: [0.0, 0.0],
            ),
    );
  }

  Map<String, dynamic> toJson() => {
        'distance': distance,
        'duration': duration,
        'name': name,
        if (ref != null) 'ref': ref,
        if (pronunciation != null) 'pronunciation': pronunciation,
        'geometry': {
          'type': 'LineString',
          'coordinates': geometryCoordinates,
        },
        'maneuver': maneuver.toJson(),
      };
}

/// A specific maneuver at the transition of a step.
@immutable
class OsrmManeuver {
  final String type;
  final String? modifier;
  final List<double> location;
  final int? bearingBefore;
  final int? bearingAfter;
  final String? instruction;

  const OsrmManeuver({
    required this.type,
    this.modifier,
    required this.location,
    this.bearingBefore,
    this.bearingAfter,
    this.instruction,
  });

  double get longitude => location.isNotEmpty ? location[0] : 0.0;
  double get latitude => location.length > 1 ? location[1] : 0.0;

  String get effectiveInstruction {
    if (instruction != null && instruction!.isNotEmpty) {
      return instruction!;
    }
    final mod = modifier != null ? ' $modifier' : '';
    switch (type) {
      case 'depart':
        return 'Head${mod.isNotEmpty ? mod : ' forward'}';
      case 'arrive':
        return 'You have arrived at your destination';
      case 'turn':
        return 'Turn$mod';
      case 'fork':
        return 'At the fork, keep$mod';
      case 'roundabout':
      case 'rotary':
        return 'Enter the roundabout and take the exit';
      case 'continue':
        return 'Continue straight';
      case 'end of road':
        return 'At the end of the road, turn$mod';
      case 'merge':
        return 'Merge$mod';
      default:
        return 'Proceed${mod.isNotEmpty ? mod : ''}';
    }
  }

  factory OsrmManeuver.fromJson(Map<String, dynamic> json) {
    final locList = (json['location'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [0.0, 0.0];

    return OsrmManeuver(
      type: json['type'] as String? ?? 'turn',
      modifier: json['modifier'] as String?,
      location: locList,
      bearingBefore: (json['bearing_before'] as num?)?.toInt(),
      bearingAfter: (json['bearing_after'] as num?)?.toInt(),
      instruction: json['instruction'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (modifier != null) 'modifier': modifier,
        'location': location,
        if (bearingBefore != null) 'bearing_before': bearingBefore,
        if (bearingAfter != null) 'bearing_after': bearingAfter,
        if (instruction != null) 'instruction': instruction,
      };
}

/// An OSRM waypoint representation.
@immutable
class OsrmWaypoint {
  final String name;
  final List<double> location;
  final double? distance;

  const OsrmWaypoint({
    required this.name,
    required this.location,
    this.distance,
  });

  factory OsrmWaypoint.fromJson(Map<String, dynamic> json) {
    return OsrmWaypoint(
      name: json['name'] as String? ?? '',
      location: (json['location'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [0.0, 0.0],
      distance: (json['distance'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'location': location,
        if (distance != null) 'distance': distance,
      };
}
