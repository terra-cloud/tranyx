import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';

class ManageVehicleModalComponent extends StatefulComponent {
  final TranyxAppState appState;
  const ManageVehicleModalComponent({required this.appState, super.key});

  @override
  State<ManageVehicleModalComponent> createState() => _ManageVehicleModalState();
}

class _ManageVehicleModalState extends State<ManageVehicleModalComponent> {
  bool _isLoadingRequests = false;
  List<Map<String, dynamic>> _requests = [];
  String? _error;
  bool _isProcessing = false;
  bool _showConfirmDelete = false;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  void _loadRequests() async {
    final r = component.appState.selectedRentalData;
    if (r == null) return;

    setState(() {
      _isLoadingRequests = true;
      _error = null;
    });

    try {
      final list = await component.appState.firestore.getPendingRequestsForVehicle(r['id']);
      setState(() {
        _requests = list;
      });
    } catch (e) {
      setState(() => _error = 'Failed to load requests: $e');
    } finally {
      setState(() => _isLoadingRequests = false);
    }
  }

  void _approveRequest(String requestId) async {
    final r = component.appState.selectedRentalData;
    if (r == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.approveBookingRequest(requestId, r['id']);
      
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

  void _deleteListing(String rentalId) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await component.appState.firestore.deleteRental(rentalId);
      
      component.appState.setState(() {
        component.appState.showManageVehicleModal = false;
        component.appState.selectedRentalData = null;
      });
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

  @override
  Component build(BuildContext context) {
    final isDark = component.appState.isDark;
    final r = component.appState.selectedRentalData;
    if (r == null) return div([]);

    final status = r['status'] as String? ?? 'Available';
    final model = r['model'] ?? 'Unknown Model';
    final brand = r['brand'] ?? 'Unknown Brand';
    final year = r['year'] ?? '';
    final plateNumber = r['plateNumber'] ?? 'N/A';
    final dailyRate = r['dailyRate'] ?? r['priceDaily'] ?? 0.0;

    final modalCls = isDark
        ? 'bg-zinc-900 border border-zinc-800 text-white'
        : 'bg-white text-zinc-900 shadow-xl';

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in',
      [
        div(
          classes: 'w-full max-w-2xl rounded-3xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh] $modalCls',
          [
            // Header
            div(classes: 'p-6 border-b ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center justify-between', [
              div([
                h2(classes: 'text-xl font-black tracking-tight', [Component.text('Manage Vehicle')]),
                p(classes: 'text-sm text-zinc-500', [Component.text('$brand $model ($year) • Plate: $plateNumber')]),
              ]),
              button(
                classes: 'p-2 rounded-full hover:bg-zinc-800/20 transition-colors',
                events: {'click': (_) => component.appState.setState(() {
                  component.appState.showManageVehicleModal = false;
                  component.appState.selectedRentalData = null;
                })},
                [lIcon('x', cls: 'w-6 h-6')],
              ),
            ]),

            // Body
            div(classes: 'flex-1 overflow-y-auto p-6', [
              if (_error != null)
                div(classes: 'mb-4 p-4 rounded-2xl bg-red-500/10 border border-red-500/20 text-red-400 text-sm flex items-center gap-2', [
                  lIcon('alert-circle', cls: 'w-5 h-5 flex-shrink-0'),
                  span([Component.text(_error!)]),
                ]),

              // Status Summary Card
              div(
                classes: 'p-5 rounded-2xl mb-6 flex items-center justify-between ${isDark ? "bg-zinc-800/40 border border-zinc-800" : "bg-zinc-50 border border-zinc-200"}',
                [
                  div([
                    p(classes: 'text-xs text-zinc-500 font-bold uppercase tracking-wider mb-1', [Component.text('Current Status')]),
                    h3(classes: 'text-lg font-bold capitalize text-purple-400', [Component.text(status)]),
                  ]),
                  div(classes: 'text-right', [
                    p(classes: 'text-xs text-zinc-500 font-bold uppercase tracking-wider mb-1', [Component.text('Daily Rate')]),
                    h3(classes: 'text-lg font-extrabold', [Component.text('₱$dailyRate/day')]),
                  ]),
                ],
              ),

              if (status == 'Available') ...[
                if (_showConfirmDelete)
                  div(classes: 'mb-6 p-4 rounded-2xl bg-red-500/10 border border-red-500/20 text-sm flex flex-col gap-3', [
                    div(classes: 'flex items-center gap-2 text-red-400 font-bold', [
                      lIcon('alert-triangle', cls: 'w-5 h-5 flex-shrink-0'),
                      span([Component.text('Are you sure you want to delete this listing?')]),
                    ]),
                    p(classes: 'text-zinc-400 text-xs', [
                      Component.text('This will permanently remove the vehicle from Tranyx. Your listing fee will be refunded to your balance.')
                    ]),
                    div(classes: 'flex items-center gap-2 mt-1', [
                      button(
                        classes: 'px-3 py-1.5 rounded-lg bg-red-500 text-white font-bold text-xs hover:bg-red-600 transition-colors',
                        events: {'click': (_) => _deleteListing(r['id'])},
                        disabled: _isProcessing,
                        [Component.text('Yes, Delete')],
                      ),
                      button(
                        classes: 'px-3 py-1.5 rounded-lg border border-zinc-700 text-zinc-400 hover:text-white font-bold text-xs transition-colors',
                        events: {'click': (_) => setState(() => _showConfirmDelete = false)},
                        disabled: _isProcessing,
                        [Component.text('Cancel')],
                      ),
                    ]),
                  ])
                else
                  div(classes: 'mb-6 flex justify-end', [
                    button(
                      classes: 'px-4 py-2 text-xs font-bold text-red-500 border border-red-500/20 hover:bg-red-500/10 rounded-xl transition-all flex items-center gap-1.5',
                      events: {'click': (_) => setState(() => _showConfirmDelete = true)},
                      disabled: _isProcessing,
                      [
                        lIcon('trash-2', cls: 'w-4 h-4'),
                        Component.text('Delete Listing'),
                      ],
                    ),
                  ]),

                h3(classes: 'text-sm font-bold text-zinc-400 uppercase tracking-wider mb-4', [Component.text('Booking Requests (${_requests.length})')]),
                
                if (_isLoadingRequests)
                  div(classes: 'py-12 flex flex-col items-center justify-center gap-3', [
                    lIcon('loader', cls: 'w-8 h-8 animate-spin text-purple-500'),
                    p(classes: 'text-sm text-zinc-500', [Component.text('Fetching applications...')]),
                  ])
                else if (_requests.isEmpty)
                  div(classes: 'py-12 text-center rounded-2xl border-2 border-dashed ${isDark ? "border-zinc-800" : "border-zinc-200"}', [
                    lIcon('user-plus', cls: 'w-10 h-10 mx-auto text-zinc-600 mb-3'),
                    p(classes: 'font-semibold text-zinc-400', [Component.text('No active requests yet')]),
                    p(classes: 'text-xs text-zinc-500 mt-1', [Component.text('Rentees who request to book this vehicle will appear here.')]),
                  ])
                else
                  div(classes: 'flex flex-col gap-4', [
                    for (final req in _requests)
                      div(
                        classes: 'p-5 rounded-2xl border transition-all ${isDark ? "bg-zinc-950 border-zinc-800 hover:border-zinc-700" : "bg-white border-zinc-200 hover:shadow-md"}',
                        [
                          div(classes: 'flex items-start justify-between mb-4', [
                            div(classes: 'flex items-center gap-3', [
                              div(
                                classes: 'w-10 h-10 rounded-full bg-purple-500/20 flex items-center justify-center overflow-hidden',
                                [
                                  if (req['renteePhotoUrl'] != null && req['renteePhotoUrl'].toString().isNotEmpty && req['renteePhotoUrl'].toString() != 'null')
                                    img(src: req['renteePhotoUrl'].toString(), classes: 'w-full h-full object-cover')
                                  else
                                    lIcon('user', cls: 'w-5 h-5 text-purple-400'),
                                ],
                              ),
                              div([
                                p(classes: 'font-bold flex items-center gap-2', [
                                  Component.text(req['renteeName'] ?? 'Renter'),
                                  if (req['hireWithDriver'] == true)
                                    span(classes: 'text-[10px] font-bold px-2 py-0.5 rounded-full bg-purple-500/20 text-purple-400 border border-purple-500/30', [
                                      Component.text('With Driver')
                                    ]),
                                ]),
                                p(classes: 'text-xs text-zinc-500', [Component.text('License: ${_obscureLicenseNumber(req['licenseNumber']?.toString())}')]),
                              ]),
                            ]),
                            div(classes: 'text-right', [
                              p(classes: 'font-black text-purple-400', [Component.text('₱${req["totalCost"]}')]),
                              p(classes: 'text-xs text-zinc-500 capitalize', [Component.text('${req["multiplier"]} ${req["durationType"]}')]),
                            ]),
                          ]),
                          
                          // Contract Accordion / Details
                          div(
                            classes: 'mb-4 p-3.5 rounded-xl text-xs ${isDark ? "bg-zinc-900 text-zinc-400" : "bg-zinc-50 text-zinc-600"}',
                            [
                              div(classes: 'flex justify-between mb-1', [
                                span([Component.text('Contract Signature:')]),
                                span(classes: 'font-bold italic text-purple-400', [Component.text(req['signatureName'] ?? 'Unsigned')]),
                              ]),
                              div(classes: 'flex justify-between', [
                                span([Component.text('Requested Date:')]),
                                span([Component.text(DateTime.fromMillisecondsSinceEpoch(req['createdAt'] ?? 0).toString().substring(0, 16))]),
                              ]),
                            ],
                          ),

                          // Actions
                          div(classes: 'flex items-center gap-2', [
                            button(
                              classes: 'flex-1 py-2 rounded-xl text-sm font-semibold text-white logo-gradient hover:opacity-90 disabled:opacity-50 transition-opacity',
                              events: {'click': (_) => _approveRequest(req['id'])},
                              disabled: _isProcessing,
                              [Component.text('Approve Request')],
                            ),
                            button(
                              classes: 'px-4 py-2 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-800 hover:bg-zinc-900 text-zinc-400 hover:text-white" : "border-zinc-200 hover:bg-zinc-50 text-zinc-500"} transition-colors',
                              events: {'click': (_) => _rejectRequest(req['id'])},
                              disabled: _isProcessing,
                              [Component.text('Reject')],
                            ),
                          ]),
                        ],
                      ),
                  ]),
              ] else ...[
                // Active Booking Details View
                h3(classes: 'text-sm font-bold text-zinc-400 uppercase tracking-wider mb-4', [Component.text('Active Renter Info')]),
                div(
                  classes: 'p-5 rounded-2xl border mb-6 ${isDark ? "bg-zinc-950 border-zinc-800" : "bg-white border-zinc-200 shadow-sm"}',
                  [
                    div(classes: 'flex items-center gap-3 mb-4', [
                      div(
                        classes: 'w-12 h-12 rounded-full bg-purple-500/20 flex items-center justify-center overflow-hidden',
                        [
                          if (r['renteePhotoUrl'] != null && r['renteePhotoUrl'].toString().isNotEmpty && r['renteePhotoUrl'].toString() != 'null')
                            img(src: r['renteePhotoUrl'].toString(), classes: 'w-full h-full object-cover')
                          else
                            lIcon('user', cls: 'w-6 h-6 text-purple-400'),
                        ],
                      ),
                      div([
                        p(classes: 'font-extrabold text-base flex items-center gap-2', [
                          Component.text(r['renteeName'] ?? 'Active Renter'),
                          if (r['hireWithDriver'] == true)
                            span(classes: 'text-[10px] font-bold px-2 py-0.5 rounded-full bg-purple-500/20 text-purple-400 border border-purple-500/30', [
                              Component.text('With Driver')
                            ]),
                        ]),
                        p(classes: 'text-xs text-zinc-500', [Component.text('License: ${_obscureLicenseNumber(r["renteeLicenseNumber"]?.toString())}')]),
                      ]),
                    ]),
                    
                    // Contract Duration / Details
                    div(
                      classes: 'p-4 rounded-xl text-sm ${isDark ? "bg-zinc-900/60" : "bg-zinc-50"} flex flex-col gap-2',
                      [
                        div(classes: 'flex justify-between', [
                          span(classes: 'text-zinc-500', [Component.text('Package:')]),
                          span(classes: 'font-bold capitalize', [Component.text('${r["rentalMultiplier"]} ${r["rentalDurationType"]}')]),
                        ]),
                        div(classes: 'flex justify-between', [
                          span(classes: 'text-zinc-500', [Component.text('Total Cost:')]),
                          span(classes: 'font-black text-purple-400', [Component.text('₱${r["totalCost"]}')]),
                        ]),
                        if (r['startDate'] != null)
                          div(classes: 'flex justify-between', [
                            span(classes: 'text-zinc-500', [Component.text('Start Date:')]),
                            span([Component.text(DateTime.fromMillisecondsSinceEpoch(r['startDate'] as int).toString().substring(0, 16))]),
                          ]),
                        if (r['endDate'] != null)
                          div(classes: 'flex justify-between', [
                            span(classes: 'text-zinc-500', [Component.text('End Date:')]),
                            span([Component.text(DateTime.fromMillisecondsSinceEpoch(r['endDate'] as int).toString().substring(0, 16))]),
                          ]),
                      ],
                    ),
                  ],
                ),

                // Controls to advance status
                div(classes: 'flex flex-col gap-3', [
                  if (status == 'Booked')
                    button(
                      classes: 'w-full py-3 rounded-2xl text-sm font-semibold text-white logo-gradient hover:opacity-90 disabled:opacity-50 transition-opacity flex items-center justify-center gap-2',
                      events: {'click': (_) => _updateStatus('Ongoing')},
                      disabled: _isProcessing,
                      [
                        lIcon('key', cls: 'w-5 h-5'),
                        Component.text('Hand Over & Start Rental'),
                      ],
                    )
                  else if (status == 'Ongoing')
                    button(
                      classes: 'w-full py-3 rounded-2xl text-sm font-semibold text-white bg-purple-500 hover:bg-purple-600 disabled:opacity-50 transition-colors flex items-center justify-center gap-2',
                      events: {'click': (_) => _updateStatus('Returning')},
                      disabled: _isProcessing,
                      [
                        lIcon('refresh-cw', cls: 'w-5 h-5'),
                        Component.text('Mark as Returning'),
                      ],
                    )
                  else if (status == 'Returning')
                    button(
                      classes: 'w-full py-3 rounded-2xl text-sm font-semibold text-white bg-green-500 hover:bg-green-600 disabled:opacity-50 transition-colors flex items-center justify-center gap-2',
                      events: {'click': (_) => _updateStatus('Completed')},
                      disabled: _isProcessing,
                      [
                        lIcon('check-circle', cls: 'w-5 h-5'),
                        Component.text('Confirm Vehicle Returned'),
                      ],
                    ),

                  // Open Live Tracking Button
                  button(
                    classes: 'w-full py-3 rounded-2xl text-sm font-semibold border ${isDark ? "border-zinc-800 hover:bg-zinc-800 text-zinc-300" : "border-zinc-200 hover:bg-zinc-50 text-zinc-600"} transition-colors flex items-center justify-center gap-2',
                    events: {'click': (_) {
                      component.appState.setState(() {
                        component.appState.showManageVehicleModal = false;
                        component.appState.showRentalTrackerMap = true;
                      });
                    }},
                    [
                      lIcon('map', cls: 'w-5 h-5'),
                      Component.text('Open Live Tracking Map'),
                    ],
                  ),
                ]),
              ],
            ]),
          ],
        ),
      ],
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
