import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'package:tranyx_mobile/features/profile/presentation/widgets/history_pane.dart' as hp;

class ListingWizardSheet extends ConsumerStatefulWidget {
  final bool isProperty;

  const ListingWizardSheet({super.key, required this.isProperty});

  @override
  ConsumerState<ListingWizardSheet> createState() => _ListingWizardSheetState();
}

class _ListingWizardSheetState extends ConsumerState<ListingWizardSheet> {
  int _step = 1;
  bool _isProcessing = false;
  String? _error;

  // STEP 1 FIELDS (Specs)
  // Vehicle
  VehicleType _selectedVehicleType = VehicleType.car;
  String _fuelType = 'Gasoline';
  String _transmission = 'Automatic';
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _plateController = TextEditingController();
  final _gpsTrackerController = TextEditingController();

  // Property
  PropertyCategory _selectedPropertyCategory = PropertyCategory.residential;
  PropertyType _selectedPropertyType = PropertyType.house;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<String> _selectedAmenities = [];
  final List<String> _amenitiesList = [
    'WiFi',
    'Aircon',
    'Parking',
    'Furnished',
    'Gym',
    'Swimming Pool',
  ];

  // STEP 2 FIELDS (Pricing & Location)
  final _priceDailyController = TextEditingController();
  final _price12hController = TextEditingController();
  final _priceWeeklyController = TextEditingController();
  final _priceMonthlyController = TextEditingController();
  final _extensionPenaltyController = TextEditingController();
  final _addressController = TextEditingController();

  // Vehicle Driver services
  bool _offersDriver = false;
  final _driverDailyPriceController = TextEditingController();
  final _driverNoteController = TextEditingController();
  final _driverLicenseController = TextEditingController();

  // Property Escrows
  final _securityDepositController = TextEditingController();
  final _advancePaymentController = TextEditingController();

  // STEP 3 FIELDS (Photos & Contract)
  final _photoUrl1Controller = TextEditingController(); // Interior
  final _photoUrl2Controller = TextEditingController(); // Front / Exterior
  final _photoUrl3Controller = TextEditingController(); // Back (vehicle only)

