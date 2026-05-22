import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';

class RentalTrackerMapComponent extends StatefulComponent {
  final TranyxAppState appState;
  const RentalTrackerMapComponent({required this.appState, super.key});

  @override
  State<RentalTrackerMapComponent> createState() => _RentalTrackerMapState();
}

class _RentalTrackerMapState extends State<RentalTrackerMapComponent> {
  bool _isUpdating = false;

  void _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      final r = component.appState.selectedRentalData;
      if (r == null) return;
      await component.appState.firestore.updateRentalStatus(r['id'], newStatus);
      // Wait for real-time listener to update the state...
    } catch (e) {
      print('Error updating rental status: $e');
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  @override
  Component build(BuildContext context) {
    if (!component.appState.showRentalTrackerMap || component.appState.selectedRentalData == null) {
      return div([]);
    }

    final isDark = component.appState.isDark;
    final r = component.appState.selectedRentalData!;
    final currentUid = component.appState.userProfile?.uid;
    final isHost = r['hostId'] == currentUid;
    final isRentee = r['renteeId'] == currentUid;
    
    final status = r['status'] as String? ?? 'Unknown';
    final model = r['model'] ?? 'Unknown';
    final brand = r['brand'] ?? 'Unknown';

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-3xl h-[85vh] rounded-3xl shadow-2xl relative flex flex-col overflow-hidden ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"}',
          [
            // Header
            div(classes: 'absolute top-0 left-0 right-0 z-20 flex items-center justify-between p-4 bg-gradient-to-b from-black/80 to-transparent', [
              div([
                h2(classes: 'text-xl font-bold text-white', [Component.text('Live Tracking')]),
                p(classes: 'text-sm text-zinc-300', [Component.text('$brand $model • $status')]),
              ]),
              button(
                classes: 'p-2 rounded-full bg-black/40 hover:bg-black/60 text-white transition-colors',
                events: {'click': (e) => component.appState.setState(() {
                  component.appState.showRentalTrackerMap = false;
                  component.appState.selectedRentalData = null;
                })},
                [lIcon('x', cls: 'w-6 h-6')],
              ),
            ]),

            // Mock Map Area (Google Maps placeholder)
            div(classes: 'flex-1 relative bg-zinc-800 w-full h-full', [
              img(
                src: 'https://images.unsplash.com/photo-1524661135-423995f22d0b?auto=format&fit=crop&q=80&w=2000',
                classes: 'w-full h-full object-cover opacity-50 grayscale',
                attributes: {'alt': 'Map background'},
              ),
              // Map Overlay Elements
              div(classes: 'absolute inset-0 flex items-center justify-center', [
                div(classes: 'relative', [
                  div(classes: 'absolute -inset-8 bg-purple-500/20 rounded-full animate-ping', []),
                  div(classes: 'w-12 h-12 bg-white rounded-full shadow-xl flex items-center justify-center border-4 border-purple-500 relative z-10', [
                    lIcon('car', cls: 'w-6 h-6 text-purple-500')
                  ]),
                ])
              ]),
            ]),

            // Action Card (Bottom)
            div(classes: 'relative z-20 -mt-6 p-6 rounded-t-3xl ${isDark ? "bg-zinc-900" : "bg-white"} shadow-[0_-10px_40px_rgba(0,0,0,0.1)]', [
              div(classes: 'flex items-center justify-between mb-6', [
                div([
                  p(classes: 'text-xs font-bold tracking-wider uppercase text-purple-500 mb-1', [Component.text('Status')]),
                  h3(classes: 'text-2xl font-black', [Component.text(status)]),
                ]),
                if (_isUpdating)
                  lIcon('loader', cls: 'w-6 h-6 animate-spin text-purple-500'),
              ]),
              
              // Progress Bar
              div(classes: 'w-full h-2 bg-zinc-800 rounded-full mb-6 overflow-hidden', [
                div(classes: 'h-full bg-purple-500 transition-all duration-1000', attributes: {
                  'style': 'width: ${_getProgressWidth(status)}%'
                }, [])
              ]),

              // Action Buttons based on Status
              div(classes: 'flex items-center gap-3', [
                if (isHost && status == 'Booked')
                  button(
                    classes: 'flex-1 py-3 rounded-xl font-bold text-white bg-purple-600 hover:bg-purple-700 transition-colors',
                    events: {'click': (_) => _updateStatus('On the way to Rentee')},
                    [Component.text('Start Delivery (On the way)')]
                  ),
                  
                if (isHost && status == 'On the way to Rentee')
                  button(
                    classes: 'flex-1 py-3 rounded-xl font-bold text-white bg-green-600 hover:bg-green-700 transition-colors',
                    events: {'click': (_) => _updateStatus('Ongoing')},
                    [Component.text('Handed Over (Ongoing)')]
                  ),
                  
                if (isRentee && status == 'Ongoing') ...[
                  button(
                    classes: 'flex-1 py-3 rounded-xl font-bold text-white bg-blue-600 hover:bg-blue-700 transition-colors',
                    events: {'click': (_) => _updateStatus('Returning')},
                    [Component.text('Start Return Trip')]
                  ),
                  button(
                    classes: 'py-3 px-4 rounded-xl font-bold text-purple-400 bg-purple-500/10 hover:bg-purple-500/20 transition-colors',
                    events: {'click': (_) => component.appState.setState(() => component.appState.showExtendRentalModal = true)},
                    [Component.text('Extend')]
                  ),
                ],
                
                if (isHost && status == 'Returning')
                  button(
                    classes: 'flex-1 py-3 rounded-xl font-bold text-white bg-green-600 hover:bg-green-700 transition-colors',
                    events: {'click': (_) => _updateStatus('Complete')},
                    [Component.text('Confirm Vehicle Returned')]
                  ),
                  
                if (status == 'Complete')
                  div(classes: 'flex-1 p-3 rounded-xl text-center bg-green-500/10 border border-green-500/20 text-green-500 font-bold', [
                    Component.text('Rental Completed')
                  ]),
              ]),
            ]),
          ]
        )
      ]
    );
  }

  int _getProgressWidth(String status) {
    switch (status) {
      case 'Available': return 0;
      case 'Booked': return 25;
      case 'On the way to Rentee': return 50;
      case 'Ongoing': return 75;
      case 'Returning': return 90;
      case 'Complete': return 100;
      default: return 0;
    }
  }
}
