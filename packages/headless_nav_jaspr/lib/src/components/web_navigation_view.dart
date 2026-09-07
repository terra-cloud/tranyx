import 'dart:async';
import 'dart:js_interop';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:web/web.dart' as web;
import 'package:headless_nav_core/headless_nav_core.dart';
import '../adapters/web_speech_adapter.dart';
import '../interop/maplibre_interop.dart';
import '../state/jaspr_nav_providers.dart';
import '../storage/web_local_storage_database.dart';
import 'web_turn_banner.dart';
import 'web_follower_view.dart';

/// Driver turn-by-turn navigation component for Jaspr Web with OpenFreeMap,
/// rotating heads-up camera, dynamic polyline pruning, real-time speed/ETA HUD, and Web Speech TTS.
class WebNavigationView extends StatefulComponent {
  final String containerId;

  /// Custom style JSON URL. If provided and [themeAdaptive] is false, this is used.
  final String? styleUrl;

  /// Whether the map style should adapt automatically to the browser theme (light/dark).
  /// Defaults to false (using [lightStyleUrl]).
  final bool themeAdaptive;

  /// Map style URL to use in light mode or when [themeAdaptive] is false.
  /// Defaults to OpenFreeMap Bright style.
  final String lightStyleUrl;

  /// Map style URL to use when [themeAdaptive] is true and dark theme is active.
  /// Defaults to OpenFreeMap Dark style.
  final String darkStyleUrl;

  /// Optional multi-stop waypoints. If provided, [WebNavigationView] will
  /// automatically check local storage, fetch via OSRM FOSSGIS, and run navigation.
  final List<NavWaypoint>? stops;

  /// Travel mode for routing (car, motorcycle, bike, foot).
  final NavTravelMode travelMode;

  /// Optional telemetry channel ID to broadcast to.
  final String? channelId;

  /// Optional callback to close or exit navigation mode.
  /// If neither [onClose] nor [onExit] is provided, the close button is omitted.
  final VoidCallback? onClose;

  /// Optional exit callback to leave navigation mode.
  final VoidCallback? onExit;

  /// Whether spoken voice prompts are enabled via Web Speech API. Defaults to true.
  final bool enableTts;

  /// Primary accent color used for the route polyline, indicator, and card highlights.
  /// Defaults to '#1976D2' (or '#38BDF8' in dark mode).
  final String? accentColor;

  /// Custom route polyline color. If null, [accentColor] is used.
  final String? routeColor;

  /// Custom route casing line color. Defaults to deep blue (#0D47A1) or dark slate (#0F172A).
  final String? routeCasingColor;

  /// Optional live GPS position stream (e.g. from [BrowserGeolocationAdapter.stream]).
  /// If omitted, falls back to [SimulatedLocationProvider] for desktop browser testing.
  final Stream<NavPosition>? locationStream;

  /// Optional telemetry broadcaster. If omitted, falls back to [jasprLocationBroadcasterProvider].
  final LocationBroadcaster? broadcaster;

  /// Optional callback invoked when arriving at a stop or destination,
  /// passing the 1-based stop count index (e.g. 1 for first stop, 2 for second stop).
  final void Function(int stopCount)? onArrived;

  /// Optional custom height. Defaults to 100.vh if null.
  final Unit? height;

  /// Whether the view is embedded in a card/container (uses absolute positioning for overlays).
  final bool isEmbedded;

  /// Whether user gestures (dragging, panning, scrolling) are enabled on the map.
  /// Defaults to true. When set to false, user dragging and panning are disabled.
  final bool isDraggable;

  /// Optional list of interactive action buttons for the navigation card.
  final List<NavAction>? actions;

  /// Custom builder for action buttons within the navigation card.
  final List<Component> Function(BuildContext context, NavigationState? state)? actionsBuilder;

  const WebNavigationView({
    super.key,
    this.containerId = 'headless-nav-map',
    this.stops,
    this.travelMode = NavTravelMode.car,
    this.channelId = 'TRIP-DEMO-101',
    this.locationStream,
    this.broadcaster,
    this.onClose,
    this.onExit,
    this.onArrived,
    this.styleUrl,
    this.themeAdaptive = false,
    this.lightStyleUrl = OpenFreeMapStyles.bright,
    this.darkStyleUrl = OpenFreeMapStyles.dark,
    this.enableTts = true,
    this.accentColor,
    this.routeColor,
    this.routeCasingColor,
    this.height,
    this.isEmbedded = false,
    this.isDraggable = true,
    this.actions,
    this.actionsBuilder,
  });

  @override
  State<WebNavigationView> createState() => _WebNavigationViewState();
}

class _WebNavigationViewState extends State<WebNavigationView> {
  MapLibreMap? _map;
  WebSpeechAdapter? _speechAdapter;
  bool _isMuted = false;
  bool _controlsCollapsed = false;
  bool _isMapLoaded = false;
  bool _routeLayerAdded = false;
  List<List<double>>? _pendingRouteCoords;

  VoidCallback? get _effectiveOnClose => component.onClose ?? component.onExit;
  double _currentCameraBearing = 0.0;
  bool _isFirstCameraUpdate = true;

  NavigationEngine? _engine;
  SimulatedLocationProvider? _sim;
  StreamSubscription<NavigationState>? _stateSub;
  StreamSubscription<NavEvent>? _eventSub;
  NavigationState? _currentState;

