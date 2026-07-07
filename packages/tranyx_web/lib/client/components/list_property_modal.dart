import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import 'package:web/web.dart' as web;
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../components/map_picker.dart';
import '../../services/web_interop.dart';
import '../../services/firebase_service.dart';
import 'contract_viewer.dart';

class ListPropertyModalComponent extends StatefulComponent {
  final TranyxAppState appState;
  const ListPropertyModalComponent({required this.appState, super.key});

  @override
  State<ListPropertyModalComponent> createState() => _ListPropertyModalState();
}

class _ListPropertyModalState extends State<ListPropertyModalComponent> {
  int _step = 1;

  @override
  void initState() {
    super.initState();
    component.appState.pickupAddress = '';
    component.appState.pickupLat = null;
    component.appState.pickupLng = null;
  }

  // Form Fields
  PropertyType _selectedType = PropertyType.house;
  PropertyCategory _selectedCategory = PropertyCategory.residential;
  String _title = '';
  String _description = '';
  final List<String> _amenities = [];

  // Pricing
  String _priceMonthly = '';
  String _priceWeekly = '';
  String _priceDaily = '';
  int _depositMonths = 1; // standard: 1 month deposit
  String _securityDepositAmount = '0';
  String _advanceAmount = '0';

  // Location
  String _address = '';
  double? _latitude;
  double? _longitude;

  String _contractType = 'Tranyx Standard';
  String _customTerms = '';
  bool _showPreview = false;

  // Images
  final List<String> _imageUrls = ['', '']; // Requires Interior, Front/Exterior
  final List<bool> _isUploadingImage = [false, false];
  final List<String> _extraImageUrls = [];
  final List<bool> _isUploadingExtraImage = [];

  bool _isSubmitting = false;
  String? _error;

  double get _listingFee {
    final monthly = double.tryParse(_priceMonthly) ?? 0;
    return monthly * 0.015; // 1.5% of monthly rent listing fee
  }

  final List<String> _amenitiesList = ['WiFi', 'Aircon', 'Parking', 'Furnished', 'Gym', 'Swimming Pool'];

