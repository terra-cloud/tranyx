import 'dart:async';
import '../telemetry/broadcaster_telemetry.dart';
import 'serverless_location_broadcaster.dart';

/// Function signature for updating a document in Firestore or Firebase Realtime DB.
typedef FirebaseDocumentUpdater = Future<void> Function(
  String collectionPath,
  String documentId,
  Map<String, dynamic> data,
);

/// Serverless Firebase implementation of [LocationBroadcaster].
///
/// Writes real-time telemetry updates to Firestore or Firebase Realtime Database
/// under the path `<collectionPath>/<channelId>`.
class FirebaseLocationBroadcaster extends ServerlessLocationBroadcaster {
  final String collectionPath;
  final FirebaseDocumentUpdater? documentUpdater;

  bool _isClosed = false;

  FirebaseLocationBroadcaster({
    this.collectionPath = 'live_telemetry',
    this.documentUpdater,
  });

  @override
  Future<void> broadcast(String channelId, BroadcasterTelemetry telemetry) async {
    if (_isClosed) {
      throw StateError('Cannot broadcast on a closed FirebaseLocationBroadcaster.');
    }

    if (documentUpdater != null) {
      await documentUpdater!(collectionPath, channelId, telemetry.toJson());
    }
  }

  @override
  Future<void> close() async {
    _isClosed = true;
  }
}
