import 'package:test/test.dart';
import 'package:tranyx_web/client/utils/guest_rental_browse.dart';

void main() {
  test('guests keep listings that have no public coordinates', () {
    final ordered = orderGuestRentals<Map<String, Object?>>(
      listings: [
        {'id': 'old', 'createdAt': 1},
        {'id': 'new', 'createdAt': 9},
        {'id': 'mid', 'createdAt': 4, 'lat': 14.6, 'lng': 121.0},
      ],
      createdAtMs: (item) => listingCreatedAtMs(item['createdAt']),
      latitude: (item) => item['lat'] as double?,
      longitude: (item) => item['lng'] as double?,
    );
    expect(ordered.map((item) => item['id']), ['new', 'mid', 'old']);
  });

  test('a known browser fix ranks located listings first and still keeps the rest', () {
    final ordered = orderGuestRentals<Map<String, Object?>>(
      listings: [
        {'id': 'far', 'createdAt': 3, 'lat': 10.0, 'lng': 123.0},
        {'id': 'hidden', 'createdAt': 8},
        {'id': 'near', 'createdAt': 2, 'lat': 14.6, 'lng': 121.0},
      ],
      createdAtMs: (item) => listingCreatedAtMs(item['createdAt']),
      latitude: (item) => item['lat'] as double?,
      longitude: (item) => item['lng'] as double?,
      viewerLat: 14.55,
      viewerLng: 121.02,
      viewerLocationKnown: true,
      distanceKm: (lat1, lng1, lat2, lng2) {
        final dLat = (lat1 - lat2).abs();
        final dLng = (lng1 - lng2).abs();
        return dLat + dLng;
      },
    );
    expect(ordered.map((item) => item['id']), ['near', 'far', 'hidden']);
  });
}
