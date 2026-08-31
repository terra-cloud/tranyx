// ignore_for_file: unnecessary_string_interpolations

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
import '../../services/web_interop.dart';
import '../../services/firebase_service.dart';
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
  Promo? _appliedPromo;
  String _promoCodeInput = '';
  String? _promoFeedback;
  bool _isValidatingPromo = false;

  bool _isBooking = false;
  String? _error;

  int get _calculatedTotalDays {
    switch (_selectedDurationType) {
      case 'Weekly':
        return _multiplier * 7;
      case 'Daily':
        return _multiplier * 1;
      default:
        return _multiplier * 30;
    }
  }

  BookingFinancials get _financials {
    final p = component.appState.selectedPropertyData;
    if (p == null) {
      return const BookingFinancials(
        appliedTier: DurationTier.daily,
        totalDays: 1,
        unitRate: 0.0,
        baseRent: 0.0,
        securityDeposit: 0.0,
        depositType: DepositType.none,
        depositValue: 0.0,
        customerPlatformFeeRate: 0.03,
        customerPlatformFee: 0.0,
        totalCustomerPayable: 0.0,
        hostCommissionRate: 0.07,
        hostCommission: 0.0,
        hostNetIncome: 0.0,
      );
    }
    final model = PropertyPricingModel.fromPropertyMap(p);
    return model.calculate(totalDays: _calculatedTotalDays);
  }

  double get _basePrice => _financials.unitRate;
  double get _totalRent => _financials.baseRent;
  double get _depositAmount => _financials.securityDeposit;
  double get _advanceAmount => 0.0;
  double get _totalPrice => _totalRent + _depositAmount;
  double get _originalPlatformFee => _financials.customerPlatformFee;

  PromoCalculationResult get _promoResult {
    if (_appliedPromo == null) {
      return PromoCalculationResult(
        basePrice: _totalRent + _depositAmount,
        originalPlatformFee: _originalPlatformFee,
        discountAmount: 0.0,
        finalPlatformFee: _originalPlatformFee,
        finalCustomerAmount: _totalRent + _depositAmount + _originalPlatformFee,
        providerSettlement: _totalRent + _depositAmount,
        tranyxRevenue: _originalPlatformFee,
        tranyxPromoCost: 0.0,
      );
    }
    return _appliedPromo!.calculateDiscount(
      basePrice: _totalRent + _depositAmount,
      platformFee: _originalPlatformFee,
    );
  }

  double get _discountAmount => _promoResult.discountAmount;
  double get _bookingFee => _promoResult.finalPlatformFee;
  double get _totalCustomerPays => _totalRent + _depositAmount + _bookingFee;

  DateTime _startDate = DateTime.now();

  DateTime get _computedEndDate {
    switch (_selectedDurationType) {
      case 'Weekly':
        return _startDate.add(Duration(days: 7 * _multiplier));
      case 'Daily':
        return _startDate.add(Duration(days: 1 * _multiplier));
      default:
        return _startDate.add(Duration(days: 30 * _multiplier));
    }
  }

  void _loadAutoApplyPromo() async {
    try {
      final activePromos = await component.appState.firestore.getAllActivePromos();
      final user = component.appState.userProfile;
      final currentUid = user?.uid;
      if (user == null || currentUid == null) return;

      final now = DateTime.now();
      final eligiblePromos = activePromos.where((promo) {
        if (promo.applicableTo != 'rentals' && promo.applicableTo != 'both') {
          return false;
        }
        if (promo.expirationDate != null && promo.expirationDate!.isBefore(now)) {
          return false;
        }
        if (promo.maxUsers != null && promo.usedCount >= promo.maxUsers!) {
          return false;
        }
        if (promo.isSingleUsePerUser && promo.usedBy.contains(currentUid)) {
          return false;
        }
        if (promo.eligibleUserUids != null &&
            promo.eligibleUserUids!.isNotEmpty &&
            !promo.eligibleUserUids!.contains(currentUid)) {
          return false;
        }
        if (promo.onlyForSubscribed && !user.isPremium) {
          return false;
        }
        if (promo.onlyForHybrid && user.accountType != AccountType.hybrid) {
          return false;
        }
        if (promo.applicableRoles.isNotEmpty && !promo.applicableRoles.contains('renter')) {
          return false;
        }
        return true;
      }).toList();

      if (eligiblePromos.isEmpty) {
        return;
      }

      final autoPromos = eligiblePromos.where((promoItem) => promoItem.isAutoApply).toList();
      if (autoPromos.isEmpty) {
        return;
      }

      final platformFee = _originalPlatformFee;
      Promo? bestPromo;
      double bestDiscount = -1.0;

      for (final promoItem in autoPromos) {
        final res = promoItem.calculateDiscount(
          basePrice: _totalPrice,
          platformFee: platformFee,
        );
        if (res.discountAmount > bestDiscount) {
          bestDiscount = res.discountAmount;
          bestPromo = promoItem;
        }
      }

      if (bestPromo != null && mounted) {
        final bp = bestPromo;
        setState(() {
          _appliedPromo = bp;
          _promoCodeInput = bp.code;
          _promoFeedback = 'Auto-applied promo: ${bp.name ?? bp.code}';
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
      final promo = await component.appState.firestore.getPromo(cleanCode);
      if (promo == null) {
        setState(() {
          _promoFeedback = 'Promo code not found.';
          _appliedPromo = null;
        });
        return;
      }

      final user = component.appState.userProfile;
      final currentUid = user?.uid;
      if (user == null || currentUid == null) throw Exception('User not logged in');

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
      if (promo.isSingleUsePerUser && promo.usedBy.contains(currentUid)) {
        setState(() {
          _promoFeedback = 'You have already used this promo code.';
          _appliedPromo = null;
        });
        return;
      }
      if (promo.eligibleUserUids != null &&
          promo.eligibleUserUids!.isNotEmpty &&
          !promo.eligibleUserUids!.contains(currentUid)) {
        setState(() {
          _promoFeedback = 'You are not eligible for this promo code.';
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
      if (promo.minTransactionAmount != null && (_totalPrice + _originalPlatformFee) < promo.minTransactionAmount!) {
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
      if (currentUid == null) throw FirebaseException('Not logged in', 403);
      final user = component.appState.userProfile;
      if (user == null) throw Exception('User profile not loaded.');

      final end = _computedEndDate;

      final totalRequired = _totalCustomerPays;
      if (user.tyxBalance < totalRequired) {
        component.appState.setState(() {
          component.appState.depositAmount = totalRequired - user.tyxBalance;
          component.appState.showDepositModal = true;
          component.appState.pendingPropertyBookingData = {
            'propertyId': p['id'],
            'durationType': _selectedDurationType,
            'multiplier': _multiplier,
            'totalCost': _totalPrice,
            'baseRentAmount': _totalRent,
            'securityDepositAmount': _depositAmount,
            'customerPlatformFeeRate': _financials.customerPlatformFeeRate,
            'hostCommissionRate': _financials.hostCommissionRate,
            'bookingFee': _bookingFee,
            'originalBookingFee': _originalPlatformFee,
            'discountAmount': _discountAmount,
            'contractType': p['contractType'] ?? 'Tranyx Standard',
            'contractTerms': p['contractTerms'] ?? 'Standard lease terms',
            'startDate': _startDate.millisecondsSinceEpoch,
            'endDate': end.millisecondsSinceEpoch,
            'licenseNumber': _licenseNumber,
            'promoCode': _appliedPromo?.code,
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
        baseRentAmount: _totalRent,
        securityDepositAmount: _depositAmount,
        customerPlatformFeeRate: _financials.customerPlatformFeeRate,
        hostCommissionRate: _financials.hostCommissionRate,
        contractType: p['contractType'] ?? 'Tranyx Standard',
        contractTerms: p['contractTerms'] ?? 'Standard lease terms',
        startDate: _startDate.millisecondsSinceEpoch,
        endDate: end.millisecondsSinceEpoch,
        licenseNumber: _licenseNumber,
        promoCode: _appliedPromo?.code,
        discountAmount: _discountAmount,
      );

      // Close modal
      component.appState.setState(() {
        component.appState.showBookPropertyModal = false;
        component.appState.selectedPropertyData = null;
      });
      await component.appState.loadRenterPendingRequests();
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
    final isHost = pData['hostId'] != null && currentUid != null && pData['hostId'] == currentUid;

    final propertyId = pData['id']?.toString();
    if (_lastPropertyId != propertyId) {
      _lastPropertyId = propertyId;
      _activeImageIndex = 0;
      _step = 1;
      _licenseNumber = '';
      final monthlyRate = (pData['priceMonthly'] as num?)?.toDouble() ?? 0.0;
      final weeklyRate = (pData['priceWeekly'] as num?)?.toDouble() ?? 0.0;
      final dailyRate = (pData['priceDaily'] as num?)?.toDouble() ?? 0.0;
      if (monthlyRate > 0) {
        _selectedDurationType = 'Monthly';
      } else if (weeklyRate > 0) {
        _selectedDurationType = 'Weekly';
      } else if (dailyRate > 0) {
        _selectedDurationType = 'Daily';
      } else {
        _selectedDurationType = 'Monthly';
      }
      _appliedPromo = null;
      _promoCodeInput = '';
      _promoFeedback = null;
      _isValidatingPromo = false;
      if (propertyId != null) {
        _loadAutoApplyPromo();
      }
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
                  div(classes: 'flex items-center gap-2', [
                    h2(classes: 'text-2xl font-bold', [Component.text(isHost ? 'Property Details' : 'Rent Property')]),
                    if (isHost)
                      span(
                        classes:
                            'px-2.5 py-0.5 rounded-full text-xs font-bold bg-indigo-500/15 text-indigo-400 border border-indigo-500/30',
                        [Component.text('Your Listing')],
                      ),
                  ]),
                  p(classes: 'text-xs text-zinc-500', [Component.text('$title • $categoryStr $pTypeStr')]),
                ]),
                button(
                  classes: 'p-2 rounded-full hover:bg-zinc-105 dark:hover:bg-zinc-800 transition-colors cursor-pointer',
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
                        classes:
                            'w-full h-full object-cover transition-all duration-300 cursor-zoom-in hover:opacity-95',
                        attributes: {'alt': 'Property interior/exterior'},
                        events: {
                          'click': (_) =>
                              component.appState.showFullScreenPhoto(photos[_activeImageIndex % photos.length]),
                        },
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
                      'mt-4 p-4 rounded-xl ${isDark ? "bg-purple-950/20 text-purple-300" : "bg-purple-50 text-purple-800"} text-xs space-y-3',
                  [
                    div(classes: 'grid grid-cols-1 sm:grid-cols-2 gap-3', [
                      div([
                        span(classes: 'block font-semibold mb-1', [Component.text('Move-in / Start Date:')]),
                        input(
                          type: InputType.date,
                          classes:
                              'w-full p-2 rounded-lg border text-xs ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 cursor-pointer',
                          attributes: {
                            'value':
                                '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}',
                            'min':
                                '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}',
                          },
                          events: {
                            'change': (e) {
                              final val = getInputValue(e.target);
                              final parsed = DateTime.tryParse(val);
                              if (parsed != null) {
                                setState(() => _startDate = parsed);
                              }
                            },
                          },
                        ),
                      ]),
                      div([
                        span(classes: 'block font-semibold mb-1', [Component.text('Move-out / End Date:')]),
                        input(
                          type: InputType.date,
                          classes:
                              'w-full p-2 rounded-lg border text-xs ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 cursor-pointer',
                          attributes: {
                            'value':
                                '${_computedEndDate.year}-${_computedEndDate.month.toString().padLeft(2, '0')}-${_computedEndDate.day.toString().padLeft(2, '0')}',
                            'min':
                                '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}',
                          },
                          events: {
                            'change': (e) {
                              final val = getInputValue(e.target);
                              final parsed = DateTime.tryParse(val);
                              if (parsed != null) {
                                final diffDays = parsed.difference(_startDate).inDays;
                                if (diffDays >= 1) {
                                  setState(() {
                                    if (_selectedDurationType == 'Daily') {
                                      _multiplier = diffDays;
                                    } else if (_selectedDurationType == 'Weekly') {
                                      _multiplier = (diffDays / 7).ceil().clamp(1, 99);
                                    } else {
                                      _multiplier = (diffDays / 30).ceil().clamp(1, 99);
                                    }
                                  });
                                }
                              }
                            },
                          },
                        ),
                      ]),
                    ]),
                    div(classes: 'flex justify-between items-center pt-1 border-t border-purple-500/20', [
                      span([Component.text('Lease Timeline:')]),
                      span(classes: 'font-bold', [
                        Component.text(
                          '${_formatDate(_startDate)} to ${_formatDate(_computedEndDate)}',
                        ),
                      ]),
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
                    hostIsVerified: baseProperty.hostIsVerified ?? (pData['hostIsVerified'] as bool? ?? (pData['hostVerificationStatus'] == 'VERIFIED')),
                    hostVerificationStatus: baseProperty.hostVerificationStatus ?? (pData['hostVerificationStatus'] as String? ?? 'UNVERIFIED'),
                    hostVerificationTier: baseProperty.hostVerificationTier ?? (pData['hostVerificationTier'] as String? ?? 'None'),
                    renteeName: component.appState.userProfile?.name,
                    renteePhotoUrl: component.appState.userProfile?.photoUrl,
                    renteeLicenseNumber: _licenseNumber.isNotEmpty ? _licenseNumber : null,
                    renteeIsVerified: component.appState.userProfile?.idVerified == true || (component.appState.userProfile?.verificationLevel ?? 0) >= 2,
                    renteeVerificationStatus: (component.appState.userProfile?.idVerified == true || (component.appState.userProfile?.verificationLevel ?? 0) >= 2) ? 'VERIFIED' : 'UNVERIFIED',
                    renteeVerificationTier: PartyVerificationHelper.formatVerificationTier(level: component.appState.userProfile?.verificationLevel, idVerified: component.appState.userProfile?.idVerified),
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
                    events: {'input': (e) => setState(() => _licenseNumber = getInputValue(e.target))},
                  ),
                ]),

                // Promo Code Section
                div(classes: 'mb-6', [
                  label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                    Component.text('Promo Code'),
                  ]),
                  div(classes: 'flex gap-2', [
                    input(
                      classes:
                          'flex-1 p-3 rounded-xl border ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-purple-500 transition-colors',
                      attributes: {'value': _promoCodeInput, 'placeholder': 'Enter code e.g., FIRST50'},
                      events: {
                        'input': (e) {
                          _promoCodeInput = getInputValue(e.target);
                        },
                      },
                    ),
                    button(
                      classes:
                          'px-4 py-2 rounded-xl font-semibold text-white bg-purple-600 hover:bg-purple-700 transition-colors cursor-pointer border-0 outline-none',
                      events: {
                        'click': (e) {
                          _applyManualPromo(_promoCodeInput);
                        },
                      },
                      [
                        Component.text(_isValidatingPromo ? 'Applying...' : 'Apply'),
                      ],
                    ),
                  ]),
                  if (_promoFeedback != null)
                    p(
                      classes: 'text-xs mt-1 font-semibold ${(_appliedPromo != null) ? "text-emerald-500" : "text-red-500"}',
                      [Component.text(_promoFeedback!)],
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
                      Component.text('$_multiplier × $_selectedDurationType Rent (${_financials.appliedTier.name.toUpperCase()} Tier)'),
                    ]),
                    span(classes: 'font-bold', [Component.text('₱ ${_totalRent.toStringAsFixed(2)}')]),
                  ]),
                  // Security Deposit
                  if (_depositAmount > 0) ...[
                    div(classes: 'flex justify-between text-sm', [
                      div(classes: 'flex items-center gap-1.5', [
                        lIcon('shield-check', cls: 'w-3.5 h-3.5 text-purple-400'),
                        span(classes: isDark ? 'text-zinc-400' : 'text-zinc-650', [
                          Component.text('Security Deposit (${_financials.depositType == DepositType.percentage ? "${_financials.depositValue.toStringAsFixed(0)}% of Rent" : "Refundable"})'),
                        ]),
                      ]),
                      span(classes: 'font-bold text-purple-400', [
                        Component.text('₱ ${_depositAmount.toStringAsFixed(2)}'),
                      ]),
                    ]),
                  ],
                  // Platform fee
                  div(classes: 'flex justify-between text-sm', [
                    div(classes: 'flex items-center gap-1.5', [
                      lIcon('percent', cls: 'w-3.5 h-3.5 text-zinc-400'),
                      span(classes: isDark ? 'text-zinc-400' : 'text-zinc-600', [
                        Component.text('Platform Service Fee (${PlatformFeeConfig.formatPercent(_financials.customerPlatformFeeRate)})'),
                      ]),
                    ]),
                    span(classes: 'font-bold ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                      Component.text('₱ ${_originalPlatformFee.toStringAsFixed(2)}'),
                    ]),
                  ]),
                  // Promo discount (applied to platform fee only)
                  if (_appliedPromo != null && _discountAmount > 0) ...[
                    div(classes: 'flex justify-between text-sm text-emerald-500 font-semibold', [
                      div(classes: 'flex items-center gap-1.5', [
                        lIcon('tag', cls: 'w-3.5 h-3.5 text-emerald-500'),
                        span([Component.text('Platform Fee Discount (${_appliedPromo!.code})')]),
                      ]),
                      span([
                        Component.text('- ₱ ${_discountAmount.toStringAsFixed(2)}'),
                      ]),
                    ]),
                    div(classes: 'flex justify-between text-xs text-purple-400', [
                      span([Component.text('Net Platform Fee Charged')]),
                      span(classes: 'font-bold', [Component.text('₱ ${_bookingFee.toStringAsFixed(2)}')]),
                    ]),
                  ],
                  // Divider
                  div(classes: 'h-px w-full bg-purple-500/20 my-1', []),
                  // Total escrow
                  div(classes: 'flex justify-between items-center', [
                    div([
                      span(classes: 'font-bold text-sm', [Component.text('Total Escrow Hold')]),
                      p(classes: 'text-[10px] ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                        Component.text('Customer Total Payable (Base + Platform Fee + Deposit)'),
                      ]),
                    ]),
                    span(classes: 'font-black text-xl text-purple-400', [
                      Component.text('₱ ${_totalCustomerPays.toStringAsFixed(2)}'),
                    ]),
                  ]),
                  div(classes: 'flex justify-between text-xs ${isDark ? "text-zinc-500" : "text-zinc-400"} pt-1', [
                    span([Component.text('Host Net Payout on Completion (${PlatformFeeConfig.formatPercent(1 - _financials.hostCommissionRate)})')]),
                    span(classes: 'font-bold text-emerald-500', [
                      Component.text('₱ ${_financials.hostNetIncome.toStringAsFixed(2)}'),
                    ]),
                  ]),
                ]),
                p(classes: 'text-[10px] text-zinc-500 mt-2', [
                  Component.text(
                    'Funds are held securely in escrow. On lease completion, TRANYX automatically deducts the 7% host commission and deposits net rent to host. Security deposits are released per inspection terms.',
                  ),
                ]),
              ],
            ]),

            // Footer
            div(classes: 'p-6 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center justify-between', [
              if (isHost) ...[
                button(
                  classes:
                      'px-6 py-2.5 rounded-xl font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800 text-zinc-300" : "border-zinc-300 hover:bg-zinc-50 text-zinc-700"} transition-colors cursor-pointer',
                  events: {
                    'click': (_) => component.appState.setState(() {
                      component.appState.showBookPropertyModal = false;
                      component.appState.selectedPropertyData = null;
                    }),
                  },
                  [Component.text('Close')],
                ),
                div(classes: 'flex items-center gap-3', [
                  if ((pData['status'] == null || pData['status'] == 'Available') &&
                      (pData['renteeId'] == null || (pData['renteeId'] as String).isEmpty))
                    button(
                      classes:
                          'px-6 py-2.5 rounded-xl font-bold text-white bg-indigo-600 hover:bg-indigo-700 transition-colors flex items-center gap-2 border-0 outline-none cursor-pointer shadow-lg shadow-indigo-500/20',
                      events: {
                        'click': (_) => component.appState.setState(() {
                          component.appState.showBookPropertyModal = false;
                          component.appState.showEditPropertyModal = true;
                        }),
                      },
                      [
                        lIcon('edit-3', cls: 'w-4 h-4'),
                        Component.text('Edit Listing'),
                      ],
                    ),
                  button(
                    classes:
                        'px-6 py-2.5 rounded-xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center gap-2 border-0 outline-none cursor-pointer shadow-lg shadow-purple-500/20',
                    events: {
                      'click': (_) => component.appState.setState(() {
                        component.appState.showBookPropertyModal = false;
                        component.appState.showManagePropertyModal = true;
                      }),
                    },
                    [
                      lIcon('sliders', cls: 'w-4 h-4'),
                      Component.text('Manage Listing'),
                    ],
                  ),
                ]),
              ] else ...[
                if (_step > 1)
                  button(
                    classes:
                        'px-6 py-2 rounded-xl font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-300 hover:bg-zinc-50"} transition-colors cursor-pointer',
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
              ],
            ]),
          ],
        ),
      ],
    );
  }

  Component _packageOption(String duration, String title, double rate, bool isDark) {
    final isSelected = _selectedDurationType == duration;
    final isAvailable = rate > 0;

    return div(
      classes:
          'p-4 rounded-2xl border text-center transition-all '
          '${!isAvailable ? (isDark ? "border-zinc-800/40 bg-zinc-900/20 opacity-40 cursor-not-allowed select-none" : "border-zinc-200/40 bg-zinc-100/40 opacity-40 cursor-not-allowed select-none") : (isSelected ? "border-purple-500 bg-purple-500/10 text-purple-400 font-extrabold cursor-pointer" : (isDark ? "border-zinc-800 bg-zinc-900/40 text-zinc-400 hover:bg-zinc-800/40 cursor-pointer" : "border-zinc-200 bg-zinc-50 text-zinc-600 hover:bg-zinc-100 cursor-pointer"))}',
      events: isAvailable
          ? {
              'click': (_) => setState(() {
                _selectedDurationType = duration;
                _multiplier = 1;
              }),
            }
          : {},
      [
        p(classes: 'text-xs uppercase font-bold opacity-60 mb-1', [Component.text(title)]),
        p(classes: 'text-sm font-extrabold', [
          if (isAvailable)
            Component.text('₱ ${rate.toStringAsFixed(0)}')
          else
            span(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-400"} font-normal', [Component.text('Not Offered')]),
        ]),
      ],
    );
  }

  String _monthName(int month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month - 1];
  }

  String _formatDate(DateTime dt) {
    return '${_monthName(dt.month)} ${dt.day.toString().padLeft(2, '0')}, ${dt.year}';
  }
}
