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
  bool _isProcessing = false;
  String? _error;

  double get _penaltyPerHour {
    final r = component.appState.selectedRentalData;
    if (r == null) return 0;
    final val = r['latePenaltyRatePerHour'] ?? r['extensionRatePerHour'] ?? r['extensionPenaltyPerHour'];
    return (val as num?)?.toDouble() ?? 0;
  }

  double get _totalExtensionFee {
    return _penaltyPerHour * _extendHours;
  }

  void _extend() async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final r = component.appState.selectedRentalData;
      if (r == null) throw Exception('No rental selected.');
      final rentalId = r['id'] as String;

      // Fetch all approved booking requests for this vehicle
      final approvedRequests = await component.appState.firestore.getApprovedRequestsForVehicle(rentalId);

      final currentEndMs = r['endDate'] as int? ?? DateTime.now().millisecondsSinceEpoch;
      final extendMs = currentEndMs + (_extendHours * 3600 * 1000);

      // Check if the extended period overlaps with any other approved booking
      bool hasOverlap = false;
      for (final req in approvedRequests) {
        final reqId = req['id'] as String?;
        if (reqId != null && reqId == r['currentRequestId']) {
          // Skip the current active booking itself
          continue;
        }

        final reqStart = (req['startDate'] as num?)?.toInt() ?? 0;
        final reqEnd = (req['endDate'] as num?)?.toInt() ?? 0;

        // Overlap check: reqStart < extendMs && reqEnd > currentEndMs
        if (reqStart < extendMs && reqEnd > currentEndMs) {
          hasOverlap = true;
          break;
        }
      }

      final uid = component.appState.userProfile?.uid;
      if (uid == null || uid.isEmpty) {
        throw Exception('User is not authenticated.');
      }

      if (hasOverlap) {
        await component.appState.firestore.createExtensionRequest(
          rentalId: rentalId,
          renteeId: uid,
          extendHours: _extendHours,
          fee: _totalExtensionFee,
        );
        component.appState.showAppToast(
          'Extension Pending',
          'Overlap detected. Pending extension request submitted for host approval.',
        );
      } else {
        await component.appState.firestore.autoApproveExtension(
          rentalId: rentalId,
          renteeId: uid,
          extendHours: _extendHours,
          fee: _totalExtensionFee,
        );
        component.appState.showAppToast(
          'Extension Approved',
          'No overlap detected. Rental extended successfully.',
        );
      }

      // Close modal
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

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-md max-h-[90vh] overflow-y-auto rounded-3xl shadow-2xl relative flex flex-col ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"}',
          [
            // Header
            div(classes: 'sticky top-0 z-10 flex items-center justify-between p-6 border-b ${isDark ? "bg-zinc-900/90 border-zinc-800" : "bg-white/90 border-zinc-100"} backdrop-blur-md', [
              div([
                h2(classes: 'text-xl font-bold', [Component.text('Extend Rental')]),
                p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-500"}', [Component.text('$brand $model')]),
              ]),
              button(
                classes: 'p-2 rounded-full hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors',
                events: {'click': (e) => component.appState.setState(() {
                  component.appState.showExtendRentalModal = false;
                  component.appState.selectedRentalData = null;
                })},
                [lIcon('x', cls: 'w-6 h-6')],
              ),
            ]),

            // Body
            div(classes: 'p-6 flex-1 space-y-6', [
              if (_error != null)
                div(classes: 'p-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-500 text-sm font-medium', [
                  Component.text(_error!),
                ]),
                
              div(classes: 'flex flex-col items-center gap-4', [
                p(classes: 'text-center text-sm ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                  Component.text('Select the number of hours you wish to extend the rental by.')
                ]),
                
                div(classes: 'flex items-center gap-4', [
                  button(
                    classes: 'p-3 rounded-xl border ${isDark ? "border-zinc-700 bg-zinc-800" : "border-zinc-200 bg-zinc-100"} hover:opacity-80 transition-opacity',
                    events: {'click': (_) => setState(() => _extendHours = _extendHours > 1 ? _extendHours - 1 : 1)},
                    [lIcon('minus', cls: 'w-5 h-5')]
                  ),
                  span(classes: 'text-3xl font-black tabular-nums w-12 text-center', [Component.text('$_extendHours')]),
                  button(
                    classes: 'p-3 rounded-xl border ${isDark ? "border-zinc-700 bg-zinc-800" : "border-zinc-200 bg-zinc-100"} hover:opacity-80 transition-opacity',
                    events: {'click': (_) => setState(() => _extendHours++)},
                    [lIcon('plus', cls: 'w-5 h-5')]
                  ),
                ]),
                span(classes: 'text-sm font-bold text-purple-400', [Component.text('Hours')]),
              ]),
              
              div(classes: 'p-5 rounded-xl bg-purple-500/10 border border-purple-500/20 space-y-3', [
                  div(classes: 'flex justify-between text-sm', [
                    span(classes: isDark ? 'text-zinc-400' : 'text-zinc-600', [Component.text('Penalty Rate (Per Hour)')]),
                    span(classes: 'font-bold', [Component.text('₱ ${_penaltyPerHour.toStringAsFixed(2)}')]),
                  ]),
                  div(classes: 'h-px w-full bg-purple-500/20 my-2', []),
                  div(classes: 'flex justify-between', [
                    span(classes: 'font-bold', [Component.text('Extension Fee')]),
                    span(classes: 'font-black text-xl text-purple-400', [Component.text('₱ ${_totalExtensionFee.toStringAsFixed(2)}')]),
                  ]),
              ]),
            ]),

            // Footer
            div(classes: 'p-6 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"}', [
              button(
                classes: 'w-full py-3 rounded-xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
                events: {'click': (e) => _extend()},
                [
                  if (_isProcessing) lIcon('loader', cls: 'w-5 h-5 animate-spin'),
                  Component.text(_isProcessing ? 'Processing...' : 'Confirm Extension')
                ]
              ),
            ]),
          ]
        )
      ]
    );
  }
}
