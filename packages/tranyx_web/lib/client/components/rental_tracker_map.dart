import 'dart:async';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../services/map_interop.dart';
import '../../components/map_container.dart';

class RentalTrackerMapComponent extends StatefulComponent {
  final TranyxAppState appState;
  const RentalTrackerMapComponent({required this.appState, super.key});

  @override
  State<RentalTrackerMapComponent> createState() => _RentalTrackerMapState();
}

class _RentalTrackerMapState extends State<RentalTrackerMapComponent> {
  static const _mapId = 'tracker-map';
  bool _isUpdating = false;
  bool _mapInitialized = false;
  Timer? _recenterTimer;
  bool _isUserInteracting = false;
  double? _lastLat;
  double? _lastLng;
  bool _showConfirmCancel = false;

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  @override
  void dispose() {
    _recenterTimer?.cancel();
    destroyMap(_mapId);
    super.dispose();
  }

  Future<void> _initMap() async {
    await ensureMapLibreLoaded();
    if (!mounted) return;

    final rId = component.appState.selectedRentalData?['id'] as String?;
    final r = component.appState.realtimeRentals.firstWhere(
      (element) => element['id'] == rId,
      orElse: () => component.appState.selectedRentalData!,
    );
    final lat = (r['trackingLat'] as num?)?.toDouble() ?? (r['pickupLat'] as num?)?.toDouble() ?? 14.5995;
    final lng = (r['trackingLng'] as num?)?.toDouble() ?? (r['pickupLng'] as num?)?.toDouble() ?? 120.9842;

    await initMap(_mapId, lat, lng, 15.5, isDark: component.appState.isDark);
    _mapInitialized = true;

    _updateMarkersAndRecenter(r, forceRecenter: true);

    setupMapInteractionListener(
      _mapId,
      () {
        _isUserInteracting = true;
        _recenterTimer?.cancel();
      },
      () {
        _recenterTimer?.cancel();
        _recenterTimer = Timer(const Duration(seconds: 5), () {
          _isUserInteracting = false;
          final currentRId = component.appState.selectedRentalData?['id'] as String?;
          if (currentRId != null) {
            final currentR = component.appState.realtimeRentals.firstWhere(
              (element) => element['id'] == currentRId,
              orElse: () => component.appState.selectedRentalData!,
            );
            _updateMarkersAndRecenter(currentR, forceRecenter: true);
          }
        });
      },
    );
  }

  void _updateMarkersAndRecenter(Map<String, dynamic> r, {bool forceRecenter = false}) {
    if (!_mapInitialized) return;
    final lat = (r['trackingLat'] as num?)?.toDouble() ?? (r['pickupLat'] as num?)?.toDouble() ?? 14.5995;
    final lng = (r['trackingLng'] as num?)?.toDouble() ?? (r['pickupLng'] as num?)?.toDouble() ?? 120.9842;
    
    setMarker(_mapId, 'vehicle', lat, lng, '🚗 ${r['brand']} ${r['model']} (${r['status']})');
    
    if (forceRecenter || lat != _lastLat || lng != _lastLng) {
      _lastLat = lat;
      _lastLng = lng;
      if (!_isUserInteracting) {
        panTo(_mapId, lat, lng, zoom: 15.5);
      }
    }
  }

