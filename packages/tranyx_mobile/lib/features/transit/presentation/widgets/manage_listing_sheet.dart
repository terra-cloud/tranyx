import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'package:intl/intl.dart';
import 'package:tranyx_mobile/core/widgets/user_avatar.dart';
import 'listing_wizard_sheet.dart';

class ManageListingSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  final bool isProperty;

  const ManageListingSheet({
    super.key,
    required this.item,
    required this.isProperty,
  });

  @override
  ConsumerState<ManageListingSheet> createState() => _ManageListingSheetState();
}

class _ManageListingSheetState extends ConsumerState<ManageListingSheet> {
  bool _isProcessing = false;
  String? _error;
  bool _allowChat = false;

  bool _isEditingGps = false;
  final _gpsController = TextEditingController();

  List<Map<String, dynamic>> _requests = [];
  bool _isLoadingRequests = true;
  bool _hasReservationRecords = false;

  @override
  void initState() {
    super.initState();
    _gpsController.text = widget.item['gpsTrackerId']?.toString() ?? '';
    _loadRequests();
  }

  @override
  void dispose() {
    _gpsController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoadingRequests = true);
    try {
      final repo = ref.read(transitRepositoryProvider);
      final id = widget.item['id'] as String;
      if (widget.isProperty) {
        final allList = await repo.getAllRequestsForProperty(id);
        allList.sort((a, b) {
          final aPending = (a['status']?.toString().toLowerCase() == 'pending') ? 0 : 1;
          final bPending = (b['status']?.toString().toLowerCase() == 'pending') ? 0 : 1;
          if (aPending != bPending) return aPending.compareTo(bPending);
          final aTime = (a['startDate'] as int?) ?? (a['createdAt'] as int?) ?? 0;
          final bTime = (b['startDate'] as int?) ?? (b['createdAt'] as int?) ?? 0;
          return bTime.compareTo(aTime);
        });
        setState(() {
          _requests = allList;
          _isLoadingRequests = false;
        });
      } else {
        final allList = await repo.getAllRequestsForVehicle(id);
        allList.sort((a, b) {
          final aPending = (a['status']?.toString().toLowerCase() == 'pending') ? 0 : 1;
          final bPending = (b['status']?.toString().toLowerCase() == 'pending') ? 0 : 1;
          if (aPending != bPending) return aPending.compareTo(bPending);
          final aTime = (a['startDate'] as int?) ?? (a['createdAt'] as int?) ?? 0;
          final bTime = (b['startDate'] as int?) ?? (b['createdAt'] as int?) ?? 0;
          return bTime.compareTo(aTime);
        });
        setState(() {
          _requests = allList;
          _hasReservationRecords = allList.isNotEmpty;
          _isLoadingRequests = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load requests: $e';
        _isLoadingRequests = false;
      });
    }
  }

  void _approveRequest(String requestId) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      final repo = ref.read(transitRepositoryProvider);
      final id = widget.item['id'] as String;
      if (widget.isProperty) {
        await repo.approvePropertyBookingRequest(requestId, id, _allowChat);
      } else {
        await repo.approveBookingRequest(requestId, id, _allowChat);
      }

