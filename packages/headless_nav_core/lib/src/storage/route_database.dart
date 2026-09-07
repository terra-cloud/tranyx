import 'dart:async';
import 'dart:convert';
import '../models/osrm_payload.dart';

/// Abstract storage contract for persistent and offline caching of OSRM route payloads.
abstract class RouteDatabase {
  /// Retrieves a cached route by key. Returns `null` if not found.
  Future<OsrmPayload?> getRoute(String key);

  /// Saves or overwrites a route in the database.
  Future<void> saveRoute(String key, OsrmPayload payload);

  /// Deletes a specific cached route by key.
  Future<void> deleteRoute(String key);

  /// Clears all cached routes from storage.
  Future<void> clear();
}

/// High-speed, in-memory implementation of [RouteDatabase] for testing,
/// transient sessions, and fast tier caching.
class InMemoryRouteDatabase implements RouteDatabase {
  final Map<String, OsrmPayload> _store = {};

  @override
  Future<OsrmPayload?> getRoute(String key) async {
    return _store[key];
  }

  @override
  Future<void> saveRoute(String key, OsrmPayload payload) async {
    _store[key] = payload;
  }

  @override
  Future<void> deleteRoute(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }

  /// Current number of cached routes in memory.
  int get count => _store.length;
}

/// JSON string-backed key-value store that supports custom string read/write delegates,
/// enabling compatibility with local files, secure storage, or browser storage.
class LocalJsonRouteDatabase implements RouteDatabase {
  final Future<String?> Function(String key) readString;
  final Future<void> Function(String key, String value) writeString;
  final Future<void> Function(String key) removeString;
  final Future<void> Function() clearAll;

  LocalJsonRouteDatabase({
    required this.readString,
    required this.writeString,
    required this.removeString,
    required this.clearAll,
  });

  @override
  Future<OsrmPayload?> getRoute(String key) async {
    try {
      final raw = await readString(key);
      if (raw == null || raw.isEmpty) return null;
      return await OsrmPayload.fromRawJsonBackground(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveRoute(String key, OsrmPayload payload) async {
    try {
      final jsonStr = jsonEncode(payload.toJson());
      await writeString(key, jsonStr);
    } catch (_) {}
  }

  @override
  Future<void> deleteRoute(String key) async {
    await removeString(key);
  }

  @override
  Future<void> clear() async {
    await clearAll();
  }
}
