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
    final isHistory = s.transitMode == TransitMode.history;

    return div(classes: 'space-y-8 animate-fade-up', [
      // Top Header
      div(classes: 'flex items-center justify-between', [
        div([
          h1(
            classes:
                'text-3xl font-extrabold tracking-tight bg-gradient-to-r from-indigo-400 via-purple-400 to-pink-400 bg-clip-text text-transparent',
            [
              Component.text(
                isHistory
                    ? 'Rental History'
                    : (isVehicles ? 'Vehicles & Transit Marketplace' : 'Properties & Spaces Marketplace'),
              ),
            ],
          ),
          p(classes: 'text-sm mt-2 max-w-xl leading-relaxed ${isDark ? "text-zinc-400" : "text-zinc-650"}', [
            Component.text(
              isHistory
                  ? 'A complete record of your past rentals as a renter and as a host.'
                  : (isVehicles
                        ? 'Discover verified local rides or capitalize on your idle garage. Seamless, secure, and peer-to-peer.'
                        : 'Discover verified residential and commercial spaces or lease your properties in secure escrow.'),
            ),
          ]),
        ]),
        div(classes: 'p-3.5 rounded-2xl bg-indigo-500/10 border border-indigo-500/20', [
          lIcon(isHistory ? 'clock' : (isVehicles ? 'car' : 'home'), cls: 'w-7 h-7 text-indigo-400'),
        ]),
      ]),

      // Segmented Switcher for Category: Vehicles vs Properties (hidden in History mode)
      if (!isHistory)
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

      // Segmented Switcher for Mode: Rent | Host | History
      segmentedControl(
        options: const [
          ('🔍 Rent', 'rent'),
          ('🏠 Host', 'host'),
          ('📋 History', 'history'),
        ],
        selected: s.transitMode == TransitMode.rent ? 'rent' : (s.transitMode == TransitMode.host ? 'host' : 'history'),
        isDark: isDark,
        onChange: (v) => s.setState(() {
          if (v == 'rent')
            s.transitMode = TransitMode.rent;
          else if (v == 'host')
            s.transitMode = TransitMode.host;
          else
            s.transitMode = TransitMode.history;
        }),
      ),

      if (s.transitMode == TransitMode.rent)
        _rentView(isVehicles, isDark)
      else if (s.transitMode == TransitMode.host)
        _hostView(isVehicles, isDark)
      else
        _RentalHistoryView(state: s),
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
    final chatId = 'rental_${active['id']}_${s.userProfile?.uid}';
    final unreadCount = s.getUnreadChatCount(chatId);

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
          div(classes: 'flex items-center gap-2', [
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
            if (status != 'Awaiting Signature' && unreadCount > 0)
              span(
                classes:
                    'px-2 py-1 rounded-lg text-xs font-black bg-red-500/10 text-red-500 border border-red-500/30 flex items-center gap-1 animate-pulse',
                [
                  lIcon('message-square', cls: 'w-3 h-3 text-red-500'),
                  Component.text('$unreadCount New'),
                ],
              ),
          ]),
        ]),
        div(classes: 'flex items-center justify-between text-xs text-purple-300', [
          p([Component.text('Click card to view tracker and live trip map')]),
          div(classes: 'flex items-center gap-2', [
            if (active['allowChat'] == true)
              () {
                final chatId = 'rental_${active['id']}_${s.userProfile?.uid}';
                return button(
                  classes:
                      'px-3 py-1.5 rounded-lg text-xs font-bold text-blue-400 hover:bg-blue-500/15 border border-blue-500/30 cursor-pointer bg-transparent relative',
                  events: {
                    'click': (e) {
                      e.stopPropagation();
                      s.openChat(chatId);
                    },
                  },
                  [
                    lIcon('message-square', cls: 'w-3.5 h-3.5 mr-1 inline'),
                    Component.text('Chat Host'),
                    if (s.getUnreadChatCount(chatId) > 0)
                      span(
                        classes:
                            'absolute -top-1 -right-1 px-1.5 py-0.5 text-[9px] font-black text-white bg-red-500 rounded-full border border-white animate-pulse',
                        [Component.text('${s.getUnreadChatCount(chatId)}')],
                      ),
                  ],
                );
              }()
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
    final chatId = 'property_${active.id}_${s.userProfile?.uid}';
    final unreadCount = s.getUnreadChatCount(chatId);

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
          div(classes: 'flex items-center gap-2', [
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
            if (status != 'Awaiting Signature' && unreadCount > 0)
              span(
                classes:
                    'px-2 py-1 rounded-lg text-xs font-black bg-red-500/10 text-red-500 border border-red-500/30 flex items-center gap-1 animate-pulse',
                [
                  lIcon('message-square', cls: 'w-3 h-3 text-red-500'),
                  Component.text('$unreadCount New'),
                ],
              ),
          ]),
        ]),
        div(classes: 'flex items-center justify-between text-xs text-purple-300', [
          p([
            Component.text(
              'Rent: ₱ ${active.priceMonthly.toStringAsFixed(0)}/mo • Deposit: ${active.depositMonths} mo',
            ),
          ]),
          if (active.allowChat)
            () {
              final chatId = 'property_${active.id}_${s.userProfile?.uid}';
              return button(
                classes:
                    'px-3 py-1.5 rounded-lg text-xs font-bold text-blue-400 hover:bg-blue-500/15 border border-blue-500/30 cursor-pointer bg-transparent relative',
                events: {
                  'click': (_) {
                    s.openChat(chatId);
                  },
                },
                [
                  lIcon('message-square', cls: 'w-3.5 h-3.5 mr-1 inline'),
                  Component.text('Chat Owner'),
                  if (s.getUnreadChatCount(chatId) > 0)
                    span(
                      classes:
                          'absolute -top-1 -right-1 px-1.5 py-0.5 text-[9px] font-black text-white bg-red-500 rounded-full border border-white animate-pulse',
                      [Component.text('${s.getUnreadChatCount(chatId)}')],
                    ),
                ],
              );
            }()
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

    final renteeId = r['renteeId']?.toString();
    final hasActiveRenter = renteeId != null && renteeId.isNotEmpty;
    final chatId = hasActiveRenter ? 'rental_${r['id']}_$renteeId' : null;
    final unreadCount = chatId != null ? s.getUnreadChatCount(chatId) : 0;

    return div(classes: 'p-5 rounded-2xl border transition-all card-hover $cardCls', [
      div(classes: 'flex items-start justify-between mb-4', [
        div([
          p(classes: 'font-bold text-lg', [Component.text(model)]),
          p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-500"} capitalize flex items-center gap-1.5', [
            Component.text(type),
            span([], classes: 'inline-block w-1 h-1 rounded-full bg-zinc-500'),
            span(
              classes:
                  'text-[10px] font-bold text-indigo-400 bg-indigo-500/10 px-1.5 py-0.5 rounded-md uppercase tracking-wider',
              [
                Component.text(fuelType),
              ],
            ),
            span([], classes: 'inline-block w-1 h-1 rounded-full bg-zinc-500'),
            span(
              classes:
                  'text-[10px] font-bold text-purple-400 bg-purple-500/10 px-1.5 py-0.5 rounded-md uppercase tracking-wider',
              [
                Component.text(transmission),
              ],
            ),
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
            if (unreadCount > 0)
              span(
                classes:
                    'px-2 py-1 rounded-lg text-xs font-black bg-red-500/10 text-red-500 border border-red-500/30 flex items-center gap-1 animate-pulse',
                [
                  lIcon('message-square', cls: 'w-3 h-3 text-red-500'),
                  Component.text('$unreadCount New'),
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
          Builder(
            builder: (context) {
              final hasRequests = s.hostPendingRequests.any((req) => req['rentalId'] == r['id']);
              final showChat = hasActiveRenter && r['allowChat'] == true;
              return div(classes: 'flex gap-2 items-center', [
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
                if (showChat)
                  button(
                    classes:
                        'px-3 py-2 rounded-xl text-xs font-bold text-blue-400 hover:bg-blue-500/15 border border-blue-500/30 cursor-pointer bg-transparent relative flex items-center',
                    events: {
                      'click': (e) {
                        e.stopPropagation();
                        s.openChat(chatId!);
                      },
                    },
                    [
                      lIcon('message-square', cls: 'w-3.5 h-3.5 mr-1 inline'),
                      Component.text('Chat Renter'),
                      if (unreadCount > 0)
                        span(
                          classes:
                              'absolute -top-1 -right-1 px-1.5 py-0.5 text-[9px] font-black text-white bg-red-500 rounded-full border border-white animate-pulse',
                          [Component.text('$unreadCount')],
                        ),
                    ],
                  ),
                button(
                  classes:
                      'px-4 py-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-300 hover:bg-zinc-50"} transition-colors bg-transparent cursor-pointer relative',
                  events: {
                    'click': (_) {
                      s.setState(() {
                        s.selectedRentalData = r;
                        s.showManageVehicleModal = true;
                      });
                    },
                  },
                  [
                    Component.text('Manage'),
                    if (hasRequests)
                      span(
                        classes: 'absolute -top-1 -right-1 flex h-2.5 w-2.5',
                        [
                          span(
                            classes:
                                'animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75',
                            [],
                          ),
                          span(classes: 'relative inline-flex rounded-full h-2.5 w-2.5 bg-red-500', []),
                        ],
                      ),
                  ],
                ),
              ]);
            },
          )
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

    final renteeId = prop.renteeId;
    final hasActiveRenter = renteeId != null && renteeId.isNotEmpty;
    final chatId = hasActiveRenter ? 'property_${prop.id}_$renteeId' : null;
    final unreadCount = chatId != null ? s.getUnreadChatCount(chatId) : 0;

    return div(classes: 'p-5 rounded-2xl border transition-all card-hover $cardCls', [
      div(classes: 'flex items-start justify-between mb-4', [
        div([
          p(classes: 'font-bold text-lg leading-tight line-clamp-1', [Component.text(prop.title)]),
          p(classes: 'text-sm ${isDark ? "text-zinc-550" : "text-zinc-500"} capitalize', [
            Component.text('${prop.category.label} • ${prop.type.label}'),
          ]),
        ]),
        div(classes: 'flex items-center gap-1.5', [
          if (isHostView && unreadCount > 0)
            span(
              classes:
                  'px-2 py-1 rounded-lg text-xs font-black bg-red-500/10 text-red-500 border border-red-500/30 flex items-center gap-1 animate-pulse',
              [
                lIcon('message-square', cls: 'w-3 h-3 text-red-500'),
                Component.text('$unreadCount New'),
              ],
            ),
          span(classes: 'px-2 py-1 rounded-lg text-xs font-bold bg-purple-500/20 text-purple-400', [
            Component.text(prop.status),
          ]),
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
          Builder(
            builder: (context) {
              final hasRequests = s.propertyHostPendingRequests.any((req) => req['propertyId'] == prop.id);
              final showChat = hasActiveRenter && prop.allowChat;
              return div(classes: 'flex gap-2 items-center', [
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
                if (showChat)
                  button(
                    classes:
                        'px-3 py-2 rounded-xl text-xs font-bold text-blue-400 hover:bg-blue-500/15 border border-blue-500/30 cursor-pointer bg-transparent relative flex items-center',
                    events: {
                      'click': (e) {
                        e.stopPropagation();
                        s.openChat(chatId!);
                      },
                    },
                    [
                      lIcon('message-square', cls: 'w-3.5 h-3.5 mr-1 inline'),
                      Component.text('Chat Renter'),
                      if (unreadCount > 0)
                        span(
                          classes:
                              'absolute -top-1 -right-1 px-1.5 py-0.5 text-[9px] font-black text-white bg-red-500 rounded-full border border-white animate-pulse',
                          [Component.text('$unreadCount')],
                        ),
                    ],
                  ),
                button(
                  classes:
                      'px-4 py-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-300 hover:bg-zinc-50"} transition-colors bg-transparent cursor-pointer relative',
                  events: {
                    'click': (_) {
                      s.setState(() {
                        s.selectedPropertyData = prop.toMap();
                        s.showManagePropertyModal = true;
                      });
                    },
                  },
                  [
                    Component.text('Manage'),
                    if (hasRequests)
                      span(
                        classes: 'absolute -top-1 -right-1 flex h-2.5 w-2.5',
                        [
                          span(
                            classes:
                                'animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75',
                            [],
                          ),
                          span(classes: 'relative inline-flex rounded-full h-2.5 w-2.5 bg-red-500', []),
                        ],
                      ),
                  ],
                ),
              ]);
            },
          )
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

// ─────────────────────────────────────────────────────────────────────────────
// RENTAL HISTORY VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _RentalHistoryView extends StatefulComponent {
  final TranyxAppState state;
  const _RentalHistoryView({required this.state});

  @override
  State<_RentalHistoryView> createState() => _RentalHistoryViewState();
}

class _RentalHistoryViewState extends State<_RentalHistoryView> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _historyItems = [];
  final Map<String, UserProfile?> _counterpartyCache = {};

  // Filters
  String _roleFilter = 'all'; // 'all', 'renter', 'host'
  String _kindFilter = 'all'; // 'all', 'vehicle', 'property'

  // Rating state
  final Map<String, double> _pendingStars = {}; // rentalId -> star hover/selection
  final Set<String> _submittingRating = {};
  final Set<String> _ratedThisSession = {};

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateComponent(_RentalHistoryView oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.state.userProfile?.uid != component.state.userProfile?.uid) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final uid = component.state.userProfile?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final items = await component.state.firestore.getMyRentalHistory(uid);
      // Pre-fetch counterparty profiles
      for (final item in items) {
        final counterpartyUid = _counterpartyUid(item, uid);
        if (counterpartyUid != null && !_counterpartyCache.containsKey(counterpartyUid)) {
          _counterpartyCache[counterpartyUid] = await component.state.firestore.getUser(counterpartyUid);
        }
      }
      setState(() {
        _historyItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  /// Returns the UID of the counterparty for a given history record and current user.
  String? _counterpartyUid(Map<String, dynamic> item, String myUid) {
    final hostId = item['hostId']?.toString();
    final renteeId = item['renteeId']?.toString();
    if (hostId == myUid) return (renteeId?.isNotEmpty == true) ? renteeId : null;
    return (hostId?.isNotEmpty == true) ? hostId : null;
  }

  String _formatDate(int? ms) {
    if (ms == null) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day.toString().padLeft(2, '0')}, ${dt.year}';
  }

  String _roleLabel(Map<String, dynamic> item, String myUid) {
    return item['hostId']?.toString() == myUid ? 'host' : 'renter';
  }

  /// Build a small pill badge
  Component _pill(String text, String colorCls) {
    return span(
      classes: 'px-2.5 py-0.5 rounded-full text-[10px] font-bold uppercase tracking-wider $colorCls',
      [Component.text(text)],
    );
  }

  /// Build a star row (read-only)
  Component _starDisplay(double? rating, String label) {
    final isDark = component.state.isDark;
    if (rating == null) {
      return span(classes: 'text-xs italic ${isDark ? "text-zinc-600" : "text-zinc-400"}', [
        Component.text('No $label yet'),
      ]);
    }
    final full = rating.floor();
    final frac = rating - full;
    return div(classes: 'flex items-center gap-1', [
      for (int i = 1; i <= 5; i++)
        span(
          classes: i <= full
              ? 'text-amber-400 text-sm'
              : (i == full + 1 && frac >= 0.5 ? 'text-amber-300 text-sm' : 'text-zinc-600 text-sm'),
          [Component.text('★')],
        ),
      span(classes: 'text-xs font-bold ml-1 ${isDark ? "text-zinc-300" : "text-zinc-600"}', [
        Component.text(rating.toStringAsFixed(1)),
      ]),
      span(classes: 'text-[10px] ml-1 ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
        Component.text('($label)'),
      ]),
    ]);
  }

  /// Build the interactive star-rating + submit section
  Component _buildRatingWidget(Map<String, dynamic> item, String myRole, String counterpartyUid) {
    final s = component.state;
    final isDark = s.isDark;
    final rentalId = item['id']?.toString() ?? '';
    final ratingRole = myRole == 'host' ? 'renter' : 'host'; // who I'm rating
    final ratedFieldKey = '${ratingRole}RatedBy_${s.userProfile?.uid}';
    final alreadyRated = item[ratedFieldKey] == true || _ratedThisSession.contains(rentalId);
    final isSubmitting = _submittingRating.contains(rentalId);
    final selectedStars = _pendingStars[rentalId] ?? 0.0;

    if (alreadyRated) {
      return div(classes: 'flex items-center gap-1.5 text-xs text-emerald-400 font-semibold', [
        lIcon('check-circle', cls: 'w-3.5 h-3.5'),
        Component.text('Rating submitted'),
      ]);
    }

    return div(classes: 'space-y-2', [
      p(classes: 'text-[10px] font-bold uppercase tracking-wider ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
        Component.text(myRole == 'host' ? 'Rate this Renter' : 'Rate this Host'),
      ]),
      div(classes: 'flex items-center gap-1', [
        for (int i = 1; i <= 5; i++)
          button(
            classes:
                'text-xl border-0 bg-transparent cursor-pointer transition-transform hover:scale-125 p-0.5 ${i <= selectedStars ? "text-amber-400" : (isDark ? "text-zinc-700" : "text-zinc-300")}',
            events: {
              'click': (_) => setState(() => _pendingStars[rentalId] = i.toDouble()),
            },
            [Component.text('★')],
          ),
      ]),
      if (selectedStars > 0)
        button(
          classes:
              'px-3 py-1.5 rounded-xl text-xs font-bold text-white logo-gradient border-0 cursor-pointer hover:opacity-90 transition-opacity flex items-center gap-1.5 ${isSubmitting ? "opacity-60 pointer-events-none" : ""}',
          events: {
            'click': (_) async {
              if (isSubmitting || selectedStars <= 0) return;
              setState(() => _submittingRating.add(rentalId));
              try {
                await s.firestore.submitRentalRating(
                  targetUid: counterpartyUid,
                  callerUid: s.userProfile?.uid ?? '',
                  role: ratingRole,
                  stars: selectedStars,
                  rentalId: rentalId,
                );
                setState(() {
                  _ratedThisSession.add(rentalId);
                  _submittingRating.remove(rentalId);
                });
                s.showAppToast('Rating Submitted', 'Thank you for your feedback!');
              } catch (e) {
                setState(() => _submittingRating.remove(rentalId));
                s.showAppToast('Error', 'Could not submit rating: $e');
              }
            },
          },
          [
            if (isSubmitting) lIcon('loader-2', cls: 'w-3 h-3 animate-spin'),
            Component.text(isSubmitting ? 'Submitting...' : 'Submit Rating'),
          ],
        ),
    ]);
  }

  /// Counterparty profile block
  Component _buildCounterpartySection(
    UserProfile? profile,
    String counterpartyRole, // 'renter' or 'host'
    bool isDark,
    Map<String, dynamic> item,
    String myRole,
    String counterpartyUid,
  ) {
    final name = profile?.name ?? 'Unknown User';
    final photo = profile?.photoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;
    final renterRating = profile?.renterRating;
    final hostRating = profile?.hostRating;
    final serviceRating = profile?.rating;

    return div(
      classes: 'mt-4 pt-4 border-t ${isDark ? "border-zinc-800" : "border-zinc-200"} space-y-3',
      [
        p(classes: 'text-[10px] font-bold uppercase tracking-wider ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
          Component.text(counterpartyRole == 'renter' ? '👤 Renter Details' : '🏠 Host / Owner Details'),
        ]),
        div(classes: 'flex items-start gap-3', [
          // Avatar
          div(
            classes:
                'w-10 h-10 rounded-full flex-shrink-0 flex items-center justify-center font-bold text-sm overflow-hidden '
                '${isDark ? "bg-indigo-500/20 text-indigo-300" : "bg-indigo-100 text-indigo-600"}',
            [
              if (hasPhoto)
                img(
                  src: photo,
                  alt: name,
                  classes: 'w-full h-full object-cover',
                )
              else
                Component.text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
            ],
          ),
          // Info
          div(classes: 'flex-1 min-w-0', [
            p(classes: 'font-bold text-sm truncate', [Component.text(name)]),
            if (profile != null) ...[
              div(classes: 'flex flex-wrap gap-2 mt-1', [
                _starDisplay(renterRating, 'As Renter'),
                _starDisplay(hostRating, 'As Host'),
                if (serviceRating != null) _starDisplay(serviceRating, 'Service'),
              ]),
              div(classes: 'flex flex-wrap gap-1.5 mt-2', [
                if (profile.idVerified) _pill('ID Verified', 'bg-blue-500/20 text-blue-400'),
                if (profile.bgChecked) _pill('BG Checked', 'bg-emerald-500/20 text-emerald-400'),
                if (profile.isPremium) _pill('Premium', 'bg-amber-500/20 text-amber-500'),
              ]),
            ],
          ]),
        ]),
        // Rating widget
        _buildRatingWidget(item, myRole, counterpartyUid),
      ],
    );
  }

  Component _buildVehicleHistoryCard(Map<String, dynamic> item, bool isDark, String myUid) {
    final myRole = _roleLabel(item, myUid);
    final counterpartyUid = _counterpartyUid(item, myUid);
    final counterparty = counterpartyUid != null ? _counterpartyCache[counterpartyUid] : null;
    final brand = item['brand']?.toString() ?? '';
    final model = item['model']?.toString() ?? '';
    final year = item['year']?.toString() ?? '';
    final plate = item['plateNumber']?.toString() ?? item['plate']?.toString() ?? '';
    final fuelType = item['fuelType']?.toString() ?? 'Gasoline';
    final transmission = item['transmission']?.toString() ?? 'Automatic';
    final vehicleType =
        item['vehicleType']?.toString().split('.').last ?? item['type']?.toString().split('.').last ?? '';
    final totalCost = (item['totalCost'] as num?)?.toDouble() ?? 0.0;
    final durationType = item['rentalDurationType']?.toString() ?? item['durationType']?.toString() ?? '';
    final multiplier = item['rentalMultiplier'] ?? item['multiplier'] ?? '';
    final startDate = (item['startDate'] as num?)?.toInt();
    final endDate = (item['endDate'] as num?)?.toInt();
    final completedAt = (item['completedAt'] as num?)?.toInt();

    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    return div(classes: 'p-5 rounded-2xl border $cardCls space-y-1', [
      // Header row
      div(classes: 'flex items-start justify-between gap-3', [
        div(classes: 'flex items-center gap-3', [
          div(classes: 'p-2.5 rounded-xl ${isDark ? "bg-zinc-800" : "bg-zinc-100"}', [
            lIcon('car', cls: 'w-5 h-5 text-purple-400'),
          ]),
          div([
            p(classes: 'font-bold text-base', [
              Component.text('$year $brand $model'.trim()),
            ]),
            if (plate.isNotEmpty)
              p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
                Component.text('Plate: $plate'),
              ]),
          ]),
        ]),
        div(classes: 'flex flex-col items-end gap-1.5', [
          _pill(
            myRole == 'host' ? 'As Host' : 'As Renter',
            myRole == 'host' ? 'bg-indigo-500/20 text-indigo-400' : 'bg-purple-500/20 text-purple-400',
          ),
          _pill('Completed', 'bg-emerald-500/20 text-emerald-400'),
        ]),
      ]),

      // Specs row
      div(classes: 'flex flex-wrap gap-2 mt-3', [
        _pill(fuelType, 'bg-amber-500/15 text-amber-400'),
        _pill(transmission, 'bg-blue-500/15 text-blue-400'),
        if (vehicleType.isNotEmpty && vehicleType.toLowerCase() != 'null')
          _pill(vehicleType, 'bg-zinc-500/20 ${isDark ? "text-zinc-400" : "text-zinc-600"}'),
      ]),

      // Rental details
      div(classes: 'mt-3 grid grid-cols-2 gap-x-4 gap-y-1 text-xs', [
        if (startDate != null)
          div([
            span(classes: '${isDark ? "text-zinc-500" : "text-zinc-400"} mr-1', [Component.text('From:')]),
            Component.text(_formatDate(startDate)),
          ]),
        if (endDate != null)
          div([
            span(classes: '${isDark ? "text-zinc-500" : "text-zinc-400"} mr-1', [Component.text('To:')]),
            Component.text(_formatDate(endDate)),
          ]),
        if (durationType.isNotEmpty && multiplier.toString().isNotEmpty)
          div([
            span(classes: '${isDark ? "text-zinc-500" : "text-zinc-400"} mr-1', [Component.text('Duration:')]),
            Component.text('$multiplier $durationType'),
          ]),
        div([
          span(classes: '${isDark ? "text-zinc-500" : "text-zinc-400"} mr-1', [Component.text('Total:')]),
          span(classes: 'font-bold text-emerald-400', [Component.text('₱${totalCost.toStringAsFixed(2)}')]),
        ]),
        if (completedAt != null)
          div([
            span(classes: '${isDark ? "text-zinc-500" : "text-zinc-400"} mr-1', [Component.text('Completed:')]),
            Component.text(_formatDate(completedAt)),
          ]),
      ]),

      // Counterparty
      _buildCounterpartySection(
        counterparty,
        myRole == 'host' ? 'renter' : 'host',
        isDark,
        item,
        myRole,
        counterpartyUid ?? '',
      ),
    ]);
  }

  Component _buildPropertyHistoryCard(Map<String, dynamic> item, bool isDark, String myUid) {
    final myRole = _roleLabel(item, myUid);
    final counterpartyUid = _counterpartyUid(item, myUid);
    final counterparty = counterpartyUid != null ? _counterpartyCache[counterpartyUid] : null;
    final title = item['title']?.toString() ?? 'Property Rental';
    final address = item['address']?.toString() ?? '';
    // Parse category/type labels — they may be enum names
    String categoryLabel = item['category']?.toString().split('.').last ?? '';
    String typeLabel = item['type']?.toString().split('.').last ?? '';
    // Attempt to map to friendly label via enums if available
    try {
      if (categoryLabel.isNotEmpty) {
        final cat = PropertyCategory.values.firstWhere(
          (c) => c.name == categoryLabel,
          orElse: () => PropertyCategory.values.first,
        );
        categoryLabel = cat.label;
      }
    } catch (_) {}
    try {
      if (typeLabel.isNotEmpty) {
        final t = PropertyType.values.firstWhere((t) => t.name == typeLabel, orElse: () => PropertyType.values.first);
        typeLabel = t.label;
      }
    } catch (_) {}

    final priceMonthly = (item['priceMonthly'] as num?)?.toDouble() ?? 0.0;
    final depositMonths = item['depositMonths'] ?? '';
    final totalCost = (item['totalCost'] as num?)?.toDouble() ?? 0.0;
    final startDate = (item['startDate'] as num?)?.toInt();
    final endDate = (item['endDate'] as num?)?.toInt();
    final completedAt = (item['completedAt'] as num?)?.toInt();

    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    return div(classes: 'p-5 rounded-2xl border $cardCls space-y-1', [
      // Header row
      div(classes: 'flex items-start justify-between gap-3', [
        div(classes: 'flex items-center gap-3', [
          div(classes: 'p-2.5 rounded-xl ${isDark ? "bg-zinc-800" : "bg-zinc-100"}', [
            lIcon('home', cls: 'w-5 h-5 text-teal-400'),
          ]),
          div(classes: 'flex-1 min-w-0', [
            p(classes: 'font-bold text-base truncate', [Component.text(title)]),
            if (address.isNotEmpty)
              p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"} truncate', [Component.text(address)]),
          ]),
        ]),
        div(classes: 'flex flex-col items-end gap-1.5 flex-shrink-0', [
          _pill(
            myRole == 'host' ? 'As Host' : 'As Renter',
            myRole == 'host' ? 'bg-indigo-500/20 text-indigo-400' : 'bg-teal-500/20 text-teal-400',
          ),
          _pill('Completed', 'bg-emerald-500/20 text-emerald-400'),
        ]),
      ]),

      // Category / Type chips
      div(classes: 'flex flex-wrap gap-2 mt-3', [
        if (categoryLabel.isNotEmpty) _pill(categoryLabel, 'bg-teal-500/15 text-teal-400'),
        if (typeLabel.isNotEmpty) _pill(typeLabel, 'bg-cyan-500/15 text-cyan-400'),
      ]),

      // Rental details
      div(classes: 'mt-3 grid grid-cols-2 gap-x-4 gap-y-1 text-xs', [
        if (startDate != null)
          div([
            span(classes: '${isDark ? "text-zinc-500" : "text-zinc-400"} mr-1', [Component.text('From:')]),
            Component.text(_formatDate(startDate)),
          ]),
        if (endDate != null)
          div([
            span(classes: '${isDark ? "text-zinc-500" : "text-zinc-400"} mr-1', [Component.text('To:')]),
            Component.text(_formatDate(endDate)),
          ]),
        if (priceMonthly > 0)
          div([
            span(classes: '${isDark ? "text-zinc-500" : "text-zinc-400"} mr-1', [Component.text('Monthly:')]),
            Component.text('₱${priceMonthly.toStringAsFixed(0)}/mo'),
          ]),
        if (depositMonths.toString().isNotEmpty && depositMonths.toString() != '0')
          div([
            span(classes: '${isDark ? "text-zinc-500" : "text-zinc-400"} mr-1', [Component.text('Deposit:')]),
            Component.text('$depositMonths month(s)'),
          ]),
        if (totalCost > 0)
          div([
            span(classes: '${isDark ? "text-zinc-500" : "text-zinc-400"} mr-1', [Component.text('Total:')]),
            span(classes: 'font-bold text-emerald-400', [Component.text('₱${totalCost.toStringAsFixed(2)}')]),
          ]),
        if (completedAt != null)
          div([
            span(classes: '${isDark ? "text-zinc-500" : "text-zinc-400"} mr-1', [Component.text('Completed:')]),
            Component.text(_formatDate(completedAt)),
          ]),
      ]),

      // Counterparty
      _buildCounterpartySection(
        counterparty,
        myRole == 'host' ? 'renter' : 'host',
        isDark,
        item,
        myRole,
        counterpartyUid ?? '',
      ),
    ]);
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final myUid = s.userProfile?.uid ?? '';
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    // Apply filters
    final filtered = _historyItems.where((item) {
      if (_roleFilter != 'all') {
        final role = _roleLabel(item, myUid);
        if (role != _roleFilter) return false;
      }
      if (_kindFilter != 'all') {
        final kind = item['rentalKind']?.toString() ?? 'vehicle';
        if (kind != _kindFilter) return false;
      }
      return true;
    }).toList();

    // Filter chip builder
    Component filterChip(String label, String value, String current, void Function(String) onTap) {
      final active = value == current;
      return button(
        classes:
            'px-3.5 py-1.5 rounded-xl text-xs font-bold border transition-all cursor-pointer '
            '${active ? "logo-gradient text-white border-transparent" : (isDark ? "bg-zinc-900 border-zinc-700 text-zinc-400 hover:bg-zinc-800" : "bg-white border-zinc-300 text-zinc-500 hover:bg-zinc-50")}',
        events: {'click': (_) => setState(() => onTap(value))},
        [Component.text(label)],
      );
    }

    return div(classes: 'space-y-6', [
      // Filter bar
      div(classes: 'flex flex-wrap items-center gap-3', [
        div(classes: 'flex items-center gap-2', [
          span(classes: 'text-xs font-bold ${isDark ? "text-zinc-500" : "text-zinc-400"}', [Component.text('Role:')]),
          filterChip('All', 'all', _roleFilter, (v) => _roleFilter = v),
          filterChip('As Renter', 'renter', _roleFilter, (v) => _roleFilter = v),
          filterChip('As Host', 'host', _roleFilter, (v) => _roleFilter = v),
        ]),
        div(classes: 'w-px h-5 ${isDark ? "bg-zinc-700" : "bg-zinc-300"}', []),
        div(classes: 'flex items-center gap-2', [
          span(classes: 'text-xs font-bold ${isDark ? "text-zinc-500" : "text-zinc-400"}', [Component.text('Type:')]),
          filterChip('All', 'all', _kindFilter, (v) => _kindFilter = v),
          filterChip('Vehicles', 'vehicle', _kindFilter, (v) => _kindFilter = v),
          filterChip('Properties', 'property', _kindFilter, (v) => _kindFilter = v),
        ]),
        div(classes: 'ml-auto', [
          button(
            classes:
                'p-2 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-zinc-400 hover:bg-zinc-800" : "bg-white border-zinc-300 text-zinc-500 hover:bg-zinc-50"} transition-colors cursor-pointer',
            events: {'click': (_) => _loadHistory()},
            [lIcon('refresh-cw', cls: 'w-3.5 h-3.5')],
          ),
        ]),
      ]),

      // Loading state
      if (_isLoading)
        div(classes: 'space-y-4', [
          for (int i = 0; i < 3; i++)
            div(
              classes: 'h-48 rounded-2xl border $cardCls animate-pulse',
              [],
            ),
        ])
      // Empty state
      else if (filtered.isEmpty)
        div(
          classes: 'py-16 flex flex-col items-center justify-center text-center space-y-4',
          [
            div(
              classes: 'p-5 rounded-2xl ${isDark ? "bg-zinc-800" : "bg-zinc-100"}',
              [lIcon('clock', cls: 'w-10 h-10 ${isDark ? "text-zinc-600" : "text-zinc-400"}')],
            ),
            p(classes: 'font-bold text-lg ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
              Component.text('No rental history yet'),
            ]),
            p(classes: 'text-sm max-w-xs ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
              Component.text('Completed rentals will appear here — both as a renter and as a host.'),
            ]),
          ],
        )
      // History cards
      else
        div(classes: 'space-y-4', [
          for (final item in filtered)
            if ((item['rentalKind']?.toString() ?? 'vehicle') == 'vehicle')
              _buildVehicleHistoryCard(item, isDark, myUid)
            else
              _buildPropertyHistoryCard(item, isDark, myUid),
        ]),
    ]);
  }
}
