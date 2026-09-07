import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/mapbox_gl.dart';
import 'package:headless_nav_core/headless_nav_core.dart';
import '../adapters/flutter_tts_adapter.dart';
import '../state/flutter_nav_providers.dart';
import 'turn_instruction_banner.dart';
import 'telemetry_share_sheet.dart';

/// Full-screen driver turn-by-turn navigation widget powered by MapLibre GL
/// with OpenFreeMap vector styles, rotating heads-up camera, dynamic polyline pruning,
/// real-time speed-adjusted turn and stop ETA HUD, and TTS voice prompts.
class NavigationView extends ConsumerStatefulWidget {
  /// Optional sequence of stops to navigate through. If provided, [NavigationView]
  /// automatically fetches the route (or loads from local DB), configures the engine,
  /// and begins navigation seamlessly.
  final List<NavWaypoint>? stops;

  /// Travel profile (Car, Motorcycle, Bike, Walking).
  final NavTravelMode travelMode;

  /// Custom style JSON URL. If provided and [themeAdaptive] is false, this is used.
  final String? styleString;

  /// Whether the map style should adapt automatically to the app/system theme (light/dark).
  /// Defaults to false (using [lightStyle]).
  final bool themeAdaptive;

  /// Map style URL to use in light mode or when [themeAdaptive] is false.
  /// Defaults to OpenFreeMap Bright style.
  final String lightStyle;

  /// Map style URL to use when [themeAdaptive] is true and dark theme is active.
  /// Defaults to OpenFreeMap Dark style.
  final String darkStyle;

  /// Whether spoken turn prompts are enabled via TTS. Defaults to true.
  final bool enableTts;

  /// Optional live GPS position stream (e.g. from [GeolocatorAdapter.getPositionStream]).
  /// If omitted, falls back to [SimulatedLocationProvider] along the route.
  final Stream<NavPosition>? locationStream;

  /// Optional telemetry broadcaster. If omitted, falls back to [locationBroadcasterProvider].
  final LocationBroadcaster? broadcaster;

  /// Optional telemetry channel ID to broadcast real-time driver coordinates to followers.
  final String? channelId;

  /// Optional callback to close or exit navigation mode.
  /// If neither [onClose] nor [onExit] is provided, the close button is omitted.
  final VoidCallback? onClose;

  final VoidCallback? onExit;

  /// Optional callback invoked when arriving at a stop or destination,
  /// passing the 1-based stop count index (e.g. 1 for first stop, 2 for second stop).
  final void Function(int stopCount)? onArrived;

  static const String defaultStyleUrl = OpenFreeMapStyles.bright;

  const NavigationView({
    super.key,
    this.stops,
    this.travelMode = NavTravelMode.car,
    this.locationStream,
    this.broadcaster,
    this.channelId,
    this.styleString,
    this.themeAdaptive = false,
    this.lightStyle = OpenFreeMapStyles.bright,
    this.darkStyle = OpenFreeMapStyles.dark,
    this.enableTts = true,
    this.onClose,
    this.onExit,
    this.onArrived,
  });

  @override
  ConsumerState<NavigationView> createState() => _NavigationViewState();
}

class _NavigationViewState extends ConsumerState<NavigationView> {
  MaplibreMapController? _mapController;
  Line? _routeLine;
  bool _autoFollowCamera = true;
  bool _isMuted = false;
  FlutterTtsAdapter? _ttsAdapter;
  int _lastPrunedCoordCount = 0;
  bool _isInitializingRoute = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    if (widget.enableTts) {
      _ttsAdapter = FlutterTtsAdapter();
    }

