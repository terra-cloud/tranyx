import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/utils/geo_helper.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';

// Dialogs & Sheets
import 'package:tranyx_mobile/features/transit/presentation/widgets/listing_detail_dialog.dart';
import 'package:tranyx_mobile/features/transit/presentation/widgets/booking_wizard_sheet.dart';
import 'package:tranyx_mobile/features/transit/presentation/widgets/active_trip_tracker_sheet.dart';
import 'package:tranyx_mobile/features/transit/presentation/widgets/listing_wizard_sheet.dart';
import 'package:tranyx_mobile/features/transit/presentation/widgets/manage_listing_sheet.dart';
import 'package:tranyx_mobile/features/profile/presentation/widgets/history_pane.dart';

class TransitView extends ConsumerStatefulWidget {
  final bool isTablet;

  const TransitView({super.key, required this.isTablet});

  @override
  ConsumerState<TransitView> createState() => _TransitViewState();
}

class _TransitViewState extends ConsumerState<TransitView> {
  final _searchController = TextEditingController();
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildToggleBtn(
    String text,
    IconData icon,
    bool isActive,
    VoidCallback onTap,
    bool isDarkMode,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? (isDarkMode ? AppColors.darkBorder : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive
                  ? (isDarkMode ? Colors.white : AppColors.lightText)
                  : (isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isActive
                    ? (isDarkMode ? Colors.white : AppColors.lightText)
                    : (isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetailDialog(Map<String, dynamic> item, bool isProperty) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ListingDetailDialog(
        item: item,
        isProperty: isProperty,
        onBookTap: () => _openBookingSheet(item, isProperty),
      ),
    );
  }

  void _openBookingSheet(Map<String, dynamic> item, bool isProperty) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          BookingWizardSheet(item: item, isProperty: isProperty),
    );
  }

