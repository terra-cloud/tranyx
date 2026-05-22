import 'dart:async';
import 'dart:math' as math;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:shared/shared.dart';
import '../services/map_interop.dart';
import 'map_container.dart';
import '../services/firebase_service.dart';
import '../client/tranyx_app.dart';
import 'ui_helpers.dart';

// Sub-status labels and progression
const _kSubStatuses = [
  ('heading_to_pickup', '🛵  Heading to Pickup', 'blue'),
  ('arrived_pickup', '📦  Arrived at Pickup', 'blue'),
  ('paid_cashier', '🛒  Items Secured / Paid', 'purple'),
  ('in_transit', '🚗  In Transit to Destination', 'orange'),
  ('arrived_dropoff', '🏠  Arrived at Destination', 'green'),
];

String _subStatusLabel(String? s) {
  if (s == null) return 'Not started';
  return _kSubStatuses.firstWhere((e) => e.$1 == s, orElse: () => (s, s, 'zinc')).$2;
}

String? _nextSubStatus(String? current) {
  if (current == null) return 'heading_to_pickup';
  final idx = _kSubStatuses.indexWhere((e) => e.$1 == current);
  if (idx == -1 || idx >= _kSubStatuses.length - 1) return null;
  return _kSubStatuses[idx + 1].$1;
}

String _nextButtonLabel(String? current) {
  final next = _nextSubStatus(current);
  if (next == null) return 'All Done';
  return _kSubStatuses.firstWhere((e) => e.$1 == next).$2.split('  ').last;
}

/// Google Maps-like navigation tracker powered by OpenStreetMap + Leaflet.
/// - For Employer: live Nyxian marker + real OSRM road route, polls every 5s.
/// - For Nyxian: GPS broadcasting + sub-status steps + "Navigate via OSM" button.
class NavigationMapComponent extends StatefulComponent {
  final TranyxAppState state;
  final bool isNyxian;
  const NavigationMapComponent({required this.state, required this.isNyxian, super.key});

  @override
  State<NavigationMapComponent> createState() => _NavigationMapState();
}

class _NavigationMapState extends State<NavigationMapComponent> {
  static const _mapId = 'nav-map';
  bool _ready = false;
  bool _routeDrawn = false;
  Timer? _pollTimer;
  Timer? _broadcastTimer;
  int _watchId = -1;

  // Current live position (for Nyxian)
  double? _myLat;
  double? _myLng;

  // Turn-by-Turn Voice Navigation variables
  List<Map<String, dynamic>> _routeSteps = [];
  List<List<double>> _routeCoordinates = [];
  int _currentStepIndex = 0;
  double _distanceToNextStep = 0.0;
  double _totalRemainingDistance = 0.0;
  double _totalRemainingDuration = 0.0;
  int _lastSpokenStepIndex = -1;
  int _lastSpokenWarningIndex = -1;

  // Developer Simulation variables
  Timer? _simulationTimer;
  int _simulationCoordIndex = 0;
  bool _isSimulating = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _initializeNyxianLocation() async {
    // 1. Try real GPS first
    try {
      final pos = await getCurrentPosition();
      if (pos != null) {
        _myLat = pos.lat;
        _myLng = pos.lng;
        return;
      }
    } catch (_) {}

    // 2. Try Firestore stored position
    final job = component.state.selectedJobData!;
    final dbLat = (job['nyxianLat'] as num?)?.toDouble();
    final dbLng = (job['nyxianLng'] as num?)?.toDouble();
    if (dbLat != null && dbLng != null) {
      _myLat = dbLat;
      _myLng = dbLng;
      return;
    }

    // 3. Fallback offset from pickup location
    final pickupLat = (job['pickupLat'] as num?)?.toDouble() ?? 14.5995;
    final pickupLng = (job['pickupLng'] as num?)?.toDouble() ?? 120.9842;
    _myLat = pickupLat - 0.015;
    _myLng = pickupLng - 0.015;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _broadcastTimer?.cancel();
    _simulationTimer?.cancel();
    if (_watchId != -1) clearWatch(_watchId);
    destroyMap(_mapId);
    super.dispose();
  }

  @override
  void didUpdateComponent(NavigationMapComponent oldWidget) {
    super.didUpdateComponent(oldWidget);
    
    final oldJob = oldWidget.state.selectedJobData;
    final newJob = component.state.selectedJobData;
    
    if (oldJob != null && newJob != null) {
      final oldId = oldJob['id'];
      final newId = newJob['id'];
      
      final oldRawStatus = oldJob['status'] as String? ?? 'Open';
      final oldSubStatus = oldJob['nyxianSubStatus'] as String? ??
          ((oldRawStatus == 'In Progress' || oldRawStatus == 'in_progress' || oldRawStatus == 'onGoing' || oldRawStatus == 'ongoing' || oldRawStatus == 'Open')
              ? null
              : oldRawStatus);
              
      final newRawStatus = newJob['status'] as String? ?? 'Open';
      final newSubStatus = newJob['nyxianSubStatus'] as String? ??
          ((newRawStatus == 'In Progress' || newRawStatus == 'in_progress' || newRawStatus == 'onGoing' || newRawStatus == 'ongoing' || newRawStatus == 'Open')
              ? null
              : newRawStatus);
              
      if (oldId != newId || oldSubStatus != newSubStatus) {
        _handleSubStatusChange(newSubStatus);
      }
    }
  }

