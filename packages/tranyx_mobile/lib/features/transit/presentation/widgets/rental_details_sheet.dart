import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:intl/intl.dart';
import 'package:tranyx_mobile/features/transit/presentation/widgets/active_trip_tracker_sheet.dart';
import 'package:tranyx_mobile/features/transit/presentation/widgets/signature_pad_dialog.dart';

class RentalDetailsSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  final bool isProperty;

  const RentalDetailsSheet({
    super.key,
    required this.item,
    required this.isProperty,
  });

  @override
  ConsumerState<RentalDetailsSheet> createState() => _RentalDetailsSheetState();
}

class _RentalDetailsSheetState extends ConsumerState<RentalDetailsSheet> {
  bool _showFullContract = false;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final data = widget.item;
    final isProp = widget.isProperty;

    // Identifiers
    final rawBookingRef = data['bookingReference'] ?? data['refNumber'] ?? data['id'];
    final bookingRef = rawBookingRef != null
        ? '#${rawBookingRef.toString().substring(0, rawBookingRef.toString().length > 10 ? 10 : rawBookingRef.toString().length).toUpperCase()}'
        : '#RN-TRX';

    // Titles
    final brand = (data['brand'] ?? '').toString().trim();
    final model = (data['model'] ?? '').toString().trim();
    final vehicleTitle = '$brand $model'.trim().isNotEmpty ? '$brand $model'.trim() : 'Vehicle Rental';
    final propTitle = (data['title'] ?? 'Property Lease').toString();
    final title = isProp ? propTitle : vehicleTitle;

    final plate = data['plateNumber']?.toString().trim();
    final hasValidPlate = plate != null && plate.isNotEmpty && plate.toLowerCase() != 'null';

    // Status logic
    final rawStatus = (data['status'] ?? 'Approved').toString();
    final isSigned = (data['signedAt'] != null && (data['signedAt'] as num) > 0) ||
        (data['signatureName'] != null && data['signatureName'].toString().isNotEmpty && data['signatureName'].toString() != 'null') ||
        (data['signatureHash'] != null && data['signatureHash'].toString().isNotEmpty);

    final isAwaitingSignature = !isSigned && (
      rawStatus.toLowerCase() == 'awaiting signature' ||
      rawStatus.toLowerCase() == 'approved'
    );

    final status = isAwaitingSignature ? 'Awaiting Signature' : rawStatus;
    final isOngoing = status == 'Ongoing' || status == 'Active' || status == 'On the way to Rentee' || status == 'Returning';

