// Stub for server-side rendering — Leaflet APIs are client-only.
Future<void> ensureLeafletLoaded() async {}
Future<({double lat, double lng})?> getCurrentPosition() async => null;
int watchPosition(void Function(double lat, double lng) onUpdate) => -1;
void clearWatch(int id) {}
Future<void> initMap(String elementId, double lat, double lng, int zoom, {bool isDark = true}) async {}
void onMapClick(String elementId, void Function(double lat, double lng) onTap) {}
void setMarker(String elementId, String markerId, double lat, double lng, String? popupText) {}
void removeMarker(String elementId, String markerId) {}
void drawRoute(String elementId, List<List<double>> points, String color) {}
Future<Map<String, dynamic>?> drawOSRMRoute(
  String elementId,
  double fromLat,
  double fromLng,
  double toLat,
  double toLng,
  String color,
) async => null;
void speakText(String text) {}
void panTo(String elementId, double lat, double lng) {}
void destroyMap(String elementId) {}
Future<String> reverseGeocode(double lat, double lng) async => '$lat, $lng';
({double lat, double lng})? getMapCenter(String elementId) => null;
void invalidateMapSize(String elementId) {}
void openOSMNavigation(double destLat, double destLng) {}
