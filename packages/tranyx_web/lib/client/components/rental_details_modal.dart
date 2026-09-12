import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import 'contract_viewer.dart';

class RentalDetailsModalComponent extends StatefulComponent {
  final TranyxAppState appState;
  final Map<String, dynamic> rentalData;
  final bool isProperty;
  final VoidCallback onClose;

  const RentalDetailsModalComponent({
    required this.appState,
    required this.rentalData,
    required this.isProperty,
    required this.onClose,
    super.key,
  });

  @override
  State<RentalDetailsModalComponent> createState() => _RentalDetailsModalState();
}

class _RentalDetailsModalState extends State<RentalDetailsModalComponent> {
  bool _showFullContract = false;
  VehicleRental? _vehicleRental;
  PropertyRental? _propertyRental;

  @override
  void initState() {
    super.initState();
    _loadListingDetails();
  }

  Future<void> _loadListingDetails() async {
    final rentalId = (component.rentalData['rentalId'] ?? component.rentalData['id'])?.toString();
    if (rentalId == null || rentalId.isEmpty) return;

    try {
      if (component.isProperty) {
        final prop = await component.appState.firestore.getPropertyRental(rentalId);
        if (mounted) setState(() => _propertyRental = prop);
      } else {
        final vehicle = await component.appState.firestore.getRental(rentalId);
        if (mounted) setState(() => _vehicleRental = vehicle);
      }
    } catch (_) {}
  }

