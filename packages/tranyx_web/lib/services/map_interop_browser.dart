// Browser-only MapLibre interop.
// Conditionally exported from map_interop.dart — never compiled on server.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart';

// ── MapLibre loader ────────────────────────────────────────────────────────────

/// Waits until `window.maplibregl` is available (MapLibre loaded from the page <head>).
Future<void> ensureMapLibreLoaded() async {
  // Fast path — MapLibre already loaded on window
  final existing = window.getProperty<JSAny?>('maplibregl'.toJS);
  if (existing != null) return;

  // Check if a script is already in the document (either from index.html or previous call)
  final existingScript = document.querySelector('script[src*="maplibre-gl"]');
  if (existingScript != null) {
    // Just wait until window.maplibregl becomes available (max 10 seconds)
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (window.getProperty<JSAny?>('maplibregl'.toJS) != null) return;
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  // Slow path — inject dynamically if missing
  final head = document.head!;

  if (document.querySelector('link[href*="maplibre-gl"]') == null) {
    final lnk = document.createElement('link') as HTMLLinkElement;
    lnk.rel = 'stylesheet';
    lnk.href = 'https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css';
    head.appendChild(lnk);
  }

  final completer = Completer<void>();
  final scr = document.createElement('script') as HTMLScriptElement;
  scr.src = 'https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js';
  scr.onLoad.listen((_) => completer.complete());
  head.appendChild(scr);

  await completer.future;
}

// ── Helper: wait for a DOM element ────────────────────────────────────────────

Future<bool> _waitForElement(String id, {int maxWaitMs = 3000}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: maxWaitMs));
  while (DateTime.now().isBefore(deadline)) {
    if (document.getElementById(id) != null) return true;
    await Future.delayed(const Duration(milliseconds: 50));
  }
  return false;
}

// ── Geolocation ───────────────────────────────────────────────────────────────

Future<({double lat, double lng})?> getCurrentPosition() async {
  final completer = Completer<({double lat, double lng})?>();
  try {
    window.navigator.geolocation.getCurrentPosition(
      ((GeolocationPosition pos) {
        final c = pos.coords;
        completer.complete((lat: c.latitude, lng: c.longitude));
      }).toJS,
      ((GeolocationPositionError err) {
        completer.complete(null);
      }).toJS,
    );
  } catch (_) {
    completer.complete(null);
  }
  return completer.future;
}

int watchPosition(void Function(double lat, double lng) onUpdate) {
  return window.navigator.geolocation.watchPosition(
    ((GeolocationPosition pos) {
      final c = pos.coords;
      onUpdate(c.latitude, c.longitude);
    }).toJS,
  );
}

void clearWatch(int id) => window.navigator.geolocation.clearWatch(id);

// ── MapLibre map lifecycle ─────────────────────────────────────────────────────

JSObject? _map(String id) => window.getProperty<JSObject?>('__lmap_$id'.toJS);

Future<void> initMap(
  String elementId,
  double lat,
  double lng,
  double zoom, {
  bool isDark = true,
  double pitch = 0,
  double bearing = 0,
}) async {
  final found = await _waitForElement(elementId);
  if (!found) {
    print('ERROR: Map element with ID "$elementId" was not found in the DOM.');
    return;
  }

  final maplibregl = window.getProperty<JSObject?>('maplibregl'.toJS);
  if (maplibregl == null) {
    print('ERROR: window.maplibregl is not defined when initializing map.');
    return;
  }

  // Destroy any stale map on this element
  final mapKey = '__lmap_$elementId'.toJS;
  final old = window.getProperty<JSObject?>(mapKey);
  if (old != null) {
    try {
      old.callMethod<JSAny>('remove'.toJS);
    } catch (_) {}
    window.setProperty(mapKey, null);
  }

  try {
    // Create raster-style specification locally to avoid needing any MapLibre / Mapbox API Key
    final style = JSObject();
    style.setProperty('version'.toJS, 8.toJS);

    final sources = JSObject();
    final rasterTiles = JSObject();
    rasterTiles.setProperty('type'.toJS, 'raster'.toJS);

    final tileUrl = isDark
        ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    final tiles = [tileUrl.toJS].toJS;

    rasterTiles.setProperty('tiles'.toJS, tiles);
    rasterTiles.setProperty('tileSize'.toJS, 256.toJS);
    rasterTiles.setProperty('attribution'.toJS, isDark ? '© CARTO, © OpenStreetMap'.toJS : '© OpenStreetMap'.toJS);
    sources.setProperty('raster-tiles'.toJS, rasterTiles);
    style.setProperty('sources'.toJS, sources);

    final layer = JSObject();
    layer.setProperty('id'.toJS, 'simple-tiles'.toJS);
    layer.setProperty('type'.toJS, 'raster'.toJS);
    layer.setProperty('source'.toJS, 'raster-tiles'.toJS);
    layer.setProperty('minzoom'.toJS, 0.toJS);
    layer.setProperty('maxzoom'.toJS, 19.toJS);
    final layers = [layer].toJS;
    style.setProperty('layers'.toJS, layers);

    final opts = JSObject();
    opts.setProperty('container'.toJS, elementId.toJS);
    opts.setProperty('style'.toJS, style);

    // MapLibre expects center as [lng, lat]
    opts.setProperty('center'.toJS, [lng.toJS, lat.toJS].toJS);
    opts.setProperty('zoom'.toJS, zoom.toJS);
    opts.setProperty('pitch'.toJS, pitch.toJS);
    opts.setProperty('bearing'.toJS, bearing.toJS);

    final m = window.callMethod<JSObject>('_createMap'.toJS, opts);
    window.setProperty(mapKey, m);
    print('DEBUG: MapLibre map successfully created on element ID "$elementId".');
  } catch (e) {
    print('ERROR: Failed during initMap execution for element ID "$elementId": $e');
    rethrow;
  }
}

