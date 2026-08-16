class GeolocationResult {
  final double? lat;
  final double? lng;
  final String? error;
  final int? errorCode;
  final bool isSuccess;

  const GeolocationResult.success(double this.lat, double this.lng)
      : error = null,
        errorCode = null,
        isSuccess = true;

  const GeolocationResult.failure(this.error, [this.errorCode])
      : lat = null,
        lng = null,
        isSuccess = false;
}

// Stub for server-side rendering — MapLibre APIs are client-only.
Future<void> ensureMapLibreLoaded() async {}
Future<GeolocationResult> getDetailedCurrentPosition({int timeoutMs = 10000}) async =>
    const GeolocationResult.failure('Not running in browser');
Future<({double lat, double lng})?> getCurrentPosition({int timeoutMs = 10000}) async => null;
int watchPosition(void Function(double lat, double lng) onUpdate) => -1;
void clearWatch(int id) {}
Future<void> initMap(
  String elementId,
  double lat,
  double lng,
  double zoom, {
  bool isDark = true,
  double pitch = 0,
  double bearing = 0,
}) async {}
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
  String color, [
  double? midLat,
  double? midLng,
]) async => null;
void speakText(String text) {}
void panTo(String elementId, double lat, double lng, {double? bearing, double? pitch, double? zoom}) {}
void destroyMap(String elementId) {}
void clearRoute(String elementId) {}
Future<String> reverseGeocode(double lat, double lng) async => '$lat, $lng';
Future<List<Map<String, dynamic>>> searchAddress(String query) async => [];
({double lat, double lng})? getMapCenter(String elementId) => null;
void invalidateMapSize(String elementId) {}
void openOSMNavigation(double destLat, double destLng) {}
void setupMapInteractionListener(
  String elementId,
  void Function() onInteractionStart,
  void Function() onInteractionEnd,
) {}
