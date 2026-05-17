import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:async';
import 'package:web/web.dart' as web;

// ── Leaflet CSS/JS loader ─────────────────────────────────────────────────────

bool _leafletLoaded = false;

/// Injects Leaflet CSS + JS into the page head once.
Future<void> ensureLeafletLoaded() async {
  if (_leafletLoaded) return;
  _leafletLoaded = true;

  final head = web.document.head!;

  // CSS
  final link = web.document.createElement('link') as web.HTMLLinkElement;
  link.rel = 'stylesheet';
  link.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
  head.appendChild(link);

  // JS
  final completer = Completer<void>();
  final script = web.document.createElement('script') as web.HTMLScriptElement;
  script.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
  script.onLoad.listen((_) => completer.complete());
  head.appendChild(script);

  await completer.future;
}

// ── Geolocation ───────────────────────────────────────────────────────────────

/// Requests the browser's current GPS position once.
Future<({double lat, double lng})?> getCurrentPosition() async {
  final completer = Completer<({double lat, double lng})?>();
  try {
    web.window.navigator.geolocation.getCurrentPosition(
      ((web.GeolocationPosition pos) {
        final c = pos.coords;
        completer.complete((lat: c.latitude, lng: c.longitude));
      }).toJS,
      ((web.GeolocationPositionError err) {
        completer.complete(null);
      }).toJS,
    );
  } catch (_) {
    completer.complete(null);
  }
  return completer.future;
}

/// Watches GPS position changes and calls [onUpdate] each time.
/// Returns the watchId so you can cancel with [clearWatch].
int watchPosition(void Function(double lat, double lng) onUpdate) {
  final id = web.window.navigator.geolocation.watchPosition(
    ((web.GeolocationPosition pos) {
      final c = pos.coords;
      onUpdate(c.latitude, c.longitude);
    }).toJS,
  );
  return id;
}

void clearWatch(int id) {
  web.window.navigator.geolocation.clearWatch(id);
}

// ── Map lifecycle ─────────────────────────────────────────────────────────────

JSObject? _getL() => web.window.getProperty<JSObject?>('L'.toJS);

/// Creates a Leaflet map on [elementId], centred at [lat],[lng] with [zoom].
void initMap(String elementId, double lat, double lng, int zoom) {
  final L = _getL();
  if (L == null) return;
  final opts = JSObject();
  opts.setProperty('center'.toJS, [lat.toJS, lng.toJS].toJS);
  opts.setProperty('zoom'.toJS, zoom.toJS);
  final map = L.callMethod<JSObject>('map'.toJS, elementId.toJS, opts);
  // Tile layer (OSM)
  final tileOpts = JSObject();
  tileOpts.setProperty(
    'attribution'.toJS,
    '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'.toJS,
  );
  L
      .callMethod<JSObject>(
        'tileLayer'.toJS,
        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png'.toJS,
        tileOpts,
      )
      .callMethod<JSObject>('addTo'.toJS, map);
  // Store on window for later access
  web.window.setProperty('__lmap_$elementId'.toJS, map);
}

/// Retrieves the stored Leaflet map instance.
JSObject? _map(String id) => web.window.getProperty<JSObject?>('__lmap_$id'.toJS);

/// Adds a click handler to the map. Calls [onTap] with (lat, lng).
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

/// Adds or moves a named marker on the map.
void setMarker(String elementId, String markerId, double lat, double lng, String? popupText) {
  final L = _getL();
  final m = _map(elementId);
  if (L == null || m == null) return;

  final storeKey = '__lmarker_${elementId}_$markerId'.toJS;
  final existing = web.window.getProperty<JSObject?>(storeKey);
  if (existing != null) {
    final ll = JSObject();
    ll.setProperty('lat'.toJS, lat.toJS);
    ll.setProperty('lng'.toJS, lng.toJS);
    existing.callMethod<JSAny>('setLatLng'.toJS, [lat.toJS, lng.toJS].toJS);
  } else {
    final latLng = L.callMethod<JSObject>('latLng'.toJS, lat.toJS, lng.toJS);
    final marker = L.callMethod<JSObject>('marker'.toJS, latLng).callMethod<JSObject>('addTo'.toJS, m);
    if (popupText != null) {
      (marker.callMethod<JSObject>('bindPopup'.toJS, popupText.toJS)).callMethod<JSAny>('openPopup'.toJS);
    }
    web.window.setProperty(storeKey, marker);
  }
}