  void _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      final r = component.appState.selectedRentalData;
      if (r == null) return;
      await component.appState.firestore.updateRentalStatus(r['id'], newStatus);
    } catch (e) {
      print('Error updating rental status: $e');
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  void _handleCancelRental(String rentalId) async {
    setState(() => _isUpdating = true);
    try {
      await component.appState.firestore.cancelRental(rentalId);
      component.appState.showAppToast('Booking Cancelled', 'The booking was successfully cancelled.');
      component.appState.setState(() {
        component.appState.showRentalTrackerMap = false;
        component.appState.selectedRentalData = null;
      });
    } catch (e) {
      print('Error cancelling rental: $e');
      component.appState.showAppToast('Error', 'Failed to cancel booking: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
          _showConfirmCancel = false;
        });
      }
    }
  }

  @override
  Component build(BuildContext context) {
    if (!component.appState.showRentalTrackerMap || component.appState.selectedRentalData == null) {
      return div([]);
    }

    final isDark = component.appState.isDark;
    final rId = component.appState.selectedRentalData?['id'] as String?;
    final r = component.appState.realtimeRentals.firstWhere(
      (element) => element['id'] == rId,
      orElse: () => component.appState.selectedRentalData!,
    );
    final currentUid = component.appState.userProfile?.uid;
    final isHost = r['hostId'] == currentUid;
    final isRentee = r['renteeId'] == currentUid;
    
    final status = r['status'] as String? ?? 'Unknown';
    final model = r['model'] ?? 'Unknown';
    final brand = r['brand'] ?? 'Unknown';
    final rentalType = r['rentalType'] as String? ?? 'pickup';
    final addressLabel = rentalType == 'deliver' ? 'Delivery Address' : 'Pickup Location';
    final addressValue = rentalType == 'deliver'
        ? (r['deliveryAddress'] as String? ?? 'N/A')
        : (r['pickupLocation'] as String? ?? 'N/A');

    if (_mapInitialized) {
      _updateMarkersAndRecenter(r);
    }

    final showCancelButton = (isRentee && status == 'Booked') ||
                             (isHost && (status == 'Booked' || status == 'On the way to Rentee'));

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-3xl h-[85vh] rounded-3xl shadow-2xl relative flex flex-col overflow-hidden ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"}',
          [
            // Header
            div(classes: 'absolute top-0 left-0 right-0 z-20 flex items-center justify-between p-4 bg-gradient-to-b from-black/80 to-transparent', [
              div([
                h2(classes: 'text-xl font-bold text-white', [Component.text('Live Tracking')]),
                p(classes: 'text-sm text-zinc-300', [Component.text('$brand $model • $status')]),
                p(classes: 'text-xs text-zinc-400 mt-1', [Component.text('$addressLabel: $addressValue')]),
              ]),
              button(
                classes: 'p-2 rounded-full bg-black/40 hover:bg-black/60 text-white transition-colors',
                events: {'click': (e) => component.appState.setState(() {
                  component.appState.showRentalTrackerMap = false;
                  component.appState.selectedRentalData = null;
                })},
                [lIcon('x', cls: 'w-6 h-6')],
              ),
            ]),

            // Real Map Area using MapContainer
            div(classes: 'flex-1 relative w-full h-full min-h-[300px]', [
              MapContainer(
                id: _mapId,
                classes: 'w-full h-full',
              ),
            ]),

            // Action Card (Bottom)
            div(classes: 'relative z-20 p-6 rounded-t-3xl ${isDark ? "bg-zinc-900" : "bg-white"} shadow-[0_-10px_40px_rgba(0,0,0,0.1)]', [
              if (_showConfirmCancel) ...[
                div(classes: 'mb-4 p-4 rounded-2xl bg-red-500/10 border border-red-500/20 text-sm flex flex-col gap-3', [
                  div(classes: 'flex items-center gap-2 text-red-400 font-bold', [
                    lIcon('alert-triangle', cls: 'w-5 h-5 flex-shrink-0'),
                    span([Component.text('Confirm Cancellation')]),
                  ]),
                  p(classes: 'text-zinc-400 text-xs', [
                    Component.text(isRentee
                        ? 'Are you sure you want to cancel this booking? Note that the 3% platform booking fee (₱${((r["totalCost"] as num? ?? 0.0) * 0.03).toStringAsFixed(2)}) is non-refundable.'
                        : 'Are you sure you want to cancel this booking? The renter will be refunded their rental payment.')
                  ]),
                  div(classes: 'flex items-center gap-2 mt-1', [
                    button(
                      classes: 'px-4 py-2 rounded-xl bg-red-500 text-white font-bold text-xs hover:bg-red-600 transition-colors',
                      events: {'click': (_) => _handleCancelRental(r['id'])},
                      disabled: _isUpdating,
                      [Component.text('Yes, Cancel Booking')],
                    ),
                    button(
                      classes: 'px-4 py-2 rounded-xl border border-zinc-700 text-zinc-400 hover:text-white font-bold text-xs transition-colors',
                      events: {'click': (_) => setState(() => _showConfirmCancel = false)},
                      disabled: _isUpdating,
                      [Component.text('No, Keep Booking')],
                    ),
                  ]),
                ])
              ] else ...[
                div(classes: 'flex items-center justify-between mb-6', [
                  div([
                    p(classes: 'text-xs font-bold tracking-wider uppercase text-purple-500 mb-1', [Component.text('Status')]),
                    h3(classes: 'text-2xl font-black', [Component.text(status)]),
                  ]),
                  if (_isUpdating)
                    lIcon('loader', cls: 'w-6 h-6 animate-spin text-purple-500'),
                ]),
                
                // Address details card
                div(classes: 'mb-6 p-4 rounded-2xl bg-zinc-800/30 border border-zinc-800 text-xs flex flex-col gap-1', [
                  span(classes: 'font-bold text-purple-400 uppercase tracking-wider text-[10px]', [Component.text(addressLabel)]),
                  span(classes: 'text-sm font-semibold', [Component.text(addressValue)]),
                ]),
                
                // Progress Bar
                div(classes: 'w-full h-2 bg-zinc-800 rounded-full mb-6 overflow-hidden', [
                  div(classes: 'h-full bg-purple-500 transition-all duration-1000', attributes: {
                    'style': 'width: ${_getProgressWidth(status)}%'
                  }, [])
                ]),

                // Action Buttons based on Status
                div(classes: 'flex items-center gap-3', [
                  if (isHost && status == 'Booked')
                    button(
                      classes: 'flex-1 py-3 rounded-xl font-bold text-white bg-purple-600 hover:bg-purple-700 transition-colors',
                      events: {'click': (_) => _updateStatus('On the way to Rentee')},
                      [Component.text(rentalType == 'deliver' ? 'Start Delivery (On the way)' : 'Start Rental')]
                    ),
                    
                  if (isHost && status == 'On the way to Rentee')
                    button(
                      classes: 'flex-1 py-3 rounded-xl font-bold text-white bg-green-600 hover:bg-green-700 transition-colors',
                      events: {'click': (_) => _updateStatus('Ongoing')},
                      [Component.text('Handed Over (Ongoing)')]
                    ),
                    
                  if (isRentee && status == 'Ongoing') ...[
                    button(
                      classes: 'flex-1 py-3 rounded-xl font-bold text-white bg-blue-600 hover:bg-blue-700 transition-colors',
                      events: {'click': (_) => _updateStatus('Returning')},
                      [Component.text('Start Return Trip')]
                    ),
                    button(
                      classes: 'py-3 px-4 rounded-xl font-bold text-purple-400 bg-purple-500/10 hover:bg-purple-500/20 transition-colors',
                      events: {'click': (_) => component.appState.setState(() => component.appState.showExtendRentalModal = true)},
                      [Component.text('Extend')]
                    ),
                  ],
                  
                  if (isHost && status == 'Returning')
                    button(
                      classes: 'flex-1 py-3 rounded-xl font-bold text-white bg-green-600 hover:bg-green-700 transition-colors',
                      events: {'click': (_) => _updateStatus('Complete')},
                      [Component.text('Confirm Vehicle Returned')]
                    ),
                    
                  if (status == 'Complete')
                    div(classes: 'flex-1 p-3 rounded-xl text-center bg-green-500/10 border border-green-500/20 text-green-500 font-bold', [
                      Component.text('Rental Completed')
                    ]),

                  if (showCancelButton)
                    button(
                      classes: 'px-4 py-3 rounded-xl font-bold text-red-500 border border-red-500/20 hover:bg-red-500/10 transition-all flex-shrink-0',
                      events: {'click': (_) => setState(() => _showConfirmCancel = true)},
                      [
                        lIcon('trash-2', cls: 'w-5 h-5'),
                      ],
                    ),
                ]),
              ]
            ]),
          ]
        )
      ]
    );
  }

  int _getProgressWidth(String status) {
    switch (status) {
      case 'Available': return 0;
      case 'Booked': return 25;
      case 'On the way to Rentee': return 50;
      case 'Ongoing': return 75;
      case 'Returning': return 90;
      case 'Complete': return 100;
      default: return 0;
    }
  }
}
