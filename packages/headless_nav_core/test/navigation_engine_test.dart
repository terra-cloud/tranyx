import 'package:test/test.dart';
import 'package:headless_nav_core/headless_nav_core.dart';

void main() {
  group('NavigationEngine', () {
    late OsrmPayload sampleRoute;

    setUp(() {
      sampleRoute = OsrmPayload(
        code: 'Ok',
        routes: [
          const OsrmRoute(
            distance: 2000.0,
            duration: 200.0,
            geometryCoordinates: [
              [121.000, 14.500],
              [121.005, 14.500],
              [121.010, 14.500],
            ],
            legs: [
              OsrmLeg(
                distance: 2000.0,
                duration: 200.0,
                summary: 'Main St',
                steps: [
                  OsrmStep(
                    distance: 1000.0,
                    duration: 100.0,
                    name: 'Main St',
                    geometryCoordinates: [
                      [121.000, 14.500],
                      [121.005, 14.500],
                    ],
                    maneuver: OsrmManeuver(
                      type: 'depart',
                      modifier: 'straight',
                      location: [121.000, 14.500],
                    ),
                  ),
                  OsrmStep(
                    distance: 1000.0,
                    duration: 100.0,
                    name: 'East Ave',
                    geometryCoordinates: [
                      [121.005, 14.500],
                      [121.010, 14.500],
                    ],
                    maneuver: OsrmManeuver(
                      type: 'turn',
                      modifier: 'right',
                      location: [121.005, 14.500],
                      instruction: 'Turn right onto East Ave',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    });

    test('emits progressive NavigationState updates on GPS ticks', () async {
      final engine = NavigationEngine(
        route: sampleRoute,
        options: const NavigationEngineOptions(enableBackgroundIsolates: false),
      );

      final states = <NavigationState>[];
      final sub = engine.stateStream.listen(states.add);

      // Tick 1: Start
      await engine.processTick(NavPosition.now(latitude: 14.500, longitude: 121.000));
      expect(states.length, equals(1));
      expect(states.first.currentStepIndex, equals(0));
      expect(states.first.isOffRoute, isFalse);

      // Tick 2: Midway
      await engine.processTick(NavPosition.now(latitude: 14.500, longitude: 121.005));
      expect(states.length, equals(2));

      await sub.cancel();
      await engine.dispose();
    });

    test('detects arrival when within arrivalThreshold', () async {
      final engine = NavigationEngine(
        route: sampleRoute,
        options: const NavigationEngineOptions(
          arrivalThresholdMeters: 20.0,
          enableBackgroundIsolates: false,
        ),
      );

      final events = <NavEvent>[];
      final sub = engine.eventStream.listen(events.add);

      // Tick at destination coordinate
      await engine.processTick(NavPosition.now(latitude: 14.500, longitude: 121.010));

      expect(engine.hasArrived, isTrue);
      expect(events.whereType<ArrivedEvent>().isNotEmpty, isTrue);

      await sub.cancel();
      await engine.dispose();
    });

    test('emits OffRouteEvent and RerouteRequestedEvent when drifting away', () async {
      final engine = NavigationEngine(
        route: sampleRoute,
        options: const NavigationEngineOptions(
          offRouteThresholdMeters: 30.0,
          offRouteConsecutiveTicks: 2,
          enableBackgroundIsolates: false,
        ),
      );

      final events = <NavEvent>[];
      final sub = engine.eventStream.listen(events.add);

      // Drift far away (> 100m) for 2 ticks
      await engine.processTick(NavPosition.now(latitude: 14.502, longitude: 121.000));
      await engine.processTick(NavPosition.now(latitude: 14.502, longitude: 121.000));

      expect(events.whereType<OffRouteEvent>().isNotEmpty, isTrue);
      expect(events.whereType<RerouteRequestedEvent>().isNotEmpty, isTrue);

      await sub.cancel();
      await engine.dispose();
    });

    test('updates route dynamically on updateRoute()', () async {
      final engine = NavigationEngine(
        route: sampleRoute,
        options: const NavigationEngineOptions(enableBackgroundIsolates: false),
      );

      final events = <NavEvent>[];
      final sub = engine.eventStream.listen(events.add);

      final newRoute = OsrmPayload(
        code: 'Ok',
        routes: [
          const OsrmRoute(
            distance: 500.0,
            duration: 50.0,
            geometryCoordinates: [
              [121.000, 14.500],
              [121.002, 14.500],
            ],
            legs: [],
          ),
        ],
      );

      engine.updateRoute(newRoute);
      expect(engine.route.primaryRoute?.distance, equals(500.0));
      expect(events.whereType<RerouteCompletedEvent>().isNotEmpty, isTrue);

      await sub.cancel();
      await engine.dispose();
    });

    test('invokes onArrived callback with 1-based stop count index', () async {
      final arrivedStops = <int>[];
      final engine = NavigationEngine(
        route: sampleRoute,
        options: const NavigationEngineOptions(
          arrivalThresholdMeters: 20.0,
          enableBackgroundIsolates: false,
        ),
        onArrived: (stopCount) {
          arrivedStops.add(stopCount);
        },
      );

      // Tick at destination coordinate
      await engine.processTick(NavPosition.now(latitude: 14.500, longitude: 121.010));

      expect(arrivedStops, equals([1]));
      expect(engine.hasArrived, isTrue);

      await engine.dispose();
    });

    test('excludes initial origin waypoint from stops count and titles', () async {
      final multiStopRoute = OsrmPayload(
        code: 'Ok',
        waypoints: [
          const OsrmWaypoint(name: 'Start Depot', location: [121.000, 14.500]),
          const OsrmWaypoint(name: 'Pickup Point', location: [121.005, 14.500]),
          const OsrmWaypoint(name: 'Customer Dropoff', location: [121.010, 14.500]),
        ],
        routes: [
          const OsrmRoute(
            distance: 2000.0,
            duration: 200.0,
            geometryCoordinates: [
              [121.000, 14.500],
              [121.005, 14.500],
              [121.010, 14.500],
            ],
            legs: [
              OsrmLeg(
                distance: 1000.0,
                duration: 100.0,
                summary: 'Leg 1',
                steps: [
                  OsrmStep(
                    distance: 1000.0,
                    duration: 100.0,
                    name: 'Leg 1 Step',
                    geometryCoordinates: [
                      [121.000, 14.500],
                      [121.005, 14.500],
                    ],
                    maneuver: OsrmManeuver(
                      type: 'depart',
                      modifier: 'straight',
                      location: [121.000, 14.500],
                    ),
                  ),
                ],
              ),
              OsrmLeg(
                distance: 1000.0,
                duration: 100.0,
                summary: 'Leg 2',
                steps: [
                  OsrmStep(
                    distance: 1000.0,
                    duration: 100.0,
                    name: 'Leg 2 Step',
                    geometryCoordinates: [
                      [121.005, 14.500],
                      [121.010, 14.500],
                    ],
                    maneuver: OsrmManeuver(
                      type: 'turn',
                      modifier: 'straight',
                      location: [121.005, 14.500],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final arrivedCounts = <int>[];
      final engine = NavigationEngine(
        route: multiStopRoute,
        options: const NavigationEngineOptions(
          arrivalThresholdMeters: 10.0,
          enableBackgroundIsolates: false,
        ),
        onArrived: (stopCount) => arrivedCounts.add(stopCount),
        waypoints: [
          NavWaypoint.fromCoords(latitude: 14.500, longitude: 121.000, title: 'Start Depot'),
          NavWaypoint.fromCoords(latitude: 14.500, longitude: 121.005, title: 'Pickup Point'),
          NavWaypoint.fromCoords(latitude: 14.500, longitude: 121.010, title: 'Customer Dropoff'),
        ],
      );

      final states = <NavigationState>[];
      final sub = engine.stateStream.listen(states.add);

      // Tick 1: at start
      await engine.processTick(NavPosition.now(latitude: 14.500, longitude: 121.000));
      expect(states.last.totalStopsCount, equals(2), reason: 'Total destination stops should be 2, excluding start depot');
      expect(states.last.currentStopTitle, equals('Pickup Point'), reason: 'First leg destination should be Pickup Point');
      expect(states.last.currentStopIndex, equals(0));

      // Tick 2: reach Stop 1 (Pickup Point)
      await engine.processTick(NavPosition.now(latitude: 14.500, longitude: 121.005));
      expect(arrivedCounts, equals([1]));

      // Tick 3: now on leg 2, toward Customer Dropoff
      await engine.processTick(NavPosition.now(latitude: 14.500, longitude: 121.007));
      expect(states.last.currentStopTitle, equals('Customer Dropoff'));
      expect(states.last.currentStopIndex, equals(1));

      // Tick 4: reach Stop 2 (Customer Dropoff)
      await engine.processTick(NavPosition.now(latitude: 14.500, longitude: 121.010));
      expect(arrivedCounts, equals([1, 2]));
      expect(engine.hasArrived, isTrue);

      await sub.cancel();
      await engine.dispose();
    });
  });
}