/// Removes a named marker.
void removeMarker(String elementId, String markerId) {
  final storeKey = '__lmarker_${elementId}_$markerId'.toJS;
  final existing = web.window.getProperty<JSObject?>(storeKey);
  if (existing != null) {
    existing.callMethod<JSAny>('remove'.toJS);
  }
}

/// Draws a polyline route between [points] (list of [lat,lng] pairs).
void drawRoute(String elementId, List<List<double>> points, String color) {
  final L = _getL();
  final m = _map(elementId);
  if (L == null || m == null) return;

  // Remove existing route
  final routeKey = '__lroute_$elementId'.toJS;
  final existing = web.window.getProperty<JSObject?>(routeKey);
  if (existing != null) existing.callMethod<JSAny>('remove'.toJS);

  final jsPoints = points.map((p) => [p[0].toJS, p[1].toJS].toJS).toList().toJS;
  final opts = JSObject();
  opts.setProperty('color'.toJS, color.toJS);
  opts.setProperty('weight'.toJS, 5.toJS);
  opts.setProperty('opacity'.toJS, 0.85.toJS);
  final poly = L.callMethod<JSObject>('polyline'.toJS, jsPoints, opts).callMethod<JSObject>('addTo'.toJS, m);
  web.window.setProperty(routeKey, poly);
  m.callMethod<JSAny>('fitBounds'.toJS, poly.callMethod<JSObject>('getBounds'.toJS));
}

/// Pans the map to [lat],[lng].
void panTo(String elementId, double lat, double lng) {
  final m = _map(elementId);
  if (m == null) return;
  m.callMethod<JSAny>('panTo'.toJS, [lat.toJS, lng.toJS].toJS);
}

/// Returns the current center of the map.
({double lat, double lng})? getMapCenter(String elementId) {
  final m = _map(elementId);
  if (m == null) return null;
  final ll = m.callMethod<JSObject>('getCenter'.toJS);
  final lat = ll.getProperty<JSNumber>('lat'.toJS).toDartDouble;
  final lng = ll.getProperty<JSNumber>('lng'.toJS).toDartDouble;
  return (lat: lat, lng: lng);
}

/// Tells Leaflet that the container size has changed.
void invalidateMapSize(String elementId) {
  final m = _map(elementId);
  if (m == null) return;
  m.callMethod<JSAny>('invalidateSize'.toJS);
}

// ── Reverse Geocoding via Nominatim ──────────────────────────────────────────

Future<String> reverseGeocode(double lat, double lng) async {
  try {
    final url = 'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng';
    final fetchFn = web.window.getProperty<JSFunction>('fetch'.toJS);
    final resp = await (fetchFn.callAsFunction(null, url.toJS) as JSPromise).toDart;
    final respObj = resp as JSObject;
    final jsonFn = respObj.getProperty<JSFunction>('json'.toJS);
    final json = await (jsonFn.callAsFunction(respObj) as JSPromise).toDart;
    final jsonObj = json as JSObject;
    final displayName = jsonObj.getProperty<JSString?>('display_name'.toJS)?.toDart ?? '$lat, $lng';
    return displayName;
  } catch (_) {
    return '$lat, $lng';
  }
}

/// Destroys the Leaflet map instance (for cleanup).
void destroyMap(String elementId) {
  final m = _map(elementId);
  if (m == null) return;
  m.callMethod<JSAny>('remove'.toJS);
}
