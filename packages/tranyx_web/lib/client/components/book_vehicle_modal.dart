import 'dart:async';
import 'package:web/web.dart' as web;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../components/map_container.dart';
import '../../services/map_interop.dart';
import 'contract_viewer.dart';

class BookVehicleModalComponent extends StatefulComponent {
  final TranyxAppState appState;
  const BookVehicleModalComponent({required this.appState, super.key});

  @override
  State<BookVehicleModalComponent> createState() => _BookVehicleModalState();
}

class _BookVehicleModalState extends State<BookVehicleModalComponent> {
  int _step = 1;
  String _selectedPackage = 'Daily'; // '12h', 'Daily', 'Weekly', 'Monthly'
  String _licenseNumber = '';
  int _quantity = 1;
  int _activeImageIndex = 0;
  String? _lastRentalId;
  bool _hireWithDriver = false;

  bool _isBooking = false;
  String? _error;

  // New features state
  String _rentalType = 'pickup'; // 'pickup' or 'deliver'
  String _deliveryAddress = '';
  double? _deliveryLat;
  double? _deliveryLng;
  // Map picker state for delivery
  static const _deliveryMapId = 'delivery-map-picker';
  bool _deliveryMapReady = false;
  bool _deliveryMapConfirming = false;
  bool _deliveryMapGeolocating = false;

  String _deliverySearchQuery = '';
  bool _deliveryIsSearching = false;
  List<Map<String, dynamic>> _deliverySearchResults = [];

  Future<void> _performDeliverySearch() async {
    final query = _deliverySearchQuery.trim();
    if (query.isEmpty) return;
    setState(() {
      _deliveryIsSearching = true;
      _deliverySearchResults = [];
    });
    try {
      final results = await searchAddress(query);
      setState(() {
        _deliverySearchResults = results;
      });
    } catch (e) {
      print('ERROR: delivery search failed: $e');
    } finally {
      setState(() {
        _deliveryIsSearching = false;
      });
    }
  }

  void _selectDeliverySearchResult(Map<String, dynamic> res) {
    final latStr = res['lat'] as String?;
    final lonStr = res['lon'] as String?;
    final displayName = res['display_name'] as String?;
    if (latStr != null && lonStr != null) {
      final lat = double.tryParse(latStr);
      final lng = double.tryParse(lonStr);
      if (lat != null && lng != null) {
        panTo(_deliveryMapId, lat, lng);
        setState(() {
          _deliverySearchResults = [];
          if (displayName != null) {
            _deliverySearchQuery = displayName;
          }
        });
      }
    }
  }

  DateTime? _startDate;
  List<Map<String, dynamic>> _approvedRequests = [];
  DateTime _calendarMonth = DateTime.now();

  double get _basePrice {
    final r = component.appState.selectedRentalData;
    if (r == null) return 0;

    switch (_selectedPackage) {
      case '12h':
        return ((r['price12h'] ?? r['halfDayRate']) as num?)?.toDouble() ?? 0;
      case 'Weekly':
        return ((r['priceWeekly'] ?? r['weeklyRate']) as num?)?.toDouble() ?? 0;
      case 'Monthly':
        return ((r['priceMonthly'] ?? r['monthlyRate']) as num?)?.toDouble() ?? 0;
      default:
        return ((r['priceDaily'] ?? r['dailyRate']) as num?)?.toDouble() ?? 0;
    }
  }

  double get _driverPrice {
    final r = component.appState.selectedRentalData;
    if (r == null || !_hireWithDriver) return 0;

    final offers = r['offersDriver'] as bool? ?? false;
    if (!offers) return 0;

    final driverDaily = (r['driverDailyPrice'] as num?)?.toDouble() ?? 0.0;
    double days = 1.0;
    if (_selectedPackage == '12h') {
      days = 0.5;
    } else if (_selectedPackage == 'Weekly') {
      days = 7.0;
    } else if (_selectedPackage == 'Monthly') {
      days = 30.0;
    } else {
      days = 1.0;
    }

    return driverDaily * days * _quantity;
  }

  double get _totalPrice {
    return (_basePrice * _quantity) + _driverPrice;
  }

  double get _bookingFee {
    return _totalPrice * 0.03; // 3% renter fee
  }

  DateTime get _computedEndDate {
    final start = _startDate ?? DateTime.now();
    switch (_selectedPackage) {
      case '12h':
        return start.add(Duration(hours: 12 * _quantity));
      case 'Weekly':
        return start.add(Duration(days: 7 * _quantity));
      case 'Monthly':
        return start.add(Duration(days: 30 * _quantity));
      default:
        return start.add(Duration(days: 1 * _quantity));
    }
  }

