import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../services/web_interop.dart';

class ManagePropertyModalComponent extends StatefulComponent {
  final TranyxAppState appState;
  const ManagePropertyModalComponent({required this.appState, super.key});

  @override
  State<ManagePropertyModalComponent> createState() => _ManagePropertyModalState();
}

class _ManagePropertyModalState extends State<ManagePropertyModalComponent> {
  bool _isLoadingRequests = false;
  List<Map<String, dynamic>> _requests = [];
  String? _error;
  bool _isProcessing = false;
  bool _showConfirmDelete = false;
  bool _showPendingWarning = false;

  bool _allowChat = false;

  void _toggleAcceptingBookings(bool currentlyAccepting) async {
    final prop = component.appState.selectedPropertyData;
    if (prop == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final newAccepting = !currentlyAccepting;
      await component.appState.firestore.setPropertyAcceptingBookings(prop['id'], newAccepting);
      final newStatus = newAccepting ? 'Available' : 'Not Accepting Bookings';
      component.appState.setState(() {
        final updated = Map<String, dynamic>.from(prop);
        updated['acceptingBookings'] = newAccepting;
        updated['status'] = newStatus;
        component.appState.selectedPropertyData = updated;
      });
      component.appState.alertDialog(
        newAccepting ? 'Bookings Resumed' : 'Bookings Paused',
        newAccepting
            ? 'Your property is now accepting booking requests in the marketplace.'
            : 'Your property will no longer accept new booking requests. Existing bookings remain active.',
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
  }

  void _loadRequests() async {
    final prop = component.appState.selectedPropertyData;
    if (prop == null) return;

    setState(() {
      _isLoadingRequests = true;
      _error = null;
    });

    try {
      final allList = await component.appState.firestore.getAllRequestsForProperty(prop['id']);
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
      });
    } catch (e) {
      setState(() => _error = 'Failed to load property requests: $e');
    } finally {
      setState(() => _isLoadingRequests = false);
    }
  }

