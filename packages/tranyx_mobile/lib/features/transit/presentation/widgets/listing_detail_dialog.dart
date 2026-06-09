import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/core/utils/geo_helper.dart';

class ListingDetailDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  final bool isProperty;
  final VoidCallback onBookTap;

  const ListingDetailDialog({
    super.key,
    required this.item,
    required this.isProperty,
    required this.onBookTap,
  });

  @override
  ConsumerState<ListingDetailDialog> createState() =>
      _ListingDetailDialogState();
}

class _ListingDetailDialogState extends ConsumerState<ListingDetailDialog> {
  final _questionController = TextEditingController();
  final _answerControllers = <String, TextEditingController>{};
  final _answeringQuestionId = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _questionController.dispose();
    _answeringQuestionId.dispose();
    for (final controller in _answerControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _askQuestion(String uid, String name, String photoUrl) async {
    final text = _questionController.text.trim();
    if (text.isEmpty) return;

    try {
      final id = widget.item['id'] as String;
      final collection = widget.isProperty ? 'properties' : 'rentals';

      await ref
          .read(firestoreProvider)
          .collection(collection)
          .doc(id)
          .collection('questions')
          .add({
            'uid': uid,
            'name': name,
            'photoUrl': photoUrl,
            'text': text,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });

      _questionController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Question posted publicly!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error posting question: $e')));
      }
    }
  }

