/// Guest-visible listing summary. Exact address and coordinates are not on the public document.
const String kPublicAddressMask = 'Brgy. *****, ****';

const Set<String> kExactListingLocationKeys = {
  'address',
  'landmark',
  'location',
  'pickupAddress',
  'pickupLat',
  'pickupLng',
  'destinationAddress',
  'destinationLat',
  'destinationLng',
  'latitude',
  'longitude',
  'lat',
  'lng',
  'nyxianLat',
  'nyxianLng',
  'currentLocationLat',
  'currentLocationLng',
  'trackingLat',
  'trackingLng',
  'routeHistory',
};

class ListingLocationSplit {
  final Map<String, dynamic> publicFields;
  final Map<String, dynamic> privateFields;
  const ListingLocationSplit(this.publicFields, this.privateFields);
}

ListingLocationSplit splitListingLocation(Map data) {
  final publicFields = Map<String, dynamic>.from(data);
  final privateFields = <String, dynamic>{};
  for (final key in kExactListingLocationKeys) {
    if (!publicFields.containsKey(key)) continue;
    final value = publicFields.remove(key);
    if (value != null) privateFields[key] = value;
  }
  const addressKeys = {'address', 'landmark', 'location', 'pickupAddress', 'destinationAddress'};
  if (privateFields.keys.any(addressKeys.contains)) {
    publicFields['addressPublic'] = kPublicAddressMask;
  }
  return ListingLocationSplit(publicFields, privateFields);
}

bool viewerIsSignedIn(String? uid) => uid != null && uid.isNotEmpty;

/// Guests always see the masked barangay summary. Signed-in viewers see the exact address.
String listingAddressForViewer(Map doc, {required bool signedIn}) {
  if (!signedIn) return kPublicAddressMask;
  for (final key in ['address', 'pickupAddress', 'location']) {
    final value = doc[key];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return doc['addressPublic'] as String? ?? kPublicAddressMask;
}

bool listingMapAllowed({required bool signedIn}) => signedIn;