  void _approveRequest(String requestId) async {
    final prop = component.appState.selectedPropertyData;
    if (prop == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.approvePropertyBookingRequest(requestId, prop['id'], _allowChat);

      // Close modal and clear selected state
      component.appState.setState(() {
        component.appState.showManagePropertyModal = false;
        component.appState.selectedPropertyData = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _rejectRequest(String requestId) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.rejectPropertyBookingRequest(requestId);
      _loadRequests(); // Refresh request list
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _deleteListing(String propertyId) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.deletePropertyRental(propertyId);
      await component.appState.loadUserProfile();
      component.appState.walletBalance = component.appState.userProfile?.tyxBalance ?? component.appState.walletBalance;

      component.appState.setState(() {
        component.appState.showManagePropertyModal = false;
        component.appState.selectedPropertyData = null;
      });
      component.appState.alertDialog('Listing Removed', 'The property listing has been removed from Tranyx.');
    } catch (e) {
      setState(() => _error = 'Failed to delete listing: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _completeLease() async {
    final prop = component.appState.selectedPropertyData;
    if (prop == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.completePropertyRental(prop['id']);
      await component.appState.loadUserProfile();
      component.appState.walletBalance = component.appState.userProfile?.tyxBalance ?? component.appState.walletBalance;

      component.appState.setState(() {
        component.appState.showManagePropertyModal = false;
        component.appState.selectedPropertyData = null;
      });
      component.appState.alertDialog('Lease Completed', 'The lease has been completed and earnings have been deposited into your wallet.');
    } catch (e) {
      setState(() => _error = 'Failed to complete lease: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _completeLeaseForRequest(String requestId) async {
    final prop = component.appState.selectedPropertyData;
    if (prop == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.completePropertyRental(prop['id'], requestId: requestId);
      await component.appState.loadUserProfile();
      component.appState.walletBalance = component.appState.userProfile?.tyxBalance ?? component.appState.walletBalance;
      _loadRequests();
      component.appState.showAppToast('Lease Completed', 'Lease earnings have been deposited into your wallet.');
    } catch (e) {
      setState(() => _error = 'Failed to complete lease: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _revokeApproval({String? requestId}) async {
    final prop = component.appState.selectedPropertyData;
    if (prop == null) return;

    final confirmed = confirmDialog(
      'Are you sure you want to revoke approval for this lease request? The tenant will be 100% refunded and the listing will reopen for new bookings.',
    );
    if (!confirmed) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.revokePropertyApproval(prop['id'], requestId: requestId);
      await component.appState.loadUserProfile();
      component.appState.showAppToast('Approval Revoked', 'Lease request cancelled and tenant refunded.');
      _loadRequests();
      component.appState.setState(() {
        component.appState.showManagePropertyModal = false;
        component.appState.selectedPropertyData = null;
      });
    } catch (e) {
      setState(() => _error = 'Failed to revoke approval: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _activateLease({String? requestId}) async {
    final prop = component.appState.selectedPropertyData;
    if (prop == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.updatePropertyStatus(prop['id'], 'Active', requestId: requestId);
      component.appState.showAppToast('Lease Activated', 'Keys handed over. The tenant residency is now Active.');
      _loadRequests();
      final updated = Map<String, dynamic>.from(prop);
      updated['status'] = 'Active';
      component.appState.setState(() {
        component.appState.selectedPropertyData = updated;
      });
    } catch (e) {
      setState(() => _error = 'Failed to activate lease: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _cancelLease({String? requestId}) async {
    final prop = component.appState.selectedPropertyData;
    if (prop == null) return;

    final confirmed = confirmDialog(
      'Are you sure you want to cancel this lease? Tenant will be refunded minus standard cancellation processing fee.',
    );
    if (!confirmed) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.cancelPropertyRental(prop['id'], requestId: requestId);
      await component.appState.loadUserProfile();
      component.appState.showAppToast('Lease Cancelled', 'Lease has been cancelled and refunded.');
      _loadRequests();
      component.appState.setState(() {
        component.appState.showManagePropertyModal = false;
        component.appState.selectedPropertyData = null;
      });
    } catch (e) {
      setState(() => _error = 'Failed to cancel lease: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Component build(BuildContext context) {
    if (!component.appState.showManagePropertyModal || component.appState.selectedPropertyData == null) {
      return div([]);
    }

    final prop = component.appState.selectedPropertyData!;
    final isDark = component.appState.isDark;
    final status = prop['status'] ?? 'Available';
    final isNotAccepting = status == 'Not Accepting Bookings' || prop['acceptingBookings'] == false;
    final hasPending = _requests.any((req) => req['status']?.toString().toLowerCase() == 'pending');
    final hasConfirmed = _requests.any((req) => BookingDateRange.fromMap(req).isConfirmedBooking);
    final title = prop['title'] ?? 'Unknown Property';
    final monthlyRent = ((prop['priceMonthly'] ?? 0) as num).toDouble();

    return div(
      classes:
          'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm animate-fade-in overflow-y-auto',
      [
        div(
          classes:
              'w-full max-w-2xl rounded-2xl border shadow-2xl overflow-hidden my-8 max-h-[90vh] flex flex-col ${isDark ? "bg-zinc-900 border-zinc-800 text-white" : "bg-white border-zinc-200 text-zinc-900"}',
          [
            // Header
            div(
              classes:
                  'p-6 border-b flex items-center justify-between shrink-0 ${isDark ? "border-zinc-800" : "border-zinc-200"}',
              [
                div([
                  h2(classes: 'text-xl font-black tracking-tight', [Component.text('Manage Property')]),
                  p(classes: 'text-xs text-zinc-400 mt-1', [Component.text(title)]),
                ]),
                button(
                  classes:
                      'p-2 rounded-xl text-zinc-400 hover:text-white hover:bg-zinc-800/60 transition-colors border-0 bg-transparent cursor-pointer',
                  events: {
                    'click': (_) {
                      component.appState.setState(() {
                        component.appState.showManagePropertyModal = false;
                        component.appState.selectedPropertyData = null;
                      });
                    },
                  },
                  [lIcon('x', cls: 'w-5 h-5')],
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
                    span([Component.text('This property is currently paused and not accepting new bookings in the marketplace.')]),
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
                    p(classes: 'text-xs text-zinc-500 font-bold uppercase tracking-wider mb-1', [
                      Component.text('Listing Status'),
                    ]),
                    h3(classes: 'text-lg font-bold capitalize ${isNotAccepting ? "text-amber-400" : "text-purple-400"}', [
                      Component.text(isNotAccepting ? 'Not Accepting Bookings' : status),
                    ]),
                  ]),
                  div(classes: 'text-right', [
                    p(classes: 'text-xs text-zinc-500 font-bold uppercase tracking-wider mb-1', [
                      Component.text('Monthly Rent'),
                    ]),
                    h3(classes: 'text-lg font-extrabold', [Component.text('₱${monthlyRent.toStringAsFixed(0)}/mo')]),
                  ]),
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
                          web.document.getElementById('property_booking_requests_feed')?.scrollIntoView();
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
                          : 'Are you sure you want to delete this listing? This will permanently remove the property from active listings.',
                    ),
                  ]),
                  div(classes: 'flex items-center gap-2 mt-1', [
                    button(
                      classes:
                          'px-3.5 py-1.5 rounded-lg bg-red-500 text-white font-bold text-xs hover:bg-red-600 transition-colors cursor-pointer',
                      events: {'click': (_) => _deleteListing(prop['id'])},
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
                    if (_requests.isEmpty && (status == 'Available' || isNotAccepting))
                      button(
                        classes:
                            'px-4 py-2 text-xs font-bold text-indigo-400 border border-indigo-500/30 hover:bg-indigo-500/10 rounded-xl transition-all flex items-center gap-1.5 cursor-pointer bg-transparent',
                        events: {
                          'click': (_) {
                            component.appState.setState(() {
                              component.appState.showManagePropertyModal = false;
                              component.appState.showEditPropertyModal = true;
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

              if (status != 'Available' && status != 'Not Accepting Bookings' && prop['renteeId'] != null && (prop['renteeId'] as String).isNotEmpty) ...[
                // Booked / Awaiting Signature / Active details
                h3(classes: 'text-sm font-bold text-zinc-400 uppercase tracking-wider mb-4', [
                  Component.text('Tenant & Lease Details'),
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
                            if (prop['renteePhotoUrl'] != null &&
                                prop['renteePhotoUrl'].toString().isNotEmpty &&
                                prop['renteePhotoUrl'].toString() != 'null')
                              img(src: prop['renteePhotoUrl'].toString(), classes: 'w-full h-full object-cover')
                            else
                              lIcon('user', cls: 'w-6 h-6 text-purple-400'),
                          ],
                        ),
                        div([
                          p(classes: 'font-extrabold text-base', [
                            Component.text(prop['renteeName'] ?? 'Tenant'),
                          ]),
                          p(classes: 'text-xs text-zinc-500', [Component.text('Lease Status: $status')]),
                        ]),
                      ]),
                      if (prop['allowChat'] == true)
                        () {
                          final chatId = 'property_${prop['id']}_${prop['renteeId']}';
                          return button(
                            classes:
                                'px-3 py-1.5 rounded-lg text-xs font-bold text-blue-400 hover:bg-blue-500/15 border border-blue-500/30 cursor-pointer bg-transparent relative',
                            events: {
                              'click': (_) {
                                component.appState.setState(() {
                                  component.appState.showManagePropertyModal = false;
                                });
                                component.appState.openChat(chatId);
                              },
                            },
                            [
                              lIcon('message-square', cls: 'w-3.5 h-3.5 mr-1 inline'),
                              Component.text('Chat Tenant'),
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

                    // Duration / Timeline
                    div(
                      classes: 'p-4 rounded-xl text-sm ${isDark ? "bg-zinc-900/60" : "bg-zinc-50"} flex flex-col gap-2',
                      [
                        div(classes: 'flex justify-between', [
                          span(classes: 'text-zinc-500', [Component.text('Start Date')]),
                          span(classes: 'font-semibold', [
                            Component.text(
                              DateTime.fromMillisecondsSinceEpoch(
                                prop['startDate'] as int? ?? 0,
                              ).toString().substring(0, 10),
                            ),
                          ]),
                        ]),
                        div(classes: 'flex justify-between', [
                          span(classes: 'text-zinc-500', [Component.text('End Date')]),
                          span(classes: 'font-semibold', [
                            Component.text(
                              DateTime.fromMillisecondsSinceEpoch(
                                prop['endDate'] as int? ?? 0,
                              ).toString().substring(0, 10),
                            ),
                          ]),
                        ]),
                        div(classes: 'flex justify-between', [
                          span(classes: 'text-zinc-500', [Component.text('Total Escrow Cost')]),
                          span(classes: 'font-extrabold text-purple-400', [Component.text('₱${prop["totalCost"]}')]),
                        ]),
                      ],
                    ),

                    if (prop['renteeSignatureName'] != null && prop['renteeSignatureName'].toString().isNotEmpty)
                      div(classes: 'mt-4 pt-4 border-t border-zinc-200 dark:border-zinc-800', [
                        p(classes: 'text-xs text-zinc-500 mb-2', [Component.text('Signed Lease Agreement:')]),
                        img(
                          src: prop['renteeSignatureName'].toString(),
                          classes:
                              'max-h-20 h-auto object-contain bg-white rounded-lg p-2 max-w-[240px] cursor-zoom-in hover:opacity-95 transition-opacity',
                          events: {
                            'click': (_) =>
                                component.appState.showFullScreenPhoto(prop['renteeSignatureName'].toString()),
                          },
                        ),
                      ]),
                  ],
                ),

                if (status == 'Awaiting Signature')
                  div(classes: 'flex flex-col gap-2 mb-6', [
                    div(
                      classes:
                          'p-4 rounded-xl border border-yellow-500/20 bg-yellow-500/10 text-yellow-500 text-xs text-center font-semibold',
                      [Component.text('Awaiting tenant to sign the contract and finalize this lease.')],
                    ),
                    button(
                      classes:
                          'w-full py-2.5 rounded-xl text-xs font-bold text-amber-400 bg-amber-500/10 hover:bg-amber-500/20 border border-amber-500/30 transition-colors flex items-center justify-center gap-1.5 cursor-pointer',
                      events: {'click': (_) => _revokeApproval()},
                      disabled: _isProcessing,
                      [
                        lIcon('rotate-ccw', cls: 'w-4 h-4'),
                        Component.text('Revoke Approval & Reopen Listing'),
                      ],
                    ),
                  ]),

                if (status == 'Booked')
                  div(classes: 'flex flex-col sm:flex-row gap-2 mb-6', [
                    button(
                      classes:
                          'flex-1 py-3.5 rounded-2xl text-sm font-bold text-white logo-gradient hover:opacity-90 disabled:opacity-50 transition-all flex items-center justify-center gap-2 border-0 cursor-pointer shadow-lg shadow-purple-600/20',
                      events: {'click': (_) => _activateLease()},
                      disabled: _isProcessing,
                      [
                        lIcon('key', cls: 'w-5 h-5'),
                        Component.text('Hand Over Keys & Activate Lease'),
                      ],
                    ),
                    button(
                      classes:
                          'px-4 py-3.5 rounded-2xl text-xs font-bold text-red-400 bg-red-500/10 hover:bg-red-500/20 border border-red-500/30 transition-colors flex items-center justify-center gap-1.5 cursor-pointer',
                      events: {'click': (_) => _cancelLease()},
                      disabled: _isProcessing,
                      [
                        lIcon('x', cls: 'w-4 h-4'),
                        Component.text('Cancel Lease'),
                      ],
                    ),
                  ]),

                if (status == 'Active')
                  div(classes: 'flex flex-col sm:flex-row gap-2 mb-6', [
                    button(
                      classes:
                          'flex-1 py-3.5 rounded-2xl text-sm font-bold text-white bg-green-500 hover:bg-green-600 disabled:opacity-50 transition-colors flex items-center justify-center gap-2 border-0 cursor-pointer',
                      events: {'click': (_) => _completeLease()},
                      disabled: _isProcessing,
                      [
                        lIcon('check-circle', cls: 'w-5 h-5'),
                        Component.text('Complete Lease & Release Payout'),
                      ],
                    ),
                    button(
                      classes:
                          'px-4 py-3.5 rounded-2xl text-xs font-bold text-red-400 bg-red-500/10 hover:bg-red-500/20 border border-red-500/30 transition-colors flex items-center justify-center gap-1.5 cursor-pointer',
                      events: {'click': (_) => _cancelLease()},
                      disabled: _isProcessing,
                      [
                        lIcon('x', cls: 'w-4 h-4'),
                        Component.text('Cancel Lease'),
                      ],
                    ),
                  ]),
              ],

              // Lease Bookings & Applications (Always visible to host)
              h3(
                id: 'property_booking_requests_feed',
                classes: 'text-sm font-bold text-zinc-400 uppercase tracking-wider mb-4 mt-6',
                [
                  Component.text('Lease Bookings & Applications (${_requests.length})'),
                ],
              ),

              if (_isLoadingRequests)
                div(classes: 'py-12 flex flex-col items-center justify-center gap-3', [
                  lIcon('loader', cls: 'w-8 h-8 animate-spin text-purple-500'),
                  p(classes: 'text-sm text-zinc-500', [Component.text('Fetching booking requests...')]),
                ])
              else if (_requests.isEmpty)
                div(
                  classes:
                      'py-12 text-center rounded-2xl border-2 border-dashed ${isDark ? "border-zinc-800" : "border-zinc-200"}',
                  [
                    lIcon('home', cls: 'w-10 h-10 mx-auto text-zinc-650 mb-3'),
                    p(classes: 'font-semibold text-zinc-400', [Component.text('No active requests yet')]),
                    p(classes: 'text-xs text-zinc-500 mt-1', [
                      Component.text('Rentees who request to rent your property will show up here.'),
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
                                  img(src: req['renteePhotoUrl'].toString(), classes: 'w-full h-full object-cover')
                                else
                                  lIcon('user', cls: 'w-5 h-5 text-purple-400'),
                              ],
                            ),
                            div([
                              p(classes: 'font-bold flex items-center gap-2', [
                                Component.text(req['renteeName'] ?? 'Renter'),
                              ]),
                              div(classes: 'flex items-center gap-2 mt-1', [
                                _statusBadge(req['status']?.toString() ?? 'Pending', isDark),
                                p(classes: 'text-xs text-zinc-500', [Component.text('ID Verified')]),
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

                        // Contract info
                        div(
                          classes:
                              'mb-4 p-3.5 rounded-xl text-xs ${isDark ? "bg-zinc-900 text-zinc-400" : "bg-zinc-50 text-zinc-650"}',
                          [
                            if (req['startDate'] != null && req['endDate'] != null)
                              div(classes: 'flex justify-between font-bold text-purple-400 mb-1.5', [
                                span([Component.text('Lease Term:')]),
                                span([
                                  Component.text(
                                    '${_formatDate(req['startDate'])} - ${_formatDate(req['endDate'])}',
                                  ),
                                ]),
                              ]),
                            div(classes: 'flex justify-between mb-1.5', [
                              span([Component.text('Request Date:')]),
                              span([
                                Component.text(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    req['createdAt'] ?? 0,
                                  ).toString().substring(0, 16),
                                ),
                              ]),
                            ]),
                            div(classes: 'flex justify-between', [
                              span([Component.text('Escrow Escaped Amount:')]),
                              span(classes: 'font-bold text-purple-400', [Component.text('₱${req["totalCost"]}')]),
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
                                  'flex-1 py-2 rounded-xl text-sm font-semibold text-white logo-gradient hover:opacity-90 disabled:opacity-50 transition-opacity border-0 cursor-pointer',
                              events: {'click': (_) => _approveRequest(req['id'])},
                              disabled: _isProcessing,
                              [Component.text('Approve & Await Signature')],
                            ),
                            button(
                              classes:
                                  'px-4 py-2 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-800 hover:bg-zinc-900 text-zinc-400 hover:text-white" : "border-zinc-200 hover:bg-zinc-50 text-zinc-500"} transition-colors bg-transparent cursor-pointer',
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
                              if (req['allowChat'] == true || (prop['allowChat'] == true && prop['renteeId'] == req['renteeId']))
                                () {
                                  final chatId = 'property_${prop['id']}_${req['renteeId']}';
                                  return button(
                                    classes:
                                        'px-3 py-1.5 rounded-lg text-xs font-bold text-blue-400 hover:bg-blue-500/15 border border-blue-500/30 cursor-pointer bg-transparent',
                                    events: {
                                      'click': (_) {
                                        component.appState.setState(() {
                                          component.appState.showManagePropertyModal = false;
                                        });
                                        component.appState.openChat(chatId);
                                      },
                                    },
                                    [
                                      lIcon('message-square', cls: 'w-3.5 h-3.5 mr-1 inline'),
                                      Component.text('Chat Tenant'),
                                    ],
                                  );
                                }(),
                            ],
                          ),
                          () {
                            final reqStatus = (req['status'] ?? '').toString().toLowerCase();
                            if (reqStatus == 'approved' || reqStatus == 'awaiting signature') {
                              return div(classes: 'mt-3 pt-3 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center gap-2', [
                                button(
                                  classes:
                                      'flex-1 py-2 rounded-xl text-xs font-bold text-amber-400 bg-amber-500/10 hover:bg-amber-500/20 border border-amber-500/30 transition-colors flex items-center justify-center gap-1.5 cursor-pointer',
                                  events: {'click': (_) => _revokeApproval(requestId: req['id'])},
                                  disabled: _isProcessing,
                                  [
                                    lIcon('rotate-ccw', cls: 'w-4 h-4'),
                                    Component.text('Revoke Approval & Reopen Listing'),
                                  ],
                                ),
                              ]);
                            } else if (reqStatus == 'booked') {
                              return div(classes: 'mt-3 pt-3 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center gap-2', [
                                button(
                                  classes:
                                      'flex-1 py-2 rounded-xl text-xs font-bold text-white logo-gradient hover:opacity-90 disabled:opacity-50 transition-opacity flex items-center justify-center gap-1.5 cursor-pointer border-0',
                                  events: {'click': (_) => _activateLease(requestId: req['id'])},
                                  disabled: _isProcessing,
                                  [
                                    lIcon('key', cls: 'w-4 h-4'),
                                    Component.text('Hand Over Keys & Activate'),
                                  ],
                                ),
                                button(
                                  classes:
                                      'px-3 py-2 rounded-xl text-xs font-semibold text-red-400 hover:bg-red-500/10 border border-red-500/30 transition-colors flex items-center justify-center gap-1 cursor-pointer bg-transparent',
                                  events: {'click': (_) => _cancelLease(requestId: req['id'])},
                                  disabled: _isProcessing,
                                  [
                                    lIcon('x', cls: 'w-3.5 h-3.5'),
                                    Component.text('Cancel Lease'),
                                  ],
                                ),
                              ]);
                            } else if (reqStatus == 'active' || reqStatus == 'ongoing' || reqStatus == 'returning') {
                              return div(classes: 'mt-3 pt-3 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center gap-2', [
                                button(
                                  classes:
                                      'flex-1 py-2 rounded-xl text-xs font-bold text-white bg-green-500 hover:bg-green-600 disabled:opacity-50 transition-colors flex items-center justify-center gap-1.5 cursor-pointer border-0',
                                  events: {'click': (_) => _completeLeaseForRequest(req['id'])},
                                  disabled: _isProcessing,
                                  [
                                    lIcon('check-circle', cls: 'w-4 h-4'),
                                    Component.text('Complete Lease & Release Earnings'),
                                  ],
                                ),
                                button(
                                  classes:
                                      'px-3 py-2 rounded-xl text-xs font-semibold text-red-400 hover:bg-red-500/10 border border-red-500/30 transition-colors flex items-center justify-center gap-1 cursor-pointer bg-transparent',
                                  events: {'click': (_) => _cancelLease(requestId: req['id'])},
                                  disabled: _isProcessing,
                                  [
                                    lIcon('x', cls: 'w-3.5 h-3.5'),
                                    Component.text('Cancel Lease'),
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
    } else if (s == 'approved' || s == 'awaiting signature') {
      bg = 'bg-blue-500/10 text-blue-400 border-blue-500/30';
      label = 'Approved (Awaiting Signature)';
    } else if (s == 'booked' || s == 'ongoing' || s == 'active') {
      bg = 'bg-green-500/10 text-green-400 border-green-500/30';
      label = 'Active / Leased';
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
}
