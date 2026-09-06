import 'location_streaming.dart';

/// Abstract base class for serverless cloud telemetry streaming (subscribing).
///
/// Implementations include [FirebaseLocationStreaming] and [SupabaseLocationStreaming].
abstract class ServerlessLocationStreaming extends LocationStreaming {
  const ServerlessLocationStreaming();
}
