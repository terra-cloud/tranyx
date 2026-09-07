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

class EditVehicleModalComponent extends StatefulComponent {
  final TranyxAppState appState;
  const EditVehicleModalComponent({required this.appState, super.key});

  @override
  State<EditVehicleModalComponent> createState() => _EditVehicleModalState();
}

class _EditVehicleModalState extends State<EditVehicleModalComponent> {
  int _step = 1;
  String? _rentalId;

  // Form Fields
  VehicleType _selectedType = VehicleType.car;
  String _brand = '';
  String _model = '';
  String _year = '';
  String _plateNumber = '';
  String _fuelType = 'Gasoline';
  String _transmission = 'Automatic';

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
  final List<String> _imageUrls = ['', '', ''];
  final List<bool> _isUploadingImage = [false, false, false];

  bool _isSubmitting = false;
  String? _error;
  String _gpsTrackerId = '';

  // LTO Registration & Comprehensive Insurance Compliance
  String _ltoCrNumber = '';
  String _ltoOrNumber = '';
  String _insuranceProvider = 'N/A';
  String _insurancePolicyNumber = '';
  String _vehicleValue = '';

  @override
  void initState() {
    super.initState();
    final r = component.appState.selectedRentalData;
    if (r != null) {
      _rentalId = r['id']?.toString();
      _brand = r['brand']?.toString() ?? '';
      _model = r['model']?.toString() ?? '';
      _year = (r['year'] ?? '').toString();
      _plateNumber = r['plateNumber']?.toString() ?? '';

      final typeStr = r['type']?.toString() ?? r['vehicleType']?.toString() ?? '';
      _selectedType = VehicleType.values.firstWhere(
        (v) => v.name == typeStr || typeStr.endsWith('.${v.name}'),
        orElse: () => VehicleType.car,
      );

      _fuelType = r['fuelType']?.toString() ?? 'Gasoline';
      _transmission = r['transmission']?.toString() ?? 'Automatic';
      _gpsTrackerId = r['gpsTrackerId']?.toString() ?? '';

      // Compliance
      _ltoCrNumber = r['ltoCrNumber']?.toString() ?? '';
      _ltoOrNumber = r['ltoOrNumber']?.toString() ?? '';
      _insuranceProvider = r['insuranceProvider']?.toString() ?? 'N/A';
      _insurancePolicyNumber = r['insurancePolicyNumber']?.toString() ?? '';
      final valNum = (r['vehicleValue'] as num?)?.toDouble() ?? 0.0;
      _vehicleValue = valNum > 0 ? valNum.toStringAsFixed(0) : '';

      // Pricing
      final daily = (r['priceDaily'] as num?)?.toDouble() ?? (r['dailyRate'] as num?)?.toDouble() ?? 0.0;
      final p12h = (r['price12h'] as num?)?.toDouble() ?? 0.0;
      final weekly = (r['priceWeekly'] as num?)?.toDouble() ?? 0.0;
      final monthly = (r['priceMonthly'] as num?)?.toDouble() ?? 0.0;
      final ext = (r['extensionRatePerHour'] as num?)?.toDouble() ?? (r['latePenaltyRatePerHour'] as num?)?.toDouble() ?? 0.0;

      _priceDaily = daily > 0 ? daily.toStringAsFixed(0) : '';
      _price12h = p12h > 0 ? p12h.toStringAsFixed(0) : '';
      _priceWeekly = weekly > 0 ? weekly.toStringAsFixed(0) : '';
      _priceMonthly = monthly > 0 ? monthly.toStringAsFixed(0) : '';
      _extensionPenaltyPerHour = ext > 0 ? ext.toStringAsFixed(0) : '';

      // Driver
      _offersDriver = r['offersDriver'] == true;
      final drvPrice = (r['driverDailyPrice'] as num?)?.toDouble() ?? 0.0;
      _driverDailyPrice = drvPrice > 0 ? drvPrice.toStringAsFixed(0) : '';
      _driverNote = r['driverNote']?.toString() ?? '';
      _driverLicenseNumber = r['driverLicenseNumber']?.toString() ?? '';

      // Location
      _pickupAddress = r['pickupAddress']?.toString() ?? '';
      _pickupLat = (r['pickupLat'] as num?)?.toDouble();
      _pickupLng = (r['pickupLng'] as num?)?.toDouble();

      component.appState.pickupAddress = _pickupAddress;
      component.appState.pickupLat = _pickupLat;
      component.appState.pickupLng = _pickupLng;

      // Legal
      _contractType = r['contractType']?.toString() ?? 'Tranyx Standard';
      _customTerms = r['contractTerms']?.toString() ?? '';

      // Images
      final interior = r['interiorPhotoUrl']?.toString() ?? r['interiorPhoto']?.toString() ?? '';
      final front = r['frontPhotoUrl']?.toString() ?? r['frontPhoto']?.toString() ?? r['photoUrl']?.toString() ?? '';
      final back = r['backPhotoUrl']?.toString() ?? r['backPhoto']?.toString() ?? '';

      _imageUrls[0] = interior;
      _imageUrls[1] = front;
      _imageUrls[2] = back;

      final extra = r['extraPhotos'];
      if (extra is List) {
        for (final ep in extra) {
          final s = ep?.toString() ?? '';
          if (s.isNotEmpty && s != 'null') {
            _imageUrls.add(s);
            _isUploadingImage.add(false);
          }
        }
      }
    }
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
      setState(() => _error = 'Please upload all required photos (Interior, Front, and Back) before saving.');
      return;
    }

