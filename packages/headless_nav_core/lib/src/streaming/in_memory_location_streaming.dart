import '../broadcasting/in_memory_location_broadcaster.dart';
import '../telemetry/broadcaster_telemetry.dart';
import 'location_streaming.dart';

/// In-memory implementation of [LocationStreaming] for local testing and simulation.
class InMemoryLocationStreaming extends LocationStreaming {
  final InMemoryTelemetryBus bus;

  InMemoryLocationStreaming({InMemoryTelemetryBus? bus})
      : bus = bus ?? InMemoryTelemetryBus.defaultInstance;

  @override
  Stream<BroadcasterTelemetry> stream(String channelId) {
    return bus.getStream(channelId);
  }

  @override
  Future<void> close() async {
    // Bus managed independently
  }
}
