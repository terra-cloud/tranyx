/// Guest browse of vehicle and property listings.
///
/// Exact coordinates live on an auth-only private document, so a guest listing
/// often has no latitude. Those listings stay in the list. A browser fix, when
/// one was already acquired, only orders listings that do publish coordinates.
int listingCreatedAtMs(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is DateTime) return value.millisecondsSinceEpoch;
  return 0;
}

List<T> orderGuestRentals<T>({
  required List<T> listings,
  required int Function(T item) createdAtMs,
  required double? Function(T item) latitude,
  required double? Function(T item) longitude,
  double? viewerLat,
  double? viewerLng,
  bool viewerLocationKnown = false,
  double Function(double lat1, double lng1, double lat2, double lng2)? distanceKm,
}) {
  final copy = List<T>.of(listings);
  int byRecent(T a, T b) => createdAtMs(b).compareTo(createdAtMs(a));
  final canRank = viewerLocationKnown && viewerLat != null && viewerLng != null && distanceKm != null;
  if (!canRank) {
    copy.sort(byRecent);
    return copy;
  }

  double? dist(T item) {
    final lat = latitude(item);
    final lng = longitude(item);
    if (lat == null || lng == null) return null;
    if (lat == 0 && lng == 0) return null;
    return distanceKm(viewerLat, viewerLng, lat, lng);
  }

  copy.sort((a, b) {
    final da = dist(a);
    final db = dist(b);
    if (da == null && db == null) return byRecent(a, b);
    if (da == null) return 1;
    if (db == null) return -1;
    final cmp = da.compareTo(db);
    if (cmp != 0) return cmp;
    return byRecent(a, b);
  });
  return copy;
}
