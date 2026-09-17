/// Pure Dart headless turn-by-turn navigation engine with background isolate
/// computation, Turf math, and symmetrical geospatial broadcasting and streaming.
library;


// Models
export 'src/models/nav_position.dart';
export 'src/models/nav_waypoint.dart';
export 'src/models/nav_travel_mode.dart';
export 'src/models/osrm_payload.dart';
export 'src/models/navigation_state.dart';
export 'src/models/nav_event.dart';
export 'src/models/openfreemap_styles.dart';

// Routing & Offline Storage
export 'src/storage/route_database.dart';
export 'src/routing/osrm_router.dart';

// Telemetry
export 'src/telemetry/broadcaster_telemetry.dart';

// Math & Background Computation
export 'src/math/geo_math.dart';
export 'src/math/geo_computation_dispatcher.dart';

// Navigation Engine
export 'src/engine/navigation_engine.dart';
export 'src/engine/navigation_engine_options.dart';

// Simulation
export 'src/simulation/simulated_location_provider.dart';

// Broadcasting (Publishing/Sending)
export 'src/broadcasting/location_broadcaster.dart';
export 'src/broadcasting/ws_location_broadcaster.dart';
export 'src/broadcasting/serverless_location_broadcaster.dart';
export 'src/broadcasting/firebase_location_broadcaster.dart';
export 'src/broadcasting/supabase_location_broadcaster.dart';
export 'src/broadcasting/in_memory_location_broadcaster.dart';

// Streaming (Subscribing/Listening)
export 'src/streaming/location_streaming.dart';
export 'src/streaming/ws_location_streaming.dart';
export 'src/streaming/serverless_location_streaming.dart';
export 'src/streaming/firebase_location_streaming.dart';
export 'src/streaming/supabase_location_streaming.dart';
export 'src/streaming/in_memory_location_streaming.dart';
