import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import 'package:headless_nav_jaspr/headless_nav_jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';

/// Vehicle Rental Live Tracking and Navigation Component for Tranyx Web.
///
/// Powered by `headless_nav_jaspr` (`WebNavigationView` for publisher/driver,
/// and `WebFollowerView` for subscriber/follower).
///
/// Enforces directional role resolving:
/// - Host is Publisher ONLY during delivery (`rentalType == 'deliver' && status == 'On the way to Rentee'`), while Rentee is Subscriber.
/// - Rentee is Publisher during return trip (`status == 'Returning'`), while Host is Subscriber.
/// - In self-pickup (`rentalType != 'deliver'`) or other states, neither is publisher.
class RentalTrackerMapComponent extends StatefulComponent {
  final TranyxAppState appState;

  const RentalTrackerMapComponent({
    required this.appState,
    super.key,
  });

  @override
  State<RentalTrackerMapComponent> createState() => _RentalTrackerMapState();
}

class _RentalTrackerMapState extends State<RentalTrackerMapComponent> {
  bool _isUpdating = false;
  bool _showConfirmCancel = false;

  void _closeModal() {
    component.appState.setState(() {
      component.appState.showRentalTrackerMap = false;
      component.appState.selectedRentalData = null;
    });
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      final r = component.appState.selectedRentalData;
      if (r == null) return;

      final rawId = (r['id'] ?? '').toString();
      final rentalId = (r['rentalId'] ?? r['propertyId'] ?? rawId).toString();
      final requestId = (r['currentRequestId'] ??
              r['requestId'] ??
              (r.containsKey('rentalId') || r.containsKey('propertyId')
                  ? rawId
                  : null))
          ?.toString();

      // Optimistic local state update
      r['status'] = newStatus;
      component.appState.setState(() {});

      if (newStatus == 'Completed' || newStatus == 'Complete') {
        await component.appState.firestore
            .completeRental(rentalId, requestId: requestId);
        _closeModal();
      } else {
        await component.appState.firestore
            .updateRentalStatus(rentalId, newStatus, requestId: requestId);
      }
    } catch (e) {
      print('Error updating rental status: $e');
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _handleCancelRental(String rentalId) async {
    setState(() => _isUpdating = true);
    try {
      final r = component.appState.selectedRentalData;
      final rawId = (r?['id'] ?? rentalId).toString();
      final targetRentalId =
          (r?['rentalId'] ?? r?['propertyId'] ?? rawId).toString();
      final targetReqId = (r?['currentRequestId'] ??
              r?['requestId'] ??
              (r?.containsKey('rentalId') == true ||
                      r?.containsKey('propertyId') == true
                  ? rawId
                  : null))
          ?.toString();

      await component.appState.firestore
          .cancelRental(targetRentalId, requestId: targetReqId);
      component.appState.showAppToast(
          'Booking Cancelled', 'The booking was successfully cancelled.');
      _closeModal();
    } catch (e) {
      print('Error cancelling rental: $e');
      component.appState
          .showAppToast('Error', 'Failed to cancel booking: $e');
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
    if (!component.appState.showRentalTrackerMap ||
        component.appState.selectedRentalData == null) {
      return div([]);
    }

    final isDark = component.appState.isDark;
    final selectedData = component.appState.selectedRentalData!;
    final lookupId =
        (selectedData['rentalId'] ?? selectedData['id']) as String?;
    final r = component.appState.realtimeRentals.firstWhere(
      (element) => element['id'] == lookupId,
      orElse: () => selectedData,
    );

    final currentUid = component.appState.userProfile?.uid ?? '';
    final hostId = (r['hostId'] ?? '').toString();
    final renteeId =
        (r['renteeId'] ?? selectedData['renteeId'] ?? '').toString();

    final isHost = currentUid.isNotEmpty && currentUid == hostId;
    final isRentee = currentUid.isNotEmpty && currentUid == renteeId;

    // Strict privacy guard: Only Host or designated Rentee can track
    if (!isHost && !isRentee) {
      Future.microtask(_closeModal);
      return div([]);
    }

    final status = r['status'] as String? ?? 'Unknown';
    final model = r['model'] ?? 'Unknown';
    final brand = r['brand'] ?? 'Unknown';
    final rentalType = r['rentalType'] as String? ?? 'pickup';
    final rentalId = (r['rentalId'] ?? r['id'] ?? '').toString();
    final channelId = 'rental_$rentalId';

    final addressLabel =
        rentalType == 'deliver' ? 'Delivery Address' : 'Pickup Location';
    final addressValue = rentalType == 'deliver'
        ? (r['deliveryAddress'] as String? ?? 'N/A')
        : (r['pickupAddress'] as String? ??
            r['pickupLocation'] as String? ??
            'N/A');

    // Directional Role Enforcement via shared helper
    final navRole = resolveRentalNavRole(
      currentUserId: currentUid,
      hostId: hostId,
      renteeId: renteeId,
      status: status,
      rentalType: rentalType,
    );

    final List<NavWaypoint> stops = _buildStops(r, status);

    return div(
      classes:
          'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-md animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-4xl h-[88vh] rounded-3xl shadow-2xl relative flex flex-col overflow-hidden ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"}',
          [
            // Header Bar
            div(
              classes:
                  'flex items-center justify-between px-6 py-4 border-b ${isDark ? "bg-zinc-900/95 border-zinc-800 text-white" : "bg-white border-zinc-200 text-zinc-900"} z-20',
              [
                div(classes: 'flex items-center gap-3', [
                  div(
                    classes:
                        'w-10 h-10 rounded-2xl flex items-center justify-center ${navRole == RentalNavRole.publisher ? "bg-blue-500/20 text-blue-500" : (navRole == RentalNavRole.subscriber ? "bg-indigo-500/20 text-indigo-500" : "bg-purple-500/20 text-purple-500")}',
                    [
                      lIcon(
                        navRole == RentalNavRole.publisher
                            ? 'navigation'
                            : (navRole == RentalNavRole.subscriber
                                ? 'radio'
                                : 'compass'),
                        cls: 'w-5 h-5',
                      ),
                    ],
                  ),
                  div([
                    h2(classes: 'text-lg font-bold leading-snug', [
                      Component.text(navRole == RentalNavRole.publisher
                          ? 'Turn-by-Turn Navigation'
                          : (navRole == RentalNavRole.subscriber
                              ? 'Live Vehicle Tracking'
                              : 'Rental Status & Tracking')),
                    ]),
                    p(
                      classes:
                          'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"}',
                      [
                        Component.text('$brand $model • '),
                        span(
                          classes:
                              'font-bold ${status == "On the way to Rentee" ? "text-blue-400" : (status == "Returning" ? "text-indigo-400" : (status == "Ongoing" ? "text-emerald-400" : "text-purple-400"))}',
                          [Component.text(status)],
                        ),
                      ],
                    ),
                  ]),
                ]),
                div(classes: 'flex items-center gap-2', [
                  if (_isUpdating)
                    lIcon('loader', cls: 'w-5 h-5 animate-spin text-purple-500'),
                  button(
                    classes:
                        'p-2 rounded-full hover:bg-zinc-800/20 transition-colors text-zinc-400 hover:text-white',
                    events: {'click': (_) => _closeModal()},
                    [lIcon('x', cls: 'w-5 h-5')],
                  ),
                ]),
              ],
            ),

            // Main Content Area: Switch between WebNavigationView, WebFollowerView, and Fallback Info View
            div(classes: 'flex-1 relative w-full h-full min-h-0 overflow-hidden', [
              if (navRole == RentalNavRole.publisher)
                WebNavigationView(
                  key: ValueKey('web-nav-$rentalId'),
                  containerId: 'rental-web-nav-map',
                  stops: stops,
                  travelMode: NavTravelMode.car,
                  channelId: channelId,
                  themeAdaptive: true,
                  isEmbedded: true,
                  height: 100.percent,
                  onClose: _closeModal,
                  actions: [
                    if (isHost && status == 'On the way to Rentee')
                      FollowerAction(
                        label: 'Handed Over (Ongoing)',
                        isPrimary: true,
                        iconSvgPath:
                            'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z',
                        onClick: () => _updateStatus('Ongoing'),
                      ),
                  ],
                )
              else if (navRole == RentalNavRole.subscriber)
                WebFollowerView(
                  key: ValueKey('web-follower-$rentalId'),
                  containerId: 'rental-web-follower-map',
                  channelId: channelId,
                  stops: stops,
                  themeAdaptive: true,
                  isEmbedded: true,
                  height: 100.percent,
                  broadcasterTitle: isHost
                      ? 'Renter Returning Vehicle'
                      : 'Host Delivering Vehicle',
                  broadcasterSubtitle: '$brand $model',
                  onClose: _closeModal,
                  actions: [
                    if (isHost && status == 'Returning')
                      FollowerAction(
                        label: 'Confirm Vehicle Returned',
                        isPrimary: true,
                        iconSvgPath:
                            'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z',
                        onClick: () => _updateStatus('Complete'),
                      ),
                  ],
                )
              else
                _buildInactiveRoleView(
                  isDark: isDark,
                  brand: brand,
                  model: model,
                  status: status,
                  rentalType: rentalType,
                  isHost: isHost,
                  isRentee: isRentee,
                  addressLabel: addressLabel,
                  addressValue: addressValue,
                  rentalId: rentalId,
                  rawRental: r,
                ),
            ]),

            // Bottom Action Strip (for cancellations, extensions, and general controls)
            _buildBottomControls(
              isDark: isDark,
              r: r,
              status: status,
              isHost: isHost,
              isRentee: isRentee,
              rentalType: rentalType,
              navRole: navRole,
            ),
          ],
        ),
      ],
    );
  }

