/// Flutter navigation widgets, hardware GPS & TTS adapters, follower live tracking,
/// and Riverpod bindings for headless_nav.
library;

export 'package:headless_nav_core/headless_nav_core.dart';

// Adapters
export 'src/adapters/geolocator_adapter.dart';
export 'src/adapters/flutter_tts_adapter.dart';

// State Management
export 'src/state/flutter_nav_providers.dart';

// UI Widgets
export 'src/ui/navigation_view.dart';
export 'src/ui/follower_navigation_view.dart';
export 'src/ui/turn_instruction_banner.dart';
export 'src/ui/telemetry_share_sheet.dart';
