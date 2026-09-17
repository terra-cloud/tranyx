import 'dart:async';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:headless_nav_core/headless_nav_core.dart';

/// Offline route database implementation backed by browser [web.window.localStorage].
class WebLocalStorageRouteDatabase implements RouteDatabase {
  final String keyPrefix;

  WebLocalStorageRouteDatabase({this.keyPrefix = 'hn_route_'});

  String _prefixed(String key) => '$keyPrefix$key';

  @override
  Future<OsrmPayload?> getRoute(String key) async {
    try {
      final raw = web.window.localStorage.getItem(_prefixed(key));
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return OsrmPayload.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveRoute(String key, OsrmPayload payload) async {
    try {
      final raw = jsonEncode(payload.toJson());
      web.window.localStorage.setItem(_prefixed(key), raw);
    } catch (_) {}
  }

  @override
  Future<void> deleteRoute(String key) async {
    try {
      web.window.localStorage.removeItem(_prefixed(key));
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      final keysToRemove = <String>[];
      for (int i = 0; i < web.window.localStorage.length; i++) {
        final k = web.window.localStorage.key(i);
        if (k != null && k.startsWith(keyPrefix)) {
          keysToRemove.add(k);
        }
      }
      for (final k in keysToRemove) {
        web.window.localStorage.removeItem(k);
      }
    } catch (_) {}
  }
}
