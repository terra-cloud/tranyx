import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';

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

  bool _allowChat = false;

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
      final list = await component.appState.firestore.getPropertyPendingRequestsForProperty(prop['id']);
      setState(() {
        _requests = list;
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

      component.appState.setState(() {
        component.appState.showManagePropertyModal = false;
        component.appState.selectedPropertyData = null;
      });
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

  @override
  Component build(BuildContext context) {
    final isDark = component.appState.isDark;
    final prop = component.appState.selectedPropertyData;
    if (prop == null) return div([]);

    final status = prop['status'] as String? ?? 'Available';
    final title = prop['title'] ?? 'Unknown Property';
    final propTypeStr = prop['type'] ?? 'house';
    final categoryStr = prop['category'] ?? 'residential';
    final monthlyRent = prop['priceMonthly'] ?? 0.0;

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
                  h2(classes: 'text-xl font-black tracking-tight', [Component.text('Manage Property')]),
                  p(classes: 'text-sm text-zinc-500', [Component.text('$title • $categoryStr $propTypeStr')]),
                ]),
                button(
                  classes: 'p-2 rounded-full hover:bg-zinc-800/20 transition-colors',
                  events: {
                    'click': (_) => component.appState.setState(() {
                      component.appState.showManagePropertyModal = false;
                      component.appState.selectedPropertyData = null;
                    }),
                  },
                  [lIcon('x', cls: 'w-6 h-6')],
                ),
              ],
            ),

            // Body
            div(classes: 'flex-1 overflow-y-auto p-6', [
              if (_error != null)
                div(
                  classes:
                      'mb-4 p-4 rounded-2xl bg-red-500/10 border border-red-500/20 text-red-400 text-sm flex items-center gap-2',
                  [
                    lIcon('alert-circle', cls: 'w-5 h-5 flex-shrink-0'),
                    span([Component.text(_error!)]),
                  ],
                ),

              // Status Summary Card
              div(
                classes:
                    'p-5 rounded-2xl mb-6 flex items-center justify-between ${isDark ? "bg-zinc-800/40 border border-zinc-800" : "bg-zinc-50 border border-zinc-200"}',
                [
                  div([
                    p(classes: 'text-xs text-zinc-500 font-bold uppercase tracking-wider mb-1', [
                      Component.text('Listing Status'),
                    ]),
                    h3(classes: 'text-lg font-bold capitalize text-purple-400', [Component.text(status)]),
                  ]),
                  div(classes: 'text-right', [
                    p(classes: 'text-xs text-zinc-500 font-bold uppercase tracking-wider mb-1', [
                      Component.text('Monthly Rent'),
                    ]),
                    h3(classes: 'text-lg font-extrabold', [Component.text('₱${monthlyRent.toStringAsFixed(0)}/mo')]),
                  ]),
                ],
              ),

              if (status == 'Available') ...[
                if (_showConfirmDelete)
                  div(classes: 'mb-6 p-4 rounded-2xl bg-red-500/10 border border-red-500/20 text-sm flex flex-col gap-3', [
                    div(classes: 'flex items-center gap-2 text-red-400 font-bold', [
                      lIcon('alert-triangle', cls: 'w-5 h-5 flex-shrink-0'),
                      span([Component.text('Delete this listing permanently?')]),
                    ]),
                    p(classes: 'text-zinc-400 text-xs', [
                      Component.text(
                        'This will delete the property posting from Tranyx. The 1.5% listing fee is non-refundable.',
                      ),
                    ]),
                    div(classes: 'flex items-center gap-2 mt-1', [
                      button(
                        classes:
                            'px-3 py-1.5 rounded-lg bg-red-500 text-white font-bold text-xs hover:bg-red-600 transition-colors border-0 cursor-pointer',
                        events: {'click': (_) => _deleteListing(prop['id'])},
                        disabled: _isProcessing,
                        [Component.text('Yes, Delete')],
                      ),
                      button(
                        classes:
                            'px-3 py-1.5 rounded-lg border border-zinc-705 text-zinc-400 hover:text-white font-bold text-xs transition-colors bg-transparent cursor-pointer',
                        events: {'click': (_) => setState(() => _showConfirmDelete = false)},
                        disabled: _isProcessing,
                        [Component.text('Cancel')],
                      ),
                    ]),
                  ])
                else
                  div(classes: 'mb-6 flex justify-end', [
                    button(
                      classes:
                          'px-4 py-2 text-xs font-bold text-red-500 border border-red-500/20 hover:bg-red-500/10 rounded-xl transition-all flex items-center gap-1.5 cursor-pointer bg-transparent',
                      events: {'click': (_) => setState(() => _showConfirmDelete = true)},
                      disabled: _isProcessing,
                      [
                        lIcon('trash-2', cls: 'w-4 h-4'),
                        Component.text('Delete Listing'),
                      ],
                    ),
                  ]),

                h3(classes: 'text-sm font-bold text-zinc-400 uppercase tracking-wider mb-4', [
                  Component.text('Lease Booking Requests (${_requests.length})'),
                ]),

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
                      p(classes: 'font-semibold text-zinc-400', [Component.text('No pending requests')]),
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
                                p(classes: 'text-xs text-zinc-500', [Component.text('ID Verified')]),
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

                          // Pre-actions (View Profile + Chat Toggle)
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

                          // Actions
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
                        ],
                      ),
                  ]),
              ] else ...[
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
                                  classes: 'absolute -top-1 -right-1 px-1.5 py-0.5 text-[9px] font-black text-white bg-red-500 rounded-full border border-white animate-pulse',
                                  [Component.text('${component.appState.getUnreadChatCount(chatId)}')],
                                ),
                            ],
                          );
                        }()
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
                          classes: 'max-h-20 h-auto object-contain bg-white rounded-lg p-2 max-w-[240px] cursor-zoom-in hover:opacity-95 transition-opacity',
                          events: {
                            'click': (_) => component.appState.showFullScreenPhoto(prop['renteeSignatureName'].toString())
                          },
                        ),
                      ]),
                  ],
                ),

                if (status == 'Awaiting Signature')
                  div(
                    classes:
                        'p-4 rounded-xl border border-yellow-500/20 bg-yellow-500/10 text-yellow-500 text-xs text-center font-semibold mb-6',
                    [Component.text('Awaiting tenant to sign the contract and finalize this lease.')],
                  ),

                if (status == 'Booked' || status == 'Active')
                  button(
                    classes:
                        'w-full py-3.5 rounded-2xl text-sm font-bold text-white bg-green-500 hover:bg-green-600 disabled:opacity-50 transition-colors flex items-center justify-center gap-2 border-0 cursor-pointer',
                    events: {'click': (_) => _completeLease()},
                    disabled: _isProcessing,
                    [
                      lIcon('check-circle', cls: 'w-5 h-5'),
                      Component.text('Complete Lease & Release Payout'),
                    ],
                  ),
              ],
            ]),
          ],
        ),
      ],
    );
  }
}
