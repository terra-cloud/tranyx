import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../constants/contract_drafts.dart';
import '../../services/web_interop.dart';

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
  
  double get _basePrice {
    final r = component.appState.selectedRentalData;
    if (r == null) return 0;
    
    switch (_selectedPackage) {
      case '12h': return ((r['price12h'] ?? r['halfDayRate']) as num?)?.toDouble() ?? 0;
      case 'Weekly': return ((r['priceWeekly'] ?? r['weeklyRate']) as num?)?.toDouble() ?? 0;
      case 'Monthly': return ((r['priceMonthly'] ?? r['monthlyRate']) as num?)?.toDouble() ?? 0;
      default: return ((r['priceDaily'] ?? r['dailyRate']) as num?)?.toDouble() ?? 0;
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

  void _book() async {
    final canvasId = 'sig-pad-${component.appState.selectedRentalData?['id'] ?? 'default'}';
    if (isSignaturePadEmptyJs(canvasId)) {
      setState(() => _error = 'Please draw your signature on the signature pad.');
      return;
    }
    final signatureDataUrl = getSignatureDataUrlJs(canvasId);
    if (signatureDataUrl.isEmpty) {
      setState(() => _error = 'Could not capture signature. Please try again.');
      return;
    }
    
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

      // Submit booking request
      await component.appState.firestore.createBookingRequest(
        rentalId: r['id'],
        renteeId: currentUid,
        renteeName: user.name,
        renteePhotoUrl: user.photoUrl,
        durationType: _selectedPackage,
        multiplier: _quantity,
        signatureName: signatureDataUrl,
        licenseNumber: _licenseNumber,
        totalCost: _totalPrice,
        hireWithDriver: _hireWithDriver,
      );
      
      // Close modal
      component.appState.setState(() {
        component.appState.showBookVehicleModal = false;
        component.appState.selectedRentalData = null;
      });
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
    }

    final brand = r['brand'] ?? 'Unknown';
    final model = r['model'] ?? 'Unknown';
    final typeVal = r['type'] ?? r['vehicleType'];
    String type = typeVal?.toString().split('.').last ?? '';
    if (type.toLowerCase() == 'null') type = '';

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-2xl max-h-[90vh] overflow-y-auto rounded-3xl shadow-2xl relative flex flex-col ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"}',
          [
            // Header
            div(classes: 'sticky top-0 z-10 flex items-center justify-between p-6 border-b ${isDark ? "bg-zinc-900/90 border-zinc-800" : "bg-white/90 border-zinc-100"} backdrop-blur-md', [
              div([
                h2(classes: 'text-2xl font-bold', [Component.text('Book $brand $model')]),
                p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-500"} capitalize', [Component.text(type)]),
              ]),
              button(
                classes: 'p-2 rounded-full hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors',
                events: {'click': (e) => component.appState.setState(() {
                  component.appState.showBookVehicleModal = false;
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
                
              if (_step == 1) ...[
                // Step 1: Packages and Details
                () {
                  final front = r['frontPhotoUrl'] ?? r['frontPhoto'] ?? r['photoUrl'];
                  final interior = r['interiorPhotoUrl'] ?? r['interiorPhoto'];
                  final back = r['backPhotoUrl'] ?? r['backPhoto'];

                  final List<String> images = [];
                  if (front != null && front.toString().isNotEmpty && front.toString() != 'null') images.add(front.toString());
                  if (interior != null && interior.toString().isNotEmpty && interior.toString() != 'null') images.add(interior.toString());
                  if (back != null && back.toString().isNotEmpty && back.toString() != 'null') images.add(back.toString());

                  return div(classes: 'aspect-video w-full rounded-2xl overflow-hidden bg-zinc-800 flex items-center justify-center mb-6 relative group select-none', [
                    if (images.isNotEmpty) ...[
                      img(
                        src: images[_activeImageIndex % images.length],
                        classes: 'w-full h-full object-cover transition-all duration-300',
                        attributes: {'alt': '$brand $model image'},
                      ),
                      // Gradient overlay
                      div(classes: 'absolute inset-0 bg-gradient-to-t from-black/60 to-transparent pointer-events-none', []),
                      
                      // Left arrow button
                      if (images.length > 1)
                        button(
                          classes: 'absolute left-4 top-1/2 -translate-y-1/2 p-2 rounded-full bg-black/40 hover:bg-black/60 text-white transition-colors backdrop-blur-[2px] cursor-pointer border-0 outline-none',
                          events: {
                            'click': (e) {
                              setState(() {
                                _activeImageIndex = (_activeImageIndex - 1 + images.length) % images.length;
                              });
                            }
                          },
                          [lIcon('chevron-left', cls: 'w-6 h-6')],
                        ),
                        
                      // Right arrow button
                      if (images.length > 1)
                        button(
                          classes: 'absolute right-4 top-1/2 -translate-y-1/2 p-2 rounded-full bg-black/40 hover:bg-black/60 text-white transition-colors backdrop-blur-[2px] cursor-pointer border-0 outline-none',
                          events: {
                            'click': (e) {
                              setState(() {
                                _activeImageIndex = (_activeImageIndex + 1) % images.length;
                              });
                            }
                          },
                          [lIcon('chevron-right', cls: 'w-6 h-6')],
                        ),
                        
                      // Indicator dots & label
                      div(classes: 'absolute bottom-4 left-0 right-0 flex flex-col items-center gap-2 pointer-events-none', [
                        if (images.length > 1)
                          div(classes: 'flex gap-1.5', [
                            for (int i = 0; i < images.length; i++)
                              div(
                                classes: 'h-1.5 rounded-full transition-all duration-300 ${i == (_activeImageIndex % images.length) ? "w-6 bg-purple-500" : "w-1.5 bg-white/55"}',
                                [],
                              ),
                          ]),
                        p(classes: 'text-white text-xs font-semibold drop-shadow-sm', [
                          Component.text('${(_activeImageIndex % images.length) + 1} of ${images.length}')
                        ]),
                      ]),
                    ] else ...[
                      lIcon('image', cls: 'w-12 h-12 text-zinc-600'),
                      div(classes: 'absolute inset-0 bg-gradient-to-t from-black/80 to-transparent flex items-end p-4', [
                         p(classes: 'text-white font-bold', [Component.text('No photos available')])
                      ])
                    ]
                  ]);
                }(),

                h3(classes: 'text-lg font-bold mb-4', [Component.text('Select Rental Package')]),
                div(classes: 'grid grid-cols-2 gap-3', [
                  _packageOption('12h', '12 Hours', ((r['price12h'] ?? r['halfDayRate']) as num?)?.toDouble() ?? 0, isDark),
                  _packageOption('Daily', 'Daily', ((r['priceDaily'] ?? r['dailyRate']) as num?)?.toDouble() ?? 0, isDark),
                  _packageOption('Weekly', 'Weekly', ((r['priceWeekly'] ?? r['weeklyRate']) as num?)?.toDouble() ?? 0, isDark),
                  _packageOption('Monthly', 'Monthly', ((r['priceMonthly'] ?? r['monthlyRate']) as num?)?.toDouble() ?? 0, isDark),
                ]),
                
                if (r['offersDriver'] == true) ...[
                  div(classes: 'mt-6 p-4 rounded-2xl border ${isDark ? "border-zinc-800 bg-zinc-950/40" : "border-zinc-200 bg-zinc-50/50"}', [
                    div(classes: 'flex items-center justify-between mb-3', [
                      div([
                        h4(classes: 'font-bold text-sm flex items-center gap-1.5', [
                          lIcon('user', cls: 'w-4 h-4 text-purple-400'),
                          Component.text('Driver Service Available')
                        ]),
                        p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"} mt-0.5', [
                          Component.text('Daily Driver Fee: ₱ ${((r['driverDailyPrice'] ?? 0) as num).toDouble().toStringAsFixed(2)}')
                        ]),
                        p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-400"} mt-1 font-mono', [
                          Component.text('License: ${_obscureLicenseNumber(r['driverLicenseNumber']?.toString())}')
                        ]),
                      ]),
                      input(
                        type: InputType.checkbox,
                        classes: 'rounded border-zinc-300 text-purple-600 focus:ring-purple-500 w-5 h-5 cursor-pointer',
                        attributes: _hireWithDriver ? {'checked': 'checked'} : {},
                        events: {'change': (e) => setState(() => _hireWithDriver = (e.target as dynamic).checked as bool)},
                      ),
                    ]),
                    if (r['driverNote'] != null && r['driverNote'].toString().trim().isNotEmpty)
                      p(classes: 'text-xs italic ${isDark ? "text-zinc-400" : "text-zinc-500"} border-t ${isDark ? "border-zinc-800" : "border-zinc-150"} pt-2 mt-2', [
                        Component.text('Driver Note: ${r['driverNote']}')
                      ]),
                  ]),
                ],

                div(classes: 'mt-6', [
                   label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [Component.text('Quantity (e.g. 2 Days, 3 Weeks)')]),
                   input(
                     classes: 'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
                     type: InputType.number,
                     attributes: {'value': _quantity.toString(), 'min': '1'},
                     events: {'input': (e) => setState(() => _quantity = int.tryParse((e.target as dynamic).value) ?? 1)},
                   ),
                ]),
                
              ] else if (_step == 2) ...[
                // Step 2: Contract and Checkout
                h3(classes: 'text-lg font-bold mb-2', [Component.text(r['contractType'] == 'Custom Contract' ? 'Host\'s Custom Rental Agreement' : 'Tranyx P2P Rental Agreement')]),
                div(classes: 'p-4 rounded-xl border border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-900/50 h-64 overflow-y-auto mb-4', [
                  p(classes: 'whitespace-pre-wrap text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"} leading-relaxed', [
                    Component.text(r['contractType'] == 'Custom Contract' ? r['contractTerms'] ?? 'No terms provided.' : buildDefaultTranyxContract(VehicleRental.fromMap(r, r['id']))),
                  ]),
                ]),
                
                div(classes: 'mb-6', [
                   label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [Component.text('Driver\'s License Number')]),
                   input(
                     classes: 'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors mb-4',
                     attributes: {'value': _licenseNumber, 'placeholder': 'e.g., N01-23-456789'},
                     events: {'input': (e) {
                       final val = (e.target as dynamic).value as String;
                       final formatted = _formatLicenseNumber(val);
                       (e.target as dynamic).value = formatted;
                       setState(() => _licenseNumber = formatted);
                     }},
                   ),

                  () {
                    final canvasId = 'sig-pad-${r['id'] ?? 'default'}';
                    // Init pad after first render (idempotent)
                    Future.microtask(() => initSignaturePadJs(canvasId));

                    return div(classes: 'mb-2', [
                      div(classes: 'flex items-center justify-between mb-2', [
                        label(
                          classes: 'block text-sm font-semibold ${isDark ? "text-zinc-300" : "text-zinc-700"}',
                          [Component.text('Draw your signature')],
                        ),
                        button(
                          classes: 'text-xs text-zinc-400 hover:text-red-400 underline transition-colors',
                          events: {'click': (_) {
                            clearSignaturePadJs(canvasId);
                          }},
                          [Component.text('Clear')],
                        ),
                      ]),
                      div(
                        classes: 'rounded-2xl border-2 border-dashed ${isDark ? "border-zinc-700 bg-zinc-900/60" : "border-zinc-300 bg-zinc-50"} overflow-hidden',
                        [
                          Component.element(
                            tag: 'canvas',
                            id: canvasId,
                            classes: 'w-full touch-none cursor-crosshair block',
                            attributes: {'width': '600', 'height': '140'},
                          ),
                        ],
                      ),
                      p(classes: 'text-xs text-zinc-500 mt-1.5 flex items-center gap-1', [
                        lIcon('pen-tool', cls: 'w-3 h-3'),
                        Component.text('Sign with your mouse or finger'),
                      ]),
                    ]);
                  }(),
                ]),
                
                div(classes: 'p-5 rounded-xl bg-purple-500/10 border border-purple-500/20 space-y-3', [
                   div(classes: 'flex justify-between text-sm', [
                     span(classes: isDark ? 'text-zinc-400' : 'text-zinc-600', [Component.text('$_quantity x $_selectedPackage Vehicle Rate')]),
                     span(classes: 'font-bold', [Component.text('₱ ${(_basePrice * _quantity).toStringAsFixed(2)}')]),
                   ]),
                   if (_hireWithDriver)
                     div(classes: 'flex justify-between text-sm text-purple-400', [
                       span([Component.text('Driver Service (Included)')]),
                       span(classes: 'font-bold', [Component.text('₱ ${_driverPrice.toStringAsFixed(2)}')]),
                     ]),
                   div(classes: 'flex justify-between text-sm', [
                     span(classes: isDark ? 'text-zinc-400' : 'text-zinc-600', [Component.text('Platform Booking Fee (3%)')]),
                     span(classes: 'font-bold text-purple-400', [Component.text('₱ ${_bookingFee.toStringAsFixed(2)}')]),
                   ]),
                   div(classes: 'h-px w-full bg-purple-500/20 my-2', []),
                   div(classes: 'flex justify-between', [
                     span(classes: 'font-bold', [Component.text('Total Amount')]),
                     span(classes: 'font-black text-xl text-purple-400', [Component.text('₱ ${(_totalPrice + _bookingFee).toStringAsFixed(2)}')]),
                   ]),
                ]),
              ],
            ]),

            // Footer
            div(classes: 'p-6 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center justify-between', [
              if (_step > 1)
                button(
                  classes: 'px-6 py-2 rounded-xl font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-300 hover:bg-zinc-50"} transition-colors',
                  events: {'click': (e) => setState(() => _step--)},
                  [Component.text('Back')]
                )
              else div([]),
              
              if (_step < 2)
                button(
                  classes: 'px-8 py-2 rounded-xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity',
                  events: {'click': (e) {
                     if (_basePrice <= 0) {
                       setState(() => _error = 'Selected package is not available for this vehicle.');
                       return;
                     }
                     setState(() => _step++);
                  }},
                  [Component.text('Review Contract')]
                )
              else
                button(
                  classes: 'px-8 py-2 rounded-xl font-bold text-white bg-green-500 hover:bg-green-600 transition-colors flex items-center gap-2',
                  events: {'click': (e) => _book()},
                  [
                    if (_isBooking) lIcon('loader', cls: 'w-4 h-4 animate-spin'),
                    Component.text(_isBooking ? 'Processing...' : 'Sign & Pay')
                  ]
                ),
            ]),
          ]
        )
      ]
    );
  }

  Component _packageOption(String id, String labelText, double price, bool isDark) {
    final isSelected = _selectedPackage == id;
    return div(
      classes: 'p-4 rounded-xl border-2 cursor-pointer transition-all ${isSelected ? "border-purple-500 bg-purple-500/10" : (isDark ? "border-zinc-800 hover:border-zinc-700 bg-zinc-800/30" : "border-zinc-200 hover:border-zinc-300 bg-zinc-50")}',
      events: {'click': (_) => setState(() => _selectedPackage = id)},
      [
        p(classes: 'font-semibold mb-1 ${isSelected ? "text-purple-400" : ""}', [Component.text(labelText)]),
        p(classes: 'font-bold text-lg', [
           if (price > 0) Component.text('₱ ${price.toStringAsFixed(0)}')
           else span(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-400"}', [Component.text('Not Available')])
        ]),
      ]
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
}
