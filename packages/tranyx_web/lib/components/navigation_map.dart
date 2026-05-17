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

// Next sub-status in the chain
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

/// Live navigation map.
/// - For Employer: shows Nyxian marker + route, polls for location.
/// - For Nyxian: shows their navigation + sub-status update buttons, broadcasts GPS.
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
  Timer? _pollTimer;
  Timer? _broadcastTimer;
  int _watchId = -1;

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
    await Future.delayed(const Duration(milliseconds: 400));

    final job = component.state.selectedJobData!;
    final pickupLat = (job['pickupLat'] as num?)?.toDouble();
    final pickupLng = (job['pickupLng'] as num?)?.toDouble();
    final destLat = (job['destinationLat'] as num?)?.toDouble();
    final destLng = (job['destinationLng'] as num?)?.toDouble();

    // Centre on pickup or Metro Manila default
    final cLat = pickupLat ?? 14.5995;
    final cLng = pickupLng ?? 120.9842;
    initMap(_mapId, cLat, cLng, 13);

    // Draw 1st Point and delivery point markers
    if (pickupLat != null) {
      setMarker(_mapId, 'pickup', pickupLat, pickupLng!, '📦 1st Point: ${job['pickupAddress'] ?? ''}');
    }
    if (destLat != null) {
      setMarker(_mapId, 'destination', destLat, destLng!, '🏠 Delivery Point: ${job['destinationAddress'] ?? ''}');
    }
    // Draw route line
    if (pickupLat != null && destLat != null) {
      drawRoute(_mapId, [
        [pickupLat, pickupLng!],
        [destLat, destLng!],
      ], 'indigo');
    }

    setState(() => _ready = true);

    if (component.isNyxian) {
      _startBroadcasting();
    } else {
      _startPolling();
    }
  }

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
        }
        // Update state for sub-status badge
        component.state.setState(() {
          component.state.selectedJobData = {...component.state.selectedJobData!, 'nyxianSubStatus': subStatus};
        });
      } catch (_) {}
    });
  }

  void _startBroadcasting() {
    // Initial check
    _updateNyxianLocation();
    // Regular update
    _broadcastTimer = Timer.periodic(const Duration(seconds: 10), (_) => _updateNyxianLocation());
    // Also use watchPosition for better accuracy
    _watchId = watchPosition((lat, lng) => _updateFirestoreLocation(lat, lng));
  }

  Future<void> _updateNyxianLocation() async {
    final pos = await getCurrentPosition();
    if (pos != null) {
      _updateFirestoreLocation(pos.lat, pos.lng);
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
      // Also update map locally
      final subStatus = component.state.selectedJobData!['nyxianSubStatus'] as String?;
      setMarker(_mapId, 'nyxian', lat, lng, '🛵 You are here — ${_subStatusLabel(subStatus)}');
    } catch (_) {}
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final job = s.selectedJobData!;
    final subStatus = job['nyxianSubStatus'] as String?;
    final nextStatus = _nextSubStatus(subStatus);
    final hasTracker = job['hasTracker'] as bool? ?? false;

    return div(
      classes:
          'relative w-full h-[550px] rounded-[2.5rem] overflow-hidden border ${isDark ? "border-zinc-800 shadow-2xl" : "border-zinc-200 shadow-xl"}',
      [
        // Map
        if (!_ready)
          div(
            classes:
                'absolute inset-0 flex flex-col items-center justify-center gap-4 ${isDark ? "bg-zinc-900" : "bg-zinc-50"}',
            [
              lIcon('loader-2', cls: 'w-10 h-10 animate-spin text-indigo-500'),
              p(classes: 'text-sm font-medium ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                Component.text('Initializing Navigation...'),
              ]),
            ],
          )
        else
          div(id: _mapId, classes: 'absolute inset-0', attributes: {'style': 'z-index:0'}, []),

        // Top Floating Status
        div(classes: 'absolute top-6 left-6 right-6 z-[400] flex justify-between pointer-events-none', [
          div(
            classes:
                'px-5 py-3 rounded-2xl backdrop-blur-xl border pointer-events-auto flex items-center gap-3 '
                '${isDark ? "bg-zinc-900/80 border-zinc-700/50 shadow-xl" : "bg-white/80 border-white shadow-xl"}',
            [
              div(classes: 'w-2.5 h-2.5 rounded-full bg-green-500 animate-pulse', []),
              div(classes: 'flex flex-col', [
                span(
                  classes:
                      'text-[10px] uppercase tracking-widest font-black ${isDark ? "text-zinc-500" : "text-zinc-400"}',
                  [Component.text('Real-time Tracker')],
                ),
                span(classes: 'text-sm font-bold', [Component.text(_subStatusLabel(subStatus))]),
              ]),
            ],
          ),
          div(classes: 'flex gap-2 pointer-events-auto', [
            _circleActionButton('navigation', isDark),
            _circleActionButton('layers', isDark),
          ]),
        ]),

        // Bottom Floating Cards
        div(classes: 'absolute bottom-6 left-6 right-6 z-[400] flex flex-col gap-4', [
          div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-3', [
            if (hasTracker) ...[
              _routeCardFloating(
                icon: 'package',
                label: '1st Point',
                address: job['pickupAddress'] as String? ?? 'Not specified',
                color: 'blue',
                isDark: isDark,
              ),
              _routeCardFloating(
                icon: 'home',
                label: 'Delivery Point',
                address: job['destinationAddress'] as String? ?? 'Not specified',
                color: 'green',
                isDark: isDark,
              ),
            ] else
              _routeCardFloating(
                icon: 'map-pin',
                label: 'Site Location',
                address: job['pickupAddress'] as String? ?? 'Not specified',
                color: 'indigo',
                isDark: isDark,
                isFullWidth: true,
              ),
          ]),

          if (hasTracker && component.isNyxian && nextStatus != null)
            _nyxianActionCard(nextStatus, subStatus, isDark, s)
          else if (hasTracker && component.isNyxian && subStatus == 'arrived_destination')
            _completionSuccessCard(isDark)
          else if (hasTracker && !component.isNyxian)
            _employerTimelineCard(subStatus, isDark),
        ]),
      ],
    );
  }

  Component _circleActionButton(String icon, bool isDark) {
    return button(
      classes:
          'w-12 h-12 rounded-2xl backdrop-blur-xl border flex items-center justify-center transition-all hover:scale-105 active:scale-95 '
          '${isDark ? "bg-zinc-900/80 border-zinc-700/50 text-white shadow-xl" : "bg-white/80 border-white text-zinc-900 shadow-xl"}',
      [lIcon(icon, cls: 'w-5 h-5')],
    );
  }

  Component _routeCardFloating({
    required String icon,
    required String label,
    required String address,
    required String color,
    required bool isDark,
    bool isFullWidth = false,
  }) {
    final textCol = color == 'blue' ? 'text-blue-400' : (color == 'green' ? 'text-green-400' : 'text-indigo-400');
    final bgCol = color == 'blue' ? 'bg-blue-500/10' : (color == 'green' ? 'bg-green-500/10' : 'bg-indigo-500/10');
    return div(
      classes:
          'p-4 rounded-[1.5rem] backdrop-blur-xl border flex items-center gap-4 transition-all shadow-xl '
          '${isDark ? "bg-zinc-900/90 border-zinc-700/50" : "bg-white/90 border-white"} '
          '${isFullWidth ? "col-span-1 md:col-span-2" : ""}',
      [
        div(classes: 'w-10 h-10 rounded-xl $bgCol flex items-center justify-center flex-shrink-0', [
          lIcon(icon, cls: 'w-5 h-5 $textCol'),
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
          'p-5 rounded-[2rem] backdrop-blur-2xl border ${isDark ? "bg-indigo-600/15 border-indigo-500/30 shadow-indigo-500/10" : "bg-indigo-50/90 border-white shadow-xl"} flex items-center gap-4 animate-fade-up',
      [
        div(classes: 'flex-1', [
          p(classes: 'text-xs font-bold text-indigo-400 uppercase tracking-widest mb-1', [
            Component.text('Next Action'),
          ]),
          p(classes: 'text-sm font-black', [Component.text(_nextButtonLabel(currentStatus))]),
        ]),
        button(
          classes: (s.isUpdatingSubStatus)
              ? 'px-8 py-3.5 rounded-2xl font-black text-xs uppercase tracking-widest text-white bg-indigo-600/50 cursor-not-allowed flex items-center gap-2'
              : 'px-8 py-3.5 rounded-2xl font-black text-xs uppercase tracking-widest text-white bg-indigo-600 hover:bg-indigo-500 shadow-lg shadow-indigo-500/40 transition-all hover:scale-[1.02] active:scale-95 flex items-center gap-2',
          events: (s.isUpdatingSubStatus) ? {} : {'click': (_) => s.handleUpdateNyxianSubStatus(nextStatus)},
          [
            if (s.isUpdatingSubStatus) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
            Component.text('Confirm Arrival'),
          ],
        ),
      ],
    );
  }

  Component _completionSuccessCard(bool isDark) {
    return div(
      classes:
          'p-5 rounded-[2rem] backdrop-blur-2xl border border-green-500/30 bg-green-500/10 flex items-center gap-4 text-center justify-center animate-fade-up',
      [
        lIcon('check-circle', cls: 'w-6 h-6 text-green-400'),
        p(classes: 'text-sm font-black text-green-400', [Component.text('Reached Destination! Show QR to Employer.')]),
      ],
    );
  }

  Component _employerTimelineCard(String? subStatus, bool isDark) {
    return div(
      classes:
          'p-6 rounded-[2rem] backdrop-blur-2xl border ${isDark ? "bg-zinc-900/90 border-zinc-700/50" : "bg-white/90 border-white shadow-xl"}',
      [
        _statusTimeline(subStatus, isDark),
      ],
    );
  }

  Component _statusTimeline(String? currentStatus, bool isDark) {
    final currentIdx = currentStatus == null ? -1 : _kSubStatuses.indexWhere((e) => e.$1 == currentStatus);
    return div(classes: 'space-y-1', [
      for (int i = 0; i < _kSubStatuses.length; i++) ...[
        div(classes: 'flex items-center gap-4', [
          div(
            classes: i <= currentIdx
                ? 'w-6 h-6 rounded-full flex items-center justify-center bg-green-500 shadow-lg shadow-green-500/20 flex-shrink-0'
                : 'w-6 h-6 rounded-full border-2 flex-shrink-0 ${isDark ? "border-zinc-800" : "border-zinc-200"}',
            [
              if (i <= currentIdx)
                lIcon('check', cls: 'w-3 h-3 text-white')
              else
                span(classes: 'text-[10px] ${isDark ? "text-zinc-700" : "text-zinc-300"}', [
                  Component.text((i + 1).toString()),
                ]),
            ],
          ),
          p(
            classes: i <= currentIdx
                ? 'text-xs font-bold text-green-400'
                : 'text-xs font-medium ${isDark ? "text-zinc-600" : "text-zinc-400"}',
            [Component.text(_kSubStatuses[i].$2)],
          ),
        ]),
        if (i < _kSubStatuses.length - 1)
          div(
            classes: 'ml-3 w-0.5 h-3 ${i < currentIdx ? "bg-green-500/30" : (isDark ? "bg-zinc-800" : "bg-zinc-100")}',
            [],
          ),
      ],
    ]);
  }
}
