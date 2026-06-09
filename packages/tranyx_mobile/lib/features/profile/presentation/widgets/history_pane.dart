import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'package:tranyx_mobile/features/jobs/providers/job_repository.dart';
import 'package:intl/intl.dart';

final userTransactionsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, uid) {
      return ref.watch(transitRepositoryProvider).getUserTransactions(uid);
    });

class HistoryPane extends ConsumerStatefulWidget {
  final VoidCallback onBack;

  const HistoryPane({super.key, required this.onBack});

  @override
  ConsumerState<HistoryPane> createState() => _HistoryPaneState();
}

class _HistoryPaneState extends ConsumerState<HistoryPane> {
  List<Map<String, dynamic>> _historyItems = [];
  final Map<String, UserProfile?> _counterpartyCache = {};

  String _kindFilter = 'all'; // 'all', 'gig', 'vehicle', 'property'
  String _activeTab = 'earnings'; // 'earnings', 'purchases', 'deposits'
  bool _tabsInitialized = false;
  String _activeFilter = 'daily'; // 'daily', 'weekly', 'monthly', 'yearly'
  int _selectedBarIndex = -1;

  final Map<String, double> _pendingStars = {};
  final Set<String> _submittingRating = {};
  final Set<String> _ratedThisSession = {};

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final profile = ref.read(userProfileProvider).value;
    if (profile == null) {
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
      });
    } catch (e) {}
  }

  String? _counterpartyUid(Map<String, dynamic> item, String myUid) {
    final hostId = item['hostId']?.toString();
    final renteeId = item['renteeId']?.toString();
    if (hostId == myUid) {
      return (renteeId?.isNotEmpty == true) ? renteeId : null;
    }
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
    final commission = totalCost * 0.03;
    final finalPaid = myRole == 'host'
        ? (totalCost - commission)
        : (totalCost + bookingFee);

    final priceDaily = (item['priceDaily'] as num?)?.toDouble() ?? 0.0;
    final listingFee = priceDaily * 0.015;

    final hireWithDriver = item['hireWithDriver'] as bool? ?? false;
    final driverDailyPrice =
        (item['driverDailyPrice'] as num?)?.toDouble() ?? 0.0;
    final multInt = multiplier is num
        ? multiplier.toInt()
        : (int.tryParse(multiplier.toString()) ?? 0);
    final driverFee = hireWithDriver ? (driverDailyPrice * multInt) : 0.0;
    final baseRentalCost = totalCost - driverFee;

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
                    Text(
                      driverFee > 0 ? 'Base Vehicle Rental' : 'Base Cost',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      '₱ ${(driverFee > 0 ? baseRentalCost : totalCost).toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (driverFee > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Driver Services Fee',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      Text(
                        '₱ ${driverFee.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      myRole == 'host'
                          ? 'Platform Commission (3%)'
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
                const SizedBox(height: 4),
                if (myRole == 'host') ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Listing Fee (1.5% paid upfront)',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      Text(
                        '− ₱ ${listingFee.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
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
    final startDate = (item['startDate'] as num?)?.toInt();
    final endDate = (item['endDate'] as num?)?.toInt();

    final bookingFee =
        (item['bookingFee'] as num?)?.toDouble() ?? (totalCost * 0.03);
    final commission = totalCost * 0.03;
    final finalPaid = myRole == 'host'
        ? (totalCost - commission)
        : (totalCost + bookingFee);

    final listingFee = priceMonthly * 0.015;

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
                          ? 'Platform Commission (3%)'
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
                const SizedBox(height: 4),
                if (myRole == 'host') ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Listing Fee (1.5% paid upfront)',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      Text(
                        '− ₱ ${listingFee.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
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

  Widget _buildAggregatesSummary(
    double periodTotal,
    double walletBalance,
    int count,
    List<Map<String, dynamic>> holdbacks,
    bool isDarkMode,
  ) {
    final double pendingTotal = holdbacks.fold<double>(0.0, (sum, item) {
      final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
      return sum + amt;
    });

    Widget card(
      IconData icon,
      Color color,
      String label,
      String value, {
      Widget? extra,
    }) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDarkMode ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (extra != null) extra,
                ],
              ),
            ),
          ],
        ),
      );
    }

    final periodLabel = _activeFilter == 'daily'
        ? "This Week"
        : _activeFilter == 'weekly'
        ? "This Month"
        : _activeFilter == 'monthly'
        ? "This Year"
        : "Total";

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: card(
                Icons.attach_money,
                AppColors.indigo,
                "$periodLabel Payouts",
                "₱ ${periodTotal.toStringAsFixed(2)}",
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: card(
                Icons.wallet,
                Colors.green,
                "Wallet Balance",
                "₱ ${walletBalance.toStringAsFixed(2)}",
                extra: pendingTotal > 0
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          "+ ₱ ${pendingTotal.toStringAsFixed(2)} pending",
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: card(
                Icons.check_circle_outline,
                Colors.deepPurple,
                "Completed Jobs",
                "$count Total",
              ),
            ),
          ],
        ),
        if (pendingTotal > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      "Escrow Holdbacks Pending Release (48h)",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...holdbacks.map((holdback) {
                  final amt = (holdback['amount'] as num?)?.toDouble() ?? 0.0;
                  final relAt =
                      holdback['releaseAt'] as int? ??
                      DateTime.now().millisecondsSinceEpoch;
                  final hrs =
                      ((relAt - DateTime.now().millisecondsSinceEpoch) /
                              (1000 * 60 * 60))
                          .ceil();
                  final hrsStr = hrs <= 0
                      ? 'processing release'
                      : 'releases in $hrs hr${hrs == 1 ? "" : "s"}';
                  return Padding(
                    padding: const EdgeInsets.only(left: 24.0, bottom: 4.0),
                    child: Text(
                      "• ₱ ${amt.toStringAsFixed(2)} ($hrsStr)",
                      style: TextStyle(
                        fontSize: 10,
                        color: isDarkMode
                            ? Colors.amber.shade200
                            : Colors.amber.shade800,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGigHistoryCard(
    Map<String, dynamic> tx,
    bool isEarningTab,
    bool isDarkMode,
  ) {
    final title = tx['title'] as String? ?? 'Job';
    final desc = tx['desc'] as String? ?? '';
    final date = tx['date'] as String? ?? '';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final baseAmount = (tx['baseAmount'] as num?)?.toDouble() ?? 0.0;
    final isSuccessful =
        tx['status'] == 'Released' || tx['status'] == 'Successful';

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
                  color: (isEarningTab ? Colors.green : Colors.red).withValues(
                    alpha: 0.1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isEarningTab ? Icons.arrow_downward : Icons.arrow_upward,
                  color: isEarningTab ? Colors.green : Colors.red,
                  size: 20,
                ),
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
                    Text(
                      '$desc • $date',
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
                  Text(
                    '${isEarningTab ? "+" : "−"} ₱ ${amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: isEarningTab
                          ? Colors.green
                          : (isDarkMode ? Colors.white : Colors.black),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _pill(
                    isSuccessful ? 'Successful' : 'Pending',
                    isSuccessful ? Colors.green : Colors.amber,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.black26 : Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isEarningTab) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Base Gig Payout',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      Text(
                        '₱ ${baseAmount.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        tx['commissionLabel']?.toString() ??
                            'Platform Commission (3%)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        '− ₱ ${(tx['commissionFee'] as num?)?.toDouble().toStringAsFixed(2) ?? "0.00"}',
                        style: const TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (tx['kind'] == 'listing_fee') ...[
                        const Text(
                          'Listing Fee (1.5%)',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          '₱ ${amount.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ] else ...[
                        const Text(
                          'Base Budget',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          '₱ ${baseAmount.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                  if (tx['txFee'] != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Transaction Fee (7%)',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          '+ ₱ ${(tx['txFee'] as num?)?.toDouble().toStringAsFixed(2) ?? "0.00"}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (tx['convFee'] != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Convenience Fee (3%)',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          '+ ₱ ${(tx['convFee'] as num?)?.toDouble().toStringAsFixed(2) ?? "0.00"}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEarningTab ? 'Net Released' : 'Total Cost',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '₱ ${amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isEarningTab ? Colors.green : AppColors.indigo,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopUpHistoryCard(Map<String, dynamic> tx, bool isDarkMode) {
    final title = tx['title'] as String? ?? 'Funds Deposited';
    final desc = tx['desc'] as String? ?? '';
    final date = tx['date'] as String? ?? '';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final method = tx['method'] as String? ?? 'Unknown';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.add_circle_outline,
              color: Colors.deepPurple,
              size: 20,
            ),
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
                    fontSize: 14,
                  ),
                ),
                Text(
                  '$desc • $date',
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
              Text(
                '+ ₱ ${amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 6),
              _pill(method, Colors.deepPurple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChart(
    List<Map<String, dynamic>> activeData,
    double maxVal,
    bool isDarkMode,
  ) {
    if (activeData.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Earnings Analytics",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "Nyxian revenue stream visualization",
                    style: TextStyle(
                      fontSize: 11,
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                ],
              ),
              // Chart filter toggles
              Container(
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.black26 : Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  children: ['daily', 'weekly', 'monthly', 'yearly'].map((
                    filter,
                  ) {
                    final isSelected = _activeFilter == filter;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _activeFilter = filter;
                          _selectedBarIndex = -1;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.indigo
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          filter.substring(0, 1).toUpperCase() +
                              filter.substring(1),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : (isDarkMode ? Colors.grey : Colors.grey[700]),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Bar columns
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(activeData.length, (index) {
                final bar = activeData[index];
                final label = bar['label'] as String;
                final val = bar['value'] as double;
                final double pct = maxVal > 0 ? (val / maxVal) : 0.0;
                final double barHeight = (pct * 80).clamp(6.0, 80.0);

                final isHovered = _selectedBarIndex == index;

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedBarIndex = isHovered ? -1 : index;
                      });
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isHovered && val > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: AppColors.indigo,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "₱${val.toStringAsFixed(0)}",
                              style: const TextStyle(
                                fontSize: 8,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Container(
                          width: 24,
                          height: barHeight,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.indigo, AppColors.purple],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: isHovered
                                ? [
                                    BoxShadow(
                                      color: AppColors.indigo.withValues(
                                        alpha: 0.4,
                                      ),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isHovered
                                ? AppColors.indigo
                                : (isDarkMode
                                      ? AppColors.darkTextMuted
                                      : AppColors.lightTextMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
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

    if (!_tabsInitialized) {
      if (userProfile.accountType == AccountType.employer) {
        _activeTab = 'purchases';
      } else {
        _activeTab = 'earnings';
      }
      _tabsInitialized = true;
    }

    final myJobs = ref.watch(myJobsProvider).value ?? [];
    final userTransactions =
        ref.watch(userTransactionsProvider(userProfile.uid)).value ?? [];
    final escrowHoldbacks = ref.watch(escrowHoldbacksProvider).value ?? [];

    // Process transactions
    final eTrans = <Map<String, dynamic>>[];
    final pTrans = <Map<String, dynamic>>[];
    final dTrans = <Map<String, dynamic>>[];

    int gigsCount = 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentWeekMonday = today.subtract(Duration(days: today.weekday - 1));
    final currentWeekMondayMs = currentWeekMonday.millisecondsSinceEpoch;
    final currentWeekSundayEndMs = currentWeekMonday
        .add(const Duration(days: 7))
        .millisecondsSinceEpoch;

    final currentMonthStartMs = DateTime(
      now.year,
      now.month,
      1,
    ).millisecondsSinceEpoch;
    final currentMonthEndMs = DateTime(
      now.year,
      now.month + 1,
      1,
    ).millisecondsSinceEpoch;

    final currentYearStartMs = DateTime(now.year, 1, 1).millisecondsSinceEpoch;
    final currentYearEndMs = DateTime(
      now.year + 1,
      1,
      1,
    ).millisecondsSinceEpoch;

    final dailyAgg = {
      'Mon': 0.0,
      'Tue': 0.0,
      'Wed': 0.0,
      'Thu': 0.0,
      'Fri': 0.0,
      'Sat': 0.0,
      'Sun': 0.0,
    };
    final weeklyAgg = {
      'Week 1': 0.0,
      'Week 2': 0.0,
      'Week 3': 0.0,
      'Week 4': 0.0,
    };
    final months = [
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
    final monthlyAgg = {for (var m in months) m: 0.0};
    final currentYear = now.year;
    final yearlyAgg = {
      '${currentYear - 2}': 0.0,
      '${currentYear - 1}': 0.0,
      '$currentYear': 0.0,
    };

    // 1. Process Jobs
    for (final job in myJobs) {
      final status = job.status.toLowerCase();
      if (status == 'completed' || status == 'done' || status == 'complete') {
        final creatorId = job.creatorId;
        final title = job.title;
        final price = job.pricingValue;
        final createdAtMs = job.createdAt.millisecondsSinceEpoch;

        if (creatorId != userProfile.uid) {
          // NYXIAN
          final platformFee = price * 0.03;
          final payout = price - platformFee;
          gigsCount++;

          eTrans.add({
            'title': title,
            'desc': 'Completed contract',
            'date': _formatDate(createdAtMs),
            'amount': payout,
            'baseAmount': price,
            'commissionFee': platformFee,
            'commissionLabel': 'Platform Commission (3%)',
            'status': 'Released',
            'timestamp': createdAtMs,
            'kind': 'gig',
          });

          // Aggregate for graph
          final dt = job.createdAt;
          if (createdAtMs >= currentWeekMondayMs &&
              createdAtMs < currentWeekSundayEndMs) {
            final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            final dayName = days[dt.weekday - 1];
            dailyAgg[dayName] = (dailyAgg[dayName] ?? 0.0) + payout;
          }
          if (createdAtMs >= currentMonthStartMs &&
              createdAtMs < currentMonthEndMs) {
            final wNum = ((dt.day - 1) ~/ 7) + 1;
            final wName = 'Week ${wNum > 4 ? 4 : wNum}';
            weeklyAgg[wName] = (weeklyAgg[wName] ?? 0.0) + payout;
          }
          if (createdAtMs >= currentYearStartMs &&
              createdAtMs < currentYearEndMs) {
            final mName = months[dt.month - 1];
            monthlyAgg[mName] = (monthlyAgg[mName] ?? 0.0) + payout;
          }
          final yName = dt.year.toString();
          if (yearlyAgg.containsKey(yName)) {
            yearlyAgg[yName] = (yearlyAgg[yName] ?? 0.0) + payout;
          }
        } else {
          // EMPLOYER
          final txFee = price * 0.07;
          final convFee = price * 0.03;
          final totalCost = price + txFee + convFee;

          pTrans.add({
            'title': title,
            'desc': 'Job payment',
            'date': _formatDate(createdAtMs),
            'amount': totalCost,
            'baseAmount': price,
            'txFee': txFee,
            'convFee': convFee,
            'status': 'Successful',
            'timestamp': createdAtMs,
            'kind': 'gig',
          });
        }
      }
    }

    // 2. Process Rentals from Local History Cache
    for (final rentalMap in _historyItems) {
      final kind = rentalMap['rentalKind']?.toString() ?? 'vehicle';
      final hostId = rentalMap['hostId']?.toString();
      final renteeId = rentalMap['renteeId']?.toString();
      final title = kind == 'vehicle'
          ? '${rentalMap['year'] ?? ''} ${rentalMap['brand'] ?? ''} ${rentalMap['model'] ?? ''}'
                .trim()
          : (rentalMap['title']?.toString() ?? 'Property Rental');
      final price = (rentalMap['totalCost'] as num?)?.toDouble() ?? 0.0;
      final completedAt =
          rentalMap['completedAt'] ?? rentalMap['createdAt'] ?? 0;
      final createdAtMs = completedAt is int
          ? completedAt
          : (completedAt is Timestamp ? completedAt.millisecondsSinceEpoch : 0);

      final dt = DateTime.fromMillisecondsSinceEpoch(createdAtMs);

      if (hostId == userProfile.uid) {
        // Earnings
        final platformFee = price * 0.03;
        final payout = price - platformFee;
        gigsCount++;

        final alreadyAdded = eTrans.any(
          (e) => e['timestamp'] == createdAtMs && e['title'] == title,
        );
        if (!alreadyAdded) {
          eTrans.add({
            'title': title,
            'desc': kind == 'vehicle'
                ? 'Completed vehicle rental'
                : 'Completed property rental',
            'date': _formatDate(createdAtMs),
            'amount': payout,
            'baseAmount': price,
            'commissionFee': platformFee,
            'commissionLabel': 'Platform Commission (3%)',
            'status': 'Released',
            'timestamp': createdAtMs,
            'kind': kind,
            'item': rentalMap,
          });

          // Aggregate for graph
          if (createdAtMs >= currentWeekMondayMs &&
              createdAtMs < currentWeekSundayEndMs) {
            final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            final dayName = days[dt.weekday - 1];
            dailyAgg[dayName] = (dailyAgg[dayName] ?? 0.0) + payout;
          }
          if (createdAtMs >= currentMonthStartMs &&
              createdAtMs < currentMonthEndMs) {
            final wNum = ((dt.day - 1) ~/ 7) + 1;
            final wName = 'Week ${wNum > 4 ? 4 : wNum}';
            weeklyAgg[wName] = (weeklyAgg[wName] ?? 0.0) + payout;
          }
          if (createdAtMs >= currentYearStartMs &&
              createdAtMs < currentYearEndMs) {
            final mName = months[dt.month - 1];
            monthlyAgg[mName] = (monthlyAgg[mName] ?? 0.0) + payout;
          }
          final yName = dt.year.toString();
          if (yearlyAgg.containsKey(yName)) {
            yearlyAgg[yName] = (yearlyAgg[yName] ?? 0.0) + payout;
          }
        }
      } else if (renteeId == userProfile.uid) {
        // Purchases
        final bookingFee = price * 0.03;
        final totalPaid = price + bookingFee;

        final alreadyAdded = pTrans.any(
          (p) => p['timestamp'] == createdAtMs && p['title'] == title,
        );
        if (!alreadyAdded) {
          pTrans.add({
            'title': title,
            'desc': kind == 'vehicle'
                ? 'Vehicle rental payment'
                : 'Property rental payment',
            'date': _formatDate(createdAtMs),
            'amount': totalPaid,
            'baseAmount': price,
            'bookingFee': bookingFee,
            'status': 'Successful',
            'timestamp': createdAtMs,
            'kind': kind,
            'item': rentalMap,
          });
        }
      }
    }

    // 3. Process Deposits
    for (final tx in userTransactions) {
      final type = tx['type'] as String?;
      final createdAt = tx['createdAt'];
      final createdAtMs = createdAt is int
          ? createdAt
          : (createdAt is Timestamp ? createdAt.millisecondsSinceEpoch : 0);

      if (type == 'deposit') {
        dTrans.add({
          'title': tx['title'] ?? 'Top-Up',
          'desc': tx['desc'] ?? 'Deposit',
          'date': _formatDate(createdAtMs),
          'amount': (tx['amount'] as num?)?.toDouble() ?? 0.0,
          'method': tx['method'] ?? 'Unknown',
          'timestamp': createdAtMs,
        });
      } else if (type == 'listing_fee') {
        pTrans.add({
          'title': tx['title'] ?? 'Listing Fee',
          'desc': tx['desc'] ?? 'Platform Listing Fee',
          'date': _formatDate(createdAtMs),
          'amount': (tx['amount'] as num?)?.toDouble() ?? 0.0,
          'status': 'Successful',
          'timestamp': createdAtMs,
          'kind': 'listing_fee',
        });
      }
    }

    // Sort descending by timestamp (latest first)
    eTrans.sort(
      (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
    );
    pTrans.sort(
      (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
    );
    dTrans.sort(
      (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
    );

    // Fallback Mock Data for Chart if eTrans is empty (same as web)
    final bool hasDynamicEarnings = eTrans.isNotEmpty;
    final List<Map<String, dynamic>> activeData;
    if (hasDynamicEarnings) {
      if (_activeFilter == 'daily') {
        activeData = dailyAgg.entries
            .map((e) => {'label': e.key, 'value': e.value})
            .toList();
      } else if (_activeFilter == 'weekly') {
        activeData = weeklyAgg.entries
            .map((e) => {'label': e.key, 'value': e.value})
            .toList();
      } else if (_activeFilter == 'monthly') {
        activeData = monthlyAgg.entries
            .map((e) => {'label': e.key, 'value': e.value})
            .toList();
      } else {
        activeData = yearlyAgg.entries
            .map((e) => {'label': e.key, 'value': e.value})
            .toList();
      }
    } else {
      if (_activeFilter == 'daily') {
        activeData = [
          {'label': 'Mon', 'value': 1200.0},
          {'label': 'Tue', 'value': 800.0},
          {'label': 'Wed', 'value': 1500.0},
          {'label': 'Thu', 'value': 2100.0},
          {'label': 'Fri', 'value': 950.0},
          {'label': 'Sat', 'value': 3000.0},
          {'label': 'Sun', 'value': 2400.0},
        ];
      } else if (_activeFilter == 'weekly') {
        activeData = [
          {'label': 'Week 1', 'value': 8500.0},
          {'label': 'Week 2', 'value': 12000.0},
          {'label': 'Week 3', 'value': 9800.0},
          {'label': 'Week 4', 'value': 15400.0},
        ];
      } else if (_activeFilter == 'monthly') {
        activeData = [
          {'label': 'Jan', 'value': 38000.0},
          {'label': 'Feb', 'value': 45000.0},
          {'label': 'Mar', 'value': 42000.0},
          {'label': 'Apr', 'value': 58000.0},
          {'label': 'May', 'value': 64000.0},
          {'label': 'Jun', 'value': 72000.0},
        ];
      } else {
        activeData = [
          {'label': '2024', 'value': 450000.0},
          {'label': '2025', 'value': 680000.0},
          {'label': '2026', 'value': 320000.0},
        ];
      }
    }

    double totalEarnedInFilter = 0.0;
    double maxVal = 1.0;
    for (final item in activeData) {
      final v = (item['value'] as num).toDouble();
      totalEarnedInFilter += v;
      if (v > maxVal) maxVal = v;
    }

    final double activeBalance = userProfile.tyxBalance;

    final filteredEarnings = eTrans.where((tx) {
      if (_kindFilter == 'all') return true;
      if (_kindFilter == 'gig') return tx['kind'] == 'gig';
      if (_kindFilter == 'vehicle') return tx['kind'] == 'vehicle';
      if (_kindFilter == 'property') return tx['kind'] == 'property';
      return true;
    }).toList();

    final filteredPurchases = pTrans.where((tx) {
      if (_kindFilter == 'all') return true;
      if (_kindFilter == 'gig') return tx['kind'] == 'gig';
      if (_kindFilter == 'vehicle') return tx['kind'] == 'vehicle';
      if (_kindFilter == 'property') return tx['kind'] == 'property';
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
              'History & Earnings',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _loadHistory();
                ref.invalidate(userTransactionsProvider(userProfile.uid));
                ref.invalidate(escrowHoldbacksProvider);
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Custom Navigation Tabs
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _activeTab = 'earnings'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: _activeTab == 'earnings'
                            ? AppColors.indigo
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    "Earnings & Analytics",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _activeTab == 'earnings'
                          ? AppColors.indigo
                          : (isDarkMode
                                ? Colors.grey.shade500
                                : Colors.grey.shade600),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _activeTab = 'purchases'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: _activeTab == 'purchases'
                            ? AppColors.indigo
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    "Purchases & Spending",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _activeTab == 'purchases'
                          ? AppColors.indigo
                          : (isDarkMode
                                ? Colors.grey.shade500
                                : Colors.grey.shade600),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _activeTab = 'deposits'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: _activeTab == 'deposits'
                            ? AppColors.indigo
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    "Added Funds",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _activeTab == 'deposits'
                          ? AppColors.indigo
                          : (isDarkMode
                                ? Colors.grey.shade500
                                : Colors.grey.shade600),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (_activeTab == 'earnings') ...[
                _buildRevenueChart(activeData, maxVal, isDarkMode),
                const SizedBox(height: 16),
                _buildAggregatesSummary(
                  totalEarnedInFilter,
                  activeBalance,
                  hasDynamicEarnings ? gigsCount : 4,
                  escrowHoldbacks,
                  isDarkMode,
                ),
                const SizedBox(height: 24),
                // Category Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip(
                        'All Types',
                        'all',
                        _kindFilter,
                        (v) => setState(() => _kindFilter = v),
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Gigs',
                        'gig',
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
                ),
                const SizedBox(height: 16),
                if (filteredEarnings.isEmpty)
                  _buildEmptyState(isDarkMode, "No earnings records found")
                else
                  ...filteredEarnings.map((tx) {
                    final kind = tx['kind'];
                    if (kind == 'vehicle') {
                      return _buildVehicleHistoryCard(
                        tx['item'],
                        userProfile.uid,
                      );
                    } else if (kind == 'property') {
                      return _buildPropertyHistoryCard(
                        tx['item'],
                        userProfile.uid,
                      );
                    } else {
                      return _buildGigHistoryCard(tx, true, isDarkMode);
                    }
                  }),
              ] else if (_activeTab == 'purchases') ...[
                // Category Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip(
                        'All Types',
                        'all',
                        _kindFilter,
                        (v) => setState(() => _kindFilter = v),
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Gigs',
                        'gig',
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
                ),
                const SizedBox(height: 16),
                if (filteredPurchases.isEmpty)
                  _buildEmptyState(isDarkMode, "No purchases found")
                else
                  ...filteredPurchases.map((tx) {
                    final kind = tx['kind'];
                    if (kind == 'vehicle') {
                      return _buildVehicleHistoryCard(
                        tx['item'],
                        userProfile.uid,
                      );
                    } else if (kind == 'property') {
                      return _buildPropertyHistoryCard(
                        tx['item'],
                        userProfile.uid,
                      );
                    } else {
                      return _buildGigHistoryCard(tx, false, isDarkMode);
                    }
                  }),
              ] else ...[
                if (dTrans.isEmpty)
                  _buildEmptyState(isDarkMode, "No deposits recorded")
                else
                  ...dTrans.map((tx) => _buildTopUpHistoryCard(tx, isDarkMode)),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDarkMode, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40.0),
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
              message,
              style: TextStyle(
                color: isDarkMode
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
