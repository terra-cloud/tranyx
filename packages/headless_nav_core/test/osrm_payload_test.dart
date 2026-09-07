import 'package:test/test.dart';
import 'package:headless_nav_core/headless_nav_core.dart';

void main() {
  group('OsrmPayload', () {
    test('parses standard OSRM v5 JSON payload correctly', () {
      final json = {
        'code': 'Ok',
        'routes': [
          {
            'distance': 1500.5,
            'duration': 210.0,
            'weight_name': 'routability',
            'weight': 210.0,
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [121.0, 14.5],
                [121.002, 14.502],
                [121.005, 14.505],
              ],
            },
            'legs': [
              {
                'distance': 1500.5,
                'duration': 210.0,
                'summary': 'Main St, Broadway',
                'steps': [
                  {
                    'distance': 500.0,
                    'duration': 70.0,
                    'name': 'Main St',
                    'geometry': {
                      'type': 'LineString',
                      'coordinates': [
                        [121.0, 14.5],
                        [121.002, 14.502],
                      ],
                    },
                    'maneuver': {
                      'type': 'depart',
                      'modifier': 'straight',
                      'location': [121.0, 14.5],
                      'bearing_before': 0,
                      'bearing_after': 45,
                    },
                  },
                  {
                    'distance': 1000.5,
                    'duration': 140.0,
                    'name': 'Broadway',
                    'geometry': {
                      'type': 'LineString',
                      'coordinates': [
                        [121.002, 14.502],
                        [121.005, 14.505],
                      ],
                    },
                    'maneuver': {
                      'type': 'turn',
                      'modifier': 'right',
                      'location': [121.002, 14.502],
                      'bearing_before': 45,
                      'bearing_after': 90,
                      'instruction': 'Turn right onto Broadway',
                    },
                  },
                ],
              },
            ],
          },
        ],
        'waypoints': [
          {
            'name': 'Origin',
            'location': [121.0, 14.5],
            'distance': 1.2,
          },
          {
            'name': 'Destination',
            'location': [121.005, 14.505],
            'distance': 0.8,
          },
        ],
      };

      final payload = OsrmPayload.fromJson(json);

      expect(payload.code, equals('Ok'));
      expect(payload.routes.length, equals(1));

      final route = payload.primaryRoute!;
      expect(route.distance, equals(1500.5));
      expect(route.duration, equals(210.0));
      expect(route.geometryCoordinates.length, equals(3));
      expect(route.legs.length, equals(1));

      final leg = route.legs.first;
      expect(leg.steps.length, equals(2));

      final step1 = leg.steps[0];
      expect(step1.name, equals('Main St'));
      expect(step1.maneuver.type, equals('depart'));
      expect(step1.maneuver.effectiveInstruction, equals('Head straight'));

      final step2 = leg.steps[1];
      expect(step2.name, equals('Broadway'));
      expect(step2.maneuver.type, equals('turn'));
      expect(step2.maneuver.effectiveInstruction, equals('Turn right onto Broadway'));

      // Round-trip serialization
      final encoded = payload.toJson();
      final roundTrip = OsrmPayload.fromJson(encoded);
      expect(roundTrip.primaryRoute?.distance, equals(1500.5));
      expect(roundTrip.primaryRoute?.geometryCoordinates.length, equals(3));
    });
  });
}
