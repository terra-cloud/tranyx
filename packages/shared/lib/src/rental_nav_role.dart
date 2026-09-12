enum RentalNavRole {
  publisher,
  subscriber,
  none,
}

/// Resolves whether the current user is a publisher (driver running turn-by-turn navigation),
/// a subscriber (follower tracking the vehicle on map), or none based on rental type and status.
///
/// Rules:
/// - Delivery: When status is 'On the way to Rentee' and rentalType is 'deliver':
///   * Host is [RentalNavRole.publisher]
///   * Rentee is [RentalNavRole.subscriber]
/// - Return: When status is 'Returning':
///   * Rentee is [RentalNavRole.publisher]
///   * Host is [RentalNavRole.subscriber]
/// - In all other states or for unassociated users, returns [RentalNavRole.none].
RentalNavRole resolveRentalNavRole({
  required String currentUserId,
  required String hostId,
  required String renteeId,
  required String status,
  required String rentalType,
}) {
  final normalizedStatus = status.trim().toLowerCase();
  final isDelivery = rentalType.trim().toLowerCase() == 'deliver';

  // 1. Delivery Phase
  if (normalizedStatus == 'on the way to rentee' || normalizedStatus == 'delivering') {
    if (isDelivery) {
      if (currentUserId == hostId) return RentalNavRole.publisher;
      if (currentUserId == renteeId) return RentalNavRole.subscriber;
    }
    return RentalNavRole.none;
  }

  // 2. Return Phase
  if (normalizedStatus == 'returning' ||
      normalizedStatus == 'return' ||
      normalizedStatus == 'arrived at return location') {
    if (currentUserId == renteeId) return RentalNavRole.publisher;
    if (currentUserId == hostId) return RentalNavRole.subscriber;
    return RentalNavRole.none;
  }

  return RentalNavRole.none;
}
