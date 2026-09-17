import 'dart:async';
import 'dart:convert';
import '../telemetry/broadcaster_telemetry.dart';
import 'location_streaming.dart';

/// Server-based WebSocket implementation of [LocationStreaming].
///
/// Subscribes to a WebSocket channel and emits incoming [BroadcasterTelemetry] packets.
class WSLocationStreaming extends LocationStreaming {
  final String serverUrl;
  final String? authToken;
  final Stream<String>? rawMessageStream;

  final Map<String, StreamController<BroadcasterTelemetry>> _controllers = {};
  StreamSubscription? _rawSubscription;
  bool _isClosed = false;

  WSLocationStreaming({
    required this.serverUrl,
    this.authToken,
    this.rawMessageStream,
  }) {
    if (rawMessageStream != null) {
      _rawSubscription = rawMessageStream!.listen(_handleRawMessage);
    }
  }

  void _handleRawMessage(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final action = decoded['action'] as String?;
      if (action == 'broadcast' || action == 'telemetry') {
        final channelId = decoded['channelId'] as String?;
        final payload = decoded['payload'] as Map<String, dynamic>?;
        if (channelId != null && payload != null) {
          final telemetry = BroadcasterTelemetry.fromJson(payload);
          _controllers[channelId]?.add(telemetry);
        }
      }
    } catch (_) {
      // Ignore malformed frames
    }
  }

  @override
  Stream<BroadcasterTelemetry> stream(String channelId) {
    if (_isClosed) {
      throw StateError('Cannot stream from a closed WSLocationStreaming.');
    }

    final controller = _controllers.putIfAbsent(
      channelId,
      () => StreamController<BroadcasterTelemetry>.broadcast(),
    );
    return controller.stream;
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    await _rawSubscription?.cancel();
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
  }
}
