import 'dart:async';
import 'dart:js_interop';

import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:web/web.dart' as web;
import 'package:headless_nav_core/headless_nav_core.dart';

import '../interop/maplibre_interop.dart';
import '../state/jaspr_nav_providers.dart';

/// An interactive action button displayed on the subscriber tracking card.
class FollowerAction {
  final String label;
  final VoidCallback onClick;
  final String? iconSvgPath;
  final String? iconEmoji;
  final bool isPrimary;
  final String? badge;

  const FollowerAction({
    required this.label,
    required this.onClick,
    this.iconSvgPath,
    this.iconEmoji,
    this.isPrimary = false,
    this.badge,
  });
}

/// Unified alias for navigation action buttons.
typedef NavAction = FollowerAction;

/// Live vehicle tracking view for followers/subscribers in Jaspr Web.
///
/// Features dynamic bearing rotation for the broadcaster's icon, multi-stop route display,
/// real-time arrival metrics, and a fully customizable subscriber card.
class WebFollowerView extends StatefulComponent {
  final String channelId;
  final String containerId;

  /// Custom icon image or emoji for the vehicle marker (optional).
  final String? vehicleIcon;

  /// Custom marker image URL or base64 data URI (e.g. PNG, SVG, WebP).
  /// If provided, this image is used as the driver's location marker.
  final String? customMarkerUrl;

  /// Custom inline SVG markup string (e.g. `'<svg>...</svg>'`) to use as the driver marker.
  final String? customMarkerSvg;

  /// Custom HTML string for complete control over the driver marker DOM element.
  final String? customMarkerHtml;

  /// Size of the driver marker pin in pixels. Defaults to 44.0.
  final double markerSize;

  /// Primary color for the default location pin. If null, [accentColor] is used.
  final String? pinColor;

  /// Optional multi-stop waypoints for the journey being tracked.
  final List<NavWaypoint>? stops;

  /// Travel profile (car, motorcycle, bike, foot).
  final NavTravelMode travelMode;

  /// Primary accent color used for route polyline and card highlights.
  final String? accentColor;

  /// Custom route polyline color. If null, [accentColor] is used.
  final String? routeColor;

  /// Custom route casing line color.
  final String? routeCasingColor;

  /// Optional broadcaster/entity title (e.g. "Alex D.", "Delivery Courier", "Bus 42").
  /// If provided, shown in the default card header.
  final String? broadcasterTitle;

  /// Optional broadcaster/entity subtitle (e.g. "Toyota Prius • NCF-8921", "Order #4920").
  final String? broadcasterSubtitle;

  /// Optional rating or badge score (e.g. "★ 4.95").
  final String? broadcasterBadge;

  /// Optional custom status text (defaults to 'EN ROUTE' or 'ARRIVED').
  final String? statusText;

  /// Optional list of interactive action buttons for the default card.
  final List<FollowerAction>? actions;

  /// Complete customization builder for the bottom subscriber card.
  /// If provided, overrides the default HUD card and gives the developer full control
  /// over layout, typography, and live telemetry data display.
  final Component Function(BuildContext context, BroadcasterTelemetry? telemetry)? cardBuilder;

  /// Custom builder for action buttons within the default card.
  final List<Component> Function(BuildContext context, BroadcasterTelemetry? telemetry)? actionsBuilder;

  /// Custom builder for the top tracking header bar.
  final Component Function(BuildContext context, BroadcasterTelemetry? telemetry)? headerBuilder;

  /// Whether to run background driver simulation if no external broadcaster is streaming.
  final bool autoSimulateIfIdle;

  /// Optional custom streaming backend (e.g. [WSLocationStreaming], [SupabaseLocationStreaming]).
  /// If omitted, falls back to [jasprLocationStreamingProvider].
  final LocationStreaming? streaming;

  /// Optional custom broadcaster (used if [autoSimulateIfIdle] runs simulated telemetry).
  /// If omitted, falls back to [jasprLocationBroadcasterProvider].
  final LocationBroadcaster? broadcaster;

  /// Custom style JSON URL. If provided and [themeAdaptive] is false, this is used.
  final String? styleUrl;

  /// Whether the map style should adapt automatically to the browser theme (light/dark).
  final bool themeAdaptive;

  /// Map style URL to use in light mode or when [themeAdaptive] is false.
  final String lightStyleUrl;

  /// Map style URL to use when [themeAdaptive] is true and dark theme is active.
  final String darkStyleUrl;

  /// Optional callback to close or exit follower mode.
  /// If neither [onClose] nor [onExit] is provided, the close button is omitted.
  final VoidCallback? onClose;

  /// Optional callback to exit follower mode.
  final VoidCallback? onExit;

  /// Optional custom height. Defaults to 100.vh if null.
  final Unit? height;

  /// Whether the view is embedded in a card/container (uses absolute positioning for overlays).
  final bool isEmbedded;

