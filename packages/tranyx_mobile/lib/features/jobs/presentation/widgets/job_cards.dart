import 'package:flutter/material.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/utils/num_extension.dart';
import 'package:tranyx_mobile/core/utils/string_extension.dart';
import 'package:tranyx_mobile/features/jobs/models/job.dart';
import 'package:intl/intl.dart';
import 'package:tranyx_mobile/core/widgets/user_avatar.dart';

/// ─── Completed Gig Card – Employer View ───────────────────────────────────
/// Shows: Base Gig Price + Transaction Fee (7%) + Convenience Fee (3%) = Total Paid
class JobCompletedEmployerCard extends StatelessWidget {
  final Job job;
  final VoidCallback onClick;
  final bool isDarkMode;

  const JobCompletedEmployerCard({
    super.key,
    required this.job,
    required this.onClick,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final base = job.pricingValue;
    final txFee = base * 0.07;
    final convFee = base * 0.03;
    final totalPaid = base + txFee + convFee;
    final isCompleted = job.status == 'Completed';
    final statusColor = isCompleted ? Colors.green : Colors.grey;
    final completedDate = DateFormat('MMM d, yyyy').format(job.createdAt);

    return GestureDetector(
      onTap: onClick,
      child: Container(
        padding: const EdgeInsets.all(20),
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
            // ── Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.title.capitalize(),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      Text(
                        '${job.category.name.capitalize()} • $completedDate',
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    job.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ── Payment breakdown
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.black26 : Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _breakdownRow(
                    'Base Gig Price',
                    '₱ ${base.toStringAsFixed(2)}',
                    isDarkMode,
                  ),
                  const SizedBox(height: 6),
                  _breakdownRow(
                    'Transaction Fee (7%)',
                    '+ ₱ ${txFee.toStringAsFixed(2)}',
                    isDarkMode,
                    valueColor: Colors.amber[700],
                  ),
                  const SizedBox(height: 6),
                  _breakdownRow(
                    'Convenience Fee (3%)',
                    '+ ₱ ${convFee.toStringAsFixed(2)}',
                    isDarkMode,
                    valueColor: Colors.amber[700],
                  ),
                  const Divider(height: 16),
                  _breakdownRow(
                    'Total Paid',
                    '₱ ${totalPaid.toStringAsFixed(2)}',
                    isDarkMode,
                    isBold: true,
                    valueColor: AppColors.indigo,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ── Footer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (job.acceptedApplicantId != null)
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 14,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Nyxian hired',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDarkMode
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  )
                else
                  const SizedBox.shrink(),
                GestureDetector(
                  onTap: onClick,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.white12 : Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Details',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? AppColors.darkText
                            : AppColors.lightText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// ─── Completed Gig Card – Nyxian View ────────────────────────────────────
/// Shows: Base Payout − Platform Commission (3%) = Net Earnings
class JobCompletedNyxianCard extends StatelessWidget {
  final Job job;
  final VoidCallback onClick;
  final bool isDarkMode;

  const JobCompletedNyxianCard({
    super.key,
    required this.job,
    required this.onClick,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final base = job.pricingValue;
    final commission = base * 0.03;
    final netPayout = base - commission;
    final completedDate = DateFormat('MMM d, yyyy').format(job.createdAt);

    return GestureDetector(
      onTap: onClick,
      child: Container(
        padding: const EdgeInsets.all(20),
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
            // ── Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.payments_outlined,
                    color: Colors.green,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.title.capitalize(),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      Text(
                        '${job.category.name.capitalize()} • $completedDate',
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'COMPLETED',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ── Payment breakdown
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.black26 : Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _breakdownRow(
                    'Base Payout',
                    '₱ ${base.toStringAsFixed(2)}',
                    isDarkMode,
                  ),
                  const SizedBox(height: 6),
                  _breakdownRow(
                    'Platform Commission (3%)',
                    '− ₱ ${commission.toStringAsFixed(2)}',
                    isDarkMode,
                    valueColor: Colors.red,
                  ),
                  const Divider(height: 16),
                  _breakdownRow(
                    'Net Earnings',
                    '₱ ${netPayout.toStringAsFixed(2)}',
                    isDarkMode,
                    isBold: true,
                    valueColor: Colors.green,
                  ),
                ],
              ),
            ),
            // ── Location / Type chips row
            Row(
              spacing: 10,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    spacing: 5,
                    children: [
                      Icon(
                        job.locationType.toLowerCase() == 'remote'
                            ? Icons.wifi
                            : Icons.location_on_outlined,
                        size: 13,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                      Expanded(
                        child: Text(
                          job.locationType.toLowerCase() == 'remote'
                              ? 'Remote'
                              : (job.address ?? 'On-site'),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDarkMode
                                ? AppColors.darkTextMuted
                                : AppColors.lightTextMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onClick,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.white12 : Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Details',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? AppColors.darkText
                            : AppColors.lightText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared breakdown row helper
Widget _breakdownRow(
  String label,
  String value,
  bool isDarkMode, {
  Color? valueColor,
  bool isBold = false,
}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: isBold ? 13 : 11,
          fontWeight: isBold ? FontWeight.w900 : FontWeight.w500,
          color:
              valueColor ??
              (isDarkMode ? AppColors.darkText : AppColors.lightText),
        ),
      ),
    ],
  );
}

class AvatarStack extends StatelessWidget {
  final List<String> photos;
  final double size;
  final int maxVisible;

  const AvatarStack({
    super.key,
    required this.photos,
    this.size = 24,
    this.maxVisible = 3,
  });

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox.shrink();

    final visiblePhotos = photos.take(maxVisible).toList();
    return SizedBox(
      height: size,
      width: (visiblePhotos.length * (size * 0.7)) + (size * 0.3),
      child: Stack(
        children: List.generate(visiblePhotos.length, (index) {
          return Positioned(
            left: index * (size * 0.6),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: UserAvatar(
                name: '?',
                photoUrl: visiblePhotos[index],
                radius: size / 2,
                backgroundColor: AppColors.indigo.withValues(alpha: 0.1),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class JobNyxianCard extends StatelessWidget {
  final Job job;
  final VoidCallback onClick;
  final bool isDarkMode;

  const JobNyxianCard({
    super.key,
    required this.job,
    required this.onClick,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    bool isHigh = job.dateRequirement != 'Flexible';
    return GestureDetector(
      onTap: onClick,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.title.capitalize(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: isDarkMode
                                ? AppColors.darkTextMuted
                                : AppColors.lightTextMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            job.locationType == 'Remote'
                                ? 'Remote'
                                : (job.address ?? 'No address'),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode
                                  ? AppColors.darkTextMuted
                                  : AppColors.lightTextMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  job.pricingValue.toAmount(length: 0),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isHigh
                        ? AppColors.red.withValues(alpha: 0.2)
                        : (isDarkMode
                              ? AppColors.darkBorder
                              : AppColors.lightBg),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isHigh ? "URGENT" : "FLEXIBLE",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isHigh
                          ? AppColors.red
                          : (isDarkMode
                                ? AppColors.darkTextMuted
                                : AppColors.lightTextMuted),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white : AppColors.darkBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "View",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? AppColors.darkBg : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class JobEmployerCard extends StatelessWidget {
  final Job job;
  final VoidCallback onClick;
  final bool isDarkMode;

  const JobEmployerCard({
    super.key,
    required this.job,
    required this.onClick,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    bool isActive = job.status == 'Open';
    String postedStr = "Posted ${DateFormat('MMM d').format(job.createdAt)}";

    return GestureDetector(
      onTap: onClick,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    job.title.capitalize(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode
                          ? AppColors.darkText
                          : AppColors.lightText,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.green.withValues(alpha: 0.1)
                        : AppColors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    job.status,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isActive ? AppColors.green : AppColors.amber,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (job.applicantCount > 0) ...[
                        AvatarStack(
                          photos: job.recentApplicantPhotos.isNotEmpty
                              ? job.recentApplicantPhotos
                              : [''],
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        "${job.applicantCount} Applicants",
                        style: TextStyle(
                          fontSize: 13,
                          color: isDarkMode
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        postedStr,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDarkMode
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.indigo),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