  Component _buildInactiveRoleView({
    required bool isDark,
    required String brand,
    required String model,
    required String status,
    required String rentalType,
    required bool isHost,
    required bool isRentee,
    required String addressLabel,
    required String addressValue,
    required String rentalId,
    required Map<String, dynamic> rawRental,
  }) {
    String explanation;
    String badgeTitle;

    if (rentalType != 'deliver' && status == 'Booked') {
      badgeTitle = 'Self-Pickup Reservation';
      explanation = isHost
          ? 'This vehicle rental was booked for self-pickup. The renter will arrive at your designated pickup address to inspect and collect the vehicle.'
          : 'This is a self-pickup rental. Please proceed to the host\'s designated pickup location to inspect the vehicle and complete keys handover.';
    } else if (status == 'Ongoing') {
      badgeTitle = 'Active Rental In Progress';
      explanation =
          'The vehicle is currently in possession of the renter. Live turn-by-turn navigation and telemetry tracking will activate as soon as the return trip starts.';
    } else if (status == 'Completed' || status == 'Complete') {
      badgeTitle = 'Rental Completed';
      explanation =
          'This rental has concluded. The vehicle has been successfully returned and escrow settlement is complete.';
    } else {
      badgeTitle = 'Navigation Inactive';
      explanation =
          'Turn-by-turn navigation and live follower tracking are active only when the vehicle is being delivered by the host or returned by the rentee.';
    }

    return div(
      classes:
          'flex flex-col items-center justify-center p-8 h-full text-center max-w-xl mx-auto',
      [
        div(
          classes:
              'w-20 h-20 rounded-3xl flex items-center justify-center mb-6 shadow-xl ${isDark ? "bg-zinc-800/80 text-purple-400 border border-zinc-700" : "bg-purple-50 text-purple-600 border border-purple-100"}',
          [lIcon('compass', cls: 'w-10 h-10')],
        ),
        span(
          classes:
              'px-3.5 py-1 rounded-full text-xs font-black uppercase tracking-wider mb-3 ${isDark ? "bg-zinc-800 text-purple-400" : "bg-purple-100 text-purple-700"}',
          [Component.text(badgeTitle)],
        ),
        h3(
          classes:
              'text-2xl font-black mb-3 ${isDark ? "text-white" : "text-zinc-900"}',
          [Component.text('$brand $model')],
        ),
        p(
          classes:
              'text-sm leading-relaxed mb-6 ${isDark ? "text-zinc-400" : "text-zinc-600"}',
          [Component.text(explanation)],
        ),
        div(
          classes:
              'w-full p-4 rounded-2xl mb-6 text-left border ${isDark ? "bg-zinc-800/40 border-zinc-800" : "bg-zinc-50 border-zinc-200"}',
          [
            div(classes: 'text-[10px] font-bold uppercase tracking-wider text-purple-500 mb-1', [
              Component.text(addressLabel),
            ]),
            div(classes: 'text-sm font-semibold ${isDark ? "text-zinc-200" : "text-zinc-800"}', [
              Component.text(addressValue),
            ]),
          ],
        ),
      ],
    );
  }

