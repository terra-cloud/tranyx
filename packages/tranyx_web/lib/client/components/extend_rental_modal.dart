import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';

class ExtendRentalModalComponent extends StatefulComponent {
  final TranyxAppState appState;
  const ExtendRentalModalComponent({required this.appState, super.key});

  @override
  State<ExtendRentalModalComponent> createState() => _ExtendRentalModalState();
}

class _ExtendRentalModalState extends State<ExtendRentalModalComponent> {
  int _currentStep = 1; // 1: Select Duration, 2: Review Pricing & Pay
  int _extendHours = 1;
  int _maxAllowedHours = 24;
  bool _isLoadingAvailability = true;
  bool _isProcessing = false;
  String? _error;
  String? _conflictNotice;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  @override
  void didUpdateComponent(ExtendRentalModalComponent oldWidget) {
    super.didUpdateComponent(oldWidget);
    if (component.appState.selectedRentalData != oldWidget.appState.selectedRentalData) {
      _checkAvailability();
    }
  }

  Future<void> _checkAvailability() async {
    final r = component.appState.selectedRentalData;
    if (r == null) return;
    setState(() {
      _isLoadingAvailability = true;
      _error = null;
      _conflictNotice = null;
    });

    try {
      final rentalId = (r['rentalId'] ?? r['id']) as String;
      final currentEndMs = (r['endDate'] as num?)?.toInt() ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (currentEndMs <= nowMs) {
        _maxAllowedHours = 0;
        _conflictNotice =
            'This trip is past its scheduled return time. Overdue rentals cannot be extended self-service to protect upcoming reservations. Please return the vehicle or contact the host.';
        setState(() => _isLoadingAvailability = false);
        return;
      }

      final approvedRequests = await component.appState.firestore.getApprovedRequestsForVehicle(rentalId);

      // Find earliest future reservation start after currentEndMs
      int? nextBookingStartMs;
      for (final req in approvedRequests) {
        final reqId = req['id'] as String?;
        if (reqId != null && reqId == r['currentRequestId']) continue;

        final reqStart = (req['startDate'] as num?)?.toInt() ?? 0;
        if (reqStart > currentEndMs) {
          if (nextBookingStartMs == null || reqStart < nextBookingStartMs) {
            nextBookingStartMs = reqStart;
          }
        }
      }

      if (nextBookingStartMs != null) {
        // Reserve a 1-hour turnaround / cleaning buffer
        const bufferMs = 3600 * 1000;
        final maxExtendMs = nextBookingStartMs - bufferMs;
        final availableMs = maxExtendMs - currentEndMs;
        final maxHours = (availableMs / (3600 * 1000)).floor();

        if (maxHours <= 0) {
          _maxAllowedHours = 0;
          _conflictNotice =
              'This vehicle cannot be extended because another customer has an upcoming booking scheduled shortly. Please return by your scheduled time.';
        } else {
          _maxAllowedHours = maxHours;
          _conflictNotice = 'Capped at $maxHours hour(s) due to an upcoming reservation after this trip.';
          if (_extendHours > _maxAllowedHours) {
            _extendHours = _maxAllowedHours;
          }
        }
      } else {
        _maxAllowedHours = 24; // Default max extension ceiling per session
      }
    } catch (e) {
      print('Warning: could not check extension availability: $e');
    } finally {
      setState(() => _isLoadingAvailability = false);
    }
  }

  double get _penaltyPerHour {
    final r = component.appState.selectedRentalData;
    if (r == null) return 200.0;
    final val = r['extensionRatePerHour'] ?? r['latePenaltyRatePerHour'] ?? r['extensionPenaltyPerHour'];
    if (val != null) {
      final parsed = (val as num).toDouble();
      if (parsed > 0) return parsed;
    }
    final priceDaily = (r['priceDaily'] as num?)?.toDouble();
    if (priceDaily != null && priceDaily > 0) {
      return (priceDaily / 24.0) * 1.5;
    }
    final priceHourly = (r['priceHourly'] as num?)?.toDouble();
    if (priceHourly != null && priceHourly > 0) {
      return priceHourly;
    }
    return 200.0;
  }

