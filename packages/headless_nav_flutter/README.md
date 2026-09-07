# headless_nav_flutter

Flutter frontend package for `headless_nav`.

Provides:
- **`NavigationView`**: Real-time driver UI with MapLibre GL map, turn banner, rotating camera, and live route line overlay.
- **`FollowerNavigationView`**: Real-time follower UI tracking a broadcaster vehicle marker with bearing rotation, live ETA, and turn previews.
- **Adapters**:
  - `GeolocatorAdapter`: Device GPS hardware integration.
  - `FlutterTtsAdapter`: Voice prompt audio output via `flutter_tts`.
- **Riverpod State Bindings**:
  - `navEngineProvider`, `navigationStateProvider`, `navEventsProvider`
  - `locationBroadcasterProvider`, `locationStreamingProvider`, `liveFollowerStreamProvider(channelId)`