  bool get _hasBookingOverlap {
    if (_startDate == null) return false;
    final start = _startDate!.millisecondsSinceEpoch;
    final end = _computedEndDate.millisecondsSinceEpoch;
    for (final req in _approvedRequests) {
      final reqStart = req['startDate'] as int?;
      final reqEnd = req['endDate'] as int?;
      if (reqStart != null && reqEnd != null) {
        if (start < reqEnd && end > reqStart) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isDateBooked(DateTime date) {
    final startOfDayMs = DateTime(date.year, date.month, date.day, 0, 0, 0).millisecondsSinceEpoch;
    final endOfDayMs = DateTime(date.year, date.month, date.day, 23, 59, 59).millisecondsSinceEpoch;
    for (final req in _approvedRequests) {
      final start = req['startDate'] as int?;
      final end = req['endDate'] as int?;
      if (start != null && end != null) {
        if (endOfDayMs >= start && startOfDayMs <= end) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isDateInPast(DateTime date) {
    final today = DateTime.now();
    return DateTime(date.year, date.month, date.day).isBefore(DateTime(today.year, today.month, today.day));
  }

  List<DateTime?> _generateCalendarDays() {
    final year = _calendarMonth.year;
    final month = _calendarMonth.month;
    final firstDayOfMonth = DateTime(year, month, 1);
    final weekdayOfFirst = firstDayOfMonth.weekday; // 1 = Monday, 7 = Sunday
    final startOffset = weekdayOfFirst == 7 ? 0 : weekdayOfFirst;
    final daysInMonth = DateTime(year, month + 1, 0).day;

    final List<DateTime?> days = List.generate(startOffset, (_) => null);
    for (int d = 1; d <= daysInMonth; d++) {
      days.add(DateTime(year, month, d));
    }
    return days;
  }

  void _loadApprovedRequests(String rentalId) async {
    try {
      final reqs = await component.appState.firestore.getApprovedRequestsForVehicle(rentalId);
      if (mounted) {
        setState(() {
          _approvedRequests = reqs;
        });
      }
    } catch (_) {}
  }

  void _book() async {
    setState(() {
      _isBooking = true;
      _error = null;
    });

    try {
      final r = component.appState.selectedRentalData;
      if (r == null) throw Exception('No rental selected.');
      if (_licenseNumber.isEmpty) {
        setState(() => _error = 'Please provide your driver\'s license number.');
        return;
      }
      final cleanedLicense = _licenseNumber.replaceAll(RegExp(r'[\s-]'), '');
      if (cleanedLicense.length != 11) {
        setState(() => _error = 'Please enter a valid Driver\'s License Number (11 characters).');
        return;
      }
      final currentUid = component.appState.userProfile?.uid;
      if (currentUid == null) throw Exception('Not logged in');
      final user = component.appState.userProfile;
      if (user == null) throw Exception('User profile not loaded.');

      if (_startDate == null) {
        setState(() => _error = 'Please select a start date.');
        return;
      }

      if (_rentalType == 'deliver' && _deliveryAddress.trim().isEmpty) {
        setState(() => _error = 'Please pin your delivery address on the map.');
        return;
      }

      if (_hasBookingOverlap) {
        setState(() => _error = 'Selected dates overlap with an existing booking schedule.');
        return;
      }

      final totalRequired = _totalPrice + _bookingFee;
      if (user.tyxBalance < totalRequired) {
        component.appState.setState(() {
          component.appState.depositAmount = totalRequired - user.tyxBalance;
          component.appState.showDepositModal = true;
          component.appState.pendingVehicleBookingData = {
            'rentalId': r['id'],
            'durationType': _selectedPackage,
            'multiplier': _quantity,
            'licenseNumber': _licenseNumber,
            'totalCost': _totalPrice,
            'hireWithDriver': _hireWithDriver,
            'rentalType': _rentalType,
            'deliveryAddress': _rentalType == 'deliver' ? _deliveryAddress.trim() : null,
            'deliveryLat': _rentalType == 'deliver' ? _deliveryLat : null,
            'deliveryLng': _rentalType == 'deliver' ? _deliveryLng : null,
            'startDate': _startDate!.millisecondsSinceEpoch,
            'endDate': _computedEndDate.millisecondsSinceEpoch,
          };
          component.appState.showBookVehicleModal = false;
        });
        return;
      }

      // Submit booking request
      await component.appState.firestore.createBookingRequest(
        rentalId: r['id'],
        renteeId: currentUid,
        renteeName: user.name,
        renteePhotoUrl: user.photoUrl,
        durationType: _selectedPackage,
        multiplier: _quantity,
        licenseNumber: _licenseNumber,
        totalCost: _totalPrice,
        hireWithDriver: _hireWithDriver,
        rentalType: _rentalType,
        deliveryAddress: _rentalType == 'deliver' ? _deliveryAddress.trim() : null,
        deliveryLat: _rentalType == 'deliver' ? _deliveryLat : null,
        deliveryLng: _rentalType == 'deliver' ? _deliveryLng : null,
        startDate: _startDate!.millisecondsSinceEpoch,
        endDate: _computedEndDate.millisecondsSinceEpoch,
      );

      // Close modal
      component.appState.setState(() {
        component.appState.showBookVehicleModal = false;
        component.appState.selectedRentalData = null;
      });
      component.appState.loadRenterPendingRequests();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isBooking = false);
    }
  }

  @override
  Component build(BuildContext context) {
    if (!component.appState.showBookVehicleModal || component.appState.selectedRentalData == null) {
      return div([]);
    }

    final isDark = component.appState.isDark;
    final r = component.appState.selectedRentalData!;

    // Safety check: do not show / allow renting if it's the owner
    final currentUid = component.appState.userProfile?.uid;
    if (r['hostId'] != null && currentUid != null && r['hostId'] == currentUid) {
      return div([]);
    }

    // Reset modal states if the selected vehicle has changed
    final rentalId = r['id']?.toString();
    if (_lastRentalId != rentalId) {
      _lastRentalId = rentalId;
      _activeImageIndex = 0;
      _step = 1;
      _licenseNumber = '';
      _quantity = 1;
      _selectedPackage = 'Daily';
      _hireWithDriver = false;
      _rentalType = 'pickup';
      _deliveryAddress = '';
      _deliveryLat = null;
      _deliveryLng = null;
      _deliveryMapReady = false;
      _deliveryMapConfirming = false;
      _deliveryMapGeolocating = false;
      _deliverySearchQuery = '';
      _deliveryIsSearching = false;
      _deliverySearchResults = [];
      final now = DateTime.now();
      _startDate = DateTime(now.year, now.month, now.day, now.hour + 1, 0);
      _approvedRequests = [];
      _calendarMonth = DateTime.now();
      if (rentalId != null) {
        _loadApprovedRequests(rentalId);
        // Pre-init delivery map so it's ready when user picks 'deliver'
      }
    }

    final brand = r['brand'] ?? 'Unknown';
    final model = r['model'] ?? 'Unknown';
    final typeVal = r['type'] ?? r['vehicleType'];
    final fuelType = r['fuelType'] as String? ?? 'Gasoline';
    final transmission = r['transmission'] as String? ?? 'Automatic';
    String type = typeVal?.toString().split('.').last ?? '';
    if (type.toLowerCase() == 'null') type = '';

    return div(classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in', [
      div(
        classes:
            'w-full max-w-2xl max-h-[90vh] overflow-y-auto rounded-3xl shadow-2xl relative flex flex-col ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"}',
        [
          // Header
          div(
            classes:
                'sticky top-0 z-10 flex items-center justify-between p-6 border-b ${isDark ? "bg-zinc-900/90 border-zinc-800" : "bg-white/90 border-zinc-100"} backdrop-blur-md',
            [
              div([
                h2(classes: 'text-2xl font-bold', [Component.text('Book $brand $model')]),
                p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-500"} capitalize flex items-center gap-1.5', [
                  Component.text(type),
                  span([], classes: 'inline-block w-1 h-1 rounded-full bg-zinc-500'),
                  span(classes: 'px-2 py-0.5 rounded-lg text-xs font-bold bg-indigo-500/10 text-indigo-400 uppercase tracking-wide', [
                    Component.text(fuelType),
                  ]),
                  span([], classes: 'inline-block w-1 h-1 rounded-full bg-zinc-500'),
                  span(classes: 'px-2 py-0.5 rounded-lg text-xs font-bold bg-purple-500/10 text-purple-400 uppercase tracking-wide', [
                    Component.text(transmission),
                  ]),
                ]),
              ]),
              button(
                classes: 'p-2 rounded-full hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors',
                events: {
                  'click': (e) => component.appState.setState(() {
                    component.appState.showBookVehicleModal = false;
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

            if (_step == 1) ...[
              // Step 1: Packages and Details
              () {
                final front = r['frontPhotoUrl'] ?? r['frontPhoto'] ?? r['photoUrl'];
                final interior = r['interiorPhotoUrl'] ?? r['interiorPhoto'];
                final back = r['backPhotoUrl'] ?? r['backPhoto'];

                final List<String> images = [];
                if (front != null && front.toString().isNotEmpty && front.toString() != 'null') {
                  images.add(front.toString());
                }
                if (interior != null && interior.toString().isNotEmpty && interior.toString() != 'null') {
                  images.add(interior.toString());
                }
                if (back != null && back.toString().isNotEmpty && back.toString() != 'null') {
                  images.add(back.toString());
                }

                // Append extra photos uploaded by the host
                final extra = r['extraPhotos'];
                if (extra is List) {
                  for (final ep in extra) {
                    final s = ep?.toString() ?? '';
                    if (s.isNotEmpty && s != 'null') images.add(s);
                  }
                }

                return div(
                  classes:
                      'aspect-video w-full rounded-2xl overflow-hidden bg-zinc-800 flex items-center justify-center mb-6 relative group select-none',
                  [
                    if (images.isNotEmpty) ...[
                      img(
                        src: images[_activeImageIndex % images.length],
                        classes: 'w-full h-full object-cover transition-all duration-300',
                        attributes: {'alt': '$brand $model image'},
                      ),
                      // Gradient overlay
                      div(
                        classes: 'absolute inset-0 bg-gradient-to-t from-black/60 to-transparent pointer-events-none',
                        [],
                      ),

                      // Left arrow button
                      if (images.length > 1)
                        button(
                          classes:
                              'absolute left-4 top-1/2 -translate-y-1/2 p-2 rounded-full bg-black/40 hover:bg-black/60 text-white transition-colors backdrop-blur-[2px] cursor-pointer border-0 outline-none',
                          events: {
                            'click': (e) {
                              setState(() {
                                _activeImageIndex = (_activeImageIndex - 1 + images.length) % images.length;
                              });
                            },
                          },
                          [lIcon('chevron-left', cls: 'w-6 h-6')],
                        ),

                      // Right arrow button
                      if (images.length > 1)
                        button(
                          classes:
                              'absolute right-4 top-1/2 -translate-y-1/2 p-2 rounded-full bg-black/40 hover:bg-black/60 text-white transition-colors backdrop-blur-[2px] cursor-pointer border-0 outline-none',
                          events: {
                            'click': (e) {
                              setState(() {
                                _activeImageIndex = (_activeImageIndex + 1) % images.length;
                              });
                            },
                          },
                          [lIcon('chevron-right', cls: 'w-6 h-6')],
                        ),

                      // Indicator dots & label
                      div(
                        classes:
                            'absolute bottom-4 left-0 right-0 flex flex-col items-center gap-2 pointer-events-none',
                        [
                          if (images.length > 1)
                            div(classes: 'flex gap-1.5', [
                              for (int i = 0; i < images.length; i++)
                                div(
                                  classes:
                                      'h-1.5 rounded-full transition-all duration-300 ${i == (_activeImageIndex % images.length) ? "w-6 bg-purple-500" : "w-1.5 bg-white/55"}',
                                  [],
                                ),
                            ]),
                          p(classes: 'text-white text-xs font-semibold drop-shadow-sm', [
                            Component.text('${(_activeImageIndex % images.length) + 1} of ${images.length}'),
                          ]),
                        ],
                      ),
                    ] else ...[
                      lIcon('image', cls: 'w-12 h-12 text-zinc-600'),
                      div(
                        classes: 'absolute inset-0 bg-gradient-to-t from-black/80 to-transparent flex items-end p-4',
                        [
                          p(classes: 'text-white font-bold', [Component.text('No photos available')]),
                        ],
                      ),
                    ],
                  ],
                );
              }(),

              div(
                classes:
                    'grid grid-cols-3 gap-3 p-4 rounded-2xl border mb-6 '
                    '${isDark ? "border-zinc-800 bg-zinc-950/40" : "border-zinc-150 bg-zinc-50/50"}',
                [
                  _specItem('Engine Type', fuelType, 'zap', isDark),
                  _specItem('Year Model', '${r['year'] ?? 'N/A'}', 'calendar', isDark),
                  _specItem('Plate Number', _obscurePlateNumber(r['plateNumber']?.toString()), 'credit-card', isDark),
                ],
              ),

              h3(classes: 'text-lg font-bold mb-4', [Component.text('Select Rental Package')]),
              div(classes: 'grid grid-cols-2 gap-3', [
                _packageOption(
                  '12h',
                  '12 Hours',
                  ((r['price12h'] ?? r['halfDayRate']) as num?)?.toDouble() ?? 0,
                  isDark,
                ),
                _packageOption(
                  'Daily',
                  'Daily',
                  ((r['priceDaily'] ?? r['dailyRate']) as num?)?.toDouble() ?? 0,
                  isDark,
                ),
                _packageOption(
                  'Weekly',
                  'Weekly',
                  ((r['priceWeekly'] ?? r['weeklyRate']) as num?)?.toDouble() ?? 0,
                  isDark,
                ),
                _packageOption(
                  'Monthly',
                  'Monthly',
                  ((r['priceMonthly'] ?? r['monthlyRate']) as num?)?.toDouble() ?? 0,
                  isDark,
                ),
              ]),

              if (r['offersDriver'] == true) ...[
                div(
                  classes:
                      'mt-6 p-4 rounded-2xl border ${isDark ? "border-zinc-800 bg-zinc-950/40" : "border-zinc-200 bg-zinc-50/50"}',
                  [
                    div(classes: 'flex items-center justify-between mb-3', [
                      div([
                        h4(classes: 'font-bold text-sm flex items-center gap-1.5', [
                          lIcon('user', cls: 'w-4 h-4 text-purple-400'),
                          Component.text('Driver Service Available'),
                        ]),
                        p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"} mt-0.5', [
                          Component.text(
                            'Daily Driver Fee: ₱ ${((r['driverDailyPrice'] ?? 0) as num).toDouble().toStringAsFixed(2)}',
                          ),
                        ]),
                        p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-400"} mt-1 font-mono', [
                          Component.text('License: ${_obscureLicenseNumber(r['driverLicenseNumber']?.toString())}'),
                        ]),
                      ]),
                      input<bool>(
                        type: InputType.checkbox,
                        classes: 'rounded border-zinc-300 text-purple-600 focus:ring-purple-500 w-5 h-5 cursor-pointer',
                        checked: _hireWithDriver,
                        onChange: (val) => setState(() => _hireWithDriver = val),
                      ),
                    ]),
                    if (r['driverNote'] != null && r['driverNote'].toString().trim().isNotEmpty)
                      p(
                        classes:
                            'text-xs italic ${isDark ? "text-zinc-400" : "text-zinc-500"} border-t ${isDark ? "border-zinc-800" : "border-zinc-150"} pt-2 mt-2',
                        [Component.text('Driver Note: ${r['driverNote']}')],
                      ),
                  ],
                ),
              ],

              div(classes: 'mt-6', [
                label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Quantity (e.g. 2 Days, 3 Weeks)'),
                ]),
                input(
                  classes:
                      'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
                  type: InputType.number,
                  attributes: {'value': _quantity.toString(), 'min': '1'},
                  events: {'input': (e) => setState(() => _quantity = int.tryParse((e.target as web.HTMLInputElement).value) ?? 1)},
                ),
              ]),

              h3(classes: 'text-lg font-bold mb-3 mt-6', [Component.text('Delivery Method')]),
              div(classes: 'grid grid-cols-2 gap-3 mb-4', [
                button(
                  classes:
                      'py-3.5 rounded-2xl font-bold text-sm flex items-center justify-center gap-2.5 transition-all border-0 outline-none cursor-pointer '
                      '${_rentalType == 'pickup' ? "bg-purple-500 text-white shadow-lg shadow-purple-500/20" : (isDark ? "bg-zinc-800 text-zinc-300 hover:bg-zinc-700 border border-zinc-700" : "bg-zinc-150 text-zinc-700 hover:bg-zinc-200 border border-zinc-200")}',
                  events: {'click': (_) => setState(() => _rentalType = 'pickup')},
                  [
                    lIcon('map-pin', cls: 'w-4 h-4'),
                    Component.text('Self-Pickup'),
                  ],
                ),
                button(
                  classes:
                      'py-3.5 rounded-2xl font-bold text-sm flex items-center justify-center gap-2.5 transition-all border-0 outline-none cursor-pointer '
                      '${_rentalType == 'deliver' ? "bg-purple-500 text-white shadow-lg shadow-purple-500/20" : (isDark ? "bg-zinc-800 text-zinc-300 hover:bg-zinc-700 border border-zinc-700" : "bg-zinc-150 text-zinc-700 hover:bg-zinc-200 border border-zinc-200")}',
                  events: {'click': (_) => setState(() => _rentalType = 'deliver')},
                  [
                    lIcon('truck', cls: 'w-4 h-4'),
                    Component.text('Delivery'),
                  ],
                ),
              ]),

              if (_rentalType == 'pickup')
                div(
                  classes:
                      'p-4 rounded-xl border ${isDark ? "border-zinc-800 bg-zinc-950/40" : "border-zinc-200 bg-zinc-50/50"} mb-6 text-sm',
                  [
                    p(classes: 'font-semibold mb-1 flex items-center gap-1.5 text-zinc-400', [
                      lIcon('map-pin', cls: 'w-4 h-4 text-purple-400'),
                      Component.text('Vehicle Address'),
                    ]),
                    p(classes: 'font-medium', [Component.text('${r['pickupAddress'] ?? r['pickupLocation'] ?? 'Address not specified'}')]),
                  ],
                )
              else
                _deliveryMapPicker(isDark),

              _calendarGrid(isDark),

              div(classes: 'flex items-center gap-4 mt-4', [
                span(classes: 'text-sm font-semibold ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Start Time:'),
                ]),
                div(classes: 'flex gap-2 flex-1', [
                  () {
                    final now = DateTime.now();
                    final isToday =
                        _startDate != null &&
                        _startDate!.year == now.year &&
                        _startDate!.month == now.month &&
                        _startDate!.day == now.day;
                    final minHour = isToday ? now.hour + 1 : 0;

                    return select(
                      classes:
                          'p-2 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors flex-1',
                      events: {
                        'change': (e) {
                          if (_startDate != null) {
                            final hour = int.tryParse((e.target as web.HTMLSelectElement).value) ?? 9;
                            setState(() {
                              _startDate = DateTime(
                                _startDate!.year,
                                _startDate!.month,
                                _startDate!.day,
                                hour,
                                0,
                              );
                            });
                          }
                        },
                      },
                      [
                        for (int h = minHour; h < 24; h++)
                          option(
                            value: h.toString(),
                            attributes: (_startDate?.hour == h) ? {'selected': 'selected'} : {},
                            [Component.text('${h.toString().padLeft(2, '0')}:00')],
                          ),
                      ],
                    );
                  }(),
                ]),
              ]),

              div(
                classes:
                    'mt-4 p-4 rounded-xl ${isDark ? "bg-purple-950/20 text-purple-300" : "bg-purple-50 text-purple-800"} text-xs space-y-2',
                [
                  div(classes: 'flex justify-between', [
                    span([Component.text('Starts:')]),
                    span(classes: 'font-semibold', [Component.text(_formatDateTime(_startDate))]),
                  ]),
                  div(classes: 'flex justify-between', [
                    span([Component.text('Ends (Return):')]),
                    span(classes: 'font-semibold', [Component.text(_formatDateTime(_computedEndDate))]),
                  ]),
                  div([], classes: 'h-px bg-purple-500/20 my-1'),
                  p(classes: 'text-[10px] opacity-80 leading-relaxed italic', [
                    () {
                      if (_startDate == null) return Component.text('');
                      final lastUsageDay = _computedEndDate.subtract(const Duration(hours: 1));
                      final startFmt = '${_startDate!.day} ${_monthName(_startDate!.month).substring(0, 3)}';
                      final lastFmt = '${lastUsageDay.day} ${_monthName(lastUsageDay.month).substring(0, 3)}';
                      final endFmt = '${_computedEndDate.day} ${_monthName(_computedEndDate.month).substring(0, 3)}';
                      final timeStr = '${_computedEndDate.hour.toString().padLeft(2, '0')}:00';
                      
                      if (_selectedPackage == 'Daily') {
                        return Component.text(
                          '💡 Your $_quantity-day rental covers $startFmt, ${startFmt == lastFmt ? "" : "through to "}$lastFmt. '
                          'The vehicle is returned on $endFmt at $timeStr.'
                        );
                      }
                      return Component.text('💡 Highlighting the complete rental schedule on the calendar.');
                    }()
                  ]),
                ],
              ),
            ] else if (_step == 2) ...[
              // Step 2: Contract and Checkout
              h3(classes: 'text-lg font-bold mb-2', [
                Component.text(
                  r['contractType'] == 'Custom Contract'
                      ? 'Host\'s Custom Rental Agreement'
                      : 'Tranyx P2P Rental Agreement',
                ),
              ]),
              () {
                final previewVehicle = VehicleRental(
                  id: r['id'] ?? '',
                  hostId: r['hostId'] ?? '',
                  hostName: r['hostName'] ?? '',
                  hostPhotoUrl: r['hostPhotoUrl'],
                  brand: r['brand'] ?? '',
                  model: r['model'] ?? '',
                  year: r['year'] is int
                      ? r['year']
                      : int.tryParse(r['year']?.toString() ?? '') ?? 0,
                  type: () {
                    return VehicleType.values.firstWhere(
                      (e) => e.name == r['type'],
                      orElse: () => VehicleType.car,
                    );
                  }(),
                  plateNumber: r['plateNumber'] ?? '',
                  vehicleValue: (r['vehicleValue'] as num?)?.toDouble() ?? 0.0,
                  ltoCrNumber: r['ltoCrNumber'] ?? '',
                  ltoOrNumber: r['ltoOrNumber'] ?? '',
                  insuranceProvider: r['insuranceProvider'] ?? '',
                  insurancePolicyNumber: r['insurancePolicyNumber'] ?? '',
                  franchisePermit: r['franchisePermit'],
                  interiorPhotoUrl: r['interiorPhotoUrl'] ?? '',
                  frontPhotoUrl: r['frontPhotoUrl'] ?? '',
                  backPhotoUrl: r['backPhotoUrl'] ?? '',
                  contractType: r['contractType'] ?? 'tranyx',
                  contractTerms: r['contractTerms'] ?? '',
                  price12h: (r['price12h'] as num?)?.toDouble() ?? 0.0,
                  priceDaily: (r['priceDaily'] as num?)?.toDouble() ?? 0.0,
                  priceWeekly: (r['priceWeekly'] as num?)?.toDouble() ?? 0.0,
                  priceMonthly: (r['priceMonthly'] as num?)?.toDouble() ?? 0.0,
                  extensionRatePerHour: (r['extensionRatePerHour'] as num?)?.toDouble() ?? 0.0,
                  latePenaltyRatePerHour: (r['latePenaltyRatePerHour'] as num?)?.toDouble() ?? 0.0,
                  status: 'Pending',
                  fuelType: r['fuelType'] as String?,
                  transmission: r['transmission'] as String?,
                  offersDriver: r['offersDriver'] as bool? ?? false,
                  driverDailyPrice: (r['driverDailyPrice'] as num?)?.toDouble() ?? 0.0,
                  driverNote: r['driverNote'] ?? '',
                  driverLicenseNumber: r['driverLicenseNumber'] ?? '',
                  renteeId: component.appState.userProfile?.uid,
                  renteeName: component.appState.userProfile?.name,
                  renteePhotoUrl: component.appState.userProfile?.photoUrl,
                  renteeLicenseNumber: _licenseNumber.isNotEmpty ? _licenseNumber : null,
                  rentalDurationType: _selectedPackage.toLowerCase(),
                  rentalMultiplier: _quantity,
                  startDate: _startDate,
                  endDate: _computedEndDate,
                  totalCost: _totalPrice,
                  hireWithDriver: _hireWithDriver,
                  pickupAddress: r['pickupAddress'] ?? '',
                  pickupLat: (r['pickupLat'] as num?)?.toDouble() ?? 0.0,
                  pickupLng: (r['pickupLng'] as num?)?.toDouble() ?? 0.0,
                  createdAt: DateTime.now(),
                );
                return ContractViewerComponent(
                  vehicleRental: r['contractType'] == 'Custom Contract' ? null : previewVehicle,
                  customTerms: r['contractType'] == 'Custom Contract' ? r['contractTerms'] : null,
                  contractType: r['contractType'] as String?,
                );
              }(),

              div(classes: 'mb-6', [
                label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Driver\'s License Number'),
                ]),
                input(
                  classes:
                      'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors mb-4',
                  attributes: {'value': _licenseNumber, 'placeholder': 'e.g., N01-23-456789'},
                  events: {
                    'input': (e) {
                      final inputEl = e.target as web.HTMLInputElement;
                      final val = inputEl.value;
                      final formatted = _formatLicenseNumber(val);
                      inputEl.value = formatted;
                      setState(() => _licenseNumber = formatted);
                    },
                  },
                ),
              ]),

              div(classes: 'p-5 rounded-xl bg-purple-500/10 border border-purple-500/20 space-y-3', [
                div(classes: 'flex justify-between text-sm', [
                  span(classes: isDark ? 'text-zinc-400' : 'text-zinc-600', [
                    Component.text('$_quantity x $_selectedPackage Vehicle Rate'),
                  ]),
                  span(classes: 'font-bold', [Component.text('₱ ${(_basePrice * _quantity).toStringAsFixed(2)}')]),
                ]),
                if (_hireWithDriver)
                  div(classes: 'flex justify-between text-sm text-purple-400', [
                    span([Component.text('Driver Service (Included)')]),
                    span(classes: 'font-bold', [Component.text('₱ ${_driverPrice.toStringAsFixed(2)}')]),
                  ]),
                div(classes: 'flex justify-between text-sm', [
                  span(classes: isDark ? 'text-zinc-400' : 'text-zinc-600', [
                    Component.text('Platform Booking Fee (3%)'),
                  ]),
                  span(classes: 'font-bold text-purple-400', [Component.text('₱ ${_bookingFee.toStringAsFixed(2)}')]),
                ]),
                div(classes: 'h-px w-full bg-purple-500/20 my-2', []),
                div(classes: 'flex justify-between', [
                  span(classes: 'font-bold', [Component.text('Total Amount')]),
                  span(classes: 'font-black text-xl text-purple-400', [
                    Component.text('₱ ${(_totalPrice + _bookingFee).toStringAsFixed(2)}'),
                  ]),
                ]),
              ]),
            ],
          ]),

