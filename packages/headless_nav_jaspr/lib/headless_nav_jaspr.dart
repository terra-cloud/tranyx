/// Jaspr web package for headless_nav with MapLibre GL JS interop,
/// browser geolocation, Web Speech API, and Riverpod state management.
library;


export 'package:headless_nav_core/headless_nav_core.dart';

// Adapters
export 'src/adapters/browser_geolocation_adapter.dart';
export 'src/adapters/web_speech_adapter.dart';

// JS Interop
export 'src/interop/maplibre_interop.dart';

// State Management
export 'package:jaspr_riverpod/jaspr_riverpod.dart';
export 'src/state/jaspr_nav_providers.dart';

// Storage
export 'src/storage/web_local_storage_database.dart';

// Components
export 'src/components/web_navigation_view.dart';
export 'src/components/web_follower_view.dart';
export 'src/components/web_turn_banner.dart';
