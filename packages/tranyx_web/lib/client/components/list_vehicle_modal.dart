import 'dart:js_interop';
import 'dart:js_interop_unsafe';
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

class ListVehicleModalComponent extends StatefulComponent {
  final TranyxAppState appState;
  const ListVehicleModalComponent({required this.appState, super.key});

  @override
  State<ListVehicleModalComponent> createState() => _ListVehicleModalState();
}

class _ListVehicleModalState extends State<ListVehicleModalComponent> {
  int _step = 1;

  @override
  void initState() {
    super.initState();
    component.appState.pickupAddress = '';
    component.appState.pickupLat = null;
    component.appState.pickupLng = null;
  }

  // Form Fields
  VehicleType _selectedType = VehicleType.car;
  String _brand = '';
  String _model = '';
  String _year = '';
  String _plateNumber = '';
  String _fuelType = 'Gasoline'; // 'Gasoline', 'Diesel', 'Electric', 'Hybrid'
  String _transmission = 'Automatic'; // 'Automatic', 'Manual'

  // Pricing
  String _price12h = '';
  String _priceDaily = '';
  String _priceWeekly = '';
  String _priceMonthly = '';
  String _extensionPenaltyPerHour = '';

  // Location
  String _pickupAddress = '';
  double? _pickupLat;
  double? _pickupLng;

  // Driver Services
  bool _offersDriver = false;
  String _driverDailyPrice = '';
  String _driverNote = '';
  String _driverLicenseNumber = '';

  String _contractType = 'Tranyx Standard';
  String _customTerms = '';
  bool _showPreview = false;

  // Images
  final List<String> _imageUrls = ['', '', '']; // Requires interior, front, back
  final List<bool> _isUploadingImage = [false, false, false];

  bool _isSubmitting = false;
  String? _error;
  String _gpsTrackerId = ''; // GPS Hardware Registry ID

  // Derived calculations
  double get _listingFee {
    final daily = double.tryParse(_priceDaily) ?? 0;
    return daily * 0.015; // 1.5% of daily rate
  }