void onMapClick(String elementId, void Function(double lat, double lng) onTap) {
  final m = _map(elementId);
  if (m == null) return;
  m.callMethod<JSAny>(
    'on'.toJS,
    'click'.toJS,
    ((JSObject e) {
      final ll = e.getProperty<JSObject>('lngLat'.toJS);
      final lat = ll.getProperty<JSNumber>('lat'.toJS).toDartDouble;
      final lng = ll.getProperty<JSNumber>('lng'.toJS).toDartDouble;
      onTap(lat, lng);
    }).toJS,
  );
}

void setMarker(
  String elementId,
  String markerId,
  double lat,
  double lng,
  String? popupText,
) {
  final m = _map(elementId);
  if (m == null) return;

  final storeKey = '__lmarker_${elementId}_$markerId'.toJS;
  final existing = window.getProperty<JSObject?>(storeKey);

  if (existing != null) {
    existing.callMethod<JSAny>('setLngLat'.toJS, [lng.toJS, lat.toJS].toJS);
    if (popupText != null) {
      final popup = existing.callMethod<JSObject?>('getPopup'.toJS);
      if (popup != null) {
        popup.callMethod<JSAny>('setHTML'.toJS, popupText.toJS);
      } else {
        final newPopup = window.callMethod<JSObject>('_createPopup'.toJS);
        newPopup.callMethod<JSAny>('setHTML'.toJS, popupText.toJS);
        existing.callMethod<JSAny>('setPopup'.toJS, newPopup);
      }
    }
  } else {
    final marker = window.callMethod<JSObject>('_createMarker'.toJS);
    marker.callMethod<JSObject>('setLngLat'.toJS, [lng.toJS, lat.toJS].toJS);

    if (popupText != null) {
      final popup = window.callMethod<JSObject>('_createPopup'.toJS);
      popup.callMethod<JSAny>('setHTML'.toJS, popupText.toJS);
      marker.callMethod<JSObject>('setPopup'.toJS, popup);
      marker.callMethod<JSAny>('addTo'.toJS, m);
      // Toggle to open the popup immediately
      marker.callMethod<JSAny>('togglePopup'.toJS);
    } else {
      marker.callMethod<JSAny>('addTo'.toJS, m);
    }

    window.setProperty(storeKey, marker);
  }
}

void removeMarker(String elementId, String markerId) {
  final storeKey = '__lmarker_${elementId}_$markerId'.toJS;
  final existing = window.getProperty<JSObject?>(storeKey);
  if (existing != null) {
    existing.callMethod<JSAny>('remove'.toJS);
    window.setProperty(storeKey, null);
  }
}