    if (widget.stops != null && widget.stops!.isNotEmpty) {
      _initializeMultiStopRoute();
    }
  }

  Future<void> _initializeMultiStopRoute() async {
    setState(() {
      _isInitializingRoute = true;
      _initError = null;
    });

    try {
      final router = ref.read(osrmRouterProvider);
      final points = widget.stops!.map((s) => s.position).toList();

      final payload = await router.getRoute(
        points: points,
        mode: widget.travelMode,
      );

      final engine = NavigationEngine(
        route: payload,
        waypoints: widget.stops,
        options: const NavigationEngineOptions(
          enableBackgroundIsolates: true,
          offRouteThresholdMeters: 40.0,
          arrivalThresholdMeters: 15.0,
        ),
        onArrived: widget.onArrived,
      );

      // If a live locationStream is provided, connect it. Otherwise, use simulation.
      if (widget.locationStream != null) {
        engine.start(widget.locationStream!);
      } else {
        final sim = SimulatedLocationProvider(
          route: payload,
          speedKmh: widget.travelMode == NavTravelMode.foot ? 5.0 : 45.0,
        );
        engine.start(sim.stream());
      }

      ref.read(navEngineProvider.notifier).state = engine;
      ref.read(travelModeProvider.notifier).state = widget.travelMode;
    } catch (e) {
      setState(() => _initError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isInitializingRoute = false);
      }
    }
  }

  void _onMapCreated(MaplibreMapController controller) {
    _mapController = controller;
  }

  /// Smoothly animates the camera with forward-tilt and vehicle bearing rotation
  /// so that forward travel is always facing upwards on the rider's screen.
  void _updateCamera(double lat, double lon, double bearing) {
    if (!_autoFollowCamera || _mapController == null) return;

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(lat, lon),
          zoom: 18.0,
          tilt: 55.0,
          bearing: bearing,
        ),
      ),
      duration: const Duration(milliseconds: 400),
    );
  }

  /// Throttled dynamic route polyline rendering that prunes traversed segments.
  Future<void> _updateRoutePolyline(List<List<double>> slicedCoords) async {
    if (_mapController == null || slicedCoords.isEmpty) return;

    // Throttle line buffer re-tessellations: only update if coordinate count changed
    if (slicedCoords.length == _lastPrunedCoordCount) return;
    _lastPrunedCoordCount = slicedCoords.length;

    final latLngs = slicedCoords.map((c) => LatLng(c[1], c[0])).toList();

    if (_routeLine == null) {
      _routeLine = await _mapController?.addLine(
        LineOptions(
          geometry: latLngs,
          lineColor: '#0066FF',
          lineWidth: 6.5,
          lineOpacity: 0.9,
          lineJoin: 'round',
        ),
      );
    } else {
      await _mapController?.updateLine(
        _routeLine!,
        LineOptions(geometry: latLngs),
      );
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).round();
    if (mins < 60) return '$mins min';
    final hours = mins ~/ 60;
    final rem = mins % 60;
    return '${hours}h ${rem}m';
  }

  String _formatEtaClock(DateTime eta) {
    final hour = eta.hour > 12 ? eta.hour - 12 : (eta.hour == 0 ? 12 : eta.hour);
    final period = eta.hour >= 12 ? 'PM' : 'AM';
    final minute = eta.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final navStateAsync = ref.watch(navigationStateProvider);
    final isBroadcasting = ref.watch(isBroadcastingActiveProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final effectiveStyle = widget.themeAdaptive
        ? (isDark ? widget.darkStyle : widget.lightStyle)
        : (widget.styleString ?? widget.lightStyle);

    // Listen for state changes to drive camera, dynamic line clipping, and telemetry broadcast
    ref.listen(navigationStateProvider, (prev, next) {
      next.whenData((state) {
        _updateCamera(
          state.snappedLocation.latitude,
          state.snappedLocation.longitude,
          state.currentBearing,
        );
        _updateRoutePolyline(state.slicedRouteCoordinates);

        // Broadcast driver telemetry if channelId is specified
        if (widget.channelId != null) {
          try {
            final broadcaster =
                widget.broadcaster ?? ref.read(locationBroadcasterProvider);
            broadcaster?.broadcast(
              widget.channelId!,
              BroadcasterTelemetry(
                channelId: widget.channelId!,
                broadcasterId: 'flutter-driver',
                rawPosition: state.snappedLocation,
                snappedPosition: state.snappedLocation,
                currentBearing: state.currentBearing,
                remainingDistance: state.remainingDistance,
                remainingDuration: state.remainingDuration,
                currentInstruction: state.currentInstruction,
                routeCoordinates: state.slicedRouteCoordinates,
                travelMode: widget.travelMode,
                currentStopIndex: state.currentStopIndex,
                totalStopsCount: state.totalStopsCount,
                currentStopTitle: state.currentStopTitle,
                distanceToCurrentStop: state.distanceToCurrentStop,
                durationToCurrentStop: state.durationToCurrentStop,
                currentStopEta: state.currentStopEta,
                currentSpeedKmh: state.currentSpeedKmh,
                timestamp: DateTime.now(),
              ),
            );
          } catch (_) {}
        }
      });
    });

    // Listen for TTS voice instruction events
    ref.listen(navEventsProvider, (prev, next) {
      next.whenData((event) {
        if (!_isMuted && event is VoiceInstructionEvent) {
          _ttsAdapter?.speak(event.instruction);
        }
      });
    });

    if (_isInitializingRoute) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Fetching route (${widget.travelMode.label})...'),
            ],
          ),
        ),
      );
    }

    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Navigation Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                const SizedBox(height: 16),
                Text(_initError!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: widget.onExit ?? () => Navigator.of(context).pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // 1. MapLibre GL Map View
          MaplibreMap(
            key: ValueKey(effectiveStyle),
            styleString: effectiveStyle,
            onMapCreated: _onMapCreated,
            initialCameraPosition: const CameraPosition(
              target: LatLng(14.5995, 120.9842),
              zoom: 17.5,
              tilt: 55.0,
            ),
            myLocationEnabled: true,
            myLocationTrackingMode: MyLocationTrackingMode.TrackingCompass,
            onCameraTrackingDismissed: () {
              setState(() => _autoFollowCamera = false);
            },
          ),

          // 2. Centered Forward Vehicle Arrow Indicator (Always pointing upwards)
          Center(
            child: IgnorePointer(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary,
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.navigation_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),

          // 3. Top Countdown Turn-by-Turn Instruction Banner
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: navStateAsync.when(
                data: (state) => TurnInstructionBanner(
                  instruction: state.currentInstruction,
                  nextInstruction: state.nextInstruction,
                  distanceMeters: state.distanceToNextTurn,
                  onRecenter: () {
                    setState(() => _autoFollowCamera = true);
                    _updateCamera(
                      state.snappedLocation.latitude,
                      state.snappedLocation.longitude,
                      state.currentBearing,
                    );
                  },
                ),
                loading: () => const SizedBox.shrink(),
                error: (err, st) => Card(
                  color: colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Navigation error: $err'),
                  ),
                ),
              ),
            ),
          ),

          // 4. Bottom Real-Time Speed & Multi-Stop ETA HUD Card
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: navStateAsync.when(
                  data: (state) => Card(
                    elevation: 6,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    color: colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Active Stop Badge
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${state.currentStopTitle ?? 'Stop ${state.currentStopIndex + 1}'} (${state.currentStopIndex + 1}/${state.totalStopsCount})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              // Live Speedometer Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.speed_rounded, size: 14, color: colorScheme.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${state.currentSpeedKmh.round()} km/h',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Stop ETA and Remaining Distance
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'STOP ARRIVAL',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.outline,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_formatEtaClock(state.currentStopEta)} • ${_formatDuration(state.durationToCurrentStop)}',
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                        ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'DISTANCE TO STOP',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.outline,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatDistance(state.distanceToCurrentStop),
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          // Total Trip Summary if multi-stop
                          if (state.totalStopsCount > 1) ...[
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total remaining: ${_formatDistance(state.remainingDistance)} (${_formatDuration(state.remainingDuration)})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (state.isFinalStop)
                                  const Text('Final leg', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),

          // 5. Floating Action Controls (Mute TTS, Telemetry Broadcast, Exit)
          SafeArea(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Mute / Unmute TTS Button
                    FloatingActionButton.small(
                      heroTag: 'mute_btn',
                      backgroundColor: colorScheme.surface,
                      foregroundColor: colorScheme.onSurface,
                      onPressed: () {
                        setState(() => _isMuted = !_isMuted);
                        if (_isMuted) _ttsAdapter?.stop();
                      },
                      child: Icon(_isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                    ),
                    const SizedBox(height: 10),

                    // Broadcasting Button
                    FloatingActionButton.small(
                      heroTag: 'broadcast_btn',
                      backgroundColor: isBroadcasting ? Colors.green : colorScheme.surface,
                      foregroundColor: isBroadcasting ? Colors.white : colorScheme.onSurface,
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => const TelemetryShareSheet(),
                        );
                      },
                      child: Icon(isBroadcasting ? Icons.sensors_rounded : Icons.sensors_off_rounded),
                    ),
                    const SizedBox(height: 10),

                    // Exit Navigation Button
                    if (widget.onClose != null || widget.onExit != null)
                      FloatingActionButton.small(
                        heroTag: 'exit_btn',
                        backgroundColor: colorScheme.error,
                        foregroundColor: colorScheme.onError,
                        onPressed: () {
                          _ttsAdapter?.dispose();
                          (widget.onClose ?? widget.onExit)!();
                        },
                        child: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ttsAdapter?.dispose();
    super.dispose();
  }
}
