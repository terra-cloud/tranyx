import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'package:intl/intl.dart';

class HistoryPane extends ConsumerStatefulWidget {
  final VoidCallback onBack;

  const HistoryPane({super.key, required this.onBack});

  @override
  ConsumerState<HistoryPane> createState() => _HistoryPaneState();
}

class _HistoryPaneState extends ConsumerState<HistoryPane> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _historyItems = [];
  final Map<String, UserProfile?> _counterpartyCache = {};

  String _roleFilter = 'all'; // 'all', 'renter', 'host'
  String _kindFilter = 'all'; // 'all', 'vehicle', 'property'

  final Map<String, double> _pendingStars = {};
  final Set<String> _submittingRating = {};
  final Set<String> _ratedThisSession = {};

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final profile = ref.read(userProfileProvider).value;
    if (profile == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final repo = ref.read(transitRepositoryProvider);
      final items = await repo.getMyRentalHistory(profile.uid);

      for (final item in items) {
        final counterpartUid = _counterpartyUid(item, profile.uid);
        if (counterpartUid != null &&
            !_counterpartyCache.containsKey(counterpartUid)) {
          _counterpartyCache[counterpartUid] = await repo.getUser(
            counterpartUid,
          );
        }
      }

      setState(() {
        _historyItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String? _counterpartyUid(Map<String, dynamic> item, String myUid) {
    final hostId = item['hostId']?.toString();
    final renteeId = item['renteeId']?.toString();
    if (hostId == myUid)
      return (renteeId?.isNotEmpty == true) ? renteeId : null;
    return (hostId?.isNotEmpty == true) ? hostId : null;
  }

  String _formatDate(int? ms) {
    if (ms == null) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateFormat('MMM dd, yyyy').format(dt);
  }

  String _roleLabel(Map<String, dynamic> item, String myUid) {
    return item['hostId']?.toString() == myUid ? 'host' : 'renter';
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

  Widget _starDisplay(double? rating, String label) {
    final isDarkMode = ref.read(themeModeProvider);
    if (rating == null) {
      return Text(
        'No $label yet',
        style: TextStyle(
          fontSize: 11,
          fontStyle: FontStyle.italic,
          color: isDarkMode
              ? AppColors.darkTextMuted
              : AppColors.lightTextMuted,
        ),
      );
    }
    final full = rating.floor();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          Icon(
            Icons.star,
            size: 14,
            color: i <= full ? Colors.amber : Colors.grey[600],
          ),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
        Text(
          ' ($label)',
          style: const TextStyle(fontSize: 9, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildRatingWidget(
    Map<String, dynamic> item,
    String myRole,
    String counterpartyUid,
  ) {
    final rentalId = item['id']?.toString() ?? '';
    final ratingRole = myRole == 'host' ? 'renter' : 'host';
    final ratedFieldKey = '${ratingRole}RatedBy_${ref.read(userProvider)?.uid}';
    final alreadyRated =
        item[ratedFieldKey] == true || _ratedThisSession.contains(rentalId);
    final isSubmitting = _submittingRating.contains(rentalId);
    final selectedStars = _pendingStars[rentalId] ?? 0.0;

    if (alreadyRated) {
      return const Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 16),
          SizedBox(width: 6),
          Text(
            'Feedback submitted',
            style: TextStyle(
              fontSize: 12,
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          myRole == 'host' ? 'RATE THIS RENTER' : 'RATE THIS HOST',
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (int i = 1; i <= 5; i++)
              IconButton(
                icon: Icon(
                  Icons.star,
                  size: 24,
                  color: i <= selectedStars ? Colors.amber : Colors.grey[300],
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _pendingStars[rentalId] = i.toDouble();
                  });
                },
              ),
            if (selectedStars > 0) ...[
              const SizedBox(width: 16),
              isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ElevatedButton(
                      onPressed: () async {
                        setState(() {
                          _submittingRating.add(rentalId);
                        });
                        try {
                          await ref
                              .read(transitRepositoryProvider)
                              .submitRentalRating(
                                targetUid: counterpartyUid,
                                callerUid: ref.read(userProvider)?.uid ?? '',
                                role: ratingRole,
                                stars: selectedStars,
                                rentalId: rentalId,
                              );
                          setState(() {
                            _ratedThisSession.add(rentalId);
                            _submittingRating.remove(rentalId);
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Feedback submitted! Thank you.'),
                              ),
                            );
                          }
                        } catch (e) {
                          setState(() {
                            _submittingRating.remove(rentalId);
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.indigo,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Submit',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildCounterpartySection(
    UserProfile? profile,
    String counterpartyRole,
    Map<String, dynamic> item,
    String myRole,
    String counterpartyUid,
  ) {
    final isDarkMode = ref.read(themeModeProvider);
    final name = profile?.name ?? 'Unknown User';
    final photo = profile?.photoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            counterpartyRole == 'renter'
                ? 'RENTER DETAILS'
                : 'HOST / OWNER DETAILS',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: hasPhoto
                    ? NetworkImage(photo) as ImageProvider
                    : const AssetImage('assets/images/default-avatar.jpg')
                          as ImageProvider,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _starDisplay(profile?.renterRating, 'As Renter'),
                    const SizedBox(height: 2),
                    _starDisplay(profile?.hostRating, 'As Host'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildRatingWidget(item, myRole, counterpartyUid),
        ],
      ),
    );
  }

  Widget _buildVehicleHistoryCard(Map<String, dynamic> item, String myUid) {
    final isDarkMode = ref.read(themeModeProvider);
    final myRole = _roleLabel(item, myUid);
    final counterpartyUid = _counterpartyUid(item, myUid);
    final counterparty = counterpartyUid != null
        ? _counterpartyCache[counterpartyUid]
        : null;

    final brand = item['brand']?.toString() ?? '';
    final model = item['model']?.toString() ?? '';
    final year = item['year']?.toString() ?? '';
    final plate =
        item['plateNumber']?.toString() ?? item['plate']?.toString() ?? '';
    final fuelType = item['fuelType']?.toString() ?? 'Gasoline';
    final transmission = item['transmission']?.toString() ?? 'Automatic';
    final totalCost = (item['totalCost'] as num?)?.toDouble() ?? 0.0;
    final durationType =
        item['rentalDurationType']?.toString() ??
        item['durationType']?.toString() ??
        '';
    final multiplier = item['rentalMultiplier'] ?? item['multiplier'] ?? '';
    final startDate = (item['startDate'] as num?)?.toInt();
    final endDate = (item['endDate'] as num?)?.toInt();

    final bookingFee =
        (item['bookingFee'] as num?)?.toDouble() ?? (totalCost * 0.03);
    final commission = totalCost * 0.05;
    final finalPaid = myRole == 'host'
        ? (totalCost - commission)
        : (totalCost + bookingFee);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.indigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.directions_car,
                  color: AppColors.indigo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$year $brand $model'.trim(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (plate.isNotEmpty)
                      Text(
                        'Plate: $plate',
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
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _pill(
                    myRole == 'host' ? 'As Host' : 'As Renter',
                    myRole == 'host' ? AppColors.indigo : AppColors.purple,
                  ),
                  const SizedBox(height: 6),
                  _pill('Completed', Colors.green),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _pill(fuelType, Colors.orange),
              const SizedBox(width: 8),
              _pill(transmission, Colors.blue),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DURATION',
                      style: TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$multiplier $durationType(s)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FROM',
                      style: TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(startDate),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TO',
                      style: TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(endDate),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.black26 : Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Base Cost',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      '₱ ${totalCost.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      myRole == 'host'
                          ? 'Platform Commission (5%)'
                          : 'Booking Fee (3%)',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      '${myRole == "host" ? "-" : "+"} ₱ ${(myRole == "host" ? commission : bookingFee).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: myRole == 'host' ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      myRole == 'host' ? 'Net Earnings' : 'Total Paid',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '₱ ${finalPaid.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppColors.indigo,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (item['signatureHash'] != null &&
              (item['signatureHash'] as String).isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.05),
                border: Border.all(color: Colors.green.withValues(alpha: 0.15)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '✓ SIGNED LEASE DETAILS (SHA-256)',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['signatureHash'] as String,
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
          _buildCounterpartySection(
            counterparty,
            myRole == 'host' ? 'renter' : 'host',
            item,
            myRole,
            counterpartyUid ?? '',
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyHistoryCard(Map<String, dynamic> item, String myUid) {
    final isDarkMode = ref.read(themeModeProvider);
    final myRole = _roleLabel(item, myUid);
    final counterpartyUid = _counterpartyUid(item, myUid);
    final counterparty = counterpartyUid != null
        ? _counterpartyCache[counterpartyUid]
        : null;

    final title = item['title']?.toString() ?? 'Property Rental';
    final address = item['address']?.toString() ?? '';
    final category = item['category']?.toString() ?? '';
    final type = item['type']?.toString() ?? '';
    final totalCost = (item['totalCost'] as num?)?.toDouble() ?? 0.0;
    final priceMonthly = (item['priceMonthly'] as num?)?.toDouble() ?? 0.0;
    final depositMonths = item['depositMonths'] ?? 0;
    final startDate = (item['startDate'] as num?)?.toInt();
    final endDate = (item['endDate'] as num?)?.toInt();

    final bookingFee =
        (item['bookingFee'] as num?)?.toDouble() ?? (totalCost * 0.03);
    final commission = totalCost * 0.05;
    final finalPaid = myRole == 'host'
        ? (totalCost - commission)
        : (totalCost + bookingFee);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.home, color: Colors.teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (address.isNotEmpty)
                      Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _pill(
                    myRole == 'host' ? 'As Host' : 'As Renter',
                    myRole == 'host' ? AppColors.indigo : Colors.teal,
                  ),
                  const SizedBox(height: 6),
                  _pill('Completed', Colors.green),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (category.isNotEmpty) ...[
                _pill(category.split('.').last, Colors.teal),
                const SizedBox(width: 8),
              ],
              if (type.isNotEmpty) _pill(type.split('.').last, Colors.cyan),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MONTHLY RATE',
                      style: TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₱ ${priceMonthly.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FROM',
                      style: TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(startDate),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TO',
                      style: TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(endDate),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.black26 : Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Base Cost',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      '₱ ${totalCost.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      myRole == 'host'
                          ? 'Platform Commission (5%)'
                          : 'Booking Fee (3%)',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      '${myRole == "host" ? "-" : "+"} ₱ ${(myRole == "host" ? commission : bookingFee).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: myRole == 'host' ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      myRole == 'host' ? 'Net Earnings' : 'Total Paid',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '₱ ${finalPaid.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.teal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (item['signatureHash'] != null &&
              (item['signatureHash'] as String).isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.05),
                border: Border.all(color: Colors.green.withValues(alpha: 0.15)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '✓ SIGNED LEASE DETAILS (SHA-256)',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['signatureHash'] as String,
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
          _buildCounterpartySection(
            counterparty,
            myRole == 'host' ? 'renter' : 'host',
            item,
            myRole,
            counterpartyUid ?? '',
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    String value,
    String current,
    Function(String) onTap,
  ) {
    final isDarkMode = ref.read(themeModeProvider);
    final active = value == current;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.indigo
              : (isDarkMode ? AppColors.darkCard : Colors.white),
          border: active
              ? null
              : Border.all(
                  color: isDarkMode
                      ? AppColors.darkBorder
                      : AppColors.lightBorder,
                ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: active
                ? Colors.white
                : (isDarkMode ? AppColors.darkTextMuted : AppColors.lightText),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final userProfile = ref.watch(userProfileProvider).value;

    if (userProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final myUid = userProfile.uid;

    final filtered = _historyItems.where((item) {
      if (_roleFilter != 'all') {
        final role = _roleLabel(item, myUid);
        if (role != _roleFilter) return false;
      }
      if (_kindFilter != 'all') {
        final kind = item['rentalKind']?.toString() ?? 'vehicle';
        if (kind != _kindFilter) return false;
      }
      return true;
    }).toList();

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
              'Rental History',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadHistory,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Role Filters
        Row(
          children: [
            const Text(
              'Role: ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              'All',
              'all',
              _roleFilter,
              (v) => setState(() => _roleFilter = v),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              'Renter',
              'renter',
              _roleFilter,
              (v) => setState(() => _roleFilter = v),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              'Host',
              'host',
              _roleFilter,
              (v) => setState(() => _roleFilter = v),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Kind Filters
        Row(
          children: [
            const Text(
              'Kind: ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              'All',
              'all',
              _kindFilter,
              (v) => setState(() => _kindFilter = v),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              'Vehicles',
              'vehicle',
              _kindFilter,
              (v) => setState(() => _kindFilter = v),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              'Properties',
              'property',
              _kindFilter,
              (v) => setState(() => _kindFilter = v),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history_outlined,
                        size: 48,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No history records found',
                        style: TextStyle(
                          color: isDarkMode
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final kind = item['rentalKind']?.toString() ?? 'vehicle';
                    if (kind == 'vehicle') {
                      return _buildVehicleHistoryCard(item, myUid);
                    } else {
                      return _buildPropertyHistoryCard(item, myUid);
                    }
                  },
                ),
        ),
      ],
    );
  }
}