void drawRoute(String elementId, List<List<double>> points, String color) {
  final m = _map(elementId);
  if (m == null) return;

  final routeKey = '__lroute_$elementId'.toJS;
  final existing = window.getProperty<JSObject?>(routeKey);
  if (existing != null) {
    try {
      final sourceId = existing.getProperty<JSString>('sourceId'.toJS);
      final layerId = existing.getProperty<JSString>('layerId'.toJS);
      if (m.callMethod<JSBoolean>('getLayer'.toJS, layerId).toDart) {
        m.callMethod<JSAny>('removeLayer'.toJS, layerId);
      }
      if (m.callMethod<JSBoolean>('getSource'.toJS, sourceId).toDart) {
        m.callMethod<JSAny>('removeSource'.toJS, sourceId);
      }
    } catch (_) {}
    window.setProperty(routeKey, null);
  }

  // Convert [[lat, lng], ...] to [[lng, lat], ...] for MapLibre
  final rawCoords = points.map((p) => [p[1].toJS, p[0].toJS].toJS).toList().toJS;

  final geojson = JSObject();
  geojson.setProperty('type'.toJS, 'Feature'.toJS);
  geojson.setProperty('properties'.toJS, JSObject());

  final geom = JSObject();
  geom.setProperty('type'.toJS, 'LineString'.toJS);
  geom.setProperty('coordinates'.toJS, rawCoords);
  geojson.setProperty('geometry'.toJS, geom);

  final sourceId = 'route_straight_$elementId';
  final layerId = 'route_straight_layer_$elementId';

  final srcOpts = JSObject();
  srcOpts.setProperty('type'.toJS, 'geojson'.toJS);
  srcOpts.setProperty('data'.toJS, geojson);
  m.callMethod<JSAny>('addSource'.toJS, sourceId.toJS, srcOpts);

  final paintOpts = JSObject();
  paintOpts.setProperty('line-color'.toJS, color.toJS);
  paintOpts.setProperty('line-width'.toJS, 5.toJS);
  paintOpts.setProperty('line-opacity'.toJS, 0.85.toJS);

  final layoutOpts = JSObject();
  layoutOpts.setProperty('line-join'.toJS, 'round'.toJS);
  layoutOpts.setProperty('line-cap'.toJS, 'round'.toJS);

  final layerOpts = JSObject();
  layerOpts.setProperty('id'.toJS, layerId.toJS);
  layerOpts.setProperty('type'.toJS, 'line'.toJS);
  layerOpts.setProperty('source'.toJS, sourceId.toJS);
  layerOpts.setProperty('paint'.toJS, paintOpts);
  layerOpts.setProperty('layout'.toJS, layoutOpts);

  m.callMethod<JSAny>('addLayer'.toJS, layerOpts);

  final routeTracker = JSObject();
  routeTracker.setProperty('sourceId'.toJS, sourceId.toJS);
  routeTracker.setProperty('layerId'.toJS, layerId.toJS);
  window.setProperty(routeKey, routeTracker);

  // Fit bounds
  final bounds = window.callMethod<JSObject>('_createLngLatBounds'.toJS);
  points.forEach((p) {
    bounds.callMethod<JSAny>('extend'.toJS, [p[1].toJS, p[0].toJS].toJS);
  });
  final fitOpts = JSObject();
  fitOpts.setProperty('padding'.toJS, 40.toJS);
  m.callMethod<JSAny>('fitBounds'.toJS, bounds, fitOpts);
}