  Future<void> _handleSubStatusChange(String? subStatus) async {
    if (!_ready) return;
    
    final job = component.state.selectedJobData!;
    final pickupLat = (job['pickupLat'] as num?)?.toDouble();
    final pickupLng = (job['pickupLng'] as num?)?.toDouble();
    final destLat = (job['destinationLat'] as num?)?.toDouble();
    final destLng = (job['destinationLng'] as num?)?.toDouble();
    
    final bool isNavigating = (subStatus == 'heading_to_pickup' || subStatus == 'in_transit');
    final pitch = isNavigating ? 45.0 : 0.0;
    final zoom = isNavigating ? 16.5 : 14.0;
    
    final bool pastPickup =
        subStatus == 'paid_cashier' || subStatus == 'in_transit' || subStatus == 'arrived_dropoff';
        
    double startLat;
    double startLng;
    double endLat;
    double endLng;
    String color;
    
    if (component.isNyxian) {
      if (_myLat == null) {
        await _initializeNyxianLocation();
      }
      startLat = _myLat!;
      startLng = _myLng!;
    } else {
      final nyxianLat = (job['nyxianLat'] as num?)?.toDouble();
      final nyxianLng = (job['nyxianLng'] as num?)?.toDouble();
      if (nyxianLat != null && nyxianLng != null) {
        startLat = nyxianLat;
        startLng = nyxianLng;
      } else {
        startLat = pickupLat ?? 14.5995;
        startLng = pickupLng ?? 120.9842;
      }
    }
    
    if (!pastPickup && pickupLat != null) {
      endLat = pickupLat;
      endLng = pickupLng!;
      color = '#3b82f6';
    } else if (destLat != null) {
      endLat = destLat;
      endLng = destLng!;
      color = '#6366f1';
    } else {
      return;
    }
    
    if (component.isNyxian) {
      _updateRouteAndSteps(startLat, startLng, endLat, endLng, color).then((_) {
        double? bearing;
        if (isNavigating && _routeSteps.isNotEmpty) {
          if (_currentStepIndex < _routeSteps.length) {
            final step = _routeSteps[_currentStepIndex];
            bearing = _calculateBearing(startLat, startLng, (step['lat'] as num).toDouble(), (step['lng'] as num).toDouble());
          }
        }
        panTo(_mapId, startLat, startLng, bearing: bearing ?? 0.0, pitch: pitch, zoom: zoom);
      });
    } else {
      _updateEmployerRoute(startLat, startLng, endLat, endLng, color).then((_) {
        double? bearing;
        if (isNavigating && _routeSteps.isNotEmpty) {
          final step = _routeSteps[0];
          bearing = _calculateBearing(startLat, startLng, (step['lat'] as num).toDouble(), (step['lng'] as num).toDouble());
        }
        panTo(_mapId, startLat, startLng, bearing: bearing ?? 0.0, pitch: pitch, zoom: zoom);
      });
    }
  }

  Future<void> _init() async {
    await ensureMapLibreLoaded();

    final job = component.state.selectedJobData!;
    final pickupLat = (job['pickupLat'] as num?)?.toDouble();
    final pickupLng = (job['pickupLng'] as num?)?.toDouble();
    final destLat = (job['destinationLat'] as num?)?.toDouble();
    final destLng = (job['destinationLng'] as num?)?.toDouble();

    final cLat = pickupLat ?? 14.5995;
    final cLng = pickupLng ?? 120.9842;

    final rawStatus = job['status'] as String? ?? 'Open';
    final subStatus = job['nyxianSubStatus'] as String? ??
        ((rawStatus == 'In Progress' || rawStatus == 'in_progress' || rawStatus == 'onGoing' || rawStatus == 'ongoing' || rawStatus == 'Open')
            ? null
            : rawStatus);
    final bool isNavigating = (subStatus == 'heading_to_pickup' || subStatus == 'in_transit');
    final pitch = isNavigating ? 45.0 : 0.0;
    final zoom = isNavigating ? 16.5 : 14.0;

    // initMap now polls for the DOM element — no fixed delay needed
    final isDark = component.state.isDark;
    await initMap(_mapId, cLat, cLng, zoom, isDark: isDark, pitch: pitch);

    // Draw named place markers
    if (pickupLat != null) {
      setMarker(_mapId, 'pickup', pickupLat, pickupLng!, '📦 1st Point: ${job['pickupAddress'] ?? ''}');
    }
    if (destLat != null) {
      setMarker(_mapId, 'destination', destLat, destLng!, '🏠 Delivery: ${job['destinationAddress'] ?? ''}');
    }

    // Draw real OSRM road route
    if (pickupLat != null && destLat != null && !_routeDrawn) {
      _routeDrawn = true;
      final bool pastPickup =
          subStatus == 'paid_cashier' || subStatus == 'in_transit' || subStatus == 'arrived_dropoff';
      final nyxianLat = (job['nyxianLat'] as num?)?.toDouble();
      final nyxianLng = (job['nyxianLng'] as num?)?.toDouble();

      double startLat;
      double startLng;
      double endLat;
      double endLng;
      String color;

      if (component.isNyxian) {
        await _initializeNyxianLocation();
        if (_myLat != null) {
          setMarker(_mapId, 'nyxian', _myLat!, _myLng!, '🛵 You — ${_subStatusLabel(subStatus)}');
        }
        startLat = _myLat!;
        startLng = _myLng!;
      } else {
        if (nyxianLat != null && nyxianLng != null) {
          setMarker(_mapId, 'nyxian', nyxianLat, nyxianLng, _nyxianMarkerLabel(subStatus));
          startLat = nyxianLat;
          startLng = nyxianLng;
        } else {
          startLat = pickupLat;
          startLng = pickupLng!;
        }
      }

      if (!pastPickup) {
        endLat = pickupLat;
        endLng = pickupLng!;
        color = '#3b82f6';
      } else {
        endLat = destLat;
        endLng = destLng!;
        color = '#6366f1';
      }

      if (component.isNyxian) {
        await _updateRouteAndSteps(startLat, startLng, endLat, endLng, color);
      } else {
        await _updateEmployerRoute(startLat, startLng, endLat, endLng, color);
      }
    }

    setState(() => _ready = true);

    // Small invalidate to fix tile rendering after layout
    await Future.delayed(const Duration(milliseconds: 600));
    invalidateMapSize(_mapId);

    if (component.isNyxian) {
      _startBroadcasting();
    } else {
      _startPolling();
    }
  }

