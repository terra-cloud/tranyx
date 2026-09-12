import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:headless_nav_flutter/headless_nav_flutter.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';

/// Full-screen live navigation and vehicle tracking screen for mobile users.
///
/// Enforces directional role resolving:
/// - Host is Publisher ONLY during vehicle delivery (`rentalType == 'deliver' && status == 'On the way to Rentee'`), while Rentee is Subscriber.
/// - Rentee is Publisher during return trip (`status == 'Returning'`), while Host is Subscriber.
/// - In self-pickup (`rentalType != 'deliver'`) or other states, neither is publisher.
class RentalNavigationScreen extends ConsumerWidget {
  final Map<String, dynamic> rentalData;

  const RentalNavigationScreen({
    super.key,
    required this.rentalData,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final currentUid = user?.uid ?? '';

    final hostId = (rentalData['hostId'] ?? '').toString();
    var renteeId = (rentalData['renteeId'] ?? '').toString();
    if (renteeId.isEmpty) {
      renteeId = (rentalData['renterId'] ?? rentalData['userId'] ?? '').toString();
    }
    final status = (rentalData['status'] ?? '').toString();
    final rentalType = (rentalData['rentalType'] ?? 'pickup').toString();
    final rentalId = (rentalData['rentalId'] ?? rentalData['id'] ?? '').toString();
    final channelId = 'rental_$rentalId';

    final role = resolveRentalNavRole(
      currentUserId: currentUid,
      hostId: hostId,
      renteeId: renteeId,
      status: status,
      rentalType: rentalType,
    );

    switch (role) {
      case RentalNavRole.publisher:
        final stops = _buildWaypoints(rentalData, status);
        return Scaffold(
          body: NavigationView(
            channelId: channelId,
            stops: stops,
            travelMode: NavTravelMode.car,
            themeAdaptive: true,
            enableTts: true,
            onClose: () => Navigator.of(context).pop(),
          ),
        );

      case RentalNavRole.subscriber:
        return Scaffold(
          body: FollowerNavigationView(
            channelId: channelId,
            themeAdaptive: true,
            driverPinColor: AppColors.indigo,
            onClose: () => Navigator.of(context).pop(),
          ),
        );

      case RentalNavRole.none:
        final isHost = currentUid == hostId;
        final brand = rentalData['brand'] ?? '';
        final model = rentalData['model'] ?? '';
        return Scaffold(
          appBar: AppBar(
            title: Text('$brand $model Live Tracking'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.indigo.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.navigation_outlined,
                      size: 36,
                      color: AppColors.indigo,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    status == 'Booked' && rentalType != 'deliver'
                        ? 'Self-Pickup Rental'
                        : 'Navigation Inactive',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _getInactiveMessage(status, rentalType, isHost),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Back to Trip Details'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    }
  }

  List<NavWaypoint> _buildWaypoints(Map<String, dynamic> data, String status) {
    final normStatus = status.trim().toLowerCase();
    final isDelivering = normStatus == 'on the way to rentee' || normStatus == 'delivering';
    final isReturning = normStatus == 'returning' || normStatus == 'return' || normStatus == 'arrived at return location';

    if (isDelivering) {
      final destLat = (data['deliveryLat'] as num?)?.toDouble() ??
          (data['dropoffLat'] as num?)?.toDouble() ??
          (data['pickupLat'] as num?)?.toDouble() ??
          14.5995;
      final destLng = (data['deliveryLng'] as num?)?.toDouble() ??
          (data['dropoffLng'] as num?)?.toDouble() ??
          (data['pickupLng'] as num?)?.toDouble() ??
          120.9842;
      final destTitle = (data['deliveryAddress'] as String?) ??
          (data['dropoffAddress'] as String?) ??
          'Rentee Delivery Location';

      var originLat = (data['pickupLat'] as num?)?.toDouble() ??
          (data['hostLat'] as num?)?.toDouble() ??
          (data['currentLat'] as num?)?.toDouble() ??
          (destLat - 0.035);
      var originLng = (data['pickupLng'] as num?)?.toDouble() ??
          (data['hostLng'] as num?)?.toDouble() ??
          (data['currentLng'] as num?)?.toDouble() ??
          (destLng - 0.025);
      final originTitle = (data['pickupAddress'] as String?) ??
          (data['pickupLocation'] as String?) ??
          'Vehicle Departure Point';

      if ((originLat - destLat).abs() < 0.0001 && (originLng - destLng).abs() < 0.0001) {
        originLat = destLat - 0.035;
        originLng = destLng - 0.025;
      }

      return [
        NavWaypoint.fromCoords(
          latitude: originLat,
          longitude: originLng,
          title: originTitle,
        ),
        NavWaypoint.fromCoords(
          latitude: destLat,
          longitude: destLng,
          title: destTitle,
        ),
      ];
    } else if (isReturning) {
      final destLat = (data['pickupLat'] as num?)?.toDouble() ??
          (data['returnLat'] as num?)?.toDouble() ??
          14.5995;
      final destLng = (data['pickupLng'] as num?)?.toDouble() ??
          (data['returnLng'] as num?)?.toDouble() ??
          120.9842;
      final destTitle = (data['pickupAddress'] as String?) ??
          (data['pickupLocation'] as String?) ??
          (data['returnAddress'] as String?) ??
          'Host Return Location';

      var originLat = (data['currentLat'] as num?)?.toDouble() ??
          (data['deliveryLat'] as num?)?.toDouble() ??
          (data['dropoffLat'] as num?)?.toDouble() ??
          (destLat - 0.035);
      var originLng = (data['currentLng'] as num?)?.toDouble() ??
          (data['deliveryLng'] as num?)?.toDouble() ??
          (data['dropoffLng'] as num?)?.toDouble() ??
          (destLng - 0.025);
      final originTitle = (data['currentAddress'] as String?) ??
          (data['deliveryAddress'] as String?) ??
          'Current Location';

      if ((originLat - destLat).abs() < 0.0001 && (originLng - destLng).abs() < 0.0001) {
        originLat = destLat - 0.035;
        originLng = destLng - 0.025;
      }

      return [
        NavWaypoint.fromCoords(
          latitude: originLat,
          longitude: originLng,
          title: originTitle,
        ),
        NavWaypoint.fromCoords(
          latitude: destLat,
          longitude: destLng,
          title: destTitle,
        ),
      ];
    }

    return const [];
  }

  String _getInactiveMessage(String status, String rentalType, bool isHost) {
    if (rentalType != 'deliver' && status == 'Booked') {
      return isHost
          ? 'This rental is designated for self-pickup. The renter will pick up the vehicle at your specified address.'
          : 'This is a self-pickup rental. Head to the host\'s location to inspect and collect the vehicle.';
    }
    if (status == 'Ongoing' || status == 'Active') {
      return 'The vehicle rental is currently active. Live turn-by-turn navigation and GPS follower tracking will activate when the return trip starts.';
    }
    if (status == 'Completed' || status == 'Complete') {
      return 'This vehicle rental has concluded and the vehicle has been safely returned.';
    }
    return 'Turn-by-turn navigation and live telemetry tracking are active only when the vehicle is being delivered by the host or returned by the rentee.';
  }
}
