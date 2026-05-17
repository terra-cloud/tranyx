import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/navigation/providers/navigation_provider.dart';

class BottomNav extends ConsumerWidget {
  const BottomNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: (isDarkMode ? AppColors.darkBg : AppColors.lightCard)
                .withValues(alpha: 0.9),
            border: Border(
              top: BorderSide(
                color: isDarkMode
                    ? AppColors.darkBorder
                    : AppColors.lightBorder,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                _NavItem(
                  icon: Icons.home_filled,
                  label: "Home",
                  tabKey: 'home',
                ),
                _NavItem(icon: Icons.work, label: "Jobs", tabKey: 'jobs'),
                _NavItem(
                  icon: Icons.directions_car,
                  label: "Transit",
                  tabKey: 'transit',
                ),
                _NavItem(
                  icon: Icons.person,
                  label: "Profile",
                  tabKey: 'profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends ConsumerWidget {
  final IconData icon;
  final String label;
  final String tabKey;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.tabKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(activeTabProvider);
    final isDarkMode = ref.watch(themeModeProvider);
    final isActive = activeTab == tabKey;
    final color = isActive
        ? (isDarkMode ? Colors.white : AppColors.indigo)
        : (isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted);

    return GestureDetector(
      onTap: () => NavigationNotifier.switchTab(ref, tabKey),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              transform: Matrix4.translationValues(0, isActive ? -4 : 0, 0),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 4),
            AnimatedOpacity(
              opacity: isActive ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
