import 'dart:async';
import '../models/nav_position.dart';
import '../models/osrm_payload.dart';
import '../math/geo_math.dart';

/// Simulates a vehicle driving smoothly along an OSRM route at a given speed.
class SimulatedLocationProvider {
  final OsrmPayload route;
  final double speedKmh;
  final Duration interval;

  StreamController<NavPosition>? _controller;
  Timer? _timer;
  int _coordIndex = 0;
  double _fraction = 0.0;

  SimulatedLocationProvider({
    required this.route,
    this.speedKmh = 50.0,
    this.interval = const Duration(milliseconds: 500),
  });

  Stream<NavPosition> stream() {
    _controller = StreamController<NavPosition>(
      onListen: _startTimer,
      onCancel: stop,
    );
    return _controller!.stream;
  }

  void _startTimer() {
    final coords = route.primaryRoute?.geometryCoordinates ?? [];
    if (coords.isEmpty) {
      _controller?.close();
      return;
    }

    _coordIndex = 0;
    _fraction = 0.0;

    final speedMps = (speedKmh * 1000.0) / 3600.0;
    final metersPerTick = speedMps * (interval.inMilliseconds / 1000.0);

    _timer = Timer.periodic(interval, (timer) {
      if (_coordIndex >= coords.length - 1) {
        final last = coords.last;
        _controller?.add(NavPosition.now(
          latitude: last[1],
          longitude: last[0],
          speed: 0.0,
        ));
        stop();
        return;
      }

      final p1 = coords[_coordIndex];
      final p2 = coords[_coordIndex + 1];
      final segmentDistance = GeoMath.distanceMeters(p1[1], p1[0], p2[1], p2[0]);

      if (segmentDistance <= 0.1) {
        _coordIndex++;
        _fraction = 0.0;
        return;
      }

      final fractionIncrement = metersPerTick / segmentDistance;
      _fraction += fractionIncrement;

      if (_fraction >= 1.0) {
        _coordIndex++;
        _fraction = 0.0;
      }

      final currentP1 = coords[_coordIndex];
      final currentP2 = coords[(_coordIndex + 1 < coords.length) ? _coordIndex + 1 : _coordIndex];

      final lat = currentP1[1] + (currentP2[1] - currentP1[1]) * _fraction;
      final lon = currentP1[0] + (currentP2[0] - currentP1[0]) * _fraction;
      final bearing = GeoMath.calculateBearing(currentP1[1], currentP1[0], currentP2[1], currentP2[0]);

      _controller?.add(NavPosition.now(
        latitude: lat,
        longitude: lon,
        heading: bearing,
        speed: speedMps,
      ));
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_controller != null && !_controller!.isClosed) {
      _controller?.close();
    }
  }
}
