import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:shared/shared.dart';
import 'package:headless_nav_jaspr/headless_nav_jaspr.dart';
import '../services/web_interop.dart';
import '../services/firebase_service.dart';
import '../client/tranyx_app.dart';
import '../client/utils/geo_helper.dart';

// Sub-status labels and progression
const _kSubStatuses = [
  ('heading_to_pickup', '🛵  Heading to Pickup', 'blue'),
  ('arrived_pickup', '📦  Arrived at Pickup', 'blue'),
  ('paid_cashier', '🛒  Items Secured / Paid', 'purple'),
  ('in_transit', '🚗  In Transit to Destination', 'orange'),
  ('arrived_dropoff', '🏠  Arrived at Destination', 'green'),
];

String _subStatusLabel(String? s) {
  if (s == null) return 'Active Order';
  return _kSubStatuses.firstWhere((e) => e.$1 == s, orElse: () => (s, s, 'zinc')).$2;
}

/// Streaming implementation that polls the Firestore job document
/// for live courier coordinates and telemetry updates for the employer view.
class FirestoreJobLocationStreaming extends LocationStreaming {
  final String? Function() tokenProvider;
  Timer? _timer;
  StreamController<BroadcasterTelemetry>? _controller;

  FirestoreJobLocationStreaming({required this.tokenProvider});

  @override
  Stream<BroadcasterTelemetry> stream(String channelId) {
    _controller = StreamController<BroadcasterTelemetry>.broadcast(
      onListen: () => _start(channelId),
      onCancel: () => _stop(),
    );
    return _controller!.stream;
  }

