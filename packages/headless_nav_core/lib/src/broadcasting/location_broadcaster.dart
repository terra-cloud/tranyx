import '../telemetry/broadcaster_telemetry.dart';

/// Abstract base contract for geospatial telemetry broadcasting (Publishing/Sending).
abstract class LocationBroadcaster {
  const LocationBroadcaster();

  /// Publishes a telemetry packet to a designated channel / session.
  Future<void> broadcast(String channelId, BroadcasterTelemetry telemetry);

  /// Closes any open connections or underlying transports.
  Future<void> close();
}
