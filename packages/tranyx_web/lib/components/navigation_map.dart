import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../services/leaflet_interop.dart';
import '../services/firebase_service.dart';
import '../client/tranyx_app.dart';
import 'ui_helpers.dart';

// Sub-status labels and progression
const _kSubStatuses = [
  ('heading_to_pickup', '🛵  Heading to Pickup', 'blue'),
  ('arrived_pickup', '📦  Arrived at Pickup', 'blue'),
  ('purchase_complete', '🛒  Purchase Done, Heading to You', 'purple'),
  ('heading_to_destination', '🚗  On the Way to Destination', 'orange'),
  ('arrived_destination', '🏠  Arrived at Destination', 'green'),
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

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _broadcastTimer?.cancel();
    if (_watchId != -1) clearWatch(_watchId);
    destroyMap(_mapId);
    super.dispose();
  }

  Future<void> _init() async {
    await ensureLeafletLoaded();

    final job = component.state.selectedJobData!;
    final pickupLat = (job['pickupLat'] as num?)?.toDouble();
    final pickupLng = (job['pickupLng'] as num?)?.toDouble();
    final destLat = (job['destinationLat'] as num?)?.toDouble();
    final destLng = (job['destinationLng'] as num?)?.toDouble();

    final cLat = pickupLat ?? 14.5995;
    final cLng = pickupLng ?? 120.9842;

    // initMap now polls for the DOM element — no fixed delay needed
    final isDark = component.state.isDark;
    await initMap(_mapId, cLat, cLng, 14, isDark: isDark);

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
      await drawOSRMRoute(_mapId, pickupLat, pickupLng!, destLat, destLng!, '#6366f1');
    }

    setState(() => _ready = true);

    // Small invalidate to fix tile rendering after layout
    await Future.delayed(const Duration(milliseconds: 80));
    invalidateMapSize(_mapId);

    if (component.isNyxian) {
      _startBroadcasting();
    } else {
      _startPolling();
    }
  }

  // ── Employer: poll Firestore for Nyxian location ──────────────────────────

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final token = component.state.idToken;
      final jobId = component.state.selectedJobData!['id'];
      if (token == null || jobId == null) return;

      try {
        final job = await FirestoreService(token).getDocument('jobs/$jobId');
        if (job == null) return;

        final lat = (job['nyxianLat'] as num?)?.toDouble();
        final lng = (job['nyxianLng'] as num?)?.toDouble();
        final subStatus = job['nyxianSubStatus'] as String?;

        if (lat != null && lng != null) {
          setMarker(_mapId, 'nyxian', lat, lng, '🛵 Nyxian — ${_subStatusLabel(subStatus)}');
          panTo(_mapId, lat, lng);

          // Re-draw route from Nyxian's live position to destination
          final destLat = (job['destinationLat'] as num?)?.toDouble();
          final destLng = (job['destinationLng'] as num?)?.toDouble();
          if (destLat != null && destLng != null) {
            await drawOSRMRoute(_mapId, lat, lng, destLat, destLng, '#6366f1');
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

  Future<void> _updateFirestoreLocation(double lat, double lng) async {
    final token = component.state.idToken;
    final jobId = component.state.selectedJobData!['id'];
    if (token == null || jobId == null) return;
    try {
      await FirestoreService(token).createOrUpdate('jobs/$jobId', {
        'nyxianLat': lat,
        'nyxianLng': lng,
      });
      final subStatus = component.state.selectedJobData!['nyxianSubStatus'] as String?;
      setMarker(_mapId, 'nyxian', lat, lng, '🛵 You — ${_subStatusLabel(subStatus)}');
      panTo(_mapId, lat, lng);
    } catch (_) {}
  }

  void _redrawRouteFromCurrentPos(double fromLat, double fromLng) {
    final job = component.state.selectedJobData!;
    final subStatus = job['nyxianSubStatus'] as String?;
    // Navigate to pickup first, then to destination
    final pickupLat = (job['pickupLat'] as num?)?.toDouble();
    final pickupLng = (job['pickupLng'] as num?)?.toDouble();
    final destLat = (job['destinationLat'] as num?)?.toDouble();
    final destLng = (job['destinationLng'] as num?)?.toDouble();

    final bool pastPickup =
        subStatus == 'purchase_complete' || subStatus == 'heading_to_destination' || subStatus == 'arrived_destination';

    if (!pastPickup && pickupLat != null) {
      drawOSRMRoute(_mapId, fromLat, fromLng, pickupLat, pickupLng!, '#3b82f6');
    } else if (pastPickup && destLat != null) {
      drawOSRMRoute(_mapId, fromLat, fromLng, destLat, destLng!, '#6366f1');
    }
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final job = s.selectedJobData!;
    final subStatus = job['nyxianSubStatus'] as String?;
    final nextStatus = _nextSubStatus(subStatus);
    final hasTracker = job['hasTracker'] as bool? ?? false;
    final destLat = (job['destinationLat'] as num?)?.toDouble();
    final destLng = (job['destinationLng'] as num?)?.toDouble();

    return div(
      classes: 'flex flex-col gap-4',
      [
        // ── Map card ─────────────────────────────────────────────────────────
        div(
          classes:
              'relative w-full rounded-[2rem] overflow-hidden border shadow-2xl '
              '${isDark ? "border-zinc-800" : "border-zinc-200"}',
          attributes: {'style': 'height: 420px'},
          [
            // Map element — always rendered so Leaflet can attach
            div(
              id: _mapId,
              classes: 'absolute inset-0',
              attributes: {'style': 'z-index: 1'},
              [],
            ),

            // Loading overlay (shown until map is ready)
            if (!_ready)
              div(
                classes:
                    'absolute inset-0 flex flex-col items-center justify-center gap-4 z-[2] '
                    '${isDark ? "bg-zinc-900" : "bg-zinc-50"}',
                [
                  lIcon('loader-2', cls: 'w-10 h-10 animate-spin text-indigo-500'),
                  p(classes: 'text-sm font-semibold ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                    Component.text('Loading map…'),
                  ]),
                ],
              ),

            // ── Floating top bar (status) ─────────────────────────────────
            if (_ready)
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
                      div(classes: 'w-2 h-2 rounded-full bg-green-400 animate-pulse flex-shrink-0', []),
                      div(classes: 'flex flex-col', [
                        span(
                          classes:
                              'text-[9px] uppercase tracking-widest font-black ${isDark ? "text-zinc-500" : "text-zinc-400"}',
                          [Component.text('Live Tracker')],
                        ),
                        span(classes: 'text-xs font-bold', [Component.text(_subStatusLabel(subStatus))]),
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
                        if (_myLat != null) {
                          panTo(_mapId, _myLat!, _myLng!);
                        } else {
                          final pLat = (job['pickupLat'] as num?)?.toDouble();
                          final pLng = (job['pickupLng'] as num?)?.toDouble();
                          if (pLat != null) panTo(_mapId, pLat, pLng!);
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

          if (hasTracker && component.isNyxian && subStatus == 'arrived_destination') _successCard(isDark),

          // Employer timeline
          if (hasTracker && !component.isNyxian) _timelineCard(subStatus, isDark),

          // ── OSM Navigate button (for Nyxian) ─────────────────────────────
          if (component.isNyxian && destLat != null)
            button(
              classes:
                  'w-full py-3.5 rounded-2xl font-bold text-sm flex items-center justify-center gap-2.5 transition-all hover:scale-[1.01] active:scale-[0.99] '
                  '${isDark ? "bg-zinc-800 hover:bg-zinc-700 border border-zinc-700 text-white" : "bg-zinc-100 hover:bg-zinc-200 border border-zinc-200 text-zinc-900"}',
              events: {
                'click': (_) => openOSMNavigation(destLat, destLng!),
              },
              [
                lIcon('navigation', cls: 'w-4 h-4 text-indigo-400'),
                Component.text('Open Navigation (OSM)'),
              ],
            ),
        ],
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