    if (_isUploadingImage.any((uploading) => uploading)) {
      setState(() => _error = 'Please wait for all image uploads to finish.');
      return;
    }

    if (_rentalId == null || _rentalId!.isEmpty) {
      setState(() => _error = 'Invalid vehicle listing ID.');
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

      final updatedRental = VehicleRental(
        id: _rentalId!,
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
        vehicleValue: double.tryParse(_vehicleValue) ?? 0,
        ltoCrNumber: _ltoCrNumber.trim().isNotEmpty ? _ltoCrNumber.trim() : 'PENDING',
        ltoOrNumber: _ltoOrNumber.trim().isNotEmpty ? _ltoOrNumber.trim() : 'PENDING',
        insuranceProvider: _insuranceProvider.trim().isNotEmpty ? _insuranceProvider.trim() : 'N/A',
        insurancePolicyNumber: _insurancePolicyNumber.trim().isNotEmpty ? _insurancePolicyNumber.trim() : 'N/A',
        contractType: _contractType,
        contractTerms: _contractType == 'Custom Contract' ? _customTerms : 'Standard P2P terms',
        offersDriver: _offersDriver,
        driverDailyPrice: double.tryParse(_driverDailyPrice) ?? 0.0,
        driverNote: _driverNote,
        driverLicenseNumber: _driverLicenseNumber,
      );

      final extraPhotosList = _imageUrls.length > 3
          ? _imageUrls.sublist(3).where((url) => url.isNotEmpty).toList()
          : <String>[];

      // Save changes without charging fee (strictly checks that 0 reservation/booking records exist)
      await component.appState.firestore.updateVehicleRental(
        _rentalId!,
        updatedRental,
        gpsTrackerId: _gpsTrackerId.trim(),
        extraPhotos: extraPhotosList,
      );

      // Close modal and clear selected state
      component.appState.setState(() {
        component.appState.showEditVehicleModal = false;
        component.appState.selectedRentalData = null;
      });

      component.appState.alertDialog(
        'Listing Updated',
        'Your vehicle listing "${updatedRental.brand} ${updatedRental.model}" has been successfully updated and is live.',
      );
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
      final daily = double.tryParse(_priceDaily) ?? 0;
      if (daily <= 0) {
        setState(() => _error = 'Please provide a valid daily rate.');
        return;
      }
      if (_offersDriver) {
        final drvPrice = double.tryParse(_driverDailyPrice) ?? 0;
        if (drvPrice <= 0) {
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
    if (!component.appState.showEditVehicleModal) return div([]);
    final isDark = component.appState.isDark;

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in',
      [
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
                  h2(classes: 'text-2xl font-bold', [Component.text('Edit Vehicle Listing')]),
                  p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                    Component.text('Step $_step of 3 • Free Edit (No fees)'),
                  ]),
                ]),
                button(
                  classes: 'p-2 rounded-full hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors cursor-pointer border-0 bg-transparent',
                  events: {
                    'click': (e) => component.appState.setState(() => component.appState.showEditVehicleModal = false),
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
                    ]),
                    _inputField(
                      'GPS Device Serial / Tracker ID',
                      _gpsTrackerId,
                      (v) => setState(() => _gpsTrackerId = v.trim()),
                      isDark,
                      placeholder: 'e.g. TFL-2024-XXXXX',
                    ),
                  ],
                ),

                // LTO Registration & Insurance Compliance
                div(
                  classes:
                      'mt-4 p-5 rounded-2xl border ${isDark ? "bg-zinc-900/60 border-zinc-800" : "bg-purple-50/50 border-purple-100"} space-y-4',
                  [
                    div(classes: 'flex items-center gap-2 mb-1', [
                      lIcon('shield-check', cls: 'w-4 h-4 text-purple-400'),
                      h4(classes: 'text-sm font-bold ${isDark ? "text-purple-300" : "text-purple-800"}', [
                        Component.text('LTO Registration & Insurance Compliance'),
                      ]),
                    ]),
                    div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4', [
                      _inputField(
                        'LTO Certificate of Registration (CR)',
                        _ltoCrNumber,
                        (v) => setState(() => _ltoCrNumber = v.toUpperCase()),
                        isDark,
                        placeholder: 'e.g. CR-12345678',
                      ),
                      _inputField(
                        'LTO Official Receipt (OR)',
                        _ltoOrNumber,
                        (v) => setState(() => _ltoOrNumber = v.toUpperCase()),
                        isDark,
                        placeholder: 'e.g. OR-87654321',
                      ),
                      _inputField(
                        'Insured Vehicle Value (₱)',
                        _vehicleValue,
                        (v) => setState(() => _vehicleValue = v),
                        isDark,
                        placeholder: 'e.g. 1500000',
                        type: InputType.number,
                      ),
                      div([
                        label(
                          classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}',
                          [Component.text('Comprehensive Insurance Provider')],
                        ),
                        select(
                          classes:
                              'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors text-sm',
                          events: {'change': (e) => setState(() => _insuranceProvider = getInputValue(e.target))},
                          [
                            option(value: 'N/A', selected: _insuranceProvider == 'N/A', [
                              Component.text('N/A (Compulsory Third Party / CTPL Only)'),
                            ]),
                            option(value: 'Standard Insurance', selected: _insuranceProvider == 'Standard Insurance', [
                              Component.text('Standard Insurance'),
                            ]),
                            option(value: 'Malayan Insurance', selected: _insuranceProvider == 'Malayan Insurance', [
                              Component.text('Malayan Insurance'),
                            ]),
                            option(value: 'FPG Insurance', selected: _insuranceProvider == 'FPG Insurance', [
                              Component.text('FPG Insurance'),
                            ]),
                            option(value: 'Pioneer Insurance', selected: _insuranceProvider == 'Pioneer Insurance', [
                              Component.text('Pioneer Insurance'),
                            ]),
                            option(value: 'Mercantile Insurance', selected: _insuranceProvider == 'Mercantile Insurance', [
                              Component.text('Mercantile Insurance'),
                            ]),
                            option(value: 'Alpha Insurance', selected: _insuranceProvider == 'Alpha Insurance', [
                              Component.text('Alpha Insurance'),
                            ]),
                            option(value: 'Charter Ping An', selected: _insuranceProvider == 'Charter Ping An', [
                              Component.text('Charter Ping An'),
                            ]),
                            option(value: 'Other Provider', selected: _insuranceProvider == 'Other Provider', [
                              Component.text('Other Provider'),
                            ]),
                          ],
                        ),
                      ]),
                      div(classes: 'col-span-1 md:col-span-2', [
                        _inputField(
                          'Insurance Policy Reference No.',
                          _insurancePolicyNumber,
                          (v) => setState(() => _insurancePolicyNumber = v.toUpperCase()),
                          isDark,
                          placeholder: 'e.g. POL-2026-98765',
                        ),
                      ]),
                    ]),
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

                // Driver services option
                div(classes: 'mt-6 border-t ${isDark ? "border-zinc-800" : "border-zinc-200"} pt-6', [
                  div(classes: 'flex items-center justify-between mb-4', [
                    label(classes: 'block text-sm font-semibold ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                      Component.text('Offer Driver Services (Chauffeur-Driven)'),
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
                          'placeholder': 'e.g. Professional driver with clean record.',
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
                  MapPickerComponent(state: component.appState),
                ]),
              ] else if (_step == 3) ...[
                // Step 3: Photos & Legal
                h3(classes: 'text-lg font-bold mb-4', [Component.text('Photos & Legal Terms')]),
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

                if (_contractType == 'Standard' || _contractType == 'Tranyx Standard') ...[
                  div(
                    classes: 'p-4 rounded-xl border border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-900/50',
                    [
                      div(classes: 'flex items-center justify-between mb-2', [
                        div(classes: 'flex items-center gap-2', [
                          lIcon('file-text', cls: 'w-5 h-5 text-purple-600 dark:text-purple-400'),
                          span(classes: 'font-bold text-sm', [Component.text('Standard Vehicle Rental Agreement')]),
                        ]),
                        button(
                          classes:
                              'text-xs text-purple-600 dark:text-purple-400 font-bold hover:underline bg-transparent border-0 cursor-pointer',
                          events: {'click': (_) => setState(() => _showPreview = !_showPreview)},
                          [Component.text(_showPreview ? 'Hide Terms' : 'View Full Terms')],
                        ),
                      ]),
                      if (_showPreview)
                        ContractViewerComponent(
                          contractType: _contractType,
                          customTerms: _customTerms,
                          vehicleRental: VehicleRental(
                            id: _rentalId ?? '',
                            hostId: '',
                            hostName: component.appState.userProfile?.name ?? 'Owner',
                            brand: _brand,
                            model: _model,
                            year: int.tryParse(_year) ?? 2022,
                            plateNumber: _plateNumber,
                            type: _selectedType,
                            vehicleValue: double.tryParse(_vehicleValue) ?? 0,
                            ltoCrNumber: _ltoCrNumber.trim().isNotEmpty ? _ltoCrNumber.trim() : 'PENDING',
                            ltoOrNumber: _ltoOrNumber.trim().isNotEmpty ? _ltoOrNumber.trim() : 'PENDING',
                            insuranceProvider: _insuranceProvider.trim().isNotEmpty ? _insuranceProvider.trim() : 'N/A',
                            insurancePolicyNumber: _insurancePolicyNumber.trim().isNotEmpty ? _insurancePolicyNumber.trim() : 'N/A',
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
                  div(classes: 'mb-4', [
                    label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                      Component.text('Custom Contract Terms (Required)'),
                    ]),
                    textarea(
                      classes:
                          'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
                      rows: 5,
                      attributes: {'placeholder': 'Enter specific rules, conditions, fuel policies, etc.'},
                      events: {'input': (e) => setState(() => _customTerms = getInputValue(e.target))},
                      [Component.text(_customTerms)],
                    ),
                  ]),
                ],
              ],
            ]),

            // Footer
            div(
              classes:
                  'p-6 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center justify-between',
              [
                if (_step > 1)
                  button(
                    classes:
                        'px-6 py-2 rounded-xl font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800 text-zinc-300" : "border-zinc-300 hover:bg-zinc-50 text-zinc-700"} transition-colors cursor-pointer bg-transparent',
                    events: {'click': (e) => setState(() => _step--)},
                    [Component.text('Back')],
                  )
                else
                  div([]),

                if (_step < 3)
                  button(
                    classes:
                        'px-8 py-2 rounded-xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity border-0 outline-none cursor-pointer',
                    events: {'click': (e) => _handleNext()},
                    [Component.text('Continue')],
                  )
                else
                  button(
                    classes:
                        'px-8 py-2 rounded-xl font-bold text-white bg-indigo-600 hover:bg-indigo-700 transition-colors flex items-center gap-2 border-0 outline-none cursor-pointer shadow-lg shadow-indigo-500/20',
                    events: {'click': (e) => _submit()},
                    disabled: _isSubmitting,
                    [
                      if (_isSubmitting) lIcon('loader', cls: 'w-4 h-4 animate-spin'),
                      Component.text(_isSubmitting ? 'Saving Changes...' : 'Save Changes'),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Component _inputField(
    String labelText,
    String val,
    Function(String) onChanged,
    bool isDark, {
    String placeholder = '',
    InputType type = InputType.text,
  }) {
    return div(classes: 'mb-4', [
      label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
        Component.text(labelText),
      ]),
      input(
        type: type,
        classes:
            'w-full p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
        attributes: {'value': val, 'placeholder': placeholder},
        events: {'input': (e) => onChanged(getInputValue(e.target))},
      ),
    ]);
  }

  Component _selectField(
    String labelText,
    String val,
    List<String> optionsList,
    bool disabled,
    Function(String) onChanged,
    bool isDark, {
    String placeholder = '',
  }) {
    return div(classes: 'mb-4', [
      label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
        Component.text(labelText),
      ]),
      select(
        classes:
            'w-full p-3 rounded-xl border ${disabled ? "opacity-50 cursor-not-allowed " : ""}${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
        attributes: disabled ? {'disabled': 'true'} : {},
        events: {'change': (e) => onChanged(getInputValue(e.target))},
        [
          option(value: '', selected: val.isEmpty, [Component.text(placeholder)]),
          for (final opt in optionsList) option(value: opt, selected: val == opt, [Component.text(opt)]),
        ],
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
            'id': 'file-input-edit-veh-$index',
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
                  'for': 'file-input-edit-veh-$index',
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
                      if (index >= 3) {
                        _imageUrls.removeAt(index);
                        _isUploadingImage.removeAt(index);
                      } else {
                        _imageUrls[index] = '';
                      }
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
              'for': 'file-input-edit-veh-$index',
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

  bool _isValidPhilippinePlate(String plate) {
    final clean = plate.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    final carOld = RegExp(r'^[A-Z]{3}\d{3}$');
    final carNew = RegExp(r'^[A-Z]{3}\d{4}$');
    final mcOld = RegExp(r'^[A-Z]{2}\d{4}$');
    final mcNew = RegExp(r'^[A-Z]{2}\d{5}$');
    final mvFile = RegExp(r'^\d{4}-\d{7,}$');
    return carOld.hasMatch(clean) ||
        carNew.hasMatch(clean) ||
        mcOld.hasMatch(clean) ||
        mcNew.hasMatch(clean) ||
        mvFile.hasMatch(plate.trim());
  }

  String _formatPlateNumber(String val) {
    final cleaned = val.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (cleaned.length <= 3) return cleaned;
    if (cleaned.length <= 7) {
      return '${cleaned.substring(0, 3)}-${cleaned.substring(3)}';
    }
    return val.toUpperCase();
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
