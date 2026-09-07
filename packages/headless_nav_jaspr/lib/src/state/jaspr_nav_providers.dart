import 'dart:async';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:headless_nav_core/headless_nav_core.dart';
import '../storage/web_local_storage_database.dart';

/// Notifier managing active [NavigationEngine] instance on Web.
class NavigationEngineNotifier extends Notifier<NavigationEngine?> {
  @override
  NavigationEngine? build() => null;

  @override
  set state(NavigationEngine? value) => super.state = value;
}

/// Holds the currently running [NavigationEngine] instance on Web.
final jasprNavEngineProvider =
    NotifierProvider<NavigationEngineNotifier, NavigationEngine?>(
        NavigationEngineNotifier.new);

/// Emits real-time [NavigationState] updates to Jaspr web components.
final jasprNavigationStateProvider = StreamProvider<NavigationState>((ref) {
  final engine = ref.watch(jasprNavEngineProvider);
  if (engine == null) return const Stream.empty();
  return engine.stateStream;
});

/// Emits discrete navigation events (voice instructions, off-route, arrived).
final jasprNavEventsProvider = StreamProvider<NavEvent>((ref) {
  final engine = ref.watch(jasprNavEngineProvider);
  if (engine == null) return const Stream.empty();
  return engine.eventStream;
});

/// Route database provider backed by browser localStorage.
final jasprRouteDatabaseProvider = Provider<RouteDatabase>((ref) {
  return WebLocalStorageRouteDatabase();
});

/// OSRM router provider configured for OpenStreetMap FOSSGIS with local caching.
final jasprOsrmRouterProvider = Provider<OsrmRouter>((ref) {
  final db = ref.watch(jasprRouteDatabaseProvider);
  return OsrmFossgisRouter(database: db);
});

/// Notifier managing travel mode for Jaspr Web.
class TravelModeNotifier extends Notifier<NavTravelMode> {
  @override
  NavTravelMode build() => NavTravelMode.car;

  @override
  set state(NavTravelMode value) => super.state = value;
}

/// Active travel mode provider for Jaspr Web.
final jasprTravelModeProvider =
    NotifierProvider<TravelModeNotifier, NavTravelMode>(TravelModeNotifier.new);

/// Active [LocationBroadcaster] configured for Web.
final jasprLocationBroadcasterProvider = Provider<LocationBroadcaster>((ref) {
  return InMemoryLocationBroadcaster();
});

/// Active [LocationStreaming] configured for Web.
final jasprLocationStreamingProvider = Provider<LocationStreaming>((ref) {
  return InMemoryLocationStreaming();
});

/// Reactive telemetry stream provider for a follower listening to a specific channel.
final jasprLiveFollowerStreamProvider =
    StreamProvider.family<BroadcasterTelemetry, String>((ref, channelId) {
  final streaming = ref.watch(jasprLocationStreamingProvider);
  return streaming.stream(channelId);
});
