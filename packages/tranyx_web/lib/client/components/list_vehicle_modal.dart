import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import 'package:web/web.dart' as web;
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../components/map_picker.dart';
import '../../constants/contract_drafts.dart';
import '../../services/web_interop.dart';
import '../../services/firebase_service.dart';

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
  List<String> _imageUrls = ['', '', '']; // Requires interior, front, back
  List<bool> _isUploadingImage = [false, false, false];

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

    if (_imageUrls[0].isEmpty) {
      _imageUrls[0] = 'https://via.placeholder.com/400x300?text=Interior';
    }
    if (_imageUrls[1].isEmpty) {
      _imageUrls[1] = 'https://via.placeholder.com/400x300?text=Front';
    }
    if (_imageUrls[2].isEmpty) {
      _imageUrls[2] = 'https://via.placeholder.com/400x300?text=Back';
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final hostId = component.appState.userProfile?.uid;
      if (hostId == null) throw Exception('Not logged in');

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
      await component.appState.firestore.createRentalFromMap(rentalData);

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
                      final selected = VehicleType.values.firstWhere((v) => v.name == (e.target as dynamic).value);
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
                    classes: 'text-[11px] text-zinc-500 italic mt-2 pt-2 border-t ${isDark ? "border-zinc-800/60" : "border-zinc-200"}',
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
                            final val = (e.target as dynamic).value as String;
                            final formatted = _formatLicenseNumber(val);
                            (e.target as dynamic).value = formatted;
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
                      events: {'input': (e) => setState(() => _driverNote = (e.target as dynamic).value)},
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
                Component.text('Tranyx requires 3 photos: Interior, Front, and Back.'),
              ]),
              div(classes: 'grid grid-cols-3 gap-3 mb-6', [
                _photoUploadPlaceholder('Interior', _imageUrls[0], 0, isDark),
                _photoUploadPlaceholder('Front', _imageUrls[1], 1, isDark),
                _photoUploadPlaceholder('Back', _imageUrls[2], 2, isDark),
              ]),

              div(classes: 'mb-4', [
                label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Contract Type'),
                ]),
                select(
                  classes:
                      'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
                  events: {'change': (e) => setState(() => _contractType = (e.target as dynamic).value)},
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
                div(classes: 'p-4 rounded-xl border border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-900/50', [
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
                    div(
                      classes:
                          'mt-3 p-3 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-700 rounded-lg max-h-40 overflow-y-auto',
                      [
                        p(
                          classes:
                              'whitespace-pre-wrap text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"} leading-relaxed',
                          [
                            Component.text(
                              buildDefaultTranyxContract(
                                VehicleRental(
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
                                  pickupAddress: '',
                                  pickupLat: 0,
                                  pickupLng: 0,
                                  createdAt: DateTime.now(),
                                  interiorPhotoUrl: '',
                                  frontPhotoUrl: '',
                                  backPhotoUrl: '',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                ]),
              ] else ...[
                div(classes: 'mt-4', [
                  label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                    Component.text('Custom Contract Terms'),
                  ]),
                  textarea(
                    classes:
                        'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors h-32 resize-none',
                    attributes: {'placeholder': 'Enter your custom terms and conditions for this rental...'},
                    events: {'input': (e) => setState(() => _customTerms = (e.target as dynamic).value)},
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
                              final inputEl = e.target as web.HTMLInputElement?;
                              if (inputEl != null && inputEl.files != null && inputEl.files!.length > 0) {
                                final file = inputEl.files!.item(0);
                                if (file != null) {
                                  final reader = web.FileReader();
                                  final lowerName = file.name.toLowerCase();
                                  if (lowerName.endsWith('.txt') || lowerName.endsWith('.md')) {
                                    reader.readAsText(file);
                                    reader.onLoadEnd.listen((_) {
                                      setState(() {
                                        _customTerms = reader.result.toString();
                                      });
                                    });
                                  } else {
                                    reader.readAsDataURL(file);
                                    reader.onLoadEnd.listen((_) {
                                      setState(() {
                                        _customTerms = '[Uploaded File: ${file.name}]\n${reader.result.toString()}';
                                      });
                                    });
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

            if (_step < 3)
              button(
                classes: 'px-8 py-2 rounded-xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity',
                events: {'click': (e) => _handleNext()},
                [Component.text('Next')],
              )
            else
              button(
                classes:
                    'px-8 py-2 rounded-xl font-bold text-white bg-green-500 hover:bg-green-600 transition-colors flex items-center gap-2',
                events: {'click': (e) => _submit()},
                [
                  if (_isSubmitting) lIcon('loader', cls: 'w-4 h-4 animate-spin'),
                  Component.text(_isSubmitting ? 'Listing...' : 'List Vehicle'),
                ],
              ),
          ]),
        ],
      ),
    ]);
  }

  Component _inputField(
    String labelText,
    String value,
    Function(String) onChange,
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
        attributes: {'value': value, if (placeholder != null) 'placeholder': placeholder},
        events: {'input': (e) => onChange((e.target as dynamic).value)},
      ),
    ]);
  }

  Component _selectField(
    String labelText,
    String selectedValue,
    List<String> optionsList,
    bool isDisabled,
    Function(String) onChange,
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
        events: {'change': (e) => onChange((e.target as dynamic).value)},
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
    return label(
      classes:
          'relative aspect-video rounded-2xl border border-dashed flex flex-col items-center justify-center cursor-pointer overflow-hidden transition-colors ${isDark ? "border-zinc-800 hover:bg-zinc-800/50 bg-zinc-900/30" : "border-zinc-200 hover:bg-zinc-50 bg-zinc-50/50"}',
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
                'absolute inset-0 bg-black/60 flex flex-col items-center justify-center text-white backdrop-blur-[2px] animate-fade-in',
            [
              lIcon('loader', cls: 'w-6 h-6 animate-spin mb-2 text-purple-400'),
              p(classes: 'text-xs font-semibold', [Component.text('Uploading...')]),
            ],
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
