import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:headless_nav_core/headless_nav_core.dart';

/// Adapts hardware GPS updates from package:geolocator into a [Stream<NavPosition>].
class GeolocatorAdapter {
  final LocationAccuracy desiredAccuracy;
  final int distanceFilter;

  /// Optional platform-specific location settings (e.g. [AppleSettings] with
  /// background location updates, or [AndroidSettings] with foreground service).
  final LocationSettings? locationSettings;

  const GeolocatorAdapter({
    this.desiredAccuracy = LocationAccuracy.high,
    this.distanceFilter = 2,
    this.locationSettings,
  });

  /// Requests permissions if needed and begins listening to GPS location updates.
  Stream<NavPosition> getPositionStream() async* {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceDisabledException();
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const PermissionDeniedException('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw const PermissionDeniedException(
          'Location permissions are permanently denied, cannot request permissions.');
    }

    final settings = locationSettings ??
        LocationSettings(
          accuracy: desiredAccuracy,
          distanceFilter: distanceFilter,
        );

    yield* Geolocator.getPositionStream(locationSettings: settings).map((pos) {
      return NavPosition(
        latitude: pos.latitude,
        longitude: pos.longitude,
        heading: pos.heading >= 0 ? pos.heading : null,
        speed: pos.speed >= 0 ? pos.speed : null,
        altitude: pos.altitude,
        accuracy: pos.accuracy,
        timestamp: pos.timestamp,
      );
    });
  }
}
