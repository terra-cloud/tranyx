import 'dart:async';
import '../telemetry/broadcaster_telemetry.dart';
import 'serverless_location_streaming.dart';

/// Function signature providing real-time document snapshots from Firestore or Firebase RTDB.
typedef FirebaseSnapshotStreamProvider = Stream<Map<String, dynamic>> Function(
  String collectionPath,
  String documentId,
);

/// Serverless Firebase implementation of [LocationStreaming].
///
/// Subscribes to real-time document snapshots from Cloud Firestore or Firebase Realtime DB.
class FirebaseLocationStreaming extends ServerlessLocationStreaming {
  final String collectionPath;
  final FirebaseSnapshotStreamProvider? snapshotProvider;

  bool _isClosed = false;

  FirebaseLocationStreaming({
    this.collectionPath = 'live_telemetry',
    this.snapshotProvider,
  });

  @override
  Stream<BroadcasterTelemetry> stream(String channelId) {
    if (_isClosed) {
      throw StateError('Cannot stream from a closed FirebaseLocationStreaming.');
    }

    if (snapshotProvider == null) {
      return const Stream.empty();
    }

    return snapshotProvider!(collectionPath, channelId).map((data) {
      return BroadcasterTelemetry.fromJson(data);
    });
  }

  @override
  Future<void> close() async {
    _isClosed = true;
  }
}
