import 'package:flutter/material.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';

/// Reusable verification badge widget.
/// Renders [SizedBox.shrink] if unverified ([VerificationLevel.none]),
/// a distinct Level 1 badge (e.g. Cyan/Blue Shield) for [VerificationLevel.level1Basic],
/// or an upgraded Level 2 tier badge (e.g. Gold/Shield icon) for [VerificationLevel.level2Pro].
class UserBadgeWidget extends StatelessWidget {
  final VerificationLevel level;
  final double size;
  final bool showLabel;
  final VoidCallback? onTap;

  const UserBadgeWidget({
    super.key,
    required this.level,
    this.size = 16,
    this.showLabel = false,
    this.onTap,
  });

  /// Factory constructor to parse from dynamic value (int, string, bool, or null)
  factory UserBadgeWidget.fromDynamic({
    Key? key,
    dynamic verificationLevel,
    bool? isVerified,
    bool? idVerified,
    String? status,
    double size = 16,
    bool showLabel = false,
    VoidCallback? onTap,
  }) {
    VerificationLevel parsed = VerificationLevel.none;
    if (verificationLevel != null) {
      parsed = VerificationLevel.fromValue(verificationLevel);
    } else if (idVerified == true ||
        isVerified == true ||
        (status != null && status.toUpperCase() == 'VERIFIED')) {
      parsed = VerificationLevel.level1Basic;
    }
    return UserBadgeWidget(
      key: key,
      level: parsed,
      size: size,
      showLabel: showLabel,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (level == VerificationLevel.none) {
      return const SizedBox.shrink();
    }

    final isLevel2 = level == VerificationLevel.level2Pro;
    final badgeColor =
        isLevel2 ? const Color(0xFFF59E0B) : const Color(0xFF06B6D4);
    final badgeBg =
        isLevel2 ? const Color(0xFFFEF3C7) : const Color(0xFFCFFAFE);
    final badgeIcon =
        isLevel2 ? Icons.shield_rounded : Icons.check_circle_rounded;
    final badgeText = isLevel2 ? 'PRO' : 'VERIFIED';

    return GestureDetector(
      onTap: () {
        if (onTap != null) {
          onTap!();
        } else {
          _showVerificationDetailsModal(context, level);
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? 6 : 3,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: badgeBg.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: badgeColor.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              badgeIcon,
              size: size,
              color: badgeColor,
            ),
            if (showLabel) ...[
              const SizedBox(width: 4),
              Text(
                badgeText,
                style: TextStyle(
                  color: isLevel2
                      ? const Color(0xFFB45309)
                      : const Color(0xFF0E7490),
                  fontSize: size * 0.7,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static void _showVerificationDetailsModal(
    BuildContext context,
    VerificationLevel level,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLevel2 = level == VerificationLevel.level2Pro;
    final badgeColor =
        isLevel2 ? const Color(0xFFF59E0B) : const Color(0xFF06B6D4);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isLevel2
                        ? Icons.shield_rounded
                        : Icons.check_circle_rounded,
                    color: badgeColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        level.label,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLevel2
                            ? 'Tier 2 Pro Counterparty'
                            : 'Tier 1 Verified Counterparty',
                        style: TextStyle(
                          fontSize: 12,
                          color: badgeColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              level.description,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                children: [
                  _buildDetailRow(
                    isDark,
                    Icons.badge_outlined,
                    'Government ID',
                    'Verified & Authenticated',
                  ),
                  const SizedBox(height: 10),
                  _buildDetailRow(
                    isDark,
                    Icons.fingerprint,
                    'Biometric Liveness',
                    isLevel2 ? 'Facial Match 99.8%' : 'Basic Verification',
                  ),
                  if (isLevel2) ...[
                    const SizedBox(height: 10),
                    _buildDetailRow(
                      isDark,
                      Icons.storefront_outlined,
                      'Merchant / Business Record',
                      'LTO / DTI Registered',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Close',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildDetailRow(
    bool isDark,
    IconData icon,
    String title,
    String value,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.darkText : AppColors.lightText,
          ),
        ),
      ],
    );
  }
}

