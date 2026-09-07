import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:headless_nav_core/headless_nav_core.dart';

void main() {
  group('OsrmFossgisRouter & RouteDatabase', () {
    late InMemoryRouteDatabase db;

    setUp(() {
      db = InMemoryRouteDatabase();
    });

    final p1 = NavPosition(latitude: 14.5995, longitude: 120.9842, timestamp: DateTime.now());
    final p2 = NavPosition(latitude: 14.5950, longitude: 120.9880, timestamp: DateTime.now());
    final p3 = NavPosition(latitude: 14.5800, longitude: 121.0100, timestamp: DateTime.now());

    final mockResponseJson = jsonEncode({
      'code': 'Ok',
      'routes': [
        {
          'distance': 5000.0,
          'duration': 600.0,
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [120.9842, 14.5995],
              [120.9880, 14.5950],
              [121.0100, 14.5800],
            ],
          },
          'legs': [
            {
              'distance': 2000.0,
              'duration': 250.0,
              'summary': 'Leg 1',
              'steps': [
                {
                  'distance': 2000.0,
                  'duration': 250.0,
                  'name': 'Roxas Blvd',
                  'geometry': {
                    'type': 'LineString',
                    'coordinates': [
                      [120.9842, 14.5995],
                      [120.9880, 14.5950],
                    ],
                  },
                  'maneuver': {
                    'type': 'depart',
                    'location': [120.9842, 14.5995],
                  },
                },
              ],
            },
            {
              'distance': 3000.0,
              'duration': 350.0,
              'summary': 'Leg 2',
              'steps': [
                {
                  'distance': 3000.0,
                  'duration': 350.0,
                  'name': 'Ayala Ave',
                  'geometry': {
                    'type': 'LineString',
                    'coordinates': [
                      [120.9880, 14.5950],
                      [121.0100, 14.5800],
                    ],
                  },
                  'maneuver': {
                    'type': 'turn',
                    'modifier': 'left',
                    'location': [120.9880, 14.5950],
                    'instruction': 'Turn left onto Ayala Ave',
                  },
                },
              ],
            },
          ],
        },
      ],
      'waypoints': [
        {'name': 'Start', 'location': [120.9842, 14.5995]},
        {'name': 'Stop 1', 'location': [120.9880, 14.5950]},
        {'name': 'Stop 2', 'location': [121.0100, 14.5800]},
      ],
    });

    test('Chains multiple coordinates and caches route in local DB on first fetch', () async {
      int networkHits = 0;

      final mockClient = MockClient((request) async {
        networkHits++;
        // Verify chained coordinates in URI
        expect(request.url.path, contains('120.984200,14.599500;120.988000,14.595000;121.010000,14.580000'));
        return http.Response(mockResponseJson, 200);
      });

      final router = OsrmFossgisRouter(
        database: db,
        client: mockClient,
      );

      // 1. First fetch -> should hit network
      final route1 = await router.getRoute(points: [p1, p2, p3], mode: NavTravelMode.car);
      expect(networkHits, equals(1));
      expect(route1.legCount, equals(2));
      expect(db.count, equals(1));

      // 2. Second fetch -> should hit local DB offline (networkHits remains 1)
      final route2 = await router.getRoute(points: [p1, p2, p3], mode: NavTravelMode.car);
      expect(networkHits, equals(1));
      expect(route2.legCount, equals(2));
      expect(route2.primaryRoute?.distance, equals(5000.0));
    });

    test('Mode-aware cache keys separate Car from Bicycle routes', () async {
      int networkHits = 0;
      final mockClient = MockClient((request) async {
        networkHits++;
        return http.Response(mockResponseJson, 200);
      });

      final router = OsrmFossgisRouter(database: db, client: mockClient);

      await router.getRoute(points: [p1, p2], mode: NavTravelMode.car);
      expect(networkHits, equals(1));

      // Querying with bike should trigger new fetch because profile differs
      await router.getRoute(points: [p1, p2], mode: NavTravelMode.bike);
      expect(networkHits, equals(2));
      expect(db.count, equals(2));
    });

    test('Multi-stop NavigationEngine emits ArrivedAtStopEvent and transitions legs', () async {
      final payload = OsrmPayload.fromJson(jsonDecode(mockResponseJson));
      final waypoints = [
        NavWaypoint.fromCoords(latitude: 14.5950, longitude: 120.9880, title: 'Pickup Stop'),
        NavWaypoint.fromCoords(latitude: 14.5800, longitude: 121.0100, title: 'Dropoff Stop'),
      ];

      final engine = NavigationEngine(
        route: payload,
        waypoints: waypoints,
        options: const NavigationEngineOptions(
          enableBackgroundIsolates: false,
          arrivalThresholdMeters: 15.0,
        ),
      );

      final events = <NavEvent>[];
      engine.eventStream.listen(events.add);

      // Tick 1: Start of Leg 0
      await engine.processTick(p1);
      expect(engine.currentLegIndex, equals(0));

      // Tick 2: Arrive at Stop 1 (Pickup)
      await engine.processTick(p2);
      // Intermediate arrival event should fire and advance leg to 1
      expect(events.any((e) => e is ArrivedAtStopEvent), isTrue);
      expect(engine.currentLegIndex, equals(1));

      // Tick 3: Arrive at Stop 2 (Dropoff)
      await engine.processTick(p3);
      expect(engine.hasArrived, isTrue);
      expect(events.any((e) => e is ArrivedEvent), isTrue);

      await engine.dispose();
    });
  });
}
