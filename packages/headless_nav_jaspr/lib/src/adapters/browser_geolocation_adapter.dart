import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:headless_nav_core/headless_nav_core.dart';

/// Adapts the browser's Geolocation API into a clean [Stream<NavPosition>].
class BrowserGeolocationAdapter {
  final bool enableHighAccuracy;
  final int timeoutMs;
  final int maximumAgeMs;

  StreamController<NavPosition>? _controller;
  int? _watchId;

  BrowserGeolocationAdapter({
    this.enableHighAccuracy = true,
    this.timeoutMs = 10000,
    this.maximumAgeMs = 0,
  });

  /// Starts listening to `window.navigator.geolocation.watchPosition`.
  Stream<NavPosition> stream() {
    _controller = StreamController<NavPosition>.broadcast(
      onListen: _startWatching,
      onCancel: _stopWatching,
    );
    return _controller!.stream;
  }

  void _startWatching() {
    final geolocation = web.window.navigator.geolocation;

    final options = web.PositionOptions(
      enableHighAccuracy: enableHighAccuracy,
      timeout: timeoutMs,
      maximumAge: maximumAgeMs,
    );

    final successCallback = ((web.GeolocationPosition position) {
      final coords = position.coords;
      final navPos = NavPosition(
        latitude: coords.latitude.toDouble(),
        longitude: coords.longitude.toDouble(),
        heading: coords.heading != null && !coords.heading!.isNaN
            ? coords.heading!.toDouble()
            : null,
        speed: coords.speed != null && !coords.speed!.isNaN
            ? coords.speed!.toDouble()
            : null,
        altitude: coords.altitude != null && !coords.altitude!.isNaN
            ? coords.altitude!.toDouble()
            : null,
        accuracy: coords.accuracy.toDouble(),
        timestamp: DateTime.now().toUtc(),
      );

      _controller?.add(navPos);
    }).toJS;

    final errorCallback = ((web.GeolocationPositionError error) {
      _controller?.addError(Exception('Geolocation error (${error.code}): ${error.message}'));
    }).toJS;

    _watchId = geolocation.watchPosition(
      successCallback,
      errorCallback,
      options,
    );
  }

  void _stopWatching() {
    if (_watchId != null) {
      web.window.navigator.geolocation.clearWatch(_watchId!);
      _watchId = null;
    }
  }

  void dispose() {
    _stopWatching();
    _controller?.close();
  }
}