          // Footer
          div(classes: 'p-6 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center justify-between', [
            if (_step > 1)
              button(
                classes:
                    'px-6 py-2 rounded-xl font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-300 hover:bg-zinc-50"} transition-colors',
                events: {'click': (e) => setState(() => _step--)},
                [Component.text('Back')],
              )
            else
              div([]),

            if (_step < 2)
              button(
                classes:
                    'px-8 py-2 rounded-xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity border-0 outline-none cursor-pointer',
                events: {
                  'click': (e) {
                    if (_basePrice <= 0) {
                      setState(() => _error = 'Selected package is not available for this vehicle.');
                      return;
                    }
                    if (_startDate == null) {
                      setState(() => _error = 'Please select a start date on the calendar.');
                      return;
                    }
                    if (_rentalType == 'deliver' && _deliveryAddress.trim().isEmpty) {
                      setState(() => _error = 'Please pin your delivery address on the map.');
                      return;
                    }
                    if (_hasBookingOverlap) {
                      setState(
                        () => _error =
                            'The selected range overlaps with an existing booking schedule. Please select another date/time.',
                      );
                      return;
                    }
                    setState(() {
                      _error = null;
                      _step++;
                    });
                  },
                },
                [Component.text('Review Contract')],
              )
            else
              button(
                classes:
                    'px-8 py-2 rounded-xl font-bold text-white bg-green-500 hover:bg-green-600 transition-colors flex items-center gap-2 border-0 outline-none cursor-pointer',
                events: {'click': (e) => _book()},
                [
                  if (_isBooking) lIcon('loader', cls: 'w-4 h-4 animate-spin'),
                  Component.text(_isBooking ? 'Processing...' : 'Submit Request'),
                ],
              ),
          ]),
        ],
      ),
    ]);
  }

  /// Inline map picker for delivery address — single-point pan-to-confirm.
  Component _deliveryMapPicker(bool isDark) {
    return div(classes: 'mb-6', [
      label(
        classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}',
        [Component.text('Delivery Address')],
      ),
      p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"} mb-3', [
        lIcon('map-pin', cls: 'w-3.5 h-3.5 inline mr-1 text-purple-400'),
        Component.text('Pan the map to your location, then press Confirm.'),
      ]),
      // Map container
      div(
        classes:
            'relative w-full rounded-2xl overflow-hidden border ${isDark ? "border-zinc-700" : "border-zinc-200"} shadow-inner',
        styles: Styles(raw: {'height': '260px'}),
        [
          () {
            if (!_deliveryMapReady) {
              // Trigger map init
              Future.microtask(() async {
                await ensureMapLibreLoaded();
                await initMap(_deliveryMapId, 14.5995, 120.9842, 13, isDark: isDark);
                if (mounted) setState(() => _deliveryMapReady = true);
                await Future.delayed(const Duration(milliseconds: 600));
                invalidateMapSize(_deliveryMapId);
                final pos = await getCurrentPosition();
                if (pos != null && mounted) {
                  panTo(_deliveryMapId, pos.lat, pos.lng);
                  invalidateMapSize(_deliveryMapId);
                }
              });
            }
            return MapContainer(
              key: const ValueKey('delivery-map-picker'),
              id: _deliveryMapId,
              classes: 'w-full h-full ${isDark ? "theme-dark" : "theme-light"}',
              styles: Styles(
                raw: {
                  'z-index': '1',
                  'position': 'absolute !important',
                  'top': '0',
                  'left': '0',
                  'right': '0',
                  'bottom': '0',
                  'height': '100%',
                  'width': '100%',
                },
              ),
            );
          }(),
          // Address search overlay
          if (_deliveryMapReady)
            div(
              classes: 'absolute top-3 left-3 right-3 z-[1010] flex flex-col gap-1.5',
              [
                div(
                  classes:
                      'flex gap-2 p-1.5 rounded-xl border shadow-lg backdrop-blur-md '
                      '${isDark ? "bg-zinc-900/95 border-zinc-700/80" : "bg-white/95 border-zinc-200/80"}',
                  [
                    lIcon('search', cls: 'w-4 h-4 my-auto ml-2 ${isDark ? "text-zinc-400" : "text-zinc-500"}'),
                    input(
                      classes:
                          'flex-1 bg-transparent border-0 outline-none text-sm px-1 '
                          '${isDark ? "text-white placeholder-zinc-500" : "text-zinc-900 placeholder-zinc-400"}',
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Search address...',
                        'value': _deliverySearchQuery,
                      },
                      events: {
                        'input': (e) {
                          final val = (e.target as web.HTMLInputElement).value;
                          setState(() {
                            _deliverySearchQuery = val;
                            if (val.isEmpty) {
                              _deliverySearchResults = [];
                            }
                          });
                        },
                        'keydown': (e) {
                          final keyEvent = e as web.KeyboardEvent;
                          final key = keyEvent.key;
                          if (key == 'Enter') {
                            keyEvent.preventDefault();
                            _performDeliverySearch();
                          }
                        },
                      },
                    ),
                    if (_deliverySearchQuery.isNotEmpty)
                      button(
                        classes: 'p-1 rounded-md hover:bg-zinc-500/20 my-auto border-0 outline-none cursor-pointer',
                        events: {
                          'click': (_) {
                            setState(() {
                              _deliverySearchQuery = '';
                              _deliverySearchResults = [];
                            });
                          },
                        },
                        [
                          lIcon('x', cls: 'w-3.5 h-3.5 ${isDark ? "text-zinc-400" : "text-zinc-500"}'),
                        ],
                      ),
                    button(
                      classes:
                          'px-3 py-1.5 rounded-lg text-xs font-bold text-white bg-indigo-600 hover:bg-indigo-500 transition-colors flex items-center gap-1 border-0 outline-none cursor-pointer',
                      events: {
                        'click': (_) => _performDeliverySearch(),
                      },
                      [
                        if (_deliveryIsSearching) lIcon('loader-2', cls: 'w-3 h-3 animate-spin') else Component.text('Search'),
                      ],
                    ),
                  ],
                ),

                // Search Results dropdown
                if (_deliverySearchResults.isNotEmpty)
                  div(
                    classes:
                        'max-h-36 overflow-y-auto rounded-xl border shadow-xl flex flex-col divide-y '
                        '${isDark ? "bg-zinc-900 border-zinc-700 divide-zinc-800" : "bg-white border-zinc-200 divide-zinc-100"}',
                    _deliverySearchResults.map((res) {
                      final displayName = res['display_name'] as String? ?? '';
                      return button(
                        classes:
                            'px-4 py-2.5 text-left text-xs transition-colors hover:bg-indigo-600/10 '
                            '${isDark ? "text-zinc-300 hover:text-white" : "text-zinc-750 hover:text-zinc-900"} border-0 outline-none cursor-pointer',
                        events: {
                          'click': (_) => _selectDeliverySearchResult(res),
                        },
                        [Component.text(displayName)],
                      );
                    }).toList(),
                  ),
              ],
            ),
          // Loading overlay
          if (!_deliveryMapReady)
            div(
              classes:
                  'absolute inset-0 flex flex-col items-center justify-center gap-2 z-[400] '
                  '${isDark ? "bg-zinc-900" : "bg-zinc-50"}',
              [
                lIcon('loader-2', cls: 'w-7 h-7 animate-spin text-purple-500'),
                p(classes: 'text-xs font-semibold ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                  Component.text('Loading map…'),
                ]),
              ],
            ),
          // Center pin overlay
          div(
            classes:
                'absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-full pointer-events-none z-[1000]',
            [
              lIcon('map-pin', cls: 'w-8 h-8 drop-shadow-md text-purple-500'),
              div(
                classes:
                    'absolute bottom-0 left-1/2 transform -translate-x-1/2 translate-y-1 w-2 h-1 bg-black/30 rounded-full blur-[1px]',
                [],
              ),
            ],
          ),
        ],
      ),
      // Confirm button
      if (_deliveryMapReady) ...[
        button(
          classes:
              'w-full mt-3 py-3 rounded-xl font-bold flex items-center justify-center gap-2 transition-all '
              '${_deliveryMapConfirming ? "bg-zinc-700 text-zinc-400 cursor-not-allowed" : "bg-purple-600 hover:bg-purple-500 text-white shadow-lg shadow-purple-500/20"}',
          events: _deliveryMapConfirming
              ? {}
              : {
                  'click': (_) async {
                    setState(() => _deliveryMapConfirming = true);
                    final center = getMapCenter(_deliveryMapId);
                    if (center != null) {
                      final addr = await reverseGeocode(center.lat, center.lng);
                      if (mounted) {
                        setState(() {
                          _deliveryLat = center.lat;
                          _deliveryLng = center.lng;
                          _deliveryAddress = addr;
                          _deliveryMapConfirming = false;
                        });
                        setMarker(_deliveryMapId, 'delivery', center.lat, center.lng, '📍 Delivery: $addr');
                      }
                    } else {
                      setState(() => _deliveryMapConfirming = false);
                    }
                  },
                },
          [
            if (_deliveryMapConfirming) ...[
              lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
              Component.text('Confirming…'),
            ] else ...[
              lIcon('check-circle', cls: 'w-4 h-4'),
              Component.text('Confirm Delivery Location'),
            ],
          ],
        ),
      ],
      // Use my location button
      button(
        classes:
            'w-full mt-2 py-2.5 rounded-xl border text-sm font-medium flex items-center justify-center gap-2 '
            '${isDark ? "border-zinc-700 text-zinc-400 hover:bg-zinc-800" : "border-zinc-200 text-zinc-600 hover:bg-zinc-50"} transition-colors',
        events: _deliveryMapGeolocating
            ? {}
            : {
                'click': (_) async {
                  setState(() => _deliveryMapGeolocating = true);
                  final pos = await getCurrentPosition();
                  if (pos != null && mounted) {
                    panTo(_deliveryMapId, pos.lat, pos.lng);
                    invalidateMapSize(_deliveryMapId);
                  }
                  if (mounted) setState(() => _deliveryMapGeolocating = false);
                },
              },
        [
          if (_deliveryMapGeolocating)
            lIcon('loader-2', cls: 'w-4 h-4 animate-spin')
          else
            lIcon('navigation', cls: 'w-4 h-4'),
          Component.text('Pan to My Location'),
        ],
      ),
      // Confirmed address preview
      if (_deliveryAddress.isNotEmpty)
        div(
          classes: 'mt-3 p-3 rounded-xl border border-purple-500/30 bg-purple-500/10 flex items-start gap-3',
          [
            lIcon('map-pin', cls: 'w-4 h-4 text-purple-400 flex-shrink-0 mt-0.5'),
            div(classes: 'flex-1 min-w-0', [
              p(classes: 'text-xs font-bold text-purple-400 uppercase tracking-wide mb-0.5', [
                Component.text('Confirmed Delivery Address'),
              ]),
              p(classes: 'text-xs ${isDark ? "text-zinc-300" : "text-zinc-700"} break-words', [
                Component.text(_deliveryAddress),
              ]),
            ]),
            button(
              classes: 'p-1 rounded-full hover:bg-zinc-500/20 flex-shrink-0',
              events: {
                'click': (_) {
                  setState(() {
                    _deliveryAddress = '';
                    _deliveryLat = null;
                    _deliveryLng = null;
                  });
                  removeMarker(_deliveryMapId, 'delivery');
                },
              },
              [lIcon('x', cls: 'w-3.5 h-3.5 ${isDark ? "text-zinc-500" : "text-zinc-400"}')],
            ),
          ],
        ),
    ]);
  }

  Component _calendarGrid(bool isDark) {
    final days = _generateCalendarDays();
    final weekHeaders = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    final formatter = '${_monthName(_calendarMonth.month)} ${_calendarMonth.year}';

    return div(
      classes:
          'mt-6 p-4 rounded-2xl border ${isDark ? "border-zinc-800 bg-zinc-950/20" : "border-zinc-200 bg-zinc-50/30"}',
      [
        div(classes: 'flex items-center justify-between mb-4', [
          h4(classes: 'font-bold text-sm', [Component.text('Select Start Date & Schedule')]),
          div(classes: 'flex gap-2', [
            button(
              classes:
                  'p-1.5 rounded-lg border-0 cursor-pointer outline-none ${isDark ? "bg-zinc-850 hover:bg-zinc-800 text-zinc-300" : "bg-zinc-100 hover:bg-zinc-200 text-zinc-700"}',
              events: {
                'click': (_) => setState(() {
                  _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1, 1);
                }),
              },
              [lIcon('chevron-left', cls: 'w-4 h-4')],
            ),
            span(classes: 'text-sm font-semibold min-w-[100px] text-center', [Component.text(formatter)]),
            button(
              classes:
                  'p-1.5 rounded-lg border-0 cursor-pointer outline-none ${isDark ? "bg-zinc-850 hover:bg-zinc-800 text-zinc-300" : "bg-zinc-100 hover:bg-zinc-200 text-zinc-700"}',
              events: {
                'click': (_) => setState(() {
                  _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1);
                }),
              },
              [lIcon('chevron-right', cls: 'w-4 h-4')],
            ),
          ]),
        ]),
        // Weeks Header
        div(classes: 'grid grid-cols-7 gap-1 text-center text-xs font-semibold text-zinc-400 mb-2', [
          for (final wh in weekHeaders) div([Component.text(wh)]),
        ]),
        // Days Grid
        div(classes: 'grid grid-cols-7 gap-1', [
          for (final day in days)
            if (day == null)
              div([])
            else
              () {
                final isBooked = _isDateBooked(day);
                final isPast = _isDateInPast(day);
                final isSelectedStart =
                    _startDate != null &&
                    _startDate!.year == day.year &&
                    _startDate!.month == day.month &&
                    _startDate!.day == day.day;

                final endRange = _computedEndDate;
                final isInRange =
                    _startDate != null &&
                    day.isAfter(_startDate!) &&
                    day.isBefore(DateTime(endRange.year, endRange.month, endRange.day, 23, 59, 59));

                final isEndRange =
                    _startDate != null &&
                    endRange.year == day.year &&
                    endRange.month == day.month &&
                    endRange.day == day.day;

                String bgClass = '';
                String textClass = '';
                bool clickable = true;

                if (isPast) {
                  bgClass = 'bg-transparent opacity-30';
                  textClass = isDark ? 'text-zinc-650' : 'text-zinc-300';
                  clickable = false;
                } else if (isBooked) {
                  bgClass = isDark ? 'bg-red-500/10 border border-red-500/20' : 'bg-red-50 border border-red-100';
                  textClass = 'text-red-500';
                  clickable = false;
                } else if (isSelectedStart) {
                  bgClass = 'bg-purple-500 text-white font-bold rounded-xl';
                } else if (isEndRange) {
                  bgClass = 'bg-purple-500 text-white font-bold rounded-xl';
                } else if (isInRange) {
                  bgClass = isDark ? 'bg-purple-500/20 text-purple-300' : 'bg-purple-50 text-purple-700';
                } else {
                  bgClass = isDark ? 'hover:bg-zinc-800' : 'hover:bg-zinc-100';
                  textClass = isDark ? 'text-zinc-200' : 'text-zinc-800';
                }

                return button(
                  classes:
                      'aspect-square flex items-center justify-center text-xs rounded-xl transition-all border-0 outline-none $bgClass $textClass ${clickable ? "cursor-pointer" : "cursor-not-allowed"}',
                  attributes: clickable ? {} : {'disabled': 'disabled'},
                  events: clickable
                      ? {
                          'click': (_) => setState(() {
                            final now = DateTime.now();
                            if (_startDate == null || day.isBefore(_startDate!)) {
                              int hour = _startDate?.hour ?? (now.hour + 1);
                              final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
                              if (isToday && hour <= now.hour) {
                                hour = now.hour + 1;
                              }
                              if (hour > 23) {
                                final tomorrow = day.add(const Duration(days: 1));
                                _startDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 0, 0);
                              } else {
                                _startDate = DateTime(day.year, day.month, day.day, hour, 0);
                              }
                            } else {
                              final diff = day.difference(DateTime(_startDate!.year, _startDate!.month, _startDate!.day));
                              int newQty = 1;
                              switch (_selectedPackage) {
                                case '12h':
                                  newQty = (diff.inHours / 12).round();
                                  break;
                                case 'Weekly':
                                  newQty = (diff.inDays / 7).round();
                                  break;
                                case 'Monthly':
                                  newQty = (diff.inDays / 30).round();
                                  break;
                                default: // 'Daily'
                                  newQty = diff.inDays;
                                  break;
                              }
                              _quantity = newQty.clamp(1, 999);
                            }
                          }),
                        }
                      : {},
                  [Component.text('${day.day}')],
                );
              }(),
        ]),
      ],
    );
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Not selected';
    return '${dt.day} ${_monthName(dt.month).substring(0, 3)} ${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:00';
  }

  Component _packageOption(String id, String labelText, double price, bool isDark) {
    final isSelected = _selectedPackage == id;
    return div(
      classes:
          'p-4 rounded-xl border-2 cursor-pointer transition-all ${isSelected ? "border-purple-500 bg-purple-500/10" : (isDark ? "border-zinc-800 hover:border-zinc-700 bg-zinc-800/30" : "border-zinc-200 hover:border-zinc-300 bg-zinc-50")}',
      events: {'click': (_) => setState(() => _selectedPackage = id)},
      [
        p(classes: 'font-semibold mb-1 ${isSelected ? "text-purple-400" : ""}', [Component.text(labelText)]),
        p(classes: 'font-bold text-lg', [
          if (price > 0)
            Component.text('₱ ${price.toStringAsFixed(0)}')
          else
            span(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-400"}', [Component.text('Not Available')]),
        ]),
      ],
    );
  }

  String _formatLicenseNumber(String val) {
    final cleaned = val.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.length > 11) {
      final limited = cleaned.substring(0, 11);
      return _insertLicenseHyphens(limited);
    }
    return _insertLicenseHyphens(cleaned);
  }

  String _insertLicenseHyphens(String val) {
    if (val.length <= 3) return val;
    if (val.length <= 5) {
      return '${val.substring(0, 3)}-${val.substring(3)}';
    }
    return '${val.substring(0, 3)}-${val.substring(3, 5)}-${val.substring(5)}';
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

  Component _specItem(String labelText, String val, String icon, bool isDark) {
    return div(classes: 'flex flex-col items-center text-center p-2 rounded-xl ${isDark ? "bg-zinc-900/50" : "bg-white"} border ${isDark ? "border-zinc-800/80" : "border-zinc-200/50"}', [
      lIcon(icon, cls: 'w-4 h-4 text-purple-400 mb-1'),
      span(classes: 'text-[9px] font-medium ${isDark ? "text-zinc-500" : "text-zinc-450"} uppercase tracking-wider', [Component.text(labelText)]),
      span(classes: 'text-xs font-bold ${isDark ? "text-zinc-250" : "text-zinc-800"} mt-0.5 capitalize', [Component.text(val)]),
    ]);
  }

  String _obscurePlateNumber(String? plate) {
    if (plate == null || plate.isEmpty) return 'N/A';
    final clean = plate.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (clean.length <= 4) return '***';
    final visibleStart = clean.substring(0, 2);
    final visibleEnd = clean.substring(clean.length - 2);
    return '$visibleStart***$visibleEnd';
  }
}