  void _submit() async {
    final mapAddress = component.appState.pickupAddress;
    final mapLat = component.appState.pickupLat;
    final mapLng = component.appState.pickupLng;

    if (mapAddress.isEmpty) {
      setState(() => _error = 'Please select and confirm property location on the map (Step 2).');
      return;
    }

    _address = mapAddress;
    _latitude = mapLat;
    _longitude = mapLng;

    if (_title.trim().isEmpty || _description.trim().isEmpty) {
      setState(() => _error = 'Please fill out property title and description.');
      return;
    }

    if (component.appState.checkProfanity(_title) ||
        component.appState.checkProfanity(_description) ||
        (_contractType == 'Custom Contract' && component.appState.checkProfanity(_customTerms))) {
      setState(
        () => _error =
            'Your title, description, or custom terms contain inappropriate language. Please review and try again.',
      );
      return;
    }

    final monthly = double.tryParse(_priceMonthly) ?? 0;
    if (monthly <= 0) {
      setState(() => _error = 'Please provide a valid monthly rate.');
      return;
    }

    if (_contractType == 'Custom Contract' && _customTerms.trim().isEmpty) {
      setState(() => _error = 'Please enter your custom contract terms.');
      return;
    }

    if (_imageUrls[0].isEmpty) {
      setState(() => _error = 'Please upload the Interior photo (Required).');
      return;
    }
    if (_imageUrls[1].isEmpty) {
      setState(() => _error = 'Please upload the Front/Exterior photo (Required).');
      return;
    }

    final finalPhotos = [
      _imageUrls[0],
      _imageUrls[1],
      ..._extraImageUrls,
    ];

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final hostId = component.appState.userProfile?.uid;
      if (hostId == null) throw FirebaseException('Not logged in', 403);

      final user = component.appState.userProfile;
      if (user == null) throw Exception('User profile not loaded.');

      final depositAmt = double.tryParse(_securityDepositAmount) ?? 0.0;
      final advanceAmt = double.tryParse(_advanceAmount) ?? 0.0;
      _depositMonths = monthly > 0 ? (depositAmt / monthly).round() : 0;

      final property = PropertyRental(
        id: '',
        hostId: hostId,
        hostName: user.name,
        hostPhotoUrl: user.photoUrl,
        title: _title.trim(),
        description: _description.trim(),
        type: _selectedType,
        category: _selectedCategory,
        priceMonthly: monthly,
        priceWeekly: double.tryParse(_priceWeekly) ?? 0.0,
        priceDaily: double.tryParse(_priceDaily) ?? 0.0,
        depositMonths: _depositMonths,
        securityDepositAmount: depositAmt,
        advanceAmount: advanceAmt,
        address: _address,
        latitude: _latitude ?? 14.5995,
        longitude: _longitude ?? 120.9842,
        photoUrls: finalPhotos,
        amenities: _amenities,
        status: 'Available',
        contractType: _contractType,
        contractTerms: _contractType == 'Custom Contract' ? _customTerms : 'Standard P2P Lease terms',
        createdAt: DateTime.now(),
        allowChat: false,
      );

      // Create property listing
      await component.appState.firestore.createPropertyRental(property);

      // Reload profile & transactions to display balance deduction and transaction log promptly
      await component.appState.loadUserProfile();
      await component.appState.loadTransactions();

      // Close modal
      component.appState.setState(() {
        component.appState.showListPropertyModal = false;
      });
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _error = e.toString();
      });
    }
  }

  void _handleNext() {
    setState(() => _error = null);

    if (_step == 1) {
      if (_title.trim().isEmpty) {
        setState(() => _error = 'Please enter a listing title.');
        return;
      }
      if (_description.trim().isEmpty) {
        setState(() => _error = 'Please enter a description.');
        return;
      }
    } else if (_step == 2) {
      if (_priceMonthly.trim().isEmpty) {
        setState(() => _error = 'Please provide a monthly rate.');
        return;
      }
      if (double.tryParse(_priceMonthly) == null || double.parse(_priceMonthly) <= 0) {
        setState(() => _error = 'Monthly rate must be a valid number greater than 0.');
        return;
      }
      if (component.appState.pickupAddress.isEmpty) {
        setState(() => _error = 'Please select and confirm property location on the map.');
        return;
      }
      _address = component.appState.pickupAddress;
      _latitude = component.appState.pickupLat;
      _longitude = component.appState.pickupLng;
    }

    setState(() => _step++);
  }

  @override
  Component build(BuildContext context) {
    if (!component.appState.showListPropertyModal) return div([]);
    final isDark = component.appState.isDark;

    return div(classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in', [
      div(
        classes:
            'w-full max-w-2xl max-h-[90vh] overflow-y-auto rounded-3xl shadow-2xl relative flex flex-col ${isDark ? "bg-zinc-900 border border-zinc-800 text-white" : "bg-white text-zinc-900"}',
        [
          // Header
          div(
            classes:
                'sticky top-0 z-10 flex items-center justify-between p-6 border-b ${isDark ? "bg-zinc-900/90 border-zinc-800" : "bg-white/90 border-zinc-100"} backdrop-blur-md',
            [
              div([
                h2(classes: 'text-2xl font-bold', [Component.text('List a Property')]),
                p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                  Component.text('Step $_step of 3'),
                ]),
              ]),
              button(
                classes: 'p-2 rounded-full hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors',
                events: {
                  'click': (_) => component.appState.setState(() => component.appState.showListPropertyModal = false),
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
              // Step 1: Specifications
              h3(classes: 'text-lg font-bold mb-4', [Component.text('Property Details')]),

              div(classes: 'grid grid-cols-2 gap-4 mb-4', [
                div([
                  label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                    Component.text('Property Category'),
                  ]),
                  select(
                    classes:
                        'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
                    events: {
                      'change': (e) {
                        setState(() {
                          _selectedCategory = PropertyCategory.values.firstWhere(
                            (c) => c.name == getInputValue(e.target),
                          );
                          // Auto-select first type that belongs to the new category
                          _selectedType = PropertyType.values.firstWhere((t) => t.category == _selectedCategory);
                        });
                      },
                    },
                    [
                      for (final c in PropertyCategory.values)
                        option(value: c.name, selected: _selectedCategory == c, [Component.text(c.label)]),
                    ],
                  ),
                ]),

                div([
                  label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                    Component.text('Property Type'),
                  ]),
                  select(
                    classes:
                        'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
                    events: {
                      'change': (e) {
                        setState(() {
                          _selectedType = PropertyType.values.firstWhere((t) => t.name == getInputValue(e.target));
                        });
                      },
                    },
                    [
                      for (final t in PropertyType.values.where((t) => t.category == _selectedCategory))
                        option(value: t.name, selected: _selectedType == t, [Component.text(t.label)]),
                    ],
                  ),
                ]),
              ]),

              _inputField(
                'Listing Title',
                _title,
                (v) => setState(() => _title = v),
                isDark,
                placeholder: 'e.g. Cozy 1BR Condo with Balcony in BGC',
              ),

              div(classes: 'mb-4', [
                label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Description'),
                ]),
                textarea(
                  classes:
                      'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors h-28 resize-none',
                  attributes: {
                    'placeholder': 'Provide details about the space, proximity to key locations, house rules...',
                  },
                  events: {'input': (e) => setState(() => _description = getInputValue(e.target))},
                  [Component.text(_description)],
                ),
              ]),

              // Amenities Checklist
              div(classes: 'mb-4', [
                label(classes: 'block text-sm font-semibold mb-3 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Amenities'),
                ]),
                div(classes: 'grid grid-cols-2 md:grid-cols-3 gap-3', [
                  for (final amenity in _amenitiesList)
                    label(
                      classes:
                          'flex items-center gap-2.5 p-3 rounded-xl border cursor-pointer transition-colors ${_amenities.contains(amenity) ? "border-purple-500/40 bg-purple-500/10 text-purple-400 font-semibold" : (isDark ? "border-zinc-800 hover:border-zinc-700 text-zinc-400" : "border-zinc-200 hover:border-zinc-300 text-zinc-600")}',
                      [
                        input(
                          type: InputType.checkbox,
                          classes: 'hidden',
                          checked: _amenities.contains(amenity),
                          onChange: (val) {
                            setState(() {
                              if (val == true) {
                                _amenities.add(amenity);
                              } else {
                                _amenities.remove(amenity);
                              }
                            });
                          },
                        ),
                        lIcon(
                          amenity == 'WiFi'
                              ? 'wifi'
                              : amenity == 'Aircon'
                              ? 'wind'
                              : amenity == 'Parking'
                              ? 'car'
                              : amenity == 'Furnished'
                              ? 'armchair'
                              : amenity == 'Gym'
                              ? 'dumbbell'
                              : 'waves',
                          cls: 'w-4 h-4',
                        ),
                        span([Component.text(amenity)]),
                      ],
                    ),
                ]),
              ]),
            ] else if (_step == 2) ...[
              // Step 2: Pricing & Location
              h3(classes: 'text-lg font-bold mb-4', [Component.text('Pricing & Proximity')]),
              div(classes: 'grid grid-cols-2 gap-4', [
                _inputField(
                  'Monthly Rent (Required)',
                  _priceMonthly,
                  (v) => setState(() => _priceMonthly = v),
                  isDark,
                  placeholder: '25000',
                  type: InputType.number,
                ),
                div([]),
                // Security Deposit
                div([
                  _inputField(
                    'Security Deposit (₱)',
                    _securityDepositAmount,
                    (v) => setState(() => _securityDepositAmount = v),
                    isDark,
                    placeholder: 'e.g. 50000',
                    type: InputType.number,
                  ),
                  Builder(
                    builder: (context) {
                      final monthly = double.tryParse(_priceMonthly) ?? 0.0;
                      if (monthly <= 0) return div([]);
                      return div(classes: 'flex flex-wrap gap-1.5 mb-4', [
                        span(classes: 'text-[10px] text-zinc-500 font-semibold my-auto mr-1', [
                          Component.text('Quick:'),
                        ]),
                        button(
                          classes:
                              'px-2 py-1 text-[10px] font-bold rounded-lg border transition-all cursor-pointer '
                              '${_securityDepositAmount == "0" ? "bg-purple-500 text-white border-purple-500" : (isDark ? "bg-zinc-800 border-zinc-700 hover:bg-zinc-700 text-zinc-300" : "bg-zinc-50 border-zinc-200 hover:bg-zinc-100 text-zinc-700")}',
                          events: {'click': (_) => setState(() => _securityDepositAmount = '0')},
                          [Component.text('None')],
                        ),
                        button(
                          classes:
                              'px-2 py-1 text-[10px] font-bold rounded-lg border transition-all cursor-pointer '
                              '${_securityDepositAmount == monthly.toInt().toString() ? "bg-purple-500 text-white border-purple-500" : (isDark ? "bg-zinc-800 border-zinc-700 hover:bg-zinc-700 text-zinc-300" : "bg-zinc-50 border-zinc-200 hover:bg-zinc-100 text-zinc-700")}',
                          events: {'click': (_) => setState(() => _securityDepositAmount = monthly.toInt().toString())},
                          [Component.text('1 mo')],
                        ),
                        button(
                          classes:
                              'px-2 py-1 text-[10px] font-bold rounded-lg border transition-all cursor-pointer '
                              '${_securityDepositAmount == (monthly * 2).toInt().toString() ? "bg-purple-500 text-white border-purple-500" : (isDark ? "bg-zinc-800 border-zinc-700 hover:bg-zinc-700 text-zinc-300" : "bg-zinc-50 border-zinc-200 hover:bg-zinc-100 text-zinc-700")}',
                          events: {
                            'click': (_) => setState(() => _securityDepositAmount = (monthly * 2).toInt().toString()),
                          },
                          [Component.text('2 mo')],
                        ),
                        button(
                          classes:
                              'px-2 py-1 text-[10px] font-bold rounded-lg border transition-all cursor-pointer '
                              '${_securityDepositAmount == (monthly * 3).toInt().toString() ? "bg-purple-500 text-white border-purple-500" : (isDark ? "bg-zinc-800 border-zinc-700 hover:bg-zinc-700 text-zinc-300" : "bg-zinc-50 border-zinc-200 hover:bg-zinc-100 text-zinc-700")}',
                          events: {
                            'click': (_) => setState(() => _securityDepositAmount = (monthly * 3).toInt().toString()),
                          },
                          [Component.text('3 mo')],
                        ),
                      ]);
                    },
                  ),
                ]),
                // Advance Payment
                div([
                  _inputField(
                    'Advance Payment (₱)',
                    _advanceAmount,
                    (v) => setState(() => _advanceAmount = v),
                    isDark,
                    placeholder: 'e.g. 25000',
                    type: InputType.number,
                  ),
                  Builder(
                    builder: (context) {
                      final monthly = double.tryParse(_priceMonthly) ?? 0.0;
                      if (monthly <= 0) return div([]);
                      return div(classes: 'flex flex-wrap gap-1.5 mb-4', [
                        span(classes: 'text-[10px] text-zinc-500 font-semibold my-auto mr-1', [
                          Component.text('Quick:'),
                        ]),
                        button(
                          classes:
                              'px-2 py-1 text-[10px] font-bold rounded-lg border transition-all cursor-pointer '
                              '${_advanceAmount == "0" ? "bg-indigo-500 text-white border-indigo-500" : (isDark ? "bg-zinc-800 border-zinc-700 hover:bg-zinc-700 text-zinc-300" : "bg-zinc-50 border-zinc-200 hover:bg-zinc-100 text-zinc-700")}',
                          events: {'click': (_) => setState(() => _advanceAmount = '0')},
                          [Component.text('None')],
                        ),
                        button(
                          classes:
                              'px-2 py-1 text-[10px] font-bold rounded-lg border transition-all cursor-pointer '
                              '${_advanceAmount == monthly.toInt().toString() ? "bg-indigo-500 text-white border-indigo-500" : (isDark ? "bg-zinc-800 border-zinc-700 hover:bg-zinc-700 text-zinc-300" : "bg-zinc-50 border-zinc-200 hover:bg-zinc-100 text-zinc-700")}',
                          events: {'click': (_) => setState(() => _advanceAmount = monthly.toInt().toString())},
                          [Component.text('1 mo')],
                        ),
                        button(
                          classes:
                              'px-2 py-1 text-[10px] font-bold rounded-lg border transition-all cursor-pointer '
                              '${_advanceAmount == (monthly * 2).toInt().toString() ? "bg-indigo-500 text-white border-indigo-500" : (isDark ? "bg-zinc-800 border-zinc-700 hover:bg-zinc-700 text-zinc-300" : "bg-zinc-50 border-zinc-200 hover:bg-zinc-100 text-zinc-700")}',
                          events: {'click': (_) => setState(() => _advanceAmount = (monthly * 2).toInt().toString())},
                          [Component.text('2 mo')],
                        ),
                      ]);
                    },
                  ),
                ]),
                _inputField(
                  'Weekly Rate (Optional)',
                  _priceWeekly,
                  (v) => setState(() => _priceWeekly = v),
                  isDark,
                  placeholder: 'e.g. 7000',
                  type: InputType.number,
                ),
                _inputField(
                  'Daily Rate (Optional)',
                  _priceDaily,
                  (v) => setState(() => _priceDaily = v),
                  isDark,
                  placeholder: 'e.g. 1500',
                  type: InputType.number,
                ),
              ]),

              div(classes: 'mt-6 p-4 rounded-xl bg-purple-500/10 border border-purple-500/20 mb-6', [
                div(classes: 'flex justify-between text-sm mb-2', [
                  span(classes: isDark ? 'text-zinc-400' : 'text-zinc-600', [
                    Component.text('Platform Listing Fee (1.5% of Monthly)'),
                  ]),
                  span(classes: 'font-bold text-purple-400', [Component.text('${_listingFee.toStringAsFixed(2)} TYX')]),
                ]),
                p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                  Component.text(
                    'To prevent listing spam, a small fee is deducted from your wallet to post your property.',
                  ),
                ]),
              ]),

              div(classes: 'mt-6 border-t ${isDark ? "border-zinc-800" : "border-zinc-200"} pt-6', [
                label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Set Property Map Location'),
                ]),
                p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"} mb-3', [
                  Component.text('Confirm property exact location by panning the map below.'),
                ]),
                MapPickerComponent(state: component.appState),
              ]),
            ] else if (_step == 3) ...[
              // Step 3: Photos & Contracts
              h3(classes: 'text-lg font-bold mb-4', [Component.text('Photos & Legal')]),
              p(classes: 'text-sm mb-4 ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                Component.text('Upload required photos representing: Interior and Front/Exterior.'),
              ]),
              div(classes: 'grid grid-cols-2 gap-4 mb-6', [
                _photoUploadPlaceholder('Interior (Required)', _imageUrls[0], 0, isDark),
                _photoUploadPlaceholder('Front/Exterior (Required)', _imageUrls[1], 1, isDark),
              ]),

              // Extra Photos Section
              div(classes: 'mb-6', [
                label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Additional Photos (Optional)'),
                ]),
                div(classes: 'grid grid-cols-3 gap-3', [
                  for (int i = 0; i < _extraImageUrls.length; i++)
                    div(
                      classes:
                          'relative aspect-video rounded-2xl overflow-hidden border group ${isDark ? "border-zinc-800" : "border-zinc-200"}',
                      [
                        img(
                          src: _extraImageUrls[i],
                          classes: 'w-full h-full object-cover',
                        ),
                        div(
                          classes:
                              'absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center gap-3 z-10',
                          [
                            button(
                              classes:
                                  'p-1.5 rounded-full bg-white/20 hover:bg-white/40 text-white transition-colors cursor-pointer border-none outline-none',
                              events: {
                                'click': (e) {
                                  e.stopPropagation();
                                  e.preventDefault();
                                  component.appState.showFullScreenPhoto(_extraImageUrls[i]);
                                }
                              },
                              [lIcon('eye', cls: 'w-4 h-4')],
                            ),
                            button(
                              classes:
                                  'p-1.5 rounded-full bg-red-600/80 hover:bg-red-600 text-white transition-colors cursor-pointer border-none outline-none',
                              events: {
                                'click': (e) {
                                  e.stopPropagation();
                                  e.preventDefault();
                                  setState(() {
                                    _extraImageUrls.removeAt(i);
                                  });
                                }
                              },
                              [lIcon('trash-2', cls: 'w-4 h-4')],
                            ),
                          ],
                        ),
                      ],
                    ),

                  // Add Photo Button / Placeholder
                  _extraPhotoUploadPlaceholder(isDark),
                ]),
              ]),

              div(classes: 'mb-4', [
                label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Contract Lease Type'),
                ]),
                select(
                  classes:
                      'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
                  events: {'change': (e) => setState(() => _contractType = getInputValue(e.target))},
                  [
                    option(value: 'Tranyx Standard', selected: _contractType == 'Tranyx Standard', [
                      Component.text('Tranyx Standard Lease'),
                    ]),
                    option(value: 'Custom Contract', selected: _contractType == 'Custom Contract', [
                      Component.text('Custom Contract Terms'),
                    ]),
                  ],
                ),
              ]),

              if (_contractType == 'Tranyx Standard') ...[
                div(
                  classes: 'p-4 rounded-xl border border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-900/50',
                  [
                    div(classes: 'flex items-center justify-between mb-2', [
                      div(classes: 'flex items-center gap-3', [
                        lIcon('file-text', cls: 'w-5 h-5 text-blue-500'),
                        h4(classes: 'font-bold', [Component.text('Tranyx Standard Lease Agreement')]),
                      ]),
                      button(
                        classes: 'text-xs text-blue-500 hover:underline',
                        events: {'click': (_) => setState(() => _showPreview = !_showPreview)},
                        [Component.text(_showPreview ? 'Hide Preview' : 'View Contract')],
                      ),
                    ]),
                    p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"} mb-2', [
                      Component.text(
                        'By proceeding, you agree to compile under our standard P2P Rental Agreement underwritten by our partner legal firm.',
                      ),
                    ]),
                    if (_showPreview)
                      ContractViewerComponent(
                        propertyRental: PropertyRental(
                          id: '',
                          hostId: '',
                          hostName: component.appState.userProfile?.name ?? 'Owner',
                          title: _title,
                          description: _description,
                          type: _selectedType,
                          category: _selectedCategory,
                          priceMonthly: double.tryParse(_priceMonthly) ?? 0,
                          priceWeekly: double.tryParse(_priceWeekly) ?? 0,
                          priceDaily: double.tryParse(_priceDaily) ?? 0,
                          depositMonths: _depositMonths,
                          securityDepositAmount: double.tryParse(_securityDepositAmount) ?? 0.0,
                          advanceAmount: double.tryParse(_advanceAmount) ?? 0.0,
                          address: _address.isNotEmpty ? _address : component.appState.pickupAddress,
                          latitude: _latitude ?? component.appState.pickupLat ?? 0.0,
                          longitude: _longitude ?? component.appState.pickupLng ?? 0.0,
                          photoUrls: [],
                          amenities: _amenities,
                          status: 'Available',
                          contractType: 'Tranyx Standard',
                          contractTerms: '',
                          createdAt: DateTime.now(),
                        ),
                      ),
                  ],
                ),
              ] else ...[
                div(classes: 'mt-4', [
                  label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                    Component.text('Custom Lease Terms'),
                  ]),
                  textarea(
                    classes:
                        'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors h-32 resize-none',
                    attributes: {
                      'placeholder':
                          'Enter your custom property lease terms, house rules, water/electricity billing agreements...',
                    },
                    events: {'input': (e) => setState(() => _customTerms = getInputValue(e.target))},
                    [Component.text(_customTerms)],
                  ),
                ]),
              ],

              Builder(
                builder: (context) {
                  final monthlyRate = double.tryParse(_priceMonthly) ?? 0.0;
                  final weeklyRate = double.tryParse(_priceWeekly) ?? 0.0;
                  final dailyRate = double.tryParse(_priceDaily) ?? 0.0;
                  final depositAmt = double.tryParse(_securityDepositAmount) ?? 0.0;
                  final advanceAmt = double.tryParse(_advanceAmount) ?? 0.0;

                  // Listing Fee (1.5% of Monthly)
                  final listingFee = monthlyRate * 0.015;

                  // Commission (3% deducted from rent)
                  final commissionMonthly = monthlyRate * 0.03;
                  final payoutMonthly = monthlyRate - commissionMonthly;

                  final commissionWeekly = weeklyRate * 0.03;
                  final payoutWeekly = weeklyRate - commissionWeekly;

                  final commissionDaily = dailyRate * 0.03;
                  final payoutDaily = dailyRate - commissionDaily;

                  if (monthlyRate <= 0) return div([]);

                  return div(
                    classes: 'mt-6 p-5 rounded-2xl border ${isDark ? "border-zinc-800 bg-zinc-900/50" : "border-zinc-200 bg-zinc-50"} space-y-3.5',
                    [
                      p(classes: 'text-xs font-bold text-indigo-400 uppercase tracking-wider', [Component.text('Listing Payment & Earnings Breakdown')]),
                      div(classes: 'space-y-2.5', [
                        // Rates
                        div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                          span([Component.text('Monthly Rent (Base):')]),
                          span(classes: 'font-semibold ${isDark ? "text-zinc-200" : "text-zinc-700"}', [
                            Component.text('₱ ${monthlyRate.toStringAsFixed(2)}')
                          ]),
                        ]),
                        if (weeklyRate > 0)
                          div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                            span([Component.text('Weekly Rent: ₱${weeklyRate.toStringAsFixed(2)}')]),
                            span(classes: 'font-semibold ${isDark ? "text-zinc-200" : "text-zinc-700"}', [
                              Component.text('Payout: ₱${payoutWeekly.toStringAsFixed(2)} (Net)')
                            ]),
                          ]),
                        if (dailyRate > 0)
                          div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                            span([Component.text('Daily Rent: ₱${dailyRate.toStringAsFixed(2)}')]),
                            span(classes: 'font-semibold ${isDark ? "text-zinc-200" : "text-zinc-700"}', [
                              Component.text('Payout: ₱${payoutDaily.toStringAsFixed(2)} (Net)')
                            ]),
                          ]),
                        if (depositAmt > 0)
                          div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                            span([Component.text('Security Deposit (Refundable):')]),
                            span(classes: 'font-semibold text-green-500', [
                              Component.text('₱ ${depositAmt.toStringAsFixed(2)}')
                            ]),
                          ]),
                        if (advanceAmt > 0)
                          div(classes: 'flex justify-between items-center text-xs text-zinc-400 border-b ${isDark ? "border-zinc-800 pb-2" : "border-zinc-200 pb-2"}', [
                            span([Component.text('Advance Rent Payment:')]),
                            span(classes: 'font-semibold text-green-500', [
                              Component.text('₱ ${advanceAmt.toStringAsFixed(2)}')
                            ]),
                          ]),

                        // Commission & Earnings summary
                        div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                          span([Component.text('Host Commission (3%):')]),
                          span(classes: 'font-semibold text-amber-500', [
                            Component.text('- ₱ ${commissionMonthly.toStringAsFixed(2)}')
                          ]),
                        ]),
                        div(classes: 'flex justify-between items-center pt-1.5', [
                          span(classes: 'text-xs font-semibold text-indigo-400', [Component.text('Est. Monthly Net Payout:')]),
                          span(classes: 'text-base font-bold text-green-500', [
                            Component.text('₱ ${payoutMonthly.toStringAsFixed(2)}')
                          ]),
                        ]),

                        // Separator
                        div(classes: 'border-t ${isDark ? "border-zinc-800" : "border-zinc-200"} my-2', []),

                        // Listing anti-spam fee
                        div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                          span([Component.text('Anti-Spam Listing Fee (1.5% of Monthly):')]),
                          span(classes: 'font-semibold text-purple-400', [
                            Component.text('${listingFee.toStringAsFixed(2)} TYX')
                          ]),
                        ]),
                      ]),
                      p(classes: 'text-[10px] text-zinc-500 leading-normal', [
                        Component.text(
                          'Notice: A listing fee of ${listingFee.toStringAsFixed(2)} TYX will be charged to your wallet now to host the property. Standard platform commission of 3% is only charged on rent payouts.',
                        ),
                      ]),
                    ],
                  );
                },
              ),
            ],
          ]),

          // Footer
          div(classes: 'p-6 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex flex-col gap-4', [
            if (_error != null)
              div(classes: 'p-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-500 text-sm font-semibold flex items-center gap-2 animate-fade-in', [
                lIcon('alert-circle', cls: 'w-5 h-5 flex-shrink-0 text-red-500'),
                span([Component.text(_error!)]),
              ]),
            div(classes: 'flex items-center justify-between', [
              if (_step > 1)
                button(
                  classes:
                      'px-6 py-2 rounded-xl font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-300 hover:bg-zinc-50"} transition-colors',
                  events: {'click': (e) => setState(() => _step--)},
                  [Component.text('Back')],
                )
              else
                div([]),

              if (_step < 3)
                button(
                  classes:
                      'px-8 py-2 rounded-xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity border-0 cursor-pointer',
                  events: {'click': (e) => _handleNext()},
                  [Component.text('Next')],
                )
              else
                button(
                  classes:
                      'px-8 py-2 rounded-xl font-bold text-white bg-green-500 hover:bg-green-600 transition-colors flex items-center gap-2 border-0 cursor-pointer',
                  events: {'click': (e) => _submit()},
                  [
                    if (_isSubmitting) lIcon('loader', cls: 'w-4 h-4 animate-spin'),
                    Component.text(_isSubmitting ? 'Listing...' : 'List Property'),
                  ],
                ),
            ]),
          ]),
        ],
      ),
    ]);
  }

  Component _inputField(
    String labelText,
    String value,
    void Function(String) onChange,
    bool isDark, {
    String? placeholder,
    InputType type = InputType.text,
  }) {
    return div([
      label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
        Component.text(labelText),
      ]),
      input(
        classes:
            'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors mb-4',
        type: type,
        attributes: {'value': value, 'placeholder': ?placeholder},
        events: {
          'input': (e) {
            onChange(getInputValue(e.target));
          },
        },
      ),
    ]);
  }

  void _handleFileSelected(web.Event event, int index) async {
    try {
      final files = await readFilesFromEvent(event);
      if (files.isEmpty) return;

      setState(() {
        _isUploadingImage[index] = true;
        _error = null;
      });

      final file = files.first;
      final token = SessionStorage.idToken;
      final url = await ImgBBService(currentFirebaseConfig, idToken: token).uploadImageBytes(file.bytes, file.name);

      if (url != null) {
        setState(() {
          _imageUrls[index] = url;
        });
      } else {
        setState(() {
          _error = 'Failed to upload image to ImgBB. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error uploading image: $e';
      });
    } finally {
      setState(() {
        _isUploadingImage[index] = false;
      });
    }
  }

  Component _photoUploadPlaceholder(String labelText, String currentUrl, int index, bool isDark) {
    final isUploading = _isUploadingImage[index];

    return div(
      classes:
          'relative aspect-video rounded-2xl overflow-hidden border border-dashed group ${isDark ? "border-zinc-800 bg-zinc-900/30" : "border-zinc-200 bg-zinc-50/50"}',
      [
        input(
          type: InputType.file,
          classes: 'hidden',
          attributes: {
            'id': 'file-input-prop-$index',
            'accept': 'image/*',
            'style': 'display: none;',
          },
          events: {
            'change': (e) {
              _handleFileSelected(e, index);
            },
          },
        ),

        if (currentUrl.isNotEmpty) ...[
          img(
            src: currentUrl,
            classes: 'w-full h-full object-cover',
            attributes: {'alt': labelText},
          ),
          div(
            classes:
                'absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center gap-4 z-20',
            [
              button(
                classes:
                    'p-2 rounded-full bg-white/20 hover:bg-white/40 text-white transition-colors cursor-pointer border-none outline-none',
                events: {
                  'click': (e) {
                    e.stopPropagation();
                    e.preventDefault();
                    component.appState.showFullScreenPhoto(currentUrl);
                  }
                },
                [lIcon('eye', cls: 'w-5 h-5')],
              ),
              label(
                classes:
                    'p-2 rounded-full bg-white/20 hover:bg-white/40 text-white transition-colors cursor-pointer',
                attributes: {
                  'for': 'file-input-prop-$index',
                },
                [lIcon('edit-2', cls: 'w-5 h-5')],
              ),
              button(
                classes:
                    'p-2 rounded-full bg-red-600/80 hover:bg-red-600 text-white transition-colors cursor-pointer border-none outline-none',
                events: {
                  'click': (e) {
                    e.stopPropagation();
                    e.preventDefault();
                    setState(() {
                      _imageUrls[index] = '';
                    });
                  }
                },
                [lIcon('trash-2', cls: 'w-5 h-5')],
              ),
            ],
          ),
        ] else ...[
          label(
            classes:
                'w-full h-full flex flex-col items-center justify-center cursor-pointer transition-colors hover:opacity-90',
            attributes: {
              'for': 'file-input-prop-$index',
            },
            [
              lIcon('camera', cls: 'w-6 h-6 mb-2 ${isDark ? "text-zinc-500" : "text-zinc-400"}'),
              p(classes: 'text-xs font-semibold ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                Component.text(labelText),
              ]),
            ],
          ),
        ],

        if (isUploading)
          div(
            classes:
                'absolute inset-0 bg-black/60 flex flex-col items-center justify-center text-white backdrop-blur-[2px] z-30 animate-fade-in',
            [
              lIcon('loader', cls: 'w-6 h-6 animate-spin mb-2 text-purple-400'),
              p(classes: 'text-xs font-semibold', [Component.text('Uploading...')]),
            ],
          ),
      ],
    );
  }

  void _handleExtraFileSelected(web.Event event) async {
    try {
      final files = await readFilesFromEvent(event);
      if (files.isEmpty) return;

      setState(() {
        _isUploadingExtraImage.add(true);
        _error = null;
      });

      final file = files.first;
      final token = SessionStorage.idToken;
      final url = await ImgBBService(currentFirebaseConfig, idToken: token).uploadImageBytes(file.bytes, file.name);

      if (url != null) {
        setState(() {
          _extraImageUrls.add(url);
        });
      } else {
        setState(() {
          _error = 'Failed to upload image to ImgBB. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error uploading image: $e';
      });
    } finally {
      setState(() {
        if (_isUploadingExtraImage.isNotEmpty) {
          _isUploadingExtraImage.removeLast();
        }
      });
    }
  }

  Component _extraPhotoUploadPlaceholder(bool isDark) {
    final isUploading = _isUploadingExtraImage.isNotEmpty && _isUploadingExtraImage.any((val) => val);
    return label(
      classes:
          'relative aspect-video rounded-2xl border border-dashed flex flex-col items-center justify-center cursor-pointer overflow-hidden transition-colors ${isDark ? "border-zinc-800 hover:bg-zinc-800/50 bg-zinc-900/30" : "border-zinc-200 hover:bg-zinc-50 bg-zinc-50/50"}',
      attributes: {
        'for': 'file-input-prop-extra',
      },
      [
        input(
          type: InputType.file,
          classes: 'hidden',
          attributes: {
            'id': 'file-input-prop-extra',
            'accept': 'image/*',
            'style': 'display: none;',
          },
          events: {
            'change': (e) {
              _handleExtraFileSelected(e);
            },
          },
        ),

        lIcon('plus', cls: 'w-6 h-6 mb-1 ${isDark ? "text-zinc-500" : "text-zinc-400"}'),
        p(classes: 'text-[10px] font-semibold ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
          Component.text('Add Photo'),
        ]),

        if (isUploading)
          div(
            classes:
                'absolute inset-0 bg-black/60 flex flex-col items-center justify-center text-white backdrop-blur-[2px] animate-fade-in',
            [
              lIcon('loader', cls: 'w-5 h-5 animate-spin mb-1 text-purple-400'),
              p(classes: 'text-[9px] font-semibold', [Component.text('Uploading...')]),
            ],
          ),
      ],
    );
  }
}