  bool _isDarkMode() {
    try {
      return web.window.matchMedia('(prefers-color-scheme: dark)').matches;
    } catch (_) {
      return false;
    }
  }

  bool get _isDark {
    if (component.themeAdaptive) {
      return _isDarkMode();
    }
    final style = component.styleUrl ?? component.lightStyleUrl;
    return style.toLowerCase().contains('dark');
  }

  String get _effectiveAccentColor {
    if (component.accentColor != null && component.accentColor!.isNotEmpty) {
      return component.accentColor!;
    }
    return _isDark ? '#38BDF8' : '#1976D2';
  }

  String get _effectiveRouteColor {
    if (component.routeColor != null && component.routeColor!.isNotEmpty) {
      return component.routeColor!;
    }
    return _effectiveAccentColor;
  }

  String get _effectiveRouteCasingColor {
    if (component.routeCasingColor != null && component.routeCasingColor!.isNotEmpty) {
      return component.routeCasingColor!;
    }
    return _isDark ? '#0F172A' : '#0D47A1';
  }

  String get _effectiveStyle {
    if (component.themeAdaptive) {
      return _isDarkMode() ? component.darkStyleUrl : component.lightStyleUrl;
    }
    return component.styleUrl ?? component.lightStyleUrl;
  }

  bool _isRouteInitialized = false;

  bool get _isMapReady {
    if (_map == null) return false;
    try {
      return _isMapLoaded || (_map?.isStyleLoaded().toDart ?? false);
    } catch (_) {
      return _isMapLoaded;
    }
  }

  web.EventListener? _resizeListener;

  void _setupResizeListener() {
    _resizeListener = (web.Event _) {
      if (_currentState != null) {
        _updateCamera(
          _currentState!.snappedLocation.latitude,
          _currentState!.snappedLocation.longitude,
          _currentState!.currentBearing,
        );
      }
    }.toJS;
    web.window.addEventListener('resize', _resizeListener);
  }

  double _calculateAdaptiveTopPadding() {
    try {
      final container = web.document.getElementById(component.containerId);
      final containerHeight =
          container?.clientHeight.toDouble() ?? web.window.innerHeight.toDouble();
      if (containerHeight <= 0) return 0.0;

      // 1. Direct measurement of the navigation puck element
      final puck = web.document.getElementById('${component.containerId}-puck') ??
          web.document.querySelector('#${component.containerId} ~ .nav-bottom-container .nav-puck-tilt-disc') ??
          web.document.querySelector('.nav-puck-tilt-disc');

      if (puck != null && container != null) {
        final puckRect = puck.getBoundingClientRect();
        final containerRect = container.getBoundingClientRect();

        // Exact vertical center of the puck in container coordinate space
        final puckCenterY =
            (puckRect.top + puckRect.height / 2.0) - containerRect.top;

        // In MapLibre: centerPoint.y = (containerHeight + topPadding) / 2
        // => topPadding = 2 * puckCenterY - containerHeight
        final calculatedPadding = 2.0 * puckCenterY - containerHeight;
        return calculatedPadding.clamp(0.0, containerHeight - 60.0);
      }

      // 2. Direct measurement of the bottom HUD card if puck is still rendering
      final bottomCard = web.document.querySelector('.nav-bottom-card');
      if (bottomCard != null && container != null) {
        final cardRect = bottomCard.getBoundingClientRect();
        final containerRect = container.getBoundingClientRect();
        final cardTop = cardRect.top - containerRect.top;
        // Puck center is 20px margin-bottom + 28px radius (half of 56px disc) above card top
        final puckCenterY = cardTop - 20.0 - 28.0;
        final calculatedPadding = 2.0 * puckCenterY - containerHeight;
        return calculatedPadding.clamp(0.0, containerHeight - 60.0);
      }

      // 3. Adaptive fallback based on screen dimensions and mobile breakpoint
      final isMobile = web.window.innerWidth <= 768;
      // With actions, card is ~220px on mobile (+ 24px bottom + 20px gap + 28px puck radius = ~292px)
      // On desktop, card is ~180px (+ 24px bottom + 20px gap + 28px puck radius = ~252px)
      final estimatedPuckFromBottom = isMobile ? 292.0 : 252.0;
      final fallbackCenterY = containerHeight - estimatedPuckFromBottom;
      final fallbackPadding = 2.0 * fallbackCenterY - containerHeight;
      return fallbackPadding.clamp(0.0, containerHeight - 60.0);
    } catch (_) {
      final windowHeight = web.window.innerHeight.toDouble();
      return (windowHeight - 500.0).clamp(0.0, windowHeight - 60.0);
    }
  }

