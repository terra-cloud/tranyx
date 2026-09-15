import 'dart:async';
import '../telemetry/broadcaster_telemetry.dart';
import 'serverless_location_streaming.dart';

/// Function signature providing a stream of incoming Supabase Realtime broadcast payloads.
typedef SupabaseEventStreamProvider = Stream<Map<String, dynamic>> Function(
  String topic,
  String event,
);

/// Serverless Supabase Realtime implementation of [LocationStreaming].
///
/// Subscribes to broadcast messages on Supabase topic `<topicPrefix>:<channelId>`.
class SupabaseLocationStreaming extends ServerlessLocationStreaming {
  final String topicPrefix;
  final String eventName;
  final SupabaseEventStreamProvider? streamProvider;

  bool _isClosed = false;

  SupabaseLocationStreaming({
    this.topicPrefix = 'telemetry',
    this.eventName = 'location_update',
    this.streamProvider,
  });

  @override
  Stream<BroadcasterTelemetry> stream(String channelId) {
    if (_isClosed) {
      throw StateError('Cannot stream from a closed SupabaseLocationStreaming.');
    }

    if (streamProvider == null) {
      return const Stream.empty();
    }

    final topic = '$topicPrefix:$channelId';
    return streamProvider!(topic, eventName).map((data) {
      return BroadcasterTelemetry.fromJson(data);
    });
  }

  @override
  Future<void> close() async {
    _isClosed = true;
  }
}
