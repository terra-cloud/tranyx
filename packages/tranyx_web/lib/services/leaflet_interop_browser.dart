// Browser-only Leaflet interop.
// Conditionally exported from leaflet_interop.dart — never compiled on server.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:js_interop';
// package:web re-exports dart:js_interop types AND provides DOM APIs.
// Import WITHOUT an alias so extension methods (.toJS, .toDart, etc.) are in scope.
// Do NOT also import 'dart:js_interop_unsafe' — it duplicates extension members
// and causes a dart2js "toJS defined in multiple extensions" ambiguity.
import 'package:web/web.dart';

// ── Leaflet loader ────────────────────────────────────────────────────────────

/// Waits until `window.L` is available (Leaflet loaded from the page <head>).
Future<void> ensureLeafletLoaded() async {
  // Fast path — Leaflet already in <head>
  final existing = window.getProperty<JSAny?>('L'.toJS);
  if (existing != null) return;

  // Slow path — inject dynamically if somehow missing
  final head = document.head!;

  final lnk = document.createElement('link') as HTMLLinkElement;
  lnk.rel = 'stylesheet';
  lnk.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
  head.appendChild(lnk);

  final completer = Completer<void>();
  final scr = document.createElement('script') as HTMLScriptElement;
  scr.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
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

// ── Leaflet map lifecycle ─────────────────────────────────────────────────────

JSObject? _L() => window.getProperty<JSObject?>('L'.toJS);
JSObject? _map(String id) => window.getProperty<JSObject?>('__lmap_$id'.toJS);

Future<void> initMap(String elementId, double lat, double lng, int zoom, {bool isDark = true}) async {
  final found = await _waitForElement(elementId);
  if (!found) return;

  final L = _L();
  if (L == null) return;

  // Destroy any stale map on this element
  final mapKey = '__lmap_$elementId'.toJS;
  final old = window.getProperty<JSObject?>(mapKey);
  if (old != null) {
    try {
      old.callMethod<JSAny>('remove'.toJS);
    } catch (_) {}
    window.setProperty(mapKey, null);
  }

  final opts = JSObject();
  opts.setProperty('center'.toJS, [lat.toJS, lng.toJS].toJS);
  opts.setProperty('zoom'.toJS, zoom.toJS);
  final m = L.callMethod<JSObject>('map'.toJS, elementId.toJS, opts);

  final tileOpts = JSObject();
  tileOpts.setProperty(
    'attribution'.toJS,
    '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'.toJS,
  );
  tileOpts.setProperty('subdomains'.toJS, 'abc'.toJS);
  tileOpts.setProperty('maxZoom'.toJS, 19.toJS);
  if (isDark) {
    tileOpts.setProperty('className'.toJS, 'map-tiles-dark'.toJS);
  }

  const tileUrl = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';

  L
      .callMethod<JSObject>(
        'tileLayer'.toJS,
        tileUrl.toJS,
        tileOpts,
      )
      .callMethod<JSAny>('addTo'.toJS, m);

  window.setProperty(mapKey, m);
}

void onMapClick(String elementId, void Function(double lat, double lng) onTap) {
  final m = _map(elementId);
  if (m == null) return;
  m.callMethod<JSAny>(
    'on'.toJS,
    'click'.toJS,
    ((JSObject e) {
      final ll = e.getProperty<JSObject>('latlng'.toJS);
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
  final L = _L();
  final m = _map(elementId);
  if (L == null || m == null) return;

  final storeKey = '__lmarker_${elementId}_$markerId'.toJS;
  final existing = window.getProperty<JSObject?>(storeKey);
  if (existing != null) {
    existing.callMethod<JSAny>('setLatLng'.toJS, [lat.toJS, lng.toJS].toJS);
    if (popupText != null) {
      existing.callMethod<JSAny>('setPopupContent'.toJS, popupText.toJS);
    }
  } else {
    final latLng = L.callMethod<JSObject>('latLng'.toJS, lat.toJS, lng.toJS);
    final marker = L.callMethod<JSObject>('marker'.toJS, latLng).callMethod<JSObject>('addTo'.toJS, m);
    if (popupText != null) {
      marker.callMethod<JSObject>('bindPopup'.toJS, popupText.toJS).callMethod<JSAny>('openPopup'.toJS);
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

// drawRoute: straight-line polyline (kept for backward compat)
void drawRoute(String elementId, List<List<double>> points, String color) {
  final L = _L();
  final m = _map(elementId);
  if (L == null || m == null) return;

  final routeKey = '__lroute_$elementId'.toJS;
  final existing = window.getProperty<JSObject?>(routeKey);
  if (existing != null) {
    existing.callMethod<JSAny>('remove'.toJS);
    window.setProperty(routeKey, null);
  }

  final jsPoints = points.map((p) => [p[0].toJS, p[1].toJS].toJS).toList().toJS;
  final opts = JSObject();
  opts.setProperty('color'.toJS, color.toJS);
  opts.setProperty('weight'.toJS, 5.toJS);
  opts.setProperty('opacity'.toJS, 0.85.toJS);
  final poly = L.callMethod<JSObject>('polyline'.toJS, jsPoints, opts).callMethod<JSObject>('addTo'.toJS, m);
  window.setProperty(routeKey, poly);
  m.callMethod<JSAny>('fitBounds'.toJS, poly.callMethod<JSObject>('getBounds'.toJS));
}

/// Draws a real road route using OSRM.
/// Delegates to `window._osrmRoute` defined in main.server.dart's script block
/// so no eval() is needed (CSP-safe).
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

void panTo(String elementId, double lat, double lng) {
  _map(elementId)?.callMethod<JSAny>('panTo'.toJS, [lat.toJS, lng.toJS].toJS);
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
  _map(elementId)?.callMethod<JSAny>('invalidateSize'.toJS);
}

void destroyMap(String elementId) {
  final m = _map(elementId);
  if (m == null) return;
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

// ── OSM Navigation ────────────────────────────────────────────────────────────

/// Opens OSM directions in a new tab (no Google Maps).
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
