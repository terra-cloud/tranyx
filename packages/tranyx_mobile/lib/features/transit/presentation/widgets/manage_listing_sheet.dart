import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'package:intl/intl.dart';
import 'package:tranyx_mobile/core/widgets/user_avatar.dart';

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
        final list = await repo.getPropertyPendingRequestsForProperty(id);
        setState(() {
          _requests = list;
          _isLoadingRequests = false;
        });
      } else {
        final list = await repo.getPendingRequestsForVehicle(id);
        setState(() {
          _requests = list;
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

  void _deleteListing() async {
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
          const SnackBar(content: Text('Listing deleted successfully!')),
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

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final status = widget.item['status'] as String? ?? 'Available';
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
                                status.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.indigo,
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

                    // If listing is Available, show delete button and booking requests
                    if (isAvailable) ...[
                      const Text(
                        'BOOKING APPLICATIONS',
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
                                'No pending booking applications yet.',
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
                                req['renteeName'] as String? ?? 'Rentees';
                            final totalCost =
                                (req['totalCost'] as num?)?.toDouble() ?? 0.0;
                            final multiplier = req['multiplier'] ?? 1;
                            final durationType = req['durationType'] ?? 'daily';
                            final reqId = req['id'] as String;

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
                                      Text(
                                        renteeName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
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
                                  const SizedBox(height: 4),
                                  Text(
                                    'Duration: $multiplier $durationType(s)',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
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
                                ],
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 24),

                      // Delete listing button
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isProcessing ? null : _deleteListing,
                              icon: const Icon(Icons.delete, color: Colors.red),
                              label: const Text(
                                'Delete Listing',
                                style: TextStyle(color: Colors.red),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.red),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
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