  Component _buildBottomControls({
    required bool isDark,
    required Map<String, dynamic> r,
    required String status,
    required bool isHost,
    required bool isRentee,
    required String rentalType,
    required RentalNavRole navRole,
  }) {
    final showCancelButton = (isRentee && status == 'Booked') ||
        (isHost && (status == 'Booked' || status == 'On the way to Rentee'));

    return div(
      classes:
          'px-6 py-4 border-t ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200"} z-20 flex flex-col gap-3',
      [
        if (_showConfirmCancel) ...[
          div(
            classes:
                'p-4 rounded-2xl bg-red-500/10 border border-red-500/20 text-sm flex flex-col gap-3',
            [
              div(classes: 'flex items-center gap-2 text-red-400 font-bold', [
                lIcon('alert-triangle', cls: 'w-5 h-5 flex-shrink-0'),
                span([Component.text('Confirm Cancellation')]),
              ]),
              p(classes: 'text-zinc-400 text-xs', [
                Component.text(
                  isRentee
                      ? 'Are you sure you want to cancel this booking? Note that the 3% platform booking fee is non-refundable.'
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
            ],
          ),
        ] else ...[
          div(classes: 'flex items-center gap-3', [
            // Host: Start Delivery or Handover
            if (isHost && status == 'Booked')
              button(
                classes:
                    'flex-1 py-3 px-4 rounded-xl font-bold text-white bg-purple-600 hover:bg-purple-700 transition-colors text-sm',
                events: {
                  'click': (_) => _updateStatus(
                      rentalType == 'deliver' ? 'On the way to Rentee' : 'Ongoing')
                },
                disabled: _isUpdating,
                [
                  Component.text(rentalType == 'deliver'
                      ? 'Start Delivery (On the way)'
                      : 'Hand Over & Start Rental'),
                ],
              ),

            // Host: Handover if delivery in progress
            if (isHost && status == 'On the way to Rentee' && navRole != RentalNavRole.publisher)
              button(
                classes:
                    'flex-1 py-3 px-4 rounded-xl font-bold text-white bg-green-600 hover:bg-green-700 transition-colors text-sm',
                events: {'click': (_) => _updateStatus('Ongoing')},
                disabled: _isUpdating,
                [Component.text('Handed Over (Ongoing)')],
              ),

            // Rentee: Start Return Trip
            if (isRentee && status == 'Ongoing') ...[
              button(
                classes:
                    'flex-1 py-3 px-4 rounded-xl font-bold text-white bg-blue-600 hover:bg-blue-700 transition-colors text-sm',
                events: {'click': (_) => _updateStatus('Returning')},
                disabled: _isUpdating,
                [Component.text('Start Return Trip')],
              ),
              button(
                classes:
                    'py-3 px-4 rounded-xl font-bold text-purple-400 bg-purple-500/10 hover:bg-purple-500/20 transition-colors text-sm',
                events: {
                  'click': (_) => component.appState.setState(
                      () => component.appState.showExtendRentalModal = true),
                },
                disabled: _isUpdating,
                [Component.text('Extend Rental')],
              ),
            ],

            // Host: Confirm Vehicle Returned
            if (isHost && status == 'Returning' && navRole != RentalNavRole.subscriber)
              button(
                classes:
                    'flex-1 py-3 px-4 rounded-xl font-bold text-white bg-green-600 hover:bg-green-700 transition-colors text-sm',
                events: {'click': (_) => _updateStatus('Complete')},
                disabled: _isUpdating,
                [Component.text('Confirm Vehicle Returned')],
              ),

            // Completed badge
            if (status == 'Complete' || status == 'Completed')
              div(
                classes:
                    'flex-1 p-3 rounded-xl text-center bg-green-500/10 border border-green-500/20 text-green-500 font-bold text-sm',
                [Component.text('Rental Completed')],
              ),

            // Cancel Button
            if (showCancelButton)
              button(
                classes:
                    'px-4 py-3 rounded-xl font-bold text-red-500 border border-red-500/20 hover:bg-red-500/10 transition-all flex-shrink-0',
                events: {'click': (_) => setState(() => _showConfirmCancel = true)},
                disabled: _isUpdating,
                [lIcon('trash-2', cls: 'w-5 h-5')],
              ),
          ]),
        ],
      ],
    );
  }

  List<NavWaypoint> _buildStops(Map<String, dynamic> r, String status) {
    if (status == 'On the way to Rentee') {
      final destLat = (r['deliveryLat'] as num?)?.toDouble() ??
          (r['dropoffLat'] as num?)?.toDouble() ??
          (r['pickupLat'] as num?)?.toDouble() ??
          14.5995;
      final destLng = (r['deliveryLng'] as num?)?.toDouble() ??
          (r['dropoffLng'] as num?)?.toDouble() ??
          (r['pickupLng'] as num?)?.toDouble() ??
          120.9842;
      final destTitle =
          (r['deliveryAddress'] as String?) ?? 'Rentee Delivery Location';

      return [
        NavWaypoint.fromCoords(
          latitude: destLat,
          longitude: destLng,
          title: destTitle,
        ),
      ];
    } else if (status == 'Returning') {
      final destLat = (r['pickupLat'] as num?)?.toDouble() ??
          (r['returnLat'] as num?)?.toDouble() ??
          14.5995;
      final destLng = (r['pickupLng'] as num?)?.toDouble() ??
          (r['returnLng'] as num?)?.toDouble() ??
          120.9842;
      final destTitle = (r['pickupAddress'] as String?) ??
          (r['pickupLocation'] as String?) ??
          'Host Return Location';

      return [
        NavWaypoint.fromCoords(
          latitude: destLat,
          longitude: destLng,
          title: destTitle,
        ),
      ];
    }

    return const [];
  }
}
