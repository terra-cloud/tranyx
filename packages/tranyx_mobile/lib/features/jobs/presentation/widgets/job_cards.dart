import 'package:flutter/material.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/utils/num_extension.dart';
import 'package:tranyx_mobile/core/utils/string_extension.dart';
import 'package:tranyx_mobile/features/jobs/models/job.dart';
import 'package:intl/intl.dart';

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
              child: CircleAvatar(
                radius: size / 2,
                backgroundImage: (visiblePhotos[index].isNotEmpty)
                    ? NetworkImage(visiblePhotos[index]) as ImageProvider
                    : const AssetImage('assets/images/default-avatar.jpg')
                          as ImageProvider,
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