  void _submit() async {
    final mapAddress = component.appState.pickupAddress;
    final mapLat = component.appState.pickupLat;
    final mapLng = component.appState.pickupLng;

    if (mapAddress.isEmpty) {
      setState(() => _error = 'Please select and confirm a vehicle pickup location on the map picker (Step 2).');
      return;
    }

    _pickupAddress = mapAddress;
    _pickupLat = mapLat;
    _pickupLng = mapLng;

    if (_brand.isEmpty || _model.isEmpty || _year.isEmpty || _plateNumber.isEmpty) {
      setState(() => _error = 'Please fill out all vehicle details.');
      return;
    }

    if (component.appState.checkProfanity(_brand) ||
        component.appState.checkProfanity(_model) ||
        component.appState.checkProfanity(_pickupAddress) ||
        (_contractType == 'Custom Contract' && component.appState.checkProfanity(_customTerms))) {
      setState(() => _error = 'Your listing details contain inappropriate language. Please review and try again.');
      return;
    }

    if (!_isValidPhilippinePlate(_plateNumber)) {
      setState(
        () => _error = 'Please enter a valid Philippine Plate Number (e.g. ABC-1234, MC-12345) or MV File Number.',
      );
      return;
    }
    final daily = double.tryParse(_priceDaily) ?? 0;
    if (daily <= 0) {
      setState(() => _error = 'Please provide a valid daily rate.');
      return;
    }
    if (_contractType == 'Custom Contract' && _customTerms.trim().isEmpty) {
      setState(() => _error = 'Please enter your custom contract terms.');
      return;
    }

    if (_imageUrls.length < 3 || _imageUrls[0].isEmpty || _imageUrls[1].isEmpty || _imageUrls[2].isEmpty) {
      setState(() => _error = 'Please upload all required photos (Interior, Front, and Back) before listing.');
      return;
    }

    if (_isUploadingImage.any((uploading) => uploading)) {
      setState(() => _error = 'Please wait for all image uploads to finish.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final hostId = component.appState.userProfile?.uid;
      if (hostId == null) throw FirebaseException('Not logged in', 403);

      final user = component.appState.userProfile;
      if (user == null) throw Exception('User profile not loaded.');

      final rental = VehicleRental(
        id: '',
        hostId: hostId,
        hostName: user.name,
        type: _selectedType,
        brand: _brand,
        model: _model,
        year: int.tryParse(_year) ?? DateTime.now().year,
        plateNumber: _plateNumber,
        fuelType: _fuelType,
        transmission: _transmission,
        interiorPhotoUrl: _imageUrls.isNotEmpty ? _imageUrls[0] : '',
        frontPhotoUrl: _imageUrls.length > 1 ? _imageUrls[1] : '',
        backPhotoUrl: _imageUrls.length > 2 ? _imageUrls[2] : '',
        price12h: double.tryParse(_price12h) ?? 0,
        priceDaily: daily,
        priceWeekly: double.tryParse(_priceWeekly) ?? 0,
        priceMonthly: double.tryParse(_priceMonthly) ?? 0,
        extensionRatePerHour: double.tryParse(_extensionPenaltyPerHour) ?? (daily / 24 * 1.5),
        latePenaltyRatePerHour: double.tryParse(_extensionPenaltyPerHour) ?? (daily / 24 * 1.5),
        pickupAddress: _pickupAddress.isNotEmpty ? _pickupAddress : 'Default Garage',
        pickupLat: _pickupLat ?? 14.5995,
        pickupLng: _pickupLng ?? 120.9842,
        status: 'Available',
        createdAt: DateTime.now(),
        // mock the required fields that we don't have inputs for yet:
        vehicleValue: 0,
        ltoCrNumber: 'PENDING',
        ltoOrNumber: 'PENDING',
        insuranceProvider: 'N/A',
        insurancePolicyNumber: 'N/A',
        contractType: _contractType,
        contractTerms: _contractType == 'Custom Contract' ? _customTerms : 'Standard P2P terms',
        offersDriver: _offersDriver,
        driverDailyPrice: double.tryParse(_driverDailyPrice) ?? 0.0,
        driverNote: _driverNote,
        driverLicenseNumber: _driverLicenseNumber,
      );

      // Create vehicle listing with GPS tracker info
      final rentalData = rental.toMap();
      if (_gpsTrackerId.trim().isNotEmpty) {
        rentalData['gpsTrackerId'] = _gpsTrackerId.trim();
      }
      if (_imageUrls.length > 3) {
        rentalData['extraPhotos'] = _imageUrls.sublist(3).where((url) => url.isNotEmpty).toList();
      }
      await component.appState.firestore.createRentalFromMap(rentalData);

      // Reload profile & transactions to display balance deduction and transaction log promptly
      await component.appState.loadUserProfile();
      await component.appState.loadTransactions();

      // Close modal
      component.appState.setState(() {
        component.appState.showListVehicleModal = false;
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
      if (_brand.trim().isEmpty || _model.trim().isEmpty || _year.trim().isEmpty || _plateNumber.trim().isEmpty) {
        setState(() => _error = 'Please fill out all vehicle specifications.');
        return;
      }
      if (int.tryParse(_year) == null) {
        setState(() => _error = 'Year must be a valid number.');
        return;
      }
      if (!_isValidPhilippinePlate(_plateNumber)) {
        setState(
          () => _error = 'Please enter a valid Philippine Plate Number (e.g. ABC-1234, MC-12345) or MV File Number.',
        );
        return;
      }
    } else if (_step == 2) {
      if (_priceDaily.trim().isEmpty) {
        setState(() => _error = 'Please provide a daily rate.');
        return;
      }
      if (double.tryParse(_priceDaily) == null || double.parse(_priceDaily) <= 0) {
        setState(() => _error = 'Daily rate must be a valid number greater than 0.');
        return;
      }
      if (_offersDriver) {
        if (_driverDailyPrice.trim().isEmpty ||
            double.tryParse(_driverDailyPrice) == null ||
            double.parse(_driverDailyPrice) < 0) {
          setState(() => _error = 'Please enter a valid driver daily rate.');
          return;
        }
        final cleanedLicense = _driverLicenseNumber.replaceAll(RegExp(r'[\s-]'), '');
        if (cleanedLicense.length != 11) {
          setState(() => _error = 'Please enter a valid Driver\'s License Number (11 characters).');
          return;
        }
        if (_driverNote.trim().isEmpty) {
          setState(() => _error = 'Please provide a driver note.');
          return;
        }
      }
      if (component.appState.pickupAddress.isEmpty) {
        setState(() => _error = 'Please select and confirm a vehicle location on the map picker.');
        return;
      }
      _pickupAddress = component.appState.pickupAddress;
      _pickupLat = component.appState.pickupLat;
      _pickupLng = component.appState.pickupLng;
    }

    setState(() => _step++);
  }

  @override
  Component build(BuildContext context) {
    if (!component.appState.showListVehicleModal) return div([]);
    final isDark = component.appState.isDark;

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
                h2(classes: 'text-2xl font-bold', [Component.text('List a Vehicle')]),
                p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                  Component.text('Step $_step of 3'),
                ]),
              ]),
              button(
                classes: 'p-2 rounded-full hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors',
                events: {
                  'click': (e) => component.appState.setState(() => component.appState.showListVehicleModal = false),
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
              // Step 1: Specs
              h3(classes: 'text-lg font-bold mb-4', [Component.text('Vehicle Specifications')]),

              div(classes: 'mb-4', [
                label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Vehicle Type'),
                ]),
                select(
                  classes:
                      'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
                  events: {
                    'change': (e) {
                      final selected = VehicleType.values.firstWhere((v) => v.name == getInputValue(e.target));
                      setState(() {
                        _selectedType = selected;
                        _brand = '';
                        _model = '';
                        _year = '';
                      });
                    },
                  },
                  [
                    for (final t in VehicleType.values)
                      option(value: t.name, selected: _selectedType == t, [Component.text(t.name.toUpperCase())]),
                  ],
                ),
              ]),

