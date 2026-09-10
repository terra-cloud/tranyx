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
        _conflictNotice = 'This trip is past its scheduled return time. Overdue rentals cannot be extended self-service to protect upcoming reservations. Please return the vehicle or contact the host.';
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
          _conflictNotice = 'This vehicle cannot be extended because another customer has an upcoming booking scheduled shortly. Please return by your scheduled time.';
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
    if (r == null) return 0;
    final val = r['extensionRatePerHour'] ?? r['latePenaltyRatePerHour'] ?? r['extensionPenaltyPerHour'];
    return (val as num?)?.toDouble() ?? 0;
  }

  double get _totalExtensionFee {
    return _penaltyPerHour * _extendHours;
  }

  void _extend() async {
    final r = component.appState.selectedRentalData;
    if (r == null) return;
    final user = component.appState.userProfile;
    if (user == null) {
      setState(() => _error = 'User is not authenticated.');
      return;
    }

    // Smart Payment: Check if balance is sufficient
    final fee = _totalExtensionFee;
    if (user.tyxBalance < fee) {
      final deficit = fee - user.tyxBalance;
      component.appState.setState(() {
        component.appState.depositAmount = deficit;
        component.appState.showDepositModal = true;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final rentalId = (r['rentalId'] ?? r['id']) as String;
      final uid = user.uid;

      // Execute autoApproveExtension (debits wallet, creates payment tx, locks in escrow, updates rental endDate)
      await component.appState.firestore.autoApproveExtension(
        rentalId: rentalId,
        renteeId: uid,
        extendHours: _extendHours,
        fee: fee,
      );

      component.appState.showAppToast(
        'Extension Confirmed',
        'Rental successfully extended by $_extendHours hour(s). ₱ ${fee.toStringAsFixed(2)} debited to escrow.',
      );

      // Close modal and refresh
      component.appState.setState(() {
        component.appState.showExtendRentalModal = false;
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
    if (!component.appState.showExtendRentalModal || component.appState.selectedRentalData == null) {
      return div([]);
    }

    final isDark = component.appState.isDark;
    final r = component.appState.selectedRentalData!;
    final brand = r['brand'] ?? 'Unknown';
    final model = r['model'] ?? 'Unknown';

    return div(classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in', [
      div(
        classes:
            'w-full max-w-md max-h-[90vh] overflow-y-auto rounded-3xl shadow-2xl relative flex flex-col ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"}',
        [
          // Header
          div(
            classes:
                'sticky top-0 z-10 flex items-center justify-between p-6 border-b ${isDark ? "bg-zinc-900/90 border-zinc-800" : "bg-white/90 border-zinc-100"} backdrop-blur-md',
            [
              div([
                h2(classes: 'text-xl font-bold', [Component.text('Extend Rental')]),
                p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-500"}', [Component.text('$brand $model')]),
              ]),
              button(
                classes: 'p-2 rounded-full hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors',
                events: {
                  'click': (e) => component.appState.setState(() {
                    component.appState.showExtendRentalModal = false;
                    component.appState.selectedRentalData = null;
                  }),
                },
                [lIcon('x', cls: 'w-6 h-6')],
              ),
            ],
          ),

          // Body
          div(classes: 'p-6 flex-1 space-y-6', [
            if (_error != null)
              div(classes: 'p-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-500 text-sm font-medium', [
                Component.text(_error!),
              ]),

            if (_conflictNotice != null)
              div(
                classes:
                    'p-4 rounded-xl text-xs font-semibold ${_maxAllowedHours <= 0 ? "bg-amber-500/15 border border-amber-500/30 text-amber-400" : "bg-blue-500/15 border border-blue-500/30 text-blue-400"} flex items-center gap-2.5',
                [
                  lIcon(_maxAllowedHours <= 0 ? 'alert-triangle' : 'info', cls: 'w-4 h-4 flex-shrink-0'),
                  span([Component.text(_conflictNotice!)]),
                ],
              ),

            if (_isLoadingAvailability)
              div(classes: 'py-8 flex flex-col items-center justify-center gap-2 text-zinc-400 text-sm', [
                lIcon('loader', cls: 'w-6 h-6 animate-spin text-purple-400'),
                Component.text('Checking schedule availability...'),
              ])
            else if (_maxAllowedHours <= 0)
              div(classes: 'py-6 px-4 rounded-xl bg-amber-500/10 border border-amber-500/30 text-center text-sm text-amber-300', [
                lIcon('alert-triangle', cls: 'w-6 h-6 mx-auto mb-2 text-amber-400'),
                p(classes: 'font-semibold', [Component.text(_conflictNotice ?? 'This vehicle cannot be extended because another customer has an upcoming booking.')]),
                p(classes: 'text-xs text-zinc-400 mt-2', [Component.text('Please return the vehicle before the scheduled trip end time to prevent late penalties.')]),
              ])
            else ...[
              div(classes: 'flex flex-col items-center gap-4', [
                p(classes: 'text-center text-sm ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                  Component.text('Select the number of hours you wish to extend the rental by.'),
                ]),

                div(classes: 'flex items-center gap-4', [
                  button(
                    classes:
                        'p-3 rounded-xl border ${isDark ? "border-zinc-700 bg-zinc-800" : "border-zinc-200 bg-zinc-100"} hover:opacity-80 transition-opacity ${_extendHours <= 1 ? "opacity-50 cursor-not-allowed" : "cursor-pointer"}',
                    events: {'click': (_) => setState(() => _extendHours = _extendHours > 1 ? _extendHours - 1 : 1)},
                    [lIcon('minus', cls: 'w-5 h-5')],
                  ),
                  span(classes: 'text-3xl font-black tabular-nums w-12 text-center', [Component.text('$_extendHours')]),
                  button(
                    classes:
                        'p-3 rounded-xl border ${isDark ? "border-zinc-700 bg-zinc-800" : "border-zinc-200 bg-zinc-100"} hover:opacity-80 transition-opacity ${_extendHours >= _maxAllowedHours ? "opacity-50 cursor-not-allowed" : "cursor-pointer"}',
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
                span(classes: 'text-sm font-bold text-purple-400', [Component.text('Hours (Max: $_maxAllowedHours)')]),
              ]),

              div(classes: 'p-5 rounded-xl bg-purple-500/10 border border-purple-500/20 space-y-3', [
                div(classes: 'flex justify-between text-sm', [
                  span(classes: isDark ? 'text-zinc-400' : 'text-zinc-600', [Component.text('Extension Rate (Per Hour)')]),
                  span(classes: 'font-bold', [Component.text('₱ ${_penaltyPerHour.toStringAsFixed(2)}')]),
                ]),
                div(classes: 'h-px w-full bg-purple-500/20 my-2', []),
                div(classes: 'flex justify-between', [
                  span(classes: 'font-bold', [Component.text('Total Extension Fee')]),
                  span(classes: 'font-black text-xl text-purple-400', [
                    Component.text('₱ ${_totalExtensionFee.toStringAsFixed(2)}'),
                  ]),
                ]),
                div(classes: 'flex justify-between text-xs pt-1', [
                  span(classes: 'text-zinc-400', [Component.text('Your Wallet Balance:')]),
                  span(
                    classes: 'font-bold ${((component.appState.userProfile?.tyxBalance ?? 0) < _totalExtensionFee) ? "text-amber-400" : "text-green-400"}',
                    [Component.text('₱ ${(component.appState.userProfile?.tyxBalance ?? 0).toStringAsFixed(2)} TYXBIT')],
                  ),
                ]),
              ]),
            ],
          ]),

          // Footer
          div(classes: 'p-6 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"}', [
            if (_maxAllowedHours <= 0)
              button(
                classes:
                    'w-full py-3 rounded-xl font-bold text-zinc-400 bg-zinc-800 cursor-not-allowed flex items-center justify-center gap-2 border-0',
                attributes: {'disabled': 'disabled'},
                [Component.text('Extension Unavailable')],
              )
            else if ((component.appState.userProfile?.tyxBalance ?? 0) < _totalExtensionFee)
              button(
                classes:
                    'w-full py-3 rounded-xl font-bold text-white bg-amber-500 hover:bg-amber-600 transition-colors flex items-center justify-center gap-2 border-0 cursor-pointer',
                events: {'click': (_) => _extend()},
                [
                  lIcon('wallet', cls: 'w-5 h-5'),
                  Component.text(
                    'Top Up ₱ ${(_totalExtensionFee - (component.appState.userProfile?.tyxBalance ?? 0)).toStringAsFixed(2)} & Extend',
                  ),
                ],
              )
            else
              button(
                classes:
                    'w-full py-3 rounded-xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2 border-0 cursor-pointer',
                events: {'click': (e) => _extend()},
                [
                  if (_isProcessing) lIcon('loader', cls: 'w-5 h-5 animate-spin'),
                  Component.text(_isProcessing ? 'Processing Payment...' : 'Pay ₱ ${_totalExtensionFee.toStringAsFixed(2)} & Extend'),
                ],
              ),
          ]),
        ],
      ),
    ]);
  }
}
