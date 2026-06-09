import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:intl/intl.dart';

final userReviewsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, uid) async {
      final firestore = ref.watch(firestoreProvider);
      final snapshot = await firestore
          .collection('users')
          .doc(uid)
          .collection('reviews')
          .orderBy('timestamp', descending: true)
          .get();
      return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
    });

class ReviewsPane extends ConsumerStatefulWidget {
  final VoidCallback onBack;

  const ReviewsPane({super.key, required this.onBack});

  @override
  ConsumerState<ReviewsPane> createState() => _ReviewsPaneState();
}

class _ReviewsPaneState extends ConsumerState<ReviewsPane> {
  String _obfuscateName(String? name) {
    if (name == null || name.trim().isEmpty) return 'Anonymous';
    final parts = name.trim().split(' ');
    return parts
        .map((part) {
          if (part.isEmpty) return '';
          return '${part[0]}***';
        })
        .join(' ');
  }

  String _formatDate(int? ms) {
    if (ms == null) return 'Unknown Date';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateFormat('MMM dd, yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final userProfile = ref.watch(userProfileProvider).value;

    if (userProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final rating = userProfile.rating ?? 5.0;
    final uid = userProfile.uid;
    final reviewsAsync = ref.watch(userReviewsProvider(uid));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
              onPressed: widget.onBack,
            ),
            const SizedBox(width: 8),
            const Text(
              'Ratings & Reviews',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 24),

        reviewsAsync.when(
          loading: () => const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading your reviews...'),
                ],
              ),
            ),
          ),
          error: (err, stack) => Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Failed to load reviews: $err',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(userReviewsProvider(uid)),
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            ),
          ),
          data: (reviews) {
            final count = reviews.length;

            return Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(userReviewsProvider(uid));
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    // Summary Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? AppColors.darkCard
                            : AppColors.lightCard,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: isDarkMode
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: AppColors.amber.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: Text(
                                    rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      color: AppColors.amber,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Your Average Rating',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Row(
                                          children: [
                                            for (int i = 1; i <= 5; i++)
                                              Icon(
                                                Icons.star,
                                                size: 16,
                                                color: i <= rating.round()
                                                    ? AppColors.amber
                                                    : (isDarkMode
                                                          ? Colors.grey[800]
                                                          : Colors.grey[300]),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Based on $count ${count == 1 ? "review" : "reviews"}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDarkMode
                                                  ? AppColors.darkTextMuted
                                                  : AppColors.lightTextMuted,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  ref.invalidate(userReviewsProvider(uid)),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Refresh Reviews'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDarkMode
                                    ? Colors.white10
                                    : Colors.grey[100],
                                foregroundColor: isDarkMode
                                    ? Colors.white
                                    : Colors.black87,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: isDarkMode
                                        ? Colors.white10
                                        : Colors.grey[300]!,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Title
                    const Text(
                      'Recent Feedback',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (reviews.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: isDarkMode
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                            style: BorderStyle
                                .none, // We can use dashed styling if needed
                          ),
                          color: isDarkMode
                              ? Colors.white.withValues(alpha: 0.02)
                              : Colors.black.withValues(alpha: 0.01),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.message_outlined,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No reviews yet',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Completed gigs will show feedback here once rated.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: reviews.length,
                        itemBuilder: (context, index) {
                          final r = reviews[index];
                          final reviewerName =
                              r['reviewerName'] as String? ?? 'A';
                          final dateStr = _formatDate(r['timestamp'] as int?);
                          final score = r['score'] as int? ?? 5;
                          final comment = r['comment'] as String? ?? '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? AppColors.darkCard
                                  : AppColors.lightCard,
                              borderRadius: BorderRadius.circular(28),
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
                                      radius: 20,
                                      backgroundColor: AppColors.indigo
                                          .withValues(alpha: 0.1),
                                      child: Text(
                                        reviewerName.isNotEmpty
                                            ? reviewerName[0].toUpperCase()
                                            : 'A',
                                        style: const TextStyle(
                                          color: AppColors.indigo,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _obfuscateName(reviewerName),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            dateStr,
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
                                    Row(
                                      children: [
                                        for (int i = 1; i <= 5; i++)
                                          Icon(
                                            Icons.star,
                                            size: 14,
                                            color: i <= score
                                                ? AppColors.amber
                                                : (isDarkMode
                                                      ? Colors.grey[800]
                                                      : Colors.grey[300]),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (comment.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    '"$comment"',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontStyle: FontStyle.italic,
                                      color: isDarkMode
                                          ? Colors.grey[300]
                                          : Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
