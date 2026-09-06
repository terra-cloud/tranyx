import 'dart:async';
import '../telemetry/broadcaster_telemetry.dart';
import 'serverless_location_broadcaster.dart';

/// Function signature for broadcasting an event on a Supabase Realtime Channel.
typedef SupabaseChannelBroadcaster = Future<void> Function(
  String topic,
  String event,
  Map<String, dynamic> payload,
);

/// Serverless Supabase Realtime implementation of [LocationBroadcaster].
///
/// Dispatches broadcast events to Supabase Realtime topic `<topicPrefix>:<channelId>`.
class SupabaseLocationBroadcaster extends ServerlessLocationBroadcaster {
  final String topicPrefix;
  final String eventName;
  final SupabaseChannelBroadcaster? channelBroadcaster;

  bool _isClosed = false;

  SupabaseLocationBroadcaster({
    this.topicPrefix = 'telemetry',
    this.eventName = 'location_update',
    this.channelBroadcaster,
  });

  @override
  Future<void> broadcast(String channelId, BroadcasterTelemetry telemetry) async {
    if (_isClosed) {
      throw StateError('Cannot broadcast on a closed SupabaseLocationBroadcaster.');
    }

    if (channelBroadcaster != null) {
      final topic = '$topicPrefix:$channelId';
      await channelBroadcaster!(topic, eventName, telemetry.toJson());
    }
  }

  @override
  Future<void> close() async {
    _isClosed = true;
  }
}
