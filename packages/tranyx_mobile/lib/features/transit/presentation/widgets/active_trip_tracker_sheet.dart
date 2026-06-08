import 'dart:async';
import 'dart:math' show Random;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'package:tranyx_mobile/features/transit/presentation/widgets/signature_pad_dialog.dart';

class ActiveTripTrackerSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  final bool isProperty;

  const ActiveTripTrackerSheet({
    super.key,
    required this.item,
    required this.isProperty,
  });

  @override
  ConsumerState<ActiveTripTrackerSheet> createState() =>
      _ActiveTripTrackerSheetState();
}

class _ActiveTripTrackerSheetState
    extends ConsumerState<ActiveTripTrackerSheet> {
  Timer? _gpsTimer;
  double _trackingLat = 14.5995;
  double _trackingLng = 120.9842;
  double _speed = 0.0;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _trackingLat = (widget.item['trackingLat'] as num?)?.toDouble() ?? 14.5995;
    _trackingLng = (widget.item['trackingLng'] as num?)?.toDouble() ?? 120.9842;
    if (widget.item['status'] == 'Active' ||
        widget.item['status'] == 'Ongoing') {
      _startGpsSimulation();
    }
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    super.dispose();
  }

  void _startGpsSimulation() {
    _gpsTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (widget.isProperty) return;
      final rand = Random();
      setState(() {
        // Move coordinates slightly (approx 10-100m)
        _trackingLat += (rand.nextDouble() - 0.5) * 0.001;
        _trackingLng += (rand.nextDouble() - 0.5) * 0.001;
        _speed = 30.0 + rand.nextDouble() * 40.0; // 30-70 km/h
      });

      // Update Firestore in background
      final id = widget.item['id'] as String;
      ref
          .read(transitRepositoryProvider)
          .updateRentalTracking(id, _trackingLat, _trackingLng);
    });
  }

  void _openSignaturePad(String id, String terms) {
    showDialog(
      context: context,
      builder: (context) => SignaturePadDialog(
        title: 'Sign Agreement',
        terms: terms,
        onSigned: (name, hash) async {
          setState(() => _isProcessing = true);
          try {
            final repo = ref.read(transitRepositoryProvider);
            if (widget.isProperty) {
              await repo.signPropertyContract(id, name, signatureHash: hash);
            } else {
              await repo.signVehicleContract(id, name, signatureHash: hash);
            }

            ref.invalidate(realtimeRentalsProvider);
            ref.invalidate(realtimePropertiesProvider);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Contract signed! Status updated to Booked.'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Failed to sign: $e')));
            }
          } finally {
            setState(() => _isProcessing = false);
          }
        },
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildStep(
    int stepNum,
    String title,
    String subtitle,
    bool isCompleted,
    bool isActive,
  ) {
    final isDarkMode = ref.read(themeModeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isCompleted
                  ? Colors.green
                  : isActive
                  ? AppColors.indigo
                  : Colors.grey[600],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : Text(
                      '$stepNum',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isActive || isCompleted
                        ? (isDarkMode ? Colors.white : Colors.black)
                        : Colors.grey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openChatDialog() {
    final user = ref.read(userProvider);
    if (user == null) return;
    final userProfile = ref.watch(userProfileProvider).value;
    final isRenter = widget.item['renteeId'] == user.uid;
    final counterpartyName = isRenter
        ? widget.item['hostName'] ?? 'Host'
        : widget.item['renteeName'] ?? 'Renter';
    final rentalId = widget.item['id'] as String;
    final prefix = widget.isProperty ? 'property' : 'rental';
    final renterId = isRenter ? user.uid : widget.item['renteeId'] as String;
    final chatId = '${prefix}_${rentalId}_$renterId';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final controller = TextEditingController();
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chat with $counterpartyName',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Public listing queries are done in Q&A. This is a private chat for booking coordination.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot>(
                  stream: ref
                      .read(firestoreProvider)
                      .collection('chats')
                      .doc(chatId)
                      .collection('messages')
                      .orderBy('createdAt', descending: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final msgs = snapshot.data?.docs ?? [];
                    return Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: msgs.isEmpty
                          ? const Center(
                              child: Text(
                                'No messages yet',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: msgs.length,
                              itemBuilder: (context, idx) {
                                final m =
                                    msgs[idx].data() as Map<String, dynamic>;
                                final sender = m['senderId'] == user.uid;
                                return Align(
                                  alignment: sender
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.all(8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: sender
                                          ? AppColors.indigo
                                          : Colors.grey[700],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      m['content'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          hintText: 'Type coordination message...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send, color: AppColors.indigo),
                      onPressed: () async {
                        final val = controller.text.trim();
                        if (val.isEmpty) return;

                        await ref
                            .read(firestoreProvider)
                            .collection('chats')
                            .doc(chatId)
                            .collection('messages')
                            .add({
                              'senderId': user.uid,
                              'senderName': userProfile?.name ?? 'User',
                              'content': val,
                              'createdAt':
                                  DateTime.now().millisecondsSinceEpoch,
                            });

                        // Set chat status metadata
                        await ref
                            .read(firestoreProvider)
                            .collection('chats')
                            .doc(chatId)
                            .set({
                              'id': chatId,
                              'lastMessage': val,
                              'updatedAt':
                                  DateTime.now().millisecondsSinceEpoch,
                              'userIds': [
                                user.uid,
                                isRenter
                                    ? widget.item['hostId']
                                    : widget.item['renteeId'],
                              ],
                            }, SetOptions(merge: true));

                        controller.clear();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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
    final status = widget.item['status'] as String? ?? 'Awaiting Signature';
    final hostId = widget.item['hostId'] as String? ?? '';
    final isHost = hostId == userProfile.uid;

    final signature = widget.item['renteeSignatureName'] as String? ?? '';
    final signatureHash = widget.item['signatureHash'] as String? ?? '';
    final terms =
        widget.item['contractTerms'] as String? ??
        'Rental terms & conditions...';

    // Step calculations
    final s1_completed = true;
    final s1_active = true;

    final s2_completed =
        signature.isNotEmpty ||
        status == 'Booked' ||
        status == 'Active' ||
        status == 'Ongoing' ||
        status == 'Completed';
    final s2_active = status == 'Awaiting Signature';

    final s3_completed =
        status == 'Active' || status == 'Ongoing' || status == 'Completed';
    final s3_active = status == 'Booked';

    final s4_completed = status == 'Completed';
    final s4_active = status == 'Active' || status == 'Ongoing';

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
                            'Trip Tracker & Escrow',
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
                    // Status Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Lease Status:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        _pill(
                          status,
                          status == 'Active' || status == 'Ongoing'
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Steps List
                    _buildStep(
                      1,
                      'Booking Escrow Deposited',
                      'Renter balance has been locked in escrow.',
                      s1_completed,
                      s1_active,
                    ),
                    _buildStep(
                      2,
                      'Lease Agreement Signed',
                      signature.isNotEmpty
                          ? 'Signed: $signature'
                          : 'Awaiting renter electronic signature.',
                      s2_completed,
                      s2_active,
                    ),
                    _buildStep(
                      3,
                      'Handover Executed',
                      status == 'Active' || status == 'Ongoing'
                          ? 'Asset handed over to renter.'
                          : 'Awaiting keys handover.',
                      s3_completed,
                      s3_active,
                    ),
                    _buildStep(
                      4,
                      'Trip Ongoing & Tracked',
                      status == 'Completed'
                          ? 'Trip has ended.'
                          : 'Active lease period.',
                      s4_completed,
                      s4_active,
                    ),

                    // Renter Signature Action
                    if (!isHost && status == 'Awaiting Signature') ...[
                      const SizedBox(height: 16),
                      _isProcessing
                          ? const Center(child: CircularProgressIndicator())
                          : UIHelpers.buildPrimaryButton(
                              'Sign Contract Agreement',
                              () => _openSignaturePad(id, terms),
                              isDarkMode,
                            ),
                    ],

                    // Signed details details
                    if (signatureHash.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.05),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.15),
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '✓ SIGNATURE CERTIFICATE (SHA-256)',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              signatureHash,
                              style: const TextStyle(
                                fontSize: 9,
                                fontFamily: 'monospace',
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // GPS Simulator Block
                    if (!widget.isProperty &&
                        (status == 'Active' || status == 'Ongoing')) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'LIVE GPS TRACKER (SIMULATED)',
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
                          color: isDarkMode
                              ? AppColors.darkCard
                              : AppColors.lightCard,
                          borderRadius: BorderRadius.circular(20),
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
                                Text(
                                  'Coords: ${_trackingLat.toStringAsFixed(5)}, ${_trackingLng.toStringAsFixed(5)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Status: Online & Tracking',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${_speed.toStringAsFixed(0)} km/h',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.indigo,
                                  ),
                                ),
                                const Text(
                                  'Velocity',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),

                    // Chat Counterpart Button
                    if (widget.item['allowChat'] == true) ...[
                      UIHelpers.buildPrimaryButton(
                        'Open Chat Coordinator',
                        _openChatDialog,
                        isDarkMode,
                        isOutlined: true,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Host Actions
                    if (isHost) ...[
                      if (status == 'Booked') ...[
                        _isProcessing
                            ? const Center(child: CircularProgressIndicator())
                            : UIHelpers.buildPrimaryButton(
                                'Handover Keys to Renter',
                                () async {
                                  setState(() => _isProcessing = true);
                                  try {
                                    final repo = ref.read(
                                      transitRepositoryProvider,
                                    );
                                    if (widget.isProperty) {
                                      await repo.updatePropertyStatus(
                                        id,
                                        'Active',
                                      );
                                    } else {
                                      await repo.updateRentalStatus(
                                        id,
                                        'Active',
                                      );
                                    }
                                    ref.invalidate(realtimeRentalsProvider);
                                    ref.invalidate(realtimePropertiesProvider);
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Status updated to Active! Renter has possession.',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text('Error: $e')),
                                      );
                                    }
                                  } finally {
                                    setState(() => _isProcessing = false);
                                  }
                                },
                                isDarkMode,
                              ),
                      ] else if (status == 'Active' || status == 'Ongoing') ...[
                        _isProcessing
                            ? const Center(child: CircularProgressIndicator())
                            : UIHelpers.buildPrimaryButton(
                                'Complete Trip & Payout P2P Escrow',
                                () async {
                                  setState(() => _isProcessing = true);
                                  try {
                                    final repo = ref.read(
                                      transitRepositoryProvider,
                                    );
                                    if (widget.isProperty) {
                                      await repo.completePropertyRental(id);
                                    } else {
                                      await repo.completeRental(id);
                                    }
                                    ref.invalidate(realtimeRentalsProvider);
                                    ref.invalidate(realtimePropertiesProvider);
                                    if (mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Lease Completed! Escrow released to your balance.',
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
                                        SnackBar(content: Text('Error: $e')),
                                      );
                                    }
                                  } finally {
                                    setState(() => _isProcessing = false);
                                  }
                                },
                                isDarkMode,
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
