import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/nav_position.dart';
import '../models/nav_travel_mode.dart';
import '../models/osrm_payload.dart';
import '../storage/route_database.dart';

/// Exception thrown when an OSRM routing request fails.
class OsrmRoutingException implements Exception {
  final String message;
  final int? statusCode;

  const OsrmRoutingException(this.message, {this.statusCode});

  @override
  String toString() => 'OsrmRoutingException: $message ${statusCode != null ? '(status: $statusCode)' : ''}';
}

/// Abstract contract for calculating turn-by-turn routes across multiple stops.
abstract class OsrmRouter {
  /// Fetches an OSRM route traversing through [points] in sequential order.
  ///
  /// Checks local offline storage before reaching the network unless [forceRefresh] is true.
  Future<OsrmPayload> getRoute({
    required List<NavPosition> points,
    NavTravelMode mode = NavTravelMode.car,
    bool forceRefresh = false,
  });
}

/// Production router connecting to OpenStreetMap FOSSGIS servers with
/// multi-modal travel profiles and local database offline caching.
class OsrmFossgisRouter implements OsrmRouter {
  final String baseUrl;
  final RouteDatabase database;
  final http.Client _client;
  final bool _ownsClient;

  /// Default OpenStreetMap Germany / FOSSGIS routing server.
  static const String defaultFossgisUrl = 'https://routing.openstreetmap.de';

  OsrmFossgisRouter({
    this.baseUrl = defaultFossgisUrl,
    RouteDatabase? database,
    http.Client? client,
  })  : database = database ?? InMemoryRouteDatabase(),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// Generates a deterministic cache key representing the ordered stops and travel mode.
  String generateRouteKey(List<NavPosition> points, NavTravelMode mode) {
    final buffer = StringBuffer('osrm_');
    buffer.write(mode.id);
    buffer.write('_');
    for (int i = 0; i < points.length; i++) {
      if (i > 0) buffer.write(';');
      buffer.write(points[i].latitude.toStringAsFixed(4));
      buffer.write(',');
      buffer.write(points[i].longitude.toStringAsFixed(4));
    }
    return buffer.toString();
  }

  @override
  Future<OsrmPayload> getRoute({
    required List<NavPosition> points,
    NavTravelMode mode = NavTravelMode.car,
    bool forceRefresh = false,
  }) async {
    if (points.length < 2) {
      throw const OsrmRoutingException('At least 2 points (origin and destination) are required for routing.');
    }

    final key = generateRouteKey(points, mode);

    // 1. Check local offline database
    if (!forceRefresh) {
      final cached = await database.getRoute(key);
      if (cached != null) {
        return cached;
      }
    }

    // 2. Fetch from OSRM FOSSGIS endpoint
    final serverSlug = mode.fossgisServerSlug;
    final osrmMode = mode.osrmMode;
    final coordsChain = points
        .map((p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
        .join(';');

    final uri = Uri.parse(
      '$baseUrl/$serverSlug/route/v1/$osrmMode/$coordsChain?overview=full&geometries=geojson&steps=true',
    );

    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw OsrmRoutingException(
          'OSRM server returned error: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      // Background JSON deserialization to prevent UI frame drops
      final payload = await OsrmPayload.fromRawJsonBackground(response.body);

      if (payload.code != 'Ok' || payload.routes.isEmpty) {
        throw OsrmRoutingException('OSRM failed to find route: ${payload.code}');
      }

      // 3. Persist to local offline database for future calls
      await database.saveRoute(key, payload);

      return payload;
    } on http.ClientException catch (e) {
      throw OsrmRoutingException('Network connection failed: $e');
    } on TimeoutException {
      throw const OsrmRoutingException('OSRM routing request timed out after 15 seconds.');
    }
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
