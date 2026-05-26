import 'package:web/web.dart' as web;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
import 'contract_viewer.dart';

class BookPropertyModalComponent extends StatefulComponent {
  final TranyxAppState appState;
  const BookPropertyModalComponent({required this.appState, super.key});

  @override
  State<BookPropertyModalComponent> createState() => _BookPropertyModalState();
}

class _BookPropertyModalState extends State<BookPropertyModalComponent> {
  int _step = 1;
  String _selectedDurationType = 'Monthly'; // 'Monthly', 'Weekly', 'Daily'
  int _multiplier = 1;
  String _licenseNumber = '';
  int _activeImageIndex = 0;
  String? _lastPropertyId;

  bool _isBooking = false;
  String? _error;

  double get _basePrice {
    final p = component.appState.selectedPropertyData;
    if (p == null) return 0;

    switch (_selectedDurationType) {
      case 'Weekly':
        return ((p['priceWeekly'] ?? 0) as num).toDouble();
      case 'Daily':
        return ((p['priceDaily'] ?? 0) as num).toDouble();
      default:
        return ((p['priceMonthly'] ?? 0) as num).toDouble();
    }
  }

  int get _depositMonths {
    final p = component.appState.selectedPropertyData;
    if (p == null) return 0;
    return ((p['depositMonths'] ?? 0) as num).toInt();
  }

  double get _totalRent {
    return _basePrice * _multiplier;
  }

  double get _depositAmount {
    final p = component.appState.selectedPropertyData;
    if (p == null) return 0;
    final customAmt = p['securityDepositAmount'] as num?;
    if (customAmt != null) {
      return customAmt.toDouble();
    }
    final monthlyRent = ((p['priceMonthly'] ?? 0) as num).toDouble();
    return monthlyRent * _depositMonths;
  }

  double get _advanceAmount {
    final p = component.appState.selectedPropertyData;
    if (p == null) return 0;
    final customAmt = p['advanceAmount'] as num?;
    return customAmt?.toDouble() ?? 0.0;
  }

  double get _totalPrice {
    return _totalRent + _depositAmount + _advanceAmount;
  }

  double get _bookingFee {
    return _totalPrice * 0.03; // 3% renter fee
  }

  DateTime get _computedEndDate {
    final start = DateTime.now();
    switch (_selectedDurationType) {
      case 'Weekly':
        return start.add(Duration(days: 7 * _multiplier));
      case 'Daily':
        return start.add(Duration(days: 1 * _multiplier));
      default:
        return start.add(Duration(days: 30 * _multiplier));
    }
  }

  void _book() async {
    setState(() {
      _isBooking = true;
      _error = null;
    });

    try {
      final p = component.appState.selectedPropertyData;
      if (p == null) throw Exception('No property selected.');
      if (_licenseNumber.trim().isEmpty) {
        setState(() => _error = 'Please enter your government ID / Driver\'s License number for verification.');
        return;
      }

      final currentUid = component.appState.userProfile?.uid;
      if (currentUid == null) throw Exception('Not logged in');
      final user = component.appState.userProfile;
      if (user == null) throw Exception('User profile not loaded.');

      final now = DateTime.now();
      final end = _computedEndDate;

      final totalRequired = _totalPrice + _bookingFee;
      if (user.tyxBalance < totalRequired) {
        component.appState.setState(() {
          component.appState.depositAmount = totalRequired - user.tyxBalance;
          component.appState.showDepositModal = true;
          component.appState.pendingPropertyBookingData = {
            'propertyId': p['id'],
            'durationType': _selectedDurationType,
            'multiplier': _multiplier,
            'totalCost': _totalPrice,
            'contractType': p['contractType'] ?? 'Tranyx Standard',
            'contractTerms': p['contractTerms'] ?? 'Standard lease terms',
            'startDate': now.millisecondsSinceEpoch,
            'endDate': end.millisecondsSinceEpoch,
          };
          component.appState.showBookPropertyModal = false;
        });
        return;
      }

      // Submit booking request
      await component.appState.firestore.createPropertyBookingRequest(
        propertyId: p['id'],
        renteeId: currentUid,
        renteeName: user.name,
        renteePhotoUrl: user.photoUrl,
        durationType: _selectedDurationType,
        multiplier: _multiplier,
        totalCost: _totalPrice,
        contractType: p['contractType'] ?? 'Tranyx Standard',
        contractTerms: p['contractTerms'] ?? 'Standard lease terms',
        startDate: now.millisecondsSinceEpoch,
        endDate: end.millisecondsSinceEpoch,
      );

      // Close modal
      component.appState.setState(() {
        component.appState.showBookPropertyModal = false;
        component.appState.selectedPropertyData = null;
      });
      // Optionally reload requests
      if (component.appState.activeTab == AppTab.transit) {
        // Trigger transit view pending requests reload
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isBooking = false);
    }
  }

