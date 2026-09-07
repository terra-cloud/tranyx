import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:headless_nav_core/headless_nav_core.dart';

/// Holds the currently running [NavigationEngine] instance.
final navEngineProvider = StateProvider<NavigationEngine?>((ref) => null);

/// Emits real-time, immutable [NavigationState] updates for the UI.
final navigationStateProvider = StreamProvider<NavigationState>((ref) {
  final engine = ref.watch(navEngineProvider);
  if (engine == null) return const Stream.empty();
  return engine.stateStream;
});

/// Emits discrete navigation events (voice instructions, off route, arrived).
final navEventsProvider = StreamProvider<NavEvent>((ref) {
  final engine = ref.watch(navEngineProvider);
  if (engine == null) return const Stream.empty();
  return engine.eventStream;
});

/// Shared offline route cache database.
final routeDatabaseProvider = Provider<RouteDatabase>((ref) {
  return InMemoryRouteDatabase();
});

/// Shared OSRM FOSSGIS router backed by [routeDatabaseProvider].
final osrmRouterProvider = Provider<OsrmRouter>((ref) {
  final db = ref.watch(routeDatabaseProvider);
  return OsrmFossgisRouter(database: db);
});

/// Active travel mode for the driver (Car, Motorcycle, Bike, Foot).
final travelModeProvider = StateProvider<NavTravelMode>((ref) => NavTravelMode.car);

/// Configured [LocationBroadcaster] for publishing telemetry (WS, Firebase, Supabase, InMemory).
final locationBroadcasterProvider = Provider<LocationBroadcaster>((ref) {
  return InMemoryLocationBroadcaster();
});

/// Configured [LocationStreaming] counterpart for listening to telemetry (WS, Firebase, Supabase, InMemory).
final locationStreamingProvider = Provider<LocationStreaming>((ref) {
  return InMemoryLocationStreaming();
});

/// Tracks whether this device is currently broadcasting its location.
final isBroadcastingActiveProvider = StateProvider<bool>((ref) => false);

/// Active broadcast channel ID.
final activeBroadcastChannelProvider = StateProvider<String?>((ref) => null);

/// Family stream provider for followers listening to a specific broadcaster's live channel.
final liveFollowerStreamProvider =
    StreamProvider.family<BroadcasterTelemetry, String>((ref, channelId) {
  final streaming = ref.watch(locationStreamingProvider);
  return streaming.stream(channelId);
});

/// Controller that binds [NavigationState] ticks to the active [LocationBroadcaster].
class TelemetryBroadcastingController extends StateNotifier<bool> {
  final Ref ref;
  StreamSubscription<NavigationState>? _stateSubscription;

  TelemetryBroadcastingController(this.ref) : super(false);

  Future<void> startBroadcasting({
    required String channelId,
    required String broadcasterId,
    Map<String, dynamic>? metadata,
  }) async {
    final broadcaster = ref.read(locationBroadcasterProvider);
    final engine = ref.read(navEngineProvider);

    if (engine == null) return;

    ref.read(activeBroadcastChannelProvider.notifier).state = channelId;
    ref.read(isBroadcastingActiveProvider.notifier).state = true;
    state = true;

    _stateSubscription?.cancel();
    _stateSubscription = engine.stateStream.listen((navState) async {
      final mode = ref.read(travelModeProvider);
      final telemetry = BroadcasterTelemetry.fromNavigationState(
        channelId: channelId,
        broadcasterId: broadcasterId,
        state: navState,
        travelMode: mode,
        metadata: metadata,
      );
      await broadcaster.broadcast(channelId, telemetry);
    });
  }

  Future<void> stopBroadcasting() async {
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    ref.read(activeBroadcastChannelProvider.notifier).state = null;
    ref.read(isBroadcastingActiveProvider.notifier).state = false;
    state = false;
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    super.dispose();
  }
}

final telemetryBroadcastingControllerProvider =
    StateNotifierProvider<TelemetryBroadcastingController, bool>((ref) {
  return TelemetryBroadcastingController(ref);
});
