import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'package:shared/shared.dart';

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
  final _promoController = TextEditingController();

  String _selectedDurationType = 'daily';
  int _multiplier = 1;
  bool _hireWithDriver = false;
  String _rentalType = 'pickup'; // 'pickup' or 'delivery'
  late DateTime _startDate;

  bool _isProcessing = false;
  Promo? _appliedPromo;
  String? _promoFeedback;
  bool _isValidatingPromo = false;

  DateTime get _calculatedEndDate {
    final int daysToAdd = _selectedDurationType == '12h'
        ? 0
        : (_selectedDurationType == 'weekly'
            ? 7 * _multiplier
            : (_selectedDurationType == 'monthly'
                ? 30 * _multiplier
                : (_selectedDurationType == 'yearly'
                    ? 365 * _multiplier
                    : 1 * _multiplier)));
    return _selectedDurationType == '12h'
        ? _startDate.add(Duration(hours: 12 * _multiplier))
        : _startDate.add(Duration(days: daysToAdd));
  }

  @override
  void initState() {
    super.initState();
    if (widget.isProperty) {
      if ((widget.item['priceMonthly'] as num? ?? 0) > 0) {
        _selectedDurationType = 'monthly';
      } else if ((widget.item['priceWeekly'] as num? ?? 0) > 0) {
        _selectedDurationType = 'weekly';
      } else if ((widget.item['priceDaily'] as num? ?? 0) > 0) {
        _selectedDurationType = 'daily';
      } else {
        _selectedDurationType = 'monthly';
      }
    } else {
      if ((widget.item['priceDaily'] as num? ?? 0) > 0) {
        _selectedDurationType = 'daily';
      } else if ((widget.item['priceWeekly'] as num? ?? 0) > 0) {
        _selectedDurationType = 'weekly';
      } else if ((widget.item['priceMonthly'] as num? ?? 0) > 0) {
        _selectedDurationType = 'monthly';
      } else if ((widget.item['price12h'] as num? ?? 0) > 0) {
        _selectedDurationType = '12h';
      } else {
        _selectedDurationType = 'daily';
      }
    }
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day, now.hour + 1, 0);
    if (_startDate.hour == 0) {
      _startDate = DateTime(now.year, now.month, now.day + 1, 9, 0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAutoApplyPromo();
    });
  }

  @override
  void dispose() {
    _licenseController.dispose();
    _deliveryAddressController.dispose();
    _promoController.dispose();
    super.dispose();
  }

  void _loadAutoApplyPromo() async {
    try {
      final repo = ref.read(transitRepositoryProvider);
      final activePromos = await repo.getAllActivePromos();
      final user = ref.read(userProfileProvider).value;
      if (user == null) return;

      final now = DateTime.now();
      final eligiblePromos = activePromos.where((promo) {
        if (promo.applicableTo != 'rentals' && promo.applicableTo != 'both') return false;
        if (promo.expirationDate != null && promo.expirationDate!.isBefore(now)) return false;
        if (promo.maxUsers != null && promo.usedCount >= promo.maxUsers!) return false;
        if (promo.isSingleUsePerUser && promo.usedBy.contains(user.uid)) return false;
        if (promo.eligibleUserUids != null &&
            promo.eligibleUserUids!.isNotEmpty &&
            !promo.eligibleUserUids!.contains(user.uid)) {
          return false;
        }
        if (promo.onlyForSubscribed && !user.isPremium) return false;
        if (promo.onlyForHybrid && user.accountType != AccountType.hybrid) return false;
        if (promo.applicableRoles.isNotEmpty && !promo.applicableRoles.contains('renter')) return false;
        return true;
      }).toList();

      if (eligiblePromos.isEmpty) return;

      final autoPromos = eligiblePromos.where((p) => p.isAutoApply).toList();
      if (autoPromos.isEmpty) return;

      final baseRate = _getRate(_selectedDurationType);
      final double driverCost = _hireWithDriver
          ? ((widget.item['driverDailyPrice'] as num?)?.toDouble() ?? 0.0)
          : 0.0;
      final baseTotal = widget.isProperty 
          ? (baseRate * _multiplier)
          : ((_multiplier * baseRate) + (_multiplier * driverCost));
      final platformFee = baseTotal * 0.03;

      Promo? bestPromo;
      double bestDiscount = -1.0;

      for (final p in autoPromos) {
        final res = p.calculateDiscount(
          basePrice: baseTotal,
          platformFee: platformFee,
        );
        if (res.discountAmount > bestDiscount) {
          bestDiscount = res.discountAmount;
          bestPromo = p;
        }
      }

      final promo = bestPromo;
      if (promo != null && mounted) {
        setState(() {
          _appliedPromo = promo;
          _promoController.text = promo.code;
          _promoFeedback = 'Auto-applied promo: ${promo.name ?? promo.code}';
        });
      }
    } catch (e) {
      print('ERROR loading auto promo: $e');
    }
  }

  void _applyManualPromo(String code) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) {
      setState(() {
        _promoFeedback = 'Please enter a promo code.';
      });
      return;
    }

    setState(() {
      _isValidatingPromo = true;
      _promoFeedback = null;
    });

    try {
      final repo = ref.read(transitRepositoryProvider);
      final promo = await repo.getPromo(cleanCode);
      if (promo == null) {
        setState(() {
          _promoFeedback = 'Promo code not found.';
          _appliedPromo = null;
        });
        return;
      }

      final user = ref.read(userProfileProvider).value;
      if (user == null) throw Exception('User profile not loaded');

      final now = DateTime.now();
      if (!promo.isActive) {
        setState(() {
          _promoFeedback = 'This promo code is inactive.';
          _appliedPromo = null;
        });
        return;
      }
      if (promo.applicableTo != 'rentals' && promo.applicableTo != 'both') {
        setState(() {
          _promoFeedback = 'This promo is not applicable to rentals.';
          _appliedPromo = null;
        });
        return;
      }
      if (promo.startDate != null && promo.startDate!.isAfter(now)) {
        setState(() {
          _promoFeedback = 'This promo code is not active yet.';
          _appliedPromo = null;
        });
        return;
      }
      if (promo.expirationDate != null && promo.expirationDate!.isBefore(now)) {
        setState(() {
          _promoFeedback = 'This promo code has expired.';
          _appliedPromo = null;
        });
        return;
      }
      if (promo.maxUsers != null && promo.usedCount >= promo.maxUsers!) {
        setState(() {
          _promoFeedback = 'This promo code has reached its maximum usage limit.';
          _appliedPromo = null;
        });
        return;
      }
      if (promo.isSingleUsePerUser && promo.usedBy.contains(user.uid)) {
        setState(() {
          _promoFeedback = 'You have already used this promo code.';
          _appliedPromo = null;
        });
        return;
      }
      if (promo.eligibleUserUids != null &&
          promo.eligibleUserUids!.isNotEmpty &&
          !promo.eligibleUserUids!.contains(user.uid)) {
        setState(() {
          _promoFeedback = 'You are not eligible for this promo code.';
          _appliedPromo = null;
        });
        return;
      }
      final baseRate = _getRate(_selectedDurationType);
      final double driverCost = _hireWithDriver
          ? ((widget.item['driverDailyPrice'] as num?)?.toDouble() ?? 0.0)
          : 0.0;
      final baseTotal = widget.isProperty 
          ? (baseRate * _multiplier)
          : ((_multiplier * baseRate) + (_multiplier * driverCost));
      final platformFee = baseTotal * 0.03;
      if (promo.minTransactionAmount != null && (baseTotal + platformFee) < promo.minTransactionAmount!) {
        setState(() {
          _promoFeedback = 'Minimum transaction amount of ₱ ${promo.minTransactionAmount!.toStringAsFixed(0)} required.';
          _appliedPromo = null;
        });
        return;
      }
      if (promo.onlyForSubscribed && !user.isPremium) {
        setState(() {
          _promoFeedback = 'This promo code is only for subscribed premium users.';
          _appliedPromo = null;
        });
        return;
      }
      if (promo.onlyForHybrid && user.accountType != AccountType.hybrid) {
        setState(() {
          _promoFeedback = 'This promo code is only for Hybrid PRO accounts.';
          _appliedPromo = null;
        });
        return;
      }
      if (promo.applicableRoles.isNotEmpty && !promo.applicableRoles.contains('renter')) {
        setState(() {
          _promoFeedback = 'This promo is not applicable for renters.';
          _appliedPromo = null;
        });
        return;
      }

      setState(() {
        _appliedPromo = promo;
        _promoFeedback = 'Promo code applied successfully!';
      });
    } catch (e) {
      setState(() {
        _promoFeedback = 'Failed to validate promo code: $e';
        _appliedPromo = null;
      });
    } finally {
      setState(() {
        _isValidatingPromo = false;
      });
    }
  }

  double _getRate(String durationType) {
    if (widget.isProperty) {
      if (durationType == 'daily') {
        return (widget.item['priceDaily'] as num?)?.toDouble() ?? 0.0;
      }
      if (durationType == 'weekly') {
        return (widget.item['priceWeekly'] as num?)?.toDouble() ?? 0.0;
      }
      if (durationType == 'monthly') {
        return (widget.item['priceMonthly'] as num?)?.toDouble() ?? 0.0;
      }
      if (durationType == 'yearly') {
        return ((widget.item['priceMonthly'] as num?)?.toDouble() ?? 0.0) * 12;
      }
    } else {
      if (durationType == '12h') {
        return (widget.item['price12h'] as num?)?.toDouble() ?? 0.0;
      }
      if (durationType == 'daily') {
        return (widget.item['priceDaily'] as num?)?.toDouble() ?? 0.0;
      }
      if (durationType == 'weekly') {
        return (widget.item['priceWeekly'] as num?)?.toDouble() ?? 0.0;
      }
      if (durationType == 'monthly') {
        return (widget.item['priceMonthly'] as num?)?.toDouble() ?? 0.0;
      }
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

    final totalDays = _selectedDurationType == '12h'
        ? 0
        : (_selectedDurationType == 'weekly'
            ? 7 * _multiplier
            : (_selectedDurationType == 'monthly'
                ? 30 * _multiplier
                : (_selectedDurationType == 'yearly'
                    ? 365 * _multiplier
                    : 1 * _multiplier)));

    final optRate = widget.isProperty
        ? SmartRateEngine.calculateOptimizedRate(
            totalDays: totalDays,
            priceDaily: (widget.item['priceDaily'] as num?)?.toDouble() ?? 0.0,
            priceWeekly: (widget.item['priceWeekly'] as num?)?.toDouble() ?? 0.0,
            priceMonthly: (widget.item['priceMonthly'] as num?)?.toDouble() ?? 0.0,
          )
        : SmartRateEngine.calculateOptimizedRate(
            totalDays: totalDays,
            hours: _selectedDurationType == '12h' ? 12 * _multiplier : 0,
            price12h: (widget.item['price12h'] as num?)?.toDouble() ?? 0.0,
            priceDaily: (widget.item['priceDaily'] as num?)?.toDouble() ?? 0.0,
            priceWeekly: (widget.item['priceWeekly'] as num?)?.toDouble() ?? 0.0,
            priceMonthly: (widget.item['priceMonthly'] as num?)?.toDouble() ?? 0.0,
          );

    final double driverDailyRate = (widget.item['driverDailyPrice'] as num?)?.toDouble() ?? 0.0;
    final double driverEffectiveDays = _selectedDurationType == '12h' ? 0.5 * _multiplier : totalDays.toDouble();
    final double driverCost = _hireWithDriver ? (driverDailyRate * driverEffectiveDays) : 0.0;

    final propertyFinancials = widget.isProperty
        ? PropertyPricingModel.fromPropertyMap(widget.item).calculate(totalDays: totalDays)
        : null;

    final baseTotal = widget.isProperty
        ? (propertyFinancials!.baseRent + propertyFinancials.securityDeposit)
        : (optRate.totalBasePrice + driverCost);
    final originalPlatformFee = widget.isProperty
        ? propertyFinancials!.customerPlatformFee
        : (baseTotal * 0.03);
    
    final promoResult = _appliedPromo != null
        ? _appliedPromo!.calculateDiscount(
            basePrice: baseTotal,
            platformFee: originalPlatformFee,
          )
        : PromoCalculationResult(
            basePrice: baseTotal,
            originalPlatformFee: originalPlatformFee,
            discountAmount: 0.0,
            finalPlatformFee: originalPlatformFee,
            finalCustomerAmount: baseTotal + originalPlatformFee,
            providerSettlement: baseTotal,
            tranyxRevenue: originalPlatformFee,
            tranyxPromoCost: 0.0,
          );

    final discountAmount = promoResult.discountAmount;
    final bookingFee = promoResult.finalPlatformFee;
    final totalRequired = promoResult.finalCustomerAmount;
    final balance = userProfile.tyxBalance;
    final hasEnoughBalance = balance >= totalRequired;

    return DraggableScrollableSheet(
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
                      initialValue: _selectedDurationType,
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
                              if ((widget.item['priceDaily'] as num? ?? 0) > 0)
                                const DropdownMenuItem(
                                  value: 'daily',
                                  child: Text('Daily'),
                                ),
                              if ((widget.item['priceWeekly'] as num? ?? 0) > 0)
                                const DropdownMenuItem(
                                  value: 'weekly',
                                  child: Text('Weekly'),
                                ),
                              if ((widget.item['priceMonthly'] as num? ?? 0) > 0)
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

                    // Reservation Schedule / Future Start Date & Time Picker
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? AppColors.darkCard
                            : Colors.purple.shade50.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDarkMode
                              ? AppColors.darkBorder
                              : Colors.purple.shade100,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.calendar_month,
                                size: 16,
                                color: AppColors.indigo,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'RESERVATION SCHEDULE & START DATE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.indigo,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final now = DateTime.now();
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _startDate.isBefore(now)
                                          ? now
                                          : _startDate,
                                      firstDate: DateTime(
                                        now.year,
                                        now.month,
                                        now.day,
                                      ),
                                      lastDate: now.add(
                                        const Duration(days: 365),
                                      ),
                                      helpText:
                                          'Select Reservation Start Date',
                                    );
                                    if (picked != null) {
                                      setState(() {
                                        _startDate = DateTime(
                                          picked.year,
                                          picked.month,
                                          picked.day,
                                          _startDate.hour,
                                          _startDate.minute,
                                        );
                                      });
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: isDarkMode
                                            ? Colors.grey.shade700
                                            : Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.event,
                                          size: 16,
                                          color: Colors.grey,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            DateFormat(
                                              'MMM dd, yyyy',
                                            ).format(_startDate),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final picked = await showTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay.fromDateTime(
                                        _startDate,
                                      ),
                                      helpText: 'Select Start Time',
                                    );
                                    if (picked != null) {
                                      setState(() {
                                        _startDate = DateTime(
                                          _startDate.year,
                                          _startDate.month,
                                          _startDate.day,
                                          picked.hour,
                                          picked.minute,
                                        );
                                      });
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: isDarkMode
                                            ? Colors.grey.shade700
                                            : Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.access_time,
                                          size: 16,
                                          color: Colors.grey,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            DateFormat(
                                              'hh:mm a',
                                            ).format(_startDate),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Colors.black26
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Starts:',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      DateFormat(
                                        'MMM dd, yyyy • hh:mm a',
                                      ).format(_startDate),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Returns / Ends:',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      DateFormat(
                                        'MMM dd, yyyy • hh:mm a',
                                      ).format(_calculatedEndDate),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.indigo,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
                              if (val) {
                                _licenseController.clear();
                              }
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
                            child: GestureDetector(
                              onTap: () => setState(() => _rentalType = 'pickup'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _rentalType == 'pickup'
                                      ? AppColors.indigo
                                      : (isDarkMode ? AppColors.darkCard : AppColors.lightCard),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _rentalType == 'pickup'
                                        ? AppColors.indigo
                                        : (isDarkMode ? AppColors.darkBorder : AppColors.lightBorder),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    'Self Pickup',
                                    style: TextStyle(
                                      color: _rentalType == 'pickup'
                                          ? Colors.white
                                          : (isDarkMode ? AppColors.darkText : AppColors.lightText),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _rentalType = 'delivery'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _rentalType == 'delivery'
                                      ? AppColors.indigo
                                      : (isDarkMode ? AppColors.darkCard : AppColors.lightCard),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _rentalType == 'delivery'
                                        ? AppColors.indigo
                                        : (isDarkMode ? AppColors.darkBorder : AppColors.lightBorder),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    'Doorstep',
                                    style: TextStyle(
                                      color: _rentalType == 'delivery'
                                          ? Colors.white
                                          : (isDarkMode ? AppColors.darkText : AppColors.lightText),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
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

                    // Driver License Number (Required for self-drive vehicle booking or property booking)
                    if (widget.isProperty || !_hireWithDriver) ...[
                      UIHelpers.buildTextField(
                        Icons.badge,
                        widget.isProperty
                            ? "Enter Government ID Number *"
                            : "Enter Driver's License Number * (Required for Self-Drive)",
                        isDarkMode,
                        controller: _licenseController,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Promo Code Section
                    Row(
                      children: [
                        Expanded(
                          child: UIHelpers.buildTextField(
                            Icons.tag,
                            "Enter Promo Code...",
                            isDarkMode,
                            controller: _promoController,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _isValidatingPromo
                              ? null
                              : () => _applyManualPromo(_promoController.text),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.indigo,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                          child: _isValidatingPromo
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Apply', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                    if (_promoFeedback != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _promoFeedback!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _appliedPromo != null ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
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
                              const Text(
                                'Optimized Base Rate',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '₱ ${optRate.totalBasePrice.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  optRate.breakdownDescription,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDarkMode ? Colors.purple.shade300 : Colors.purple.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (optRate.isCapped) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '✨ ${optRate.capReason ?? "Optimized Flat Rate Applied"}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ),
                                  if (optRate.savings > 0)
                                    Text(
                                      'Saved ₱ ${optRate.savings.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                          if (!widget.isProperty) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Rental Type'),
                                Text(
                                  _hireWithDriver
                                      ? 'With Driver (Chauffeur-Driven)'
                                      : 'Self-Drive',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('TRANYX Platform Fee (3%)'),
                              Text(
                                '₱ ${originalPlatformFee.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          if (_appliedPromo != null && discountAmount > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Platform Fee Promo (${_appliedPromo!.code})',
                                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '- ₱ ${discountAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Net Platform Fee Charged',
                                  style: TextStyle(color: AppColors.indigo, fontSize: 12),
                                ),
                                Text(
                                  '₱ ${bookingFee.toStringAsFixed(2)}',
                                  style: const TextStyle(color: AppColors.indigo, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                          ],
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
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Host Settlement (100% Guaranteed)',
                                style: TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              Text(
                                '₱ ${baseTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
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
                                    final bool requiresLicense =
                                        widget.isProperty || !_hireWithDriver;
                                    final license = _licenseController.text
                                        .trim();
                                    if (requiresLicense && license.isEmpty) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            widget.isProperty
                                                ? 'Please enter your Government ID Number'
                                                : "Driver's license number is required for self-drive bookings.",
                                          ),
                                          backgroundColor: Colors.red,
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
                                          _startDate.millisecondsSinceEpoch;
                                      final end = _calculatedEndDate
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
                                           baseRentAmount: propertyFinancials?.baseRent,
                                           securityDepositAmount: propertyFinancials?.securityDeposit,
                                           customerPlatformFeeRate: propertyFinancials?.customerPlatformFeeRate,
                                           hostCommissionRate: propertyFinancials?.hostCommissionRate,
                                           contractType:
                                               widget.item['contractType'] ??
                                               'tranyx',
                                           contractTerms:
                                               widget.item['contractTerms'] ??
                                               'Property Lease Terms',
                                           startDate: start,
                                           endDate: end,
                                           licenseNumber: license,
                                           promoCode: _appliedPromo?.code,
                                           discountAmount: discountAmount,
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
                                           licenseNumber: _hireWithDriver ? null : (license.isNotEmpty ? license : null),
                                           totalCost: baseTotal,
                                           hireWithDriver: _hireWithDriver,
                                           rentalType: _rentalType,
                                           deliveryAddress:
                                               _deliveryAddressController.text
                                                   .trim(),
                                           startDate: start,
                                           endDate: end,
                                           promoCode: _appliedPromo?.code,
                                           discountAmount: discountAmount,
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
        ), // close Container
        ); // close Padding
      },
    );
  }
}