  String _statusColor(String? status) {
    if (status == 'heading_to_pickup' || status == 'arrived_pickup') return 'bg-blue-400';
    if (status == 'paid_cashier') return 'bg-purple-400';
    if (status == 'in_transit') return 'bg-orange-400';
    if (status == 'arrived_dropoff') return 'bg-green-400';
    return 'bg-zinc-400';
  }

  String _nyxianMarkerLabel(String? status) {
    final label = _subStatusLabel(status);
    if (status == 'heading_to_pickup') return '🛵 Nyxian — $label';
    if (status == 'arrived_pickup') return '📦 Nyxian — $label';
    if (status == 'paid_cashier') return '🛒 Nyxian — $label';
    if (status == 'in_transit') return '🚗 Nyxian — $label';
    if (status == 'arrived_dropoff') return '🏠 Nyxian — $label';
    return '🛵 Nyxian — $label';
  }

  Future<void> _updateEmployerRoute(double fromLat, double fromLng, double toLat, double toLng, String color) async {
    try {
      final routeData = await drawOSRMRoute(_mapId, fromLat, fromLng, toLat, toLng, color);
      if (routeData != null) {
        final stepsList = routeData['steps'] as List<dynamic>?;
        final coordsList = routeData['coordinates'] as List<dynamic>?;

        setState(() {
          _routeSteps = stepsList?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
          _routeCoordinates = coordsList?.map((e) => (e as List<dynamic>).map((x) => (x as num).toDouble()).toList()).toList() ?? [];
          _currentStepIndex = 0;
        });

        double remainingDist = 0.0;
        double remainingDur = 0.0;
        for (final step in _routeSteps) {
          remainingDist += (step['distance'] as num).toDouble();
          remainingDur += (step['duration'] as num).toDouble();
        }

        setState(() {
          _totalRemainingDistance = remainingDist;
          _totalRemainingDuration = remainingDur;
        });
      }
    } catch (e) {
      print("Error loading employer route: $e");
    }
  }