  /// Whether user gestures (dragging, panning, scrolling) are enabled on the map.
  /// Defaults to true. When set to false, the map becomes a non-draggable tracking display.
  final bool isDraggable;

  const WebFollowerView({
    super.key,
    required this.channelId,
    this.containerId = 'headless-follower-map',
    this.vehicleIcon,
    this.customMarkerUrl,
    this.customMarkerSvg,
    this.customMarkerHtml,
    this.markerSize = 44.0,
    this.pinColor,
    this.stops,
    this.travelMode = NavTravelMode.car,
    this.accentColor,
    this.routeColor,
    this.routeCasingColor,
    this.broadcasterTitle,
    this.broadcasterSubtitle,
    this.broadcasterBadge,
    this.statusText,
    this.actions,
    this.cardBuilder,
    this.actionsBuilder,
    this.headerBuilder,
    this.streaming,
    this.broadcaster,
    this.autoSimulateIfIdle = true,
    this.onClose,
    this.onExit,
    this.styleUrl,
    this.themeAdaptive = false,
    this.lightStyleUrl = OpenFreeMapStyles.bright,
    this.darkStyleUrl = OpenFreeMapStyles.dark,
    this.height,
    this.isEmbedded = false,
    this.isDraggable = true,
  });

  @override
  State<WebFollowerView> createState() => _WebFollowerViewState();
}

class _WebFollowerViewState extends State<WebFollowerView> {
  MapLibreMap? _map;
  MapLibreMarker? _vehicleMarker;
  bool _isMapLoaded = false;
  bool _routeLayerAdded = false;
  List<List<double>>? _pendingRouteCoords;
  StreamSubscription<BroadcasterTelemetry>? _telemetrySub;
  BroadcasterTelemetry? _currentTelemetry;

  NavigationEngine? _simEngine;
  SimulatedLocationProvider? _sim;
  final List<MapLibreMarker> _stopMarkers = [];
  final bool _autoFollowCamera = true;
  String? _actionToast;
  Timer? _toastTimer;

  VoidCallback? get _effectiveOnClose => component.onClose ?? component.onExit;

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

