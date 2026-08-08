import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  void dispose() {
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
                  .watch(realtimeRentalsProvider)
                  .when(
                    data: (rentals) {
                      final active = rentals
                          .where(
                            (r) =>
                                r.renteeId == userProfile.uid &&
                                r.status != 'Available' &&
                                r.status != 'Completed' &&
                                r.status != 'Complete',
                          )
                          .toList();

                      if (active.isEmpty) return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ACTIVE VEHICLE RENTALS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...active.map((act) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.indigo.withValues(alpha: 0.1),
                                border: Border.all(
                                  color: AppColors.indigo.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${act.brand} ${act.model}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          act.status.toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Handover address: ${act.pickupAddress}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: () => _openActiveTripSheet(
                                            act.toMap(),
                                            false,
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.indigo,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text('Open Tracker Map'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Text('Error: $err'),
                  ),
            ] else ...[
              ref
                  .watch(realtimePropertiesProvider)
                  .when(
                    data: (props) {
                      final active = props
                          .where(
                            (p) =>
                                p.renteeId == userProfile.uid &&
                                p.status != 'Available' &&
                                p.status != 'Completed',
                          )
                          .toList();

                      if (active.isEmpty) return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ACTIVE REAL ESTATE LEASES',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...active.map((act) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.1),
                                border: Border.all(
                                  color: Colors.teal.withValues(alpha: 0.3),
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        act.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          act.status.toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Address: ${act.address}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: () => _openActiveTripSheet(
                                            act.toMap(),
                                            true,
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.teal,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text(
                                            'Open Lease Portal',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
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
                          ...pending.map((req) {
                            final reqId = req['id'] as String;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                title: Text('${req["brand"]} ${req["model"]}'),
                                subtitle: Text(
                                  'Duration: ${req["multiplier"]} ${req["durationType"]}(s)',
                                ),
                                trailing: OutlinedButton(
                                  onPressed: () => ref
                                      .read(transitRepositoryProvider)
                                      .cancelBookingRequest(reqId),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ),
                            );
                          }),
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
                          ...pending.map((req) {
                            final reqId = req['id'] as String;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                title: Text(req['title'] ?? 'Property Rental'),
                                subtitle: Text(
                                  'Rent: ₱ ${req["totalCost"]?.toString() ?? "0"}',
                                ),
                                trailing: OutlinedButton(
                                  onPressed: () => ref
                                      .read(transitRepositoryProvider)
                                      .rejectPropertyBookingRequest(
                                        reqId,
                                      ), // Cancels same collection
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ),
                            );
                          }),
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
                        if (r.status != 'Available') return false;
                        if (r.hostId == userProfile.uid) return false;

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
                          final dist = calculateDistance(
                            userLat,
                            userLng,
                            item.pickupLat,
                            item.pickupLng,
                          );
                          return GestureDetector(
                            onTap: () => _openDetailDialog(item.toMap(), false),
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
                                        Text(
                                          '${item.transmission} • ${item.fuelType}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
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
                                      ],
                                    ),
                                  ),
                                ],
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
                        if (p.status != 'Available') return false;
                        if (p.hostId == userProfile.uid) return false;

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
                          final dist = calculateDistance(
                            userLat,
                            userLng,
                            item.latitude,
                            item.longitude,
                          );
                          final photoUrl = item.photoUrls.firstOrNull;
                          return GestureDetector(
                            onTap: () => _openDetailDialog(item.toMap(), true),
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
                                        Text(
                                          '${item.category.label} • ${item.type.label}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
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
                                      ],
                                    ),
                                  ),
                                ],
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
                          .where((r) => r.hostId == userProfile.uid)
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
                                                      color: Colors.purple
                                                          .withValues(
                                                            alpha: 0.15,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      item.status.toUpperCase(),
                                                      style: const TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.purple,
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
                          .where((p) => p.hostId == userProfile.uid)
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
                                                      color: Colors.purple
                                                          .withValues(
                                                            alpha: 0.15,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      item.status.toUpperCase(),
                                                      style: const TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.purple,
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
