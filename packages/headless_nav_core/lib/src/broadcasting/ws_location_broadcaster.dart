import 'dart:async';
import 'dart:convert';
import '../telemetry/broadcaster_telemetry.dart';
import 'location_broadcaster.dart';

/// Server-based WebSocket implementation of [LocationBroadcaster].
///
/// Dispatches serialized JSON telemetry frames over a persistent WebSocket connection.
class WSLocationBroadcaster extends LocationBroadcaster {
  final String serverUrl;
  final String? authToken;
  final Future<void> Function(String rawMessage)? customSender;

  bool _isClosed = false;

  WSLocationBroadcaster({
    required this.serverUrl,
    this.authToken,
    this.customSender,
  });

  @override
  Future<void> broadcast(String channelId, BroadcasterTelemetry telemetry) async {
    if (_isClosed) {
      throw StateError('Cannot broadcast on a closed WSLocationBroadcaster.');
    }

    final message = jsonEncode({
      'action': 'broadcast',
      'channelId': channelId,
      if (authToken != null) 'authToken': authToken,
      'payload': telemetry.toJson(),
    });

    if (customSender != null) {
      await customSender!(message);
    }
  }

  @override
  Future<void> close() async {
    _isClosed = true;
  }
}