  @override
  Component build(BuildContext context) {
    if (!component.appState.showBookPropertyModal || component.appState.selectedPropertyData == null) {
      return div([]);
    }

    final isDark = component.appState.isDark;
    final pData = component.appState.selectedPropertyData!;

    final currentUid = component.appState.userProfile?.uid;
    if (pData['hostId'] != null && currentUid != null && pData['hostId'] == currentUid) {
      return div([]);
    }

    final propertyId = pData['id']?.toString();
    if (_lastPropertyId != propertyId) {
      _lastPropertyId = propertyId;
      _activeImageIndex = 0;
      _step = 1;
      _licenseNumber = '';
      _multiplier = 1;
      _selectedDurationType = 'Monthly';
    }

    final title = pData['title'] ?? 'Unknown Property';
    final desc = pData['description'] ?? '';
    final address = pData['address'] ?? 'No address provided';
    final pTypeStr = pData['type'] ?? 'house';
    final categoryStr = pData['category'] ?? 'residential';
    final amenities = (pData['amenities'] as List?)?.map((e) => e.toString()).toList() ?? [];

    final photos = (pData['photoUrls'] as List?)?.map((e) => e.toString()).toList() ?? [];

    final modalCls = isDark ? 'bg-zinc-900 border border-zinc-800 text-white' : 'bg-white text-zinc-900 shadow-xl';

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-2xl max-h-[90vh] overflow-y-auto rounded-3xl shadow-2xl relative flex flex-col $modalCls',
          [
            // Header
            div(
              classes:
                  'sticky top-0 z-10 flex items-center justify-between p-6 border-b ${isDark ? "bg-zinc-900/90 border-zinc-800" : "bg-white/90 border-zinc-100"} backdrop-blur-md',
              [
                div([
                  h2(classes: 'text-2xl font-bold', [Component.text('Rent Property')]),
                  p(classes: 'text-xs text-zinc-500', [Component.text('$title • $categoryStr $pTypeStr')]),
                ]),
                button(
                  classes: 'p-2 rounded-full hover:bg-zinc-105 dark:hover:bg-zinc-800 transition-colors',
                  events: {
                    'click': (_) => component.appState.setState(() {
                      component.appState.showBookPropertyModal = false;
                      component.appState.selectedPropertyData = null;
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
                // Image slider
                div(
                  classes:
                      'aspect-video w-full rounded-2xl overflow-hidden bg-zinc-800 flex items-center justify-center mb-6 relative group select-none',
                  [
                    if (photos.isNotEmpty) ...[
                      img(
                        src: photos[_activeImageIndex % photos.length],
                        classes: 'w-full h-full object-cover transition-all duration-300',
                        attributes: {'alt': 'Property interior/exterior'},
                      ),
                      div(
                        classes: 'absolute inset-0 bg-gradient-to-t from-black/60 to-transparent pointer-events-none',
                        [],
                      ),
                      if (photos.length > 1)
                        button(
                          classes:
                              'absolute left-4 top-1/2 -translate-y-1/2 p-2 rounded-full bg-black/40 hover:bg-black/60 text-white transition-colors backdrop-blur-[2px] cursor-pointer border-0 outline-none',
                          events: {
                            'click': (_) => setState(
                              () => _activeImageIndex = (_activeImageIndex - 1 + photos.length) % photos.length,
                            ),
                          },
                          [lIcon('chevron-left', cls: 'w-6 h-6')],
                        ),
                      if (photos.length > 1)
                        button(
                          classes:
                              'absolute right-4 top-1/2 -translate-y-1/2 p-2 rounded-full bg-black/40 hover:bg-black/60 text-white transition-colors backdrop-blur-[2px] cursor-pointer border-0 outline-none',
                          events: {
                            'click': (_) => setState(() => _activeImageIndex = (_activeImageIndex + 1) % photos.length),
                          },
                          [lIcon('chevron-right', cls: 'w-6 h-6')],
                        ),
                      div(
                        classes:
                            'absolute bottom-4 left-0 right-0 flex flex-col items-center gap-2 pointer-events-none',
                        [
                          if (photos.length > 1)
                            div(classes: 'flex gap-1.5', [
                              for (int i = 0; i < photos.length; i++)
                                div(
                                  classes:
                                      'h-1.5 rounded-full transition-all duration-300 ${i == (_activeImageIndex % photos.length) ? "w-6 bg-purple-500" : "w-1.5 bg-white/55"}',
                                  [],
                                ),
                            ]),
                          p(classes: 'text-white text-xs font-semibold drop-shadow-sm', [
                            Component.text('${(_activeImageIndex % photos.length) + 1} of ${photos.length}'),
                          ]),
                        ],
                      ),
                    ] else ...[
                      lIcon('image', cls: 'w-12 h-12 text-zinc-650'),
                    ],
                  ],
                ),

                // Specifications details
                div([
                  h3(classes: 'text-lg font-bold mb-2', [Component.text('About this Space')]),
                  p(classes: 'text-sm ${isDark ? "text-zinc-300" : "text-zinc-600"} leading-relaxed', [
                    Component.text(desc),
                  ]),
                ]),

                if (amenities.isNotEmpty)
                  div([
                    h3(classes: 'text-sm font-bold text-zinc-400 uppercase tracking-wider mb-3', [
                      Component.text('Amenities'),
                    ]),
                    div(classes: 'grid grid-cols-2 md:grid-cols-3 gap-2.5', [
                      for (final a in amenities)
                        div(
                          classes:
                              'flex items-center gap-2 text-xs p-2.5 rounded-xl border ${isDark ? "border-zinc-800 bg-zinc-900/40 text-zinc-300" : "border-zinc-200 bg-zinc-50 text-zinc-700"}',
                          [
                            lIcon(
                              a == 'WiFi'
                                  ? 'wifi'
                                  : a == 'Aircon'
                                  ? 'wind'
                                  : a == 'Parking'
                                  ? 'car'
                                  : a == 'Furnished'
                                  ? 'armchair'
                                  : a == 'Gym'
                                  ? 'dumbbell'
                                  : 'waves',
                              cls: 'w-4 h-4 text-purple-400',
                            ),
                            span([Component.text(a)]),
                          ],
                        ),
                    ]),
                  ]),

                div(classes: 'flex items-start gap-2.5 text-xs text-zinc-500', [
                  lIcon('map-pin', cls: 'w-4 h-4 text-purple-400 shrink-0'),
                  span([Component.text(address)]),
                ]),

                h3(classes: 'text-lg font-bold mb-3', [Component.text('Rental Period')]),
                div(classes: 'grid grid-cols-3 gap-3 mb-4', [
                  _packageOption('Monthly', 'Monthly Rate', ((pData['priceMonthly'] ?? 0) as num).toDouble(), isDark),
                  _packageOption('Weekly', 'Weekly Rate', ((pData['priceWeekly'] ?? 0) as num).toDouble(), isDark),
                  _packageOption('Daily', 'Daily Rate', ((pData['priceDaily'] ?? 0) as num).toDouble(), isDark),
                ]),

                div(
                  classes:
                      'flex items-center justify-between p-4 rounded-xl border ${isDark ? "border-zinc-800 bg-zinc-950" : "border-zinc-200 bg-zinc-50"}',
                  [
                    div([
                      p(classes: 'font-bold text-sm', [Component.text('Duration of Stay')]),
                      p(classes: 'text-xs text-zinc-500', [Component.text('Enter multiplier for the selected rate')]),
                    ]),
                    div(classes: 'flex items-center gap-3', [
                      button(
                        classes:
                            'w-8 h-8 rounded-full border flex items-center justify-center font-bold text-lg hover:bg-zinc-800/20 cursor-pointer',
                        events: {
                          'click': (_) => setState(() {
                            if (_multiplier > 1) _multiplier--;
                          }),
                        },
                        [Component.text('-')],
                      ),
                      span(classes: 'font-bold text-lg w-6 text-center', [Component.text('$_multiplier')]),
                      button(
                        classes:
                            'w-8 h-8 rounded-full border flex items-center justify-center font-bold text-lg hover:bg-zinc-800/20 cursor-pointer',
                        events: {'click': (_) => setState(() => _multiplier++)},
                        [Component.text('+')],
                      ),
                    ]),
                  ],
                ),

                div(
                  classes:
                      'mt-4 p-4 rounded-xl ${isDark ? "bg-purple-950/20 text-purple-300" : "bg-purple-50 text-purple-800"} text-xs flex justify-between',
                  [
                    span([Component.text('Lease Timeline:')]),
                    span(classes: 'font-bold', [
                      Component.text(
                        '${DateTime.now().toString().substring(0, 10)} to ${_computedEndDate.toString().substring(0, 10)}',
                      ),
                    ]),
                  ],
                ),

                // Move-in cost summary banner (shows when advance or deposit > 0)
                Builder(
                  builder: (context) {
                    final hasAdvance = _advanceAmount > 0;
                    final hasDeposit = _depositAmount > 0;
                    if (!hasAdvance && !hasDeposit) return div([]);
                    return div(
                      classes:
                          'mt-3 p-4 rounded-xl border ${isDark ? "border-amber-500/20 bg-amber-500/5" : "border-amber-400/30 bg-amber-50"} space-y-2',
                      [
                        div(classes: 'flex items-center gap-2 mb-2', [
                          lIcon('info', cls: 'w-3.5 h-3.5 text-amber-500'),
                          p(classes: 'text-xs font-bold text-amber-500', [
                            Component.text('Move-in Requirements by Owner'),
                          ]),
                        ]),
                        if (hasAdvance)
                          div(classes: 'flex items-center justify-between text-xs', [
                            div(classes: 'flex items-center gap-1.5 ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                              lIcon('calendar-check', cls: 'w-3 h-3 text-indigo-400'),
                              Component.text('Advance Payment'),
                            ]),
                            span(classes: 'font-bold text-indigo-400', [
                              Component.text('₱ ${_advanceAmount.toStringAsFixed(2)}'),
                            ]),
                          ]),
                        if (hasDeposit)
                          div(classes: 'flex items-center justify-between text-xs', [
                            div(classes: 'flex items-center gap-1.5 ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                              lIcon('shield-check', cls: 'w-3 h-3 text-purple-400'),
                              Component.text('Security Deposit (refundable)'),
                            ]),
                            span(classes: 'font-bold text-purple-400', [
                              Component.text('₱ ${_depositAmount.toStringAsFixed(2)}'),
                            ]),
                          ]),
                        div(classes: 'h-px ${isDark ? "bg-amber-500/10" : "bg-amber-200"} my-1', []),
                        div(classes: 'flex items-center justify-between text-xs font-bold', [
                          span(classes: '${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                            Component.text('Move-in Total (excl. rent)'),
                          ]),
                          span(classes: 'text-amber-500', [
                            Component.text('₱ ${(_advanceAmount + _depositAmount).toStringAsFixed(2)}'),
                          ]),
                        ]),
                      ],
                    );
                  },
                ),
              ] else if (_step == 2) ...[
                // Step 2: Contract & Payment Review
                h3(classes: 'text-lg font-bold mb-2', [
                  Component.text(
                    pData['contractType'] == 'Custom Contract'
                        ? 'Owner\'s Custom Lease Terms'
                        : 'Tranyx Standard Lease Agreement',
                  ),
                ]),
                () {
                  final baseProperty = PropertyRental.fromMap(pData, pData['id'] ?? '');
                  final previewProperty = PropertyRental(
                    id: baseProperty.id,
                    hostId: baseProperty.hostId,
                    hostName: baseProperty.hostName,
                    hostPhotoUrl: baseProperty.hostPhotoUrl,
                    title: baseProperty.title,
                    description: baseProperty.description,
                    type: baseProperty.type,
                    category: baseProperty.category,
                    priceMonthly: baseProperty.priceMonthly,
                    priceWeekly: baseProperty.priceWeekly,
                    priceDaily: baseProperty.priceDaily,
                    depositMonths: baseProperty.depositMonths,
                    address: baseProperty.address,
                    latitude: baseProperty.latitude,
                    longitude: baseProperty.longitude,
                    photoUrls: baseProperty.photoUrls,
                    amenities: baseProperty.amenities,
                    status: baseProperty.status,
                    contractType: baseProperty.contractType,
                    contractTerms: baseProperty.contractTerms,
                    createdAt: baseProperty.createdAt,
                    allowChat: baseProperty.allowChat,
                    renteeName: component.appState.userProfile?.name,
                    renteePhotoUrl: component.appState.userProfile?.photoUrl,
                    renteeLicenseNumber: _licenseNumber.isNotEmpty ? _licenseNumber : null,
                    rentalDurationType: _selectedDurationType,
                    rentalMultiplier: _multiplier,
                    totalCost: _totalPrice,
                    renteeSignatureName: null,
                    signedAt: null,
                  );
                  return ContractViewerComponent(
                    propertyRental: pData['contractType'] == 'Custom Contract' ? null : previewProperty,
                    customTerms: pData['contractType'] == 'Custom Contract' ? pData['contractTerms'] : null,
                    contractType: pData['contractType'] as String?,
                  );
                }(),

                div(classes: 'mb-6', [
                  label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                    Component.text('Government ID / Driver\'s License Number'),
                  ]),
                  input(
                    classes:
                        'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors mb-4',
                    attributes: {'value': _licenseNumber, 'placeholder': 'e.g. Passport, License, or UMID number'},
                    events: {'input': (e) => setState(() => _licenseNumber = (e.target as web.HTMLInputElement).value)},
                  ),
                ]),

                div(classes: 'p-5 rounded-xl bg-purple-500/10 border border-purple-500/20 space-y-3', [
                  // Header
                  p(classes: 'text-xs font-bold uppercase tracking-wider text-purple-400 mb-1', [
                    Component.text('Move-in Cost Breakdown'),
                  ]),
                  // Rental cost
                  div(classes: 'flex justify-between text-sm', [
                    span(classes: isDark ? 'text-zinc-400' : 'text-zinc-650', [
                      Component.text('$_multiplier × $_selectedDurationType Rental'),
                    ]),
                    span(classes: 'font-bold', [Component.text('₱ ${_totalRent.toStringAsFixed(2)}')]),
                  ]),
                  // Advance payment
                  if (_advanceAmount > 0) ...[
                    div(classes: 'flex justify-between text-sm', [
                      div(classes: 'flex items-center gap-1.5', [
                        lIcon('calendar-check', cls: 'w-3.5 h-3.5 text-indigo-400'),
                        span(classes: isDark ? 'text-zinc-400' : 'text-zinc-650', [
                          Component.text('Advance Payment'),
                        ]),
                      ]),
                      span(classes: 'font-bold text-indigo-400', [
                        Component.text('₱ ${_advanceAmount.toStringAsFixed(2)}'),
                      ]),
                    ]),
                    p(classes: 'text-[10px] ${isDark ? "text-zinc-600" : "text-zinc-400"} -mt-1 ml-5', [
                      Component.text("Applied to first month's rent upon move-in"),
                    ]),
                  ],
                  // Security deposit
                  if (_depositAmount > 0) ...[
                    div(classes: 'flex justify-between text-sm', [
                      div(classes: 'flex items-center gap-1.5', [
                        lIcon('shield-check', cls: 'w-3.5 h-3.5 text-purple-400'),
                        span(classes: isDark ? 'text-zinc-400' : 'text-zinc-650', [
                          Component.text('Security Deposit'),
                        ]),
                      ]),
                      span(classes: 'font-bold text-purple-400', [
                        Component.text('₱ ${_depositAmount.toStringAsFixed(2)}'),
                      ]),
                    ]),
                    p(classes: 'text-[10px] ${isDark ? "text-zinc-600" : "text-zinc-400"} -mt-1 ml-5', [
                      Component.text('Fully refundable at end of lease'),
                    ]),
                  ],
                  // Platform fee
                  div(classes: 'flex justify-between text-sm', [
                    div(classes: 'flex items-center gap-1.5', [
                      lIcon('percent', cls: 'w-3.5 h-3.5 text-zinc-400'),
                      span(classes: isDark ? 'text-zinc-400' : 'text-zinc-600', [
                        Component.text('Platform Service Fee (3%)'),
                      ]),
                    ]),
                    span(classes: 'font-bold text-zinc-400', [Component.text('₱ ${_bookingFee.toStringAsFixed(2)}')]),
                  ]),
                  // Divider
                  div(classes: 'h-px w-full bg-purple-500/20 my-1', []),
                  // Total escrow
                  div(classes: 'flex justify-between items-center', [
                    div([
                      span(classes: 'font-bold text-sm', [Component.text('Total Escrow Hold')]),
                      p(classes: 'text-[10px] ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                        Component.text('Locked until lease completion'),
                      ]),
                    ]),
                    span(classes: 'font-black text-xl text-purple-400', [
                      Component.text('₱ ${(_totalPrice + _bookingFee).toStringAsFixed(2)}'),
                    ]),
                  ]),
                ]),
                p(classes: 'text-[10px] text-zinc-500 mt-2', [
                  Component.text(
                    'Funds are locked securely in escrow and released only when both parties confirm lease completion. Advance and deposit are governed by contract terms.',
                  ),
                ]),
              ],
            ]),

            // Footer
            div(classes: 'p-6 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center justify-between', [
              if (_step > 1)
                button(
                  classes:
                      'px-6 py-2 rounded-xl font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-300 hover:bg-zinc-50"} transition-colors',
                  events: {'click': (_) => setState(() => _step--)},
                  [Component.text('Back')],
                )
              else
                div([]),

              if (_step < 2)
                button(
                  classes:
                      'px-8 py-2 rounded-xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity border-0 outline-none cursor-pointer',
                  events: {
                    'click': (_) {
                      if (_basePrice <= 0) {
                        setState(() => _error = 'Rate option is not configured for this property.');
                        return;
                      }
                      setState(() {
                        _error = null;
                        _step++;
                      });
                    },
                  },
                  [Component.text('Review Terms')],
                )
              else
                button(
                  classes:
                      'px-8 py-2 rounded-xl font-bold text-white bg-green-500 hover:bg-green-600 transition-colors flex items-center gap-2 border-0 outline-none cursor-pointer',
                  events: {'click': (_) => _book()},
                  [
                    if (_isBooking) lIcon('loader', cls: 'w-4 h-4 animate-spin'),
                    Component.text(_isBooking ? 'Locking Escrow...' : 'Submit Request'),
                  ],
                ),
            ]),
          ],
        ),
      ],
    );
  }

  Component _packageOption(String duration, String title, double rate, bool isDark) {
    if (rate <= 0) return div([]);
    final isSelected = _selectedDurationType == duration;

    return div(
      classes:
          'p-4 rounded-2xl border cursor-pointer text-center transition-all ${isSelected ? "border-purple-500 bg-purple-500/10 text-purple-400 font-extrabold" : (isDark ? "border-zinc-800 bg-zinc-900/40 text-zinc-400 hover:bg-zinc-800/40" : "border-zinc-200 bg-zinc-50 text-zinc-600 hover:bg-zinc-100")}',
      events: {
        'click': (_) => setState(() {
          _selectedDurationType = duration;
          _multiplier = 1;
        }),
      },
      [
        p(classes: 'text-xs uppercase font-bold opacity-60 mb-1', [Component.text(title)]),
        p(classes: 'text-sm font-extrabold', [Component.text('₱ ${rate.toStringAsFixed(0)}')]),
      ],
    );
  }
}
