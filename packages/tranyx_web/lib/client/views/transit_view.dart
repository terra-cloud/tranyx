import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
import '../../services/web_interop.dart';
import '../utils/geo_helper.dart';

class TransitViewComponent extends StatefulComponent {
  final TranyxAppState state;
  const TransitViewComponent({required this.state, super.key});

  @override
  State<TransitViewComponent> createState() => _TransitViewComponentState();
}

class _TransitViewComponentState extends State<TransitViewComponent> {
  // Common filters
  String _searchQuery = '';
  double? _maxPrice;
  String _selectedDurationFilter = 'any'; // 'any', 'daily', 'weekly', 'monthly', 'yearly'

  // Property specific filters
  PropertyCategory? _selectedCategory;
  PropertyType? _selectedType;

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final isVehicles = s.activeRentalCategory == RentalCategory.vehicles;

    return div(classes: 'space-y-8 animate-fade-up', [
      // Top Header
      div(classes: 'flex items-center justify-between', [
        div([
          h1(classes: 'text-3xl font-extrabold tracking-tight bg-gradient-to-r from-indigo-400 via-purple-400 to-pink-400 bg-clip-text text-transparent', [
            Component.text(isVehicles ? 'Vehicles & Transit Marketplace' : 'Properties & Spaces Marketplace'),
          ]),
          p(classes: 'text-sm mt-2 max-w-xl leading-relaxed ${isDark ? "text-zinc-400" : "text-zinc-650"}', [
            Component.text(
              isVehicles
                  ? 'Discover verified local rides or capitalize on your idle garage. Seamless, secure, and peer-to-peer.'
                  : 'Discover verified residential and commercial spaces or lease your properties in secure escrow.',
            ),
          ]),
        ]),
        div(classes: 'p-3.5 rounded-2xl bg-indigo-500/10 border border-indigo-500/20', [
          lIcon(isVehicles ? 'car' : 'home', cls: 'w-7 h-7 text-indigo-400'),
        ]),
      ]),

      // Segmented Switcher for Category: Vehicles vs Properties
      segmentedControl(
        options: const [
          ('🚗 Vehicles', 'vehicles'),
          ('🏢 Real Estate', 'properties'),
        ],
        selected: isVehicles ? 'vehicles' : 'properties',
        isDark: isDark,
        onChange: (v) {
          s.setState(() {
            s.activeRentalCategory = v == 'vehicles' ? RentalCategory.vehicles : RentalCategory.properties;
            // Clear filters when switching
            _searchQuery = '';
            _maxPrice = null;
            _selectedCategory = null;
            _selectedType = null;
          });
        },
      ),

      // Segmented Switcher for Mode: Rent vs Host
      segmentedControl(
        options: [
          (isVehicles ? 'Rent a Vehicle' : 'Rent a Space', 'rent'),
          (isVehicles ? 'Host (My Garage)' : 'Host (My Properties)', 'host'),
        ],
        selected: s.transitMode == TransitMode.rent ? 'rent' : 'host',
        isDark: isDark,
        onChange: (v) => s.setState(() => s.transitMode = v == 'rent' ? TransitMode.rent : TransitMode.host),
      ),

      if (s.transitMode == TransitMode.rent) _rentView(isVehicles, isDark) else _hostView(isVehicles, isDark),
    ]);
  }

  Component _rentView(bool isVehicles, bool isDark) {
    final s = component.state;
    final currentUid = s.userProfile?.uid;

    if (isVehicles) {
      // 🚗 VEHICLES RENT MODE
      final activeRentals = s.realtimeRentals
          .where(
            (r) =>
                r['renteeId'] == currentUid &&
                r['status'] != 'Available' &&
                r['status'] != 'Completed' &&
                r['status'] != 'Complete',
          )
          .toList();

      final availableRentals = s.realtimeRentals.where((r) {
        if (r['status'] != 'Available') return false;
        if (r['hostId'] == currentUid) return false;

        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          final brand = (r['brand'] ?? '').toString().toLowerCase();
          final model = (r['model'] ?? '').toString().toLowerCase();
          final type = (r['type'] ?? r['vehicleType'] ?? '').toString().toLowerCase();
          if (!brand.contains(query) && !model.contains(query) && !type.contains(query)) {
            return false;
          }
        }

        final double pickupLat = (r['pickupLat'] as num?)?.toDouble() ?? 14.5995;
        final double pickupLng = (r['pickupLng'] as num?)?.toDouble() ?? 120.9842;
        final double distKm = calculateDistance(s.userLatitude, s.userLongitude, pickupLat, pickupLng);
        if (s.geofenceRadius < 999.0 && distKm > s.geofenceRadius) return false;

        if (_maxPrice != null) {
          final priceVal = r['priceDaily'] ?? r['dailyRate'];
          final priceNum = double.tryParse(priceVal?.toString() ?? '') ?? 0.0;
          if (priceNum > _maxPrice!) return false;
        }
        return true;
      }).toList();

      // Sort by distance (closest first)
      availableRentals.sort((a, b) {
        final aLat = (a['pickupLat'] as num?)?.toDouble() ?? 14.5995;
        final aLng = (a['pickupLng'] as num?)?.toDouble() ?? 120.9842;
        final aDist = calculateDistance(s.userLatitude, s.userLongitude, aLat, aLng);

        final bLat = (b['pickupLat'] as num?)?.toDouble() ?? 14.5995;
        final bLng = (b['pickupLng'] as num?)?.toDouble() ?? 120.9842;
        final bDist = calculateDistance(s.userLatitude, s.userLongitude, bLat, bLng);

        return aDist.compareTo(bDist);
      });

      return div(classes: 'space-y-6', [
        // Active vehicle rentals list
        if (activeRentals.isNotEmpty) ...[
          h3(classes: 'text-sm font-bold text-zinc-400 uppercase tracking-wider mb-2', [
            Component.text('Active Rentals & Schedules'),
          ]),
          for (final active in activeRentals) _activeVehicleCard(active, isDark),
        ],

        // Renter pending requests
        if (s.renterPendingRequests.isNotEmpty) ...[
          h3(classes: 'text-sm font-bold text-zinc-400 uppercase tracking-wider mb-2', [
            Component.text('Pending Requests (${s.renterPendingRequests.length})'),
          ]),
          for (final req in s.renterPendingRequests) _pendingRequestCard(req, false, isDark),
        ],

        // Search & Filter header
        _buildVehicleFilters(isDark, s),

        // Available listings grid
        if (availableRentals.isEmpty)
          div(
            classes:
                'p-10 rounded-2xl border border-dashed ${isDark ? "border-zinc-800 text-zinc-500 bg-zinc-900/10" : "border-zinc-200 text-zinc-400 bg-zinc-50/50"} text-center font-medium',
            [Component.text('No matching vehicles available for rent.')],
          )
        else
          div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4', [
            for (final v in availableRentals) _vehicleCard(v, isDark, isHostView: false),
          ]),
      ]);
    } else {
      // 🏢 PROPERTIES RENT MODE
      final activeLeases = s.realtimeProperties
          .where((p) => p.renteeId == currentUid && p.status != 'Available' && p.status != 'Completed')
          .toList();

      final availableProperties = s.realtimeProperties.where((p) {
        if (p.status != 'Available') return false;
        if (p.hostId == currentUid) return false;

        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          if (!p.title.toLowerCase().contains(query) &&
              !p.description.toLowerCase().contains(query) &&
              !p.address.toLowerCase().contains(query)) {
            return false;
          }
        }

        if (_selectedCategory != null && p.category != _selectedCategory) return false;
        if (_selectedType != null && p.type != _selectedType) return false;

        final double distKm = calculateDistance(s.userLatitude, s.userLongitude, p.latitude, p.longitude);
        if (s.geofenceRadius < 999.0 && distKm > s.geofenceRadius) return false;

        // Apply Rent Option / Duration filter
        if (_selectedDurationFilter == 'daily' && p.priceDaily <= 0 && p.priceMonthly <= 0) return false;
        if (_selectedDurationFilter == 'weekly' && p.priceWeekly <= 0 && p.priceMonthly <= 0) return false;
        if (_selectedDurationFilter == 'monthly' && p.priceMonthly <= 0 && p.priceDaily <= 0) return false;
        if (_selectedDurationFilter == 'yearly' && p.priceMonthly <= 0) return false;

        // Apply Custom Max Price filter
        if (_maxPrice != null) {
          double? priceToCheck;
          if (_selectedDurationFilter == 'daily') {
            priceToCheck = p.priceDaily > 0 ? p.priceDaily : p.priceMonthly;
          } else if (_selectedDurationFilter == 'weekly') {
            priceToCheck = p.priceWeekly > 0 ? p.priceWeekly : p.priceMonthly;
          } else if (_selectedDurationFilter == 'yearly') {
            priceToCheck = p.priceMonthly > 0 ? p.priceMonthly * 12 : null;
          } else if (_selectedDurationFilter == 'monthly') {
            priceToCheck = p.priceMonthly > 0 ? p.priceMonthly : p.priceDaily;
          } else {
            // 'any' filter: check if any of the offered rates is under maxPrice
            bool matchesAny = false;
            if (p.priceDaily > 0 && p.priceDaily <= _maxPrice!) matchesAny = true;
            if (p.priceWeekly > 0 && p.priceWeekly <= _maxPrice!) matchesAny = true;
            if (p.priceMonthly > 0 && p.priceMonthly <= _maxPrice!) matchesAny = true;
            if (!matchesAny) return false;
          }

          if (priceToCheck != null && priceToCheck > _maxPrice!) return false;
        }

        return true;
      }).toList();

      // Sort by distance (closest first)
      availableProperties.sort((a, b) {
        final aDist = calculateDistance(s.userLatitude, s.userLongitude, a.latitude, a.longitude);
        final bDist = calculateDistance(s.userLatitude, s.userLongitude, b.latitude, b.longitude);
        return aDist.compareTo(bDist);
      });

      return div(classes: 'space-y-6', [
        // Active Leases list
        if (activeLeases.isNotEmpty) ...[
          h3(classes: 'text-sm font-bold text-zinc-400 uppercase tracking-wider mb-2', [
            Component.text('Active Leases'),
          ]),
          for (final active in activeLeases) _activePropertyCard(active, isDark),
        ],

        // Renter pending property requests
        if (s.propertyRenterPendingRequests.isNotEmpty) ...[
          h3(classes: 'text-sm font-bold text-zinc-400 uppercase tracking-wider mb-2', [
            Component.text('Pending Requests (${s.propertyRenterPendingRequests.length})'),
          ]),
          for (final req in s.propertyRenterPendingRequests) _pendingRequestCard(req, true, isDark),
        ],

        // Filters bar
        _buildPropertyFilters(isDark, s),

        // Available property listings grid
        if (availableProperties.isEmpty)
          div(
            classes:
                'p-10 rounded-2xl border border-dashed ${isDark ? "border-zinc-800 text-zinc-500 bg-zinc-900/10" : "border-zinc-200 text-zinc-400 bg-zinc-50/50"} text-center font-medium',
            [Component.text('No matching real estate listings found.')],
          )
        else
          div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4', [
            for (final prop in availableProperties) _propertyCard(prop, isDark, isHostView: false),
          ]),
      ]);
    }
  }

  Component _hostView(bool isVehicles, bool isDark) {
    final s = component.state;
    final currentUid = s.userProfile?.uid;
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    if (isVehicles) {
      // 🚗 VEHICLES HOST MODE
      final myRentals = s.realtimeRentals.where((r) => r['hostId'] == currentUid).toList();

      return div(classes: 'space-y-6', [
        if (myRentals.isEmpty)
          div(classes: 'p-10 rounded-2xl border border-dashed text-center $cardCls', [
            div(classes: 'flex justify-center mb-5', [
              div(classes: 'p-5 rounded-2xl ${isDark ? "bg-zinc-850" : "bg-zinc-100"}', [
                lIcon('car', cls: 'w-10 h-10 ${isDark ? "text-zinc-600" : "text-zinc-450"}'),
              ]),
            ]),
            h2(classes: 'text-xl font-bold mb-2', [Component.text('Turn your vehicle into earnings')]),
            p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-500"} max-w-xs mx-auto mb-6', [
              Component.text('List your car, motorcycle, or truck and earn while it\'s idle.'),
            ]),
            button(
              classes:
                  'px-6 py-3 rounded-xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity inline-flex items-center gap-2 border-0 cursor-pointer',
              events: {'click': (_) => s.setState(() => s.showListVehicleModal = true)},
              [lIcon('plus', cls: 'w-4 h-4'), Component.text(' List a Vehicle')],
            ),
          ])
        else ...[
          div(classes: 'flex items-center justify-between', [
            h2(classes: 'text-xl font-bold', [Component.text('My Garage')]),
            button(
              classes:
                  'px-4 py-2 rounded-xl text-sm font-semibold text-white logo-gradient hover:opacity-90 transition-opacity border-0 cursor-pointer',
              events: {'click': (_) => s.setState(() => s.showListVehicleModal = true)},
              [Component.text('+ List Another')],
            ),
          ]),
          div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4', [
            for (final v in myRentals) _vehicleCard(v, isDark, isHostView: true),
          ]),
        ],
      ]);
    } else {
      // 🏢 PROPERTIES HOST MODE
      final myProperties = s.realtimeProperties.where((p) => p.hostId == currentUid).toList();

      return div(classes: 'space-y-6', [
        if (myProperties.isEmpty)
          div(classes: 'p-10 rounded-2xl border border-dashed text-center $cardCls', [
            div(classes: 'flex justify-center mb-5', [
              div(classes: 'p-5 rounded-2xl ${isDark ? "bg-zinc-850" : "bg-zinc-100"}', [
                lIcon('home', cls: 'w-10 h-10 ${isDark ? "text-zinc-600" : "text-zinc-450"}'),
              ]),
            ]),
            h2(classes: 'text-xl font-bold mb-2', [Component.text('List your property for rent')]),
            p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-550"} max-w-xs mx-auto mb-6', [
              Component.text('Rent out your apartment, room, bedspace, or commercial lot securely.'),
            ]),
            button(
              classes:
                  'px-6 py-3 rounded-xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity inline-flex items-center gap-2 border-0 cursor-pointer',
              events: {'click': (_) => s.setState(() => s.showListPropertyModal = true)},
              [lIcon('plus', cls: 'w-4 h-4'), Component.text(' List a Property')],
            ),
          ])
        else ...[
          div(classes: 'flex items-center justify-between', [
            h2(classes: 'text-xl font-bold', [Component.text('My Properties')]),
            button(
              classes:
                  'px-4 py-2 rounded-xl text-sm font-semibold text-white logo-gradient hover:opacity-90 transition-opacity border-0 cursor-pointer',
              events: {'click': (_) => s.setState(() => s.showListPropertyModal = true)},
              [Component.text('+ List Another')],
            ),
          ]),
          div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4', [
            for (final p in myProperties) _propertyCard(p, isDark, isHostView: true),
          ]),
        ],
      ]);
    }
  }

  // ── Filter Builder Helpers ──────────────────────────────────────────────────

  Component _buildVehicleFilters(bool isDark, TranyxAppState s) {
    return div(classes: 'space-y-3', [
      div(
        classes:
            'flex items-center gap-3 p-4 rounded-2xl border ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200 shadow-sm"}',
        [
          lIcon('search', cls: 'w-5 h-5 ${isDark ? "text-zinc-600" : "text-zinc-400"}'),
          input(
            classes: 'bg-transparent border-none outline-none flex-1 text-sm text-white',
            type: InputType.search,
            attributes: {
              'placeholder': 'Search vehicles, location...',
              'value': _searchQuery,
            },
            events: {
              'input': (e) => setState(() => _searchQuery = getInputValue(e.target)),
            },
          ),
        ],
      ),
      div(classes: 'flex flex-wrap items-center gap-3', [
        div(classes: 'flex items-center gap-2 text-xs', [
          span(classes: 'font-semibold ${isDark ? "text-zinc-500" : "text-zinc-400"} flex items-center gap-1', [
            lIcon('map-pin', cls: 'w-3.5 h-3.5 text-purple-400'),
            Component.text('Distance:'),
          ]),
          select(
            classes:
                'text-xs p-1.5 rounded-xl border ${isDark ? "bg-zinc-800 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
            events: {
              'change': (e) {
                final val = getInputValue(e.target);
                s.setState(() => s.geofenceRadius = double.parse(val));
              },
            },
            [
              option(value: '5.0', selected: s.geofenceRadius == 5.0, [Component.text('Within 5 km')]),
              option(value: '15.0', selected: s.geofenceRadius == 15.0, [Component.text('Within 15 km')]),
              option(value: '30.0', selected: s.geofenceRadius == 30.0, [Component.text('Within 30 km')]),
              option(value: '50.0', selected: s.geofenceRadius == 50.0, [Component.text('Within 50 km')]),
              option(value: '100.0', selected: s.geofenceRadius == 100.0, [Component.text('Within 100 km')]),
              option(value: '9999.0', selected: s.geofenceRadius >= 999.0, [Component.text('Any Distance')]),
            ],
          ),
        ]),
        div(classes: 'flex items-center gap-2 ml-auto', [
          span(classes: 'text-xs font-semibold ${isDark ? "text-zinc-400" : "text-zinc-550"}', [
            Component.text('Max Price:'),
          ]),
          select(
            classes:
                'text-xs p-1.5 rounded-xl border ${isDark ? "bg-zinc-800 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
            events: {
              'change': (e) {
                final val = getInputValue(e.target);
                setState(() => _maxPrice = val == 'any' ? null : double.tryParse(val));
              },
            },
            [
              option(value: 'any', [Component.text('Any Price')]),
              option(value: '1500', [Component.text('Under ₱1,500/day')]),
              option(value: '3000', [Component.text('Under ₱3,000/day')]),
              option(value: '5000', [Component.text('Under ₱5,000/day')]),
              option(value: '10000', [Component.text('Under ₱10,000/day')]),
            ],
          ),
        ]),
      ]),
    ]);
  }

  Component _buildPropertyFilters(bool isDark, TranyxAppState s) {
    return div(classes: 'space-y-3', [
      div(
        classes:
            'flex items-center gap-3 p-4 rounded-2xl border ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200 shadow-sm"}',
        [
          lIcon('search', cls: 'w-5 h-5 ${isDark ? "text-zinc-600" : "text-zinc-400"}'),
          input(
            classes: 'bg-transparent border-none outline-none flex-1 text-sm text-white',
            type: InputType.search,
            attributes: {
              'placeholder': 'Search property title, address, description...',
              'value': _searchQuery,
            },
            events: {
              'input': (e) => setState(() => _searchQuery = getInputValue(e.target)),
            },
          ),
        ],
      ),
      div(classes: 'flex flex-wrap items-center gap-3', [
        div(classes: 'flex items-center gap-2 text-xs', [
          span(classes: 'font-semibold ${isDark ? "text-zinc-555" : "text-zinc-500"} flex items-center gap-1', [
            lIcon('map-pin', cls: 'w-3.5 h-3.5 text-purple-400'),
            Component.text('Distance:'),
          ]),
          select(
            classes:
                'text-xs p-1.5 rounded-xl border ${isDark ? "bg-zinc-800 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
            events: {
              'change': (e) {
                final val = getInputValue(e.target);
                s.setState(() => s.geofenceRadius = double.parse(val));
              },
            },
            [
              option(value: '5.0', selected: s.geofenceRadius == 5.0, [Component.text('Within 5 km')]),
              option(value: '15.0', selected: s.geofenceRadius == 15.0, [Component.text('Within 15 km')]),
              option(value: '30.0', selected: s.geofenceRadius == 30.0, [Component.text('Within 30 km')]),
              option(value: '50.0', selected: s.geofenceRadius == 50.0, [Component.text('Within 50 km')]),
              option(value: '100.0', selected: s.geofenceRadius == 100.0, [Component.text('Within 100 km')]),
              option(value: '9999.0', selected: s.geofenceRadius >= 999.0, [Component.text('Any Distance')]),
            ],
          ),
        ]),

        // Category filter
        select(
          classes:
              'text-xs p-1.5 rounded-xl border ${isDark ? "bg-zinc-800 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
          events: {
            'change': (e) {
              final val = getInputValue(e.target);
              setState(() {
                _selectedCategory = val == 'any' ? null : PropertyCategory.values.firstWhere((c) => c.name == val);
                // Clear type filter if not compatible with new category
                if (_selectedCategory != null &&
                    _selectedType != null &&
                    _selectedType!.category != _selectedCategory) {
                  _selectedType = null;
                }
              });
            },
          },
          [
            option(value: 'any', [Component.text('All Categories')]),
            for (final c in PropertyCategory.values)
              option(value: c.name, selected: _selectedCategory == c, [Component.text(c.label)]),
          ],
        ),

        // Type filter
        select(
          classes:
              'text-xs p-1.5 rounded-xl border ${isDark ? "bg-zinc-800 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
          events: {
            'change': (e) {
              final val = getInputValue(e.target);
              setState(() {
                _selectedType = val == 'any' ? null : PropertyType.values.firstWhere((t) => t.name == val);
              });
            },
          },
          [
            option(value: 'any', [Component.text('All Types')]),
            for (final t in PropertyType.values.where(
              (t) => _selectedCategory == null || t.category == _selectedCategory,
            ))
              option(value: t.name, selected: _selectedType == t, [Component.text(t.label)]),
          ],
        ),

        // Rate option filter (monthly, weekly, daily, yearly)
        select(
          classes:
              'text-xs p-1.5 rounded-xl border ${isDark ? "bg-zinc-800 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
          events: {
            'change': (e) {
              final val = getInputValue(e.target);
              setState(() {
                _selectedDurationFilter = val;
              });
            },
          },
          [
            option(value: 'any', selected: _selectedDurationFilter == 'any', [Component.text('Any Rent Option')]),
            option(value: 'daily', selected: _selectedDurationFilter == 'daily', [Component.text('Offers Daily')]),
            option(value: 'weekly', selected: _selectedDurationFilter == 'weekly', [Component.text('Offers Weekly')]),
            option(value: 'monthly', selected: _selectedDurationFilter == 'monthly', [
              Component.text('Offers Monthly'),
            ]),
            option(value: 'yearly', selected: _selectedDurationFilter == 'yearly', [Component.text('Offers Yearly')]),
          ],
        ),

        div(classes: 'flex items-center gap-2 ml-auto', [
          span(classes: 'text-xs font-semibold ${isDark ? "text-zinc-400" : "text-zinc-550"}', [
            Component.text('Max Price:'),
          ]),
          input(
            classes:
                'text-xs p-1.5 w-24 rounded-xl border ${isDark ? "bg-zinc-800 border-zinc-700 text-white placeholder-zinc-550" : "bg-white border-zinc-300 text-zinc-800 placeholder-zinc-400"} outline-none focus:border-purple-500 transition-colors',
            type: InputType.number,
            attributes: {
              'placeholder': 'Any Price',
              'value': _maxPrice?.toString() ?? '',
            },
            events: {
              'input': (e) {
                final val = getInputValue(e.target);
                setState(() {
                  _maxPrice = val.trim().isEmpty ? null : double.tryParse(val);
                });
              },
            },
          ),
        ]),
      ]),
    ]);
  }

  // ── Card Rendering Components ──────────────────────────────────────────────

  Component _activeVehicleCard(Map<String, dynamic> active, bool isDark) {
    final s = component.state;
    final status = active['status'] as String? ?? 'Booked';

    return div(
      classes:
          'p-5 rounded-2xl border border-purple-500/30 bg-purple-500/10 cursor-pointer hover:bg-purple-500/20 transition-colors mb-4',
      events: {
        'click': (_) => s.setState(() {
          s.selectedRentalData = active;
          s.showRentalTrackerMap = true;
        }),
      },
      [
        div(classes: 'flex items-center justify-between mb-3', [
          div(classes: 'flex items-center gap-3', [
            div(classes: 'p-2 rounded-xl bg-purple-500/20', [lIcon('car', cls: 'w-5 h-5 text-purple-400')]),
            div([
              p(classes: 'text-xs font-semibold text-purple-400 uppercase tracking-wider', [
                Component.text('Active Vehicle Rental • $status'),
              ]),
              p(classes: 'font-bold', [
                Component.text('${active['brand']} ${active['model']} • ${active['plateNumber']}'),
              ]),
            ]),
          ]),
          if (status == 'Awaiting Signature')
            button(
              classes:
                  'px-4 py-2 rounded-xl text-xs font-bold text-white bg-green-500 hover:bg-green-600 transition-colors border-0 cursor-pointer',
              events: {
                'click': (e) {
                  e.stopPropagation();
                  s.setState(() {
                    s.signingContractId = active['id']?.toString();
                    s.signingContractTitle = '${active['brand']} ${active['model']} Rental Agreement';
                    s.signingContractTerms = active['contractTerms'] ?? 'Rental Agreement terms';
                    s.signingContractIsProperty = false;
                    s.showSignContractModal = true;
                  });
                },
              },
              [Component.text('Sign Contract')],
            ),
        ]),
        div(classes: 'flex items-center justify-between text-xs text-purple-300', [
          p([Component.text('Click card to view tracker and live trip map')]),
          div(classes: 'flex items-center gap-2', [
            if (active['allowChat'] == true)
              button(
                classes:
                    'px-3 py-1.5 rounded-lg text-xs font-bold text-blue-400 hover:bg-blue-500/15 border border-blue-500/30 cursor-pointer bg-transparent',
                events: {
                  'click': (e) {
                    e.stopPropagation();
                    final chatId = 'rental_${active['id']}_${s.userProfile?.uid}';
                    s.openChat(chatId);
                  },
                },
                [lIcon('message-square', cls: 'w-3.5 h-3.5 mr-1 inline'), Component.text('Chat Host')],
              )
            else
              span(classes: 'text-zinc-550 italic mr-1', [Component.text('Chat disabled')]),
            if (status == 'Booked' || status == 'Active' || status == 'Ongoing')
              button(
                classes:
                    'px-4 py-2 rounded-xl text-xs font-bold bg-purple-500/20 text-purple-300 hover:bg-purple-500/30 transition-colors border-0 cursor-pointer',
                events: {
                  'click': (e) {
                    e.stopPropagation();
                    s.setState(() {
                      s.selectedRentalData = active;
                      s.showExtendRentalModal = true;
                    });
                  },
                },
                [Component.text('Extend')],
              ),
          ]),
        ]),
        if (active['signatureHash'] != null)
          div(classes: 'mt-3 p-2.5 rounded-xl bg-green-500/10 border border-green-500/25 space-y-1', [
            p(classes: 'text-[10px] font-bold text-green-400 uppercase tracking-wider', [
              Component.text('✓ Signed Lease Details (Cryptographic SHA-256)'),
            ]),
            p(classes: 'text-[9px] font-mono text-green-300/80 break-all leading-normal', [
              Component.text(active['signatureHash'] as String),
            ]),
          ]),
      ],
    );
  }

  Component _activePropertyCard(PropertyRental active, bool isDark) {
    final s = component.state;
    final status = active.status;

    return div(
      classes: 'p-5 rounded-2xl border border-purple-500/30 bg-purple-500/10 transition-colors mb-4',
      [
        div(classes: 'flex items-center justify-between mb-3', [
          div(classes: 'flex items-center gap-3', [
            div(classes: 'p-2 rounded-xl bg-purple-500/20', [lIcon('home', cls: 'w-5 h-5 text-purple-400')]),
            div([
              p(classes: 'text-xs font-semibold text-purple-400 uppercase tracking-wider', [
                Component.text('Active Lease • $status'),
              ]),
              p(classes: 'font-bold', [Component.text(active.title)]),
            ]),
          ]),
          if (status == 'Awaiting Signature')
            button(
              classes:
                  'px-4 py-2 rounded-xl text-xs font-bold text-white bg-green-500 hover:bg-green-600 transition-colors border-0 cursor-pointer',
              events: {
                'click': (_) {
                  s.setState(() {
                    s.signingContractId = active.id;
                    s.signingContractTitle = '${active.title} Lease Agreement';
                    s.signingContractTerms = active.contractTerms;
                    s.signingContractIsProperty = true;
                    s.showSignContractModal = true;
                  });
                },
              },
              [Component.text('Sign Contract')],
            ),
        ]),
        div(classes: 'flex items-center justify-between text-xs text-purple-300', [
          p([
            Component.text(
              'Rent: ₱ ${active.priceMonthly.toStringAsFixed(0)}/mo • Deposit: ${active.depositMonths} mo',
            ),
          ]),
          if (active.allowChat)
            button(
              classes:
                  'px-3 py-1.5 rounded-lg text-xs font-bold text-blue-400 hover:bg-blue-500/15 border border-blue-500/30 cursor-pointer bg-transparent',
              events: {
                'click': (_) {
                  final chatId = 'property_${active.id}_${s.userProfile?.uid}';
                  s.openChat(chatId);
                },
              },
              [lIcon('message-square', cls: 'w-3.5 h-3.5 mr-1 inline'), Component.text('Chat Owner')],
            )
          else
            span(classes: 'text-zinc-550 italic', [Component.text('Chat disabled by host')]),
        ]),
        if (active.signatureHash != null)
          div(classes: 'mt-3 p-2.5 rounded-xl bg-green-500/10 border border-green-500/25 space-y-1', [
            p(classes: 'text-[10px] font-bold text-green-400 uppercase tracking-wider', [
              Component.text('✓ Signed Lease Details (Cryptographic SHA-256)'),
            ]),
            p(classes: 'text-[9px] font-mono text-green-300/80 break-all leading-normal', [
              Component.text(active.signatureHash!),
            ]),
          ]),
      ],
    );
  }

  Component _pendingRequestCard(Map<String, dynamic> req, bool isProperty, bool isDark) {
    final s = component.state;
    return div(
      classes:
          'p-5 rounded-2xl border ${isDark ? "border-zinc-800 bg-zinc-800/15" : "border-zinc-200 bg-zinc-50"} mb-4 flex items-center justify-between',
      [
        div(classes: 'flex items-center gap-3', [
          div(classes: 'p-2 rounded-xl bg-purple-500/20', [lIcon('clock', cls: 'w-5 h-5 text-purple-400')]),
          div([
            p(classes: 'text-xs font-semibold text-purple-400 uppercase tracking-wider', [
              Component.text('Awaiting Approval'),
            ]),
            p(classes: 'font-bold', [Component.text(req['title'] ?? (isProperty ? 'Lease' : 'Rental'))]),
            p(classes: 'text-xs text-zinc-550 capitalize', [
              Component.text('${req['multiplier']} ${req['durationType']}'),
            ]),
          ]),
        ]),
        div(classes: 'text-right flex flex-col items-end gap-1.5', [
          p(classes: 'font-black text-purple-400', [Component.text('₱${req["totalCost"]}')]),
          div(classes: 'flex items-center gap-2', [
            span(classes: 'px-2 py-0.5 rounded text-[10px] bg-yellow-500/20 text-yellow-400 font-bold', [
              Component.text('PENDING'),
            ]),
            if (!isProperty)
              button(
                classes:
                    'px-2.5 py-1 text-[10px] font-bold text-red-400 hover:text-red-300 border border-red-500/20 hover:bg-red-500/10 rounded-lg transition-all cursor-pointer bg-transparent',
                events: {
                  'click': (_) async {
                    final confirmed = confirmDialog(
                      'Are you sure you want to cancel this booking request? Your locked funds will be refunded.',
                    );
                    if (confirmed) {
                      try {
                        await s.firestore.cancelBookingRequest(req['id']?.toString() ?? '');
                        await s.loadRenterPendingRequests();
                        await s.loadUserProfile();
                        s.showAppToast('Request Cancelled', 'Your request has been cancelled and funds refunded.');
                      } catch (e) {
                        s.showAppToast('Error', 'Failed to cancel request: $e');
                      }
                    }
                  },
                },
                [Component.text('Cancel Request')],
              ),
          ]),
        ]),
      ],
    );
  }

  Component _vehicleCard(Map<String, dynamic> r, bool isDark, {bool isHostView = false}) {
    final s = component.state;
    final model = r['model'] ?? 'Unknown';
    final typeVal = r['type'] ?? r['vehicleType'];
    String type = typeVal?.toString().split('.').last ?? 'Unknown';
    if (type.toLowerCase() == 'null') type = 'Unknown';

    final priceVal = r['priceDaily'] ?? r['dailyRate'];
    final priceStr = (priceVal != null && priceVal.toString().toLowerCase() != 'null') ? priceVal.toString() : '0';

    final double pickupLat = (r['pickupLat'] as num?)?.toDouble() ?? 14.5995;
    final double pickupLng = (r['pickupLng'] as num?)?.toDouble() ?? 120.9842;
    final double distKm = calculateDistance(s.userLatitude, s.userLongitude, pickupLat, pickupLng);

    final cardCls = isDark
        ? 'bg-zinc-900 border-zinc-800 hover:border-purple-500/40'
        : 'bg-white border-zinc-200 shadow-sm hover:shadow-md';

    final photoUrl =
        r['frontPhotoUrl'] ?? r['frontPhoto'] ?? r['photoUrl'] ?? r['interiorPhotoUrl'] ?? r['backPhotoUrl'];
    final hasPhoto = photoUrl != null && photoUrl.toString().isNotEmpty && photoUrl.toString() != 'null';

    final gpsTrackerId = r['gpsTrackerId'] as String?;
    final hasGps = gpsTrackerId != null && gpsTrackerId.isNotEmpty;
    final fuelType = r['fuelType'] as String? ?? 'Gasoline';
    final transmission = r['transmission'] as String? ?? 'Automatic';

    return div(classes: 'p-5 rounded-2xl border transition-all card-hover $cardCls', [
      div(classes: 'flex items-start justify-between mb-4', [
        div([
          p(classes: 'font-bold text-lg', [Component.text(model)]),
          p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-500"} capitalize flex items-center gap-1.5', [
            Component.text(type),
            span([], classes: 'inline-block w-1 h-1 rounded-full bg-zinc-500'),
            span(classes: 'text-[10px] font-bold text-indigo-400 bg-indigo-500/10 px-1.5 py-0.5 rounded-md uppercase tracking-wider', [
              Component.text(fuelType),
            ]),
            span([], classes: 'inline-block w-1 h-1 rounded-full bg-zinc-500'),
            span(classes: 'text-[10px] font-bold text-purple-400 bg-purple-500/10 px-1.5 py-0.5 rounded-md uppercase tracking-wider', [
              Component.text(transmission),
            ]),
          ]),
        ]),
        div(classes: 'flex items-center gap-1.5', [
          if (isHostView) ...[
            if (hasGps)
              span(
                classes:
                    'px-2 py-1 rounded-lg text-[10px] font-bold bg-green-500/15 text-green-400 flex items-center gap-1',
                attributes: {'title': 'GPS Tracker ID: $gpsTrackerId'},
                [
                  lIcon('activity', cls: 'w-3 h-3 text-green-400 animate-pulse'),
                  Component.text('GPS Active (Online)'),
                ],
              )
            else
              span(
                classes:
                    'px-2 py-1 rounded-lg text-[10px] font-bold bg-amber-500/15 text-amber-400 flex items-center gap-1',
                [
                  lIcon('alert-triangle', cls: 'w-3 h-3 text-amber-400'),
                  Component.text('No GPS Registered'),
                ],
              ),
          ] else if (hasGps) ...[
            span(
              classes:
                  'px-2 py-1 rounded-lg text-[10px] font-bold bg-green-500/15 text-green-400 flex items-center gap-0.5',
              attributes: {'title': 'GPS Tracker ID: $gpsTrackerId'},
              [
                lIcon('map-pin', cls: 'w-2.5 h-2.5'),
                Component.text('GPS Tracked'),
              ],
            ),
          ],
          span(classes: 'px-2 py-1 rounded-lg text-xs font-bold bg-purple-500/20 text-purple-400', [
            Component.text(r['status'] ?? 'AVAILABLE'),
          ]),
        ]),
      ]),

      div(
        classes:
            'w-full h-32 rounded-xl mb-4 ${isDark ? "bg-zinc-800" : "bg-zinc-100"} flex items-center justify-center overflow-hidden relative',
        [
          if (hasPhoto)
            img(src: photoUrl.toString(), classes: 'w-full h-full object-cover', attributes: {'alt': model})
          else
            lIcon('car', cls: 'w-10 h-10 ${isDark ? "text-zinc-600" : "text-zinc-300"}'),
        ],
      ),

      div(classes: 'flex items-center justify-between', [
        div([
          p(classes: 'font-bold text-lg text-purple-400', [Component.text('₱ $priceStr/day')]),
          div(classes: 'flex items-center gap-1 text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
            lIcon('map-pin', cls: 'w-3 h-3'),
            Component.text(' ${distKm.toStringAsFixed(1)} km'),
          ]),
        ]),

        if (isHostView)
          div(classes: 'flex gap-2', [
            button(
              classes:
                  'p-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-300 hover:bg-zinc-50"} transition-colors bg-transparent cursor-pointer',
              events: {
                'click': (_) => s.setState(() {
                  s.selectedRentalData = r;
                  s.showVehicleQaModal = true;
                }),
              },
              [lIcon('message-circle-question', cls: 'w-4 h-4 text-zinc-400')],
            ),
            button(
              classes:
                  'px-4 py-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-300 hover:bg-zinc-50"} transition-colors bg-transparent cursor-pointer',
              events: {
                'click': (_) {
                  s.setState(() {
                    s.selectedRentalData = r;
                    s.showManageVehicleModal = true;
                  });
                },
              },
              [Component.text('Manage')],
            ),
          ])
        else
          div(classes: 'flex items-center gap-2', [
            button(
              classes:
                  'p-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800 text-purple-400" : "border-zinc-300 hover:bg-zinc-50 text-purple-650"} transition-colors bg-transparent cursor-pointer',
              events: {
                'click': (_) => s.setState(() {
                  s.selectedRentalData = r;
                  s.showVehicleQaModal = true;
                }),
              },
              [lIcon('message-circle-question', cls: 'w-4 h-4')],
            ),
            button(
              classes:
                  'px-4 py-2.5 rounded-xl text-sm font-semibold text-white logo-gradient hover:opacity-90 transition-opacity border-0 cursor-pointer',
              events: {
                'click': (_) => s.setState(() {
                  s.selectedRentalData = r;
                  s.showBookVehicleModal = true;
                }),
              },
              [Component.text('Book Now')],
            ),
          ]),
      ]),
    ]);
  }

  Component _propertyCard(PropertyRental prop, bool isDark, {bool isHostView = false}) {
    final s = component.state;
    final monthly = prop.priceMonthly;
    final double distKm = calculateDistance(s.userLatitude, s.userLongitude, prop.latitude, prop.longitude);

    final cardCls = isDark
        ? 'bg-zinc-900 border-zinc-800 hover:border-purple-500/40'
        : 'bg-white border-zinc-200 shadow-sm hover:shadow-md';

    final hasPhoto = prop.photoUrls.isNotEmpty && prop.photoUrls.first.isNotEmpty;

    return div(classes: 'p-5 rounded-2xl border transition-all card-hover $cardCls', [
      div(classes: 'flex items-start justify-between mb-4', [
        div([
          p(classes: 'font-bold text-lg leading-tight line-clamp-1', [Component.text(prop.title)]),
          p(classes: 'text-sm ${isDark ? "text-zinc-550" : "text-zinc-500"} capitalize', [
            Component.text('${prop.category.label} • ${prop.type.label}'),
          ]),
        ]),
        span(classes: 'px-2 py-1 rounded-lg text-xs font-bold bg-purple-500/20 text-purple-400', [
          Component.text(prop.status),
        ]),
      ]),

      div(
        classes:
            'w-full h-32 rounded-xl mb-4 ${isDark ? "bg-zinc-850" : "bg-zinc-100"} flex items-center justify-center overflow-hidden relative',
        [
          if (hasPhoto)
            img(src: prop.photoUrls.first, classes: 'w-full h-full object-cover', attributes: {'alt': prop.title})
          else
            lIcon('home', cls: 'w-10 h-10 ${isDark ? "text-zinc-650" : "text-zinc-300"}'),
        ],
      ),

      div(classes: 'flex items-center justify-between', [
        div([
          p(classes: 'font-bold text-lg text-purple-400', [Component.text('₱ ${monthly.toStringAsFixed(0)}/mo')]),
          div(classes: 'flex items-center gap-1 text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
            lIcon('map-pin', cls: 'w-3 h-3'),
            Component.text(' ${distKm.toStringAsFixed(1)} km'),
          ]),
        ]),

        if (isHostView)
          div(classes: 'flex gap-2', [
            button(
              classes:
                  'p-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-300 hover:bg-zinc-50"} transition-colors bg-transparent cursor-pointer',
              events: {
                'click': (_) => s.setState(() {
                  s.selectedPropertyData = prop.toMap();
                  s.showPropertyQaModal = true;
                }),
              },
              [lIcon('message-circle-question', cls: 'w-4 h-4 text-zinc-400')],
            ),
            button(
              classes:
                  'px-4 py-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-300 hover:bg-zinc-50"} transition-colors bg-transparent cursor-pointer',
              events: {
                'click': (_) {
                  s.setState(() {
                    s.selectedPropertyData = prop.toMap();
                    s.showManagePropertyModal = true;
                  });
                },
              },
              [Component.text('Manage')],
            ),
          ])
        else
          div(classes: 'flex items-center gap-2', [
            button(
              classes:
                  'p-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800 text-purple-400" : "border-zinc-300 hover:bg-zinc-50 text-purple-600"} transition-colors bg-transparent cursor-pointer',
              events: {
                'click': (_) => s.setState(() {
                  s.selectedPropertyData = prop.toMap();
                  s.showPropertyQaModal = true;
                }),
              },
              [lIcon('message-circle-question', cls: 'w-4 h-4')],
            ),
            button(
              classes:
                  'px-4 py-2.5 rounded-xl text-sm font-semibold text-white logo-gradient hover:opacity-90 transition-opacity border-0 cursor-pointer',
              events: {
                'click': (_) => s.setState(() {
                  s.selectedPropertyData = prop.toMap();
                  s.showBookPropertyModal = true;
                }),
              },
              [Component.text('Rent Now')],
            ),
          ]),
      ]),
    ]);
  }
}