      ref.invalidate(realtimeRentalsProvider);
      ref.invalidate(realtimePropertiesProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Booking request approved! Awaiting renter signature.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Error approving: $e';
      });
    }
  }

  void _rejectRequest(String requestId) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      final repo = ref.read(transitRepositoryProvider);
      if (widget.isProperty) {
        await repo.rejectPropertyBookingRequest(requestId);
      } else {
        await repo.rejectBookingRequest(requestId);
      }
      await _loadRequests();
      setState(() => _isProcessing = false);
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Error rejecting: $e';
      });
    }
  }

  void _updateBookingStatus(String requestId, String newStatus) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      final repo = ref.read(transitRepositoryProvider);
      final id = widget.item['id'] as String;
      if (widget.isProperty) {
        if (newStatus == 'Completed') {
          await repo.completePropertyRental(id, requestId: requestId);
        } else {
          await repo.updatePropertyStatus(id, newStatus, requestId: requestId);
        }
      } else {
        if (newStatus == 'Completed') {
          await repo.completeRental(id, requestId: requestId);
        } else {
          await repo.updateRentalStatus(id, newStatus, requestId: requestId);
        }
      }

      ref.invalidate(realtimeRentalsProvider);
      ref.invalidate(realtimePropertiesProvider);
      await _loadRequests();
      setState(() => _isProcessing = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 'Completed' ? 'Rental completed & payout released!' : 'Status updated to: $newStatus',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Error updating status: $e';
      });
    }
  }

  void _toggleAcceptingBookings(bool currentlyAccepting) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      final repo = ref.read(transitRepositoryProvider);
      final id = widget.item['id'] as String;
      final newAccepting = !currentlyAccepting;
      if (widget.isProperty) {
        await repo.setPropertyAcceptingBookings(id, newAccepting);
      } else {
        await repo.setVehicleAcceptingBookings(id, newAccepting);
      }

      ref.invalidate(realtimeRentalsProvider);
      ref.invalidate(realtimePropertiesProvider);

      setState(() {
        widget.item['acceptingBookings'] = newAccepting;
        widget.item['status'] = newAccepting ? 'Available' : 'Not Accepting Bookings';
        _isProcessing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newAccepting
                  ? 'Bookings resumed! Listing is now accepting bookings in the marketplace.'
                  : 'Bookings paused! Listing will not accept new bookings.',
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Failed to update availability: $e';
      });
    }
  }

  void _handleDeletePress(ScrollController scrollController) {
    final hasPending = _requests.any((req) => req['status']?.toString().toLowerCase() == 'pending');
    final hasConfirmed = _requests.any((req) {
      final st = (req['status'] ?? '').toString().toLowerCase();
      return st == 'approved' || st == 'active' || st == 'ongoing' || st == 'confirmed' || st == 'awaiting_signature' || st == 'booked';
    });

    if (hasPending) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber),
              SizedBox(width: 8),
              Expanded(
                child: Text('Pending Requests Need Resolution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: const Text(
            'You have pending booking requests for this listing. Please accept or reject all pending requests before deleting this listing.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[700],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                scrollController.animateTo(
                  scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                );
              },
              child: const Text('View Pending Requests', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else if (hasConfirmed) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text('Confirm Listing Deletion', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: const Text(
            'This listing has existing bookings. Deleting the listing will prevent new bookings, but your existing bookings will remain active and accessible. Are you sure you want to delete this listing?',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _deleteListing(hasConfirmed: true);
              },
              child: const Text('Delete Listing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Listing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: const Text(
            'Are you sure you want to delete this listing? This will permanently remove the listing from active listings.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _deleteListing(hasConfirmed: false);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  void _deleteListing({bool hasConfirmed = false}) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      final repo = ref.read(transitRepositoryProvider);
      final id = widget.item['id'] as String;
      if (widget.isProperty) {
        await repo.deletePropertyRental(id);
      } else {
        await repo.deleteRental(id);
      }

      ref.invalidate(realtimeRentalsProvider);
      ref.invalidate(realtimePropertiesProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasConfirmed
                  ? 'Listing deleted. Existing bookings remain active and accessible.'
                  : 'Listing deleted and listing fee refunded to your wallet!',
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Error deleting listing: $e';
      });
    }
  }

  void _completeLease() async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      final repo = ref.read(transitRepositoryProvider);
      final id = widget.item['id'] as String;
      if (widget.isProperty) {
        await repo.completePropertyRental(id);
      } else {
        await repo.completeRental(id);
      }

      ref.invalidate(realtimeRentalsProvider);
      ref.invalidate(realtimePropertiesProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lease completed! Escrow funds paid out to your wallet.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Error completing lease: $e';
      });
    }
  }

  void _saveGps() async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      final repo = ref.read(transitRepositoryProvider);
      final id = widget.item['id'] as String;
      await repo.updateVehicleGpsTracker(id, _gpsController.text.trim());

      ref.invalidate(realtimeRentalsProvider);
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _isEditingGps = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS Tracker ID saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Error saving GPS Tracker: $e';
      });
    }
  }

  String _formatDate(int? ms) {
    if (ms == null || ms == 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateFormat('MMM dd, yyyy • hh:mm a').format(dt);
  }

  String _formatDateShort(int? ms) {
    if (ms == null || ms == 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateFormat('MMM dd, yyyy').format(dt);
  }

  Widget _buildStatusBadge(String status, bool isDarkMode) {
    final s = status.toLowerCase();
    Color textColor = Colors.amber.shade700;
    Color bgColor = Colors.amber.withValues(alpha: 0.15);
    String label = status;

    if (s == 'pending') {
      textColor = Colors.amber.shade800;
      bgColor = Colors.amber.withValues(alpha: 0.15);
      label = 'Pending Review';
    } else if (s == 'approved' || s == 'awaiting signature') {
      textColor = Colors.blue;
      bgColor = Colors.blue.withValues(alpha: 0.15);
      label = 'Approved';
    } else if (s == 'booked' || s == 'active' || s == 'ongoing' || s == 'on the way to rentee' || s == 'returning') {
      textColor = Colors.green;
      bgColor = Colors.green.withValues(alpha: 0.15);
      label = 'Confirmed';
    } else if (s == 'completed') {
      textColor = Colors.teal;
      bgColor = Colors.teal.withValues(alpha: 0.15);
      label = 'Completed';
    } else if (s == 'rejected' || s == 'cancelled') {
      textColor = Colors.red;
      bgColor = Colors.red.withValues(alpha: 0.15);
      label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final status = widget.item['status'] as String? ?? 'Available';
    final isNotAccepting = status == 'Not Accepting Bookings' || widget.item['acceptingBookings'] == false;
    final isAvailable = status == 'Available';

    final brand = widget.item['brand'] as String? ?? '';
    final model = widget.item['model'] as String? ?? '';
    final title = widget.item['title'] as String? ?? '$brand $model';
    final subInfo =
        widget.item['plateNumber'] as String? ??
        widget.item['address'] as String? ??
        '';

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
                            'Manage Listing',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$title • $subInfo',
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

                    if (isNotAccepting) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.pause_circle_outline, color: Colors.amber, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'This listing is paused and not accepting new bookings in the marketplace.',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Current Status Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? AppColors.darkCard
                            : AppColors.lightCard,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isDarkMode
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CURRENT STATUS',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isNotAccepting ? 'NOT ACCEPTING BOOKINGS' : status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isNotAccepting ? Colors.amber : AppColors.indigo,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'PRICING',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.isProperty
                                    ? '₱ ${(widget.item["priceMonthly"] as num?)?.toStringAsFixed(0) ?? "0"}/mo'
                                    : '₱ ${(widget.item["priceDaily"] as num?)?.toStringAsFixed(0) ?? "0"}/day',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // GPS Hardware Section (for vehicle only)
                    if (!widget.isProperty) ...[
                      const Text(
                        'GPS HARDWARE TRACKER',
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
                        child: _isEditingGps
                            ? Column(
                                children: [
                                  UIHelpers.buildTextField(
                                    Icons.gps_fixed,
                                    "Enter GPS Tracker Device ID",
                                    isDarkMode,
                                    controller: _gpsController,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: () => setState(
                                          () => _isEditingGps = false,
                                        ),
                                        child: const Text('Cancel'),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: _saveGps,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.indigo,
                                        ),
                                        child: const Text('Save ID'),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _gpsController.text.trim().isNotEmpty
                                              ? 'Serial ID: ${_gpsController.text.trim()}'
                                              : 'No Hardware GPS Tracker registered.',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                _gpsController.text
                                                    .trim()
                                                    .isNotEmpty
                                                ? Colors.green
                                                : Colors.orange,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'GPS tracking ensures live updates in case of theft.',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      color: AppColors.indigo,
                                    ),
                                    onPressed: () =>
                                        setState(() => _isEditingGps = true),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Listing Controls (Edit, Pause/Resume, Delete)
                    Row(
                      children: [
                        if (_requests.isEmpty && (isAvailable || isNotAccepting) && (widget.isProperty || !_hasReservationRecords)) ...[
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isProcessing
                                  ? null
                                  : () {
                                      Navigator.pop(context);
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (context) =>
                                            ListingWizardSheet(
                                          isProperty: widget.isProperty,
                                          initialItem: widget.item,
                                        ),
                                      );
                                    },
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: Colors.white,
                                size: 16,
                              ),
                              label: const Text(
                                'Edit',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.indigo,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: isNotAccepting
                              ? ElevatedButton.icon(
                                  onPressed: _isProcessing ? null : () => _toggleAcceptingBookings(false),
                                  icon: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
                                  label: const Text(
                                    'Resume',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                )
                              : ElevatedButton.icon(
                                  onPressed: _isProcessing ? null : () => _toggleAcceptingBookings(true),
                                  icon: const Icon(Icons.pause, color: Colors.white, size: 16),
                                  label: const Text(
                                    'Stop Bookings',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amber[800],
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isProcessing ? null : () => _handleDeletePress(scrollController),
                            icon: const Icon(Icons.delete, color: Colors.red, size: 16),
                            label: const Text(
                              'Delete',
                              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    if (!isAvailable && !isNotAccepting && widget.item['renteeId'] != null && (widget.item['renteeId'] as String).isNotEmpty) ...[
                      // Trip is ongoing / booked
                      const Text(
                        'ACTIVE TENANT / RENTEE INFO',
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
                          color: isDarkMode ? AppColors.darkCard : Colors.white,
                          border: Border.all(
                            color: isDarkMode
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                 UserAvatar(
                                   name: widget.item['renteeName'] as String?,
                                   photoUrl: widget.item['renteePhotoUrl'] as String?,
                                   radius: 20,
                                   backgroundColor: AppColors.purple.withValues(
                                     alpha: 0.1,
                                   ),
                                   textStyle: const TextStyle(
                                     color: AppColors.purple,
                                     fontWeight: FontWeight.bold,
                                   ),
                                 ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.item['renteeName'] as String? ??
                                            'Renter',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Government ID / License: ${widget.item["renteeLicenseNumber"] ?? widget.item["licenseNumber"] ?? "Verified"}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total Escrow Locked:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  '₱ ${(widget.item["totalCost"] as num?)?.toStringAsFixed(0) ?? "0"}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Start Date:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  _formatDate(widget.item['startDate'] as int?),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'End Date:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  _formatDate(widget.item['endDate'] as int?),
                                ),
                              ],
                            ),
                            if (widget.item['signatureHash'] != null &&
                                (widget.item['signatureHash'] as String)
                                    .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.green.withValues(alpha: 0.15),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '✓ CRYPTOGRAPHIC SHA-256 SIGNATURE',
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.item['signatureHash'] as String,
                                      style: const TextStyle(
                                        fontSize: 8,
                                        fontFamily: 'monospace',
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Actions to complete lease
                      if (status == 'Booked' ||
                          status == 'Active' ||
                          status == 'Ongoing') ...[
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isProcessing
                                    ? null
                                    : _completeLease,
                                icon: const Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'Complete Lease & Payout Earnings',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else if (status == 'Awaiting Signature') ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.hourglass_empty, color: Colors.amber),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Awaiting renter signature on lease contract. Payout cannot be released yet.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.amber,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],

                    const SizedBox(height: 24),

                    // BOOKING APPLICATIONS & SCHEDULES (Always visible to host)
                    const Text(
                      'BOOKING APPLICATIONS & SCHEDULES',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (_isLoadingRequests)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_requests.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDarkMode
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 40,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'No booking applications or reservations yet.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _requests.length,
                        itemBuilder: (context, idx) {
                          final req = _requests[idx];
                          final renteeName =
                              req['renteeName'] as String? ?? 'Renter';
                          final totalCost =
                              (req['totalCost'] as num?)?.toDouble() ?? 0.0;
                          final multiplier = req['multiplier'] ?? 1;
                          final durationType = req['durationType'] ?? 'daily';
                          final reqId = req['id'] as String;
                          final reqStatus = req['status'] as String? ?? 'Pending';
                          final isPending = reqStatus.toLowerCase() == 'pending';
                          final startMs = req['startDate'] as int?;
                          final endMs = req['endDate'] as int?;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? AppColors.darkCard
                                  : Colors.white,
                              border: Border.all(
                                color: isDarkMode
                                    ? AppColors.darkBorder
                                    : AppColors.lightBorder,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              renteeName,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _buildStatusBadge(reqStatus, isDarkMode),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '₱ ${totalCost.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.indigo,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                if (startMs != null && endMs != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Schedule: ${_formatDateShort(startMs)} - ${_formatDateShort(endMs)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.indigo,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  'Duration: $multiplier $durationType(s)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (isPending) ...[
                                  const SizedBox(height: 12),
                                  CheckboxListTile(
                                    title: const Text(
                                      'Allow direct chat session with rentee',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    value: _allowChat,
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    onChanged: (val) => setState(
                                      () => _allowChat = val ?? false,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _isProcessing
                                              ? null
                                              : () => _approveRequest(reqId),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                          ),
                                          child: const Text('Approve'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        onPressed: _isProcessing
                                            ? null
                                            : () => _rejectRequest(reqId),
                                        child: const Text('Reject'),
                                      ),
                                    ],
                                  ),
                                ] else if (widget.isProperty) ...[
                                  if (['booked', 'active', 'ongoing', 'returning'].contains(status)) ...[
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isProcessing
                                            ? null
                                            : () => _updateBookingStatus(reqId, 'Completed'),
                                        icon: const Icon(
                                          Icons.check_circle,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          'Complete Lease & Payout Earnings',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                        ),
                                      ),
                                    ),
                                  ],
                                ] else ...[
                                  if (status == 'booked') ...[
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isProcessing
                                            ? null
                                            : () => _updateBookingStatus(reqId, 'Ongoing'),
                                        icon: const Icon(
                                          Icons.vpn_key,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          'Hand Over & Start Rental',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.indigo,
                                        ),
                                      ),
                                    ),
                                  ] else if (status == 'on the way to rentee') ...[
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isProcessing
                                            ? null
                                            : () => _updateBookingStatus(reqId, 'Ongoing'),
                                        icon: const Icon(
                                          Icons.vpn_key,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          'Hand Over & Start Rental',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.indigo,
                                        ),
                                      ),
                                    ),
                                  ] else if (status == 'ongoing') ...[
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isProcessing
                                            ? null
                                            : () => _updateBookingStatus(reqId, 'Returning'),
                                        icon: const Icon(
                                          Icons.sync,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          'Mark as Returning',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.purple,
                                        ),
                                      ),
                                    ),
                                  ] else if (status == 'returning') ...[
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _isProcessing
                                            ? null
                                            : () => _updateBookingStatus(reqId, 'Completed'),
                                        icon: const Icon(
                                          Icons.check_circle,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          'Confirm Returned & Complete',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          );
                        },
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