  @override
  void initState() {
    super.initState();
    Future.microtask(_initMap);
    Future.microtask(_subscribeTelemetry);
    if (component.stops != null && component.stops!.isNotEmpty) {
      Future.microtask(_initRouteAndSimulation);
    }
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _sim?.stop();
    _simEngine?.dispose();
    _clearStopMarkers();
    _vehicleMarker?.remove();
    _map?.remove();
    _telemetrySub?.cancel();
    super.dispose();
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() {
      _actionToast = message;
    });
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _actionToast = null;
        });
      }
    });
  }

  void _subscribeTelemetry() {
    try {
      final streaming = component.streaming ??
          context.read(jasprLocationStreamingProvider);
      _telemetrySub?.cancel();
      _telemetrySub = streaming?.stream(component.channelId).listen((telemetry) {
        final pos = telemetry.snappedPosition ?? telemetry.rawPosition;
        _updateFollower(pos.latitude, pos.longitude, telemetry.currentBearing);
        final routeCoords = telemetry.routeCoordinates;
        if (routeCoords != null && routeCoords.isNotEmpty) {
          _updateRouteLine(routeCoords);
        }
        setState(() {
          _currentTelemetry = telemetry;
        });
      });
    } catch (_) {}
  }

  Future<void> _initRouteAndSimulation() async {
    if (component.stops == null || component.stops!.isEmpty) return;

    try {
      final router = context.read(jasprOsrmRouterProvider);
      final waypoints = component.stops!;
      final points = waypoints.map((w) => w.position).toList();

      final payload = await router.getRoute(
        points: points,
        mode: component.travelMode,
      );

      final coords = payload.primaryRoute?.geometryCoordinates ?? [];
      if (coords.isNotEmpty) {
        _pendingRouteCoords = coords;
        if (_isMapLoaded) {
          _displayFullRoute(coords);
          _addStopMarkers();
        }
      }

      // Auto-simulate driver movement along route if enabled
      if (component.autoSimulateIfIdle) {
        final engine = NavigationEngine(
          route: payload,
          waypoints: component.stops,
        );
        _simEngine = engine;

        final sim = SimulatedLocationProvider(
          route: payload,
          speedKmh: component.travelMode == NavTravelMode.foot ? 5.0 : 45.0,
          interval: const Duration(milliseconds: 350),
        );
        _sim = sim;

        engine.stateStream.listen((state) {
          try {
            final broadcaster = component.broadcaster ??
                context.read(jasprLocationBroadcasterProvider);
            broadcaster?.broadcast(
              component.channelId,
              BroadcasterTelemetry(
                channelId: component.channelId,
                broadcasterId: 'simulated-driver',
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
        });

        engine.start(sim.stream());
      }
    } catch (e) {
      web.console.error('HeadlessFollower: _initRouteAndSimulation error: $e'.toJS);
    }
  }

  void _initMap() {
    try {
      final container = web.document.getElementById(component.containerId);
      if (container == null) {
        web.window.requestAnimationFrame(
          ([JSAny? _]) {
            _initMap();
          }.toJS,
        );
        return;
      }

      final initialCoords = component.stops != null && component.stops!.isNotEmpty
          ? [component.stops!.first.position.longitude.toJS, component.stops!.first.position.latitude.toJS].toJS
          : [120.9842.toJS, 14.5995.toJS].toJS;

      final options = MapOptions(
        container: component.containerId.toJS,
        style: _effectiveStyle.toJS,
        center: initialCoords,
        zoom: 14.8.toJS,
        pitch: 35.toJS,
        bearing: 0.toJS,
        attributionControl: false.toJS,
        interactive: component.isDraggable.toJS,
        dragPan: component.isDraggable.toJS,
        scrollZoom: component.isDraggable.toJS,
        dragRotate: component.isDraggable.toJS,
      );
      _map = MapLibreMap(options);

      _map?.on(
        'load'.toJS,
        ([JSAny? _]) {
          _isMapLoaded = true;
          _map?.resize();
          if (_pendingRouteCoords != null && _pendingRouteCoords!.isNotEmpty) {
            _displayFullRoute(_pendingRouteCoords!);
          }
          _addStopMarkers();
        }.toJS,
      );

      _map?.on(
        'styledata'.toJS,
        ([JSAny? _]) {
          if (!_routeLayerAdded && _isMapLoaded) {
            if (_pendingRouteCoords != null && _pendingRouteCoords!.isNotEmpty) {
              _displayFullRoute(_pendingRouteCoords!);
            }
            _addStopMarkers();
          }
        }.toJS,
      );
    } catch (_) {}
  }

  void _clearStopMarkers() {
    for (final marker in _stopMarkers) {
      try {
        marker.remove();
      } catch (_) {}
    }
    _stopMarkers.clear();
  }

  void _addStopMarkers() {
    if (_map == null || !_isMapLoaded || component.stops == null || component.stops!.isEmpty) return;
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
      el.className = 'follower-stop-pin';
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
    padding: 0 6px;
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
  "></div>
  <div style="
    background: ${_isDark ? 'rgba(15, 23, 42, 0.90)' : 'rgba(255, 255, 255, 0.95)'};
    color: ${_isDark ? '#F8FAFC' : '#0F172A'};
    font-size: 10px;
    font-weight: 700;
    padding: 2px 6px;
    border-radius: 6px;
    margin-top: 2px;
    white-space: nowrap;
    box-shadow: 0 2px 4px rgba(0,0,0,0.25);
    border: 1px solid ${_isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.06)'};
  ">
    $stopTitle
  </div>
</div>
'''.toJS;
      try {
        final marker = MapLibreMarker({'element': el}.jsify()! as JSObject);
        marker.setLngLat([stop.position.longitude.toJS, stop.position.latitude.toJS].toJS);
        marker.addTo(_map!);
        _stopMarkers.add(marker);
      } catch (_) {}
    }
  }

  void _updateFollower(double lat, double lon, double? bearing) {
    if (_map == null || !_isMapLoaded) return;
    try {
      if (_autoFollowCamera) {
        _map?.easeTo(
          EaseToOptions(
            center: [lon.toJS, lat.toJS].toJS,
            bearing: 0.toJS, // Subscriber view stays North-up
            zoom: 16.2.toJS,
            pitch: 35.toJS,
            duration: 400.toJS,
          ),
        );
      }

      if (_vehicleMarker == null) {
        final el = web.document.createElement('div') as web.HTMLDivElement;
        el.className = 'follower-vehicle-marker';
        el.innerHTML = _buildMarkerHtml().toJS;
        final marker = MapLibreMarker({'element': el}.jsify()! as JSObject);
        marker.setLngLat([lon.toJS, lat.toJS].toJS);
        if (bearing != null) {
          marker.setRotation(bearing.toJS);
        }
        marker.addTo(_map!);
        _vehicleMarker = marker;
      } else {
        _vehicleMarker?.setLngLat([lon.toJS, lat.toJS].toJS);
        if (bearing != null) {
          _vehicleMarker?.setRotation(bearing.toJS);
        }
      }
    } catch (_) {}
  }

  /// Builds the HTML representation of the driver's location marker.
  /// Supports custom HTML, inline SVG, image URLs/base64 (PNG, SVG, WebP),
  /// or a sleek, modern vector location pin by default (replacing cartoon icons).
  String _buildMarkerHtml() {
    final size = component.markerSize;

    if (component.customMarkerHtml != null &&
        component.customMarkerHtml!.isNotEmpty) {
      return component.customMarkerHtml!;
    }

    if (component.customMarkerSvg != null &&
        component.customMarkerSvg!.isNotEmpty) {
      return '''
<div style="
  width: ${size}px;
  height: ${size}px;
  display: flex;
  align-items: center;
  justify-content: center;
  filter: drop-shadow(0 3px 6px rgba(0,0,0,0.35));
  transition: transform 0.35s cubic-bezier(0.4, 0, 0.2, 1);
">
  ${component.customMarkerSvg}
</div>
''';
    }

    if (component.customMarkerUrl != null &&
        component.customMarkerUrl!.isNotEmpty) {
      return '''
<img src="${component.customMarkerUrl}" alt="Driver" style="
  width: ${size}px;
  height: ${size}px;
  object-fit: contain;
  filter: drop-shadow(0 3px 6px rgba(0,0,0,0.35));
  display: block;
  user-select: none;
  pointer-events: none;
  transition: transform 0.35s cubic-bezier(0.4, 0, 0.2, 1);
" />
''';
    }

    if (component.vehicleIcon != null && component.vehicleIcon!.isNotEmpty) {
      return '''
<div style="
  display: flex;
  align-items: center;
  justify-content: center;
  width: ${size}px;
  height: ${size}px;
  border-radius: 50%;
  background: ${_isDark ? 'rgba(15, 23, 42, 0.95)' : 'rgba(255, 255, 255, 0.98)'};
  border: 2.5px solid $_effectiveAccentColor;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.45);
  font-size: 24px;
  user-select: none;
  transition: transform 0.35s cubic-bezier(0.4, 0, 0.2, 1);
">
  ${component.vehicleIcon}
</div>
''';
    }

    // Default: Professional, sleek location pin / navigation puck (non-cartoonish)
    final pinColor = component.pinColor ?? _effectiveAccentColor;
    final haloColor = _isDark ? '#0F172A' : '#FFFFFF';
    final ringStroke =
        _isDark ? 'rgba(255,255,255,0.25)' : 'rgba(0,0,0,0.12)';

    return '''
<svg width="$size" height="$size" viewBox="0 0 44 44" fill="none" xmlns="http://www.w3.org/2000/svg" style="
  display: block;
  filter: drop-shadow(0 3px 8px rgba(0,0,0,0.40));
  transition: transform 0.35s cubic-bezier(0.4, 0, 0.2, 1);
">
  <!-- Outer High-Contrast Halo -->
  <circle cx="22" cy="22" r="19" fill="$haloColor" stroke="$ringStroke" stroke-width="2"/>
  <!-- Primary Accent Core -->
  <circle cx="22" cy="22" r="14" fill="$pinColor"/>
  <!-- Directional Heading Arrow pointing North (0 deg) -->
  <polygon points="22,10 29,26.5 22,23 15,26.5" fill="#FFFFFF"/>
</svg>
''';
  }

  void _displayFullRoute(List<List<double>> coords) {
    if (coords.isEmpty || _map == null || !_isMapLoaded) return;
    _pendingRouteCoords = coords;

    try {
      final geoJson = {
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {'type': 'LineString', 'coordinates': coords},
      };

      if (_routeLayerAdded) {
        final source = _map?.getSource('follower-route'.toJS);
        source?.setData(geoJson.jsify()!);
        return;
      }

      _map?.addSource(
        'follower-route'.toJS,
        {'type': 'geojson', 'data': geoJson}.jsify()! as JSObject,
      );

      _map?.addLayer(
        {
          'id': 'follower-route-casing',
          'type': 'line',
          'source': 'follower-route',
          'layout': {'line-join': 'round', 'line-cap': 'round'},
          'paint': {
            'line-color': _effectiveRouteCasingColor,
            'line-width': 9,
            'line-opacity': 0.85,
          },
        }.jsify()! as JSObject,
      );

      _map?.addLayer(
        {
          'id': 'follower-route-line',
          'type': 'line',
          'source': 'follower-route',
          'layout': {'line-join': 'round', 'line-cap': 'round'},
          'paint': {
            'line-color': _effectiveRouteColor,
            'line-width': 5.5,
            'line-opacity': 0.95,
          },
        }.jsify()! as JSObject,
      );

      _routeLayerAdded = true;
    } catch (e) {
      web.console.warn('HeadlessFollower: _displayFullRoute error: $e'.toJS);
    }
  }

  void _updateRouteLine(List<List<double>> coords) {
    if (coords.isEmpty || _map == null || !_isMapLoaded) return;
    try {
      final geoJson = {
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {'type': 'LineString', 'coordinates': coords},
      };

      if (_routeLayerAdded) {
        final source = _map?.getSource('follower-route'.toJS);
        source?.setData(geoJson.jsify()!);
      } else {
        _displayFullRoute(coords);
      }
    } catch (_) {}
  }

  String _formatDuration(double? seconds) {
    if (seconds == null) return '-- min';
    final mins = (seconds / 60).round();
    if (mins < 60) return '$mins min';
    final hours = mins ~/ 60;
    final remMins = mins % 60;
    return '${hours}h ${remMins}m';
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '-- km';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatEtaClock(DateTime? eta) {
    if (eta == null) return '--:--';
    final hour = eta.hour > 12
        ? eta.hour - 12
        : (eta.hour == 0 ? 12 : eta.hour);
    final period = eta.hour >= 12 ? 'PM' : 'AM';
    final minute = eta.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  Component _buildActionButton(FollowerAction action) {
    return button(
      onClick: action.onClick,
      styles: Styles(
        padding: Padding.symmetric(vertical: 10.px),
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
          'gap': '6px',
          'color': action.isPrimary ? '#ffffff' : (_isDark ? '#F8FAFC' : '#0F172A'),
          'font-size': '13px',
          'font-weight': '600',
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

  Component _buildDefaultCard(BuildContext context, BroadcasterTelemetry? telemetry) {
    final currentStopIndex = telemetry?.currentStopIndex ?? 0;
    final totalStops = telemetry?.totalStopsCount ??
        (component.stops != null && component.stops!.length > 1
            ? component.stops!.length - 1
            : (component.stops?.length ?? 1));
    final currentStopTitle = telemetry?.currentStopTitle ??
        (component.stops != null && currentStopIndex + 1 < component.stops!.length
            ? component.stops![currentStopIndex + 1].title
            : (component.stops != null && currentStopIndex < component.stops!.length
                ? component.stops![currentStopIndex].title
                : 'Destination'));
    final hasArrived = (telemetry?.remainingDistance != null && telemetry!.remainingDistance! <= 15.0);
    final status = component.statusText ?? (hasArrived ? 'ARRIVED' : 'EN ROUTE');

    final actionComponents = component.actionsBuilder?.call(context, telemetry) ??
        component.actions?.map(_buildActionButton).toList();

    return div(
      styles: Styles(
        position: component.isEmbedded
            ? Position.absolute(bottom: 20.px, left: 50.percent)
            : Position.fixed(bottom: 20.px, left: 50.percent),
        zIndex: ZIndex(100),
        transform: Transform.translate(x: (-50).percent),
        width: 92.percent,
        maxWidth: 520.px,
        padding: Padding.all(20.px),
        radius: BorderRadius.circular(22.px),
        border: Border.all(
          color: _isDark ? Color('rgba(255, 255, 255, 0.12)') : Color('rgba(0, 0, 0, 0.08)'),
          width: 1.px,
          style: BorderStyle.solid,
        ),
        shadow: BoxShadow(
          offsetX: 0.px,
          offsetY: 8.px,
          blur: 28.px,
          color: _isDark ? Color('rgba(0, 0, 0, 0.65)') : Color('rgba(0, 0, 0, 0.18)'),
        ),
        raw: {
          'backdrop-filter': 'blur(20px)',
          '-webkit-backdrop-filter': 'blur(20px)',
          'background': _isDark
              ? 'rgba(15, 23, 42, 0.94)'
              : 'rgba(255, 255, 255, 0.96)',
          'display': 'flex',
          'flex-direction': 'column',
          'gap': '14px',
        },
      ),
      [
        // 1. Broadcaster Header (if broadcasterTitle is provided)
        if (component.broadcasterTitle != null)
          div(
            styles: Styles(
              display: Display.flex,
              flexDirection: FlexDirection.row,
              justifyContent: JustifyContent.spaceBetween,
              alignItems: AlignItems.center,
            ),
            [
              div(
                styles: Styles(
                  display: Display.flex,
                  flexDirection: FlexDirection.row,
                  alignItems: AlignItems.center,
                  raw: {'gap': '12px'},
                ),
                [
                  div(
                    styles: Styles(
                      width: 44.px,
                      height: 44.px,
                      radius: BorderRadius.circular(22.px),
                      backgroundColor: Color(_effectiveAccentColor),
                      display: Display.flex,
                      alignItems: AlignItems.center,
                      justifyContent: JustifyContent.center,
                      shadow: BoxShadow(
                        offsetX: 0.px,
                        offsetY: 3.px,
                        blur: 8.px,
                        color: Color('${_effectiveAccentColor}66'),
                      ),
                    ),
                    [
                      span(
                        styles: Styles(
                          fontSize: 16.px,
                          fontWeight: FontWeight.bold,
                          color: Color('#ffffff'),
                        ),
                        [
                          Component.text(
                            component.broadcasterTitle!.isNotEmpty
                                ? component.broadcasterTitle![0].toUpperCase()
                                : '📍',
                          ),
                        ],
                      ),
                    ],
                  ),
                  div(
                    styles: Styles(
                      display: Display.flex,
                      flexDirection: FlexDirection.column,
                    ),
                    [
                      div(
                        styles: Styles(
                          display: Display.flex,
                          flexDirection: FlexDirection.row,
                          alignItems: AlignItems.center,
                          raw: {'gap': '6px'},
                        ),
                        [
                          span(
                            styles: Styles(
                              fontSize: 16.px,
                              fontWeight: FontWeight.bold,
                              color: _isDark ? Color('#F8FAFC') : Color('#0F172A'),
                            ),
                            [Component.text(component.broadcasterTitle!)],
                          ),
                          if (component.broadcasterBadge != null)
                            span(
                              styles: Styles(
                                fontSize: 13.px,
                                fontWeight: FontWeight.bold,
                                color: Color('#F59E0B'),
                              ),
                              [Component.text(component.broadcasterBadge!)],
                            ),
                        ],
                      ),
                      if (component.broadcasterSubtitle != null)
                        span(
                          styles: Styles(
                            fontSize: 12.px,
                            color: _isDark ? Color('#94A3B8') : Color('#64748B'),
                          ),
                          [Component.text(component.broadcasterSubtitle!)],
                        ),
                    ],
                  ),
                ],
              ),

              // Status Badge
              div(
                styles: Styles(
                  padding: Padding.symmetric(horizontal: 10.px, vertical: 5.px),
                  radius: BorderRadius.circular(12.px),
                  backgroundColor: hasArrived
                      ? Color('rgba(59, 130, 246, 0.15)')
                      : Color('rgba(16, 185, 129, 0.15)'),
                  border: Border.all(
                    color: hasArrived
                        ? Color('rgba(59, 130, 246, 0.35)')
                        : Color('rgba(16, 185, 129, 0.35)'),
                    width: 1.px,
                    style: BorderStyle.solid,
                  ),
                ),
                [
                  span(
                    styles: Styles(
                      fontSize: 11.px,
                      fontWeight: FontWeight.bold,
                      color: hasArrived ? Color('#3B82F6') : Color('#10B981'),
                      raw: {'letter-spacing': '0.5px'},
                    ),
                    [Component.text(status)],
                  ),
                ],
              ),
            ],
          ),

        // 2. Current Stop / Target Header
        div(
          styles: Styles(
            padding: Padding.all(10.px),
            radius: BorderRadius.circular(12.px),
            backgroundColor: _isDark ? Color('rgba(30, 41, 59, 0.60)') : Color('rgba(241, 245, 249, 0.85)'),
            display: Display.flex,
            flexDirection: FlexDirection.row,
            justifyContent: JustifyContent.spaceBetween,
            alignItems: AlignItems.center,
          ),
          [
            div(
              styles: Styles(
                display: Display.flex,
                flexDirection: FlexDirection.row,
                alignItems: AlignItems.center,
                raw: {'gap': '8px'},
              ),
              [
                span(styles: Styles(fontSize: 16.px), [Component.text('📍')]),
                span(
                  styles: Styles(
                    fontSize: 13.px,
                    fontWeight: FontWeight.bold,
                    color: _isDark ? Color('#F8FAFC') : Color('#0F172A'),
                  ),
                  [Component.text(currentStopTitle.isNotEmpty ? currentStopTitle : 'Destination')],
                ),
              ],
            ),
            if (totalStops > 1)
              span(
                styles: Styles(
                  fontSize: 12.px,
                  fontWeight: FontWeight.bold,
                  color: Color(_effectiveAccentColor),
                ),
                [Component.text('Stop ${currentStopIndex + 1} of $totalStops')],
              )
            else if (component.broadcasterTitle == null)
              div(
                styles: Styles(
                  padding: Padding.symmetric(horizontal: 8.px, vertical: 3.px),
                  radius: BorderRadius.circular(8.px),
                  backgroundColor: hasArrived
                      ? Color('rgba(59, 130, 246, 0.15)')
                      : Color('rgba(16, 185, 129, 0.15)'),
                ),
                [
                  span(
                    styles: Styles(
                      fontSize: 10.px,
                      fontWeight: FontWeight.bold,
                      color: hasArrived ? Color('#3B82F6') : Color('#10B981'),
                    ),
                    [Component.text(status)],
                  ),
                ],
              ),
          ],
        ),

        // 3. Core Live Arrival Metrics (ETA, Remaining Duration, Distance, Speed)
        div(
          styles: Styles(
            display: Display.flex,
            flexDirection: FlexDirection.row,
            justifyContent: JustifyContent.spaceBetween,
            alignItems: AlignItems.end,
          ),
          [
            div(
              styles: Styles(
                display: Display.flex,
                flexDirection: FlexDirection.column,
              ),
              [
                span(
                  styles: Styles(
                    fontSize: 11.px,
                    fontWeight: FontWeight.bold,
                    color: _isDark ? Color('#94A3B8') : Color('#64748B'),
                    raw: {'letter-spacing': '0.5px'},
                  ),
                  [Component.text('ESTIMATED ARRIVAL')],
                ),
                div(
                  styles: Styles(
                    display: Display.flex,
                    flexDirection: FlexDirection.row,
                    alignItems: AlignItems.baseline,
                    raw: {'gap': '8px'},
                  ),
                  [
                    span(
                      styles: Styles(
                        fontSize: 26.px,
                        fontWeight: FontWeight.bold,
                        color: _isDark ? Color('#38BDF8') : Color('#1976D2'),
                      ),
                      [
                        Component.text(
                          telemetry?.currentStopEta != null
                              ? _formatEtaClock(telemetry!.currentStopEta!)
                              : (telemetry != null ? 'In ${_formatDuration(telemetry.remainingDuration)}' : 'Calculating...'),
                        ),
                      ],
                    ),
                    if (telemetry != null && telemetry.remainingDuration != null)
                      span(
                        styles: Styles(
                          fontSize: 13.px,
                          fontWeight: FontWeight.bold,
                          color: _isDark ? Color('#94A3B8') : Color('#64748B'),
                        ),
                        [Component.text('(${_formatDuration(telemetry.remainingDuration)})')],
                      ),
                  ],
                ),
              ],
            ),

            div(
              styles: Styles(
                display: Display.flex,
                flexDirection: FlexDirection.row,
                raw: {'gap': '12px'},
              ),
              [
                div(
                  styles: Styles(
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
                      [Component.text('REMAINING')],
                    ),
                    span(
                      styles: Styles(
                        fontSize: 15.px,
                        fontWeight: FontWeight.bold,
                        color: _isDark ? Color('#F8FAFC') : Color('#0F172A'),
                      ),
                      [Component.text(_formatDistance(telemetry?.remainingDistance))],
                    ),
                  ],
                ),

                div(
                  styles: Styles(
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
                      [Component.text('SPEED')],
                    ),
                    span(
                      styles: Styles(
                        fontSize: 15.px,
                        fontWeight: FontWeight.bold,
                        color: _isDark ? Color('#F8FAFC') : Color('#0F172A'),
                      ),
                      [Component.text('${telemetry?.currentSpeedKmh?.round() ?? 0} km/h')],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        // 4. Action Buttons (Rendered only if provided)
        if (actionComponents != null && actionComponents.isNotEmpty)
          div(
            styles: Styles(
              display: Display.flex,
              flexDirection: FlexDirection.row,
              margin: Margin.only(top: 4.px),
              raw: {'gap': '10px'},
            ),
            actionComponents,
          ),
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final telemetry = _currentTelemetry;

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

        // 2. Top Header Bar (Default or Custom Header Builder)
        if (component.headerBuilder != null)
          component.headerBuilder!(context, telemetry)
        else
          div(
            styles: Styles(
              position: component.isEmbedded
                  ? Position.absolute(top: 20.px, left: 20.px)
                  : Position.fixed(top: 20.px, left: 20.px),
              zIndex: ZIndex(100),
              display: Display.flex,
              alignItems: AlignItems.center,
              raw: {'gap': '10px'},
            ),
            [
              // Live Status Pill
              div(
                styles: Styles(
                  padding: Padding.symmetric(horizontal: 14.px, vertical: 8.px),
                  radius: BorderRadius.circular(24.px),
                  border: Border.all(
                    color: _isDark ? Color('rgba(255, 255, 255, 0.15)') : Color('rgba(0, 0, 0, 0.08)'),
                    width: 1.px,
                    style: BorderStyle.solid,
                  ),
                  shadow: BoxShadow(
                    offsetX: 0.px,
                    offsetY: 4.px,
                    blur: 14.px,
                    color: _isDark ? Color('rgba(0, 0, 0, 0.55)') : Color('rgba(0, 0, 0, 0.15)'),
                  ),
                  raw: {
                    'backdrop-filter': 'blur(16px)',
                    '-webkit-backdrop-filter': 'blur(16px)',
                    'background': _isDark ? 'rgba(15, 23, 42, 0.92)' : 'rgba(255, 255, 255, 0.95)',
                    'display': 'flex',
                    'align-items': 'center',
                    'gap': '8px',
                  },
                ),
                [
                  // Pulsing Green Live Indicator
                  div(
                    styles: Styles(
                      width: 9.px,
                      height: 9.px,
                      radius: BorderRadius.circular(5.px),
                      backgroundColor: Color('#10B981'),
                      shadow: BoxShadow(
                        offsetX: 0.px,
                        offsetY: 0.px,
                        blur: 8.px,
                        color: Color('#10B981'),
                      ),
                    ),
                    [],
                  ),
                  span(
                    styles: Styles(
                      fontSize: 12.px,
                      fontWeight: FontWeight.bold,
                      color: _isDark ? Color('#F8FAFC') : Color('#0F172A'),
                      raw: {'letter-spacing': '0.4px'},
                    ),
                    [Component.text('LIVE TRACKING • ${component.channelId}')],
                  ),
                ],
              ),

              // Travel Mode Chip
              div(
                styles: Styles(
                  padding: Padding.symmetric(horizontal: 12.px, vertical: 8.px),
                  radius: BorderRadius.circular(24.px),
                  border: Border.all(
                    color: _isDark ? Color('rgba(255, 255, 255, 0.15)') : Color('rgba(0, 0, 0, 0.08)'),
                    width: 1.px,
                    style: BorderStyle.solid,
                  ),
                  raw: {
                    'backdrop-filter': 'blur(16px)',
                    '-webkit-backdrop-filter': 'blur(16px)',
                    'background': _isDark ? 'rgba(15, 23, 42, 0.92)' : 'rgba(255, 255, 255, 0.95)',
                    'font-size': '12px',
                    'font-weight': '600',
                    'color': _isDark ? '#94A3B8' : '#475569',
                  },
                ),
                [
                  Component.text(
                    component.vehicleIcon != null && component.vehicleIcon!.isNotEmpty
                        ? '${component.vehicleIcon} ${component.travelMode.label}'
                        : component.travelMode.label,
                  ),
                ],
              ),
            ],
          ),

        // 3. Recenter on Driver Button (Top Right, in place of close button)
        div(
          styles: Styles(
            position: component.isEmbedded
                ? Position.absolute(top: 20.px, right: 20.px)
                : Position.fixed(top: 20.px, right: 20.px),
            zIndex: ZIndex(100),
          ),
          [
            button(
              onClick: () {
                final pos = _currentTelemetry?.snappedPosition ?? _currentTelemetry?.rawPosition;
                if (pos != null && _map != null) {
                  _map?.easeTo(
                    EaseToOptions(
                      center: [pos.longitude.toJS, pos.latitude.toJS].toJS,
                      zoom: 16.5.toJS,
                      pitch: 35.toJS,
                      duration: 500.toJS,
                    ),
                  );
                  _showToast('📍 Centered on driver');
                }
              },
              styles: Styles(
                width: 44.px,
                height: 44.px,
                radius: BorderRadius.circular(22.px),
                border: Border.all(
                  color: _isDark ? Color('rgba(255, 255, 255, 0.15)') : Color('rgba(0, 0, 0, 0.08)'),
                  width: 1.px,
                  style: BorderStyle.solid,
                ),
                backgroundColor: _isDark ? Color('rgba(15, 23, 42, 0.92)') : Color('#ffffff'),
                shadow: BoxShadow(
                  offsetX: 0.px,
                  offsetY: 4.px,
                  blur: 12.px,
                  color: _isDark ? Color('rgba(0, 0, 0, 0.50)') : Color('rgba(0, 0, 0, 0.15)'),
                ),
                cursor: Cursor.pointer,
                display: Display.flex,
                alignItems: AlignItems.center,
                justifyContent: JustifyContent.center,
                raw: {
                  'backdrop-filter': 'blur(16px)',
                  '-webkit-backdrop-filter': 'blur(16px)',
                },
              ),
              [
                svg(
                  viewBox: '0 0 24 24',
                  width: 22.px,
                  height: 22.px,
                  styles: Styles(
                    raw: {
                      'fill': _effectiveAccentColor,
                    },
                  ),
                  [
                    path(
                      [],
                      d: 'M12 8c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4zm8.94 3c-.46-4.17-3.77-7.48-7.94-7.94V1h-2v2.06C6.83 3.52 3.52 6.83 3.06 11H1v2h2.06c.46 4.17 3.77 7.48 7.94 7.94V23h2v-2.06c4.17-.46 7.48-3.77 7.94-7.94H23v-2h-2.06zM12 19c-3.87 0-7-3.13-7-7s3.13-7 7-7 7 3.13 7 7-3.13 7-7 7z',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        // 4. Action Toast Feedback Banner (if triggered)
        if (_actionToast != null)
          div(
            styles: Styles(
              position: component.isEmbedded
                  ? Position.absolute(top: 80.px, left: 50.percent)
                  : Position.fixed(top: 80.px, left: 50.percent),
              transform: Transform.translate(x: (-50).percent),
              zIndex: ZIndex(200),
              padding: Padding.symmetric(horizontal: 20.px, vertical: 10.px),
              radius: BorderRadius.circular(24.px),
              border: Border.all(
                color: Color('rgba(255, 255, 255, 0.3)'),
                width: 1.px,
                style: BorderStyle.solid,
              ),
              shadow: BoxShadow(
                offsetX: 0.px,
                offsetY: 6.px,
                blur: 20.px,
                color: Color('rgba(0, 0, 0, 0.4)'),
              ),
              raw: {
                'background': 'linear-gradient(135deg, #10B981 0%, #059669 100%)',
                'color': '#ffffff',
                'font-weight': '700',
                'font-size': '14px',
                'backdrop-filter': 'blur(16px)',
                '-webkit-backdrop-filter': 'blur(16px)',
                'pointer-events': 'none',
              },
            ),
            [Component.text(_actionToast!)],
          ),


        // 6. Bottom Live Trip HUD Card (Custom Builder OR Default Highly-Configurable Card)
        if (component.cardBuilder != null)
          component.cardBuilder!(context, telemetry)
        else
          _buildDefaultCard(context, telemetry),
      ],
    );
  }
}
