import 'dart:async';
import 'dart:math' as math;
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

  String? _lastStatus;
  double? _lastTrackerLat;
  double? _lastTrackerLng;
  double? _totalRemainingDistance;
  double? _totalRemainingDuration;

  int _watchId = -1;
  Timer? _broadcastTimer;
  List<Map<String, dynamic>> _routeSteps = [];
  int _currentStepIndex = 0;
  double _distanceToNextStep = 0.0;
  int _lastSpokenStepIndex = -1;
  int _lastSpokenWarningIndex = -1;

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  @override
  void didUpdateComponent(RentalTrackerMapComponent oldWidget) {
    super.didUpdateComponent(oldWidget);
    if (oldWidget.appState.isDark != component.appState.isDark) {
      setMapTheme(_mapId, isDark: component.appState.isDark);
    }
    final newRental = component.appState.selectedRentalData;
    if (newRental != null) {
      final rId = newRental['id'] as String?;
      final r = component.appState.realtimeRentals.firstWhere(
        (element) => element['id'] == rId,
        orElse: () => newRental,
      );
      final status = r['status'] as String? ?? 'Unknown';
      final currentUid = component.appState.userProfile?.uid;
      final isHost = r['hostId'] == currentUid;
      final isRentee = r['renteeId'] == currentUid;
      final isDriver = (isHost && status == 'On the way to Rentee') || (isRentee && status == 'Returning');

      if (isDriver) {
        if (_watchId == -1 && rId != null) {
          _startBroadcasting(rId);
        }
      } else {
        if (_watchId != -1) {
          clearWatch(_watchId);
          _watchId = -1;
          _broadcastTimer?.cancel();
          _broadcastTimer = null;
        }
      }
    }
  }

  @override
  void dispose() {
    _recenterTimer?.cancel();
    _broadcastTimer?.cancel();
    if (_watchId != -1) clearWatch(_watchId);
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
    _updateRoute(r);

    final status = r['status'] as String? ?? 'Unknown';
    final currentUid = component.appState.userProfile?.uid;
    final isHost = r['hostId'] == currentUid;
    final isRentee = r['renteeId'] == currentUid;
    final isDriver = (isHost && status == 'On the way to Rentee') || (isRentee && status == 'Returning');
    if (isDriver && rId != null) {
      _startBroadcasting(rId);
    }

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
    final status = r['status'] as String? ?? 'Unknown';

    setMarker(_mapId, 'vehicle', lat, lng, '🚗 ${r['brand']} ${r['model']} ($status)');

    final pickupLat = (r['pickupLat'] as num?)?.toDouble();
    final pickupLng = (r['pickupLng'] as num?)?.toDouble();
    final deliveryLat = (r['deliveryLat'] as num?)?.toDouble();
    final deliveryLng = (r['deliveryLng'] as num?)?.toDouble();

    if (pickupLat != null) {
      setMarker(_mapId, 'pickup', pickupLat, pickupLng!, '🏠 Host Pickup Location');
    }
    if (deliveryLat != null) {
      setMarker(_mapId, 'delivery', deliveryLat, deliveryLng!, '📍 Renter Delivery Location');
    }

    if (forceRecenter || lat != _lastLat || lng != _lastLng) {
      _lastLat = lat;
      _lastLng = lng;
      if (!_isUserInteracting) {
        panTo(_mapId, lat, lng, zoom: 15.5);
      }
    }
  }

  void _startBroadcasting(String rentalId) {
    _updateDriverLocation(rentalId);
    _broadcastTimer = Timer.periodic(const Duration(seconds: 10), (_) => _updateDriverLocation(rentalId));
    _watchId = watchPosition((lat, lng) {
      if (!mounted) return;
      _updateFirestoreLocation(rentalId, lat, lng);
    });
  }

  Future<void> _updateDriverLocation(String rentalId) async {
    final pos = await getCurrentPosition();
    if (pos != null) {
      _updateFirestoreLocation(rentalId, pos.lat, pos.lng);
    }
  }

  Future<void> _updateFirestoreLocation(String rentalId, double lat, double lng) async {
    try {
      await component.appState.firestore.updateRentalTracking(rentalId, lat, lng);
      if (!mounted) return;
      setState(() {
        _lastTrackerLat = lat;
        _lastTrackerLng = lng;
      });
    } catch (e) {
      print('Error updating rental tracking location: $e');
    }
  }

  double _distanceInMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final phi1 = lat1 * math.pi / 180.0;
    final phi2 = lat2 * math.pi / 180.0;
    final deltaPhi = (lat2 - lat1) * math.pi / 180.0;
    final deltaLambda = (lon2 - lon1) * math.pi / 180.0;

    final a = math.sin(deltaPhi / 2.0) * math.sin(deltaPhi / 2.0) +
        math.cos(phi1) * math.cos(phi2) * math.sin(deltaLambda / 2.0) * math.sin(deltaLambda / 2.0);
    final c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));

    return r * c;
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final lat1Rad = lat1 * math.pi / 180.0;
    final lat2Rad = lat2 * math.pi / 180.0;

    final y = math.sin(dLon) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) - math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);

    final brng = math.atan2(y, x) * 180.0 / math.pi;
    return (brng + 360.0) % 360.0;
  }

  void _updateNavigationMetrics(double myLat, double myLng) {
    if (_routeSteps.isEmpty) return;

    while (_currentStepIndex < _routeSteps.length) {
      final step = _routeSteps[_currentStepIndex];
      final stepLat = (step['lat'] as num).toDouble();
      final stepLng = (step['lng'] as num).toDouble();
      final dist = _distanceInMeters(myLat, myLng, stepLat, stepLng);

      if (dist < 15.0 && _currentStepIndex < _routeSteps.length - 1) {
        _currentStepIndex++;
      } else {
        _distanceToNextStep = dist;
        break;
      }
    }

    if (_currentStepIndex < _routeSteps.length) {
      final currentStep = _routeSteps[_currentStepIndex];
      final instruction = currentStep['instruction'] as String? ?? 'Continue';

      if (_currentStepIndex != _lastSpokenStepIndex) {
        _lastSpokenStepIndex = _currentStepIndex;
        speakText(instruction);
      } else if (_distanceToNextStep <= 50.0 &&
          _distanceToNextStep > 20.0 &&
          _currentStepIndex != _lastSpokenWarningIndex) {
        _lastSpokenWarningIndex = _currentStepIndex;
        speakText("In 50 meters, $instruction");
      }
    }

    double remainingDist = _distanceToNextStep;
    double remainingDur = 0.0;
    if (_currentStepIndex < _routeSteps.length) {
      remainingDur += (_routeSteps[_currentStepIndex]['duration'] as num).toDouble();
    }

    for (int i = _currentStepIndex + 1; i < _routeSteps.length; i++) {
      remainingDist += (_routeSteps[i]['distance'] as num).toDouble();
      remainingDur += (_routeSteps[i]['duration'] as num).toDouble();
    }

    setState(() {
      _totalRemainingDistance = remainingDist;
      _totalRemainingDuration = remainingDur;
    });
  }

  Future<void> _updateRoute(Map<String, dynamic> r) async {
    if (!_mapInitialized) return;

    final status = r['status'] as String? ?? '';
    final pickupLat = (r['pickupLat'] as num?)?.toDouble();
    final pickupLng = (r['pickupLng'] as num?)?.toDouble();
    final deliveryLat = (r['deliveryLat'] as num?)?.toDouble();
    final deliveryLng = (r['deliveryLng'] as num?)?.toDouble();

    final trackerLat = (r['trackingLat'] as num?)?.toDouble();
    final trackerLng = (r['trackingLng'] as num?)?.toDouble();

    double? fromLat;
    double? fromLng;
    double? toLat;
    double? toLng;
    String color = '#6366f1'; // Indigo

    if (status == 'On the way to Rentee') {
      fromLat = trackerLat ?? pickupLat;
      fromLng = trackerLng ?? pickupLng;
      toLat = deliveryLat ?? pickupLat;
      toLng = deliveryLng ?? pickupLng;
      color = '#3b82f6'; // Blue
    } else if (status == 'Returning') {
      fromLat = trackerLat ?? deliveryLat ?? pickupLat;
      fromLng = trackerLng ?? deliveryLng ?? pickupLng;
      toLat = pickupLat;
      toLng = pickupLng;
      color = '#6366f1'; // Indigo
    }

    if (fromLat != null && fromLng != null && toLat != null && toLng != null &&
        (fromLat != toLat || fromLng != toLng)) {
      try {
        final routeData = await drawOSRMRoute(_mapId, fromLat, fromLng, toLat, toLng, color);
        if (routeData != null && mounted) {
          final stepsList = routeData['steps'] as List<dynamic>?;

          setState(() {
            _routeSteps = stepsList?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
            _currentStepIndex = 0;
            _lastSpokenStepIndex = -1;
            _lastSpokenWarningIndex = -1;
          });

          _updateNavigationMetrics(fromLat, fromLng);

          final currentUid = component.appState.userProfile?.uid;
          final isHost = r['hostId'] == currentUid;
          final isRentee = r['renteeId'] == currentUid;
          final isDriver = (isHost && status == 'On the way to Rentee') || (isRentee && status == 'Returning');
          if (isDriver && _routeSteps.isNotEmpty) {
            double? bearing;
            if (_currentStepIndex < _routeSteps.length) {
              final step = _routeSteps[_currentStepIndex];
              bearing = _calculateBearing(fromLat, fromLng, (step['lat'] as num).toDouble(), (step['lng'] as num).toDouble());
            }
            if (!_isUserInteracting) {
              panTo(_mapId, fromLat, fromLng, bearing: bearing ?? 0.0, pitch: 45.0, zoom: 16.5);
            }
          }
        }
      } catch (e) {
        print('Error drawing OSRM route: $e');
      }
    } else {
      if (mounted) {
        setState(() {
          _totalRemainingDistance = null;
          _totalRemainingDuration = null;
        });
      }
      clearRoute(_mapId);
    }
  }

  void _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      final r = component.appState.selectedRentalData;
      if (r == null) return;
      if (newStatus == 'Completed' || newStatus == 'Complete') {
        await component.appState.firestore.completeRental(r['id']);
      } else {
        await component.appState.firestore.updateRentalStatus(r['id'], newStatus);
      }
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
        : (r['pickupAddress'] as String? ?? r['pickupLocation'] as String? ?? 'N/A');

    if (_mapInitialized) {
      _updateMarkersAndRecenter(r);
      final trackingLat = (r['trackingLat'] as num?)?.toDouble();
      final trackingLng = (r['trackingLng'] as num?)?.toDouble();
      if (status != _lastStatus || trackingLat != _lastTrackerLat || trackingLng != _lastTrackerLng) {
        _lastStatus = status;
        _lastTrackerLat = trackingLat;
        _lastTrackerLng = trackingLng;
        Future.microtask(() => _updateRoute(r));
      }
    }

    final isDriver = (isHost && status == 'On the way to Rentee') || (isRentee && status == 'Returning');
    final showNavigationOverlay = _mapInitialized &&
        isDriver &&
        _routeSteps.isNotEmpty &&
        _currentStepIndex < _routeSteps.length;

    final showCancelButton =
        (isRentee && status == 'Booked') || (isHost && (status == 'Booked' || status == 'On the way to Rentee'));

    return div(classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in', [
      div(
        classes:
            'w-full max-w-3xl h-[85vh] rounded-3xl shadow-2xl relative flex flex-col overflow-hidden ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"}',
        [
          // Header
          div(
            classes:
                'absolute top-0 left-0 right-0 z-20 flex items-center justify-between p-4 bg-gradient-to-b from-black/80 to-transparent',
            [
              div([
                h2(classes: 'text-xl font-bold text-white', [Component.text('Live Tracking')]),
                p(classes: 'text-sm text-zinc-300', [Component.text('$brand $model • $status')]),
                p(classes: 'text-xs text-zinc-400 mt-1', [Component.text('$addressLabel: $addressValue')]),
              ]),
              button(
                classes: 'p-2 rounded-full bg-black/40 hover:bg-black/60 text-white transition-colors',
                events: {
                  'click': (e) => component.appState.setState(() {
                    component.appState.showRentalTrackerMap = false;
                    component.appState.selectedRentalData = null;
                  }),
                },
                [lIcon('x', cls: 'w-6 h-6')],
              ),
            ],
          ),

          // Real Map Area using MapContainer
          div(classes: 'flex-1 relative w-full h-full min-h-[300px]', [
            MapContainer(
              id: _mapId,
              classes: 'w-full h-full',
            ),
            if (showNavigationOverlay) _navigationOverlay(isDark),
          ]),

          // Action Card (Bottom)
          div(
            classes:
                'relative z-20 p-6 rounded-t-3xl ${isDark ? "bg-zinc-900" : "bg-white"} shadow-[0_-10px_40px_rgba(0,0,0,0.1)]',
            [
              if (_showConfirmCancel) ...[
                div(classes: 'mb-4 p-4 rounded-2xl bg-red-500/10 border border-red-500/20 text-sm flex flex-col gap-3', [
                  div(classes: 'flex items-center gap-2 text-red-400 font-bold', [
                    lIcon('alert-triangle', cls: 'w-5 h-5 flex-shrink-0'),
                    span([Component.text('Confirm Cancellation')]),
                  ]),
                  p(classes: 'text-zinc-400 text-xs', [
                    Component.text(
                      isRentee
                          ? 'Are you sure you want to cancel this booking? Note that the 3% platform booking fee (₱${((r["totalCost"] as num? ?? 0.0) * 0.03).toStringAsFixed(2)}) is non-refundable.'
                          : 'Are you sure you want to cancel this booking? The renter will be refunded their rental payment.',
                    ),
                  ]),
                  div(classes: 'flex items-center gap-2 mt-1', [
                    button(
                      classes:
                          'px-4 py-2 rounded-xl bg-red-500 text-white font-bold text-xs hover:bg-red-600 transition-colors',
                      events: {'click': (_) => _handleCancelRental(r['id'])},
                      disabled: _isUpdating,
                      [Component.text('Yes, Cancel Booking')],
                    ),
                    button(
                      classes:
                          'px-4 py-2 rounded-xl border border-zinc-700 text-zinc-400 hover:text-white font-bold text-xs transition-colors',
                      events: {'click': (_) => setState(() => _showConfirmCancel = false)},
                      disabled: _isUpdating,
                      [Component.text('No, Keep Booking')],
                    ),
                  ]),
                ]),
              ] else ...[
                div(classes: 'flex items-center justify-between mb-6', [
                  div([
                    p(classes: 'text-xs font-bold tracking-wider uppercase text-purple-500 mb-1', [
                      Component.text('Status'),
                    ]),
                    h3(classes: 'text-2xl font-black', [Component.text(status)]),
                  ]),
                  if (_isUpdating) lIcon('loader', cls: 'w-6 h-6 animate-spin text-purple-500'),
                ]),

                // Address details card
                div(classes: 'mb-6 p-4 rounded-2xl bg-zinc-800/30 border border-zinc-800 text-xs flex flex-col gap-2', [
                  div(classes: 'flex flex-col gap-1', [
                    span(classes: 'font-bold text-purple-400 uppercase tracking-wider text-[10px]', [
                      Component.text(addressLabel),
                    ]),
                    span(classes: 'text-sm font-semibold', [Component.text(addressValue)]),
                  ]),
                  if (_totalRemainingDistance != null && _totalRemainingDuration != null) ...[
                    div(classes: 'h-px bg-zinc-800/80 my-1', []),
                    div(classes: 'flex items-center gap-6 text-xs text-zinc-400 font-semibold', [
                      div(classes: 'flex items-center gap-1.5', [
                        lIcon('clock', cls: 'w-4 h-4 text-emerald-400'),
                        span([Component.text('${(_totalRemainingDuration! / 60).round()} min')]),
                      ]),
                      div(classes: 'flex items-center gap-1.5', [
                        lIcon('map-pin', cls: 'w-4 h-4 text-rose-400'),
                        span([
                          Component.text(_totalRemainingDistance! >= 1000
                              ? '${(_totalRemainingDistance! / 1000).toStringAsFixed(1)} km remaining'
                              : '${_totalRemainingDistance!.toStringAsFixed(0)} m remaining')
                        ]),
                      ]),
                    ]),
                  ],
                ]),

                // Progress Bar
                div(classes: 'w-full h-2 bg-zinc-800 rounded-full mb-6 overflow-hidden', [
                  div(
                    classes: 'h-full bg-purple-500 transition-all duration-1000',
                    attributes: {'style': 'width: ${_getProgressWidth(status)}%'},
                    [],
                  ),
                ]),

                // Action Buttons based on Status
                div(classes: 'flex items-center gap-3', [
                  if (isHost && status == 'Booked')
                    button(
                      classes:
                          'flex-1 py-3 rounded-xl font-bold text-white bg-purple-600 hover:bg-purple-700 transition-colors',
                      events: {'click': (_) => _updateStatus('On the way to Rentee')},
                      [Component.text(rentalType == 'deliver' ? 'Start Delivery (On the way)' : 'Start Rental')],
                    ),

                  if (isHost && status == 'On the way to Rentee')
                    button(
                      classes:
                          'flex-1 py-3 rounded-xl font-bold text-white bg-green-600 hover:bg-green-700 transition-colors',
                      events: {'click': (_) => _updateStatus('Ongoing')},
                      [Component.text('Handed Over (Ongoing)')],
                    ),

                  if (isRentee && status == 'Ongoing') ...[
                    button(
                      classes:
                          'flex-1 py-3 rounded-xl font-bold text-white bg-blue-600 hover:bg-blue-700 transition-colors',
                      events: {'click': (_) => _updateStatus('Returning')},
                      [Component.text('Start Return Trip')],
                    ),
                    button(
                      classes:
                          'py-3 px-4 rounded-xl font-bold text-purple-400 bg-purple-500/10 hover:bg-purple-500/20 transition-colors',
                      events: {
                        'click': (_) =>
                            component.appState.setState(() => component.appState.showExtendRentalModal = true),
                      },
                      [Component.text('Extend')],
                    ),
                  ],

                  if (isHost && status == 'Returning')
                    button(
                      classes:
                          'flex-1 py-3 rounded-xl font-bold text-white bg-green-600 hover:bg-green-700 transition-colors',
                      events: {'click': (_) => _updateStatus('Complete')},
                      [Component.text('Confirm Vehicle Returned')],
                    ),

                  if (status == 'Complete')
                    div(
                      classes:
                          'flex-1 p-3 rounded-xl text-center bg-green-500/10 border border-green-500/20 text-green-500 font-bold',
                      [Component.text('Rental Completed')],
                    ),

                  if (showCancelButton)
                    button(
                      classes:
                          'px-4 py-3 rounded-xl font-bold text-red-500 border border-red-500/20 hover:bg-red-500/10 transition-all flex-shrink-0',
                      events: {'click': (_) => setState(() => _showConfirmCancel = true)},
                      [
                        lIcon('trash-2', cls: 'w-5 h-5'),
                      ],
                    ),
                ]),
              ],
            ],
          ),
        ],
      ),
    ]);
  }

  int _getProgressWidth(String status) {
    switch (status) {
      case 'Available':
        return 0;
      case 'Booked':
        return 25;
      case 'On the way to Rentee':
        return 50;
      case 'Ongoing':
        return 75;
      case 'Returning':
        return 90;
      case 'Complete':
        return 100;
      default:
        return 0;
    }
  }

  String _maneuverIcon(String? modifier, String? type) {
    if (type == 'arrive') return 'check-circle';
    if (type == 'depart') return 'navigation';
    if (modifier == null) return 'navigation';
    if (modifier.contains('left')) return 'arrow-left';
    if (modifier.contains('right')) return 'arrow-right';
    if (modifier.contains('uturn')) return 'rotate-ccw';
    return 'arrow-up';
  }

  Component _navigationOverlay(bool isDark) {
    if (_routeSteps.isEmpty || _currentStepIndex >= _routeSteps.length) return div([]);
    final step = _routeSteps[_currentStepIndex];
    final instruction = step['instruction'] as String? ?? 'Continue';
    final mod = step['modifier'] as String?;
    final type = step['type'] as String?;
    final iconName = _maneuverIcon(mod, type);

    // Format remaining distance
    String distStr;
    if (_distanceToNextStep >= 1000) {
      distStr = '${(_distanceToNextStep / 1000).toStringAsFixed(1)} km';
    } else {
      distStr = '${_distanceToNextStep.toStringAsFixed(0)} m';
    }

    // Format total remaining distance
    String totalDistStr;
    final rDist = _totalRemainingDistance ?? 0.0;
    if (rDist >= 1000) {
      totalDistStr = '${(rDist / 1000).toStringAsFixed(1)} km';
    } else {
      totalDistStr = '${rDist.toStringAsFixed(0)} m';
    }

    // Format total remaining duration
    String durationStr;
    final rDur = _totalRemainingDuration ?? 0.0;
    final minutes = (rDur / 60).round();
    if (minutes <= 0) {
      durationStr = 'Under 1 min';
    } else {
      durationStr = '$minutes min';
    }

    return div(
      classes:
          'absolute top-20 left-4 right-4 z-[400] p-4 rounded-2xl backdrop-blur-md border shadow-xl flex flex-col gap-3 pointer-events-auto '
          '${isDark ? "bg-zinc-900/90 border-zinc-700/60 text-white" : "bg-white/90 border-zinc-200 text-zinc-900"}',
      [
        // Upper row: maneuver and next turn distance
        div(classes: 'flex items-center gap-3.5', [
          div(
            classes:
                'w-10 h-10 rounded-xl bg-indigo-500 flex items-center justify-center flex-shrink-0 text-white shadow-lg shadow-indigo-500/20',
            [
              lIcon(iconName, cls: 'w-5 h-5'),
            ],
          ),
          div(classes: 'flex-1 min-w-0', [
            p(classes: 'text-[10px] font-black uppercase tracking-wider text-indigo-400 mb-0.5', [
              Component.text('Next Step ($distStr)'),
            ]),
            p(classes: 'text-sm font-bold truncate leading-tight', [
              Component.text(instruction),
            ]),
          ]),
        ]),

        // Divider
        div(classes: 'h-px w-full ${isDark ? "bg-zinc-800" : "bg-zinc-100"}', []),

        // Bottom row: overall remaining distance and time
        div(
          classes:
              'flex items-center justify-between text-xs font-semibold ${isDark ? "text-zinc-400" : "text-zinc-500"}',
          [
            div(classes: 'flex items-center gap-1.5', [
              lIcon('clock', cls: 'w-3.5 h-3.5 text-emerald-400'),
              span([Component.text(durationStr)]),
            ]),
            div(classes: 'flex items-center gap-1.5', [
              lIcon('map-pin', cls: 'w-3.5 h-3.5 text-rose-400'),
              span([Component.text('$totalDistStr remaining')]),
            ]),
          ],
        ),
      ],
    );
  }
}
