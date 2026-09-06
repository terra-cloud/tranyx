import 'dart:async';
import '../telemetry/broadcaster_telemetry.dart';
import 'location_broadcaster.dart';

/// Central in-memory event bus managing telemetry message routing across channels.
class InMemoryTelemetryBus {
  static final InMemoryTelemetryBus defaultInstance = InMemoryTelemetryBus();

  final Map<String, StreamController<BroadcasterTelemetry>> _channelControllers = {};

  Stream<BroadcasterTelemetry> getStream(String channelId) {
    final controller = _channelControllers.putIfAbsent(
      channelId,
      () => StreamController<BroadcasterTelemetry>.broadcast(),
    );
    return controller.stream;
  }

  void publish(String channelId, BroadcasterTelemetry telemetry) {
    final controller = _channelControllers[channelId];
    if (controller != null && !controller.isClosed) {
      controller.add(telemetry);
    }
  }

  void closeChannel(String channelId) {
    _channelControllers[channelId]?.close();
    _channelControllers.remove(channelId);
  }

  void reset() {
    for (final controller in _channelControllers.values) {
      controller.close();
    }
    _channelControllers.clear();
  }
}

/// In-memory implementation of [LocationBroadcaster] for local testing and simulation.
class InMemoryLocationBroadcaster extends LocationBroadcaster {
  final InMemoryTelemetryBus bus;

  InMemoryLocationBroadcaster({InMemoryTelemetryBus? bus})
      : bus = bus ?? InMemoryTelemetryBus.defaultInstance;

  @override
  Future<void> broadcast(String channelId, BroadcasterTelemetry telemetry) async {
    bus.publish(channelId, telemetry);
  }

  @override
  Future<void> close() async {
    // Bus remains open for other channels unless explicitly cleared
  }
}
