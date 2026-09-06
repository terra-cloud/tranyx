import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/mapbox_gl.dart';
import 'package:headless_nav_core/headless_nav_core.dart';
import '../state/flutter_nav_providers.dart';

/// Generates a crisp, high-resolution vector location pin / navigation puck (PNG bytes)
/// with a drop shadow, outer halo, accent colored core, and directional heading chevron.
Future<Uint8List> generateDefaultDriverPinBytes({
  Color pinColor = const Color(0xFF1976D2),
  Color haloColor = Colors.white,
  int size = 120,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
  );
  final center = Offset(size / 2, size / 2);
  final radius = size * 0.40;

  // 1. Soft Drop Shadow
  final shadowPaint = Paint()
    ..color = const Color(0x66000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
  canvas.drawCircle(center.translate(0, 4), radius, shadowPaint);

  // 2. High-Contrast White Halo
  final haloPaint = Paint()
    ..color = haloColor
    ..style = PaintingStyle.fill;
  canvas.drawCircle(center, radius, haloPaint);

  // 3. Accent Colored Circular Core
  final corePaint = Paint()
    ..color = pinColor
    ..style = PaintingStyle.fill;
  canvas.drawCircle(center, radius * 0.78, corePaint);

  // 4. Directional Heading Arrow pointing North (0 deg)
  final arrowPath = Path();
  final arrowTop = center.dy - radius * 0.52;
  final arrowBottom = center.dy + radius * 0.38;
  final arrowWidth = radius * 0.42;
  final arrowIndent = center.dy + radius * 0.16;

  arrowPath.moveTo(center.dx, arrowTop);
  arrowPath.lineTo(center.dx + arrowWidth, arrowBottom);
  arrowPath.lineTo(center.dx, arrowIndent);
  arrowPath.lineTo(center.dx - arrowWidth, arrowBottom);
  arrowPath.close();

  final arrowPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;
  canvas.drawPath(arrowPath, arrowPaint);

  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// Full-screen live tracking viewer for a follower / listener subscribing
/// to a driver's geospatial telemetry stream with OpenFreeMap vector maps.
///
/// Displays the driver's remaining planned route, dynamic vehicle pin rotated
/// to match the driver's real-time compass bearing, and arrival overview
/// without turn-by-turn navigation instructions.
class FollowerNavigationView extends ConsumerStatefulWidget {
  final String channelId;

  /// Custom raw image bytes (PNG, JPEG, WebP) for the driver marker.
  /// If provided, this image is uploaded directly to MapLibre style.
  final Uint8List? driverMarkerBytes;

  /// Custom Flutter asset path (e.g. 'assets/images/driver_pin.png')
  /// to load and register as the driver marker.
  final String? driverMarkerAsset;

  /// Custom icon image name if already registered in the MapLibre style sprite.
  final String? driverMarkerImage;

  /// Scale size for the driver marker symbol. Defaults to 1.3.
  final double driverMarkerSize;

  /// Primary color for the default location pin if no custom image is supplied.
  /// If null, Theme colorScheme.primary or '#1976D2' is used.
  final Color? driverPinColor;

  /// Deprecated legacy parameter. Prefer [driverMarkerImage], [driverMarkerAsset],
  /// or [driverMarkerBytes].
  final String? vehicleIconImage;

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

  /// Optional custom streaming backend (e.g. [WSLocationStreaming], [SupabaseLocationStreaming]).
  /// If omitted, falls back to [locationStreamingProvider].
  final LocationStreaming? streaming;

  /// Optional callback to close or exit follower mode.
  /// If neither [onClose] nor [onExit] is provided, the close button is omitted.
  final VoidCallback? onClose;

  final VoidCallback? onExit;

  /// Optional custom card builder to completely customize the subscriber tracking overlay.
  final Widget Function(BuildContext context, BroadcasterTelemetry? telemetry)? cardBuilder;

  static const String defaultStyleUrl = OpenFreeMapStyles.bright;

  const FollowerNavigationView({
    super.key,
    required this.channelId,
    this.streaming,
    this.driverMarkerBytes,
    this.driverMarkerAsset,
    this.driverMarkerImage,
    this.driverMarkerSize = 1.3,
    this.driverPinColor,
    this.vehicleIconImage,
    this.styleString,
    this.themeAdaptive = false,
    this.lightStyle = OpenFreeMapStyles.bright,
    this.darkStyle = OpenFreeMapStyles.dark,
    this.onClose,
    this.onExit,
    this.cardBuilder,
  });

  @override
  ConsumerState<FollowerNavigationView> createState() =>
      _FollowerNavigationViewState();
}

class _FollowerNavigationViewState
    extends ConsumerState<FollowerNavigationView> {
  MaplibreMapController? _mapController;
  Symbol? _driverMarker;
  Line? _routeLine;
  int _lastPrunedCoordCount = 0;
  StreamSubscription<BroadcasterTelemetry>? _customTelemetrySub;
  BroadcasterTelemetry? _customTelemetry;

  @override
  void initState() {
    super.initState();
    if (widget.streaming != null) {
      _customTelemetrySub =
          widget.streaming!.stream(widget.channelId).listen((telemetry) {
        final pos = telemetry.snappedPosition ?? telemetry.rawPosition;
        _updateFollowerCamera(
          pos.latitude,
          pos.longitude,
          telemetry.currentBearing,
        );
        _updateFollowerRouteLine(telemetry.routeCoordinates);
        if (mounted) {
          setState(() {
            _customTelemetry = telemetry;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _customTelemetrySub?.cancel();
    super.dispose();
  }

  static const String _customDriverPinName = 'headless_nav_custom_driver_pin';
  bool _markerRegistered = false;
  String _effectiveMarkerImage = _customDriverPinName;

  Future<void> _ensureMarkerRegistered() async {
    if (_markerRegistered || _mapController == null) return;

    try {
      if (widget.driverMarkerBytes != null) {
        await _mapController!
            .addImage(_customDriverPinName, widget.driverMarkerBytes!);
        _effectiveMarkerImage = _customDriverPinName;
      } else if (widget.driverMarkerAsset != null) {
        final data = await rootBundle.load(widget.driverMarkerAsset!);
        await _mapController!
            .addImage(_customDriverPinName, data.buffer.asUint8List());
        _effectiveMarkerImage = _customDriverPinName;
      } else if (widget.driverMarkerImage != null) {
        _effectiveMarkerImage = widget.driverMarkerImage!;
      } else if (widget.vehicleIconImage != null) {
        _effectiveMarkerImage = widget.vehicleIconImage!;
      } else {
        final pinColor = widget.driverPinColor ??
            (mounted
                ? Theme.of(context).colorScheme.primary
                : const Color(0xFF1976D2));
        final bytes = await generateDefaultDriverPinBytes(pinColor: pinColor);
        await _mapController!.addImage(_customDriverPinName, bytes);
        _effectiveMarkerImage = _customDriverPinName;
      }
      _markerRegistered = true;
    } catch (_) {}
  }

  void _onMapCreated(MaplibreMapController controller) {
    _mapController = controller;
    _markerRegistered = false;
    _driverMarker = null;
    _routeLine = null;
    _ensureMarkerRegistered();
  }

  Future<void> _updateFollowerCamera(
      double lat, double lon, double? bearing) async {
    if (_mapController == null) return;

    final target = LatLng(lat, lon);

    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: 16.5,
          bearing: 0.0, // Follower map remains North-up
          tilt: 35.0,
        ),
      ),
      duration: const Duration(milliseconds: 600),
    );

    await _ensureMarkerRegistered();

    final iconName = _effectiveMarkerImage;
    final rotation = bearing ?? 0.0;
    final iconSize = widget.driverMarkerSize;

    if (_driverMarker == null) {
      _driverMarker = await _mapController?.addSymbol(
        SymbolOptions(
          geometry: target,
          iconImage: iconName,
          iconRotate: rotation,
          iconSize: iconSize,
        ),
      );
    } else {
      await _mapController?.updateSymbol(
        _driverMarker!,
        SymbolOptions(
          geometry: target,
          iconImage: iconName,
          iconRotate: rotation,
          iconSize: iconSize,
        ),
      );
    }
  }

  /// Throttled rendering of the driver's remaining route on the subscriber's map.
  Future<void> _updateFollowerRouteLine(List<List<double>>? coordinates) async {
    if (_mapController == null || coordinates == null || coordinates.isEmpty) {
      return;
    }

    if (coordinates.length == _lastPrunedCoordCount) return;
    _lastPrunedCoordCount = coordinates.length;

    final latLngs = coordinates.map((c) => LatLng(c[1], c[0])).toList();

    if (_routeLine == null) {
      _routeLine = await _mapController?.addLine(
        LineOptions(
          geometry: latLngs,
          lineColor: '#0066FF',
          lineWidth: 5.5,
          lineOpacity: 0.85,
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
    final hour = eta.hour > 12 ? eta.hour - 12 : (eta.hour == 0 ? 12 : eta.hour);
    final period = eta.hour >= 12 ? 'PM' : 'AM';
    final minute = eta.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<BroadcasterTelemetry> telemetryAsync =
        widget.streaming != null
            ? (_customTelemetry != null
                ? AsyncValue.data(_customTelemetry!)
                : const AsyncValue.loading())
            : ref.watch(liveFollowerStreamProvider(widget.channelId));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final effectiveStyle = widget.themeAdaptive
        ? (isDark ? widget.darkStyle : widget.lightStyle)
        : (widget.styleString ?? widget.lightStyle);

    if (widget.streaming == null) {
      ref.listen(liveFollowerStreamProvider(widget.channelId), (prev, next) {
        next.whenData((telemetry) {
          final pos = telemetry.snappedPosition ?? telemetry.rawPosition;
          _updateFollowerCamera(
            pos.latitude,
            pos.longitude,
            telemetry.currentBearing,
          );
          _updateFollowerRouteLine(telemetry.routeCoordinates);
        });
      });
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
              zoom: 15.0,
            ),
          ),

          // 2. Top App Bar / Channel Tracking Status Badge
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'LIVE TRACKING: ${widget.channelId}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    if (widget.onClose != null || widget.onExit != null) ...[
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: widget.onClose ?? widget.onExit,
                        child: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // 3. Bottom Live Tracking Overview Card (Custom builder OR Default Card)
          if (widget.cardBuilder != null)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: widget.cardBuilder!(context, telemetryAsync.asData?.value),
              ),
            )
          else
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Card(
                elevation: 6,
                margin: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                color: colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: telemetryAsync.when(
                    data: (telemetry) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Stop & Speed status if multi-stop
                        if (telemetry.totalStopsCount != null &&
                            telemetry.totalStopsCount! > 1) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${telemetry.currentStopTitle ?? 'Stop'} (${(telemetry.currentStopIndex ?? 0) + 1}/${telemetry.totalStopsCount})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              if (telemetry.currentSpeedKmh != null)
                                Text(
                                  'Speed: ${telemetry.currentSpeedKmh!.round()} km/h',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.outline,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],

                        // Arrival metrics
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ESTIMATED ARRIVAL',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.outline,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  telemetry.currentStopEta != null
                                      ? '${_formatEtaClock(telemetry.currentStopEta)} • ${_formatDuration(telemetry.remainingDuration)}'
                                      : _formatDuration(telemetry.remainingDuration),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
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
                                  'REMAINING DISTANCE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.outline,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatDistance(telemetry.remainingDistance),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                            SizedBox(width: 12),
                            Text('Connecting to live telemetry stream...'),
                          ],
                        ),
                      ),
                    ),
                    error: (err, st) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Unable to connect: $err',
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