  double get _totalExtensionFee => _penaltyPerHour * _extendHours;

  double get _userBalance => (component.appState.userProfile?.tyxBalance ?? 0.0).toDouble();

  bool get _hasInsufficientBalance => _userBalance < _totalExtensionFee;

  double get _deficit => _hasInsufficientBalance ? (_totalExtensionFee - _userBalance) : 0.0;

  int get _currentEndMs {
    final r = component.appState.selectedRentalData;
    return (r?['endDate'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
  }

  int get _newEndMs {
    return DateTime.fromMillisecondsSinceEpoch(_currentEndMs).add(Duration(hours: _extendHours)).millisecondsSinceEpoch;
  }

  String _formatDateTime(int epochMs) {
    if (epochMs <= 0) return 'N/A';
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[dt.month - 1];
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$month ${dt.day}, ${dt.year} $hour:$min $ampm';
  }

  void _closeModal() {
    component.appState.setState(() {
      component.appState.showExtendRentalModal = false;
      if (!component.appState.showRentalTrackerMap) {
        component.appState.selectedRentalData = null;
      }
    });
  }

  void _openDepositModal() {
    component.appState.setState(() {
      component.appState.depositAmount = _deficit;
      component.appState.showDepositModal = true;
    });
  }

  void _extend() async {
    final r = component.appState.selectedRentalData;
    if (r == null) return;
    final user = component.appState.userProfile;
    if (user == null) {
      setState(() => _error = 'User is not authenticated.');
      return;
    }

    final fee = _totalExtensionFee;
    if (user.tyxBalance < fee) {
      _openDepositModal();
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final rentalId = (r['rentalId'] ?? r['id']) as String;
      final requestId =
          (r['currentRequestId'] ?? r['requestId'] ?? (r.containsKey('rentalId') ? r['id'] : null)) as String?;
      final uid = user.uid;

      await component.appState.firestore.autoApproveExtension(
        rentalId: rentalId,
        renteeId: uid,
        extendHours: _extendHours,
        fee: fee,
        requestId: requestId,
      );

      // Optimistically update local rental data
      final newEndMs = _newEndMs;
      r['endDate'] = newEndMs;
      final currentCost = (r['totalCost'] as num? ?? 0.0).toDouble();
      r['totalCost'] = currentCost + fee;

      component.appState.showAppToast(
        'Extension Confirmed',
        'Rental successfully extended by $_extendHours hour(s). ₱ ${fee.toStringAsFixed(2)} debited to escrow.',
      );

      // Close modal and keep tracker map open if active
      component.appState.setState(() {
        component.appState.showExtendRentalModal = false;
        if (!component.appState.showRentalTrackerMap) {
          component.appState.selectedRentalData = null;
        }
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Component build(BuildContext context) {
    if (!component.appState.showExtendRentalModal || component.appState.selectedRentalData == null) {
      return div([]);
    }

    final isDark = component.appState.isDark;
    final r = component.appState.selectedRentalData!;
    final brand = r['brand'] ?? 'Unknown';
    final model = r['model'] ?? 'Vehicle';
    final plate = r['plateNumber'] ?? r['plate'] ?? '';

    return div(
      classes: 'fixed inset-0 z-[70] flex items-center justify-center p-4 bg-black/65 backdrop-blur-md animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-lg max-h-[90vh] overflow-y-auto rounded-3xl shadow-2xl relative flex flex-col ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white border border-zinc-150"}',
          [
            // Header with Wizard Stepper
            div(
              classes:
                  'sticky top-0 z-10 flex flex-col p-6 border-b ${isDark ? "bg-zinc-900/95 border-zinc-800" : "bg-white/95 border-zinc-100"} backdrop-blur-md',
              [
                div(classes: 'flex items-center justify-between', [
                  div([
                    h2(classes: 'text-xl font-bold flex items-center gap-2', [
                      lIcon('clock', cls: 'w-5 h-5 text-purple-400'),
                      Component.text('Extend Rental'),
                    ]),
                    p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"} mt-0.5', [
                      Component.text('$brand $model${plate.isNotEmpty ? " • $plate" : ""}'),
                    ]),
                  ]),
                  button(
                    classes:
                        'p-2 rounded-full hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors cursor-pointer border-0 bg-transparent text-zinc-400 hover:text-zinc-200',
                    events: {'click': (_) => _closeModal()},
                    [lIcon('x', cls: 'w-5 h-5')],
                  ),
                ]),

                // Wizard Steps Breadcrumb
                div(classes: 'flex items-center gap-2 mt-4 pt-3 border-t ${isDark ? "border-zinc-800/60" : "border-zinc-100"}', [
                  div(
                    classes:
                        'flex-1 flex items-center gap-2 px-3 py-1.5 rounded-xl text-xs font-semibold ${_currentStep == 1 ? "bg-purple-500/15 text-purple-400 border border-purple-500/30" : "bg-zinc-800/40 text-zinc-400"}',
                    [
                      span(
                        classes:
                            'w-5 h-5 rounded-full flex items-center justify-center text-[10px] ${_currentStep == 1 ? "bg-purple-500 text-white" : "bg-zinc-700 text-zinc-300"}',
                        [Component.text('1')],
                      ),
                      Component.text('Duration'),
                    ],
                  ),
                  lIcon('chevron-right', cls: 'w-4 h-4 text-zinc-600'),
                  div(
                    classes:
                        'flex-1 flex items-center gap-2 px-3 py-1.5 rounded-xl text-xs font-semibold ${_currentStep == 2 ? "bg-purple-500/15 text-purple-400 border border-purple-500/30" : "bg-zinc-800/40 text-zinc-400"}',
                    [
                      span(
                        classes:
                            'w-5 h-5 rounded-full flex items-center justify-center text-[10px] ${_currentStep == 2 ? "bg-purple-500 text-white" : "bg-zinc-700 text-zinc-300"}',
                        [Component.text('2')],
                      ),
                      Component.text('Pricing & Pay'),
                    ],
                  ),
                ]),
              ],
            ),

            // Body
            div(classes: 'p-6 flex-1 space-y-6', [
              if (_error != null)
                div(classes: 'p-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 text-sm font-medium flex items-center gap-2.5', [
                  lIcon('alert-triangle', cls: 'w-5 h-5 flex-shrink-0 text-red-400'),
                  span([Component.text(_error!)]),
                ]),

              if (_conflictNotice != null)
                div(
                  classes:
                      'p-4 rounded-xl text-xs font-semibold ${_maxAllowedHours <= 0 ? "bg-amber-500/15 border border-amber-500/30 text-amber-300" : "bg-blue-500/15 border border-blue-500/30 text-blue-300"} flex items-center gap-2.5',
                  [
                    lIcon(_maxAllowedHours <= 0 ? 'alert-triangle' : 'info', cls: 'w-4 h-4 flex-shrink-0'),
                    span([Component.text(_conflictNotice!)]),
                  ],
                ),

              if (_isLoadingAvailability)
                div(classes: 'py-12 flex flex-col items-center justify-center gap-3 text-zinc-400 text-sm', [
                  lIcon('loader', cls: 'w-8 h-8 animate-spin text-purple-400'),
                  Component.text('Checking vehicle schedule availability...'),
                ])
              else if (_maxAllowedHours <= 0)
                div(
                  classes:
                      'py-8 px-5 rounded-2xl bg-amber-500/10 border border-amber-500/30 text-center text-sm text-amber-200 space-y-3',
                  [
                    lIcon('alert-triangle', cls: 'w-8 h-8 mx-auto text-amber-400'),
                    p(classes: 'font-bold text-base', [
                      Component.text(_conflictNotice ?? 'This vehicle cannot be extended.'),
                    ]),
                    p(classes: 'text-xs text-zinc-400 max-w-sm mx-auto', [
                      Component.text(
                        'To protect subsequent reservations and avoid late return surcharges, please complete your trip and return the vehicle by the scheduled return time.',
                      ),
                    ]),
                  ],
                )
              else if (_currentStep == 1) ...[
                // STEP 1: DURATION WIZARD
                div(classes: 'space-y-6', [
                  // Return Time Transformation Card
                  div(
                    classes:
                        'p-4 rounded-2xl ${isDark ? "bg-zinc-800/60 border border-zinc-700/60" : "bg-zinc-50 border border-zinc-200"} flex items-center justify-between gap-2',
                    [
                      div(classes: 'flex-1', [
                        span(classes: 'text-[10px] font-bold uppercase tracking-wider text-zinc-400 block mb-1', [
                          Component.text('Current Return'),
                        ]),
                        span(classes: 'text-xs font-semibold block text-zinc-300', [
                          Component.text(_formatDateTime(_currentEndMs)),
                        ]),
                      ]),
                      div(classes: 'p-2 rounded-full bg-purple-500/10 text-purple-400 flex-shrink-0', [
                        lIcon('arrow-right', cls: 'w-4 h-4'),
                      ]),
                      div(classes: 'flex-1 text-right', [
                        span(classes: 'text-[10px] font-bold uppercase tracking-wider text-purple-400 block mb-1', [
                          Component.text('New Return'),
                        ]),
                        span(classes: 'text-xs font-bold block text-purple-300', [
                          Component.text(_formatDateTime(_newEndMs)),
                        ]),
                      ]),
                    ],
                  ),

                  // Interactive Stepper
                  div(classes: 'flex flex-col items-center gap-3', [
                    p(classes: 'text-center text-xs font-medium ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                      Component.text('How many hours would you like to extend?'),
                    ]),
                    div(classes: 'flex items-center justify-center gap-5', [
                      button(
                        classes:
                            'w-12 h-12 rounded-2xl border flex items-center justify-center ${isDark ? "border-zinc-700 bg-zinc-800 text-zinc-200" : "border-zinc-300 bg-zinc-100 text-zinc-700"} hover:opacity-80 transition-all ${_extendHours <= 1 ? "opacity-30 cursor-not-allowed" : "cursor-pointer active:scale-95"}',
                        events: {
                          'click': (_) {
                            if (_extendHours > 1) {
                              setState(() => _extendHours--);
                            }
                          },
                        },
                        [lIcon('minus', cls: 'w-5 h-5')],
                      ),
                      div(classes: 'flex flex-col items-center min-w-[100px]', [
                        span(classes: 'text-4xl font-black tabular-nums text-purple-400 leading-none', [
                          Component.text('$_extendHours'),
                        ]),
                        span(classes: 'text-[11px] font-bold text-zinc-400 uppercase tracking-wider mt-1', [
                          Component.text(_extendHours == 1 ? 'Hour' : 'Hours'),
                        ]),
                      ]),
                      button(
                        classes:
                            'w-12 h-12 rounded-2xl border flex items-center justify-center ${isDark ? "border-zinc-700 bg-zinc-800 text-zinc-200" : "border-zinc-300 bg-zinc-100 text-zinc-700"} hover:opacity-80 transition-all ${_extendHours >= _maxAllowedHours ? "opacity-30 cursor-not-allowed" : "cursor-pointer active:scale-95"}',
                        events: {
                          'click': (_) {
                            if (_extendHours < _maxAllowedHours) {
                              setState(() => _extendHours++);
                            }
                          },
                        },
                        [lIcon('plus', cls: 'w-5 h-5')],
                      ),
                    ]),
                    span(classes: 'text-xs font-medium text-zinc-400', [
                      Component.text('Maximum allowed extension: $_maxAllowedHours hour(s)'),
                    ]),
                  ]),

                  // Quick Preset Chips
                  div(classes: 'space-y-2', [
                    span(classes: 'text-[11px] font-bold text-zinc-400 uppercase tracking-wider block text-center', [
                      Component.text('Quick Presets'),
                    ]),
                    div(classes: 'flex flex-wrap items-center justify-center gap-2', [
                      for (final hours in [1, 2, 4, 8, 12, 24])
                        if (hours <= _maxAllowedHours)
                          button(
                            classes:
                                'px-3.5 py-1.5 rounded-xl text-xs font-bold transition-all cursor-pointer border '
                                '${_extendHours == hours ? "bg-purple-600 text-white border-purple-500 shadow-md shadow-purple-500/20" : (isDark ? "bg-zinc-800/80 hover:bg-zinc-750 text-zinc-300 border-zinc-700" : "bg-zinc-100 hover:bg-zinc-200 text-zinc-700 border-zinc-200")}',
                            events: {'click': (_) => setState(() => _extendHours = hours)},
                            [Component.text('+$hours hr${hours > 1 ? "s" : ""}')],
                          ),
                    ]),
                  ]),

                  // Rate & Subtotal Preview Pill
                  div(
                    classes:
                        'p-4 rounded-2xl bg-purple-500/10 border border-purple-500/20 flex items-center justify-between text-xs',
                    [
                      div(classes: 'flex items-center gap-2', [
                        lIcon('clock', cls: 'w-4 h-4 text-purple-400'),
                        span(classes: isDark ? 'text-zinc-300' : 'text-zinc-700', [
                          Component.text('Rate: ₱ ${_penaltyPerHour.toStringAsFixed(2)} / hour'),
                        ]),
                      ]),
                      span(classes: 'font-black text-sm text-purple-400', [
                        Component.text('Est. ₱ ${_totalExtensionFee.toStringAsFixed(2)}'),
                      ]),
                    ],
                  ),
                ]),
              ] else ...[
                // STEP 2: PRICING & PAYMENT WIZARD
                div(classes: 'space-y-5', [
                  // Back button
                  button(
                    classes:
                        'inline-flex items-center gap-1.5 text-xs font-semibold text-zinc-400 hover:text-zinc-200 transition-colors cursor-pointer border-0 bg-transparent p-0',
                    events: {'click': (_) => setState(() => _currentStep = 1)},
                    [
                      lIcon('arrow-left', cls: 'w-3.5 h-3.5'),
                      Component.text('Back to Duration'),
                    ],
                  ),

                  // Smart Calculation Cost Breakdown
                  div(classes: 'p-5 rounded-2xl bg-purple-500/10 border border-purple-500/20 space-y-3', [
                    div(classes: 'flex justify-between text-xs', [
                      span(classes: isDark ? 'text-zinc-400' : 'text-zinc-600', [Component.text('Vehicle')]),
                      span(classes: 'font-bold', [Component.text('$brand $model')]),
                    ]),
                    div(classes: 'flex justify-between text-xs', [
                      span(classes: isDark ? 'text-zinc-400' : 'text-zinc-600', [Component.text('Hourly Rate')]),
                      span(classes: 'font-bold', [Component.text('₱ ${_penaltyPerHour.toStringAsFixed(2)} / hr')]),
                    ]),
                    div(classes: 'flex justify-between text-xs', [
                      span(classes: isDark ? 'text-zinc-400' : 'text-zinc-600', [Component.text('Extension Duration')]),
                      span(classes: 'font-bold', [Component.text('$_extendHours hour(s)')]),
                    ]),
                    div(classes: 'flex justify-between text-xs', [
                      span(classes: isDark ? 'text-zinc-400' : 'text-zinc-600', [Component.text('New Return Deadline')]),
                      span(classes: 'font-bold text-purple-400', [Component.text(_formatDateTime(_newEndMs))]),
                    ]),
                    div(classes: 'h-px w-full bg-purple-500/20 my-2', []),
                    div(classes: 'flex justify-between items-baseline', [
                      span(classes: 'font-bold text-sm', [Component.text('Total Extension Fee')]),
                      span(classes: 'font-black text-2xl text-purple-400', [
                        Component.text('₱ ${_totalExtensionFee.toStringAsFixed(2)}'),
                      ]),
                    ]),
                    div(classes: 'flex items-center gap-1.5 pt-1 text-[11px] text-zinc-400', [
                      lIcon('lock', cls: 'w-3.5 h-3.5 text-purple-400'),
                      span([Component.text('100% Escrow Protected — Payment held safely until trip return.')]),
                    ]),
                  ]),

                  // Wallet Assessment & Deficit Breakdown
                  if (_hasInsufficientBalance)
                    div(
                      classes:
                          'p-4 rounded-2xl bg-amber-500/10 border border-amber-500/30 space-y-2 text-xs text-amber-200',
                      [
                        div(classes: 'flex items-center gap-2 font-bold text-amber-400', [
                          lIcon('alert-triangle', cls: 'w-4 h-4 flex-shrink-0'),
                          Component.text('Insufficient Wallet Balance'),
                        ]),
                        div(classes: 'flex justify-between pt-1', [
                          span(classes: 'text-zinc-400', [Component.text('Your Available Balance:')]),
                          span(classes: 'font-bold text-amber-400', [
                            Component.text('₱ ${_userBalance.toStringAsFixed(2)} TYXBIT'),
                          ]),
                        ]),
                        div(classes: 'flex justify-between', [
                          span(classes: 'text-zinc-400', [Component.text('Total Fee Required:')]),
                          span(classes: 'font-bold text-zinc-200', [
                            Component.text('₱ ${_totalExtensionFee.toStringAsFixed(2)} TYXBIT'),
                          ]),
                        ]),
                        div(classes: 'flex justify-between font-bold border-t border-amber-500/20 pt-2 text-amber-300', [
                          span([Component.text('Balance Deficit:')]),
                          span(classes: 'text-sm', [
                            Component.text('₱ ${_deficit.toStringAsFixed(2)} TYXBIT'),
                          ]),
                        ]),
                        p(classes: 'text-[11px] text-zinc-400 pt-1', [
                          Component.text(
                            'Click the button below to top up the exact deficit amount (₱ ${_deficit.toStringAsFixed(2)}) via GCash P2P or Solana, then return to extend.',
                          ),
                        ]),
                      ],
                    )
                  else
                    div(
                      classes:
                          'p-4 rounded-2xl bg-green-500/10 border border-green-500/25 flex items-center justify-between text-xs',
                      [
                        div(classes: 'flex items-center gap-2', [
                          lIcon('check-circle', cls: 'w-4 h-4 text-green-400'),
                          span(classes: 'font-medium text-green-300', [Component.text('Wallet Balance Sufficient')]),
                        ]),
                        span(classes: 'font-bold text-green-400', [
                          Component.text(
                            '₱ ${_userBalance.toStringAsFixed(2)} (₱ ${(_userBalance - _totalExtensionFee).toStringAsFixed(2)} remaining)',
                          ),
                        ]),
                      ],
                    ),
                ]),
              ],
            ]),

            // Footer
            div(classes: 'p-6 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"}', [
              if (_maxAllowedHours <= 0)
                button(
                  classes:
                      'w-full py-3.5 rounded-xl font-bold text-zinc-400 bg-zinc-800 cursor-not-allowed flex items-center justify-center gap-2 border-0',
                  attributes: {'disabled': 'disabled'},
                  [Component.text('Extension Unavailable')],
                )
              else if (_currentStep == 1)
                button(
                  classes:
                      'w-full py-3.5 rounded-xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2 border-0 cursor-pointer shadow-lg shadow-purple-500/20 active:scale-[0.99]',
                  events: {'click': (_) => setState(() => _currentStep = 2)},
                  [
                    Component.text('Review Pricing & Pay'),
                    lIcon('arrow-right', cls: 'w-4 h-4'),
                  ],
                )
              else if (_hasInsufficientBalance)
                button(
                  classes:
                      'w-full py-3.5 rounded-xl font-bold text-white bg-amber-500 hover:bg-amber-600 transition-colors flex items-center justify-center gap-2 border-0 cursor-pointer shadow-lg shadow-amber-500/20 active:scale-[0.99]',
                  events: {'click': (_) => _openDepositModal()},
                  [
                    lIcon('wallet', cls: 'w-5 h-5'),
                    Component.text('Top Up ₱ ${_deficit.toStringAsFixed(2)} & Extend'),
                  ],
                )
              else
                button(
                  classes:
                      'w-full py-3.5 rounded-xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2 border-0 cursor-pointer shadow-lg shadow-purple-500/20 active:scale-[0.99]',
                  events: {'click': (_) => _extend()},
                  [
                    if (_isProcessing) lIcon('loader', cls: 'w-5 h-5 animate-spin'),
                    Component.text(
                      _isProcessing ? 'Processing Payment...' : 'Pay ₱ ${_totalExtensionFee.toStringAsFixed(2)} & Extend',
                    ),
                  ],
                ),
            ]),
          ],
        ),
      ],
    );
  }
}