              div(classes: 'grid grid-cols-2 gap-4 mb-4', [
                div(classes: '', [
                  label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                    Component.text('Engine / Fuel Type'),
                  ]),
                  select(
                    classes:
                        'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
                    events: {
                      'change': (e) {
                        setState(() {
                          _fuelType = getInputValue(e.target);
                        });
                      },
                    },
                    [
                      option(value: 'Gasoline', selected: _fuelType == 'Gasoline', [Component.text('Gasoline')]),
                      option(value: 'Diesel', selected: _fuelType == 'Diesel', [Component.text('Diesel')]),
                      option(value: 'Electric', selected: _fuelType == 'Electric', [Component.text('Electric')]),
                      option(value: 'Hybrid', selected: _fuelType == 'Hybrid', [Component.text('Hybrid')]),
                    ],
                  ),
                ]),
                div(classes: '', [
                  label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                    Component.text('Transmission'),
                  ]),
                  select(
                    classes:
                        'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
                    events: {
                      'change': (e) {
                        setState(() {
                          _transmission = getInputValue(e.target);
                        });
                      },
                    },
                    [
                      option(value: 'Automatic', selected: _transmission == 'Automatic', [Component.text('Automatic')]),
                      option(value: 'Manual', selected: _transmission == 'Manual', [Component.text('Manual')]),
                    ],
                  ),
                ]),
              ]),

              div(classes: 'grid grid-cols-2 gap-4', [
                _selectField(
                  'Brand',
                  _brand,
                  VehicleSpecDatabase.modelsByTypeAndBrand[_selectedType]?.keys.toList() ?? [],
                  false,
                  (v) => setState(() {
                    _brand = v;
                    _model = '';
                    _year = '';
                  }),
                  isDark,
                  placeholder: 'Select Brand',
                ),

                _selectField(
                  'Model',
                  _model,
                  _brand.isEmpty ? [] : (VehicleSpecDatabase.modelsByTypeAndBrand[_selectedType]?[_brand] ?? []),
                  _brand.isEmpty,
                  (v) => setState(() {
                    _model = v;
                    _year = '';
                  }),
                  isDark,
                  placeholder: 'Select Model',
                ),

                _selectField(
                  'Year',
                  _year,
                  _model.isEmpty ? [] : VehicleSpecDatabase.getYearsForModel(_model).map((y) => y.toString()).toList(),
                  _model.isEmpty,
                  (v) => setState(() => _year = v),
                  isDark,
                  placeholder: 'Select Year',
                ),

                _inputField(
                  'Plate Number',
                  _plateNumber,
                  (v) => setState(() => _plateNumber = _formatPlateNumber(v)),
                  isDark,
                  placeholder: 'ABC-1234',
                ),
              ]),

              // GPS Tracker Registry
              div(
                classes:
                    'mt-4 p-4 rounded-xl border ${isDark ? "bg-zinc-800/30 border-zinc-700" : "bg-blue-50 border-blue-200"}',
                [
                  div(classes: 'flex items-center gap-2 mb-2', [
                    lIcon('map-pin', cls: 'w-4 h-4 ${isDark ? "text-blue-400" : "text-blue-500"}'),
                    label(classes: 'text-sm font-semibold ${isDark ? "text-blue-300" : "text-blue-700"}', [
                      Component.text('GPS Tracker ID (Optional)'),
                    ]),
                    span(classes: 'text-[10px] px-1.5 py-0.5 rounded bg-blue-500/20 text-blue-400 font-bold', [
                      Component.text('NEW'),
                    ]),
                  ]),
                  p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"} mb-3', [
                    Component.text(
                      'Enter your GPS device serial number (e.g. Traffilink, GovLink, Carlock). Listings with a verified GPS ID display a "GPS Tracked" badge — increases renter confidence and earns priority placement.',
                    ),
                  ]),
                  _inputField(
                    'GPS Device Serial / Tracker ID',
                    _gpsTrackerId,
                    (v) => setState(() => _gpsTrackerId = v.trim()),
                    isDark,
                    placeholder: 'e.g. TFL-2024-XXXXX',
                  ),
                  p(
                    classes:
                        'text-[11px] text-zinc-500 italic mt-2 pt-2 border-t ${isDark ? "border-zinc-800/60" : "border-zinc-200"}',
                    [
                      Component.text(
                        'Note: Real-time vehicle tracking functions only when the active renter is logged into the app on their device with location permissions enabled.',
                      ),
                    ],
                  ),
                ],
              ),
            ] else if (_step == 2) ...[
              // Step 2: Pricing & Location
              h3(classes: 'text-lg font-bold mb-4', [Component.text('Pricing & Location')]),
              div(classes: 'grid grid-cols-2 gap-4', [
                _inputField(
                  'Daily Rate (Required)',
                  _priceDaily,
                  (v) => setState(() => _priceDaily = v),
                  isDark,
                  placeholder: '2500',
                  type: InputType.number,
                ),
                _inputField(
                  '12-Hour Rate',
                  _price12h,
                  (v) => setState(() => _price12h = v),
                  isDark,
                  placeholder: '1500',
                  type: InputType.number,
                ),
                _inputField(
                  'Weekly Rate',
                  _priceWeekly,
                  (v) => setState(() => _priceWeekly = v),
                  isDark,
                  placeholder: '15000',
                  type: InputType.number,
                ),
                _inputField(
                  'Monthly Rate',
                  _priceMonthly,
                  (v) => setState(() => _priceMonthly = v),
                  isDark,
                  placeholder: '50000',
                  type: InputType.number,
                ),
              ]),
              div(classes: 'mt-4', [
                _inputField(
                  'Late Penalty (Per Hour)',
                  _extensionPenaltyPerHour,
                  (v) => setState(() => _extensionPenaltyPerHour = v),
                  isDark,
                  placeholder: 'e.g. 200',
                  type: InputType.number,
                ),
              ]),
              div(classes: 'mt-6 p-4 rounded-xl bg-purple-500/10 border border-purple-500/20 mb-6', [
                div(classes: 'flex justify-between text-sm mb-2', [
                  span(classes: isDark ? 'text-zinc-400' : 'text-zinc-600', [
                    Component.text('Platform Listing Fee (1.5% of Daily)'),
                  ]),
                  span(classes: 'font-bold text-purple-400', [Component.text('${_listingFee.toStringAsFixed(2)} TYX')]),
                ]),
                p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                  Component.text('To maintain quality, a small anti-spam fee is required to list your vehicle.'),
                ]),
              ]),
              // Driver services option
              div(classes: 'mt-6 border-t ${isDark ? "border-zinc-800" : "border-zinc-200"} pt-6', [
                div(classes: 'flex items-center justify-between mb-4', [
                  label(classes: 'block text-sm font-semibold ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                    Component.text('Offer Driver Services (Host provides driver / serves as driver)'),
                  ]),
                  input<bool>(
                    type: InputType.checkbox,
                    classes: 'rounded border-zinc-300 text-purple-600 focus:ring-purple-500 w-5 h-5 cursor-pointer',
                    checked: _offersDriver,
                    onChange: (val) => setState(() => _offersDriver = val),
                  ),
                ]),
                if (_offersDriver) ...[
                  div(classes: 'grid grid-cols-2 gap-4 mb-4', [
                    _inputField(
                      'Driver Daily Rate (TYX)',
                      _driverDailyPrice,
                      (v) => setState(() => _driverDailyPrice = v),
                      isDark,
                      placeholder: '500',
                      type: InputType.number,
                    ),
                    div(classes: '', [
                      label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                        Component.text('Driver\'s License Number'),
                      ]),
                      input(
                        classes:
                            'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
                        attributes: {'value': _driverLicenseNumber, 'placeholder': 'e.g. N01-23-456789'},
                        events: {
                          'input': (e) {
                            final val = getInputValue(e.target);
                            final formatted = _formatLicenseNumber(val);
                            setInputValue(e.target, formatted);
                            setState(() => _driverLicenseNumber = formatted);
                          },
                        },
                      ),
                    ]),
                  ]),
                  div(classes: 'mb-4', [
                    label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                      Component.text('Driver Notes / Details'),
                    ]),
                    textarea(
                      classes:
                          'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
                      rows: 3,
                      attributes: {
                        'placeholder':
                            'e.g. Professional driver with 5+ years clean record, familiar with Metro Manila routes.',
                      },
                      events: {'input': (e) => setState(() => _driverNote = getInputValue(e.target))},
                      [Component.text(_driverNote)],
                    ),
                  ]),
                ],
              ]),

              div(classes: 'mt-6 border-t ${isDark ? "border-zinc-800" : "border-zinc-200"} pt-6', [
                label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Set Vehicle Pickup Location'),
                ]),
                p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"} mb-3', [
                  Component.text(
                    'Pan the map to the location of your vehicle and click "Confirm Site Location" to set it.',
                  ),
                ]),
                MapPickerComponent(state: component.appState),
              ]),
            ] else if (_step == 3) ...[
              // Step 3: Photos & Contracts
              h3(classes: 'text-lg font-bold mb-4', [Component.text('Photos & Legal')]),
              p(classes: 'text-sm mb-4 ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                Component.text(
                  'Tranyx requires 3 photos: Interior, Front, and Back. You can also upload additional photos.',
                ),
              ]),
              div(classes: 'space-y-4 mb-6', [
                div(classes: 'grid grid-cols-3 gap-3', [
                  for (int i = 0; i < _imageUrls.length; i++)
                    _photoUploadPlaceholder(
                      i == 0
                          ? 'Interior'
                          : i == 1
                          ? 'Front'
                          : i == 2
                          ? 'Back'
                          : 'Extra Photo ${i - 2}',
                      _imageUrls[i],
                      i,
                      isDark,
                    ),
                ]),
                button(
                  classes:
                      'px-4 py-2.5 rounded-xl font-bold text-xs flex items-center justify-center gap-2 border '
                      '${isDark ? "border-zinc-700 hover:bg-zinc-800 bg-zinc-800/30 text-purple-400 hover:text-purple-300" : "border-zinc-300 hover:bg-zinc-50 bg-zinc-50/20 text-purple-600 hover:text-purple-700"} transition-all cursor-pointer',
                  events: {
                    'click': (_) {
                      setState(() {
                        _imageUrls.add('');
                        _isUploadingImage.add(false);
                      });
                    },
                  },
                  [
                    lIcon('plus', cls: 'w-4 h-4'),
                    Component.text('Add More Photos'),
                  ],
                ),
              ]),

              div(classes: 'mb-4', [
                label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Contract Type'),
                ]),
                select(
                  classes:
                      'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
                  events: {'change': (e) => setState(() => _contractType = getInputValue(e.target))},
                  [
                    option(value: 'Tranyx Standard', selected: _contractType == 'Tranyx Standard', [
                      Component.text('Tranyx Standard'),
                    ]),
                    option(value: 'Custom Contract', selected: _contractType == 'Custom Contract', [
                      Component.text('Custom Contract'),
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
                        h4(classes: 'font-bold', [Component.text('Tranyx Rental Contract')]),
                      ]),
                      button(
                        classes: 'text-xs text-blue-500 hover:underline',
                        events: {'click': (_) => setState(() => _showPreview = !_showPreview)},
                        [Component.text(_showPreview ? 'Hide Preview' : 'View Contract')],
                      ),
                    ]),
                    p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"} mb-2', [
                      Component.text(
                        'By proceeding, you agree to our standard P2P Rental Agreement underwritten by our partner legal firm.',
                      ),
                    ]),
                    if (_showPreview)
                      ContractViewerComponent(
                        vehicleRental: VehicleRental(
                          id: '',
                          hostId: '',
                          hostName: component.appState.userProfile?.name ?? 'Owner',
                          brand: _brand,
                          model: _model,
                          year: int.tryParse(_year) ?? 2022,
                          plateNumber: _plateNumber,
                          type: _selectedType,
                          vehicleValue: 0,
                          ltoCrNumber: 'PENDING',
                          ltoOrNumber: 'PENDING',
                          insuranceProvider: 'N/A',
                          insurancePolicyNumber: 'N/A',
                          contractType: 'Tranyx Standard',
                          contractTerms: '',
                          price12h: double.tryParse(_price12h) ?? 0,
                          priceDaily: double.tryParse(_priceDaily) ?? 0,
                          priceWeekly: double.tryParse(_priceWeekly) ?? 0,
                          priceMonthly: double.tryParse(_priceMonthly) ?? 0,
                          extensionRatePerHour: double.tryParse(_extensionPenaltyPerHour) ?? 0,
                          latePenaltyRatePerHour: double.tryParse(_extensionPenaltyPerHour) ?? 0,
                          status: 'Available',
                          fuelType: _fuelType,
                          transmission: _transmission,
                          pickupAddress: _pickupAddress.isNotEmpty ? _pickupAddress : component.appState.pickupAddress,
                          pickupLat: _pickupLat ?? component.appState.pickupLat ?? 0.0,
                          pickupLng: _pickupLng ?? component.appState.pickupLng ?? 0.0,
                          createdAt: DateTime.now(),
                          interiorPhotoUrl: '',
                          frontPhotoUrl: '',
                          backPhotoUrl: '',
                        ),
                      ),
                  ],
                ),
              ] else ...[
                div(classes: 'mt-4', [
                  label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                    Component.text('Custom Contract Terms'),
                  ]),
                  textarea(
                    classes:
                        'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors h-32 resize-none',
                    attributes: {'placeholder': 'Enter your custom terms and conditions for this rental...'},
                    events: {'input': (e) => setState(() => _customTerms = getInputValue(e.target))},
                    [Component.text(_customTerms)],
                  ),
                  div(classes: 'mt-3 flex items-center gap-3', [
                    span(classes: 'text-xs text-zinc-500 font-medium', [
                      Component.text('Or upload a contract terms file:'),
                    ]),
                    label(
                      classes:
                          'px-3 py-1.5 rounded-lg text-xs font-semibold bg-purple-600 hover:bg-purple-700 text-white cursor-pointer transition-colors',
                      attributes: {'for': 'custom-contract-upload'},
                      [
                        Component.text('Upload Terms'),
                        input(
                          type: InputType.file,
                          classes: 'hidden',
                          attributes: {
                            'id': 'custom-contract-upload',
                            'accept': '.txt,.md,.pdf,.png,.jpg,.jpeg',
                            'style': 'display: none;',
                          },
                          events: {
                            'change': (e) {
                              final targetObj = e.target as JSObject?;
                              if (targetObj != null && targetObj.hasProperty('files'.toJS).toDart) {
                                final filesObj = targetObj.getProperty<JSObject>('files'.toJS);
                                if (filesObj.hasProperty('length'.toJS).toDart) {
                                  final len = (filesObj.getProperty('length'.toJS) as JSNumber).toDartInt;
                                  if (len > 0) {
                                    final file = filesObj.callMethod<JSObject?>('item'.toJS, 0.toJS);
                                    if (file != null) {
                                      final reader = web.FileReader();
                                      final name = (file.getProperty('name'.toJS) as JSString).toDart;
                                      final lowerName = name.toLowerCase();
                                      if (lowerName.endsWith('.txt') || lowerName.endsWith('.md')) {
                                        reader.readAsText(file as web.Blob);
                                        reader.onLoadEnd.listen((_) {
                                          setState(() {
                                            _customTerms = reader.result.toString();
                                          });
                                        });
                                      } else {
                                        reader.readAsDataURL(file as web.Blob);
                                        reader.onLoadEnd.listen((_) {
                                          setState(() {
                                            _customTerms = '[Uploaded File: $name]\n${reader.result.toString()}';
                                          });
                                        });
                                      }
                                    }
                                  }
                                }
                              }
                            },
                          },
                        ),
                      ],
                    ),
                  ]),
                ]),
              ],

              Builder(
                builder: (context) {
                  final dailyRate = double.tryParse(_priceDaily) ?? 0.0;
                  final weeklyRate = double.tryParse(_priceWeekly) ?? 0.0;
                  final monthlyRate = double.tryParse(_priceMonthly) ?? 0.0;
                  final rate12h = double.tryParse(_price12h) ?? 0.0;

                  // Listing Fee (1.5% of Daily Rate)
                  final listingFee = dailyRate * 0.015;

                  // Standard Platform commission fee: 3% deducted from payout
                  final commissionDaily = dailyRate * 0.03;
                  final payoutDaily = dailyRate - commissionDaily;

                  final commission12h = rate12h * 0.03;
                  final payout12h = rate12h - commission12h;

                  final commissionWeekly = weeklyRate * 0.03;
                  final payoutWeekly = weeklyRate - commissionWeekly;

                  final commissionMonthly = monthlyRate * 0.03;
                  final payoutMonthly = monthlyRate - commissionMonthly;

                  if (dailyRate <= 0 && rate12h <= 0 && weeklyRate <= 0 && monthlyRate <= 0) {
                    return div([]);
                  }

                  return div(
                    classes: 'mt-6 p-5 rounded-2xl border ${isDark ? "border-zinc-800 bg-zinc-900/50" : "border-zinc-200 bg-zinc-50"} space-y-3.5',
                    [
                      p(classes: 'text-xs font-bold text-indigo-400 uppercase tracking-wider', [Component.text('Listing Payment & Earnings Breakdown')]),
                      div(classes: 'space-y-2.5', [
                        // Rates & Earnings
                        if (rate12h > 0)
                          div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                            span([Component.text('12-Hour Rental: ₱${rate12h.toStringAsFixed(2)}')]),
                            span(classes: 'font-semibold ${isDark ? "text-zinc-200" : "text-zinc-700"}', [
                              Component.text('Payout: ₱${payout12h.toStringAsFixed(2)} (Net of 3% platform commission)')
                            ]),
                          ]),
                        if (dailyRate > 0)
                          div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                            span([Component.text('Daily Rental: ₱${dailyRate.toStringAsFixed(2)}')]),
                            span(classes: 'font-semibold ${isDark ? "text-zinc-200" : "text-zinc-700"}', [
                              Component.text('Payout: ₱${payoutDaily.toStringAsFixed(2)} (Net of 3% platform commission)')
                            ]),
                          ]),
                        if (weeklyRate > 0)
                          div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                            span([Component.text('Weekly Rental: ₱${weeklyRate.toStringAsFixed(2)}')]),
                            span(classes: 'font-semibold ${isDark ? "text-zinc-200" : "text-zinc-700"}', [
                              Component.text('Payout: ₱${payoutWeekly.toStringAsFixed(2)} (Net of 3% platform commission)')
                            ]),
                          ]),
                        if (monthlyRate > 0)
                          div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                            span([Component.text('Monthly Rental: ₱${monthlyRate.toStringAsFixed(2)}')]),
                            span(classes: 'font-semibold ${isDark ? "text-zinc-200" : "text-zinc-700"}', [
                              Component.text('Payout: ₱${payoutMonthly.toStringAsFixed(2)} (Net of 3% platform commission)')
                            ]),
                          ]),
                        // Separator
                        div(classes: 'border-t ${isDark ? "border-zinc-800" : "border-zinc-200"} my-2', []),
                        // Listing anti-spam fee
                        div(classes: 'flex justify-between items-center text-xs text-zinc-400', [
                          span([Component.text('Anti-Spam Listing Fee (1.5% of Daily):')]),
                          span(classes: 'font-semibold text-purple-400', [
                            Component.text('${listingFee.toStringAsFixed(2)} TYX')
                          ]),
                        ]),
                      ]),
                      p(classes: 'text-[10px] text-zinc-500 leading-normal', [
                        Component.text(
                          'Notice: A listing fee of ${listingFee.toStringAsFixed(2)} TYX will be charged to your wallet now. A platform service fee of 3% is only deducted from your earnings upon successful rental completion.',
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
                  classes: 'px-8 py-2 rounded-xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity border-0 cursor-pointer',
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
                    Component.text(_isSubmitting ? 'Listing...' : 'List Vehicle'),
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
            'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
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

  Component _selectField(
    String labelText,
    String selectedValue,
    List<String> optionsList,
    bool isDisabled,
    void Function(String) onChange,
    bool isDark, {
    String placeholder = 'Select Option',
  }) {
    return div([
      label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
        Component.text(labelText),
      ]),
      select(
        classes:
            'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} ${isDisabled ? "opacity-50 cursor-not-allowed" : "cursor-pointer"} outline-none focus:border-purple-500 transition-colors',
        attributes: isDisabled ? {'disabled': 'disabled'} : {},
        events: {
          'change': (e) {
            onChange(getInputValue(e.target));
          },
        },
        [
          option(value: '', selected: selectedValue.isEmpty, [Component.text(placeholder)]),
          for (final opt in optionsList) option(value: opt, selected: selectedValue == opt, [Component.text(opt)]),
        ],
      ),
    ]);
  }

  bool _isValidPhilippinePlate(String plate) {
    final cleaned = plate.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (cleaned.isEmpty) return false;

    // Check 1: Standard LTO format (1-5 letters + 1-5 digits)
    final ltoRegex = RegExp(r'^[A-Z]{1,5}\d{1,5}$');
    if (ltoRegex.hasMatch(cleaned)) return true;

    // Check 2: MV File Number format (9-12 digits)
    final mvRegex = RegExp(r'^\d{9,12}$');
    if (mvRegex.hasMatch(cleaned)) return true;

    return false;
  }

  String _formatPlateNumber(String val) {
    // Upper case and strip any character that is not alphanumeric, space, or hyphen
    final cleaned = val.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\s-]'), '');

    final digitsOnly = cleaned.replaceAll(RegExp(r'\D'), '');
    final lettersDigitsOnly = cleaned.replaceAll(RegExp(r'[\s-]'), '');

    // If it's all digits or starts with digits (potential MV File Number)
    if (RegExp(r'^\d').hasMatch(lettersDigitsOnly)) {
      if (digitsOnly.length > 4) {
        return '${digitsOnly.substring(0, 4)}-${digitsOnly.substring(4, digitsOnly.length > 11 ? 11 : digitsOnly.length)}';
      }
      return digitsOnly;
    }

    // Standard plate format (starts with letters)
    final letterMatches = RegExp(r'^[A-Z]+').firstMatch(lettersDigitsOnly);
    if (letterMatches != null) {
      final letters = letterMatches.group(0)!;
      final truncatedLetters = letters.substring(0, letters.length > 5 ? 5 : letters.length);
      final digits = lettersDigitsOnly.substring(letters.length);
      final truncatedDigits = digits.substring(0, digits.length > 5 ? 5 : digits.length);

      if (truncatedDigits.isNotEmpty) {
        return '$truncatedLetters-$truncatedDigits';
      } else {
        return truncatedLetters;
      }
    }

    return cleaned;
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
    final showRemove = index >= 3;

    return div(
      classes:
          'relative aspect-video rounded-2xl overflow-hidden border border-dashed ${isDark ? "border-zinc-800 bg-zinc-900/30" : "border-zinc-200 bg-zinc-50/50"}',
      [
        label(
          classes:
              'w-full h-full flex flex-col items-center justify-center cursor-pointer transition-colors hover:opacity-90',
          attributes: {
            'for': 'file-input-$index',
          },
          [
            input(
              type: InputType.file,
              classes: 'hidden',
              attributes: {
                'id': 'file-input-$index',
                'accept': 'image/*',
                'style': 'display: none;',
              },
              events: {
                'change': (e) {
                  _handleFileSelected(e, index);
                },
              },
            ),

            if (currentUrl.isNotEmpty)
              img(
                src: currentUrl,
                classes: 'w-full h-full object-cover',
                attributes: {'alt': labelText},
              )
            else ...[
              lIcon('camera', cls: 'w-6 h-6 mb-2 ${isDark ? "text-zinc-500" : "text-zinc-400"}'),
              p(classes: 'text-xs font-semibold ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                Component.text(labelText),
              ]),
            ],

            if (isUploading)
              div(
                classes:
                    'absolute inset-0 bg-black/60 flex flex-col items-center justify-center text-white backdrop-blur-[2px] z-10 animate-fade-in',
                [
                  lIcon('loader', cls: 'w-6 h-6 animate-spin mb-2 text-purple-400'),
                  p(classes: 'text-xs font-semibold', [Component.text('Uploading...')]),
                ],
              ),
          ],
        ),
        if (showRemove)
          button(
            classes:
                'absolute top-2 right-2 p-1.5 rounded-full bg-red-600 hover:bg-red-700 text-white shadow-md transition-colors z-20 border-none outline-none cursor-pointer',
            events: {
              'click': (e) {
                setState(() {
                  _imageUrls.removeAt(index);
                  _isUploadingImage.removeAt(index);
                });
              },
            },
            [lIcon('trash-2', cls: 'w-3.5 h-3.5')],
          ),
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
}
