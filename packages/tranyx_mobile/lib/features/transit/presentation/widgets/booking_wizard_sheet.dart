import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';

class BookingWizardSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  final bool isProperty;

  const BookingWizardSheet({
    super.key,
    required this.item,
    required this.isProperty,
  });

  @override
  ConsumerState<BookingWizardSheet> createState() => _BookingWizardSheetState();
}

class _BookingWizardSheetState extends ConsumerState<BookingWizardSheet> {
  final _licenseController = TextEditingController();
  final _deliveryAddressController = TextEditingController();

  String _selectedDurationType = 'daily';
  int _multiplier = 1;
  bool _hireWithDriver = false;
  String _rentalType = 'pickup'; // 'pickup' or 'delivery'

  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _selectedDurationType = widget.isProperty ? 'monthly' : 'daily';
  }

  @override
  void dispose() {
    _licenseController.dispose();
    _deliveryAddressController.dispose();
    super.dispose();
  }

  double _getRate(String durationType) {
    if (widget.isProperty) {
      if (durationType == 'daily')
        return (widget.item['priceDaily'] as num?)?.toDouble() ?? 0.0;
      if (durationType == 'weekly')
        return (widget.item['priceWeekly'] as num?)?.toDouble() ?? 0.0;
      if (durationType == 'monthly')
        return (widget.item['priceMonthly'] as num?)?.toDouble() ?? 0.0;
      if (durationType == 'yearly')
        return ((widget.item['priceMonthly'] as num?)?.toDouble() ?? 0.0) * 12;
    } else {
      if (durationType == '12h')
        return (widget.item['price12h'] as num?)?.toDouble() ?? 0.0;
      if (durationType == 'daily')
        return (widget.item['priceDaily'] as num?)?.toDouble() ?? 0.0;
      if (durationType == 'weekly')
        return (widget.item['priceWeekly'] as num?)?.toDouble() ?? 0.0;
      if (durationType == 'monthly')
        return (widget.item['priceMonthly'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final userProfile = ref.watch(userProfileProvider).value;

    if (userProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final id = widget.item['id'] as String;
    final brand = widget.item['brand'] as String? ?? '';
    final model = widget.item['model'] as String? ?? '';
    final title = widget.item['title'] as String? ?? '$brand $model';

    final baseRate = _getRate(_selectedDurationType);
    final double driverCost = _hireWithDriver
        ? ((widget.item['driverDailyPrice'] as num?)?.toDouble() ?? 0.0)
        : 0.0;

    // Total calculation:
    // If vehicle 12h, driver cost is halved or proportional; let's keep it simple: multiplier * baseRate + multiplier * driverCost
    final baseTotal = (_multiplier * baseRate) + (_multiplier * driverCost);
    final bookingFee = baseTotal * 0.03;
    final totalRequired = baseTotal + bookingFee;
    final balance = userProfile.tyxBalance;
    final hasEnoughBalance = balance >= totalRequired;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
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
                          const Text(
                            'Book Rental Listing',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
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
                    // Duration Type Choice
                    const Text(
                      'RENTAL OPTION',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedDurationType,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedDurationType = val;
                          });
                        }
                      },
                      items: widget.isProperty
                          ? [
                              if ((widget.item['priceDaily'] as num? ?? 0) > 0)
                                const DropdownMenuItem(
                                  value: 'daily',
                                  child: Text('Daily Rent'),
                                ),
                              if ((widget.item['priceWeekly'] as num? ?? 0) > 0)
                                const DropdownMenuItem(
                                  value: 'weekly',
                                  child: Text('Weekly Rent'),
                                ),
                              if ((widget.item['priceMonthly'] as num? ?? 0) >
                                  0)
                                const DropdownMenuItem(
                                  value: 'monthly',
                                  child: Text('Monthly Rent'),
                                ),
                              const DropdownMenuItem(
                                value: 'yearly',
                                child: Text('Yearly Rent'),
                              ),
                            ]
                          : [
                              if ((widget.item['price12h'] as num? ?? 0) > 0)
                                const DropdownMenuItem(
                                  value: '12h',
                                  child: Text('12 Hours'),
                                ),
                              const DropdownMenuItem(
                                value: 'daily',
                                child: Text('Daily'),
                              ),
                              const DropdownMenuItem(
                                value: 'weekly',
                                child: Text('Weekly'),
                              ),
                              const DropdownMenuItem(
                                value: 'monthly',
                                child: Text('Monthly'),
                              ),
                            ],
                    ),
                    const SizedBox(height: 16),

                    // Multiplier
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Duration Multiplier',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: _multiplier > 1
                                  ? () => setState(() => _multiplier--)
                                  : null,
                            ),
                            Text(
                              '$_multiplier',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => setState(() => _multiplier++),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Vehicle specific choices
                    if (!widget.isProperty) ...[
                      // Driver Option
                      if (widget.item['offersDriver'] == true) ...[
                        SwitchListTile(
                          title: const Text(
                            'Hire With Personal Driver',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            'Add ₱ ${((widget.item["driverDailyPrice"] as num?)?.toStringAsFixed(0) ?? "0")}/day',
                          ),
                          value: _hireWithDriver,
                          onChanged: (val) {
                            setState(() {
                              _hireWithDriver = val;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Handover Choice
                      const Text(
                        'HANDOVER TYPE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text(
                                'Self Pickup',
                                style: TextStyle(fontSize: 12),
                              ),
                              value: 'pickup',
                              groupValue: _rentalType,
                              onChanged: (val) =>
                                  setState(() => _rentalType = val!),
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text(
                                'Doorstep',
                                style: TextStyle(fontSize: 12),
                              ),
                              value: 'delivery',
                              groupValue: _rentalType,
                              onChanged: (val) =>
                                  setState(() => _rentalType = val!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (_rentalType == 'delivery') ...[
                        UIHelpers.buildTextField(
                          Icons.location_city,
                          "Enter Delivery Address...",
                          isDarkMode,
                          controller: _deliveryAddressController,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],

                    // Driver License Number (Required for booking request validation)
                    UIHelpers.buildTextField(
                      Icons.badge,
                      widget.isProperty
                          ? "Enter Government ID Number..."
                          : "Enter Driver's License Number...",
                      isDarkMode,
                      controller: _licenseController,
                    ),
                    const SizedBox(height: 24),

                    // Pricing breakdown
                    const Text(
                      'PRICE BREAKDOWN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '$_multiplier x Base Rate ($_selectedDurationType)',
                              ),
                              Text(
                                '₱ ${(_multiplier * baseRate).toStringAsFixed(2)}',
                              ),
                            ],
                          ),
                          if (_hireWithDriver) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Personal Driver service fee'),
                                Text(
                                  '₱ ${(_multiplier * driverCost).toStringAsFixed(2)}',
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Platform Escrow Fee (3%)'),
                              Text(
                                '+ ₱ ${bookingFee.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.green),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total Locked Funds Required',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '₱ ${totalRequired.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: AppColors.indigo,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Balance status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Your Wallet Balance:',
                          style: TextStyle(
                            color: isDarkMode
                                ? AppColors.darkTextMuted
                                : AppColors.lightTextMuted,
                          ),
                        ),
                        Text(
                          '₱ ${balance.toStringAsFixed(2)} TYXBIT',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: hasEnoughBalance ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    _isProcessing
                        ? const Center(child: CircularProgressIndicator())
                        : UIHelpers.buildPrimaryButton(
                            hasEnoughBalance
                                ? 'Request Booking'
                                : 'Insufficient Balance',
                            hasEnoughBalance
                                ? () async {
                                    final license = _licenseController.text
                                        .trim();
                                    if (license.isEmpty) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            widget.isProperty
                                                ? 'Please enter your ID Number'
                                                : 'Please enter your Driver\'s License',
                                          ),
                                        ),
                                      );
                                      return;
                                    }

                                    setState(() => _isProcessing = true);
                                    try {
                                      final repo = ref.read(
                                        transitRepositoryProvider,
                                      );

                                      final start =
                                          DateTime.now().millisecondsSinceEpoch;
                                      final int daysToAdd =
                                          _selectedDurationType == '12h'
                                          ? 0
                                          : (_selectedDurationType == 'weekly'
                                                ? 7 * _multiplier
                                                : (_selectedDurationType ==
                                                          'monthly'
                                                      ? 30 * _multiplier
                                                      : (_selectedDurationType ==
                                                                'yearly'
                                                            ? 365 * _multiplier
                                                            : 1 * _multiplier)));
                                      final end = _selectedDurationType == '12h'
                                          ? DateTime.now()
                                                .add(const Duration(hours: 12))
                                                .millisecondsSinceEpoch
                                          : DateTime.now()
                                                .add(Duration(days: daysToAdd))
                                                .millisecondsSinceEpoch;

                                      if (widget.isProperty) {
                                        await repo.createPropertyBookingRequest(
                                          propertyId: id,
                                          renteeId: userProfile.uid,
                                          renteeName: userProfile.name,
                                          renteePhotoUrl:
                                              userProfile.photoUrl ?? '',
                                          durationType: _selectedDurationType,
                                          multiplier: _multiplier,
                                          totalCost: baseTotal,
                                          contractType:
                                              widget.item['contractType'] ??
                                              'tranyx',
                                          contractTerms:
                                              widget.item['contractTerms'] ??
                                              'Property Lease Terms',
                                          startDate: start,
                                          endDate: end,
                                          licenseNumber: license,
                                        );
                                      } else {
                                        await repo.createBookingRequest(
                                          rentalId: id,
                                          renteeId: userProfile.uid,
                                          renteeName: userProfile.name,
                                          renteePhotoUrl:
                                              userProfile.photoUrl ?? '',
                                          durationType: _selectedDurationType,
                                          multiplier: _multiplier,
                                          licenseNumber: license,
                                          totalCost: baseTotal,
                                          hireWithDriver: _hireWithDriver,
                                          rentalType: _rentalType,
                                          deliveryAddress:
                                              _deliveryAddressController.text
                                                  .trim(),
                                          startDate: start,
                                          endDate: end,
                                        );
                                      }

                                      // Invalidate providers to refresh lists in-place
                                      ref.invalidate(userProfileProvider);
                                      ref.invalidate(
                                        renterPendingRequestsProvider,
                                      );
                                      ref.invalidate(
                                        propertyRenterPendingRequestsProvider,
                                      );

                                      if (mounted) {
                                        Navigator.pop(context);
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Booking request sent to host! Funds locked in escrow.',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text('Booking failed: $e'),
                                          ),
                                        );
                                      }
                                    } finally {
                                      setState(() => _isProcessing = false);
                                    }
                                  }
                                : null,
                            isDarkMode,
                          ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