Future<Map<String, dynamic>?> drawOSRMRoute(
  String elementId,
  double fromLat,
  double fromLng,
  double toLat,
  double toLng,
  String color,
) async {
  final fn = window.getProperty<JSFunction?>('_osrmRoute'.toJS);
  if (fn == null) return null;
  final args = [
    elementId.toJS,
    fromLat.toJS,
    fromLng.toJS,
    toLat.toJS,
    toLng.toJS,
    color.toJS,
  ].toJS;
  final promise = fn.callAsFunction(null, args) as JSPromise;
  final res = await promise.toDart;
  if (res == null) return null;
  final jsonStr = (res as JSString).toDart;
  try {
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

void speakText(String text) {
  final fn = window.getProperty<JSFunction?>('speakText'.toJS);
  if (fn == null) return;
  fn.callAsFunction(null, text.toJS);
}

void panTo(String elementId, double lat, double lng, {double? bearing, double? pitch, double? zoom}) {
  final m = _map(elementId);
  if (m == null) return;

  final opts = JSObject();
  opts.setProperty('center'.toJS, [lng.toJS, lat.toJS].toJS);
  if (bearing != null) {
    opts.setProperty('bearing'.toJS, bearing.toJS);
  }
  if (pitch != null) {
    opts.setProperty('pitch'.toJS, pitch.toJS);
  }
  if (zoom != null) {
    opts.setProperty('zoom'.toJS, zoom.toJS);
  }
  opts.setProperty('duration'.toJS, 1000.toJS); // 1s smooth camera glide

  m.callMethod<JSAny>('easeTo'.toJS, opts);
}

({double lat, double lng})? getMapCenter(String elementId) {
  final m = _map(elementId);
  if (m == null) return null;
  final ll = m.callMethod<JSObject>('getCenter'.toJS);
  return (
    lat: ll.getProperty<JSNumber>('lat'.toJS).toDartDouble,
    lng: ll.getProperty<JSNumber>('lng'.toJS).toDartDouble,
  );
}

void invalidateMapSize(String elementId) {
  _map(elementId)?.callMethod<JSAny>('resize'.toJS);
}

void destroyMap(String elementId) {
  final m = _map(elementId);
  if (m == null) return;

  // Clean up any route if present
  final routeKey = '__lroute_$elementId'.toJS;
  final route = window.getProperty<JSObject?>(routeKey);
  if (route != null) {
    try {
      final sourceId = route.getProperty<JSString>('sourceId'.toJS);
      final layerId = route.getProperty<JSString>('layerId'.toJS);
      if (m.callMethod<JSBoolean>('getLayer'.toJS, layerId).toDart) {
        m.callMethod<JSAny>('removeLayer'.toJS, layerId);
      }
      if (m.callMethod<JSBoolean>('getSource'.toJS, sourceId).toDart) {
        m.callMethod<JSAny>('removeSource'.toJS, sourceId);
      }
    } catch (_) {}
    window.setProperty(routeKey, null);
  }

  m.callMethod<JSAny>('remove'.toJS);
  window.setProperty('__lmap_$elementId'.toJS, null);
}

// ── Reverse Geocoding (Nominatim) ─────────────────────────────────────────────

Future<String> reverseGeocode(double lat, double lng) async {
  try {
    final url = 'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng';
    final resp = await window.fetch(url.toJS).toDart;
    final json = await resp.json().toDart;
    final obj = json as JSObject;
    return obj.getProperty<JSString?>('display_name'.toJS)?.toDart ?? '$lat, $lng';
  } catch (_) {
    return '$lat, $lng';
  }
}

Future<List<Map<String, dynamic>>> searchAddress(String query) async {
  try {
    final url = 'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=5';
    final resp = await window.fetch(url.toJS).toDart;
    final jsonText = await resp.text().toDart;
    final text = jsonText.toDart;
    final decoded = jsonDecode(text);
    if (decoded is List) {
      return decoded.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
    return [];
  } catch (e) {
    print('ERROR searching address: $e');
    return [];
  }
}

// ── OSM Navigation ────────────────────────────────────────────────────────────

void openOSMNavigation(double destLat, double destLng) {
  window.open(
    'https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=;$destLat,$destLng',
    '_blank',
  );
}

// ── Phantom Wallet ────────────────────────────────────────────────────────────

JSObject? _phantom() {
  try {
    final p = window.getProperty<JSObject?>('phantom'.toJS);
    return p?.getProperty<JSObject?>('solana'.toJS);
  } catch (_) {
    return null;
  }
}

Future<String?> connectPhantomWallet() async {
  final sol = _phantom();
  if (sol == null) return null;
  try {
    final res = await sol.callMethod<JSPromise>('connect'.toJS).toDart;
    final pk = (res as JSObject).getProperty<JSObject>('publicKey'.toJS);
    return pk.callMethod<JSString>('toBase58'.toJS).toDart;
  } catch (_) {
    return null;
  }
}

bool isPhantomInstalled() => _phantom() != null;

Future<String?> getPhantomPublicKeyIfConnected() async {
  final sol = _phantom();
  if (sol == null) return null;
  try {
    final opts = JSObject();
    opts.setProperty('onlyIfTrusted'.toJS, true.toJS);
    final res = await sol.callMethod<JSPromise>('connect'.toJS, opts).toDart;
    final pk = (res as JSObject).getProperty<JSObject>('publicKey'.toJS);
    return pk.callMethod<JSString>('toBase58'.toJS).toDart;
  } catch (_) {
    return null;
  }
}

// ── Google Sign In ────────────────────────────────────────────────────────────

Future<String?> signInWithGoogleJs(Map<String, String> config) async {
  try {
    final jsConfig = JSObject();
    for (final e in config.entries) {
      jsConfig.setProperty(e.key.toJS, e.value.toJS);
    }
    final res = await window.callMethod<JSPromise>('signInWithGoogle'.toJS, jsConfig).toDart;
    return (res as JSString).toDart;
  } catch (_) {
    return null;
  }
}

// ── Session Storage ───────────────────────────────────────────────────────────

class SessionStorage {
  static const _uid = 'tranyx_uid';
  static const _tok = 'tranyx_token';
  static const _ref = 'tranyx_refresh';
  static const _name = 'tranyx_name';
  static const _email = 'tranyx_email';
  static const _acct = 'tranyx_account_type';

  static void save(dynamic auth) {
    window.localStorage.setItem(_uid, auth.uid as String);
    window.localStorage.setItem(_tok, auth.idToken as String);
    if (auth.refreshToken != null) window.localStorage.setItem(_ref, auth.refreshToken as String);
    if (auth.displayName != null) window.localStorage.setItem(_name, auth.displayName as String);
    if (auth.email != null) window.localStorage.setItem(_email, auth.email as String);
  }

  static void saveProfile({String? name, String? email, String? accountType}) {
    if (name != null) window.localStorage.setItem(_name, name);
    if (email != null) window.localStorage.setItem(_email, email);
    if (accountType != null) window.localStorage.setItem(_acct, accountType);
  }

  static String? get uid => window.localStorage.getItem(_uid);
  static String? get idToken => window.localStorage.getItem(_tok);
  static String? get refreshToken => window.localStorage.getItem(_ref);
  static String? get displayName => window.localStorage.getItem(_name);
  static String? get email => window.localStorage.getItem(_email);
  static String? get accountType => window.localStorage.getItem(_acct);

  static bool get hasSession => window.localStorage.getItem(_uid) != null && window.localStorage.getItem(_tok) != null;

  static void clear() {
    for (final k in [_uid, _tok, _ref, _name, _email, _acct]) {
      window.localStorage.removeItem(k);
    }
  }
}

String getHostname() => window.location.hostname;

// ── File reading ──────────────────────────────────────────────────────────────

class WebFile {
  final String name;
  final Uint8List bytes;
  WebFile(this.name, this.bytes);
}

Future<List<WebFile>> readFilesFromEvent(dynamic event) async {
  try {
    final e = event as Event;
    final target = e.target as HTMLInputElement?;
    if (target == null) return [];
    final files = target.files;
    if (files == null || files.length == 0) return [];

    final result = <WebFile>[];
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null) continue;
      final completer = Completer<Uint8List>();
      final reader = FileReader();
      reader.readAsArrayBuffer(file);
      reader.onLoadEnd.listen((_) {
        try {
          final buf = reader.result as JSArrayBuffer;
          completer.complete(buf.toDart.asUint8List());
        } catch (err) {
          completer.completeError(err);
        }
      });
      result.add(WebFile(file.name, await completer.future));
    }
    return result;
  } catch (_) {
    return [];
  }
}

// ── URL opener ────────────────────────────────────────────────────────────────

void openUrl(String url) => window.open(url, '_blank');

// ── Solana balance ────────────────────────────────────────────────────────────

Future<double?> getSolanaBalance(String publicKey) async {
  try {
    const rpc = 'https://api.mainnet-beta.solana.com';
    final body = '{"jsonrpc":"2.0","id":1,"method":"getBalance","params":["$publicKey"]}';
    final headers = Headers();
    headers.set('Content-Type', 'application/json');
    final opts = RequestInit(method: 'POST', body: body.toJS, headers: headers);
    final resp = await window.fetch(rpc.toJS, opts).toDart;
    final json = await resp.json().toDart;
    final obj = json as JSObject;
    final result = obj.getProperty<JSObject>('result'.toJS);
    final lamports = result.getProperty<JSNumber>('value'.toJS).toDartInt;
    return lamports / 1e9;
  } catch (_) {
    return null;
  }
}

void setupMapInteractionListener(
  String elementId,
  void Function() onInteractionStart,
  void Function() onInteractionEnd,
) {
  final m = _map(elementId);
  if (m == null) return;

  m.callMethod<JSAny>(
    'on'.toJS,
    'dragstart'.toJS,
    (() {
      onInteractionStart();
    }).toJS,
  );
  m.callMethod<JSAny>(
    'on'.toJS,
    'zoomstart'.toJS,
    (() {
      onInteractionStart();
    }).toJS,
  );
  m.callMethod<JSAny>(
    'on'.toJS,
    'dragend'.toJS,
    (() {
      onInteractionEnd();
    }).toJS,
  );
  m.callMethod<JSAny>(
    'on'.toJS,
    'zoomend'.toJS,
    (() {
      onInteractionEnd();
    }).toJS,
  );
}
