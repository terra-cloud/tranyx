import 'location_broadcaster.dart';

/// Abstract base class for serverless cloud telemetry broadcasting.
///
/// Implementations include [FirebaseLocationBroadcaster] and [SupabaseLocationBroadcaster].
abstract class ServerlessLocationBroadcaster extends LocationBroadcaster {
  const ServerlessLocationBroadcaster();
}