  void _start(String jobId) {
    _poll(jobId);
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll(jobId));
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll(String jobId) async {
    final token = tokenProvider();
    if (token == null) return;
    try {
      final doc = await FirestoreService(token).getDocument('jobs/$jobId');
      if (doc == null) return;

      if (doc['lastTelemetry'] is Map) {
        try {
          final telemetry = BroadcasterTelemetry.fromJson(
            Map<String, dynamic>.from(doc['lastTelemetry'] as Map),
          );
          _controller?.add(telemetry);
          return;
        } catch (_) {}
      }

      final lat = (doc['nyxianLat'] as num?)?.toDouble();
      final lng = (doc['nyxianLng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        final bearing = (doc['nyxianBearing'] as num?)?.toDouble();
        final speed = (doc['nyxianSpeed'] as num?)?.toDouble();
        final remDist = (doc['nyxianRemainingDistance'] as num?)?.toDouble();
        final remDur = (doc['nyxianRemainingDuration'] as num?)?.toDouble();

        final telemetry = BroadcasterTelemetry(
          channelId: jobId,
          broadcasterId: (doc['acceptedApplicantId'] as String?) ?? 'nyxian',
          rawPosition: NavPosition(
            latitude: lat,
            longitude: lng,
            timestamp: DateTime.now().toUtc(),
            heading: bearing,
            speed: speed,
          ),
          currentBearing: bearing,
          currentSpeedKmh: speed,
          remainingDistance: remDist,
          remainingDuration: remDur,
          timestamp: DateTime.now().toUtc(),
        );
        _controller?.add(telemetry);
      }
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    _stop();
    await _controller?.close();
  }
}

/// Streaming implementation for the Nyxian driver that captures live browser GPS,
/// broadcasts it to Firestore so the employer can track the courier in real time,
/// and feeds the live telemetry directly into the driver's local tracker map.
class NyxianLiveBroadcastingStreaming extends LocationStreaming {
  final Stream<NavPosition> Function() streamProvider;
  final FirebaseLocationBroadcaster broadcaster;
  final String nyxianId;
  final void Function(NavPosition pos)? onPosition;

  StreamSubscription<NavPosition>? _sub;
  StreamController<BroadcasterTelemetry>? _controller;

  NyxianLiveBroadcastingStreaming({
    required this.streamProvider,
    required this.broadcaster,
    required this.nyxianId,
    this.onPosition,
  });

  @override
  Stream<BroadcasterTelemetry> stream(String channelId) {
    _controller = StreamController<BroadcasterTelemetry>.broadcast(
      onListen: () {
        _sub = streamProvider().listen((pos) {
          final telemetry = BroadcasterTelemetry(
            channelId: channelId,
            broadcasterId: nyxianId,
            rawPosition: pos,
            currentBearing: pos.heading,
            currentSpeedKmh: pos.speed,
            timestamp: pos.timestamp,
          );
          broadcaster.broadcast(channelId, telemetry);
          _controller?.add(telemetry);
          onPosition?.call(pos);
        });
      },
      onCancel: () {
        _sub?.cancel();
        _sub = null;
      },
    );
    return _controller!.stream;
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    await _controller?.close();
  }
}

/// Pure Live Order Tracker powered by `headless_nav_jaspr`.
///
/// Designed with user-friendly, non-intrusive UX:
/// - Displays ONLY when the job has `hasTracker = true`, has valid coordinates,
///   is currently ongoing, has a hired Nyxian, and the current user is either
///   the hired Nyxian or the employer who posted the job.
/// - Non-draggable, non-intrusive tracker: Does not hijack scrolling or panning.
/// - No annoying "Confirm Checkpoint" or "Confirm 1st Point" popups — the Nyxian
///   simply updates the order status using the standard order buttons in the view.
class NavigationMapComponent extends StatefulComponent {
  final TranyxAppState state;
  final bool isNyxian;

  const NavigationMapComponent({
    required this.state,
    required this.isNyxian,
    super.key,
  });

  @override
  State<NavigationMapComponent> createState() => _NavigationMapState();
}

class _NavigationMapState extends State<NavigationMapComponent> {
  FirestoreJobLocationStreaming? _streaming;
  FirebaseLocationBroadcaster? _broadcaster;
  NyxianLiveBroadcastingStreaming? _nyxianStreaming;
  bool _hasAutoUpdatedPickup = false;

  @override
  void initState() {
    super.initState();
    _setupBroadcasterAndStreaming();
  }

  void _setupBroadcasterAndStreaming() {
    _streaming?.close();
    _broadcaster?.close();
    _nyxianStreaming?.close();
    _hasAutoUpdatedPickup = false;

    _streaming = FirestoreJobLocationStreaming(
      tokenProvider: () => component.state.idToken,
    );

    _broadcaster = FirebaseLocationBroadcaster(
      collectionPath: 'jobs',
      documentUpdater: (collection, documentId, data) async {
        final token = component.state.idToken;
        if (token == null) return;
        try {
          final lat = (data['rawPosition']?['latitude'] as num?)?.toDouble() ??
              (data['snappedPosition']?['latitude'] as num?)?.toDouble();
          final lng = (data['rawPosition']?['longitude'] as num?)?.toDouble() ??
              (data['snappedPosition']?['longitude'] as num?)?.toDouble();
          final bearing = (data['currentBearing'] as num?)?.toDouble();
          final speed = (data['currentSpeedKmh'] as num?)?.toDouble();
          final remainingDistance = (data['remainingDistance'] as num?)?.toDouble();
          final remainingDuration = (data['remainingDuration'] as num?)?.toDouble();

          final updatePayload = <String, dynamic>{
            'nyxianLat': ?lat,
            'nyxianLng': ?lng,
            'nyxianBearing': ?bearing,
            'nyxianSpeed': ?speed,
            'nyxianRemainingDistance': ?remainingDistance,
            'nyxianRemainingDuration': ?remainingDuration,
            'lastTelemetry': data,
          };
          await FirestoreService(token).setDocument('jobs/$documentId', updatePayload);
        } catch (_) {}
      },
    );

    if (component.isNyxian) {
      final nyxianId = (component.state.userProfile?.uid ?? SessionStorage.uid ?? 'nyxian').trim();
      _nyxianStreaming = NyxianLiveBroadcastingStreaming(
        streamProvider: () => BrowserGeolocationAdapter(enableHighAccuracy: true).stream(),
        broadcaster: _broadcaster!,
        nyxianId: nyxianId,
        onPosition: (pos) => _checkProximityAutoArrival(pos),
      );
    }
  }

  void _checkProximityAutoArrival(NavPosition pos) {
    if (_hasAutoUpdatedPickup) return;
    final s = component.state;
    final job = s.selectedJobData;
    if (job == null || s.isUpdatingSubStatus) return;

    final rawStatus = job['status'] as String? ?? '';
    final subStatus = job['nyxianSubStatus'] as String? ?? rawStatus;
    final pastPickup = subStatus == 'arrived_pickup' ||
        subStatus == 'paid_cashier' ||
        subStatus == 'in_transit' ||
        subStatus == 'arrived_dropoff';
    if (pastPickup) {
      _hasAutoUpdatedPickup = true;
      return;
    }

    final pickupLat = (job['pickupLat'] as num?)?.toDouble();
    final pickupLng = (job['pickupLng'] as num?)?.toDouble();
    if (pickupLat == null || pickupLng == null) return;

    final distKm = calculateDistance(pos.latitude, pos.longitude, pickupLat, pickupLng);
    if (distKm * 1000.0 <= 50.0) {
      _hasAutoUpdatedPickup = true;
      s.handleUpdateNyxianSubStatus('arrived_pickup');
    }
  }

  @override
  void didUpdateComponent(NavigationMapComponent oldWidget) {
    super.didUpdateComponent(oldWidget);
    final oldJobId = oldWidget.state.selectedJobData?['id'];
    final newJobId = component.state.selectedJobData?['id'];
    if (oldJobId != newJobId) {
      _setupBroadcasterAndStreaming();
    }
  }

  @override
  void dispose() {
    _streaming?.close();
    _broadcaster?.close();
    _nyxianStreaming?.close();
    super.dispose();
  }

  bool _isEligibleToDisplay() {
    final s = component.state;
    final job = s.selectedJobData;
    if (job == null) return false;

    final catName = (job['category'] as String? ?? '').toLowerCase();
    final cat = JobCategory.values.firstWhere(
      (e) => e.name.toLowerCase() == catName || e.label.toLowerCase() == catName,
      orElse: () => JobCategory.others,
    );
    final hasTracker = job['hasTracker'] == true ||
        job['hasTracker'] == 'true' ||
        cat.hasTracker;
    if (!hasTracker) return false;

    final pickupLat = (job['pickupLat'] as num?)?.toDouble();
    final destLat = (job['destinationLat'] as num?)?.toDouble();
    if (pickupLat == null || destLat == null) return false;

    final rawStatus = (job['status'] as String? ?? '').toLowerCase();
    const ongoingStatuses = {
      'in progress',
      'in_progress',
      'ongoing',
      'heading_to_pickup',
      'arrived_pickup',
      'paid_cashier',
      'in_transit',
      'arrived_dropoff',
    };
    final isOngoing = ongoingStatuses.contains(rawStatus);
    if (!isOngoing) return false;

    final acceptedApplicantId =
        (job['acceptedApplicantId'] as String? ?? '').trim();
    if (acceptedApplicantId.isEmpty) return false;

    final currentUserId =
        (s.userProfile?.uid ?? SessionStorage.uid ?? '').trim();
    if (currentUserId.isEmpty) return false;

    final creatorId =
        (job['creatorId'] as String? ?? job['userId'] as String? ?? '').trim();

    if (component.isNyxian) {
      if (currentUserId != acceptedApplicantId) return false;
    } else {
      if (currentUserId != creatorId) return false;
    }

    return true;
  }

  @override
  Component build(BuildContext context) {
    if (!_isEligibleToDisplay()) {
      return div([]);
    }

    final s = component.state;
    final isDark = s.isDark;
    final job = s.selectedJobData!;
    final jobId = (job['id'] as String? ?? 'active-job').toString();
    final rawStatus = job['status'] as String? ?? 'Open';
    final rawStatusLower = rawStatus.toLowerCase();
    final subStatus =
        job['nyxianSubStatus'] as String? ??
        ((rawStatusLower == 'in progress' ||
                rawStatusLower == 'in_progress' ||
                rawStatusLower == 'ongoing' ||
                rawStatusLower == 'open')
            ? null
            : rawStatus);

    final pickupLat = (job['pickupLat'] as num).toDouble();
    final pickupLng = (job['pickupLng'] as num).toDouble();
    final destLat = (job['destinationLat'] as num).toDouble();
    final destLng = (job['destinationLng'] as num).toDouble();

    final courierLat = (job['nyxianLat'] as num?)?.toDouble() ?? s.userLatitude;
    final courierLng = (job['nyxianLng'] as num?)?.toDouble() ?? s.userLongitude;

    final bool pastPickup = subStatus == 'arrived_pickup' ||
        subStatus == 'paid_cashier' ||
        subStatus == 'in_transit' ||
        subStatus == 'arrived_dropoff';

    final bool hasDistinctCourierStart = (courierLat - pickupLat).abs() > 0.0005 ||
        (courierLng - pickupLng).abs() > 0.0005;

    final stops = pastPickup
        ? [
            NavWaypoint.fromCoords(
              latitude: pickupLat,
              longitude: pickupLng,
              title: job['pickupAddress'] as String? ?? '1st Point (Pickup)',
              id: 'pickup',
            ),
            NavWaypoint.fromCoords(
              latitude: destLat,
              longitude: destLng,
              title: job['destinationAddress'] as String? ?? 'Delivery Point',
              id: 'destination',
            ),
          ]
        : (hasDistinctCourierStart
            ? [
                NavWaypoint.fromCoords(
                  latitude: courierLat,
                  longitude: courierLng,
                  title: 'Start Location',
                  id: 'courier_start',
                ),
                NavWaypoint.fromCoords(
                  latitude: pickupLat,
                  longitude: pickupLng,
                  title: job['pickupAddress'] as String? ?? '1st Point (Pickup)',
                  id: 'pickup',
                ),
                NavWaypoint.fromCoords(
                  latitude: destLat,
                  longitude: destLng,
                  title: job['destinationAddress'] as String? ?? 'Delivery Point',
                  id: 'destination',
                ),
              ]
            : [
                NavWaypoint.fromCoords(
                  latitude: pickupLat,
                  longitude: pickupLng,
                  title: job['pickupAddress'] as String? ?? '1st Point (Pickup)',
                  id: 'pickup',
                ),
                NavWaypoint.fromCoords(
                  latitude: destLat,
                  longitude: destLng,
                  title: job['destinationAddress'] as String? ?? 'Delivery Point',
                  id: 'destination',
                ),
              ]);

    final acceptedApplicantId =
        (job['acceptedApplicantId'] as String? ?? '').trim();

    final navActions = [
      NavAction(
        label: 'Back',
        iconSvgPath:
            'M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z',
        onClick: () => s.exitJobDetails(),
      ),
      if (acceptedApplicantId.isNotEmpty)
        NavAction(
          label: 'Chat',
          iconSvgPath:
              'M20 2H4c-1.1 0-1.99.9-1.99 2L2 22l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z',
          badge: s.getUnreadChatCount(jobId) > 0
              ? '${s.getUnreadChatCount(jobId)}'
              : null,
          onClick: () => s.openChat(jobId),
        ),
      NavAction(
        label: 'Job Details',
        isPrimary: true,
        iconSvgPath:
            'M19 3h-4.18C14.4 1.84 13.3 1 12 1c-1.3 0-2.4.84-2.82 2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-7 0c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm2 14H7v-2h7v2zm3-4H7v-2h10v2zm0-4H7V7h10v2z',
        onClick: () => s.setState(() => s.showJobOrderDetails = true),
      ),
    ];

    return div(
      classes:
          'relative w-full h-full flex flex-col ${isDark ? "bg-zinc-950 text-white" : "bg-zinc-900 text-white"} overflow-hidden animate-fade-in',
      [
        // Live Navigation / Tracker Map - Fills 100% of remaining height
        div(
          classes: 'w-full h-full relative overflow-hidden',
          [
            ProviderScope(
              child: component.isNyxian
                  ? WebNavigationView(
                      key: ValueKey('driver-nav-$jobId-$pastPickup'),
                      containerId: 'driver-nav-map',
                      channelId: jobId,
                      stops: stops,
                      travelMode: NavTravelMode.car,
                      locationStream: BrowserGeolocationAdapter(
                        enableHighAccuracy: true,
                      ).stream(),
                      broadcaster: _broadcaster,
                      enableTts: true,
                      height: 100.percent,
                      isEmbedded: false,
                      isDraggable: false, // Non-draggable navigation view
                      themeAdaptive: true,
                      accentColor: '#6366f1',
                      actions: navActions,
                      onArrived: (stopCount) {
                        if (stopCount == 1 &&
                            !pastPickup &&
                            !_hasAutoUpdatedPickup &&
                            !s.isUpdatingSubStatus) {
                          _hasAutoUpdatedPickup = true;
                          s.handleUpdateNyxianSubStatus('arrived_pickup');
                        }
                      },
                    )
                  : WebFollowerView(
                      key: ValueKey('follower-nav-$jobId-$pastPickup'),
                      channelId: jobId,
                      containerId: 'follower-nav-map',
                      stops: stops,
                      travelMode: NavTravelMode.car,
                      streaming: _streaming,
                      autoSimulateIfIdle: false,
                      height: 100.percent,
                      isEmbedded: false,
                      isDraggable: false, // Non-draggable follower map
                      themeAdaptive: true,
                      accentColor: '#6366f1',
                      broadcasterTitle: job['acceptedApplicantName'] as String? ??
                          'Nyxian Courier',
                      broadcasterSubtitle: 'Live Delivery Tracking',
                      statusText: _subStatusLabel(subStatus),
                      actions: navActions,
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

