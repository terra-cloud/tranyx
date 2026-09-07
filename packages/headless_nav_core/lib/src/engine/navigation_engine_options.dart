import 'package:meta/meta.dart';

/// Configuration options for [NavigationEngine].
@immutable
class NavigationEngineOptions {
  /// Distance in meters away from route line before triggering an off-route condition.
  final double offRouteThresholdMeters;

  /// Number of consecutive off-route ticks required before emitting [OffRouteEvent].
  final int offRouteConsecutiveTicks;

  /// Distance in meters from destination to consider the trip arrived.
  final double arrivalThresholdMeters;

  /// Milestone distances in meters that trigger voice instructions for approaching turns.
  final List<double> voiceTriggerDistancesMeters;

  /// Whether to offload geometry math to background isolates via [Isolate.run].
  final bool enableBackgroundIsolates;

  const NavigationEngineOptions({
    this.offRouteThresholdMeters = 40.0,
    this.offRouteConsecutiveTicks = 3,
    this.arrivalThresholdMeters = 15.0,
    this.voiceTriggerDistancesMeters = const [500.0, 200.0, 50.0],
    this.enableBackgroundIsolates = true,
  });
}
