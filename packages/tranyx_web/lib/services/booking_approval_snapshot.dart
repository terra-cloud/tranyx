/// Fields the host-approve screen reads off a booking request.
///
/// [bookingRequest] stores price and parties, and only recently started
/// copying duration and multiplier. Older pending requests omit them.
class BookingApprovalSnapshot {
  final String renteeId;
  final String renteeName;
  final String durationType;
  final int multiplier;

  const BookingApprovalSnapshot({
    required this.renteeId,
    required this.renteeName,
    required this.durationType,
    required this.multiplier,
  });

  factory BookingApprovalSnapshot.fromRequest(Map<dynamic, dynamic> req) {
    final renteeId = (req['renteeId'] ?? req['renterId'])?.toString().trim() ?? '';
    if (renteeId.isEmpty) {
      throw FormatException('Booking request has no renter.');
    }
    final name = (req['renteeName'] ?? req['renterName'])?.toString().trim() ?? '';
    final duration = (req['durationType'] ?? req['rentalDurationType'])?.toString().trim() ?? '';
    final rawMult = req['multiplier'] ?? req['rentalMultiplier'];
    final parsed = rawMult is num ? rawMult.toInt() : int.tryParse('${rawMult ?? ''}');
    return BookingApprovalSnapshot(
      renteeId: renteeId,
      renteeName: name.isEmpty ? 'Renter' : name,
      durationType: duration.isEmpty ? 'daily' : duration,
      multiplier: parsed == null || parsed < 1 ? 1 : parsed,
    );
  }
}
