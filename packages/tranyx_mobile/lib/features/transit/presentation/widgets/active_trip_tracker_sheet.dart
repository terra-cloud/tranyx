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
import 'package:shared/shared.dart';

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
  int _extendHours = 1;

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

                        if (MessageViolationTracker.isMessagingLocked(user.uid)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Messaging locked: An Admin ticket has been opened for account review due to repeated violations.'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }

                        final policyResult = MessagePolicyFilter.check(val);
                        if (policyResult != MessagePolicyResult.ok) {
                          final isNowLocked = MessageViolationTracker.recordViolation(user.uid);
                          final userName = userProfile?.name ?? 'User';

                          if (isNowLocked) {
                            final ticketSubject = MessageViolationTracker.formatBanSubject(userName);
                            final ticketId = 'ticket_ban_${DateTime.now().millisecondsSinceEpoch}_${user.uid.substring(0, 5)}';

                            await ref.read(firestoreProvider).collection('tickets').doc(ticketId).set({
                              'id': ticketId,
                              'subject': ticketSubject,
                              'title': ticketSubject,
                              'userId': user.uid,
                              'userName': userName,
                              'chatId': chatId,
                              'reason': 'Repeated attempt to share contact numbers, emails, or off-platform payment methods in chat.',
                              'lastOffendingMessage': val,
                              'violationType': policyResult.name,
                              'status': 'flagged_for_ban',
                              'priority': 'urgent',
                              'createdAt': DateTime.now().millisecondsSinceEpoch,
                              'updatedAt': DateTime.now().millisecondsSinceEpoch,
                            });

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Messaging Locked: $ticketSubject. An admin ticket has been opened for account review.'),
                                backgroundColor: Colors.redAccent,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                            return;
                          }

                          if (policyResult == MessagePolicyResult.piiBlocked) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Message blocked: Sharing phone numbers, emails, or links is not allowed.'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Message blocked: Off-platform payment requests (GCash, Maya, etc.) violate Tranyx terms.'),
                                backgroundColor: Colors.orangeAccent,
                              ),
                            );
                          }
                          return;
                        }

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
    final s1Completed = true;
    final s1Active = true;

    final s2Completed =
        signature.isNotEmpty ||
        status == 'Booked' ||
        status == 'Active' ||
        status == 'Ongoing' ||
        status == 'Completed';
    final s2Active = status == 'Awaiting Signature';

    final s3Completed =
        status == 'Active' || status == 'Ongoing' || status == 'Completed';
    final s3Active = status == 'Booked';

    final s4Completed = status == 'Completed';
    final s4Active = status == 'Active' || status == 'Ongoing';

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
                      s1Completed,
                      s1Active,
                    ),
                    _buildStep(
                      2,
                      'Lease Agreement Signed',
                      signature.isNotEmpty
                          ? 'Signed: $signature'
                          : 'Awaiting renter electronic signature.',
                      s2Completed,
                      s2Active,
                    ),
                    _buildStep(
                      3,
                      'Handover Executed',
                      status == 'Active' || status == 'Ongoing'
                          ? 'Asset handed over to renter.'
                          : 'Awaiting keys handover.',
                      s3Completed,
                      s3Active,
                    ),
                    _buildStep(
                      4,
                      'Trip Ongoing & Tracked',
                      status == 'Completed'
                          ? 'Trip has ended.'
                          : 'Active lease period.',
                      s4Completed,
                      s4Active,
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

                    if (!widget.isProperty && (status == 'Active' || status == 'Ongoing')) ...[
                      StreamBuilder<QuerySnapshot>(
                        stream: ref.watch(firestoreProvider)
                            .collection('rental_extensions')
                            .where('rentalId', isEqualTo: id)
                            .where('status', isEqualTo: 'Pending')
                            .snapshots(),
                        builder: (context, snapshot) {
                          final hasPending = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
                          final pendingDocs = hasPending ? snapshot.data!.docs : [];

                          if (!isHost) {
                            if (hasPending) {
                              final extData = pendingDocs.first.data() as Map<String, dynamic>;
                              final hours = extData['extendHours'];
                              final fee = extData['fee'];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 24),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.hourglass_empty, color: Colors.orange, size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          'EXTENSION REQUEST PENDING',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            color: Colors.orange,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'You requested to extend the rental by $hours hours for ₱ ${fee.toStringAsFixed(0)} TYXBIT.',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Awaiting host approval. Funds are currently locked in escrow.',
                                      style: TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              );
                            } else {
                              final extensionRatePerHour = (widget.item['extensionRatePerHour'] as num?)?.toDouble() ?? 200.0;
                              final fee = _extendHours * extensionRatePerHour;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 24),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
                                  border: Border.all(
                                    color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'REQUEST RENTAL EXTENSION',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '₱ ${extensionRatePerHour.toStringAsFixed(0)}/hour',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const Text(
                                              'Extension Rate',
                                              style: TextStyle(fontSize: 10, color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline),
                                              onPressed: _extendHours > 1
                                                  ? () => setState(() => _extendHours--)
                                                  : null,
                                            ),
                                            Text(
                                              '$_extendHours hr${_extendHours > 1 ? "s" : ""}',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.add_circle_outline),
                                              onPressed: () => setState(() => _extendHours++),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 20),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Extension escrow fee:',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        Text(
                                          '₱ ${fee.toStringAsFixed(0)} TYXBIT',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.indigo,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    _isProcessing
                                        ? const Center(child: CircularProgressIndicator())
                                        : SizedBox(
                                            width: double.infinity,
                                            child: UIHelpers.buildPrimaryButton(
                                              'Submit Extension Request',
                                              () async {
                                                setState(() => _isProcessing = true);
                                                try {
                                                  await ref.read(transitRepositoryProvider).createExtensionRequest(
                                                    rentalId: id,
                                                    renteeId: userProfile.uid,
                                                    extendHours: _extendHours,
                                                    fee: fee,
                                                  );
                                                  ref.invalidate(realtimeRentalsProvider);
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(
                                                        content: Text('Extension request submitted!'),
                                                        backgroundColor: Colors.green,
                                                      ),
                                                    );
                                                  }
                                                } catch (e) {
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text('Failed: $e'),
                                                        backgroundColor: Colors.red,
                                                      ),
                                                    );
                                                  }
                                                } finally {
                                                  setState(() => _isProcessing = false);
                                                }
                                              },
                                              isDarkMode,
                                            ),
                                          ),
                                  ],
                                ),
                              );
                            }
                          }

                          if (isHost && hasPending) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'PENDING EXTENSION REQUESTS',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...pendingDocs.map((doc) {
                                  final extData = doc.data() as Map<String, dynamic>;
                                  final extId = doc.id;
                                  final hours = extData['extendHours'];
                                  final fee = extData['fee'];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
                                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Renter requests extension of $hours hours.',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Escrow payout: ₱ ${fee.toStringAsFixed(0)} TYXBIT (will release upon completion).',
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                        const SizedBox(height: 12),
                                        _isProcessing
                                            ? const Center(child: CircularProgressIndicator())
                                            : Row(
                                                children: [
                                                  Expanded(
                                                    child: OutlinedButton(
                                                      style: OutlinedButton.styleFrom(
                                                        side: const BorderSide(color: Colors.red),
                                                        foregroundColor: Colors.red,
                                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                                      ),
                                                      onPressed: () async {
                                                        setState(() => _isProcessing = true);
                                                        try {
                                                          await ref.read(transitRepositoryProvider).rejectExtension(extId);
                                                          ref.invalidate(realtimeRentalsProvider);
                                                          if (mounted) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              const SnackBar(
                                                                content: Text('Extension request rejected.'),
                                                              ),
                                                            );
                                                          }
                                                        } catch (e) {
                                                          if (mounted) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              SnackBar(content: Text('Error: $e')),
                                                            );
                                                          }
                                                        } finally {
                                                          setState(() => _isProcessing = false);
                                                        }
                                                      },
                                                      child: const Text('Reject'),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: ElevatedButton(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: AppColors.indigo,
                                                        foregroundColor: Colors.white,
                                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                                      ),
                                                      onPressed: () async {
                                                        setState(() => _isProcessing = true);
                                                        try {
                                                          await ref.read(transitRepositoryProvider).approveExtension(extId);
                                                          ref.invalidate(realtimeRentalsProvider);
                                                          if (mounted) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              const SnackBar(
                                                                content: Text('Extension request approved!'),
                                                                backgroundColor: Colors.green,
                                                              ),
                                                            );
                                                          }
                                                        } catch (e) {
                                                          if (mounted) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              SnackBar(content: Text('Error: $e')),
                                                            );
                                                          }
                                                        } finally {
                                                          setState(() => _isProcessing = false);
                                                        }
                                                      },
                                                      child: const Text('Approve'),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ],
                                    ),
                                  );
                                }),
                                const SizedBox(height: 16),
                              ],
                            );
                          }

                          return const SizedBox.shrink();
                        },
                      ),
                    ],

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
