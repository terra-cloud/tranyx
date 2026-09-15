import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../services/web_interop.dart';

class ManageVehicleModalComponent extends StatefulComponent {
  final TranyxAppState appState;
  const ManageVehicleModalComponent({required this.appState, super.key});

  @override
  State<ManageVehicleModalComponent> createState() => _ManageVehicleModalState();
}

class _ManageVehicleModalState extends State<ManageVehicleModalComponent> {
  bool _isLoadingRequests = false;
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _extensions = [];
  String? _error;
  bool _isProcessing = false;
  bool _showConfirmDelete = false;
  bool _showPendingWarning = false;

  bool _allowChat = false;

  bool _isEditingGps = false;
  String _gpsInput = '';
  bool _isSavingGps = false;
  bool _hasReservationRecords = false;

  void _toggleAcceptingBookings(bool currentlyAccepting) async {
    final r = component.appState.selectedRentalData;
    if (r == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final newAccepting = !currentlyAccepting;
      await component.appState.firestore.setVehicleAcceptingBookings(r['id'], newAccepting);
      final newStatus = newAccepting ? 'Available' : 'Not Accepting Bookings';
      component.appState.setState(() {
        final updated = Map<String, dynamic>.from(r);
        updated['acceptingBookings'] = newAccepting;
        updated['status'] = newStatus;
        component.appState.selectedRentalData = updated;
      });
      component.appState.alertDialog(
        newAccepting ? 'Bookings Resumed' : 'Bookings Paused',
        newAccepting
            ? 'Your vehicle is now accepting booking requests in the marketplace.'
            : 'Your vehicle will no longer accept new booking requests. Existing bookings remain active.',
      );
    } catch (e) {
      setState(() => _error = 'Failed to update booking status: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRequests();
    final r = component.appState.selectedRentalData;
    _gpsInput = r?['gpsTrackerId']?.toString() ?? '';
  }

  void _loadRequests() async {
    final r = component.appState.selectedRentalData;
    if (r == null) return;

    setState(() {
      _isLoadingRequests = true;
      _error = null;
    });

    try {
      final extList = await component.appState.firestore.getPendingExtensionsForVehicle(r['id']);
      final allList = await component.appState.firestore.getAllRequestsForVehicle(r['id']);
      allList.sort((reqA, reqB) {
        final aPending = (reqA['status']?.toString().toLowerCase() == 'pending') ? 0 : 1;
        final bPending = (reqB['status']?.toString().toLowerCase() == 'pending') ? 0 : 1;
        if (aPending != bPending) return aPending.compareTo(bPending);
        final aTime = (reqA['startDate'] as int?) ?? (reqA['createdAt'] as int?) ?? 0;
        final bTime = (reqB['startDate'] as int?) ?? (reqB['createdAt'] as int?) ?? 0;
        return bTime.compareTo(aTime);
      });
      setState(() {
        _requests = allList;
        _extensions = extList;
        _hasReservationRecords = allList.isNotEmpty;
      });
    } catch (e) {
      setState(() => _error = 'Failed to load requests & extensions: $e');
    } finally {
      setState(() => _isLoadingRequests = false);
    }
  }

  void _approveRequest(String requestId) async {
    if (_isProcessing) return;
    final r = component.appState.selectedRentalData;
    if (r == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.approveBookingRequest(requestId, r['id'], _allowChat);

      component.appState.showAppToast(
        'Rental Request Accepted',
        "Booking request approved. Awaiting renter's signature.",
      );

      // Close modal and clear selected state
      component.appState.setState(() {
        component.appState.showManageVehicleModal = false;
        component.appState.selectedRentalData = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _rejectRequest(String requestId) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.rejectBookingRequest(requestId);
      _loadRequests(); // Refresh request list
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _approveExtension(String extensionId) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.approveExtension(extensionId);

      // Reload rental details to get updated end date
      final r = component.appState.selectedRentalData;
      if (r != null) {
        final updatedRental = await component.appState.firestore.getRental(r['id']);
        if (updatedRental != null) {
          component.appState.setState(() {
            component.appState.selectedRentalData = updatedRental.toMap();
          });
        }
      }

      _loadRequests(); // Refresh lists
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _rejectExtension(String extensionId) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.rejectExtension(extensionId);
      _loadRequests(); // Refresh lists
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _deleteListing(String rentalId) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.deleteRental(rentalId);
      await component.appState.loadUserProfile();
      component.appState.walletBalance = component.appState.userProfile?.tyxBalance ?? component.appState.walletBalance;

      component.appState.setState(() {
        component.appState.showManageVehicleModal = false;
        component.appState.selectedRentalData = null;
      });
      component.appState.alertDialog('Listing Cancelled', 'The vehicle listing has been cancelled and your listing fee has been refunded to your wallet.');
    } catch (e) {
      setState(() => _error = 'Failed to delete listing: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _updateStatus(String newStatus) async {
    final r = component.appState.selectedRentalData;
    if (r == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      if (newStatus == 'Completed') {
        await component.appState.firestore.completeRental(r['id']);
      } else {
        await component.appState.firestore.updateRentalStatus(r['id'], newStatus);
      }

      // Close modal and clear selected state
      component.appState.setState(() {
        component.appState.showManageVehicleModal = false;
        component.appState.selectedRentalData = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _updateBookingStatus(String requestId, String newStatus) async {
    final r = component.appState.selectedRentalData;
    if (r == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      if (newStatus == 'Completed') {
        await component.appState.firestore.completeRental(r['id'], requestId: requestId);
      } else {
        await component.appState.firestore.updateRentalStatus(r['id'], newStatus, requestId: requestId);
      }
      _loadRequests();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _revokeApproval(String? requestId) async {
    final r = component.appState.selectedRentalData;
    if (r == null) return;

    final confirmed = confirmDialog(
      'Are you sure you want to revoke approval for this booking request? The renter will be 100% refunded and the vehicle will reopen for new bookings.',
    );
    if (!confirmed) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.revokeApproval(r['id'], requestId: requestId);
      await component.appState.loadUserProfile();
      component.appState.showAppToast('Approval Revoked', 'Request cancelled and renter fully refunded.');
      _loadRequests();
      component.appState.setState(() {
        component.appState.showManageVehicleModal = false;
        component.appState.selectedRentalData = null;
      });
    } catch (e) {
      setState(() => _error = 'Failed to revoke approval: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _cancelRental(String? requestId) async {
    final r = component.appState.selectedRentalData;
    if (r == null) return;

    final confirmed = confirmDialog(
      'Are you sure you want to cancel this rental booking? The renter will be refunded minus the standard platform cancellation fee.',
    );
    if (!confirmed) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.cancelRental(r['id'], requestId: requestId);
      await component.appState.loadUserProfile();
      component.appState.showAppToast('Rental Cancelled', 'The rental has been cancelled and refunded.');
      _loadRequests();
      component.appState.setState(() {
        component.appState.showManageVehicleModal = false;
        component.appState.selectedRentalData = null;
      });
    } catch (e) {
      setState(() => _error = 'Failed to cancel rental: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _saveGps() async {
    final r = component.appState.selectedRentalData;
    if (r == null) return;

    setState(() {
      _isSavingGps = true;
      _error = null;
    });

    try {
      await component.appState.firestore.updateVehicleGpsTracker(r['id'], _gpsInput.trim());

      component.appState.setState(() {
        final updated = Map<String, dynamic>.from(r);
        updated['gpsTrackerId'] = _gpsInput.trim();
        component.appState.selectedRentalData = updated;
      });

      setState(() {
        _isEditingGps = false;
      });

      component.appState.showAppToast(
        'GPS Tracker Updated',
        'The GPS Tracker Device ID has been successfully registered.',
      );
    } catch (e) {
      setState(() => _error = 'Failed to update GPS tracker: $e');
    } finally {
      setState(() => _isSavingGps = false);
    }
  }

  @override
  Component build(BuildContext context) {
    final isDark = component.appState.isDark;
    final r = component.appState.selectedRentalData;
    if (r == null) return div([]);

    final status = r['status'] as String? ?? 'Available';
    final isNotAccepting = status == 'Not Accepting Bookings' || r['acceptingBookings'] == false;
    final hasPending = _requests.any((req) => req['status']?.toString().toLowerCase() == 'pending');
    final hasConfirmed = _requests.any((req) => BookingDateRange.fromMap(req).isConfirmedBooking);
    final model = r['model'] ?? 'Unknown Model';
    final brand = r['brand'] ?? 'Unknown Brand';
    final year = r['year'] ?? '';
    final plateNumber = r['plateNumber'] ?? 'N/A';
    final dailyRate = r['dailyRate'] ?? r['priceDaily'] ?? 0.0;
    final rentalType = r['rentalType'] as String? ?? 'pickup';

    final modalCls = isDark ? 'bg-zinc-900 border border-zinc-800 text-white' : 'bg-white text-zinc-900 shadow-xl';

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in',
      [
        div(
          classes: 'w-full max-w-2xl rounded-3xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh] $modalCls',
          [
            // Header
            div(
              classes:
                  'p-6 border-b ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center justify-between',
              [
                div([
                  h2(classes: 'text-xl font-black tracking-tight', [Component.text('Manage Vehicle')]),
                  p(classes: 'text-sm text-zinc-500', [Component.text('$brand $model ($year) • Plate: $plateNumber')]),
                ]),
                button(
                  classes: 'p-2 rounded-full hover:bg-zinc-800/20 transition-colors',
                  events: {
                    'click': (_) => component.appState.setState(() {
                      component.appState.showManageVehicleModal = false;
                      component.appState.selectedRentalData = null;
                    }),
                  },
                  [lIcon('x', cls: 'w-6 h-6')],
                ),
              ],
            ),

            // Content
            div(classes: 'p-6 overflow-y-auto space-y-6 flex-1', [
              if (_error != null)
                div(
                  classes:
                      'mb-4 p-4 rounded-2xl bg-red-500/10 border border-red-500/20 text-red-400 text-sm flex items-center gap-2',
                  [
                    lIcon('alert-circle', cls: 'w-5 h-5 flex-shrink-0'),
                    span([Component.text(_error!)]),
                  ],
                ),

              if (isNotAccepting)
                div(classes: 'mb-4 p-3.5 rounded-2xl bg-amber-500/10 border border-amber-500/30 text-amber-400 text-xs flex items-center justify-between', [
                  div(classes: 'flex items-center gap-2', [
                    lIcon('pause-circle', cls: 'w-4 h-4 flex-shrink-0 text-amber-400'),
                    span([Component.text('This vehicle is currently paused and not accepting new bookings in the marketplace.')]),
                  ]),
                  span(classes: 'px-2 py-0.5 rounded text-[10px] font-bold bg-amber-500/20 text-amber-300', [
                    Component.text('NOT ACCEPTING BOOKINGS'),
                  ]),
                ]),

              // Status Summary Card
              div(
                classes:
                    'p-5 rounded-2xl mb-6 flex items-center justify-between ${isDark ? "bg-zinc-800/40 border border-zinc-800" : "bg-zinc-50 border border-zinc-200"}',
                [
                  div([
                    p(classes: 'text-xs text-zinc-550 font-bold uppercase tracking-wider mb-1', [
                      Component.text('Current Status'),
                    ]),
                    h3(classes: 'text-lg font-bold capitalize ${isNotAccepting ? "text-amber-400" : "text-purple-400"}', [
                      Component.text(isNotAccepting ? 'Not Accepting Bookings' : status),
                    ]),
                  ]),
                  div(classes: 'text-right', [
                    p(classes: 'text-xs text-zinc-550 font-bold uppercase tracking-wider mb-1', [
                      Component.text('Daily Rate'),
                    ]),
                    h3(classes: 'text-lg font-extrabold', [Component.text('₱$dailyRate/day')]),
                  ]),
                ],
              ),

              // GPS Hardware Tracker Card
              div(
                classes:
                    'p-5 rounded-2xl mb-6 border ${isDark ? "bg-zinc-800/25 border-zinc-800" : "bg-zinc-50/50 border-zinc-200"} flex flex-col gap-3',
                [
                  div(classes: 'flex items-center justify-between', [
                    div(classes: 'flex items-center gap-2', [
                      lIcon(
                        'activity',
                        cls: 'w-4.5 h-4.5 text-indigo-400 ${_gpsInput.isNotEmpty ? "animate-pulse" : ""}',
                      ),
                      span(classes: 'text-xs font-bold text-zinc-500 uppercase tracking-wider', [
                        Component.text('GPS Hardware Tracker'),
                      ]),
                    ]),
                    if (!_isEditingGps)
                      button(
                        classes:
                            'text-xs font-semibold text-indigo-400 hover:text-indigo-300 flex items-center gap-1 bg-transparent border-0 cursor-pointer',
                        events: {
                          'click': (_) {
                            setState(() {
                              _gpsInput = r['gpsTrackerId']?.toString() ?? '';
                              _isEditingGps = true;
                            });
                          },
                        },
                        [
                          lIcon('edit-2', cls: 'w-3.5 h-3.5'),
                          Component.text(
                            r['gpsTrackerId'] != null && r['gpsTrackerId'].toString().isNotEmpty ? 'Edit' : 'Register',
                          ),
                        ],
                      ),
                  ]),
                  if (_isEditingGps)
                    div(classes: 'flex flex-col gap-3', [
                      div(classes: 'flex items-center gap-2', [
                        input(
                          classes:
                              'flex-1 px-4 py-2.5 rounded-xl border text-sm focus:outline-none focus:ring-1 focus:ring-purple-500 '
                              '${isDark ? "bg-zinc-950 border-zinc-850 text-white focus:border-purple-500" : "bg-white border-zinc-250 text-zinc-800 focus:border-purple-500"}',
                          attributes: {
                            'type': 'text',
                            'value': _gpsInput,
                            'placeholder': 'Enter GPS Tracker Device ID (e.g. GPS-99081)',
                          },
                          events: {
                            'input': (e) {
                              final val = getInputValue(e.target);
                              setState(() => _gpsInput = val);
                            },
                          },
                        ),
                      ]),
                      div(classes: 'flex items-center gap-2 justify-end', [
                        button(
                          classes:
                              'px-3 py-1.5 rounded-lg border text-xs font-bold transition-all cursor-pointer '
                              '${isDark ? "border-zinc-700 hover:bg-zinc-800 text-zinc-400" : "border-zinc-200 hover:bg-zinc-50 text-zinc-500"}',
                          events: {'click': (_) => setState(() => _isEditingGps = false)},
                          disabled: _isSavingGps,
                          [Component.text('Cancel')],
                        ),
                        button(
                          classes:
                              'px-3 py-1.5 rounded-lg text-xs font-bold text-white logo-gradient hover:opacity-90 disabled:opacity-50 transition-opacity cursor-pointer',
                          events: {'click': (_) => _saveGps()},
                          disabled: _isSavingGps,
                          [Component.text(_isSavingGps ? 'Saving...' : 'Save Tracker')],
                        ),
                      ]),
                    ])
                  else
                    div([
                      if (r['gpsTrackerId'] != null && r['gpsTrackerId'].toString().isNotEmpty)
                        p(classes: 'text-sm font-bold text-green-400', [
                          Component.text('Registered ID: ${r['gpsTrackerId']} (Status: Online)'),
                        ])
                      else
                        p(classes: 'text-sm font-bold text-amber-500 flex items-center gap-1', [
                          lIcon('alert-triangle', cls: 'w-4 h-4 text-amber-500'),
                          Component.text('No active GPS hardware registered. Host is exposed to theft risk.'),
                        ]),
                    ]),
                  p(
                    classes:
                        'text-[11px] text-zinc-500 italic mt-1 pt-2 border-t ${isDark ? "border-zinc-800/60" : "border-zinc-200"}',
                    [
                      Component.text(
                        'Note: Real-time vehicle tracking functions only when the active renter is logged into the app on their device with location permissions enabled.',
                      ),
                    ],
                  ),
                ],
              ),

              // Host Listing Controls (Edit, Pause/Resume, Delete)
              if (_showPendingWarning)
                div(classes: 'mb-6 p-4 rounded-2xl bg-amber-500/10 border border-amber-500/30 text-sm flex flex-col gap-3', [
                  div(classes: 'flex items-center gap-2 text-amber-400 font-bold', [
                    lIcon('alert-triangle', cls: 'w-5 h-5 flex-shrink-0'),
                    span([Component.text('Pending Requests Need Resolution')]),
                  ]),
                  p(classes: 'text-zinc-300 text-xs leading-relaxed', [
                    Component.text(
                      'You have pending booking requests for this listing. Please accept or reject all pending requests before deleting this listing.',
                    ),
                  ]),
                  div(classes: 'flex items-center gap-2 mt-1', [
                    button(
                      classes:
                          'px-3.5 py-1.5 rounded-lg bg-amber-500 text-black font-bold text-xs hover:bg-amber-400 transition-colors cursor-pointer',
                      events: {
                        'click': (_) {
                          setState(() => _showPendingWarning = false);
                          web.document.getElementById('vehicle_booking_requests_feed')?.scrollIntoView();
                        },
                      },
                      [Component.text('View Pending Requests')],
                    ),
                    button(
                      classes:
                          'px-3.5 py-1.5 rounded-lg border border-zinc-700 text-zinc-400 hover:text-white font-bold text-xs transition-colors cursor-pointer',
                      events: {'click': (_) => setState(() => _showPendingWarning = false)},
                      [Component.text('Close')],
                    ),
                  ]),
                ])
              else if (_showConfirmDelete)
                div(classes: 'mb-6 p-4 rounded-2xl bg-red-500/10 border border-red-500/20 text-sm flex flex-col gap-3', [
                  div(classes: 'flex items-center gap-2 text-red-400 font-bold', [
                    lIcon('alert-triangle', cls: 'w-5 h-5 flex-shrink-0'),
                    span([Component.text(hasConfirmed ? 'Confirm Listing Deletion' : 'Delete Listing')]),
                  ]),
                  p(classes: 'text-zinc-300 text-xs leading-relaxed', [
                    Component.text(
                      hasConfirmed
                          ? 'This listing has existing bookings. Deleting the listing will prevent new bookings, but your existing bookings will remain active and accessible. Are you sure you want to delete this listing?'
                          : 'Are you sure you want to delete this listing? This will permanently remove the vehicle from active listings.',
                    ),
                  ]),
                  div(classes: 'flex items-center gap-2 mt-1', [
                    button(
                      classes:
                          'px-3.5 py-1.5 rounded-lg bg-red-500 text-white font-bold text-xs hover:bg-red-600 transition-colors cursor-pointer',
                      events: {'click': (_) => _deleteListing(r['id'])},
                      disabled: _isProcessing,
                      [Component.text(hasConfirmed ? 'Delete Listing' : 'Yes, Delete')],
                    ),
                    button(
                      classes:
                          'px-3.5 py-1.5 rounded-lg border border-zinc-700 text-zinc-400 hover:text-white font-bold text-xs transition-colors cursor-pointer',
                      events: {'click': (_) => setState(() => _showConfirmDelete = false)},
                      disabled: _isProcessing,
                      [Component.text('Cancel')],
                    ),
                  ]),
                ])
              else
                div(classes: 'mb-6 flex flex-wrap items-center justify-between gap-3', [
                  div(classes: 'flex items-center gap-2', [
                    if (!_hasReservationRecords &&
                        status == 'Available' &&
                        (r['renteeId'] == null || (r['renteeId'] as String).isEmpty))
                      button(
                        classes:
                            'px-4 py-2 text-xs font-bold text-indigo-400 border border-indigo-500/30 hover:bg-indigo-500/10 rounded-xl transition-all flex items-center gap-1.5 cursor-pointer bg-transparent',
                        events: {
                          'click': (_) {
                            component.appState.setState(() {
                              component.appState.showManageVehicleModal = false;
                              component.appState.showEditVehicleModal = true;
                            });
                          },
                        },
                        disabled: _isProcessing,
                        [
                          lIcon('edit-3', cls: 'w-4 h-4 text-indigo-400'),
                          Component.text('Edit Listing'),
                        ],
                      ),
                    if (isNotAccepting)
                      button(
                        classes:
                            'px-4 py-2 text-xs font-bold text-emerald-400 border border-emerald-500/30 hover:bg-emerald-500/10 rounded-xl transition-all flex items-center gap-1.5 cursor-pointer bg-transparent',
                        events: {'click': (_) => _toggleAcceptingBookings(false)},
                        disabled: _isProcessing,
                        [
                          lIcon('play', cls: 'w-4 h-4 text-emerald-400'),
                          Component.text('Resume Bookings'),
                        ],
                      )
                    else
                      button(
                        classes:
                            'px-4 py-2 text-xs font-bold text-amber-400 border border-amber-500/30 hover:bg-amber-500/10 rounded-xl transition-all flex items-center gap-1.5 cursor-pointer bg-transparent',
                        events: {'click': (_) => _toggleAcceptingBookings(true)},
                        disabled: _isProcessing,
                        [
                          lIcon('pause', cls: 'w-4 h-4 text-amber-400'),
                          Component.text('Stop Receiving Bookings'),
                        ],
                      ),
                  ]),
                  button(
                    classes:
                        'px-4 py-2 text-xs font-bold text-red-500 border border-red-500/20 hover:bg-red-500/10 rounded-xl transition-all flex items-center gap-1.5 cursor-pointer bg-transparent',
                    events: {
                      'click': (_) {
                        if (hasPending) {
                          setState(() {
                            _showPendingWarning = true;
                            _showConfirmDelete = false;
                          });
                        } else {
                          setState(() {
                            _showConfirmDelete = true;
                            _showPendingWarning = false;
                          });
                        }
                      },
                    },
                    disabled: _isProcessing,
                    [
                      lIcon('trash-2', cls: 'w-4 h-4'),
                      Component.text('Delete Listing'),
                    ],
                  ),
                ]),

              if (status != 'Available' && status != 'Not Accepting Bookings' && r['renteeId'] != null && (r['renteeId'] as String).isNotEmpty) ...[
                // Active Booking Details View
                h3(classes: 'text-sm font-bold text-zinc-400 uppercase tracking-wider mb-4', [
                  Component.text('Active Renter Info'),
                ]),
                div(
                  classes:
                      'p-5 rounded-2xl border mb-6 ${isDark ? "bg-zinc-950 border-zinc-800" : "bg-white border-zinc-200 shadow-sm"}',
                  [
                    div(classes: 'flex items-center justify-between gap-3 mb-4', [
                      div(classes: 'flex items-center gap-3', [
                        div(
                          classes:
                              'w-12 h-12 rounded-full bg-purple-500/20 flex items-center justify-center overflow-hidden',
                          [
                            if (r['renteePhotoUrl'] != null &&
                                r['renteePhotoUrl'].toString().isNotEmpty &&
                                r['renteePhotoUrl'].toString() != 'null')
                              img(
                                src: r['renteePhotoUrl'].toString(),
                                classes:
                                    'w-full h-full object-cover cursor-zoom-in hover:opacity-90 transition-opacity',
                                events: {
                                  'click': (_) =>
                                      component.appState.showFullScreenPhoto(r['renteePhotoUrl'].toString()),
                                },
                              )
                            else
                              lIcon('user', cls: 'w-6 h-6 text-purple-400'),
                          ],
                        ),
                        div([
                          p(classes: 'font-extrabold text-base flex items-center gap-2', [
                            Component.text(r['renteeName'] ?? 'Active Renter'),
                            if (r['hireWithDriver'] == true)
                              span(
                                classes:
                                    'text-[10px] font-bold px-2 py-0.5 rounded-full bg-purple-500/20 text-purple-400 border border-purple-500/30',
                                [Component.text('With Driver')],
                              ),
                          ]),
                          p(classes: 'text-xs text-zinc-500', [
                            Component.text('License: ${_obscureLicenseNumber(r["renteeLicenseNumber"]?.toString())}'),
                          ]),
                        ]),
                      ]),
                      if (r['allowChat'] == true)
                        () {
                          final chatId = 'rental_${r['id']}_${r['renteeId']}';
                          return button(
                            classes:
                                'px-3 py-1.5 rounded-lg text-xs font-bold text-blue-400 hover:bg-blue-500/15 border border-blue-500/30 cursor-pointer bg-transparent relative',
                            events: {
                              'click': (_) {
                                component.appState.setState(() {
                                  component.appState.showManageVehicleModal = false;
                                });
                                component.appState.openChat(chatId);
                              },
                            },
                            [
                              lIcon('message-square', cls: 'w-3.5 h-3.5 mr-1 inline'),
                              Component.text('Chat Renter'),
                              if (component.appState.getUnreadChatCount(chatId) > 0)
                                span(
                                  classes:
                                      'absolute -top-1 -right-1 px-1.5 py-0.5 text-[9px] font-black text-white bg-red-500 rounded-full border border-white animate-pulse',
                                  [Component.text('${component.appState.getUnreadChatCount(chatId)}')],
                                ),
                            ],
                          );
                        }(),
                    ]),

                    // Contract Duration / Details
                    div(
                      classes: 'p-4 rounded-xl text-sm ${isDark ? "bg-zinc-900/60" : "bg-zinc-50"} flex flex-col gap-2',
                      [
                        div(classes: 'flex justify-between', [
                          span(classes: 'text-zinc-500', [Component.text('Package:')]),
                          span(classes: 'font-bold capitalize', [
                            Component.text('${r["rentalMultiplier"]} ${r["rentalDurationType"]}'),
                          ]),
                        ]),
                        div(classes: 'flex justify-between', [
                          span(classes: 'text-zinc-500', [Component.text('Total Cost:')]),
                          span(classes: 'font-black text-purple-400', [Component.text('₱${r["totalCost"]}')]),
                        ]),
                        if (r['startDate'] != null)
                          div(classes: 'flex justify-between', [
                            span(classes: 'text-zinc-500', [Component.text('Start Date:')]),
                            span([
                              Component.text(
                                DateTime.fromMillisecondsSinceEpoch(r['startDate'] as int).toString().substring(0, 16),
                              ),
                            ]),
                          ]),
                        if (r['endDate'] != null)
                          div(classes: 'flex justify-between', [
                            span(classes: 'text-zinc-500', [Component.text('End Date:')]),
                            span([
                              Component.text(
                                DateTime.fromMillisecondsSinceEpoch(r['endDate'] as int).toString().substring(0, 16),
                              ),
                            ]),
                          ]),
                        if (r['renteeSignatureName'] != null)
                          div(
                            classes:
                                'flex flex-col gap-1.5 mt-2 pt-2 border-t ${isDark ? "border-zinc-800" : "border-zinc-200"}',
                            [
                              span(classes: 'text-zinc-500 text-xs', [Component.text('Contract Signature:')]),
                              if (r['renteeSignatureName'].toString().startsWith('data:image/'))
                                img(
                                  src: r['renteeSignatureName'].toString(),
                                  classes:
                                      'max-h-16 h-auto object-contain bg-white rounded-lg p-1 max-w-[200px] mt-1 cursor-zoom-in hover:opacity-90 transition-opacity',
                                  events: {
                                    'click': (_) =>
                                        component.appState.showFullScreenPhoto(r['renteeSignatureName'].toString()),
                                  },
                                )
                              else
                                span(classes: 'font-bold italic text-purple-400', [
                                  Component.text(r['renteeSignatureName'] ?? 'Unsigned'),
                                ]),
                            ],
                          ),
                      ],
                    ),

                    if (_extensions.isNotEmpty) ...[
                      h3(classes: 'text-sm font-bold text-zinc-400 uppercase tracking-wider mb-4 mt-6', [
                        Component.text('Pending Extension Requests (${_extensions.length})'),
                      ]),
                      div(classes: 'flex flex-col gap-4 mb-6', [
                        for (final ext in _extensions)
                          div(
                            classes:
                                'p-5 rounded-2xl border transition-all ${isDark ? "bg-zinc-950 border-zinc-800 hover:border-zinc-700" : "bg-white border-zinc-200 hover:shadow-md"}',
                            [
                              div(classes: 'flex items-start justify-between mb-4', [
                                div([
                                  p(classes: 'font-bold text-sm', [Component.text('Extension Request')]),
                                  p(classes: 'text-xs text-zinc-500 mt-1', [
                                    Component.text(
                                      'Requested: ${DateTime.fromMillisecondsSinceEpoch(ext["createdAt"] ?? 0).toString().substring(0, 16)}',
                                    ),
                                  ]),
                                ]),
                                div(classes: 'text-right', [
                                  p(classes: 'font-black text-purple-400', [Component.text('₱${ext["fee"]}')]),
                                  p(classes: 'text-xs text-zinc-500', [
                                    Component.text('+${ext["extendHours"]} hour(s)'),
                                  ]),
                                ]),
                              ]),
                              div(classes: 'flex items-center gap-2', [
                                button(
                                  classes:
                                      'flex-1 py-2 rounded-xl text-sm font-semibold text-white logo-gradient hover:opacity-90 disabled:opacity-50 transition-opacity',
                                  events: {'click': (_) => _approveExtension(ext['id'])},
                                  disabled: _isProcessing,
                                  [Component.text('Approve')],
                                ),
                                button(
                                  classes:
                                      'px-4 py-2 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-800 hover:bg-zinc-900 text-zinc-400 hover:text-white" : "border-zinc-200 hover:bg-zinc-50 text-zinc-500"} transition-colors',
                                  events: {'click': (_) => _rejectExtension(ext['id'])},
                                  disabled: _isProcessing,
                                  [Component.text('Reject')],
                                ),
                              ]),
                            ],
                          ),
                      ]),
                    ],
                  ],
                ),

                // Controls to advance status
                div(classes: 'flex flex-col gap-3', [
                  if (status == 'Awaiting Signature')
                    div(classes: 'flex flex-col gap-2', [
                      div(
                        classes:
                            'p-4 rounded-xl border border-yellow-500/20 bg-yellow-500/10 text-yellow-500 text-xs text-center font-semibold',
                        [Component.text('Awaiting rentee to sign the rental agreement to activate this trip.')],
                      ),
                      button(
                        classes:
                            'w-full py-2.5 rounded-xl text-xs font-bold text-amber-400 bg-amber-500/10 hover:bg-amber-500/20 border border-amber-500/30 transition-colors flex items-center justify-center gap-1.5 cursor-pointer',
                        events: {'click': (_) => _revokeApproval(r['currentRequestId']?.toString())},
                        disabled: _isProcessing,
                        [
                          lIcon('rotate-ccw', cls: 'w-4 h-4'),
                          Component.text('Revoke Approval & Reopen Listing'),
                        ],
                      ),
                    ])
                  else if (status == 'Booked')
                    div(classes: 'flex flex-col sm:flex-row gap-2', [
                      if (rentalType == 'deliver')
                        button(
                          classes:
                              'flex-1 py-3 rounded-2xl text-sm font-semibold text-white logo-gradient hover:opacity-90 disabled:opacity-50 transition-opacity flex items-center justify-center gap-2 cursor-pointer border-0',
                          events: {'click': (_) => _updateStatus('On the way to Rentee')},
                          disabled: _isProcessing,
                          [
                            lIcon('truck', cls: 'w-5 h-5'),
                            Component.text('Start Delivery (On the way)'),
                          ],
                        )
                      else
                        button(
                          classes:
                              'flex-1 py-3 rounded-2xl text-sm font-semibold text-white logo-gradient hover:opacity-90 disabled:opacity-50 transition-opacity flex items-center justify-center gap-2 cursor-pointer border-0',
                          events: {'click': (_) => _updateStatus('Ongoing')},
                          disabled: _isProcessing,
                          [
                            lIcon('key', cls: 'w-5 h-5'),
                            Component.text('Hand Over & Start Rental'),
                          ],
                        ),
                      button(
                        classes:
                            'px-4 py-3 rounded-2xl text-xs font-bold text-red-400 bg-red-500/10 hover:bg-red-500/20 border border-red-500/30 transition-colors flex items-center justify-center gap-1.5 cursor-pointer',
                        events: {'click': (_) => _cancelRental(r['currentRequestId']?.toString())},
                        disabled: _isProcessing,
                        [
                          lIcon('x', cls: 'w-4 h-4'),
                          Component.text('Cancel Rental'),
                        ],
                      ),
                    ])
                  else if (status == 'On the way to Rentee')
                    button(
                      classes:
                          'w-full py-3 rounded-2xl text-sm font-semibold text-white logo-gradient hover:opacity-90 disabled:opacity-50 transition-opacity flex items-center justify-center gap-2',
                      events: {'click': (_) => _updateStatus('Ongoing')},
                      disabled: _isProcessing,
                      [
                        lIcon('key', cls: 'w-5 h-5'),
                        Component.text('Hand Over & Start Rental (Turned Over)'),
                      ],
                    )
                  else if (status == 'Ongoing')
                    button(
                      classes:
                          'w-full py-3 rounded-2xl text-sm font-semibold text-white bg-purple-500 hover:bg-purple-600 disabled:opacity-50 transition-colors flex items-center justify-center gap-2',
                      events: {'click': (_) => _updateStatus('Returning')},
                      disabled: _isProcessing,
                      [
                        lIcon('refresh-cw', cls: 'w-5 h-5'),
                        Component.text('Mark as Returning'),
                      ],
                    )
                  else if (status == 'Returning')
                    button(
                      classes:
                          'w-full py-3 rounded-2xl text-sm font-semibold text-white bg-green-500 hover:bg-green-600 disabled:opacity-50 transition-colors flex items-center justify-center gap-2',
                      events: {'click': (_) => _updateStatus('Completed')},
                      disabled: _isProcessing,
                      [
                        lIcon('check-circle', cls: 'w-5 h-5'),
                        Component.text('Confirm Vehicle Returned'),
                      ],
                    ),

                  // Open Live Tracking Button
                  button(
                    classes:
                        'w-full py-3 rounded-2xl text-sm font-semibold border ${isDark ? "border-zinc-800 hover:bg-zinc-800 text-zinc-300" : "border-zinc-200 hover:bg-zinc-50 text-zinc-600"} transition-colors flex items-center justify-center gap-2',
                    events: {
                      'click': (_) {
                        component.appState.setState(() {
                          component.appState.showManageVehicleModal = false;
                          component.appState.showRentalTrackerMap = true;
                        });
                      },
                    },
                    [
                      lIcon('map', cls: 'w-5 h-5'),
                      Component.text('Open Live Tracking Map'),
                    ],
                  ),
                ]),
              ],

              // All Booking Requests and Schedules (Always visible to host)
              div(id: 'vehicle_booking_requests_feed', classes: 'pt-2', [
                h3(classes: 'text-sm font-bold text-zinc-400 uppercase tracking-wider mb-4 mt-4', [
                  Component.text('Rental Bookings & Schedules (${_requests.length})'),
                ]),
              ]),

              if (_isLoadingRequests)
                div(classes: 'py-12 flex flex-col items-center justify-center gap-3', [
                  lIcon('loader', cls: 'w-8 h-8 animate-spin text-purple-500'),
                  p(classes: 'text-sm text-zinc-500', [Component.text('Fetching applications...')]),
                ])
              else if (_requests.isEmpty)
                div(
                  classes:
                      'py-12 text-center rounded-2xl border-2 border-dashed ${isDark ? "border-zinc-800" : "border-zinc-200"}',
                  [
                    lIcon('user-plus', cls: 'w-10 h-10 mx-auto text-zinc-600 mb-3'),
                    p(classes: 'font-semibold text-zinc-400', [Component.text('No active requests yet')]),
                    p(classes: 'text-xs text-zinc-500 mt-1', [
                      Component.text('Rentees who request to book this vehicle will appear here.'),
                    ]),
                  ],
                )
              else
                div(classes: 'flex flex-col gap-4', [
                  for (final req in _requests)
                    div(
                      classes:
                          'p-5 rounded-2xl border transition-all ${isDark ? "bg-zinc-950 border-zinc-800 hover:border-zinc-700" : "bg-white border-zinc-200 hover:shadow-md"}',
                      [
                        div(classes: 'flex items-start justify-between mb-4', [
                          div(classes: 'flex items-center gap-3', [
                            div(
                              classes:
                                  'w-10 h-10 rounded-full bg-purple-500/20 flex items-center justify-center overflow-hidden',
                              [
                                if (req['renteePhotoUrl'] != null &&
                                    req['renteePhotoUrl'].toString().isNotEmpty &&
                                    req['renteePhotoUrl'].toString() != 'null')
                                  img(
                                    src: req['renteePhotoUrl'].toString(),
                                    classes:
                                        'w-full h-full object-cover cursor-zoom-in hover:opacity-90 transition-opacity',
                                    events: {
                                      'click': (_) =>
                                          component.appState.showFullScreenPhoto(req['renteePhotoUrl'].toString()),
                                    },
                                  )
                                else
                                  lIcon('user', cls: 'w-5 h-5 text-purple-400'),
                              ],
                            ),
                            div([
                              p(classes: 'font-bold flex items-center gap-2', [
                                Component.text(req['renteeName'] ?? 'Renter'),
                                if (req['hireWithDriver'] == true)
                                  span(
                                    classes:
                                        'text-[10px] font-bold px-2 py-0.5 rounded-full bg-purple-500/20 text-purple-400 border border-purple-500/30',
                                    [Component.text('With Driver')],
                                  ),
                              ]),
                              div(classes: 'flex items-center gap-2 mt-1', [
                                _statusBadge(req['status']?.toString() ?? 'Pending', isDark),
                                p(classes: 'text-xs text-zinc-500', [
                                  Component.text('License: ${_obscureLicenseNumber(req['licenseNumber']?.toString())}'),
                                ]),
                              ]),
                            ]),
                          ]),
                          div(classes: 'text-right', [
                            p(classes: 'font-black text-purple-400', [Component.text('₱${req["totalCost"]}')]),
                            p(classes: 'text-xs text-zinc-500 capitalize', [
                              Component.text('${req["multiplier"]} ${req["durationType"]}'),
                            ]),
                          ]),
                        ]),

                        // Contract Accordion / Details
                        div(
                          classes:
                              'mb-4 p-3.5 rounded-xl text-xs ${isDark ? "bg-zinc-900 text-zinc-400" : "bg-zinc-50 text-zinc-600"}',
                          [
                            if (req['startDate'] != null && req['endDate'] != null)
                              div(classes: 'flex justify-between font-bold text-purple-400 mb-1.5', [
                                span([Component.text('Rental Schedule:')]),
                                span([
                                  Component.text(
                                    '${_formatDate(req['startDate'])} - ${_formatDate(req['endDate'])}',
                                  ),
                                ]),
                              ]),
                            div(classes: 'flex flex-col gap-1.5 mb-2', [
                              span([Component.text('Contract Signature:')]),
                              if (req['signatureName'] != null &&
                                  req['signatureName'].toString().startsWith('data:image/'))
                                img(
                                  src: req['signatureName'].toString(),
                                  classes:
                                      'max-h-16 h-auto object-contain bg-white rounded-lg p-1 max-w-[200px] mt-1 cursor-zoom-in hover:opacity-90 transition-opacity',
                                  events: {
                                    'click': (_) =>
                                        component.appState.showFullScreenPhoto(req['signatureName'].toString()),
                                  },
                                )
                              else
                                span(classes: 'font-bold italic text-purple-400', [
                                  Component.text(req['signatureName'] ?? 'Unsigned'),
                                ]),
                            ]),
                            div(classes: 'flex justify-between', [
                              span([Component.text('Requested Date:')]),
                              span([
                                Component.text(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    req['createdAt'] ?? 0,
                                  ).toString().substring(0, 16),
                                ),
                              ]),
                            ]),
                          ],
                        ),

                        // Pre-actions (View Profile + Chat Toggle) & Actions
                        if (req['status']?.toString().toLowerCase() == 'pending') ...[
                          div(
                            classes:
                                'flex items-center justify-between gap-3 mb-4 pt-2 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"}',
                            [
                              button(
                                classes:
                                    'text-xs font-bold text-indigo-400 hover:text-indigo-300 flex items-center gap-1 bg-transparent border-0 cursor-pointer',
                                events: {'click': (_) => component.appState.viewEmployerProfile(req['renteeId'] ?? '')},
                                [
                                  lIcon('user', cls: 'w-3.5 h-3.5'),
                                  Component.text('View Renter Profile'),
                                ],
                              ),
                              label(
                                classes:
                                    'flex items-center gap-2 cursor-pointer text-xs ${isDark ? "text-zinc-300" : "text-zinc-650"}',
                                [
                                  input(
                                    type: InputType.checkbox,
                                    checked: _allowChat,
                                    onChange: (val) {
                                      setState(() => _allowChat = val == true);
                                    },
                                  ),
                                  Component.text('Allow Chatting with Renter'),
                                ],
                              ),
                            ],
                          ),
                          div(classes: 'flex items-center gap-2', [
                            button(
                              classes:
                                  'flex-1 py-2 rounded-xl text-sm font-semibold text-white logo-gradient hover:opacity-90 disabled:opacity-50 transition-opacity',
                              events: {'click': (_) => _approveRequest(req['id'])},
                              disabled: _isProcessing,
                              [Component.text('Approve Request')],
                            ),
                            button(
                              classes:
                                  'px-4 py-2 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-800 hover:bg-zinc-900 text-zinc-400 hover:text-white" : "border-zinc-200 hover:bg-zinc-50 text-zinc-500"} transition-colors',
                              events: {'click': (_) => _rejectRequest(req['id'])},
                              disabled: _isProcessing,
                              [Component.text('Reject')],
                            ),
                          ]),
                        ] else ...[
                          div(
                            classes:
                                'flex items-center justify-between gap-3 pt-2 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"}',
                            [
                              button(
                                classes:
                                    'text-xs font-bold text-indigo-400 hover:text-indigo-300 flex items-center gap-1 bg-transparent border-0 cursor-pointer',
                                events: {'click': (_) => component.appState.viewEmployerProfile(req['renteeId'] ?? '')},
                                [
                                  lIcon('user', cls: 'w-3.5 h-3.5'),
                                  Component.text('View Renter Profile'),
                                ],
                              ),
                              if (req['allowChat'] == true || (r['allowChat'] == true && r['renteeId'] == req['renteeId']))
                                () {
                                  final chatId = 'rental_${r['id']}_${req['renteeId']}';
                                  return button(
                                    classes:
                                        'px-3 py-1.5 rounded-lg text-xs font-bold text-blue-400 hover:bg-blue-500/15 border border-blue-500/30 cursor-pointer bg-transparent',
                                    events: {
                                      'click': (_) {
                                        component.appState.setState(() {
                                          component.appState.showManageVehicleModal = false;
                                        });
                                        component.appState.openChat(chatId);
                                      },
                                    },
                                    [
                                      lIcon('message-square', cls: 'w-3.5 h-3.5 mr-1 inline'),
                                      Component.text('Chat Renter'),
                                    ],
                                  );
                                }(),
                            ],
                          ),
                          () {
                            final reqStatus = (req['status'] ?? '').toString();
                            final isDeliver = (req['rentalType'] ?? r['rentalType']) == 'deliver';
                            if (reqStatus == 'Approved' || reqStatus == 'Awaiting Signature') {
                              return div(classes: 'mt-3 pt-3 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center gap-2', [
                                button(
                                  classes:
                                      'flex-1 py-2 rounded-xl text-xs font-bold text-amber-400 bg-amber-500/10 hover:bg-amber-500/20 border border-amber-500/30 transition-colors flex items-center justify-center gap-1.5 cursor-pointer',
                                  events: {'click': (_) => _revokeApproval(req['id'])},
                                  disabled: _isProcessing,
                                  [
                                    lIcon('rotate-ccw', cls: 'w-4 h-4'),
                                    Component.text('Revoke Approval & Reopen Listing'),
                                  ],
                                ),
                              ]);
                            } else if (reqStatus == 'Booked') {
                              return div(classes: 'mt-3 pt-3 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center gap-2', [
                                button(
                                  classes:
                                      'flex-1 py-2 rounded-xl text-xs font-bold text-white logo-gradient hover:opacity-90 disabled:opacity-50 transition-opacity flex items-center justify-center gap-1.5 cursor-pointer border-0',
                                  events: {'click': (_) => _updateBookingStatus(req['id'], isDeliver ? 'On the way to Rentee' : 'Ongoing')},
                                  disabled: _isProcessing,
                                  [
                                    lIcon(isDeliver ? 'truck' : 'key', cls: 'w-4 h-4'),
                                    Component.text(isDeliver ? 'Start Delivery' : 'Hand Over & Start Rental'),
                                  ],
                                ),
                                button(
                                  classes:
                                      'px-3 py-2 rounded-xl text-xs font-semibold text-red-400 hover:bg-red-500/10 border border-red-500/30 transition-colors flex items-center justify-center gap-1 cursor-pointer bg-transparent',
                                  events: {'click': (_) => _cancelRental(req['id'])},
                                  disabled: _isProcessing,
                                  [
                                    lIcon('x', cls: 'w-3.5 h-3.5'),
                                    Component.text('Cancel Rental'),
                                  ],
                                ),
                              ]);
                            } else if (reqStatus == 'On the way to Rentee') {
                              return div(classes: 'mt-3 pt-3 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center gap-2', [
                                button(
                                  classes:
                                      'flex-1 py-2 rounded-xl text-xs font-bold text-white logo-gradient hover:opacity-90 disabled:opacity-50 transition-opacity flex items-center justify-center gap-1.5 cursor-pointer border-0',
                                  events: {'click': (_) => _updateBookingStatus(req['id'], 'Ongoing')},
                                  disabled: _isProcessing,
                                  [
                                    lIcon('key', cls: 'w-4 h-4'),
                                    Component.text('Hand Over & Start Rental'),
                                  ],
                                ),
                              ]);
                            } else if (reqStatus == 'Ongoing') {
                              return div(classes: 'mt-3 pt-3 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center gap-2', [
                                button(
                                  classes:
                                      'flex-1 py-2 rounded-xl text-xs font-bold text-white bg-purple-500 hover:bg-purple-600 disabled:opacity-50 transition-colors flex items-center justify-center gap-1.5 cursor-pointer border-0',
                                  events: {'click': (_) => _updateBookingStatus(req['id'], 'Returning')},
                                  disabled: _isProcessing,
                                  [
                                    lIcon('refresh-cw', cls: 'w-4 h-4'),
                                    Component.text('Mark as Returning'),
                                  ],
                                ),
                              ]);
                            } else if (reqStatus == 'Returning') {
                              return div(classes: 'mt-3 pt-3 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center gap-2', [
                                button(
                                  classes:
                                      'flex-1 py-2 rounded-xl text-xs font-bold text-white bg-green-500 hover:bg-green-600 disabled:opacity-50 transition-colors flex items-center justify-center gap-1.5 cursor-pointer border-0',
                                  events: {'click': (_) => _updateBookingStatus(req['id'], 'Completed')},
                                  disabled: _isProcessing,
                                  [
                                    lIcon('check-circle', cls: 'w-4 h-4'),
                                    Component.text('Confirm Vehicle Returned & Complete'),
                                  ],
                                ),
                              ]);
                            }
                            return div([]);
                          }(),
                        ],
                      ],
                    ),
                ]),
            ]),
          ],
        ),
      ],
    );
  }

  String _formatDate(dynamic epoch) {
    if (epoch == null) return 'N/A';
    final ms = epoch is int ? epoch : int.tryParse(epoch.toString()) ?? 0;
    if (ms == 0) return 'N/A';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Component _statusBadge(String status, bool isDark) {
    final s = status.toLowerCase();
    String bg = 'bg-amber-500/10 text-amber-400 border-amber-500/20';
    String label = status;

    if (s == 'pending') {
      bg = 'bg-yellow-500/10 text-yellow-400 border-yellow-500/30';
      label = 'Pending Review';
    } else if (s == 'approved') {
      bg = 'bg-blue-500/10 text-blue-400 border-blue-500/30';
      label = 'Approved (Awaiting Signature)';
    } else if (s == 'booked' || s == 'ongoing' || s == 'active' || s == 'on the way to rentee' || s == 'returning') {
      bg = 'bg-green-500/10 text-green-400 border-green-500/30';
      label = status;
    } else if (s == 'completed') {
      bg = 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30';
      label = 'Completed';
    } else if (s == 'rejected' || s == 'cancelled') {
      bg = 'bg-red-500/10 text-red-400 border-red-500/30';
      label = status;
    }

    return span(
      classes: 'text-[10px] font-bold px-2 py-0.5 rounded-full border $bg capitalize inline-block',
      [Component.text(label)],
    );
  }

  String _obscureLicenseNumber(String? license) {
    if (license == null || license.isEmpty) return 'N/A';
    final clean = license.replaceAll('-', '');
    if (clean.length < 5) return '***';
    final visiblePart = clean.substring(clean.length - 4);
    final obscuredPrefix = '*' * (clean.length - 4);
    if (obscuredPrefix.length > 3) {
      return '${obscuredPrefix.substring(0, 3)}-${obscuredPrefix.substring(3)}-$visiblePart';
    }
    return '$obscuredPrefix-$visiblePart';
  }
}