  void _injectPuckStyles() {
    try {
      if (web.document.getElementById('nav-puck-style') != null) return;
      final styleEl = web.document.createElement('style') as web.HTMLStyleElement;
      styleEl.id = 'nav-puck-style';
      styleEl.textContent = '''
@keyframes navPuckPulse {
  0% {
    transform: rotateX(55deg) scale(0.85);
    opacity: 0.9;
  }
  50% {
    opacity: 0.45;
  }
  100% {
    transform: rotateX(55deg) scale(1.65);
    opacity: 0;
  }
}
''';
      web.document.head?.appendChild(styleEl);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _injectPuckStyles();
    if (component.enableTts) {
      _speechAdapter = WebSpeechAdapter();
    }
    _setupResizeListener();
    Future.microtask(_initMap);
    if (component.stops != null && component.stops!.isNotEmpty) {
      Future.microtask(_initializeRoute);
    }
  }

  void _initMap() {
    try {
      final container = web.document.getElementById(component.containerId);
      if (container == null) {
        web.window.requestAnimationFrame(([JSAny? _]) {
          _initMap();
        }.toJS);
        return;
      }

      final initialCoords = component.stops != null && component.stops!.isNotEmpty
          ? [component.stops!.first.position.longitude.toJS, component.stops!.first.position.latitude.toJS].toJS
          : [120.9842.toJS, 14.5995.toJS].toJS;

      final topPadding = _calculateAdaptiveTopPadding();

      final options = MapOptions(
        container: component.containerId.toJS,
        style: _effectiveStyle.toJS,
        center: initialCoords,
        zoom: 18.5.toJS,
        pitch: 55.toJS,
        bearing: 0.toJS,
        padding: MapPadding(
          top: topPadding.toDouble().toJS,
          bottom: 0.toJS,
          left: 0.toJS,
          right: 0.toJS,
        ),
        attributionControl: false.toJS,
        interactive: component.isDraggable.toJS,
        dragPan: component.isDraggable.toJS,
        scrollZoom: component.isDraggable.toJS,
        dragRotate: component.isDraggable.toJS,
      );
      _map = MapLibreMap(options);

      _map?.on('load'.toJS, ([JSAny? _]) {
        _isMapLoaded = true;
        _onMapReady();
      }.toJS);

      _map?.on('styledata'.toJS, ([JSAny? _]) {
        if (!_routeLayerAdded && _isMapReady) {
          _onMapReady();
        }
      }.toJS);
    } catch (_) {}
  }

  final List<MapLibreMarker> _stopMarkers = [];

  void _clearStopMarkers() {
    for (final marker in _stopMarkers) {
      try {
        marker.remove();
      } catch (_) {}
    }
    _stopMarkers.clear();
  }

  void _addStopMarkers() {
    if (_map == null || !_isMapReady || component.stops == null || component.stops!.isEmpty) return;
    _clearStopMarkers();

    final stops = component.stops!;
    for (int i = 1; i < stops.length; i++) {
      final stop = stops[i];
      final isLast = i == stops.length - 1;

      final pinColor = isLast ? '#D32F2F' : '#1976D2';
      final badgeText = isLast ? '🏁' : '$i';
      final defaultTitle = isLast ? 'Destination' : 'Stop $i';
      final stopTitle = stop.title.isNotEmpty ? stop.title : defaultTitle;

      final el = web.document.createElement('div') as web.HTMLDivElement;
      el.className = 'headless-stop-pin';
      el.innerHTML = '''
<div style="display: flex; flex-direction: column; align-items: center; user-select: none; cursor: pointer; filter: drop-shadow(0 3px 6px rgba(0,0,0,0.35));">
  <div style="
    background: $pinColor;
    color: #ffffff;
    font-weight: 800;
    font-size: 12px;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    min-width: 26px;
    height: 26px;
    padding: 0 5px;
    border-radius: 13px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 2px solid #ffffff;
  ">
    $badgeText
  </div>
  <div style="
    width: 0;
    height: 0;
    border-left: 5px solid transparent;
    border-right: 5px solid transparent;
    border-top: 6px solid $pinColor;
    margin-top: -1px;
  "></div>
  <div style="
    background: rgba(15, 23, 42, 0.88);
    color: #ffffff;
    font-size: 11px;
    font-weight: 600;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    padding: 2px 7px;
    border-radius: 6px;
    margin-top: 3px;
    white-space: nowrap;
    border: 1px solid rgba(255,255,255,0.25);
    box-shadow: 0 2px 4px rgba(0,0,0,0.25);
  ">
    $stopTitle
  </div>
</div>
'''.toJS;

      try {
        final options = {'element': el, 'anchor': 'bottom'}.jsify()! as JSObject;
        final marker = MapLibreMarker(options);
        marker.setLngLat([stop.position.longitude.toJS, stop.position.latitude.toJS].toJS);
        marker.addTo(_map!);
        _stopMarkers.add(marker);
      } catch (e) {
        web.console.error('HeadlessNav: Failed to add stop marker #$i: $e'.toJS);
      }
    }
  }

  void _onMapReady() {
    try {
      _map?.resize();
      if (_pendingRouteCoords != null && _pendingRouteCoords!.isNotEmpty) {
        _displayFullRoute(_pendingRouteCoords!);
      }
      _addStopMarkers();
    } catch (_) {}
  }

  Future<void> _initializeRoute() async {
    if (_isRouteInitialized || component.stops == null || component.stops!.length < 2) return;
    _isRouteInitialized = true;

    final db = WebLocalStorageRouteDatabase();
    final router = OsrmFossgisRouter(database: db);

    try {
      final points = component.stops!.map((wp) => wp.position).toList();
      final payload = await router.getRoute(
        points: points,
        mode: component.travelMode,
      );

      final coords = payload.primaryRoute?.geometryCoordinates ?? [];
      if (coords.isNotEmpty) {
        _displayFullRoute(coords);
      }
      _addStopMarkers();

      final engine = NavigationEngine(
        route: payload,
        waypoints: component.stops,
        onArrived: component.onArrived,
      );
      _engine = engine;

      // Subscribe directly to real-time engine state updates
      _stateSub?.cancel();
      _stateSub = engine.stateStream.listen((state) {
        final wasNull = _currentState == null;
        setState(() {
          _currentState = state;
        });

        if (wasNull) {
          // Allow DOM to mount the puck and bottom card, then align camera with exact measurements
          web.window.requestAnimationFrame(([JSAny? _]) {
            _updateCamera(
              state.snappedLocation.latitude,
              state.snappedLocation.longitude,
              state.currentBearing,
            );
          }.toJS);
        } else {
          _updateCamera(
            state.snappedLocation.latitude,
            state.snappedLocation.longitude,
            state.currentBearing,
          );
        }

        if (state.slicedRouteCoordinates.isNotEmpty) {
          _updateRouteLine(state.slicedRouteCoordinates);
        }

        // Broadcast telemetry for follower subscriber
        if (component.channelId != null) {
          try {
            final broadcaster = component.broadcaster ??
                context.read(jasprLocationBroadcasterProvider);
            broadcaster?.broadcast(
              component.channelId!,
              BroadcasterTelemetry(
                channelId: component.channelId!,
                broadcasterId: 'web-driver',
                rawPosition: state.snappedLocation,
                snappedPosition: state.snappedLocation,
                currentBearing: state.currentBearing,
                remainingDistance: state.remainingDistance,
                remainingDuration: state.remainingDuration,
                currentInstruction: state.currentInstruction,
                routeCoordinates: state.slicedRouteCoordinates,
                travelMode: component.travelMode,
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

      // Subscribe directly to turn-by-turn voice and navigation events
      _eventSub?.cancel();
      _eventSub = engine.eventStream.listen((event) {
        if (!_isMuted && event is VoiceInstructionEvent) {
          _speechAdapter?.speak(event.instruction);
        }
      });

      // If a live locationStream is provided, connect it. Otherwise, use simulation.
      if (component.locationStream != null) {
        engine.start(component.locationStream!);
        web.console.log('HeadlessNav: Live GPS location stream started.'.toJS);
      } else {
        final sim = SimulatedLocationProvider(
          route: payload,
          speedKmh: component.travelMode == NavTravelMode.foot ? 5.0 : 45.0,
          interval: const Duration(milliseconds: 300),
        );
        _sim = sim;
        engine.start(sim.stream());
        web.console.log('HeadlessNav: Route simulation started successfully.'.toJS);
      }

      try {
        context.read(jasprNavEngineProvider.notifier).state = engine;
      } catch (_) {}
    } catch (e, st) {
      web.console.error('HeadlessNav: Route initialization failed: $e'.toJS);
      web.console.error(st.toString().toJS);
    }
  }

  void _displayFullRoute(List<List<double>> coords) {
    if (coords.isEmpty) return;
    _pendingRouteCoords = coords;
    if (_map == null || !_isMapReady) return;

    try {
      final geoJson = {
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {
          'type': 'LineString',
          'coordinates': coords,
        },
      };

      if (_routeLayerAdded) {
        final source = _map?.getSource('route'.toJS);
        source?.setData(geoJson.jsify()!);
        return;
      }

      try {
        _map?.addSource(
          'route'.toJS,
          {
            'type': 'geojson',
            'data': geoJson,
          }.jsify()! as JSObject,
        );

        _map?.addLayer(
          {
            'id': 'route-line-casing',
            'type': 'line',
            'source': 'route',
            'layout': {
              'line-join': 'round',
              'line-cap': 'round',
            },
            'paint': {
              'line-color': _effectiveRouteCasingColor,
              'line-width': 8,
              'line-opacity': 0.75,
            },
          }.jsify()! as JSObject,
        );

        _map?.addLayer(
          {
            'id': 'route-line',
            'type': 'line',
            'source': 'route',
            'layout': {
              'line-join': 'round',
              'line-cap': 'round',
            },
            'paint': {
              'line-color': _effectiveRouteColor,
              'line-width': 6,
              'line-opacity': 0.95,
            },
          }.jsify()! as JSObject,
        );

        _routeLayerAdded = true;
        web.console.log('HeadlessNav: Route layer added successfully.'.toJS);
      } catch (e) {
        // Fallback: If source was already registered, update it
        final source = _map?.getSource('route'.toJS);
        if (source != null) {
          source.setData(geoJson.jsify()!);
          _routeLayerAdded = true;
        } else {
          web.console.warn('HeadlessNav: addSource/addLayer deferred: $e'.toJS);
        }
      }
    } catch (e) {
      web.console.error('HeadlessNav: _displayFullRoute error: $e'.toJS);
    }
  }

  void _updateRouteLine(List<List<double>> remainingCoords) {
    if (_map == null || !_isMapReady || remainingCoords.isEmpty) return;

    try {
      final geoJson = {
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {
          'type': 'LineString',
          'coordinates': remainingCoords,
        },
      };

      if (_routeLayerAdded) {
        final source = _map?.getSource('route'.toJS);
        source?.setData(geoJson.jsify()!);
      } else {
        _displayFullRoute(remainingCoords);
      }
    } catch (e) {
      web.console.error('HeadlessNav: _updateRouteLine error: $e'.toJS);
    }
  }

  void _updateCamera(double lat, double lon, double bearing) {
    if (_map == null) return;
    try {
      final topPadding = _calculateAdaptiveTopPadding();

      if (_isFirstCameraUpdate) {
        _currentCameraBearing = bearing;
        _isFirstCameraUpdate = false;
      } else {
        // Continuous shortest-path angular unwrapping:
        // Calculates delta modulo 360, wrapped to [-180, +180]
        // This ensures the camera turns the shortest angular direction
        // and never does a 360-degree flip spin when crossing North (0°/360°).
        double diff = (bearing - _currentCameraBearing) % 360.0;
        if (diff > 180.0) diff -= 360.0;
        if (diff < -180.0) diff += 360.0;
        _currentCameraBearing += diff;
      }

      _map?.easeTo(
        EaseToOptions(
          center: [lon.toJS, lat.toJS].toJS,
          bearing: _currentCameraBearing.toJS,
          zoom: 18.5.toJS,
          pitch: 55.toJS,
          duration: 450.toJS,
          padding: MapPadding(
            top: topPadding.toDouble().toJS,
            bottom: 0.toJS,
            left: 0.toJS,
            right: 0.toJS,
          ),
        ),
      );
    } catch (e) {
      web.console.error('HeadlessNav: _updateCamera error: $e'.toJS);
    }
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).round();
    if (mins < 60) return '$mins min';
    final hours = mins ~/ 60;
    final remMins = mins % 60;
    return '${hours}h ${remMins}m';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatEtaClock(DateTime eta) {
    final hour = eta.hour > 12 ? eta.hour - 12 : (eta.hour == 0 ? 12 : eta.hour);
    final period = eta.hour >= 12 ? 'PM' : 'AM';
    final minute = eta.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  Component _buildFloatingActionButton({
    required VoidCallback onClick,
    required String svgPath,
    required String title,
    String? iconColor,
    int iconRotationDeg = 0,
    bool isLast = false,
  }) {
    return button(
      onClick: onClick,
      attributes: {'title': title, 'aria-label': title},
      styles: Styles(
        width: 42.px,
        height: 42.px,
        margin: isLast ? Margin.zero : Margin.only(bottom: 10.px),
        radius: BorderRadius.circular(21.px),
        border: Border.all(
          color: _isDark
              ? Color('rgba(255, 255, 255, 0.15)')
              : Color('rgba(0, 0, 0, 0.08)'),
          width: 1.px,
          style: BorderStyle.solid,
        ),
        backgroundColor: _isDark ? Color('rgba(15, 23, 42, 0.92)') : Color('#ffffff'),
        shadow: BoxShadow(
          offsetX: 0.px,
          offsetY: 2.px,
          blur: 8.px,
          color: _isDark ? Color('rgba(0, 0, 0, 0.50)') : Color('#00000020'),
        ),
        cursor: Cursor.pointer,
        display: Display.flex,
        alignItems: AlignItems.center,
        justifyContent: JustifyContent.center,
        raw: {
          'backdrop-filter': 'blur(12px)',
          '-webkit-backdrop-filter': 'blur(12px)',
          'transition': 'all 0.25s cubic-bezier(0.4, 0, 0.2, 1)',
        },
      ),
      [
        svg(
          viewBox: '0 0 24 24',
          width: 20.px,
          height: 20.px,
          styles: Styles(
            raw: {
              'fill': iconColor ?? (_isDark ? '#F8FAFC' : '#1E293B'),
              'transform': 'rotate(${iconRotationDeg}deg)',
              'transition': 'transform 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
            },
          ),
          [
            path([], d: svgPath),
          ],
        ),
      ],
    );
  }

  Component _buildActionButton(NavAction action) {
    return button(
      onClick: action.onClick,
      styles: Styles(
        padding: Padding.symmetric(vertical: 10.px, horizontal: 8.px),
        radius: BorderRadius.circular(12.px),
        border: Border.all(
          color: _isDark ? Color('rgba(255, 255, 255, 0.12)') : Color('rgba(0, 0, 0, 0.08)'),
          width: 1.px,
          style: BorderStyle.solid,
        ),
        backgroundColor: action.isPrimary
            ? Color(_effectiveAccentColor)
            : (_isDark ? Color('rgba(30, 41, 59, 0.80)') : Color('rgba(241, 245, 249, 0.90)')),
        cursor: Cursor.pointer,
        display: Display.flex,
        alignItems: AlignItems.center,
        justifyContent: JustifyContent.center,
        raw: {
          'flex': '1',
          'min-width': '0',
          'gap': '5px',
          'color': action.isPrimary ? '#ffffff' : (_isDark ? '#F8FAFC' : '#0F172A'),
          'font-size': '12px',
          'font-weight': '600',
          'white-space': 'nowrap',
          'overflow': 'hidden',
          'text-overflow': 'ellipsis',
          'pointer-events': 'auto',
        },
      ),
      [
        if (action.iconEmoji != null)
          span(styles: Styles(fontSize: 14.px), [Component.text(action.iconEmoji!)]),
        if (action.iconSvgPath != null)
          svg(
            viewBox: '0 0 24 24',
            width: 16.px,
            height: 16.px,
            styles: Styles(
              raw: {'fill': action.isPrimary ? '#ffffff' : _effectiveAccentColor},
            ),
            [
              path([], d: action.iconSvgPath!),
            ],
          ),
        Component.text(action.label),
        if (action.badge != null && action.badge!.isNotEmpty)
          span(
            styles: Styles(
              margin: Margin.only(left: 4.px),
              padding: Padding.symmetric(horizontal: 6.px, vertical: 1.px),
              radius: BorderRadius.circular(10.px),
              backgroundColor: Color('#EF4444'),
              raw: {
                'color': '#ffffff',
                'font-size': '10px',
                'font-weight': 'bold',
              },
            ),
            [Component.text(action.badge!)],
          ),
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final state = _currentState;
    final actionComponents = component.actionsBuilder?.call(context, state) ??
        component.actions?.map(_buildActionButton).toList();

    return div(
      styles: Styles(
        position: const Position.relative(),
        width: 100.percent,
        height: component.height ?? 100.vh,
        overflow: Overflow.hidden,
      ),
      [
        // 1. Map Canvas Container
        div(
          id: component.containerId,
          styles: Styles(
            width: 100.percent,
            height: 100.percent,
            raw: {
              if (!component.isDraggable) 'pointer-events': 'none',
            },
          ),
          [],
        ),
        // 2. Floating Turn Guidance Banner
        if (state != null)
          WebTurnBanner(
            instruction: state.currentInstruction,
            nextInstruction: state.nextInstruction,
            distanceMeters: state.distanceToNextTurn,
            isDark: _isDark,
            accentColor: _effectiveAccentColor,
            isEmbedded: component.isEmbedded,
          ),

        // 3. Unified Bottom Container: Navigation Indicator (20px above bottom card) + Bottom HUD Card
        if (state != null || (actionComponents != null && actionComponents.isNotEmpty))
          div(
            classes: 'nav-bottom-container',
            styles: Styles(
              position: component.isEmbedded
                  ? Position.absolute(bottom: 24.px, left: 50.percent)
                  : Position.fixed(bottom: 24.px, left: 50.percent),
              zIndex: ZIndex(100),
              transform: Transform.translate(x: (-50).percent),
              display: Display.flex,
              flexDirection: FlexDirection.column,
              alignItems: AlignItems.center,
              pointerEvents: PointerEvents.none,
              width: 90.percent,
              maxWidth: 500.px,
            ),
            [
              // 3a. 3D Tilted Glasslike Circle with Pulsing Effect & Clear Filled Nav Icon (20px above bottom card)
              if (state != null)
                div(
                  id: '${component.containerId}-puck-container',
                  classes: 'nav-puck-tilt-container',
                  styles: Styles(
                    margin: Margin.only(bottom: 20.px),
                    pointerEvents: PointerEvents.none,
                    display: Display.flex,
                    flexDirection: FlexDirection.column,
                    alignItems: AlignItems.center,
                    justifyContent: JustifyContent.center,
                    position: const Position.relative(),
                    raw: {
                      'perspective': '600px',
                      'transform-style': 'preserve-3d',
                    },
                  ),
                  [
                    // Concentric Pulsing Radar Wave Rings (3D Ground-Tilted)
                    div(
                      classes: 'nav-puck-pulse-ring',
                      styles: Styles(
                        position: const Position.absolute(),
                        width: 76.px,
                        height: 76.px,
                        radius: BorderRadius.circular(38.px),
                        border: Border.all(
                          color: Color('${_effectiveAccentColor}70'),
                          width: 1.5.px,
                          style: BorderStyle.solid,
                        ),
                        raw: {
                          'transform': 'rotateX(55deg)',
                          'transform-origin': 'center center',
                          'background': 'radial-gradient(circle, ${_effectiveAccentColor}33 0%, ${_effectiveAccentColor}0a 70%, transparent 100%)',
                          'animation': 'navPuckPulse 2.4s ease-out infinite',
                        },
                      ),
                      [],
                    ),
                    div(
                      classes: 'nav-puck-pulse-ring-outer',
                      styles: Styles(
                        position: const Position.absolute(),
                        width: 96.px,
                        height: 96.px,
                        radius: BorderRadius.circular(48.px),
                        border: Border.all(
                          color: Color('${_effectiveAccentColor}40'),
                          width: 1.px,
                          style: BorderStyle.solid,
                        ),
                        raw: {
                          'transform': 'rotateX(55deg)',
                          'transform-origin': 'center center',
                          'animation': 'navPuckPulse 2.4s ease-out 0.8s infinite',
                        },
                      ),
                      [],
                    ),

                    // 3D Tilted Glasslike Circle Disc (55deg Tilt matching 3D Map Pitch)
                    div(
                      id: '${component.containerId}-puck',
                      classes: 'nav-puck-tilt-disc',
                      styles: Styles(
                        width: 56.px,
                        height: 56.px,
                        radius: BorderRadius.circular(28.px),
                        display: Display.flex,
                        alignItems: AlignItems.center,
                        justifyContent: JustifyContent.center,
                        pointerEvents: PointerEvents.none,
                        border: Border.all(
                          color: _isDark
                              ? Color('rgba(255, 255, 255, 0.35)')
                              : Color('rgba(255, 255, 255, 0.95)'),
                          width: 2.5.px,
                          style: BorderStyle.solid,
                        ),
                        shadow: BoxShadow(
                          offsetX: 0.px,
                          offsetY: 8.px,
                          blur: 24.px,
                          color: _isDark
                              ? Color('rgba(0, 0, 0, 0.75)')
                              : Color('${_effectiveAccentColor}50'),
                        ),
                        raw: {
                          'transform': 'rotateX(55deg)',
                          'transform-origin': 'center center',
                          'backdrop-filter': 'blur(16px)',
                          '-webkit-backdrop-filter': 'blur(16px)',
                          'background': _isDark
                              ? 'radial-gradient(120% 120% at 30% 20%, rgba(30, 41, 59, 0.94) 0%, rgba(15, 23, 42, 0.86) 60%, rgba(2, 6, 23, 0.92) 100%)'
                              : 'radial-gradient(120% 120% at 30% 20%, rgba(255, 255, 255, 0.98) 0%, rgba(224, 242, 254, 0.88) 60%, rgba(186, 230, 253, 0.75) 100%)',
                        },
                      ),
                      [
                        // Clear Filled Aerodynamic Navigation Icon (Points Forward on Tilted Disc)
                        svg(
                          viewBox: '0 0 24 24',
                          width: 28.px,
                          height: 28.px,
                          styles: Styles(
                            raw: {
                              'filter': 'drop-shadow(0 2px 4px rgba(0, 0, 0, 0.35))',
                            },
                          ),
                          [
                            path(
                              [],
                              d: 'M12 2.5L3.5 21.2C3.1 22.0 4.0 22.8 4.8 22.3L12 18.0L19.2 22.3C20.0 22.8 20.9 22.0 20.5 21.2L12 2.5Z',
                              fill: Color(_effectiveAccentColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

              // 3b. Bottom Speed & Stop ETA HUD Card (Theme Adaptive)
              div(
                classes: 'nav-bottom-card',
                styles: Styles(
                  pointerEvents: PointerEvents.auto,
                  width: 100.percent,
                  padding: Padding.all(18.px),
                  radius: BorderRadius.circular(18.px),
                  border: Border.all(
                    color: _isDark
                        ? Color('rgba(255, 255, 255, 0.12)')
                        : Color('rgba(0, 0, 0, 0.08)'),
                    width: 1.px,
                    style: BorderStyle.solid,
                  ),
                  shadow: BoxShadow(
                    offsetX: 0.px,
                    offsetY: 4.px,
                    blur: 16.px,
                    color: _isDark
                        ? Color('rgba(0, 0, 0, 0.55)')
                        : Color('rgba(0, 0, 0, 0.15)'),
                  ),
                  raw: {
                    'backdrop-filter': 'blur(16px)',
                    '-webkit-backdrop-filter': 'blur(16px)',
                    'background': _isDark
                        ? 'rgba(15, 23, 42, 0.92)'
                        : 'rgba(255, 255, 255, 0.96)',
                  },
                ),
                [
                  if (state != null) ...[
                    // Stop & Speed header
                    div(
                      styles: const Styles(
                        display: Display.flex,
                        flexDirection: FlexDirection.row,
                        justifyContent: JustifyContent.spaceBetween,
                        alignItems: AlignItems.center,
                      ),
                      [
                        span(
                          styles: Styles(
                            padding: Padding.symmetric(horizontal: 10.px, vertical: 4.px),
                            radius: BorderRadius.circular(10.px),
                            backgroundColor: _isDark
                                ? Color('rgba(255, 255, 255, 0.10)')
                                : Color('${_effectiveAccentColor}18'),
                            fontSize: 12.px,
                            fontWeight: FontWeight.bold,
                            color: Color(_effectiveAccentColor),
                          ),
                          [
                            Component.text(
                              '${state.currentStopTitle ?? 'Stop'} (${state.currentStopIndex + 1}/${state.totalStopsCount})',
                            ),
                          ],
                        ),
                        span(
                          styles: Styles(
                            padding: Padding.symmetric(horizontal: 10.px, vertical: 4.px),
                            radius: BorderRadius.circular(10.px),
                            backgroundColor: _isDark
                                ? Color('rgba(255, 255, 255, 0.08)')
                                : Color('#F1F5F9'),
                            fontSize: 12.px,
                            fontWeight: FontWeight.bold,
                            color: _isDark ? Color('#F8FAFC') : Color('#1E293B'),
                          ),
                          [Component.text('${state.currentSpeedKmh.round()} km/h')],
                        ),
                      ],
                    ),
                    div(
                      styles: Styles(margin: Margin.only(top: 10.px)),
                      [
                        div(
                          styles: const Styles(
                            display: Display.flex,
                            flexDirection: FlexDirection.row,
                            justifyContent: JustifyContent.spaceBetween,
                            alignItems: AlignItems.center,
                          ),
                          [
                            div(
                              styles: const Styles(
                                display: Display.flex,
                                flexDirection: FlexDirection.column,
                              ),
                              [
                                span(
                                  styles: Styles(
                                    fontSize: 10.px,
                                    fontWeight: FontWeight.bold,
                                    color: _isDark ? Color('#94A3B8') : Color('#64748B'),
                                  ),
                                  [Component.text('STOP ARRIVAL')],
                                ),
                                span(
                                  styles: Styles(
                                    fontSize: 20.px,
                                    fontWeight: FontWeight.bold,
                                    color: Color(_effectiveAccentColor),
                                  ),
                                  [
                                    Component.text(
                                      '${_formatEtaClock(state.currentStopEta)} • ${_formatDuration(state.durationToCurrentStop)}',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            div(
                              styles: const Styles(
                                display: Display.flex,
                                flexDirection: FlexDirection.column,
                                alignItems: AlignItems.end,
                              ),
                              [
                                span(
                                  styles: Styles(
                                    fontSize: 10.px,
                                    fontWeight: FontWeight.bold,
                                    color: _isDark ? Color('#94A3B8') : Color('#64748B'),
                                  ),
                                  [Component.text('DISTANCE TO STOP')],
                                ),
                                span(
                                  styles: Styles(
                                    fontSize: 20.px,
                                    fontWeight: FontWeight.bold,
                                    color: _isDark ? Color('#F8FAFC') : Color('#1E293B'),
                                  ),
                                  [Component.text(_formatDistance(state.distanceToCurrentStop))],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ] else ...[
                    div(
                      styles: const Styles(
                        display: Display.flex,
                        flexDirection: FlexDirection.row,
                        justifyContent: JustifyContent.spaceBetween,
                        alignItems: AlignItems.center,
                      ),
                      [
                        span(
                          styles: Styles(
                            padding: Padding.symmetric(horizontal: 10.px, vertical: 4.px),
                            radius: BorderRadius.circular(10.px),
                            backgroundColor: _isDark
                                ? Color('rgba(255, 255, 255, 0.10)')
                                : Color('${_effectiveAccentColor}18'),
                            fontSize: 12.px,
                            fontWeight: FontWeight.bold,
                            color: Color(_effectiveAccentColor),
                          ),
                          [
                            Component.text(
                              component.stops?.isNotEmpty == true
                                  ? (component.stops!.first.title ?? 'Route Navigation')
                                  : 'Route Navigation',
                            ),
                          ],
                        ),
                        span(
                          styles: Styles(
                            fontSize: 12.px,
                            fontWeight: FontWeight.bold,
                            color: _isDark ? Color('#94A3B8') : Color('#64748B'),
                          ),
                          [Component.text('ACTIVE')],
                        ),
                      ],
                    ),
                  ],

                  // Action Buttons (Rendered if provided)
                  if (actionComponents != null && actionComponents.isNotEmpty)
                    div(
                      styles: Styles(
                        display: Display.flex,
                        flexDirection: FlexDirection.row,
                        margin: Margin.only(top: 14.px),
                        raw: {'gap': '8px'},
                      ),
                      actionComponents,
                    ),
                ],
              ),
            ],
          ),

        // 4. Floating Action Controls (Collapse Toggle, Recenter, Sound/TTS, Close)
        div(
          classes: 'nav-floating-controls',
          styles: Styles(
            position: component.isEmbedded
                ? Position.absolute(top: 112.px, right: 20.px)
                : Position.fixed(top: 112.px, right: 20.px),
            zIndex: ZIndex(110),
            display: Display.flex,
            flexDirection: FlexDirection.column,
            alignItems: AlignItems.center,
          ),
          [
            // Collapse / Expand Toggle
            _buildFloatingActionButton(
              onClick: () {
                setState(() {
                  _controlsCollapsed = !_controlsCollapsed;
                });
              },
              title: _controlsCollapsed ? 'Expand controls' : 'Collapse controls',
              svgPath: 'M12 8l-6 6 1.41 1.41L12 10.83l4.59 4.58L18 14z',
              iconColor: _controlsCollapsed ? null : _effectiveAccentColor,
              iconRotationDeg: _controlsCollapsed ? 180 : 0,
              isLast: _controlsCollapsed,
            ),
            // Smoothly Animated Expandable Action Cluster
            div(
              classes: 'nav-controls-expandable-group',
              styles: Styles(
                display: Display.flex,
                flexDirection: FlexDirection.column,
                alignItems: AlignItems.center,
                raw: {
                  'overflow': 'hidden',
                  'max-height': _controlsCollapsed ? '0px' : '220px',
                  'opacity': _controlsCollapsed ? '0' : '1',
                  'transform': _controlsCollapsed ? 'translateY(-10px) scale(0.92)' : 'translateY(0) scale(1)',
                  'transition': 'max-height 0.35s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.25s ease, transform 0.35s cubic-bezier(0.4, 0, 0.2, 1), padding 0.35s cubic-bezier(0.4, 0, 0.2, 1)',
                  'pointer-events': _controlsCollapsed ? 'none' : 'auto',
                  'padding-top': _controlsCollapsed ? '0px' : '10px',
                },
              ),
              [
                // Recenter Button
                _buildFloatingActionButton(
                  onClick: () {
                    if (state != null) {
                      _updateCamera(
                        state.snappedLocation.latitude,
                        state.snappedLocation.longitude,
                        state.currentBearing,
                      );
                    }
                  },
                  title: 'Recenter on vehicle',
                  svgPath: 'M12 8c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4zm8.94 3c-.46-4.17-3.77-7.48-7.94-7.94V1h-2v2.06C6.83 3.52 3.52 6.83 3.06 11H1v2h2.06c.46 4.17 3.77 7.48 7.94 7.94V23h2v-2.06c4.17-.46 7.48-3.77 7.94-7.94H23v-2h-2.06zM12 19c-3.87 0-7-3.13-7-7s3.13-7 7-7 7 3.13 7 7-3.13 7-7 7z',
                ),
                // Sound / TTS Toggle Button
                _buildFloatingActionButton(
                  onClick: () {
                    setState(() {
                      _isMuted = !_isMuted;
                    });
                    if (_isMuted) _speechAdapter?.stop();
                  },
                  title: _isMuted ? 'Unmute voice guidance' : 'Mute voice guidance',
                  svgPath: _isMuted
                      ? 'M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z'
                      : 'M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z',
                  isLast: true,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    if (_resizeListener != null) {
      web.window.removeEventListener('resize', _resizeListener);
    }
    _clearStopMarkers();
    _stateSub?.cancel();
    _eventSub?.cancel();
    _sim?.stop();
    _engine?.dispose();
    _speechAdapter?.dispose();
    _map?.remove();
    super.dispose();
  }
}
