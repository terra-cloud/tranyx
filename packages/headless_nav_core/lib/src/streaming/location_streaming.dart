import '../telemetry/broadcaster_telemetry.dart';

/// Abstract base contract for geospatial telemetry streaming (Subscribing/Listening).
abstract class LocationStreaming {
  const LocationStreaming();

  /// Returns a real-time stream of incoming telemetry from a given channel.
  Stream<BroadcasterTelemetry> stream(String channelId);

  /// Closes any active subscriptions or underlying connections.
  Future<void> close();
}