  void _answerQuestion(String qId) async {
    final text = _answerControllers[qId]?.text.trim() ?? '';
    if (text.isEmpty) return;

    try {
      final id = widget.item['id'] as String;
      final collection = widget.isProperty ? 'properties' : 'rentals';

      await ref
          .read(firestoreProvider)
          .collection(collection)
          .doc(id)
          .collection('questions')
          .doc(qId)
          .update({'answer': text});

      _answerControllers[qId]?.clear();
      _answeringQuestionId.value = null;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Answer posted!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final userProfile = ref.watch(userProfileProvider).value;
    final userLat =
        ref.watch(userProfileProvider).whenData((p) => 14.5995).value ??
        14.5995;
    final userLng =
        ref.watch(userProfileProvider).whenData((p) => 120.9842).value ??
        120.9842;

    final id = widget.item['id'] as String? ?? '';
    final brand = widget.item['brand'] as String? ?? '';
    final model = widget.item['model'] as String? ?? '';
    final title = widget.item['title'] as String? ?? '$brand $model';
    final desc = widget.item['description'] as String? ?? '';
    final hostId = widget.item['hostId'] as String? ?? '';
    final hostName = widget.item['hostName'] as String? ?? 'Host';
    final status = widget.item['status'] as String? ?? 'Available';

    final double lat =
        (widget.item[widget.isProperty ? 'latitude' : 'pickupLat'] as num?)
            ?.toDouble() ??
        0.0;
    final double lng =
        (widget.item[widget.isProperty ? 'longitude' : 'pickupLng'] as num?)
            ?.toDouble() ??
        0.0;
    final address =
        widget.item[widget.isProperty ? 'address' : 'pickupAddress']
            as String? ??
        '';
    final distance = calculateDistance(userLat, userLng, lat, lng);

    final photoUrl = widget.isProperty
        ? ((widget.item['photoUrls'] as List?)?.firstOrNull?.toString())
        : (widget.item['frontPhotoUrl'] ??
              widget.item['photoUrl'] ??
              widget.item['frontPhoto']?.toString());
    final hasPhoto =
        photoUrl != null && photoUrl.isNotEmpty && photoUrl != 'null';

    final isHost = hostId == userProfile?.uid;
    final questionsStream = ref
        .read(firestoreProvider)
        .collection(widget.isProperty ? 'properties' : 'rentals')
        .doc(id)
        .collection('questions')
        .orderBy('createdAt', descending: false)
        .snapshots();

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
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
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _pill(
                                status,
                                status == 'Available'
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.location_on,
                                size: 12,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${distance.toStringAsFixed(1)} km away',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
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
                    // Photo
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        height: 200,
                        width: double.infinity,
                        color: isDarkMode
                            ? AppColors.darkBorder
                            : AppColors.lightBg,
                        child: hasPhoto
                            ? Image.network(photoUrl, fit: BoxFit.cover)
                            : Icon(
                                widget.isProperty
                                    ? Icons.home
                                    : Icons.directions_car,
                                size: 64,
                                color: Colors.grey,
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Price info
                    const Text(
                      'PRICING RATES',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (widget.isProperty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Monthly Rate',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            '₱ ${(widget.item['priceMonthly'] as num?)?.toStringAsFixed(0) ?? "0"}/mo',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.indigo,
                            ),
                          ),
                        ],
                      ),
                      if ((widget.item['priceWeekly'] as num? ?? 0) > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Weekly Rate',
                              style: TextStyle(fontSize: 14),
                            ),
                            Text(
                              '₱ ${(widget.item['priceWeekly'] as num?)?.toStringAsFixed(0) ?? "0"}/wk',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if ((widget.item['priceDaily'] as num? ?? 0) > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Daily Rate',
                              style: TextStyle(fontSize: 14),
                            ),
                            Text(
                              '₱ ${(widget.item['priceDaily'] as num?)?.toStringAsFixed(0) ?? "0"}/day',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Daily Rate',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            '₱ ${(widget.item['priceDaily'] as num?)?.toStringAsFixed(0) ?? "0"}/day',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
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
                            '12-Hour Rate',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            '₱ ${(widget.item['price12h'] as num?)?.toStringAsFixed(0) ?? "0"}/12h',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Weekly Rate',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            '₱ ${(widget.item['priceWeekly'] as num?)?.toStringAsFixed(0) ?? "0"}/wk',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Specs or Amenities
                    Text(
                      widget.isProperty ? 'AMENITIES' : 'SPECIFICATIONS',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (widget.isProperty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final am
                              in (widget.item['amenities'] as List? ?? []))
                            _pill(am.toString(), Colors.blueGrey),
                        ],
                      ),
                    ] else ...[
                      Row(
                        children: [
                          _pill(
                            widget.item['fuelType']?.toString() ?? 'Gasoline',
                            Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          _pill(
                            widget.item['transmission']?.toString() ??
                                'Automatic',
                            Colors.blue,
                          ),
                          if (widget.item['offersDriver'] == true) ...[
                            const SizedBox(width: 8),
                            _pill('Driver Included Option', Colors.green),
                          ],
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Description
                    const Text(
                      'DESCRIPTION',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      desc.isEmpty ? 'No description provided.' : desc,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Location address
                    const Text(
                      'LOCATION ADDRESS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.pin_drop,
                          size: 16,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            address,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDarkMode
                                  ? AppColors.darkTextMuted
                                  : AppColors.lightTextMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Host info
                    const Text(
                      'LISTED BY HOST',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundImage:
                              (widget.item['hostPhotoUrl'] != null &&
                                  (widget.item['hostPhotoUrl'] as String)
                                      .isNotEmpty)
                              ? NetworkImage(
                                      widget.item['hostPhotoUrl'] as String,
                                    )
                                    as ImageProvider
                              : const AssetImage(
                                      'assets/images/default-avatar.jpg',
                                    )
                                    as ImageProvider,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hostName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Verified Tranyx Peer',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Public Q&A Section
                    const Text(
                      'PUBLIC Q&A',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),

                    StreamBuilder<QuerySnapshot>(
                      stream: questionsStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'No public questions yet. Be the first to ask!',
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: isDarkMode
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted,
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: docs.map((doc) {
                            final qId = doc.id;
                            final qData = doc.data() as Map<String, dynamic>;
                            final qName = qData['name'] as String? ?? 'User';
                            final qPhoto = qData['photoUrl'] as String? ?? '';
                            final qText = qData['text'] as String? ?? '';
                            final qAnswer = qData['answer'] as String? ?? '';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? Colors.black12
                                    : Colors.grey[50],
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
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 12,
                                        backgroundImage: qPhoto.isNotEmpty
                                            ? NetworkImage(qPhoto)
                                                  as ImageProvider
                                            : const AssetImage(
                                                    'assets/images/default-avatar.jpg',
                                                  )
                                                  as ImageProvider,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        qName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    qText,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  if (qAnswer.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppColors.indigo.withValues(
                                          alpha: 0.05,
                                        ),
                                        border: Border.all(
                                          color: AppColors.indigo.withValues(
                                            alpha: 0.1,
                                          ),
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            '★ HOST RESPONSE',
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.indigo,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            qAnswer,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ] else if (isHost) ...[
                                    const SizedBox(height: 12),
                                    ValueListenableBuilder<String?>(
                                      valueListenable: _answeringQuestionId,
                                      builder: (context, answeringId, _) {
                                        if (answeringId == qId) {
                                          if (!_answerControllers.containsKey(
                                            qId,
                                          )) {
                                            _answerControllers[qId] =
                                                TextEditingController();
                                          }
                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              TextField(
                                                controller:
                                                    _answerControllers[qId],
                                                decoration:
                                                    const InputDecoration(
                                                      hintText:
                                                          'Type answer...',
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        _answeringQuestionId
                                                                .value =
                                                            null,
                                                    child: const Text('Cancel'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () =>
                                                        _answerQuestion(qId),
                                                    child: const Text(
                                                      'Post Answer',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          );
                                        }

                                        return TextButton.icon(
                                          icon: const Icon(
                                            Icons.reply,
                                            size: 14,
                                          ),
                                          label: const Text(
                                            'Reply to question',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                          onPressed: () =>
                                              _answeringQuestionId.value = qId,
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),

                    if (!isHost && userProfile != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _questionController,
                              decoration: const InputDecoration(
                                hintText: 'Ask a question...',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _askQuestion(
                              userProfile.uid,
                              userProfile.name,
                              userProfile.photoUrl ?? '',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Ask'),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 48),
                  ],
                ),
              ),

              // Bottom Book Button Panel
              if (!isHost && status == 'Available')
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border(
                      top: BorderSide(
                        color: isDarkMode
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                  ),
                  child: UIHelpers.buildPrimaryButton(
                    widget.isProperty
                        ? 'Rent Property Now'
                        : 'Book Vehicle Now',
                    () {
                      Navigator.pop(context);
                      widget.onBookTap();
                    },
                    isDarkMode,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