    // Photos
    final photos = (data['photoUrls'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final primaryPhoto = photos.isNotEmpty && photos.first.isNotEmpty
        ? photos.first
        : (data['imageUrl']?.toString());

    // Financials
    final totalAmount = (data['totalAmount'] as num?)?.toDouble() ??
        (data['amount'] as num?)?.toDouble() ??
        (data['priceDaily'] as num?)?.toDouble() ??
        (data['priceMonthly'] as num?)?.toDouble() ??
        0.0;
    final depositAmount = (data['depositAmount'] as num?)?.toDouble() ??
        (data['securityDeposit'] as num?)?.toDouble() ??
        0.0;
    final dailyRate = (data['priceDaily'] as num?)?.toDouble();
    final monthlyRate = (data['priceMonthly'] as num?)?.toDouble();

    // Schedule
    final startMs = (data['startDate'] as num?)?.toInt();
    final endMs = (data['endDate'] as num?)?.toInt();
    final startDateStr = startMs != null
        ? DateFormat('MMM dd, yyyy • hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(startMs).toLocal())
        : 'Scheduled at booking';
    final endDateStr = endMs != null
        ? DateFormat('MMM dd, yyyy • hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(endMs).toLocal())
        : 'Scheduled return';

    final durationDays = (data['durationDays'] as num?)?.toInt() ?? 1;
    final durationHours = (data['hours'] as num?)?.toInt();
    final durationStr = durationHours != null && durationHours > 0
        ? '$durationHours Hours'
        : (isProp ? '${data['leaseTermMonths'] ?? 1} Months' : '$durationDays Days');

    // Locations
    final pickupLocation = (data['pickupLocation'] ?? data['locationAddress'] ?? data['address'] ?? 'Designated Location').toString();
    final dropoffLocation = (data['dropoffLocation'] ?? pickupLocation).toString();
    final handoverInstructions = (data['handoverInstructions'] ?? data['instructions'] ?? 'Follow standard vehicle handover protocol. Perform physical inspection before departure.').toString();

    // Signature
    final signatureHash = (data['signatureHash'] ?? '0x8f3c7b2a9e1d4a0b5c6e7f8a9b0c1d2e3f4a5b6c').toString();
    final signedAtMs = (data['signedAt'] as num?)?.toInt();
    final signedAtStr = signedAtMs != null
        ? DateFormat('MMM dd, yyyy • hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(signedAtMs).toLocal())
        : 'Pending Signature';
    final signatoryName = (data['signatureName'] ?? 'Verified Rentee').toString();
    final contractTerms = (data['contractTerms'] ?? 'Standard P2P Rental Terms apply. Escrow protection, verification, and return inspection protocol agreed upon booking.').toString();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isProp
                        ? Colors.teal.withValues(alpha: 0.15)
                        : AppColors.indigo.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isProp ? Icons.home_rounded : Icons.directions_car_rounded,
                    color: isProp ? Colors.teal : AppColors.indigo,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              isProp ? 'Property Lease' : 'Rental Booking',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDarkMode ? Colors.white10 : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              bookingRef,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                color: isDarkMode ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Review confirmed schedule, contract & escrow',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Hero / Overview Card
                  _buildHeroCard(
                    title: title,
                    plate: hasValidPlate ? plate : null,
                    primaryPhoto: primaryPhoto,
                    status: status,
                    isOngoing: isOngoing,
                    isAwaitingSignature: isAwaitingSignature,
                    isProp: isProp,
                    isDarkMode: isDarkMode,
                    data: data,
                  ),
                  const SizedBox(height: 16),

                  // 2. Lifecycle Timeline Stepper
                  _buildLifecycleStepper(
                    status: status,
                    isSigned: isSigned,
                    isOngoing: isOngoing,
                    isAwaitingSignature: isAwaitingSignature,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 16),

                  // 3. Schedule & Handover Details
                  _buildScheduleCard(
                    startDateStr: startDateStr,
                    endDateStr: endDateStr,
                    durationStr: durationStr,
                    pickupLocation: pickupLocation,
                    dropoffLocation: dropoffLocation,
                    handoverInstructions: handoverInstructions,
                    isProp: isProp,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 16),

                  // 4. Financials & Escrow Protection
                  _buildFinancialsCard(
                    totalAmount: totalAmount,
                    depositAmount: depositAmount,
                    dailyRate: dailyRate,
                    monthlyRate: monthlyRate,
                    durationStr: durationStr,
                    isProp: isProp,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 16),

                  // 5. Signed Agreement & Cryptography
                  _buildContractCard(
                    isSigned: isSigned,
                    isAwaitingSignature: isAwaitingSignature,
                    signedAtStr: signedAtStr,
                    signatoryName: signatoryName,
                    signatureHash: signatureHash,
                    contractTerms: contractTerms,
                    title: title,
                    isProp: isProp,
                    isDarkMode: isDarkMode,
                  ),
                ],
              ),
            ),
          ),

          // Contextual Action Bottom Bar
          _buildBottomActionBar(
            isAwaitingSignature: isAwaitingSignature,
            isOngoing: isOngoing,
            isProp: isProp,
            data: data,
            title: title,
            contractTerms: contractTerms,
            isDarkMode: isDarkMode,
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard({
    required String title,
    required String? plate,
    required String? primaryPhoto,
    required String status,
    required bool isOngoing,
    required bool isAwaitingSignature,
    required bool isProp,
    required bool isDarkMode,
    required Map<String, dynamic> data,
  }) {
    final statusColor = isOngoing
        ? Colors.green
        : (isAwaitingSignature ? Colors.amber : AppColors.indigo);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF18181B) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 90,
                  height: 70,
                  color: isDarkMode ? Colors.black26 : Colors.grey.shade200,
                  child: primaryPhoto != null && primaryPhoto.isNotEmpty
                      ? Image.network(
                          primaryPhoto,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            isProp ? Icons.home : Icons.directions_car,
                            color: Colors.grey,
                            size: 32,
                          ),
                        )
                      : Icon(
                          isProp ? Icons.home : Icons.directions_car,
                          color: Colors.grey,
                          size: 32,
                        ),
                ),
              ),
              const SizedBox(width: 14),

              // Title & Status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (plate != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Plate: $plate',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: AppColors.indigo,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          // Specs Row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (!isProp) ...[
                _specChip(Icons.local_gas_station_rounded, (data['fuelType'] ?? 'Gasoline').toString(), isDarkMode),
                _specChip(Icons.settings_rounded, (data['transmission'] ?? 'Automatic').toString(), isDarkMode),
                _specChip(Icons.people_rounded, '${data['seats'] ?? 5} Seats', isDarkMode),
              ] else ...[
                _specChip(Icons.hotel_rounded, '${data['bedrooms'] ?? 1} Bed', isDarkMode),
                _specChip(Icons.bathtub_rounded, '${data['bathrooms'] ?? 1} Bath', isDarkMode),
                _specChip(Icons.category_rounded, (data['category'] ?? 'Residential').toString(), isDarkMode),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _specChip(IconData icon, String label, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDarkMode ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: isDarkMode ? Colors.white70 : Colors.black54),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLifecycleStepper({
    required String status,
    required bool isSigned,
    required bool isOngoing,
    required bool isAwaitingSignature,
    required bool isDarkMode,
  }) {
    int currentStep = 2; // Approved
    if (isSigned) currentStep = 4; // Signed & Escrow
    if (isOngoing) currentStep = 5;
    if (status.toLowerCase() == 'completed') currentStep = 6;
    if (isAwaitingSignature) currentStep = 2;

    final steps = ['Requested', 'Approved', 'Signed', 'Escrow Paid', 'Active', 'Completed'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF18181B) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LIFECYCLE TIMELINE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: isDarkMode ? Colors.white54 : Colors.black54,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.indigo.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Stage $currentStep of 6',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.indigo,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Horizontal Stepper
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < steps.length; i++) ...[
                  Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (i + 1) <= currentStep
                              ? AppColors.indigo
                              : (isDarkMode ? Colors.white10 : Colors.grey.shade300),
                        ),
                        child: Center(
                          child: (i + 1) <= currentStep
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDarkMode ? Colors.white54 : Colors.black54,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        steps[i],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: (i + 1) <= currentStep ? FontWeight.bold : FontWeight.normal,
                          color: (i + 1) <= currentStep
                              ? (isDarkMode ? Colors.white : Colors.black87)
                              : (isDarkMode ? Colors.white38 : Colors.black38),
                        ),
                      ),
                    ],
                  ),
                  if (i < steps.length - 1)
                    Container(
                      width: 24,
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
                      color: (i + 1) < currentStep
                          ? AppColors.indigo
                          : (isDarkMode ? Colors.white10 : Colors.grey.shade300),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard({
    required String startDateStr,
    required String endDateStr,
    required String durationStr,
    required String pickupLocation,
    required String dropoffLocation,
    required String handoverInstructions,
    required bool isProp,
    required bool isDarkMode,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF18181B) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isProp ? 'LEASE SCHEDULE & CHECK-IN' : 'RENTAL SCHEDULE & HANDOVER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: isDarkMode ? Colors.white54 : Colors.black54,
            ),
          ),
          const SizedBox(height: 12),

          // Pickup Schedule
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward_rounded, color: Colors.green, size: 14),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isProp ? 'Commencement Date' : 'Pickup & Handover',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    Text(
                      startDateStr,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pickupLocation,
                      style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.white54 : Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ),

          // Return Schedule
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.blue, size: 14),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isProp ? 'Lease Expiration' : 'Scheduled Return & Dropoff',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                    Text(
                      endDateStr,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dropoffLocation,
                      style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.white54 : Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    handoverInstructions,
                    style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.white70 : Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialsCard({
    required double totalAmount,
    required double depositAmount,
    required double? dailyRate,
    required double? monthlyRate,
    required String durationStr,
    required bool isProp,
    required bool isDarkMode,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF18181B) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'FINANCIALS & ESCROW PROTECTION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: isDarkMode ? Colors.white54 : Colors.black54,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_rounded, color: Colors.green, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'Escrow Protected',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _finItem('Rental Rate', dailyRate != null ? '₱${dailyRate.toStringAsFixed(0)}/day' : (monthlyRate != null ? '₱${monthlyRate.toStringAsFixed(0)}/mo' : '-'), isDarkMode),
              _finItem('Duration', durationStr, isDarkMode),
              _finItem('Security Deposit', depositAmount > 0 ? '₱${depositAmount.toStringAsFixed(0)}' : '₱0 (Waived)', isDarkMode, isGreen: true),
              _finItem('Total Amount', '₱${totalAmount.toStringAsFixed(0)}', isDarkMode, isBold: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _finItem(String label, String value, bool isDarkMode, {bool isBold = false, bool isGreen = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: isDarkMode ? Colors.white54 : Colors.black54),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 14 : 12,
            fontWeight: FontWeight.w900,
            color: isGreen
                ? Colors.green
                : (isBold ? AppColors.indigo : (isDarkMode ? Colors.white : Colors.black87)),
          ),
        ),
      ],
    );
  }

  Widget _buildContractCard({
    required bool isSigned,
    required bool isAwaitingSignature,
    required String signedAtStr,
    required String signatoryName,
    required String signatureHash,
    required String contractTerms,
    required String title,
    required bool isProp,
    required bool isDarkMode,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF18181B) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CRYPTOGRAPHIC AGREEMENT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: isDarkMode ? Colors.white54 : Colors.black54,
                ),
              ),
              InkWell(
                onTap: () => setState(() => _showFullContract = !_showFullContract),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _showFullContract ? 'Hide Terms' : 'View Agreement',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.indigo),
                      ),
                      Icon(
                        _showFullContract ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: AppColors.indigo,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSigned
                  ? Colors.green.withValues(alpha: 0.08)
                  : Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSigned
                    ? Colors.green.withValues(alpha: 0.3)
                    : Colors.amber.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isSigned ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                      color: isSigned ? Colors.green : Colors.amber,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isSigned
                            ? 'Digitally Signed & SHA-256 Verified'
                            : 'Awaiting Digital Signature',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSigned ? Colors.green : Colors.amber,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isSigned) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Signed by $signatoryName on $signedAtStr',
                    style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.white70 : Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.black38 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Hash: $signatureHash',
                      style: TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        color: isDarkMode ? Colors.white70 : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (_showFullContract) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.black26 : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDarkMode ? Colors.white10 : Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isProp ? 'Property Lease Terms' : 'Vehicle Rental Terms',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    contractTerms,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomActionBar({
    required bool isAwaitingSignature,
    required bool isOngoing,
    required bool isProp,
    required Map<String, dynamic> data,
    required String title,
    required String contractTerms,
    required bool isDarkMode,
  }) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkCard : Colors.white,
        border: Border(
          top: BorderSide(color: isDarkMode ? Colors.white10 : Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          if (isAwaitingSignature)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (_) => SignaturePadDialog(
                      title: '$title Agreement',
                      terms: contractTerms,
                      onSigned: (signatureName, signatureHash) {
                        // Handled by dialog callback
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.edit_document, size: 18),
                label: const Text('Review & Sign'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            )
          else if (!isProp && isOngoing)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => ActiveTripTrackerSheet(item: data, isProperty: false),
                  );
                },
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Open Live Tracker & GPS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            )
          else
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Close'),
              ),
            ),
        ],
      ),
    );
  }
}