  void _openActiveTripSheet(Map<String, dynamic> item, bool isProperty) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          ActiveTripTrackerSheet(item: item, isProperty: isProperty),
    );
  }

  void _openManageListingSheet(Map<String, dynamic> item, bool isProperty) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          ManageListingSheet(item: item, isProperty: isProperty),
    );
  }

  void _openListingWizardSheet(bool isProperty) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ListingWizardSheet(isProperty: isProperty),
    );
  }

  Widget _buildPendingRequestCard(
    Map<String, dynamic> req,
    bool isProperty,
    bool isDarkMode,
  ) {
    final reqId = req['id']?.toString() ?? '';

    String title;
    String? photoUrl;
    String address;
    Map<String, dynamic> itemMap;

    if (isProperty) {
      final propId = (req['propertyId'] ?? req['listingId'])?.toString();
      final properties = ref.watch(realtimePropertiesProvider).value ?? [];
      PropertyRental? property;
      if (propId != null && propId.isNotEmpty) {
        for (final p in properties) {
          if (p.id == propId) {
            property = p;
            break;
          }
        }
      }
      title = property?.title ?? req['title'] ?? req['propertyTitle'] ?? 'Property Rental';
      if (property != null && property.photoUrls.isNotEmpty) {
        photoUrl = property.photoUrls.first;
      } else if (req['photoUrl'] != null && req['photoUrl'].toString().isNotEmpty) {
        photoUrl = req['photoUrl'].toString();
      } else if (req['photoUrls'] is List && (req['photoUrls'] as List).isNotEmpty) {
        photoUrl = (req['photoUrls'] as List).first.toString();
      }
      address = property?.address ?? req['address'] ?? req['city'] ?? 'Location on file';
      itemMap = property?.toMap() ?? {
        'id': propId,
        'title': title,
        'address': address,
        'photoUrls': photoUrl != null ? [photoUrl] : <String>[],
        'priceDaily': req['priceDaily'] ?? req['totalCost'],
        'status': 'Pending Approval',
      };
    } else {
      final rentalId = (req['rentalId'] ?? req['listingId'])?.toString();
      final rentals = ref.watch(realtimeRentalsProvider).value ?? [];
      VehicleRental? vehicle;
      if (rentalId != null && rentalId.isNotEmpty) {
        for (final v in rentals) {
          if (v.id == rentalId) {
            vehicle = v;
            break;
          }
        }
      }
      final brand = vehicle?.brand ?? req['brand'] ?? '';
      final model = vehicle?.model ?? req['model'] ?? req['title'] ?? '';
      title = '$brand $model'.trim();
      if (title.isEmpty) title = 'Vehicle Rental';

      photoUrl = vehicle?.frontPhotoUrl ?? req['frontPhotoUrl'] ?? req['photoUrl'];
      address = vehicle?.pickupAddress ?? req['pickupAddress'] ?? 'Pickup location on file';
      itemMap = vehicle?.toMap() ?? {
        'id': rentalId,
        'brand': brand,
        'model': model.isNotEmpty ? model : title,
        'frontPhotoUrl': photoUrl,
        'pickupAddress': address,
        'priceDaily': req['dailyRate'] ?? req['priceDaily'] ?? req['totalCost'],
        'status': 'Pending Approval',
      };
    }

    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      if (val is DateTime) return val;
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is num) return DateTime.fromMillisecondsSinceEpoch(val.toInt());
      try {
        final ms = (val as dynamic).millisecondsSinceEpoch;
        if (ms is int) return DateTime.fromMillisecondsSinceEpoch(ms);
      } catch (_) {}
      try {
        final ms = (val as dynamic).toMillis();
        if (ms is int) return DateTime.fromMillisecondsSinceEpoch(ms);
      } catch (_) {}
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final startDate = parseDate(req['startDate']);
    final endDate = parseDate(req['endDate']);
    final hasDates = startDate != null && endDate != null;
    final dateRangeStr = hasDates
        ? '${DateFormat('MMM dd, yyyy').format(startDate)} – ${DateFormat('MMM dd, yyyy').format(endDate)}'
        : (req['multiplier'] != null && req['durationType'] != null)
            ? '${req['multiplier']} ${req['durationType']}(s)'
            : '';

    final totalCost = req['totalCost'] ?? req['amount'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkCard : Colors.white,
        border: Border.all(
          color: isDarkMode ? AppColors.darkBorder : Colors.grey.shade200,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (!isDarkMode)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openDetailDialog(itemMap, isProperty),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail / Icon
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? Image.network(
                              photoUrl,
                              width: 68,
                              height: 68,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 68,
                                height: 68,
                                color: Colors.purple.withValues(alpha: 0.1),
                                child: Icon(
                                  isProperty
                                      ? Icons.apartment_rounded
                                      : Icons.directions_car_filled_rounded,
                                  color: Colors.purple,
                                  size: 30,
                                ),
                              ),
                            )
                          : Container(
                              width: 68,
                              height: 68,
                              color: Colors.purple.withValues(alpha: 0.1),
                              child: Icon(
                                isProperty
                                    ? Icons.apartment_rounded
                                    : Icons.directions_car_filled_rounded,
                                color: Colors.purple,
                                size: 30,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'AWAITING APPROVAL',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'PENDING',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 13,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  address,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (dateRangeStr.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 12,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  dateRangeStr,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDarkMode
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: isDarkMode
                      ? AppColors.darkBorder.withValues(alpha: 0.5)
                      : Colors.grey.shade100,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ESCROW LOCKED',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '₱$totalCost',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.purple,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _openDetailDialog(itemMap, isProperty),
                          child: const Text(
                            'View Details',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Cancel Request'),
                                content: const Text(
                                  'Are you sure you want to cancel this booking request? Your locked funds will be refunded immediately.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: const Text('Keep Request'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    child: const Text(
                                      'Yes, Cancel',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              try {
                                if (isProperty) {
                                  await ref
                                      .read(transitRepositoryProvider)
                                      .cancelPropertyBookingRequest(reqId);
                                } else {
                                  await ref
                                      .read(transitRepositoryProvider)
                                      .cancelBookingRequest(reqId);
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Booking request cancelled and escrow refunded.',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to cancel request: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            }
                          },
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final transitMode = ref.watch(transitModeProvider);
    final category = ref.watch(activeRentalCategoryProvider);
    final isVehicles = category == 'vehicles';
    final userProfile = ref.watch(userProfileProvider).value;

    if (userProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final double userLat = 14.5995;
    final double userLng = 120.9842;

    if (transitMode == 'history') {
      return HistoryPane(
        onBack: () => ref.read(transitModeProvider.notifier).state = 'rent',
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode switcher: Rent | Host | History
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? AppColors.darkCard
                  : AppColors.lightBorder.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildToggleBtn(
                    "Rent",
                    Icons.search,
                    transitMode == 'rent',
                    () => ref.read(transitModeProvider.notifier).state = 'rent',
                    isDarkMode,
                  ),
                ),
                Expanded(
                  child: _buildToggleBtn(
                    "Host",
                    Icons.house,
                    transitMode == 'host',
                    () => ref.read(transitModeProvider.notifier).state = 'host',
                    isDarkMode,
                  ),
                ),
                Expanded(
                  child: _buildToggleBtn(
                    "History",
                    Icons.history,
                    transitMode == 'history',
                    () => ref.read(transitModeProvider.notifier).state =
                        'history',
                    isDarkMode,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Category switcher: Vehicles vs Real Estate
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? AppColors.darkCard
                  : AppColors.lightBorder.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildToggleBtn(
                    "🚗 Vehicles",
                    Icons.directions_car,
                    isVehicles,
                    () =>
                        ref.read(activeRentalCategoryProvider.notifier).state =
                            'vehicles',
                    isDarkMode,
                  ),
                ),
                Expanded(
                  child: _buildToggleBtn(
                    "🏢 Real Estate",
                    Icons.apartment,
                    !isVehicles,
                    () =>
                        ref.read(activeRentalCategoryProvider.notifier).state =
                            'properties',
                    isDarkMode,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // RENT MODE
          if (transitMode == 'rent') ...[
            // 1. ACTIVE RENTALS / LEASES
            if (isVehicles) ...[
              ref
                  .watch(renterActiveBookingsProvider)
                  .when(
                    data: (bookings) {
                      if (bookings.isEmpty) return const SizedBox.shrink();

                      final ongoing = bookings.where((b) {
                        final st = (b['status'] ?? '').toString().toLowerCase();
                        return st == 'ongoing' || st == 'active' || st == 'on the way to rentee' || st == 'returning';
                      }).toList();

                      final upcoming = bookings.where((b) {
                        final st = (b['status'] ?? '').toString().toLowerCase();
                        final isUpcomingStatus = st == 'booked' || st == 'awaiting signature' || st == 'approved';
                        if (!isUpcomingStatus) return false;
                        final endMs = getEpochMs(b['endDate'] ?? b['returnDate']);
                        final nowMs = DateTime.now().millisecondsSinceEpoch;
                        return endMs == 0 || endMs > nowMs;
                      }).toList();

                      Widget buildRentalCard(Map<String, dynamic> act, bool isOngoingTrip) {
                        final brand = (act['brand'] ?? '').toString().trim();
                        final model = (act['model'] ?? '').toString().trim();
                        final title = '$brand $model'.trim().isNotEmpty ? '$brand $model'.trim() : 'Vehicle Rental';
                        final rawPlate = act['plateNumber']?.toString().trim();
                        final hasPlate = rawPlate != null && rawPlate.isNotEmpty && rawPlate.toLowerCase() != 'null';
                        final plateStr = hasPlate ? ' • $rawPlate' : '';

                        final rawStatus = (act['status'] ?? 'BOOKED').toString();
                        final isSigned = (act['signedAt'] != null && (act['signedAt'] as num) > 0) ||
                            (act['renteeSignatureName'] != null && act['renteeSignatureName'].toString().isNotEmpty && act['renteeSignatureName'].toString() != 'null') ||
                            (act['signatureName'] != null && act['signatureName'].toString().isNotEmpty && act['signatureName'].toString() != 'null') ||
                            (act['signatureHash'] != null && act['signatureHash'].toString().isNotEmpty);

                        final isAwaitingSignature = !isSigned && (
                          rawStatus.toLowerCase() == 'awaiting signature' ||
                          rawStatus.toLowerCase() == 'approved'
                        );
                        final displayStatus = isAwaitingSignature ? 'Awaiting Signature' : rawStatus;
                        final pickupAddress = act['deliveryAddress'] ?? act['pickupAddress'] ?? 'Pickup point';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isOngoingTrip
                                ? Colors.green.withValues(alpha: 0.08)
                                : (isAwaitingSignature
                                    ? Colors.amber.withValues(alpha: 0.08)
                                    : AppColors.indigo.withValues(alpha: 0.08)),
                            border: Border.all(
                              color: isOngoingTrip
                                  ? Colors.green.withValues(alpha: 0.3)
                                  : (isAwaitingSignature
                                      ? Colors.amber.withValues(alpha: 0.4)
                                      : AppColors.indigo.withValues(alpha: 0.3)),
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$title$plateStr',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isOngoingTrip
                                          ? Colors.green.withValues(alpha: 0.15)
                                          : (isAwaitingSignature
                                              ? Colors.amber.withValues(alpha: 0.15)
                                              : Colors.orange.withValues(alpha: 0.15)),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isAwaitingSignature ? 'ACTION REQUIRED • SIGN' : displayStatus.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isOngoingTrip
                                            ? Colors.green
                                            : (isAwaitingSignature ? Colors.amber.shade800 : Colors.orange),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isOngoingTrip
                                    ? 'Current trip handover address: $pickupAddress'
                                    : (isAwaitingSignature
                                        ? 'Host approved your rental! Please review & sign the agreement to activate.'
                                        : 'Scheduled handover address: $pickupAddress'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isAwaitingSignature ? Colors.amber.shade700 : Colors.grey,
                                  fontWeight: isAwaitingSignature ? FontWeight.w500 : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  if (isAwaitingSignature) ...[
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () async {
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Cancel Approved Request?'),
                                              content: const Text(
                                                'Are you sure you want to cancel this approved rental request before signing? Your escrow deposit will be 100% refunded immediately.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(ctx, false),
                                                  child: const Text('Keep Rental'),
                                                ),
                                                TextButton(
                                                  onPressed: () => Navigator.pop(ctx, true),
                                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                                  child: const Text('Cancel Request'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirmed == true) {
                                            try {
                                              await ref
                                                  .read(transitRepositoryProvider)
                                                  .cancelBookingRequest(act['id']?.toString() ?? '');
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('Rental request cancelled and escrow refunded.'),
                                                    backgroundColor: Colors.green,
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Failed to cancel request: $e'),
                                                    backgroundColor: Colors.red,
                                                  ),
                                                );
                                              }
                                            }
                                          }
                                        },
                                        icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                        label: const Text('Cancel', style: TextStyle(color: Colors.red)),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Colors.red),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _openActiveTripSheet(act, false),
                                      icon: Icon(
                                        isOngoingTrip
                                            ? Icons.location_on
                                            : (isAwaitingSignature ? Icons.draw : Icons.route),
                                        size: 16,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isOngoingTrip
                                            ? Colors.green.shade700
                                            : (isAwaitingSignature ? Colors.green.shade700 : AppColors.indigo),
                                        foregroundColor: Colors.white,
                                      ),
                                      label: Text(
                                        isOngoingTrip
                                            ? 'Open Tracker & Telemetry'
                                            : (isAwaitingSignature ? 'Review & Sign Agreement' : 'View Trip Itinerary'),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (ongoing.isNotEmpty) ...[
                            const Text(
                              'ACTIVE VEHICLE RENTALS (IN PROGRESS)',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...ongoing.map((act) => buildRentalCard(act, true)),
                          ],
                          if (upcoming.isNotEmpty) ...[
                            const Text(
                              'UPCOMING RENTAL SCHEDULES',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...upcoming.map((act) => buildRentalCard(act, false)),
                          ],
                        ],
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Text('Error: $err'),
                  ),
            ] else ...[
              ref
                  .watch(propertyRenterActiveBookingsProvider)
                  .when(
                    data: (leases) {
                      if (leases.isEmpty) return const SizedBox.shrink();

                      final ongoingLeases = leases.where((l) {
                        final st = (l['status'] ?? '').toString().toLowerCase();
                        return st == 'ongoing' || st == 'active' || st == 'occupied';
                      }).toList();

                      final upcomingLeases = leases.where((l) {
                        final st = (l['status'] ?? '').toString().toLowerCase();
                        final isUpcomingStatus = st == 'booked' || st == 'awaiting signature' || st == 'approved';
                        if (!isUpcomingStatus) return false;
                        final endMs = getEpochMs(l['endDate'] ?? l['checkOutDate']);
                        final nowMs = DateTime.now().millisecondsSinceEpoch;
                        return endMs == 0 || endMs > nowMs;
                      }).toList();

                      Widget buildLeaseCard(Map<String, dynamic> act, bool isOngoing) {
                        final title = (act['title'] ?? 'Property Lease').toString();
                        final rawStatus = (act['status'] ?? 'BOOKED').toString();
                        final isSigned = (act['signedAt'] != null && (act['signedAt'] as num) > 0) ||
                            (act['renteeSignatureName'] != null && act['renteeSignatureName'].toString().isNotEmpty && act['renteeSignatureName'].toString() != 'null') ||
                            (act['signatureName'] != null && act['signatureName'].toString().isNotEmpty && act['signatureName'].toString() != 'null') ||
                            (act['signatureHash'] != null && act['signatureHash'].toString().isNotEmpty);

                        final isAwaitingSignature = !isSigned && (
                          rawStatus.toLowerCase() == 'awaiting signature' ||
                          rawStatus.toLowerCase() == 'approved'
                        );
                        final displayStatus = isAwaitingSignature ? 'Awaiting Signature' : rawStatus;
                        final address = (act['address'] ?? '').toString();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isOngoing
                                ? Colors.teal.withValues(alpha: 0.08)
                                : (isAwaitingSignature
                                    ? Colors.amber.withValues(alpha: 0.08)
                                    : AppColors.indigo.withValues(alpha: 0.08)),
                            border: Border.all(
                              color: isOngoing
                                  ? Colors.teal.withValues(alpha: 0.3)
                                  : (isAwaitingSignature
                                      ? Colors.amber.withValues(alpha: 0.4)
                                      : AppColors.indigo.withValues(alpha: 0.3)),
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isOngoing
                                          ? Colors.green.withValues(alpha: 0.15)
                                          : (isAwaitingSignature
                                              ? Colors.amber.withValues(alpha: 0.15)
                                              : Colors.orange.withValues(alpha: 0.15)),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isAwaitingSignature ? 'ACTION REQUIRED • SIGN' : displayStatus.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isOngoing
                                            ? Colors.green
                                            : (isAwaitingSignature ? Colors.amber.shade800 : Colors.orange),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isOngoing
                                    ? 'Address: $address'
                                    : (isAwaitingSignature
                                        ? 'Host approved your lease! Please review & sign the agreement to activate.'
                                        : 'Address: $address'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isAwaitingSignature ? Colors.amber.shade700 : Colors.grey,
                                  fontWeight: isAwaitingSignature ? FontWeight.w500 : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  if (isAwaitingSignature) ...[
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () async {
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Cancel Approved Lease?'),
                                              content: const Text(
                                                'Are you sure you want to cancel this approved lease request before signing? Your escrow deposit will be 100% refunded immediately.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(ctx, false),
                                                  child: const Text('Keep Lease'),
                                                ),
                                                TextButton(
                                                  onPressed: () => Navigator.pop(ctx, true),
                                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                                  child: const Text('Cancel Lease'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirmed == true) {
                                            try {
                                              await ref
                                                  .read(transitRepositoryProvider)
                                                  .cancelPropertyBookingRequest(act['id']?.toString() ?? '');
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('Lease request cancelled and escrow refunded.'),
                                                    backgroundColor: Colors.green,
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Failed to cancel request: $e'),
                                                    backgroundColor: Colors.red,
                                                  ),
                                                );
                                              }
                                            }
                                          }
                                        },
                                        icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                        label: const Text('Cancel', style: TextStyle(color: Colors.red)),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Colors.red),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _openActiveTripSheet(act, true),
                                      icon: Icon(
                                        isOngoing
                                            ? Icons.apartment
                                            : (isAwaitingSignature ? Icons.draw : Icons.receipt_long),
                                        size: 16,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isOngoing
                                            ? Colors.teal.shade700
                                            : (isAwaitingSignature ? Colors.green.shade700 : AppColors.indigo),
                                        foregroundColor: Colors.white,
                                      ),
                                      label: Text(
                                        isOngoing
                                            ? 'View Lease Details'
                                            : (isAwaitingSignature ? 'Review & Sign Agreement' : 'View Reservation Itinerary'),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (ongoingLeases.isNotEmpty) ...[
                            const Text(
                              'ACTIVE REAL ESTATE LEASES (CURRENT RESIDENCE)',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...ongoingLeases.map((act) => buildLeaseCard(act, true)),
                          ],
                          if (upcomingLeases.isNotEmpty) ...[
                            const Text(
                              'UPCOMING PROPERTY LEASES & SCHEDULES',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...upcomingLeases.map((act) => buildLeaseCard(act, false)),
                          ],
                        ],
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Text('Error: $err'),
                  ),
            ],

            // 2. PENDING REQUESTS
            if (isVehicles) ...[
              ref
                  .watch(renterPendingRequestsProvider)
                  .when(
                    data: (reqs) {
                      final pending = reqs
                          .where((r) => r['status'] == 'Pending')
                          .toList();
                      if (pending.isEmpty) return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PENDING BOOKINGS (${pending.length})',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...pending.map(
                            (req) => _buildPendingRequestCard(
                              req,
                              false,
                              isDarkMode,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
            ] else ...[
              ref
                  .watch(propertyRenterPendingRequestsProvider)
                  .when(
                    data: (reqs) {
                      final pending = reqs
                          .where((r) => r['status'] == 'Pending')
                          .toList();
                      if (pending.isEmpty) return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PENDING LEASE REQUESTS (${pending.length})',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...pending.map(
                            (req) => _buildPendingRequestCard(
                              req,
                              true,
                              isDarkMode,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
            ],

            // 3. SEARCH & FILTERS
            const Text(
              'MARKETPLACE LISTINGS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: isVehicles
                    ? 'Search brand, model, type...'
                    : 'Search properties, amenities...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onChanged: (val) {
                ref.read(transitSearchQueryProvider.notifier).state = val;
              },
            ),
            const SizedBox(height: 12),

            // Distance filter select
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Distance:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                DropdownButton<double>(
                  value: ref.watch(transitGeofenceRadiusProvider),
                  onChanged: (val) {
                    if (val != null) {
                      ref.read(transitGeofenceRadiusProvider.notifier).state =
                          val;
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 5.0, child: Text('Within 5 km')),
                    DropdownMenuItem(value: 15.0, child: Text('Within 15 km')),
                    DropdownMenuItem(value: 30.0, child: Text('Within 30 km')),
                    DropdownMenuItem(value: 50.0, child: Text('Within 50 km')),
                    DropdownMenuItem(
                      value: 100.0,
                      child: Text('Within 100 km'),
                    ),
                    DropdownMenuItem(
                      value: 9999.0,
                      child: Text('Any Distance'),
                    ),
                  ],
                ),
              ],
            ),

            if (isVehicles) ...[
              // Max Price Vehicles dropdown
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Max Daily Price:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  DropdownButton<double?>(
                    value: ref.watch(transitMaxPriceProvider),
                    onChanged: (val) {
                      ref.read(transitMaxPriceProvider.notifier).state = val;
                    },
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Any Price')),
                      DropdownMenuItem(
                        value: 1500.0,
                        child: Text('Under ₱1,500/day'),
                      ),
                      DropdownMenuItem(
                        value: 3000.0,
                        child: Text('Under ₱3,000/day'),
                      ),
                      DropdownMenuItem(
                        value: 5000.0,
                        child: Text('Under ₱5,000/day'),
                      ),
                      DropdownMenuItem(
                        value: 10000.0,
                        child: Text('Under ₱10,000/day'),
                      ),
                    ],
                  ),
                ],
              ),
            ] else ...[
              // Property category dropdown
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Category:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  DropdownButton<PropertyCategory?>(
                    value: ref.watch(transitSelectedPropertyCategoryProvider),
                    onChanged: (val) {
                      ref
                              .read(
                                transitSelectedPropertyCategoryProvider
                                    .notifier,
                              )
                              .state =
                          val;
                      ref
                              .read(
                                transitSelectedPropertyTypeProvider.notifier,
                              )
                              .state =
                          null;
                    },
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Categories'),
                      ),
                      ...PropertyCategory.values.map(
                        (c) => DropdownMenuItem(value: c, child: Text(c.label)),
                      ),
                    ],
                  ),
                ],
              ),
              // Property type dropdown
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Property Type:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  DropdownButton<PropertyType?>(
                    value: ref.watch(transitSelectedPropertyTypeProvider),
                    onChanged: (val) {
                      ref
                              .read(
                                transitSelectedPropertyTypeProvider.notifier,
                              )
                              .state =
                          val;
                    },
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Types'),
                      ),
                      ...PropertyType.values
                          .where(
                            (t) =>
                                ref.watch(
                                      transitSelectedPropertyCategoryProvider,
                                    ) ==
                                    null ||
                                t.category ==
                                    ref.watch(
                                      transitSelectedPropertyCategoryProvider,
                                    ),
                          )
                          .map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Text(t.label),
                            ),
                          ),
                    ],
                  ),
                ],
              ),
              // Duration Filter dropdown
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Offers Rent Option:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  DropdownButton<String>(
                    value: ref.watch(transitDurationFilterProvider),
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(transitDurationFilterProvider.notifier).state =
                            val;
                      }
                    },
                    items: const [
                      DropdownMenuItem(value: 'any', child: Text('Any Option')),
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(
                        value: 'monthly',
                        child: Text('Monthly'),
                      ),
                      DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                    ],
                  ),
                ],
              ),
              // Max Price Property text input
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Max Budget (₱):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    width: 120,
                    height: 40,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'Any Budget',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onChanged: (val) {
                        final dVal = double.tryParse(val);
                        ref.read(transitMaxPriceProvider.notifier).state = dVal;
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),

            // 4. GRID / LIST OF AVAILABLE
            if (isVehicles) ...[
              ref
                  .watch(realtimeRentalsProvider)
                  .when(
                    data: (rentals) {
                      final sq = ref
                          .watch(transitSearchQueryProvider)
                          .toLowerCase();
                      final maxP = ref.watch(transitMaxPriceProvider);
                      final rad = ref.watch(transitGeofenceRadiusProvider);

                      final filtered = rentals.where((r) {
                        final status = r.status.toLowerCase();
                        if (status == 'inactive' || status == 'unpublished' || status == 'archived' || status == 'deleted' || status == 'not accepting bookings') return false;
                        if (r.isDeleted || !r.acceptingBookings) return false;

                        if (sq.isNotEmpty) {
                          final title = '${r.brand} ${r.model} ${r.type.name}'
                              .toLowerCase();
                          if (!title.contains(sq)) return false;
                        }

                        if (maxP != null && r.priceDaily > maxP) return false;

                        final dist = calculateDistance(
                          userLat,
                          userLng,
                          r.pickupLat,
                          r.pickupLng,
                        );
                        if (rad < 999.0 && dist > rad) return false;

                        return true;
                      }).toList();

                      // Sort closest first
                      filtered.sort((a, b) {
                        final distA = calculateDistance(
                          userLat,
                          userLng,
                          a.pickupLat,
                          a.pickupLng,
                        );
                        final distB = calculateDistance(
                          userLat,
                          userLng,
                          b.pickupLat,
                          b.pickupLng,
                        );
                        return distA.compareTo(distB);
                      });

                      if (filtered.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(40),
                          child: const Center(
                            child: Text(
                              'No vehicles matching search filter options.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final isMyListing = item.hostId == userProfile.uid;
                          final dist = calculateDistance(
                            userLat,
                            userLng,
                            item.pickupLat,
                            item.pickupLng,
                          );
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? AppColors.darkCard
                                  : AppColors.lightCard,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: isDarkMode
                                    ? AppColors.darkBorder
                                    : AppColors.lightBorder,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(24),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                mouseCursor: SystemMouseCursors.click,
                                onTap: () =>
                                    _openDetailDialog(item.toMap(), false),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          width: 80,
                                          height: 80,
                                          color: isDarkMode
                                              ? AppColors.darkBorder
                                              : AppColors.lightBg,
                                          child: (item.frontPhotoUrl.isNotEmpty)
                                              ? Image.network(
                                                  item.frontPhotoUrl,
                                                  fit: BoxFit.cover,
                                                )
                                              : const Icon(
                                                  Icons.directions_car,
                                                  size: 32,
                                                  color: Colors.grey,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${item.brand} ${item.model}',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: isDarkMode
                                                    ? AppColors.darkText
                                                    : AppColors.lightText,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Wrap(
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              spacing: 6,
                                              children: [
                                                Text(
                                                  '${item.transmission} • ${item.fuelType}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                                if (isMyListing)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.purple.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: Colors.purple.withValues(alpha: 0.3),
                                                      ),
                                                    ),
                                                    child: const Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.person,
                                                          size: 10,
                                                          color: Colors.purple,
                                                        ),
                                                        SizedBox(width: 2),
                                                        Text(
                                                          'Your Listing',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                            color: Colors.purple,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                Builder(
                                                  builder: (context) {
                                                    final statusStr = item.status;
                                                    final isRented = statusStr == 'Rented' || statusStr == 'Ongoing' || statusStr == 'Active';
                                                    final endMs = item.endDate?.millisecondsSinceEpoch;
                                                    final nowMs = DateTime.now().millisecondsSinceEpoch;

                                                    if (isRented && endMs != null) {
                                                      if (endMs > nowMs) {
                                                        final diffMins = ((endMs - nowMs) / (60 * 1000)).round();
                                                        if (diffMins <= 60) {
                                                          return Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                            decoration: BoxDecoration(
                                                              color: Colors.green.withValues(alpha: 0.15),
                                                              borderRadius: BorderRadius.circular(6),
                                                            ),
                                                            child: Text(
                                                              'Returns in ${diffMins > 0 ? diffMins : 1}m',
                                                              style: const TextStyle(
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.bold,
                                                                color: Colors.green,
                                                              ),
                                                            ),
                                                          );
                                                        } else if (diffMins <= 1440) {
                                                          final hours = (diffMins / 60).floor();
                                                          final remMins = diffMins % 60;
                                                          return Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                            decoration: BoxDecoration(
                                                              color: Colors.orange.withValues(alpha: 0.15),
                                                              borderRadius: BorderRadius.circular(6),
                                                            ),
                                                            child: Text(
                                                              'Returns in ${hours}h ${remMins}m',
                                                              style: const TextStyle(
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.bold,
                                                                color: Colors.orange,
                                                              ),
                                                            ),
                                                          );
                                                        } else {
                                                          final returnDate = DateTime.fromMillisecondsSinceEpoch(endMs);
                                                          return Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                            decoration: BoxDecoration(
                                                              color: Colors.purple.withValues(alpha: 0.15),
                                                              borderRadius: BorderRadius.circular(6),
                                                            ),
                                                            child: Text(
                                                              'Available ${returnDate.month}/${returnDate.day}',
                                                              style: const TextStyle(
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.bold,
                                                                color: Colors.purple,
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                      } else {
                                                        return Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.amber.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: const Text(
                                                            'Turnaround Pending',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.amber,
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    }
                                                    return const SizedBox.shrink();
                                                  },
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '₱ ${item.priceDaily.toStringAsFixed(0)}/day',
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w900,
                                                        color: AppColors.indigo,
                                                      ),
                                                    ),
                                                    Text(
                                                      '${dist.toStringAsFixed(1)} km away',
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                ElevatedButton(
                                                  onPressed: () => isMyListing
                                                      ? _openManageListingSheet(
                                                          item.toMap(),
                                                          false,
                                                        )
                                                      : _openBookingSheet(
                                                          item.toMap(),
                                                          false,
                                                        ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        AppColors.indigo,
                                                    foregroundColor: Colors.white,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(12),
                                                    ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 14,
                                                          vertical: 8,
                                                        ),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                                  child: Text(
                                                    isMyListing ? 'Manage' : 'Book Now',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Center(child: Text('Error: $err')),
                  ),
            ] else ...[
              ref
                  .watch(realtimePropertiesProvider)
                  .when(
                    data: (props) {
                      final sq = ref
                          .watch(transitSearchQueryProvider)
                          .toLowerCase();
                      final maxP = ref.watch(transitMaxPriceProvider);
                      final rad = ref.watch(transitGeofenceRadiusProvider);
                      final filterCat = ref.watch(
                        transitSelectedPropertyCategoryProvider,
                      );
                      final filterType = ref.watch(
                        transitSelectedPropertyTypeProvider,
                      );
                      final filterDur = ref.watch(
                        transitDurationFilterProvider,
                      );

                      final filtered = props.where((p) {
                        final status = p.status.toLowerCase();
                        if (status == 'inactive' || status == 'unpublished' || status == 'archived' || status == 'deleted' || status == 'not accepting bookings') return false;
                        if (p.isDeleted || !p.acceptingBookings) return false;

                        if (sq.isNotEmpty) {
                          final title =
                              '${p.title} ${p.description} ${p.address}'
                                  .toLowerCase();
                          if (!title.contains(sq)) return false;
                        }

                        if (filterCat != null && p.category != filterCat) {
                          return false;
                        }
                        if (filterType != null && p.type != filterType) {
                          return false;
                        }

                        if (filterDur == 'daily' &&
                            p.priceDaily <= 0 &&
                            p.priceMonthly <= 0) {
                          return false;
                        }
                        if (filterDur == 'weekly' &&
                            p.priceWeekly <= 0 &&
                            p.priceMonthly <= 0) {
                          return false;
                        }
                        if (filterDur == 'monthly' &&
                            p.priceMonthly <= 0 &&
                            p.priceDaily <= 0) {
                          return false;
                        }
                        if (filterDur == 'yearly' && p.priceMonthly <= 0) {
                          return false;
                        }

                        if (maxP != null) {
                          double checkPrice = p.priceMonthly;
                          if (filterDur == 'daily' && p.priceDaily > 0) {
                            checkPrice = p.priceDaily;
                          }
                          if (filterDur == 'weekly' && p.priceWeekly > 0) {
                            checkPrice = p.priceWeekly;
                          }
                          if (checkPrice > maxP) return false;
                        }

                        final dist = calculateDistance(
                          userLat,
                          userLng,
                          p.latitude,
                          p.longitude,
                        );
                        if (rad < 999.0 && dist > rad) return false;

                        return true;
                      }).toList();

                      // Sort closest first
                      filtered.sort((a, b) {
                        final distA = calculateDistance(
                          userLat,
                          userLng,
                          a.latitude,
                          a.longitude,
                        );
                        final distB = calculateDistance(
                          userLat,
                          userLng,
                          b.latitude,
                          b.longitude,
                        );
                        return distA.compareTo(distB);
                      });

                      if (filtered.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(40),
                          child: const Center(
                            child: Text(
                              'No real estate listings matching search filters.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final isMyProperty = item.hostId == userProfile.uid;
                          final dist = calculateDistance(
                            userLat,
                            userLng,
                            item.latitude,
                            item.longitude,
                          );
                          final photoUrl = item.photoUrls.firstOrNull;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? AppColors.darkCard
                                  : AppColors.lightCard,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: isDarkMode
                                    ? AppColors.darkBorder
                                    : AppColors.lightBorder,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(24),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                mouseCursor: SystemMouseCursors.click,
                                onTap: () =>
                                    _openDetailDialog(item.toMap(), true),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          width: 80,
                                          height: 80,
                                          color: isDarkMode
                                              ? AppColors.darkBorder
                                              : AppColors.lightBg,
                                          child:
                                              (photoUrl != null &&
                                                  photoUrl.isNotEmpty)
                                              ? Image.network(
                                                  photoUrl,
                                                  fit: BoxFit.cover,
                                                )
                                              : const Icon(
                                                  Icons.home,
                                                  size: 32,
                                                  color: Colors.grey,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: isDarkMode
                                                    ? AppColors.darkText
                                                    : AppColors.lightText,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Wrap(
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              spacing: 6,
                                              children: [
                                                Text(
                                                  '${item.category.label} • ${item.type.label}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                                if (isMyProperty)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.purple.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: Colors.purple.withValues(alpha: 0.3),
                                                      ),
                                                    ),
                                                    child: const Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.person,
                                                          size: 10,
                                                          color: Colors.purple,
                                                        ),
                                                        SizedBox(width: 2),
                                                        Text(
                                                          'Your Property',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                            color: Colors.purple,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '₱ ${item.priceMonthly.toStringAsFixed(0)}/mo',
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w900,
                                                        color: Colors.teal,
                                                      ),
                                                    ),
                                                    Text(
                                                      '${dist.toStringAsFixed(1)} km away',
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                ElevatedButton(
                                                  onPressed: () => isMyProperty
                                                      ? _openManageListingSheet(
                                                          item.toMap(),
                                                          true,
                                                        )
                                                      : _openBookingSheet(
                                                          item.toMap(),
                                                          true,
                                                        ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.teal,
                                                    foregroundColor: Colors.white,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(12),
                                                    ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 14,
                                                          vertical: 8,
                                                        ),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                                  child: Text(
                                                    isMyProperty ? 'Manage' : 'Rent Now',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Center(child: Text('Error: $err')),
                  ),
            ],
          ] else ...[
            // HOST MODE
            if (isVehicles) ...[
              ref
                  .watch(realtimeRentalsProvider)
                  .when(
                    data: (rentals) {
                      final myGarage = rentals
                          .where((r) => r.hostId == userProfile.uid && r.status.toLowerCase() != 'archived' && r.status.toLowerCase() != 'deleted' && !r.isDeleted)
                          .toList();

                      return Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'MY GARAGE',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () => _openListingWizardSheet(false),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.indigo,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('+ List Vehicle'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (myGarage.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(40),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isDarkMode
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder,
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Column(
                                children: [
                                  Icon(
                                    Icons.directions_car,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'No vehicles listed. Earn while your vehicle is idle!',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: myGarage.length,
                              itemBuilder: (context, index) {
                                final item = myGarage[index];
                                final isNotAccepting = item.status == 'Not Accepting Bookings' || !item.acceptingBookings;
                                return GestureDetector(
                                  onTap: () => _openManageListingSheet(
                                    item.toMap(),
                                    false,
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isDarkMode
                                          ? AppColors.darkCard
                                          : AppColors.lightCard,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: isDarkMode
                                            ? AppColors.darkBorder
                                            : AppColors.lightBorder,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: Container(
                                            width: 80,
                                            height: 80,
                                            color: isDarkMode
                                                ? AppColors.darkBorder
                                                : AppColors.lightBg,
                                            child:
                                                (item.frontPhotoUrl.isNotEmpty)
                                                ? Image.network(
                                                    item.frontPhotoUrl,
                                                    fit: BoxFit.cover,
                                                  )
                                                : const Icon(
                                                    Icons.directions_car,
                                                    size: 32,
                                                    color: Colors.grey,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${item.brand} ${item.model}',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Plate: ${item.plateNumber}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    '₱ ${item.priceDaily.toStringAsFixed(0)}/day',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: AppColors.indigo,
                                                    ),
                                                  ),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isNotAccepting
                                                          ? Colors.amber
                                                              .withValues(
                                                                alpha: 0.15,
                                                              )
                                                          : Colors.purple
                                                              .withValues(
                                                                alpha: 0.15,
                                                              ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      isNotAccepting
                                                          ? 'NOT ACCEPTING BOOKINGS'
                                                          : (item.status == 'Rented'
                                                              ? 'ACTIVE • DATES AVAILABLE'
                                                              : item.status.toUpperCase()),
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        color: isNotAccepting
                                                            ? Colors.amber[800]
                                                            : (item.status == 'Rented'
                                                                ? Colors.orange
                                                                : Colors.purple),
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Center(child: Text('Error: $err')),
                  ),
            ] else ...[
              ref
                  .watch(realtimePropertiesProvider)
                  .when(
                    data: (props) {
                      final myProperties = props
                          .where((p) => p.hostId == userProfile.uid && p.status.toLowerCase() != 'archived' && p.status.toLowerCase() != 'deleted' && !p.isDeleted)
                          .toList();

                      return Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'MY PROPERTIES',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () => _openListingWizardSheet(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('+ List Property'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (myProperties.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(40),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isDarkMode
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder,
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Column(
                                children: [
                                  Icon(
                                    Icons.home,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'No properties listed. Lease your room or lot securely!',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: myProperties.length,
                              itemBuilder: (context, index) {
                                final item = myProperties[index];
                                final isNotAccepting = item.status == 'Not Accepting Bookings' || !item.acceptingBookings;
                                final photoUrl = item.photoUrls.firstOrNull;
                                return GestureDetector(
                                  onTap: () => _openManageListingSheet(
                                    item.toMap(),
                                    true,
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isDarkMode
                                          ? AppColors.darkCard
                                          : AppColors.lightCard,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: isDarkMode
                                            ? AppColors.darkBorder
                                            : AppColors.lightBorder,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: Container(
                                            width: 80,
                                            height: 80,
                                            color: isDarkMode
                                                ? AppColors.darkBorder
                                                : AppColors.lightBg,
                                            child:
                                                (photoUrl != null &&
                                                    photoUrl.isNotEmpty)
                                                ? Image.network(
                                                    photoUrl,
                                                    fit: BoxFit.cover,
                                                  )
                                                : const Icon(
                                                    Icons.home,
                                                    size: 32,
                                                    color: Colors.grey,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${item.category.label} • ${item.type.label}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    '₱ ${item.priceMonthly.toStringAsFixed(0)}/mo',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.teal,
                                                    ),
                                                  ),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isNotAccepting
                                                          ? Colors.amber
                                                              .withValues(
                                                                alpha: 0.15,
                                                              )
                                                          : Colors.purple
                                                              .withValues(
                                                                alpha: 0.15,
                                                              ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      isNotAccepting
                                                          ? 'NOT ACCEPTING BOOKINGS'
                                                          : (item.status == 'Rented'
                                                              ? 'ACTIVE • DATES AVAILABLE'
                                                              : item.status.toUpperCase()),
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        color: isNotAccepting
                                                            ? Colors.amber[800]
                                                            : (item.status == 'Rented'
                                                                ? Colors.orange
                                                                : Colors.purple),
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Center(child: Text('Error: $err')),
                  ),
            ],
          ],
        ],
      ),
    );
  }
}
