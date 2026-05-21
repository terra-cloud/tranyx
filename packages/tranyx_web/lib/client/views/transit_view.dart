import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';

class TransitViewComponent extends StatefulComponent {
  final TranyxAppState state;
  const TransitViewComponent({required this.state, super.key});

  @override
  State<TransitViewComponent> createState() => _TransitViewComponentState();
}

class _TransitViewComponentState extends State<TransitViewComponent> {
  String _searchQuery = '';
  bool _nearMeOnly = false;
  double? _maxPrice;

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final isRent = s.transitMode == TransitMode.rent;

    return div(classes: 'space-y-8 animate-fade-up', [
      // Header
      div(classes: 'flex items-center justify-between', [
        div([
          h1(classes: 'text-3xl font-extrabold tracking-tight', [Component.text('Transit Hub')]),
          p(classes: 'text-sm mt-1 ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
            Component.text('Rent wheels or earn from your garage'),
          ]),
        ]),
        lIcon('car', cls: 'w-8 h-8 text-purple-400'),
      ]),

      // Mode toggle
      segmentedControl(
        options: const [('Rent a Vehicle', 'rent'), ('Host (My Garage)', 'host')],
        selected: isRent ? 'rent' : 'host',
        isDark: isDark,
        onChange: (v) => s.setState(() => s.transitMode = v == 'rent' ? TransitMode.rent : TransitMode.host),
      ),

      if (isRent) _rentView(isDark) else _hostView(isDark),
    ]);
  }

  Component _rentView(bool isDark) {
    final s = component.state;
    final currentUid = s.userProfile?.uid;
    final activeRentals = s.realtimeRentals.where((r) => r['renteeId'] == currentUid && r['status'] != 'Available' && r['status'] != 'Complete').toList();

    final availableRentals = s.realtimeRentals.where((r) {
      // 1. Must be status Available
      if (r['status'] != 'Available') return false;
      
      // 2. DO NOT include own listings
      if (r['hostId'] == currentUid) return false;
      
      // 3. Search query filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final brand = (r['brand'] ?? '').toString().toLowerCase();
        final model = (r['model'] ?? '').toString().toLowerCase();
        final type = (r['type'] ?? r['vehicleType'] ?? '').toString().toLowerCase();
        if (!brand.contains(query) && !model.contains(query) && !type.contains(query)) {
          return false;
        }
      }
      
      // 4. Distance / Near Me filter
      final double distKm = ((r['id']?.toString().hashCode ?? 0).abs() % 80) / 10.0 + 0.5;
      if (_nearMeOnly && distKm > 4.0) return false;
      
      // 5. Price range filter
      if (_maxPrice != null) {
        final priceVal = r['priceDaily'] ?? r['dailyRate'];
        final priceNum = double.tryParse(priceVal?.toString() ?? '') ?? 0.0;
        if (priceNum > _maxPrice!) return false;
      }
      
      return true;
    }).toList();

    return div(classes: 'space-y-6', [
      if (activeRentals.isNotEmpty)
        for (final active in activeRentals)
          // Active rental card
          div(
            classes: 'p-5 rounded-2xl border border-purple-500/30 bg-purple-500/10 cursor-pointer hover:bg-purple-500/20 transition-colors',
            events: {
              'click': (_) => s.setState(() {
                s.selectedRentalData = active;
                s.showRentalTrackerMap = true;
              })
            },
            [
              div(classes: 'flex items-center gap-3 mb-3', [
                div(classes: 'p-2 rounded-xl bg-purple-500/20', [lIcon('car', cls: 'w-5 h-5 text-purple-400')]),
                div([
                  p(classes: 'text-xs font-semibold text-purple-400 uppercase tracking-wider', [
                    Component.text('Active Rental • ${active['status']}'),
                  ]),
                  p(classes: 'font-bold', [Component.text('${active['brand']} ${active['model']} • ${active['plateNumber']}')]),
                ]),
              ]),
              div(classes: 'flex items-center justify-between', [
                p(classes: 'text-sm text-purple-300', [Component.text('Ongoing')]),
                button(
                  classes:
                      'px-4 py-2 rounded-xl text-xs font-bold bg-purple-500/20 text-purple-300 hover:bg-purple-500/30 transition-colors',
                  events: {'click': (e) {
                    e.stopPropagation();
                    s.setState(() {
                      s.selectedRentalData = active;
                      s.showExtendRentalModal = true;
                    });
                  }},
                  [Component.text('Extend')],
                ),
              ]),
            ],
          ),

      if (s.renterPendingRequests.isNotEmpty) ...[
        h3(classes: 'text-sm font-bold text-zinc-400 uppercase tracking-wider mb-3', [Component.text('Pending Requests (${s.renterPendingRequests.length})')]),
        for (final req in s.renterPendingRequests)
          div(
            classes: 'p-5 rounded-2xl border ${isDark ? "border-zinc-800 bg-zinc-800/15" : "border-zinc-200 bg-zinc-50"} mb-4 flex items-center justify-between',
            [
              div(classes: 'flex items-center gap-3', [
                div(classes: 'p-2 rounded-xl bg-purple-500/20', [lIcon('clock', cls: 'w-5 h-5 text-purple-400')]),
                div([
                  p(classes: 'text-xs font-semibold text-purple-400 uppercase tracking-wider', [
                    Component.text('Awaiting Host Approval'),
                  ]),
                  p(classes: 'font-bold', [Component.text('${req['brand']} ${req['model']} • ${req['year']}')]),
                  p(classes: 'text-xs text-zinc-500 capitalize', [Component.text('${req['multiplier']} ${req['durationType']}')]),
                ]),
              ]),
              div(classes: 'text-right', [
                p(classes: 'font-black text-purple-400', [Component.text('₱${req["totalCost"]}')]),
                span(classes: 'px-2 py-0.5 rounded text-[10px] bg-yellow-500/20 text-yellow-400 font-bold', [Component.text('PENDING')]),
              ]),
            ],
          ),
      ],

      // Search and Filter Bar
      div(classes: 'space-y-3', [
        div(
          classes:
              'flex items-center gap-3 p-4 rounded-2xl border ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200 shadow-sm"}',
          [
            lIcon('search', cls: 'w-5 h-5 ${isDark ? "text-zinc-600" : "text-zinc-400"}'),
            input(
              classes: 'bg-transparent border-none outline-none flex-1 text-sm',
              type: InputType.search,
              attributes: {
                'placeholder': 'Search vehicles, location...',
                'id': 'transit-search-input',
                'name': 'search',
                'value': _searchQuery,
              },
              events: {
                'input': (e) {
                  setState(() {
                    _searchQuery = (e.target as web.HTMLInputElement).value;
                  });
                }
              },
            ),
          ],
        ),
        
        // Filters row
        div(classes: 'flex flex-wrap items-center gap-3', [
          button(
            classes: 'px-3 py-1.5 rounded-xl text-xs font-semibold border transition-all ${
              _nearMeOnly 
                ? "bg-purple-500/20 border-purple-500 text-purple-400 font-bold" 
                : (isDark ? "border-zinc-800 hover:border-zinc-700 bg-zinc-800/30 text-zinc-400" : "border-zinc-200 hover:border-zinc-300 bg-zinc-50 text-zinc-600")
            }',
            events: {
              'click': (_) {
                setState(() {
                  _nearMeOnly = !_nearMeOnly;
                });
              }
            },
            [
              span(classes: 'flex items-center gap-1 pointer-events-none', [
                lIcon('map-pin', cls: 'w-3.5 h-3.5'),
                Component.text('Near Me (< 4km)')
              ])
            ]
          ),

          div(classes: 'flex items-center gap-2 ml-auto', [
            span(classes: 'text-xs font-semibold ${isDark ? "text-zinc-400" : "text-zinc-500"}', [Component.text('Max Price:')]),
            select(
              classes: 'text-xs p-1.5 rounded-xl border ${isDark ? "bg-zinc-800 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
              events: {
                'change': (e) {
                  final val = (e.target as web.HTMLSelectElement).value;
                  setState(() {
                    _maxPrice = val == 'any' ? null : double.tryParse(val);
                  });
                }
              },
              [
                option(attributes: {'value': 'any'}, [Component.text('Any Price')]),
                option(attributes: {'value': '1500'}, [Component.text('Under ₱1,500/day')]),
                option(attributes: {'value': '3000'}, [Component.text('Under ₱3,000/day')]),
                option(attributes: {'value': '5000'}, [Component.text('Under ₱5,000/day')]),
                option(attributes: {'value': '10000'}, [Component.text('Under ₱10,000/day')]),
              ]
            ),
          ]),
        ]),
      ]),

      // Vehicle cards
      if (availableRentals.isEmpty)
        div(classes: 'p-10 rounded-2xl border border-dashed ${isDark ? "border-zinc-800 text-zinc-500 bg-zinc-900/10" : "border-zinc-200 text-zinc-400 bg-zinc-50/50"} text-center font-medium', [
          Component.text('No matching vehicles available for rent.')
        ])
      else
        div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4', [
          for (final v in availableRentals)
            _vehicleCard(v, isDark),
        ]),
    ]);
  }

  Component _hostView(bool isDark) {
    final s = component.state;
    final currentUid = s.userProfile?.uid;
    final myRentals = s.realtimeRentals.where((r) => r['hostId'] == currentUid).toList();
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    
    return div(classes: 'space-y-6', [
      if (myRentals.isEmpty)
        div(classes: 'p-10 rounded-2xl border border-dashed text-center $cardCls', [
          div(classes: 'flex justify-center mb-5', [
            div(classes: 'p-5 rounded-2xl ${isDark ? "bg-zinc-800" : "bg-zinc-100"}', [
              lIcon('car', cls: 'w-10 h-10 ${isDark ? "text-zinc-600" : "text-zinc-400"}'),
            ]),
          ]),
          h2(classes: 'text-xl font-bold mb-2', [Component.text('Turn your vehicle into earnings')]),
          p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-500"} max-w-xs mx-auto mb-6', [
            Component.text('List your car, motorcycle, or truck and earn while it\'s idle.'),
          ]),
          button(
            classes:
                'px-6 py-3 rounded-xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity inline-flex items-center gap-2',
            events: {'click': (_) => s.setState(() => s.showListVehicleModal = true)},
            [lIcon('plus', cls: 'w-4 h-4'), Component.text(' List a Vehicle')],
          ),
        ])
      else ...[
        div(classes: 'flex items-center justify-between', [
          h2(classes: 'text-xl font-bold', [Component.text('My Garage')]),
          button(
            classes: 'px-4 py-2 rounded-xl text-sm font-semibold text-white logo-gradient hover:opacity-90 transition-opacity',
            events: {'click': (_) => s.setState(() => s.showListVehicleModal = true)},
            [Component.text('+ List Another')],
          )
        ]),
        div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4', [
          for (final v in myRentals)
            _vehicleCard(
              v,
              isDark,
              isHostView: true,
            ),
        ]),
      ],
    ]);
  }

  Component _vehicleCard(Map<String, dynamic> rentalData, bool isDark, {bool isHostView = false}) {
    final s = component.state;
    final model = rentalData['model'] ?? 'Unknown';
    final typeVal = rentalData['type'] ?? rentalData['vehicleType'];
    String type = typeVal?.toString().split('.').last ?? 'Unknown';
    if (type.toLowerCase() == 'null') type = 'Unknown';
    
    final priceVal = rentalData['priceDaily'] ?? rentalData['dailyRate'];
    final priceStr = (priceVal != null && priceVal.toString().toLowerCase() != 'null') ? priceVal.toString() : '0';
    final price = '₱ $priceStr/day';
    
    // Stable distance calculation based on the hash of the document ID
    final double distKm = ((rentalData['id']?.toString().hashCode ?? 0).abs() % 80) / 10.0 + 0.5;
    final distance = '${distKm.toStringAsFixed(1)} km';
    
    final cardCls = isDark
        ? 'bg-zinc-900 border-zinc-800 hover:border-purple-500/40'
        : 'bg-white border-zinc-200 shadow-sm hover:shadow-md';
    return div(classes: 'p-5 rounded-2xl border transition-all card-hover $cardCls', [
      div(classes: 'flex items-start justify-between mb-4', [
        div([
          p(classes: 'font-bold text-lg', [Component.text(model)]),
          p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-500"} capitalize', [Component.text(type)]),
        ]),
        span(classes: 'px-2 py-1 rounded-lg text-xs font-bold bg-purple-500/20 text-purple-400', [
          Component.text('AVAILABLE'),
        ]),
      ]),
      // Placeholder or actual front image area
      () {
        final photoUrl = rentalData['frontPhotoUrl'] ?? rentalData['frontPhoto'] ?? rentalData['photoUrl'] ?? rentalData['interiorPhotoUrl'] ?? rentalData['backPhotoUrl'];
        final hasPhoto = photoUrl != null && photoUrl.toString().isNotEmpty && photoUrl.toString() != 'null';
        return div(
          classes:
              'w-full h-28 rounded-xl mb-4 ${isDark ? "bg-zinc-800" : "bg-zinc-100"} flex items-center justify-center overflow-hidden relative',
          [
            if (hasPhoto)
              img(
                src: photoUrl.toString(),
                classes: 'w-full h-full object-cover',
                attributes: {'alt': model},
              )
            else
              lIcon('car', cls: 'w-10 h-10 ${isDark ? "text-zinc-600" : "text-zinc-300"}'),
          ],
        );
      }(),
      div(classes: 'flex items-center justify-between', [
        div([
          p(classes: 'font-bold text-lg text-purple-400', [Component.text(price)]),
          div(classes: 'flex items-center gap-1 text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
            lIcon('map-pin', cls: 'w-3 h-3'),
            Component.text(' $distance'),
          ]),
        ]),
        if (isHostView || (rentalData['hostId'] != null && s.userProfile?.uid != null && rentalData['hostId'] == s.userProfile?.uid))
          div(classes: 'flex gap-2', [
            button(
              classes: 'p-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-300 hover:bg-zinc-50"} transition-colors',
              attributes: {'title': 'Public Q&A'},
              events: {'click': (_) => s.setState(() { s.selectedRentalData = rentalData; s.showVehicleQaModal = true; })},
              [lIcon('message-circle-question', cls: 'w-4 h-4')]
            ),
            button(
              classes: 'px-4 py-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-300 hover:bg-zinc-50"} transition-colors',
              events: {'click': (_) {
                s.setState(() {
                  s.selectedRentalData = rentalData;
                  s.showManageVehicleModal = true;
                });
              }},
              [Component.text(rentalData['status'] != 'Available' && rentalData['status'] != 'Completed' && rentalData['status'] != 'Complete' ? 'Track' : 'Manage')]
            ),
          ])
        else
          div(classes: 'flex items-center gap-2', [
            button(
              classes: 'p-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800 text-purple-400" : "border-zinc-300 hover:bg-zinc-50 text-purple-600"} transition-colors',
              attributes: {'title': 'Public Q&A'},
              events: {'click': (_) => s.setState(() { s.selectedRentalData = rentalData; s.showVehicleQaModal = true; })},
              [lIcon('message-circle-question', cls: 'w-4 h-4')]
            ),
            if (rentalData['hostId'] != null && rentalData['hostId'] != s.userProfile?.uid)
              button(
                classes: 'p-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800 text-blue-400" : "border-zinc-300 hover:bg-zinc-50 text-blue-600"} transition-colors',
                attributes: {'title': 'Chat with Host'},
                events: {'click': (_) {
                  final chatId = 'rental_${rentalData['id']}_${s.userProfile?.uid}';
                  s.openChat(chatId);
                }},
                [lIcon('message-square', cls: 'w-4 h-4')]
              ),
            button(
              classes: 'px-4 py-2.5 rounded-xl text-sm font-semibold text-white logo-gradient hover:opacity-90 transition-opacity',
              events: {'click': (_) => s.setState(() {
                s.selectedRentalData = rentalData;
                s.showBookVehicleModal = true;
              })},
              [Component.text('Book Now')]
            ),
          ]),
      ]),
    ]);
  }
}