  // ── Employer: poll Firestore for Nyxian location ──────────────────────────

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_isSimulating) return;
      final token = component.state.idToken;
      final jobId = component.state.selectedJobData!['id'];
      if (token == null || jobId == null) return;

      try {
        final job = await FirestoreService(token).getDocument('jobs/$jobId');
        if (job == null) return;

        final lat = (job['nyxianLat'] as num?)?.toDouble();
        final lng = (job['nyxianLng'] as num?)?.toDouble();
        final rawStatus = job['status'] as String? ?? 'Open';
        final subStatus = job['nyxianSubStatus'] as String? ??
            ((rawStatus == 'In Progress' || rawStatus == 'in_progress' || rawStatus == 'onGoing' || rawStatus == 'ongoing' || rawStatus == 'Open')
                ? null
                : rawStatus);

        if (lat != null && lng != null) {
          setMarker(_mapId, 'nyxian', lat, lng, _nyxianMarkerLabel(subStatus));
          _myLat = lat;
          _myLng = lng;

          double? bearing;
          double? pitch;
          double? zoom;
          final bool isNavigating = (subStatus == 'heading_to_pickup' || subStatus == 'in_transit');

          if (isNavigating) {
            pitch = 45.0;
            zoom = 16.5;
            if (_routeSteps.isNotEmpty && _currentStepIndex < _routeSteps.length) {
              final step = _routeSteps[_currentStepIndex];
              bearing = _calculateBearing(lat, lng, (step['lat'] as num).toDouble(), (step['lng'] as num).toDouble());
            }
          } else {
            pitch = 0.0;
            bearing = 0.0;
            zoom = 14.0;
          }
          panTo(_mapId, lat, lng, bearing: bearing, pitch: pitch, zoom: zoom);

          final pickupLat = (job['pickupLat'] as num?)?.toDouble();
          final pickupLng = (job['pickupLng'] as num?)?.toDouble();
          final destLat = (job['destinationLat'] as num?)?.toDouble();
          final destLng = (job['destinationLng'] as num?)?.toDouble();

          final bool pastPickup =
              subStatus == 'paid_cashier' || subStatus == 'in_transit' || subStatus == 'arrived_dropoff';

          if (!pastPickup && pickupLat != null) {
            await _updateEmployerRoute(lat, lng, pickupLat, pickupLng!, '#3b82f6');
          } else if (pastPickup && destLat != null) {
            await _updateEmployerRoute(lat, lng, destLat, destLng!, '#6366f1');
          }
        }

        component.state.setState(() {
          component.state.selectedJobData = {
            ...component.state.selectedJobData!,
            'nyxianSubStatus': subStatus,
          };
        });
      } catch (_) {}
    });
  }

  // ── Nyxian: broadcast GPS + draw live route ───────────────────────────────

  void _startBroadcasting() {
    _updateNyxianLocation();
    _broadcastTimer = Timer.periodic(const Duration(seconds: 10), (_) => _updateNyxianLocation());
    _watchId = watchPosition((lat, lng) {
      if (_isSimulating) return;
      setState(() {
        _myLat = lat;
        _myLng = lng;
      });
      _updateFirestoreLocation(lat, lng);
      // Live route from current GPS to next waypoint
      _redrawRouteFromCurrentPos(lat, lng);
    });
  }

  Future<void> _updateNyxianLocation() async {
    if (_isSimulating) return;
    final pos = await getCurrentPosition();
    if (pos != null) {
      setState(() {
        _myLat = pos.lat;
        _myLng = pos.lng;
      });
      _updateFirestoreLocation(pos.lat, pos.lng);
      _redrawRouteFromCurrentPos(pos.lat, pos.lng);
    }
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final lat1Rad = lat1 * math.pi / 180.0;
    final lat2Rad = lat2 * math.pi / 180.0;

    final y = math.sin(dLon) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);

    final brng = math.atan2(y, x) * 180.0 / math.pi;
    return (brng + 360.0) % 360.0;
  }

  Future<void> _updateFirestoreLocation(double lat, double lng) async {
    final token = component.state.idToken;
    final jobId = component.state.selectedJobData!['id'];
    if (token == null || jobId == null) return;
    try {
      if (component.isNyxian) {
        await FirestoreService(token).createOrUpdate('jobs/$jobId', {
          'nyxianLat': lat,
          'nyxianLng': lng,
        });
      }
      final rawStatus = component.state.selectedJobData!['status'] as String? ?? 'Open';
      final subStatus = component.state.selectedJobData!['nyxianSubStatus'] as String? ??
          ((rawStatus == 'In Progress' || rawStatus == 'in_progress' || rawStatus == 'onGoing' || rawStatus == 'ongoing' || rawStatus == 'Open')
              ? null
              : rawStatus);
      setMarker(_mapId, 'nyxian', lat, lng, component.isNyxian ? '🛵 You — ${_subStatusLabel(subStatus)}' : '🛵 Courier (Simulated) — ${_subStatusLabel(subStatus)}');
      
      double? bearing;
      double? pitch;
      double? zoom;
      final bool isNavigating = (subStatus == 'heading_to_pickup' || subStatus == 'in_transit' || _isSimulating);
      
      if (isNavigating) {
        pitch = 45.0;
        zoom = 16.5;
        if (_isSimulating && _simulationCoordIndex + 1 < _routeCoordinates.length) {
          final nextCoord = _routeCoordinates[_simulationCoordIndex + 1];
          bearing = _calculateBearing(lat, lng, nextCoord[0], nextCoord[1]);
        } else if (_routeCoordinates.isNotEmpty) {
          if (_currentStepIndex < _routeSteps.length) {
            final step = _routeSteps[_currentStepIndex];
            bearing = _calculateBearing(lat, lng, (step['lat'] as num).toDouble(), (step['lng'] as num).toDouble());
          }
        }
      } else {
        pitch = 0.0;
        bearing = 0.0;
        zoom = 14.0;
      }
      panTo(_mapId, lat, lng, bearing: bearing, pitch: pitch, zoom: zoom);
    } catch (_) {}
  }

  void _redrawRouteFromCurrentPos(double fromLat, double fromLng) {
    if (_isSimulating) return;
    final job = component.state.selectedJobData!;
    final rawStatus2 = job['status'] as String? ?? 'Open';
    final subStatus = job['nyxianSubStatus'] as String? ??
        ((rawStatus2 == 'In Progress' || rawStatus2 == 'in_progress' || rawStatus2 == 'onGoing' || rawStatus2 == 'ongoing' || rawStatus2 == 'Open')
            ? null
            : rawStatus2);
    // Navigate to pickup first, then to destination
    final pickupLat = (job['pickupLat'] as num?)?.toDouble();
    final pickupLng = (job['pickupLng'] as num?)?.toDouble();
    final destLat = (job['destinationLat'] as num?)?.toDouble();
    final destLng = (job['destinationLng'] as num?)?.toDouble();

    final bool pastPickup =
        subStatus == 'paid_cashier' || subStatus == 'in_transit' || subStatus == 'arrived_dropoff';

    if (!pastPickup && pickupLat != null) {
      _updateRouteAndSteps(fromLat, fromLng, pickupLat, pickupLng!, '#3b82f6');
    } else if (pastPickup && destLat != null) {
      _updateRouteAndSteps(fromLat, fromLng, destLat, destLng!, '#6366f1');
    }
  }

  Future<void> _updateRouteAndSteps(double fromLat, double fromLng, double toLat, double toLng, String color) async {
    try {
      final routeData = await drawOSRMRoute(_mapId, fromLat, fromLng, toLat, toLng, color);
      if (routeData != null) {
        final stepsList = routeData['steps'] as List<dynamic>?;
        final coordsList = routeData['coordinates'] as List<dynamic>?;

        setState(() {
          _routeSteps = stepsList?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
          _routeCoordinates = coordsList?.map((e) => (e as List<dynamic>).map((x) => (x as num).toDouble()).toList()).toList() ?? [];
          _currentStepIndex = 0;
          _lastSpokenStepIndex = -1;
          _lastSpokenWarningIndex = -1;
        });

        _updateNavigationMetrics(fromLat, fromLng);
      }
    } catch (e) {
      print("Error loading route and steps: $e");
    }
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
        if (component.isNyxian) {
          speakText(instruction);
        }
      } else if (_distanceToNextStep <= 50.0 && _distanceToNextStep > 20.0 && _currentStepIndex != _lastSpokenWarningIndex) {
        _lastSpokenWarningIndex = _currentStepIndex;
        if (component.isNyxian) {
          speakText("In 50 meters, $instruction");
        }
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

  double _distanceInMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final phi1 = lat1 * math.pi / 180.0;
    final phi2 = lat2 * math.pi / 180.0;
    final deltaPhi = (lat2 - lat1) * math.pi / 180.0;
    final deltaLambda = (lon2 - lon1) * math.pi / 180.0;

    final a = math.sin(deltaPhi / 2.0) * math.sin(deltaPhi / 2.0) +
        math.cos(phi1) * math.cos(phi2) *
        math.sin(deltaLambda / 2.0) * math.sin(deltaLambda / 2.0);
    final c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));

    return r * c;
  }

  void _toggleSimulation() {
    if (_isSimulating) {
      _stopSimulation();
    } else {
      _startSimulation();
    }
  }

  void _startSimulation() {
    if (_routeCoordinates.isEmpty) return;

    setState(() {
      _isSimulating = true;
      _simulationCoordIndex = 0;
    });

    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_simulationCoordIndex >= _routeCoordinates.length) {
        _stopSimulation();
        if (component.isNyxian) {
          speakText("You have arrived at your destination.");
        }
        return;
      }

      final coord = _routeCoordinates[_simulationCoordIndex];
      final lat = coord[0];
      final lng = coord[1];

      setState(() {
        _myLat = lat;
        _myLng = lng;
      });

      _updateFirestoreLocation(lat, lng);
      _updateNavigationMetrics(lat, lng);

      _simulationCoordIndex++;
    });
  }

  void _stopSimulation() {
    _simulationTimer?.cancel();
    setState(() {
      _isSimulating = false;
    });
    if (!component.isNyxian) {
      final job = component.state.selectedJobData!;
      final nyxianLat = (job['nyxianLat'] as num?)?.toDouble();
      final nyxianLng = (job['nyxianLng'] as num?)?.toDouble();
      final targetLat = nyxianLat ?? (job['pickupLat'] as num?)?.toDouble() ?? 14.5995;
      final targetLng = nyxianLng ?? (job['pickupLng'] as num?)?.toDouble() ?? 120.9842;
      panTo(_mapId, targetLat, targetLng, bearing: 0.0, pitch: 0.0);
    }
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final job = s.selectedJobData!;
    final rawStatus = job['status'] as String? ?? 'Open';
    final subStatus = job['nyxianSubStatus'] as String? ??
        ((rawStatus == 'In Progress' || rawStatus == 'in_progress' || rawStatus == 'onGoing' || rawStatus == 'ongoing' || rawStatus == 'Open')
            ? null
            : rawStatus);
    final nextStatus = _nextSubStatus(subStatus);
    final catName = (job['category'] as String? ?? '').toLowerCase();
    final cat = JobCategory.values.firstWhere(
      (e) => e.name.toLowerCase() == catName || e.label.toLowerCase() == catName,
      orElse: () => JobCategory.others,
    );
    final hasTracker = job['hasTracker'] == true || job['hasTracker'] == 'true' || cat.hasTracker;
    final destLat = (job['destinationLat'] as num?)?.toDouble();
    final destLng = (job['destinationLng'] as num?)?.toDouble();

    String? remainingMetricStr;
    if (!component.isNyxian && _totalRemainingDistance > 0) {
      final distStr = _totalRemainingDistance >= 1000
          ? '${(_totalRemainingDistance / 1000).toStringAsFixed(1)} km'
          : '${_totalRemainingDistance.toStringAsFixed(0)} m';
      final minutes = (_totalRemainingDuration / 60).round();
      final durStr = minutes <= 0 ? 'Under 1 min' : '$minutes min';
      remainingMetricStr = '• $distStr ($durStr)';
    }

    final showNavigationOverlay = _ready &&
        component.isNyxian &&
        (subStatus == 'heading_to_pickup' || subStatus == 'in_transit' || _isSimulating) &&
        _routeSteps.isNotEmpty &&
        _currentStepIndex < _routeSteps.length;

    return div(
      classes: 'flex flex-col gap-4',
      [
        // ── Map card ─────────────────────────────────────────────────────────
        div(
          classes:
              'relative w-full rounded-[2rem] overflow-hidden border shadow-2xl '
              '${isDark ? "border-zinc-800" : "border-zinc-200"}',
          styles: Styles(raw: {'height': '420px'}),
          [
            // Map element — always rendered so MapLibre can attach
            MapContainer(
              key: const ValueKey('map-navigator'),
              id: _mapId,
              classes: 'w-full h-full ${isDark ? "theme-dark" : "theme-light"}',
              styles: Styles(raw: {
                'z-index': '1',
                'position': 'absolute !important',
                'top': '0',
                'left': '0',
                'right': '0',
                'bottom': '0',
                'height': '100%',
                'width': '100%',
              }),
            ),

            // Loading overlay (shown until map is ready)
            div(
              classes:
                  'absolute inset-0 flex flex-col items-center justify-center gap-4 z-[2] '
                  '${isDark ? "bg-zinc-900" : "bg-zinc-50"} '
                  '${_ready ? "hidden" : ""}',
              [
                lIcon('loader-2', cls: 'w-10 h-10 animate-spin text-indigo-500'),
                p(classes: 'text-sm font-semibold ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                  Component.text('Loading map…'),
                ]),
              ],
            ),

            // Turn-by-Turn Navigation Overlay
            if (showNavigationOverlay)
              _navigationOverlay(isDark),

            // ── Floating top bar (status) ─────────────────────────────────
            if (_ready && !showNavigationOverlay)
              div(
                classes:
                    'absolute top-4 left-4 right-4 z-[400] flex items-center justify-between gap-2 pointer-events-none',
                [
                  // Status pill
                  div(
                    classes:
                        'px-4 py-2.5 rounded-2xl backdrop-blur-md border pointer-events-auto flex items-center gap-2.5 shadow-lg '
                        '${isDark ? "bg-zinc-900/85 border-zinc-700/60" : "bg-white/85 border-white"}',
                    [
                      div(classes: 'w-2 h-2 rounded-full ${_statusColor(subStatus)} animate-pulse flex-shrink-0', []),
                      div(classes: 'flex flex-col', [
                        span(
                          classes:
                              'text-[9px] uppercase tracking-widest font-black ${isDark ? "text-zinc-500" : "text-zinc-400"}',
                          [Component.text('Live Tracker')],
                        ),
                        span(classes: 'text-xs font-bold flex items-center gap-1.5', [
                          Component.text(_subStatusLabel(subStatus)),
                          if (remainingMetricStr != null)
                            span(classes: 'text-[11px] font-medium opacity-75', [
                              Component.text(remainingMetricStr),
                            ]),
                        ]),
                      ]),
                    ],
                  ),

                  // Recenter button
                  button(
                    classes:
                        'w-10 h-10 rounded-xl backdrop-blur-md border flex items-center justify-center pointer-events-auto shadow-lg hover:scale-105 transition-transform '
                        '${isDark ? "bg-zinc-900/85 border-zinc-700/60 text-white" : "bg-white/85 border-white text-zinc-900"}',
                    events: {
                      'click': (_) {
                        final pitch = component.isNyxian ? 45.0 : 0.0;
                        if (_myLat != null) {
                          double? bearing;
                          if (component.isNyxian) {
                            if (_isSimulating && _simulationCoordIndex + 1 < _routeCoordinates.length) {
                              final nextCoord = _routeCoordinates[_simulationCoordIndex + 1];
                              bearing = _calculateBearing(_myLat!, _myLng!, nextCoord[0], nextCoord[1]);
                            } else if (_routeCoordinates.isNotEmpty && _currentStepIndex < _routeSteps.length) {
                              final step = _routeSteps[_currentStepIndex];
                              bearing = _calculateBearing(_myLat!, _myLng!, (step['lat'] as num).toDouble(), (step['lng'] as num).toDouble());
                            }
                          }
                          panTo(_mapId, _myLat!, _myLng!, bearing: bearing, pitch: pitch);
                        } else {
                          final pLat = (job['pickupLat'] as num?)?.toDouble();
                          final pLng = (job['pickupLng'] as num?)?.toDouble();
                          if (pLat != null) {
                            panTo(_mapId, pLat, pLng!, pitch: pitch);
                          }
                        }
                      },
                    },
                    [lIcon('crosshair', cls: 'w-4 h-4')],
                  ),
                ],
              ),
          ],
        ),

        // ── Bottom info cards ─────────────────────────────────────────────────
        if (_ready) ...[
          // Route cards
          div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-3', [
            if (hasTracker) ...[
              _routeCard(
                icon: 'package',
                label: '1st Point',
                address: job['pickupAddress'] as String? ?? 'Not specified',
                color: 'blue',
                isDark: isDark,
              ),
              _routeCard(
                icon: 'home',
                label: 'Delivery Point',
                address: job['destinationAddress'] as String? ?? 'Not specified',
                color: 'green',
                isDark: isDark,
              ),
            ] else
              _routeCard(
                icon: 'map-pin',
                label: 'Site Location',
                address: job['address'] as String? ?? 'Not specified',
                color: 'indigo',
                isDark: isDark,
                fullWidth: true,
              ),
          ]),

          // Nyxian action card (sub-status progression)
          if (hasTracker && component.isNyxian && nextStatus != null)
            _nyxianActionCard(nextStatus, subStatus, isDark, s),

          if (hasTracker && component.isNyxian && subStatus == 'arrived_dropoff') _successCard(isDark),

          // Employer timeline
          if (hasTracker && !component.isNyxian) _timelineCard(subStatus, isDark),

          // ── OSM Navigate & Simulate buttons ─────────────────────────────
          if (destLat != null && component.isNyxian)
            div(classes: 'flex gap-2.5 w-full', [
              button(
                classes:
                    'flex-1 py-3.5 rounded-2xl font-bold text-sm flex items-center justify-center gap-2.5 transition-all hover:scale-[1.01] active:scale-[0.99] '
                    '${isDark ? "bg-zinc-800 hover:bg-zinc-700 border border-zinc-700 text-white" : "bg-zinc-100 hover:bg-zinc-200 border border-zinc-200 text-zinc-900"}',
                events: {
                  'click': (_) => openOSMNavigation(destLat, destLng!),
                },
                [
                  lIcon('navigation', cls: 'w-4 h-4 text-indigo-400'),
                  Component.text('Open Navigation (OSM)'),
                ],
              ),
              if (_routeCoordinates.isNotEmpty)
                button(
                  classes:
                      'px-5 py-3.5 rounded-2xl font-bold text-sm flex items-center justify-center gap-2.5 transition-all hover:scale-[1.01] active:scale-[0.99] '
                      '${_isSimulating ? "bg-rose-500 text-white hover:bg-rose-600 shadow-lg shadow-rose-500/20" : (isDark ? "bg-zinc-800 text-indigo-400 hover:bg-zinc-700 border border-zinc-700" : "bg-zinc-100 text-indigo-600 hover:bg-zinc-200 border border-zinc-200")}',
                  events: {
                    'click': (_) => _toggleSimulation(),
                  },
                  [
                    lIcon(_isSimulating ? 'square' : 'play', cls: 'w-4 h-4'),
                    Component.text(_isSimulating ? 'Stop Simulation' : 'Simulate'),
                  ],
                ),
            ]),
        ],
      ],
    );
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
    if (_totalRemainingDistance >= 1000) {
      totalDistStr = '${(_totalRemainingDistance / 1000).toStringAsFixed(1)} km';
    } else {
      totalDistStr = '${_totalRemainingDistance.toStringAsFixed(0)} m';
    }

    // Format total remaining duration
    String durationStr;
    final minutes = (_totalRemainingDuration / 60).round();
    if (minutes <= 0) {
      durationStr = 'Under 1 min';
    } else {
      durationStr = '$minutes min';
    }

    return div(
      classes: 'absolute top-4 left-4 right-4 z-[400] p-4 rounded-2xl backdrop-blur-md border shadow-xl flex flex-col gap-3 pointer-events-auto '
               '${isDark ? "bg-zinc-900/90 border-zinc-700/60 text-white" : "bg-white/90 border-zinc-200 text-zinc-900"}',
      [
        // Upper row: maneuver and next turn distance
        div(classes: 'flex items-center gap-3.5', [
          div(classes: 'w-10 h-10 rounded-xl bg-indigo-500 flex items-center justify-center flex-shrink-0 text-white shadow-lg shadow-indigo-500/20', [
            lIcon(iconName, cls: 'w-5 h-5'),
          ]),
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
        div(classes: 'flex items-center justify-between text-xs font-semibold ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
          div(classes: 'flex items-center gap-1.5', [
            lIcon('clock', cls: 'w-3.5 h-3.5 text-emerald-400'),
            span([Component.text(durationStr)]),
          ]),
          div(classes: 'flex items-center gap-1.5', [
            lIcon('map-pin', cls: 'w-3.5 h-3.5 text-rose-400'),
            span([Component.text('$totalDistStr remaining')]),
          ]),
        ]),
      ],
    );
  }

  Component _routeCard({
    required String icon,
    required String label,
    required String address,
    required String color,
    required bool isDark,
    bool fullWidth = false,
  }) {
    final textCol = color == 'blue' ? 'text-blue-400' : (color == 'green' ? 'text-green-400' : 'text-indigo-400');
    final bgCol = color == 'blue' ? 'bg-blue-500/10' : (color == 'green' ? 'bg-green-500/10' : 'bg-indigo-500/10');
    return div(
      classes:
          'flex items-center gap-3 p-4 rounded-2xl border '
          '${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200"} '
          '${fullWidth ? "col-span-2" : ""}',
      [
        div(classes: 'w-9 h-9 rounded-xl $bgCol flex items-center justify-center flex-shrink-0', [
          lIcon(icon, cls: 'w-4 h-4 $textCol'),
        ]),
        div(classes: 'flex-1 min-w-0', [
          p(classes: 'text-[10px] font-black uppercase tracking-wider $textCol mb-0.5', [Component.text(label)]),
          p(classes: 'text-xs font-medium truncate ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
            Component.text(address),
          ]),
        ]),
      ],
    );
  }

  Component _nyxianActionCard(String nextStatus, String? currentStatus, bool isDark, TranyxAppState s) {
    return div(
      classes:
          'p-4 rounded-2xl border flex items-center gap-4 '
          '${isDark ? "bg-indigo-600/10 border-indigo-500/30" : "bg-indigo-50 border-indigo-200"}',
      [
        div(classes: 'flex-1', [
          p(classes: 'text-[10px] font-black uppercase tracking-widest text-indigo-400 mb-0.5', [
            Component.text('Next Action'),
          ]),
          p(classes: 'text-sm font-bold', [Component.text(_nextButtonLabel(currentStatus))]),
        ]),
        button(
          classes: s.isUpdatingSubStatus
              ? 'px-5 py-2.5 rounded-xl font-bold text-xs text-white bg-indigo-600/50 cursor-not-allowed flex items-center gap-2'
              : 'px-5 py-2.5 rounded-xl font-bold text-xs text-white bg-indigo-600 hover:bg-indigo-500 shadow-lg shadow-indigo-500/30 transition-all hover:scale-[1.02] active:scale-95 flex items-center gap-2',
          events: s.isUpdatingSubStatus ? {} : {'click': (_) => s.handleUpdateNyxianSubStatus(nextStatus)},
          [
            if (s.isUpdatingSubStatus) lIcon('loader-2', cls: 'w-3.5 h-3.5 animate-spin'),
            Component.text('Confirm'),
          ],
        ),
      ],
    );
  }

  Component _successCard(bool isDark) {
    return div(
      classes: 'p-4 rounded-2xl border border-green-500/30 bg-green-500/10 flex items-center gap-3 justify-center',
      [
        lIcon('check-circle', cls: 'w-5 h-5 text-green-400'),
        p(classes: 'text-sm font-bold text-green-400', [
          Component.text('Arrived! Show QR code to Employer.'),
        ]),
      ],
    );
  }

  Component _timelineCard(String? subStatus, bool isDark) {
    final currentIdx = subStatus == null ? -1 : _kSubStatuses.indexWhere((e) => e.$1 == subStatus);
    return div(
      classes: 'p-4 rounded-2xl border ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200"}',
      [
        p(
          classes:
              'text-[10px] font-black uppercase tracking-widest ${isDark ? "text-zinc-500" : "text-zinc-400"} mb-3',
          [
            Component.text('Delivery Progress'),
          ],
        ),
        div(classes: 'space-y-1', [
          for (int i = 0; i < _kSubStatuses.length; i++) ...[
            div(classes: 'flex items-center gap-3', [
              div(
                classes: i <= currentIdx
                    ? 'w-5 h-5 rounded-full flex items-center justify-center bg-indigo-500 shadow-md flex-shrink-0'
                    : 'w-5 h-5 rounded-full border-2 flex-shrink-0 ${isDark ? "border-zinc-700" : "border-zinc-200"}',
                [
                  if (i <= currentIdx)
                    lIcon('check', cls: 'w-3 h-3 text-white')
                  else
                    span(
                      classes: 'text-[9px] ${isDark ? "text-zinc-600" : "text-zinc-400"}',
                      [Component.text((i + 1).toString())],
                    ),
                ],
              ),
              p(
                classes: i <= currentIdx
                    ? 'text-xs font-bold text-indigo-400'
                    : 'text-xs ${isDark ? "text-zinc-600" : "text-zinc-400"}',
                [Component.text(_kSubStatuses[i].$2)],
              ),
            ]),
            if (i < _kSubStatuses.length - 1)
              div(
                classes:
                    'ml-2.5 w-0.5 h-3 ${i < currentIdx ? "bg-indigo-500/30" : (isDark ? "bg-zinc-800" : "bg-zinc-100")}',
                [],
              ),
          ],
        ]),
      ],
    );
  }
}