  @override
  Component build(BuildContext context) {
    final isDark = component.appState.isDark;
    final data = component.rentalData;
    final isProp = component.isProperty;

    // Extract identifiers & listings
    final rentalId = (data['rentalId'] ?? data['id'])?.toString() ?? '';
    final rawBookingRef = data['bookingReference'] ?? data['refNumber'] ?? data['id'];
    final bookingRef = rawBookingRef != null
        ? '#${rawBookingRef.toString().substring(0, rawBookingRef.toString().length > 10 ? 10 : rawBookingRef.toString().length).toUpperCase()}'
        : '#RN-TRX';

    // Listing data fallback from realtime arrays
    final listingVehicle = !isProp
        ? component.appState.realtimeRentals.firstWhere(
            (e) => e['id'] == rentalId,
            orElse: () => <String, dynamic>{},
          )
        : <String, dynamic>{};
    final PropertyRental? matchedProp = isProp
        ? component.appState.realtimeProperties.where((prop) => prop.id == rentalId).firstOrNull
        : null;
    final Map<String, dynamic> listingProperty = matchedProp?.toMap() ?? <String, dynamic>{};

    // Extract Title & Subtitle
    final brand = (data['brand'] ?? listingVehicle['brand'] ?? '').toString().trim();
    final model = (data['model'] ?? listingVehicle['model'] ?? '').toString().trim();
    final vehicleTitle = '$brand $model'.trim().isNotEmpty ? '$brand $model'.trim() : 'Vehicle Rental';
    final propTitle = (data['title'] ?? listingProperty['title'] ?? 'Property Lease').toString();
    final title = isProp ? propTitle : vehicleTitle;

    // Plate & Property Specs
    final plate = (data['plateNumber'] ?? listingVehicle['plateNumber'])?.toString().trim();
    final hasValidPlate = plate != null && plate.isNotEmpty && plate.toLowerCase() != 'null';

    // Status logic
    final rawStatus = (data['status'] ?? listingVehicle['status'] ?? listingProperty['status'] ?? 'Approved').toString();
    final isSigned = (data['signedAt'] != null && (data['signedAt'] as num) > 0) ||
        (data['signatureName'] != null && data['signatureName'].toString().isNotEmpty && data['signatureName'].toString() != 'null') ||
        (data['signatureHash'] != null && data['signatureHash'].toString().isNotEmpty) ||
        (listingVehicle['signedAt'] != null && (listingVehicle['signedAt'] as num) > 0) ||
        (listingVehicle['signatureHash'] != null && listingVehicle['signatureHash'].toString().isNotEmpty);

    final isAwaitingSignature = !isSigned && (
      rawStatus.toLowerCase() == 'awaiting signature' ||
      rawStatus.toLowerCase() == 'approved' ||
      listingVehicle['status']?.toString().toLowerCase() == 'awaiting signature'
    );

    final status = isAwaitingSignature ? 'Awaiting Signature' : rawStatus;
    final isOngoing = status == 'Ongoing' || status == 'Active' || status == 'On the way to Rentee' || status == 'Returning';

    // Photos
    final photos = (data['photoUrls'] as List?)?.map((e) => e.toString()).toList() ??
        (listingVehicle['photoUrls'] as List?)?.map((e) => e.toString()).toList() ??
        (listingProperty['photoUrls'] as List?)?.map((e) => e.toString()).toList() ??
        [];
    final primaryPhoto = photos.isNotEmpty && photos.first.isNotEmpty ? photos.first : null;

    // Financials
    final totalAmount = (data['totalAmount'] as num?)?.toDouble() ??
        (data['amount'] as num?)?.toDouble() ??
        (listingVehicle['priceDaily'] as num?)?.toDouble() ??
        (listingProperty['priceMonthly'] as num?)?.toDouble() ??
        0.0;
    final depositAmount = (data['depositAmount'] as num?)?.toDouble() ??
        (data['securityDeposit'] as num?)?.toDouble() ??
        (listingVehicle['securityDeposit'] as num?)?.toDouble() ??
        (listingProperty['securityDeposit'] as num?)?.toDouble() ??
        0.0;
    final dailyRate = (data['priceDaily'] as num?)?.toDouble() ?? (listingVehicle['priceDaily'] as num?)?.toDouble();
    final monthlyRate = (data['priceMonthly'] as num?)?.toDouble() ?? (listingProperty['priceMonthly'] as num?)?.toDouble();

    // Schedule Timestamps
    final startMs = (data['startDate'] as num?)?.toInt() ?? (listingVehicle['startDate'] as num?)?.toInt();
    final endMs = (data['endDate'] as num?)?.toInt() ?? (listingVehicle['endDate'] as num?)?.toInt();
    final startDateStr = startMs != null ? DateTime.fromMillisecondsSinceEpoch(startMs).toLocal().toString().substring(0, 16) : 'Scheduled at booking';
    final endDateStr = endMs != null ? DateTime.fromMillisecondsSinceEpoch(endMs).toLocal().toString().substring(0, 16) : 'Scheduled return';

    final durationDays = (data['durationDays'] as num?)?.toInt() ?? 1;
    final durationHours = (data['hours'] as num?)?.toInt();
    final durationStr = durationHours != null && durationHours > 0
        ? '$durationHours Hours'
        : (isProp ? '${data['leaseTermMonths'] ?? 1} Months' : '$durationDays Days');

    // Locations
    final pickupLocation = (data['pickupLocation'] ?? data['locationAddress'] ?? listingVehicle['locationAddress'] ?? listingProperty['address'] ?? 'Designated Location').toString();
    final dropoffLocation = (data['dropoffLocation'] ?? pickupLocation).toString();
    final handoverInstructions = (data['handoverInstructions'] ?? data['instructions'] ?? 'Follow standard safety and handover procedure. Inspect before departure.').toString();

    // Signatures and Cryptography
    final signatureHash = (data['signatureHash'] ?? listingVehicle['signatureHash'] ?? '0x8f3c7b2a9e1d4a0b5c6e7f8a9b0c1d2e3f4a5b6c').toString();
    final signedAtMs = (data['signedAt'] as num?)?.toInt() ?? (listingVehicle['signedAt'] as num?)?.toInt();
    final signedAtStr = signedAtMs != null ? DateTime.fromMillisecondsSinceEpoch(signedAtMs).toLocal().toString().substring(0, 16) : 'Pending';
    final signatoryName = (data['signatureName'] ?? component.appState.userProfile?.name ?? 'Verified Rentee').toString();
    final contractTerms = (data['contractTerms'] ?? listingVehicle['contractTerms'] ?? listingProperty['contractTerms'] ?? 'Standard P2P Rental Terms and Conditions apply. Both parties agree to escrow protection, vehicle inspection protocols, and timely handover.').toString();

    // Chat thread info
    final chatId = isProp ? 'property_${rentalId}_${component.appState.userProfile?.uid}' : 'rental_${rentalId}_${component.appState.userProfile?.uid}';
    final unreadCount = component.appState.getUnreadChatCount(chatId);
    final allowChat = data['allowChat'] ?? true;

    return div(
      classes: 'fixed inset-0 z-[9999] flex items-center justify-center p-3 md:p-6 bg-black/80 backdrop-blur-md animate-fade-in',
      events: {
        'click': (_) => component.onClose(),
      },
      [
        div(
          classes:
              'w-full max-w-3xl max-h-[92vh] flex flex-col rounded-3xl overflow-hidden border shadow-2xl transition-all ${isDark ? "bg-zinc-900 border-zinc-800 text-zinc-100" : "bg-white border-zinc-200 text-zinc-900"}',
          events: {
            'click': (e) => e.stopPropagation(),
          },
          [
            // ── Modal Header ──
            div(
              classes:
                  'px-6 py-4 border-b flex items-center justify-between ${isDark ? "border-zinc-800 bg-zinc-900/60" : "border-zinc-100 bg-zinc-50/80"}',
              [
                div(classes: 'flex items-center gap-3', [
                  div(
                    classes:
                        'p-2.5 rounded-2xl ${isProp ? "bg-teal-500/10 text-teal-400" : "bg-purple-500/10 text-purple-400"}',
                    [lIcon(isProp ? 'home' : 'car', cls: 'w-5 h-5')],
                  ),
                  div([
                    div(classes: 'flex items-center gap-2', [
                      h2(classes: 'font-extrabold text-lg leading-tight tracking-tight', [
                        Component.text(isProp ? 'Property Lease Details' : 'Rental Booking Details'),
                      ]),
                      span(
                        classes:
                            'px-2 py-0.5 rounded-md text-[11px] font-mono font-bold ${isDark ? "bg-zinc-800 text-zinc-400" : "bg-zinc-200 text-zinc-700"}',
                        [Component.text(bookingRef)],
                      ),
                    ]),
                    p(
                      classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"}',
                      [Component.text('Review confirmed booking parameters, signed contract, and schedule')],
                    ),
                  ]),
                ]),
                button(
                  classes:
                      'p-2 rounded-xl border border-transparent hover:border-zinc-700/50 ${isDark ? "hover:bg-zinc-800 text-zinc-400" : "hover:bg-zinc-100 text-zinc-600"} cursor-pointer transition-all',
                  events: {'click': (_) => component.onClose()},
                  [lIcon('x', cls: 'w-5 h-5')],
                ),
              ],
            ),

            // ── Scrollable Modal Body ──
            div(classes: 'flex-1 overflow-y-auto p-6 space-y-6', [
              // 1. Hero / Overview Card
              _buildHeroSection(
                title: title,
                plate: hasValidPlate ? plate : null,
                primaryPhoto: primaryPhoto,
                status: status,
                isOngoing: isOngoing,
                isAwaitingSignature: isAwaitingSignature,
                isProp: isProp,
                isDark: isDark,
                data: data,
                listingVehicle: listingVehicle,
                listingProperty: listingProperty,
              ),

              // 2. Lifecycle History Stepper
              _buildLifecycleTimeline(
                status: status,
                isSigned: isSigned,
                isOngoing: isOngoing,
                isAwaitingSignature: isAwaitingSignature,
                isDark: isDark,
              ),

              // 3. Schedule & Handover Details
              _buildScheduleSection(
                startDateStr: startDateStr,
                endDateStr: endDateStr,
                durationStr: durationStr,
                pickupLocation: pickupLocation,
                dropoffLocation: dropoffLocation,
                handoverInstructions: handoverInstructions,
                isProp: isProp,
                isDark: isDark,
              ),

              // 4. Financials & Escrow Protection
              _buildFinancialsSection(
                totalAmount: totalAmount,
                depositAmount: depositAmount,
                dailyRate: dailyRate,
                monthlyRate: monthlyRate,
                durationStr: durationStr,
                isProp: isProp,
                isDark: isDark,
              ),

              // 5. Signed Agreement & Cryptography
              _buildContractSection(
                isSigned: isSigned,
                isAwaitingSignature: isAwaitingSignature,
                signedAtStr: signedAtStr,
                signatoryName: signatoryName,
                signatureHash: signatureHash,
                contractTerms: contractTerms,
                title: title,
                isProp: isProp,
                isDark: isDark,
              ),
            ]),

            // ── Contextual Action Footer ──
            div(
              classes:
                  'px-6 py-4 border-t flex flex-wrap items-center justify-between gap-3 ${isDark ? "border-zinc-800 bg-zinc-900/90" : "border-zinc-100 bg-zinc-50"}',
              [
                div(classes: 'flex items-center gap-2', [
                  if (allowChat)
                    button(
                      classes:
                          'px-4 py-2.5 rounded-xl text-xs font-bold border border-blue-500/30 text-blue-400 bg-blue-500/10 hover:bg-blue-500/20 cursor-pointer flex items-center gap-2 transition-all',
                      events: {
                        'click': (_) {
                          component.onClose();
                          component.appState.openChat(chatId);
                        },
                      },
                      [
                        lIcon('message-square', cls: 'w-4 h-4 text-blue-400'),
                        Component.text('Chat Host'),
                        if (unreadCount > 0)
                          span(
                            classes: 'px-1.5 py-0.2 rounded-full text-[10px] font-black bg-red-500 text-white',
                            [Component.text('$unreadCount')],
                          ),
                      ],
                    ),
                ]),
                div(classes: 'flex items-center gap-2.5', [
                  if (isAwaitingSignature)
                    button(
                      classes:
                          'px-5 py-2.5 rounded-xl text-xs font-bold text-white bg-emerald-600 hover:bg-emerald-500 shadow-lg shadow-emerald-600/30 border-0 cursor-pointer flex items-center gap-2 animate-pulse',
                      events: {
                        'click': (_) {
                          component.onClose();
                          component.appState.setState(() {
                            component.appState.signingContractId = rentalId;
                            component.appState.signingContractRequestId = data['id']?.toString();
                            component.appState.signingContractTitle = '$title Agreement';
                            component.appState.signingContractTerms = contractTerms;
                            component.appState.signingContractIsProperty = isProp;
                            component.appState.showSignContractModal = true;
                          });
                        },
                      },
                      [
                        lIcon('file-signature', cls: 'w-4 h-4 text-white'),
                        Component.text('Review & Sign Agreement'),
                      ],
                    ),
                  if (!isProp && isOngoing) ...[
                    button(
                      classes:
                          'px-4 py-2.5 rounded-xl text-xs font-bold text-purple-300 bg-purple-500/20 hover:bg-purple-500/30 border border-purple-500/30 cursor-pointer flex items-center gap-1.5 transition-all',
                      events: {
                        'click': (_) {
                          component.onClose();
                          component.appState.setState(() {
                            component.appState.selectedRentalData = data;
                            component.appState.showExtendRentalModal = true;
                          });
                        },
                      },
                      [
                        lIcon('clock', cls: 'w-3.5 h-3.5 text-purple-400'),
                        Component.text('Extend Rental'),
                      ],
                    ),
                    button(
                      classes:
                          'px-5 py-2.5 rounded-xl text-xs font-bold text-white bg-indigo-600 hover:bg-indigo-500 shadow-lg shadow-indigo-600/30 border-0 cursor-pointer flex items-center gap-2 transition-all',
                      events: {
                        'click': (_) {
                          component.onClose();
                          component.appState.setState(() {
                            component.appState.selectedRentalData = data;
                            component.appState.showRentalTrackerMap = true;
                          });
                        },
                      },
                      [
                        lIcon('navigation', cls: 'w-4 h-4 text-white'),
                        Component.text('Open Live Tracker & GPS'),
                      ],
                    ),
                  ],
                  button(
                    classes:
                        'px-4 py-2.5 rounded-xl text-xs font-semibold ${isDark ? "bg-zinc-800 text-zinc-300 hover:bg-zinc-700" : "bg-zinc-200 text-zinc-700 hover:bg-zinc-300"} border-0 cursor-pointer transition-all',
                    events: {'click': (_) => component.onClose()},
                    [Component.text('Close')],
                  ),
                ]),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ── 1. Hero / Overview Card ───────────────────────────────────────────────
  Component _buildHeroSection({
    required String title,
    required String? plate,
    required String? primaryPhoto,
    required String status,
    required bool isOngoing,
    required bool isAwaitingSignature,
    required bool isProp,
    required bool isDark,
    required Map<String, dynamic> data,
    required Map<String, dynamic> listingVehicle,
    required Map<String, dynamic> listingProperty,
  }) {
    final statusColor = isOngoing
        ? 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30'
        : (isAwaitingSignature
            ? 'bg-amber-500/20 text-amber-400 border-amber-500/30'
            : 'bg-purple-500/20 text-purple-300 border-purple-500/30');

    return div(
      classes:
          'p-5 rounded-2xl border ${isDark ? "bg-zinc-800/50 border-zinc-800" : "bg-zinc-50 border-zinc-200"} flex flex-col md:flex-row gap-5 items-start',
      [
        // Photo or Placeholder
        if (primaryPhoto != null)
          div(
            classes:
                'w-full md:w-48 h-32 rounded-xl overflow-hidden border border-zinc-700/40 relative flex-shrink-0 bg-zinc-950',
            [
              img(
                src: primaryPhoto,
                alt: title,
                classes: 'w-full h-full object-cover hover:scale-105 transition-transform duration-300',
              ),
            ],
          )
        else
          div(
            classes:
                'w-full md:w-48 h-32 rounded-xl border flex flex-col items-center justify-center flex-shrink-0 ${isDark ? "bg-zinc-800/80 border-zinc-700 text-zinc-500" : "bg-zinc-100 border-zinc-200 text-zinc-400"}',
            [
              lIcon(isProp ? 'home' : 'car', cls: 'w-10 h-10 mb-1'),
              span(classes: 'text-[11px] uppercase tracking-wider font-semibold', [Component.text('No Photo Available')]),
            ],
          ),

        // Info details
        div(classes: 'flex-1 min-w-0 space-y-2', [
          div(classes: 'flex items-center justify-between gap-2', [
            span(
              classes:
                  'px-3 py-1 rounded-full text-xs font-bold border flex items-center gap-1.5 uppercase tracking-wider $statusColor',
              [
                span([], classes: 'w-2 h-2 rounded-full ${isOngoing ? "bg-emerald-400 animate-ping" : (isAwaitingSignature ? "bg-amber-400" : "bg-purple-400")}'),
                Component.text(isAwaitingSignature ? 'Awaiting Signature' : status),
              ],
            ),
            span(
              classes:
                  'text-xs font-semibold px-2.5 py-1 rounded-lg ${isProp ? "bg-teal-500/10 text-teal-400" : "bg-indigo-500/10 text-indigo-400"}',
              [Component.text(isProp ? 'Property Lease' : 'Vehicle Rental')],
            ),
          ]),

          div([
            h3(classes: 'text-xl font-black leading-snug', [
              Component.text(title),
              if (plate != null)
                span(classes: 'text-sm font-bold text-zinc-400 font-mono ml-2', [Component.text('• $plate')]),
            ]),
          ]),

          // Quick Specs Chips
          div(classes: 'flex flex-wrap items-center gap-2 pt-1', [
            if (!isProp) ...[
              _specBadge('fuel', (data['fuelType'] ?? listingVehicle['fuelType'] ?? 'Gasoline').toString(), isDark),
              _specBadge('settings', (data['transmission'] ?? listingVehicle['transmission'] ?? 'Automatic').toString(), isDark),
              _specBadge('users', '${data['seats'] ?? listingVehicle['seats'] ?? 5} Seats', isDark),
              _specBadge('tag', (data['type'] ?? listingVehicle['type'] ?? 'SUV').toString(), isDark),
            ] else ...[
              _specBadge('home', (data['category'] ?? listingProperty['category'] ?? 'Residential').toString(), isDark),
              _specBadge('layers', '${data['bedrooms'] ?? listingProperty['bedrooms'] ?? 1} Bed', isDark),
              _specBadge('droplet', '${data['bathrooms'] ?? listingProperty['bathrooms'] ?? 1} Bath', isDark),
            ],
          ]),
        ]),
      ],
    );
  }

  // ── 2. Lifecycle History Stepper ──────────────────────────────────────────
  Component _buildLifecycleTimeline({
    required String status,
    required bool isSigned,
    required bool isOngoing,
    required bool isAwaitingSignature,
    required bool isDark,
  }) {
    // Stepper levels: 1: Requested, 2: Approved, 3: Signed, 4: Confirmed/Paid, 5: Active/Upcoming, 6: Completed
    int currentStep = 2; // default approved
    if (isSigned) currentStep = 4; // signed & escrow locked
    if (isOngoing) currentStep = 5;
    if (status.toLowerCase() == 'completed') currentStep = 6;
    if (isAwaitingSignature) currentStep = 2; // awaiting step 3

    final steps = [
      {'title': 'Requested', 'desc': 'Booking sent'},
      {'title': 'Approved', 'desc': 'Host accepted'},
      {'title': 'Signed', 'desc': 'Agreement executed'},
      {'title': 'Escrow Paid', 'desc': 'Funds protected'},
      {'title': 'Active / Schedule', 'desc': isOngoing ? 'Trip ongoing' : 'Confirmed schedule'},
      {'title': 'Completed', 'desc': 'Finished'},
    ];

    return div(
      classes:
          'p-5 rounded-2xl border ${isDark ? "bg-zinc-800/30 border-zinc-800" : "bg-white border-zinc-200"}',
      [
        div(classes: 'flex items-center justify-between mb-4', [
          h4(classes: 'text-xs font-black uppercase tracking-wider text-zinc-400 flex items-center gap-2', [
            lIcon('activity', cls: 'w-4 h-4 text-purple-400'),
            Component.text('Rental Lifecycle & Booking Timeline'),
          ]),
          span(classes: 'text-[11px] font-bold text-purple-400 bg-purple-500/10 px-2 py-0.5 rounded-md', [
            Component.text('Stage $currentStep of 6'),
          ]),
        ]),

        div(classes: 'relative flex items-center justify-between gap-1 overflow-x-auto pb-2', [
          for (int i = 0; i < steps.length; i++) ...[
            _timelineStep(
              stepNumber: i + 1,
              title: steps[i]['title']!,
              desc: steps[i]['desc']!,
              isDone: (i + 1) <= currentStep,
              isCurrent: (i + 1) == currentStep,
              isDark: isDark,
            ),
            if (i < steps.length - 1)
              div(
                classes:
                    'flex-1 h-0.5 mx-1 min-w-[20px] transition-all ${(i + 1) < currentStep ? "bg-purple-500" : (isDark ? "bg-zinc-800" : "bg-zinc-200")}',
                [],
              ),
          ],
        ]),
      ],
    );
  }

  Component _timelineStep({
    required int stepNumber,
    required String title,
    required String desc,
    required bool isDone,
    required bool isCurrent,
    required bool isDark,
  }) {
    final circleClass = isDone
        ? 'bg-purple-600 text-white shadow-md shadow-purple-600/30'
        : (isDark ? 'bg-zinc-800 text-zinc-500 border border-zinc-700' : 'bg-zinc-200 text-zinc-500');

    return div(classes: 'flex flex-col items-center text-center min-w-[80px]', [
      div(
        classes:
            'w-7 h-7 rounded-full flex items-center justify-center text-xs font-black mb-1.5 transition-all $circleClass ${isCurrent ? "ring-4 ring-purple-500/20 animate-pulse" : ""}',
        [
          if (isDone)
            lIcon('check', cls: 'w-3.5 h-3.5')
          else
            Component.text('$stepNumber'),
        ],
      ),
      p(
        classes:
            'text-[11px] font-bold leading-tight ${isDone ? (isDark ? "text-zinc-200" : "text-zinc-800") : "text-zinc-500"}',
        [Component.text(title)],
      ),
      p(classes: 'text-[9px] text-zinc-500 leading-tight mt-0.5 hidden sm:block', [Component.text(desc)]),
    ]);
  }

  // ── 3. Schedule & Handover Details ────────────────────────────────────────
  Component _buildScheduleSection({
    required String startDateStr,
    required String endDateStr,
    required String durationStr,
    required String pickupLocation,
    required String dropoffLocation,
    required String handoverInstructions,
    required bool isProp,
    required bool isDark,
  }) {
    return div(
      classes:
          'p-5 rounded-2xl border ${isDark ? "bg-zinc-800/30 border-zinc-800" : "bg-white border-zinc-200"} space-y-4',
      [
        h4(classes: 'text-xs font-black uppercase tracking-wider text-zinc-400 flex items-center gap-2', [
          lIcon('calendar', cls: 'w-4 h-4 text-indigo-400'),
          Component.text(isProp ? 'Lease Schedule & Check-in Rules' : 'Rental Schedule & Handover Instructions'),
        ]),

        div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4', [
          // Start / Handover
          div(
            classes: 'p-4 rounded-xl border ${isDark ? "bg-zinc-900/60 border-zinc-800" : "bg-zinc-50 border-zinc-200"}',
            [
              div(classes: 'flex items-center gap-2 text-xs font-bold text-emerald-400 mb-1', [
                lIcon('arrow-right', cls: 'w-3.5 h-3.5'),
                Component.text(isProp ? 'Lease Commencement' : 'Pickup & Handover Schedule'),
              ]),
              p(classes: 'font-bold text-sm', [Component.text(startDateStr)]),
              p(classes: 'text-xs text-zinc-500 mt-2 flex items-start gap-1.5', [
                lIcon('map-pin', cls: 'w-3.5 h-3.5 text-zinc-400 flex-shrink-0 mt-0.5'),
                span(classes: 'line-clamp-2', [Component.text(pickupLocation)]),
              ]),
            ],
          ),

          // End / Return
          div(
            classes: 'p-4 rounded-xl border ${isDark ? "bg-zinc-900/60 border-zinc-800" : "bg-zinc-50 border-zinc-200"}',
            [
              div(classes: 'flex items-center gap-2 text-xs font-bold text-blue-400 mb-1', [
                lIcon('arrow-left', cls: 'w-3.5 h-3.5'),
                Component.text(isProp ? 'Lease Expiration' : 'Scheduled Return & Dropoff'),
              ]),
              p(classes: 'font-bold text-sm', [Component.text(endDateStr)]),
              p(classes: 'text-xs text-zinc-500 mt-2 flex items-start gap-1.5', [
                lIcon('map-pin', cls: 'w-3.5 h-3.5 text-zinc-400 flex-shrink-0 mt-0.5'),
                span(classes: 'line-clamp-2', [Component.text(dropoffLocation)]),
              ]),
            ],
          ),
        ]),

        // Instructions note
        div(
          classes: 'p-3.5 rounded-xl border border-amber-500/20 bg-amber-500/5 text-xs text-amber-300 flex items-start gap-2.5',
          [
            lIcon('info', cls: 'w-4 h-4 text-amber-400 flex-shrink-0 mt-0.5'),
            div([
              span(classes: 'font-bold block', [Component.text('Handover Notes & Protocol:')]),
              span(classes: 'text-zinc-400', [Component.text(handoverInstructions)]),
            ]),
          ],
        ),
      ],
    );
  }

  // ── 4. Financials & Escrow Breakdown ──────────────────────────────────────
  Component _buildFinancialsSection({
    required double totalAmount,
    required double depositAmount,
    required double? dailyRate,
    required double? monthlyRate,
    required String durationStr,
    required bool isProp,
    required bool isDark,
  }) {
    return div(
      classes:
          'p-5 rounded-2xl border ${isDark ? "bg-zinc-800/30 border-zinc-800" : "bg-white border-zinc-200"} space-y-4',
      [
        div(classes: 'flex items-center justify-between', [
          h4(classes: 'text-xs font-black uppercase tracking-wider text-zinc-400 flex items-center gap-2', [
            lIcon('credit-card', cls: 'w-4 h-4 text-emerald-400'),
            Component.text('Financial Breakdown & Escrow Protection'),
          ]),
          span(
            classes:
                'px-2.5 py-0.5 rounded-md text-[11px] font-bold bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 flex items-center gap-1',
            [
              lIcon('shield-check', cls: 'w-3.5 h-3.5 text-emerald-400'),
              Component.text('Smart Escrow Protected'),
            ],
          ),
        ]),

        div(
          classes:
              'grid grid-cols-2 md:grid-cols-4 gap-3 p-4 rounded-xl ${isDark ? "bg-zinc-900/60 border border-zinc-800" : "bg-zinc-50 border border-zinc-200"}',
          [
            _financialCol('Rental Rate', dailyRate != null ? '₱${dailyRate.toStringAsFixed(0)} / day' : (monthlyRate != null ? '₱${monthlyRate.toStringAsFixed(0)} / mo' : 'Standard Rate'), isDark),
            _financialCol('Duration', durationStr, isDark),
            _financialCol('Security Deposit', depositAmount > 0 ? '₱${depositAmount.toStringAsFixed(0)}' : '₱0 (Waived)', isDark, highlight: true),
            _financialCol('Total Locked Amount', '₱${totalAmount.toStringAsFixed(0)}', isDark, isTotal: true),
          ],
        ),

        p(classes: 'text-xs text-zinc-500 italic', [
          Component.text(
            'Security deposits are locked safely in Tranyx smart contract escrow and automatically released upon successful return inspection with 0 disputes.',
          ),
        ]),
      ],
    );
  }

  Component _financialCol(String label, String value, bool isDark, {bool highlight = false, bool isTotal = false}) {
    return div(classes: 'flex flex-col', [
      span(classes: 'text-[11px] text-zinc-500 font-medium', [Component.text(label)]),
      span(
        classes:
            'text-sm font-black mt-0.5 ${isTotal ? "text-purple-400 text-base" : (highlight ? "text-emerald-400" : (isDark ? "text-zinc-200" : "text-zinc-800"))}',
        [Component.text(value)],
      ),
    ]);
  }

  // ── 5. Signed Agreement & Cryptography ─────────────────────────────────────
  Component _buildContractSection({
    required bool isSigned,
    required bool isAwaitingSignature,
    required String signedAtStr,
    required String signatoryName,
    required String signatureHash,
    required String contractTerms,
    required String title,
    required bool isProp,
    required bool isDark,
  }) {
    return div(
      classes:
          'p-5 rounded-2xl border ${isDark ? "bg-zinc-800/30 border-zinc-800" : "bg-white border-zinc-200"} space-y-4',
      [
        div(classes: 'flex items-center justify-between', [
          h4(classes: 'text-xs font-black uppercase tracking-wider text-zinc-400 flex items-center gap-2', [
            lIcon('file-text', cls: 'w-4 h-4 text-blue-400'),
            Component.text('Cryptographic Contract & Verification'),
          ]),
          button(
            classes:
                'px-3 py-1.5 rounded-xl text-xs font-bold ${isDark ? "bg-zinc-800 hover:bg-zinc-700 text-zinc-300" : "bg-zinc-100 hover:bg-zinc-200 text-zinc-700"} border border-zinc-700/30 cursor-pointer flex items-center gap-1.5 transition-all',
            events: {
              'click': (_) => setState(() => _showFullContract = !_showFullContract),
            },
            [
              lIcon(_showFullContract ? 'chevron-up' : 'chevron-down', cls: 'w-3.5 h-3.5'),
              Component.text(_showFullContract ? 'Hide Agreement Terms' : 'View Full Agreement'),
            ],
          ),
        ]),

        div(
          classes:
              'p-4 rounded-xl border ${isSigned ? "border-emerald-500/30 bg-emerald-500/5" : "border-amber-500/30 bg-amber-500/5"} space-y-3',
          [
            div(classes: 'flex items-center justify-between', [
              div(classes: 'flex items-center gap-2', [
                div(
                  classes:
                      'p-1.5 rounded-lg ${isSigned ? "bg-emerald-500/20 text-emerald-400" : "bg-amber-500/20 text-amber-400"}',
                  [lIcon(isSigned ? 'check-circle' : 'clock', cls: 'w-4 h-4')],
                ),
                div([
                  p(
                    classes: 'text-xs font-bold ${isSigned ? "text-emerald-400" : "text-amber-400"}',
                    [Component.text(isSigned ? 'Digitally Signed & SHA-256 Verified' : 'Awaiting Digital Signature')],
                  ),
                  p(classes: 'text-[11px] text-zinc-500', [
                    Component.text(isSigned ? 'Signed by $signatoryName on $signedAtStr' : 'Signature required prior to vehicle handover'),
                  ]),
                ]),
              ]),
            ]),

            // Hash display
            if (isSigned)
              div(classes: 'p-2.5 rounded-lg bg-zinc-950/70 border border-zinc-800 font-mono text-[11px] flex items-center justify-between text-zinc-400', [
                span(classes: 'truncate mr-2', [Component.text('Signature Hash: $signatureHash')]),
                span(classes: 'text-emerald-400 text-[10px] font-bold uppercase flex-shrink-0', [Component.text('VERIFIED')]),
              ]),
          ],
        ),

        // Expanded contract preview
        if (_showFullContract)
          div(classes: 'animate-fade-in pt-2', [
            ContractViewerComponent(
              vehicleRental: _vehicleRental,
              propertyRental: _propertyRental,
              customTerms: contractTerms,
              contractType: isProp ? 'Property Lease Agreement' : 'Vehicle Rental Agreement',
            ),
          ]),
      ],
    );
  }

  Component _specBadge(String iconName, String label, bool isDark) {
    return span(
      classes:
          'px-2.5 py-1 rounded-lg text-xs font-medium border flex items-center gap-1.5 ${isDark ? "bg-zinc-800/80 border-zinc-700/60 text-zinc-300" : "bg-zinc-100 border-zinc-200 text-zinc-700"}',
      [
        lIcon(iconName, cls: 'w-3.5 h-3.5 text-zinc-400'),
        Component.text(label),
      ],
    );
  }
}
