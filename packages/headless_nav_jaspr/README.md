# headless_nav_jaspr

Modern Jaspr web package for `headless_nav`.

Provides:
- **`WebNavigationView`**: Browser-based turn-by-turn driver component using MapLibre GL JS and modern CSS.
- **`WebFollowerView`**: Live follower component in the browser tracking a broadcaster vehicle marker with easing camera animations and live ETA card.
- **`WebTurnBanner`**: Floating guidance banner.
- **Adapters**:
  - `BrowserGeolocationAdapter`: `window.navigator.geolocation.watchPosition` mapped to `Stream<NavPosition>`.
  - `WebSpeechAdapter`: `window.speechSynthesis` voice instructions via modern `package:web`.
- **State Management**:
  - `jasprNavEngineProvider`, `jasprNavigationStateProvider`, `jasprNavEventsProvider`
  - `jasprLocationBroadcasterProvider`, `jasprLocationStreamingProvider`, `jasprLiveFollowerStreamProvider(channelId)`
