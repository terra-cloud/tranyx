import 'dart:math' as math;

/// Calculates the distance between two coordinates (latitude/longitude) in kilometers
/// using the Haversine formula. Returns 0.0 if any coordinates are invalid.
double calculateDistance(double? lat1, double? lon1, double? lat2, double? lon2) {
  if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return 0.0;
  if (lat1 == 0.0 && lon1 == 0.0) return 0.0;
  if (lat2 == 0.0 && lon2 == 0.0) return 0.0;

  const p = 0.017453292519943295; // math.pi / 180
  final a = 0.5 -
      math.cos((lat2 - lat1) * p) / 2 +
      math.cos(lat1 * p) *
          math.cos(lat2 * p) *
          (1 - math.cos((lon2 - lon1) * p)) /
          2;
  return 12742 * math.asin(math.sqrt(a)); // 2 * R; R = 6371 km
}