  String _contractType = 'Tranyx Standard';
  final _customTermsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.isProperty) {
      _photoUrl1Controller.text =
          'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?auto=format&fit=crop&w=600&q=80';
      _photoUrl2Controller.text =
          'https://images.unsplash.com/photo-1564013799919-ab600027ffc6?auto=format&fit=crop&w=600&q=80';
    } else {
      _photoUrl1Controller.text =
          'https://images.unsplash.com/photo-1542282088-fe8426682b8f?auto=format&fit=crop&w=600&q=80';
      _photoUrl2Controller.text =
          'https://images.unsplash.com/photo-1503376780353-7e6692767b70?auto=format&fit=crop&w=600&q=80';
      _photoUrl3Controller.text =
          'https://images.unsplash.com/photo-1549399542-7e3f8b79c341?auto=format&fit=crop&w=600&q=80';
    }
    _addressController.text = '1280 Silicon Ave, BGC, Metro Manila';
  }

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _plateController.dispose();
    _gpsTrackerController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _priceDailyController.dispose();
    _price12hController.dispose();
    _priceWeeklyController.dispose();
    _priceMonthlyController.dispose();
    _extensionPenaltyController.dispose();
    _addressController.dispose();
    _driverDailyPriceController.dispose();
    _driverNoteController.dispose();
    _driverLicenseController.dispose();
    _securityDepositController.dispose();
    _advancePaymentController.dispose();
    _photoUrl1Controller.dispose();
    _photoUrl2Controller.dispose();
    _photoUrl3Controller.dispose();
    _customTermsController.dispose();
    super.dispose();
  }

  double get _listingFee {
    if (widget.isProperty) {
      final monthly = double.tryParse(_priceMonthlyController.text) ?? 0.0;
      return monthly * 0.015;
    } else {
      final daily = double.tryParse(_priceDailyController.text) ?? 0.0;
      return daily * 0.015;
    }
  }

  void _scrollToTop(ScrollController scrollController) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Validates a Philippine LTO plate number (standard or MV File format).
  bool _isValidPhilippinePlate(String plate) {
    final cleaned = plate.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (cleaned.isEmpty) return false;
    // Standard LTO format: 1–5 letters + 1–5 digits (e.g. ABC-1234)
    if (RegExp(r'^[A-Z]{1,5}\d{1,5}$').hasMatch(cleaned)) return true;
    // MV File Number: 9–12 consecutive digits
    if (RegExp(r'^\d{9,12}$').hasMatch(cleaned)) return true;
    return false;
  }

  /// Auto-formats a plate number string as the user types.
  String _formatPlateNumber(String val) {
    final cleaned = val.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\s-]'), '');
    final digitsOnly = cleaned.replaceAll(RegExp(r'\D'), '');
    final lettersDigitsOnly = cleaned.replaceAll(RegExp(r'[\s-]'), '');

    if (lettersDigitsOnly.isEmpty) return '';

    // MV File Number style (starts with digit)
    if (RegExp(r'^\d').hasMatch(lettersDigitsOnly)) {
      if (digitsOnly.length > 4) {
        return '${digitsOnly.substring(0, 4)}-${digitsOnly.substring(4, digitsOnly.length > 11 ? 11 : digitsOnly.length)}';
      }
      return digitsOnly;
    }

    // Standard plate format (starts with letters)
    final letterMatch = RegExp(r'^[A-Z]+').firstMatch(lettersDigitsOnly);
    if (letterMatch != null) {
      final letters = letterMatch.group(0)!;
      final truncLetters = letters.substring(0, letters.length > 5 ? 5 : letters.length);
      final digits = lettersDigitsOnly.substring(letters.length);
      final truncDigits = digits.substring(0, digits.length > 5 ? 5 : digits.length);
      return truncDigits.isNotEmpty ? '$truncLetters-$truncDigits' : truncLetters;
    }
    return cleaned;
  }

  bool _validateStep1(ScrollController scrollController) {
    setState(() => _error = null);
    if (widget.isProperty) {
      final title = _titleController.text.trim();
      final desc = _descriptionController.text.trim();
      if (title.isEmpty) {
        setState(() => _error = 'Please enter a property title');
        _scrollToTop(scrollController);
        return false;
      }
      if (desc.isEmpty) {
        setState(() => _error = 'Please enter a property description');
        _scrollToTop(scrollController);
        return false;
      }
      if (checkProfanity(title) || checkProfanity(desc)) {
        setState(() => _error = 'Your title or description contains inappropriate language. Please review and try again.');
        _scrollToTop(scrollController);
        return false;
      }
    } else {
      final brand = _brandController.text.trim();
      final model = _modelController.text.trim();
      if (brand.isEmpty) {
        setState(() => _error = 'Please enter vehicle brand');
        _scrollToTop(scrollController);
        return false;
      }
      if (model.isEmpty) {
        setState(() => _error = 'Please enter vehicle model');
        _scrollToTop(scrollController);
        return false;
      }
      if (checkProfanity(brand) || checkProfanity(model)) {
        setState(() => _error = 'Your vehicle brand or model contains inappropriate language. Please review and try again.');
        _scrollToTop(scrollController);
        return false;
      }
      if (_yearController.text.trim().isEmpty) {
        setState(() => _error = 'Please select a vehicle year');
        _scrollToTop(scrollController);
        return false;
      }
      if (!_isValidPhilippinePlate(_plateController.text)) {
        setState(() => _error = 'Please enter a valid Philippine Plate Number (e.g. ABC-1234, MC-12345) or MV File Number.');
        _scrollToTop(scrollController);
        return false;
      }
    }
    return true;
  }

  bool _validateStep2(ScrollController scrollController) {
    setState(() => _error = null);
    if (widget.isProperty) {
      final monthly =
          double.tryParse(_priceMonthlyController.text.trim()) ?? 0.0;
      if (monthly <= 0) {
        setState(() => _error = 'Please enter a valid monthly rent amount');
        _scrollToTop(scrollController);
        return false;
      }
    } else {
      final daily = double.tryParse(_priceDailyController.text.trim()) ?? 0.0;
      if (daily <= 0) {
        setState(() => _error = 'Please enter a valid daily rate');
        _scrollToTop(scrollController);
        return false;
      }
      if (_offersDriver) {
        final driverDaily =
            double.tryParse(_driverDailyPriceController.text.trim()) ?? 0.0;
        if (driverDaily <= 0) {
          setState(() => _error = 'Please enter a driver daily rate');
          _scrollToTop(scrollController);
          return false;
        }
        if (_driverLicenseController.text.trim().isEmpty) {
          setState(() => _error = 'Please enter driver\'s license number');
          _scrollToTop(scrollController);
          return false;
        }
      }
    }

    if (_addressController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter an address location');
      _scrollToTop(scrollController);
      return false;
    }
    return true;
  }

  void _submitListing(ScrollController scrollController) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    final userProfile = ref.read(userProfileProvider).value;
    if (userProfile == null) {
      setState(() {
        _isProcessing = false;
        _error = 'User profile not loaded';
      });
      _scrollToTop(scrollController);
      return;
    }

    if (_contractType == 'Custom Contract' && checkProfanity(_customTermsController.text.trim())) {
      setState(() {
        _isProcessing = false;
        _error = 'Your custom terms contain inappropriate language. Please review and try again.';
      });
      _scrollToTop(scrollController);
      return;
    }

    final fee = _listingFee;

    if (userProfile.tyxBalance < fee) {
      setState(() {
        _isProcessing = false;
        _error =
            'Insufficient balance for listing fee. Required: ${fee.toStringAsFixed(2)} TYXBIT, Available: ${userProfile.tyxBalance.toStringAsFixed(2)} TYXBIT';
      });
      _scrollToTop(scrollController);
      return;
    }

    try {
      final repo = ref.read(transitRepositoryProvider);

      if (widget.isProperty) {
        final monthly =
            double.tryParse(_priceMonthlyController.text.trim()) ?? 0.0;
        final weekly =
            double.tryParse(_priceWeeklyController.text.trim()) ?? 0.0;
        final daily = double.tryParse(_priceDailyController.text.trim()) ?? 0.0;
        final depositAmt =
            double.tryParse(_securityDepositController.text.trim()) ?? 0.0;
        final advanceAmt =
            double.tryParse(_advancePaymentController.text.trim()) ?? 0.0;
        final depositMonths = monthly > 0 ? (depositAmt / monthly).round() : 0;

        final property = PropertyRental(
          id: '',
          hostId: userProfile.uid,
          hostName: userProfile.name,
          hostPhotoUrl: userProfile.photoUrl ?? '',
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          type: _selectedPropertyType,
          category: _selectedPropertyCategory,
          priceMonthly: monthly,
          priceWeekly: weekly,
          priceDaily: daily,
          depositMonths: depositMonths,
          securityDepositAmount: depositAmt,
          advanceAmount: advanceAmt,
          address: _addressController.text.trim(),
          latitude:
              14.5995 +
              (DateTime.now().millisecond % 100) *
                  0.0001, // Mock local coordinate
          longitude: 120.9842 + (DateTime.now().microsecond % 100) * 0.0001,
          photoUrls: [
            _photoUrl1Controller.text.trim(),
            _photoUrl2Controller.text.trim(),
          ].where((url) => url.isNotEmpty).toList(),
          amenities: _selectedAmenities,
          status: 'Available',
          contractType: _contractType,
          contractTerms: _contractType == 'Custom Contract'
              ? _customTermsController.text.trim()
              : 'Standard Peer-to-Peer Property Lease Terms. Payment is held securely in Tranyx Smart Escrow.',
          createdAt: DateTime.now(),
        );

        await repo.createPropertyRental(property);
      } else {
        final daily = double.tryParse(_priceDailyController.text.trim()) ?? 0.0;
        final hourly12 =
            double.tryParse(_price12hController.text.trim()) ?? 0.0;
        final weekly =
            double.tryParse(_priceWeeklyController.text.trim()) ?? 0.0;
        final monthly =
            double.tryParse(_priceMonthlyController.text.trim()) ?? 0.0;
        final extPenalty =
            double.tryParse(_extensionPenaltyController.text.trim()) ??
            (daily / 24 * 1.5);

        final rental = VehicleRental(
          id: '',
          hostId: userProfile.uid,
          hostName: userProfile.name,
          type: _selectedVehicleType,
          brand: _brandController.text.trim(),
          model: _modelController.text.trim(),
          year:
              int.tryParse(_yearController.text.trim()) ?? DateTime.now().year,
          plateNumber: _plateController.text.trim(),
          fuelType: _fuelType,
          transmission: _transmission,
          interiorPhotoUrl: _photoUrl1Controller.text.trim(),
          frontPhotoUrl: _photoUrl2Controller.text.trim(),
          backPhotoUrl: _photoUrl3Controller.text.trim(),
          price12h: hourly12,
          priceDaily: daily,
          priceWeekly: weekly,
          priceMonthly: monthly,
          extensionRatePerHour: extPenalty,
          latePenaltyRatePerHour: extPenalty,
          pickupAddress: _addressController.text.trim(),
          pickupLat: 14.5995 + (DateTime.now().millisecond % 100) * 0.0001,
          pickupLng: 120.9842 + (DateTime.now().microsecond % 100) * 0.0001,
          status: 'Available',
          createdAt: DateTime.now(),
          vehicleValue: 0,
          ltoCrNumber: 'PENDING',
          ltoOrNumber: 'PENDING',
          insuranceProvider: 'N/A',
          insurancePolicyNumber: 'N/A',
          contractType: _contractType,
          contractTerms: _contractType == 'Custom Contract'
              ? _customTermsController.text.trim()
              : 'Standard Peer-to-Peer Vehicle Rental Terms. Payment is held securely in Tranyx Smart Escrow.',
          offersDriver: _offersDriver,
          driverDailyPrice:
              double.tryParse(_driverDailyPriceController.text.trim()) ?? 0.0,
          driverNote: _driverNoteController.text.trim(),
          driverLicenseNumber: _driverLicenseController.text.trim(),
        );

        final mapData = rental.toMap();
        if (_gpsTrackerController.text.trim().isNotEmpty) {
          mapData['gpsTrackerId'] = _gpsTrackerController.text.trim();
        }
        await repo.createRentalFromMap(mapData);
      }

      ref.invalidate(userProfileProvider);
      ref.invalidate(realtimeRentalsProvider);
      ref.invalidate(realtimePropertiesProvider);
      ref.invalidate(userTransactionsProvider);
      ref.invalidate(hp.userTransactionsProvider(userProfile.uid));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.isProperty ? "Property" : "Vehicle"} listed successfully! Posting fee deducted.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Error listing: $e';
      });
      _scrollToTop(scrollController);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final userProfile = ref.watch(userProfileProvider).value;

    if (userProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return PopScope(
      canPop: _step == 1 && !_isProcessing,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isProcessing) return;
        if (_step > 1) {
          setState(() {
            _step--;
          });
        }
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              // Pull bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.isProperty
                                ? 'List a Property'
                                : 'List a Vehicle',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Step $_step of 3',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _step == 1 ? Icons.close : Icons.arrow_back_ios_new_rounded,
                      ),
                      onPressed: () {
                        if (_step == 1) {
                          Navigator.pop(context);
                        } else {
                          setState(() => _step--);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (_step == 1) ...[
                      // STEP 1: Specs / Specifications
                      if (widget.isProperty) ...[
                        const Text(
                          'PROPERTY CATEGORY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<PropertyCategory>(
                          initialValue: _selectedPropertyCategory,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedPropertyCategory = val;
                                // Reset type to first compatible
                                _selectedPropertyType = PropertyType.values
                                    .firstWhere((t) => t.category == val);
                              });
                            }
                          },
                          items: PropertyCategory.values.map((c) {
                            return DropdownMenuItem(
                              value: c,
                              child: Text(c.label),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          'PROPERTY TYPE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<PropertyType>(
                          initialValue: _selectedPropertyType,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedPropertyType = val;
                              });
                            }
                          },
                          items: PropertyType.values
                              .where(
                                (t) => t.category == _selectedPropertyCategory,
                              )
                              .map((t) {
                                return DropdownMenuItem(
                                  value: t,
                                  child: Text(t.label),
                                );
                              })
                              .toList(),
                        ),
                        const SizedBox(height: 16),

                        UIHelpers.buildTextField(
                          Icons.title,
                          "Listing Title (e.g. Cozy Condo in BGC)",
                          isDarkMode,
                          controller: _titleController,
                        ),
                        const SizedBox(height: 16),

                        UIHelpers.buildTextField(
                          Icons.description,
                          "Description / Specs / Rules...",
                          isDarkMode,
                          controller: _descriptionController,
                          maxLines: 4,
                        ),
                        const SizedBox(height: 20),

                        const Text(
                          'AMENITIES',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _amenitiesList.map((amenity) {
                            final active = _selectedAmenities.contains(amenity);
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (active) {
                                    _selectedAmenities.remove(amenity);
                                  } else {
                                    _selectedAmenities.add(amenity);
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: active
                                      ? AppColors.indigo.withValues(alpha: 0.2)
                                      : (isDarkMode
                                            ? AppColors.darkCard
                                            : Colors.white),
                                  border: Border.all(
                                    color: active
                                        ? AppColors.indigo
                                        : (isDarkMode
                                              ? AppColors.darkBorder
                                              : AppColors.lightBorder),
                                    width: active ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  amenity,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: active
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: active
                                        ? AppColors.indigo
                                        : (isDarkMode
                                              ? Colors.white
                                              : Colors.black),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ] else ...[
                        const Text(
                          'VEHICLE TYPE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<VehicleType>(
                          initialValue: _selectedVehicleType,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedVehicleType = val;
                                _brandController.text = '';
                                _modelController.text = '';
                                _yearController.text = '';
                              });
                            }
                          },
                          items: VehicleType.values.map((t) {
                            return DropdownMenuItem(
                              value: t,
                              child: Text(t.name.toUpperCase()),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          'FUEL TYPE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _fuelType,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _fuelType = val);
                            }
                          },
                          items: ['Gasoline', 'Diesel', 'Electric', 'Hybrid']
                              .map((f) {
                                return DropdownMenuItem(
                                  value: f,
                                  child: Text(f),
                                );
                              })
                              .toList(),
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          'TRANSMISSION',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _transmission,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _transmission = val);
                            }
                          },
                          items: ['Automatic', 'Manual'].map((t) {
                            return DropdownMenuItem(value: t, child: Text(t));
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        // ── Brand Dropdown ──────────────────────────────
                        const Text(
                          'BRAND',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _brandController.text.isEmpty ? null : _brandController.text,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                            hintText: 'Select Brand',
                          ),
                          items: (VehicleSpecDatabase.modelsByTypeAndBrand[_selectedVehicleType]?.keys.toList() ?? [])
                              .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _brandController.text = val;
                                _modelController.text = '';
                                _yearController.text = '';
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 16),

                        // ── Model Dropdown ──────────────────────────────
                        const Text(
                          'MODEL',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _modelController.text.isEmpty ? null : _modelController.text,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                            hintText: _brandController.text.isEmpty ? 'Select Brand first' : 'Select Model',
                          ),
                          items: _brandController.text.isEmpty
                              ? []
                              : (VehicleSpecDatabase.modelsByTypeAndBrand[_selectedVehicleType]?[_brandController.text] ?? [])
                                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                                  .toList(),
                          onChanged: _brandController.text.isEmpty
                              ? null
                              : (val) {
                                  if (val != null) {
                                    setState(() {
                                      _modelController.text = val;
                                      _yearController.text = '';
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 16),

                        // ── Year Dropdown ───────────────────────────────
                        const Text(
                          'YEAR',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _yearController.text.isEmpty ? null : _yearController.text,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                            hintText: _modelController.text.isEmpty ? 'Select Model first' : 'Select Year',
                          ),
                          items: _modelController.text.isEmpty
                              ? []
                              : VehicleSpecDatabase.getYearsForModel(_modelController.text)
                                  .map((y) => DropdownMenuItem(value: y.toString(), child: Text(y.toString())))
                                  .toList(),
                          onChanged: _modelController.text.isEmpty
                              ? null
                              : (val) {
                                  if (val != null) setState(() => _yearController.text = val);
                                },
                        ),
                        const SizedBox(height: 16),

                        // ── Plate Number (with auto-format) ─────────────
                        UIHelpers.buildTextField(
                          Icons.credit_card,
                          'Plate Number (e.g. ABC-1234)',
                          isDarkMode,
                          controller: _plateController,
                          onChanged: (v) {
                            final formatted = _formatPlateNumber(v);
                            if (_plateController.text != formatted) {
                              _plateController.value = _plateController.value.copyWith(
                                text: formatted,
                                selection: TextSelection.collapsed(offset: formatted.length),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        UIHelpers.buildTextField(
                          Icons.gps_fixed,
                          'GPS Hardware Tracker ID (Optional)',
                          isDarkMode,
                          controller: _gpsTrackerController,
                        ),

                      ],
                    ] else if (_step == 2) ...[
                      // STEP 2: Pricing & Location
                      if (widget.isProperty) ...[
                        UIHelpers.buildTextField(
                          Icons.monetization_on,
                          "Monthly Rent Rate (₱, Required)",
                          isDarkMode,
                          controller: _priceMonthlyController,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        UIHelpers.buildTextField(
                          Icons.security,
                          "Security Deposit Amount (₱)",
                          isDarkMode,
                          controller: _securityDepositController,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              'Quick Deposit:',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 8),
                            for (int m in [1, 2, 3]) ...[
                              GestureDetector(
                                onTap: () {
                                  final monthly =
                                      double.tryParse(
                                        _priceMonthlyController.text,
                                      ) ??
                                      0.0;
                                  _securityDepositController.text =
                                      (monthly * m).toInt().toString();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? AppColors.darkCard
                                        : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$m Month${m > 1 ? "s" : ""}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        UIHelpers.buildTextField(
                          Icons.payment,
                          "Advance Payment Amount (₱)",
                          isDarkMode,
                          controller: _advancePaymentController,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              'Quick Advance:',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 8),
                            for (int m in [1, 2]) ...[
                              GestureDetector(
                                onTap: () {
                                  final monthly =
                                      double.tryParse(
                                        _priceMonthlyController.text,
                                      ) ??
                                      0.0;
                                  _advancePaymentController.text = (monthly * m)
                                      .toInt()
                                      .toString();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? AppColors.darkCard
                                        : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$m Month${m > 1 ? "s" : ""}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        UIHelpers.buildTextField(
                          Icons.monetization_on_outlined,
                          "Weekly Rate (Optional)",
                          isDarkMode,
                          controller: _priceWeeklyController,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        UIHelpers.buildTextField(
                          Icons.monetization_on_outlined,
                          "Daily Rate (Optional)",
                          isDarkMode,
                          controller: _priceDailyController,
                          keyboardType: TextInputType.number,
                        ),
                      ] else ...[
                        UIHelpers.buildTextField(
                          Icons.monetization_on,
                          "Daily Rental Rate (₱, Required)",
                          isDarkMode,
                          controller: _priceDailyController,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        UIHelpers.buildTextField(
                          Icons.monetization_on_outlined,
                          "12-Hour Rental Rate (Optional)",
                          isDarkMode,
                          controller: _price12hController,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        UIHelpers.buildTextField(
                          Icons.monetization_on_outlined,
                          "Weekly Rental Rate (Optional)",
                          isDarkMode,
                          controller: _priceWeeklyController,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        UIHelpers.buildTextField(
                          Icons.monetization_on_outlined,
                          "Monthly Rental Rate (Optional)",
                          isDarkMode,
                          controller: _priceMonthlyController,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        UIHelpers.buildTextField(
                          Icons.timer,
                          "Late Return Extension Penalty (Per Hour)",
                          isDarkMode,
                          controller: _extensionPenaltyController,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),

                        // Driver options
                        SwitchListTile(
                          title: const Text(
                            'Offer Personal Driver Services',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: const Text(
                            'Host provides driver / acts as driver',
                          ),
                          value: _offersDriver,
                          onChanged: (val) =>
                              setState(() => _offersDriver = val),
                        ),
                        const SizedBox(height: 8),

                        if (_offersDriver) ...[
                          UIHelpers.buildTextField(
                            Icons.monetization_on_outlined,
                            "Driver Daily Cost (₱)",
                            isDarkMode,
                            controller: _driverDailyPriceController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 16),
                          UIHelpers.buildTextField(
                            Icons.badge,
                            "Driver License Number",
                            isDarkMode,
                            controller: _driverLicenseController,
                          ),
                          const SizedBox(height: 16),
                          UIHelpers.buildTextField(
                            Icons.note,
                            "Driver Experience Note (e.g. 5 yrs clean record)",
                            isDarkMode,
                            controller: _driverNoteController,
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],

                      UIHelpers.buildTextField(
                        Icons.location_on,
                        widget.isProperty
                            ? "Property Physical Address"
                            : "Handover Pickup Location",
                        isDarkMode,
                        controller: _addressController,
                      ),
                    ] else ...[
                      // STEP 3: Photos & Legal
                      const Text(
                        'PHOTOS (IMAGE URLS)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      UIHelpers.buildTextField(
                        Icons.camera_alt,
                        "Interior Photo URL",
                        isDarkMode,
                        controller: _photoUrl1Controller,
                      ),
                      const SizedBox(height: 16),
                      UIHelpers.buildTextField(
                        Icons.camera,
                        "Front / Exterior Photo URL",
                        isDarkMode,
                        controller: _photoUrl2Controller,
                      ),
                      const SizedBox(height: 16),
                      if (!widget.isProperty) ...[
                        UIHelpers.buildTextField(
                          Icons.camera_alt_outlined,
                          "Back Photo URL",
                          isDarkMode,
                          controller: _photoUrl3Controller,
                        ),
                        const SizedBox(height: 16),
                      ],

                      const Text(
                        'CONTRACT TYPE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _contractType,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _contractType = val);
                          }
                        },
                        items: ['Tranyx Standard', 'Custom Contract'].map((c) {
                          return DropdownMenuItem(value: c, child: Text(c));
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      if (_contractType == 'Custom Contract') ...[
                        UIHelpers.buildTextField(
                          Icons.gavel,
                          "Custom Lease Agreement Terms...",
                          isDarkMode,
                          controller: _customTermsController,
                          maxLines: 4,
                        ),
                        const SizedBox(height: 16),
                      ],
                      Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.black26 : Colors.grey[50],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDarkMode
                                  ? AppColors.darkBorder
                                  : AppColors.lightBorder,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ESTIMATED EARNINGS & PAYOUTS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.indigo,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (widget.isProperty) ...[
                                _buildBreakdownRow(
                                  'Monthly Rent (Base)',
                                  double.tryParse(_priceMonthlyController.text) ?? 0.0,
                                ),
                                if ((double.tryParse(_priceWeeklyController.text) ?? 0.0) > 0)
                                  _buildBreakdownRow(
                                    'Weekly Rent',
                                    double.tryParse(_priceWeeklyController.text) ?? 0.0,
                                  ),
                                if ((double.tryParse(_priceDailyController.text) ?? 0.0) > 0)
                                  _buildBreakdownRow(
                                    'Daily Rent',
                                    double.tryParse(_priceDailyController.text) ?? 0.0,
                                  ),
                                if ((double.tryParse(_securityDepositController.text) ?? 0.0) > 0)
                                  _buildBreakdownRow(
                                    'Security Deposit (Refundable)',
                                    double.tryParse(_securityDepositController.text) ?? 0.0,
                                    isGreen: true,
                                  ),
                                if ((double.tryParse(_advancePaymentController.text) ?? 0.0) > 0)
                                  _buildBreakdownRow(
                                    'Advance Rent Payment',
                                    double.tryParse(_advancePaymentController.text) ?? 0.0,
                                    isGreen: true,
                                  ),
                                const Divider(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Host Commission (3%)',
                                      style: TextStyle(fontSize: 13, color: Colors.grey),
                                    ),
                                    Text(
                                      '- ₱ ${((double.tryParse(_priceMonthlyController.text) ?? 0.0) * 0.03).toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 13, color: Colors.amber),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Est. Monthly Net Payout',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      '₱ ${((double.tryParse(_priceMonthlyController.text) ?? 0.0) * 0.97).toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                if ((double.tryParse(_price12hController.text) ?? 0.0) > 0)
                                  _buildPayoutRow(
                                    '12-Hour Rental',
                                    double.tryParse(_price12hController.text) ?? 0.0,
                                  ),
                                _buildPayoutRow(
                                  'Daily Rental (Base)',
                                  double.tryParse(_priceDailyController.text) ?? 0.0,
                                ),
                                if ((double.tryParse(_priceWeeklyController.text) ?? 0.0) > 0)
                                  _buildPayoutRow(
                                    'Weekly Rental',
                                    double.tryParse(_priceWeeklyController.text) ?? 0.0,
                                  ),
                                if ((double.tryParse(_priceMonthlyController.text) ?? 0.0) > 0)
                                  _buildPayoutRow(
                                    'Monthly Rental',
                                    double.tryParse(_priceMonthlyController.text) ?? 0.0,
                                  ),
                              ],
                              const Divider(height: 24),
                              const Text(
                                'POSTING FEES',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.indigo,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    widget.isProperty
                                        ? 'Anti-Spam Listing Fee (1.5% of Monthly)'
                                        : 'Anti-Spam Listing Fee (1.5% of Daily)',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  Text(
                                    '₱ ${_listingFee.toStringAsFixed(2)} TYXBIT',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppColors.indigo,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Your Wallet Balance:',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  Text(
                                    '₱ ${userProfile.tyxBalance.toStringAsFixed(2)} TYXBIT',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: userProfile.tyxBalance >= _listingFee
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    const SizedBox(height: 16),
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      const SizedBox(height: 16),
                    ],

                    // Controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (_step > 1)
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => setState(() => _step--),
                          )
                        else
                          const SizedBox(width: 48),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: _isProcessing
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : UIHelpers.buildPrimaryButton(
                                  _step == 3 ? 'Publish Listing' : 'Next Step',
                                  () {
                                    if (_step == 1) {
                                      if (_validateStep1(scrollController)) {
                                        setState(() => _step = 2);
                                      }
                                    } else if (_step == 2) {
                                      if (_validateStep2(scrollController)) {
                                        setState(() => _step = 3);
                                      }
                                    } else {
                                      _submitListing(scrollController);
                                    }
                                  },
                                  isDarkMode,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ],
          ),
        ), // close Container
        ); // close Padding
      },
    ),
  );
}

  Widget _buildBreakdownRow(String label, double amount, {bool isGreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(
            '₱ ${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isGreen ? Colors.green : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutRow(String label, double amount) {
    final commission = amount * 0.03;
    final payout = amount - commission;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              Text(
                'Rate: ₱ ${amount.toStringAsFixed(2)} | Comm (3%): - ₱ ${commission.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          Text(
            '₱ ${payout.toStringAsFixed(2)} Net',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}
