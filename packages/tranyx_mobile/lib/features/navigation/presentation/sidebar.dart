import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/navigation/providers/navigation_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);

    return Container(
      width: 96,
      decoration: BoxDecoration(
        color: isDarkMode
            ? AppColors.darkCard.withValues(alpha: 0.5)
            : AppColors.lightCard,
        border: Border(
          right: BorderSide(
            color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(height: 32),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/images/logo.png',
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.indigo, AppColors.purple],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.widgets,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
            Column(
              children: [
                const SizedBox(height: 48),
                const _SidebarItem(icon: Icons.home_filled, tabKey: 'home'),
                const SizedBox(height: 16),
                const _SidebarItem(icon: Icons.work, tabKey: 'jobs'),
                const SizedBox(height: 16),
                const _SidebarItem(
                  icon: Icons.directions_car,
                  tabKey: 'transit',
                ),
                const SizedBox(height: 16),
                const _SidebarItem(icon: Icons.person, tabKey: 'profile'),
              ],
            ),
            IconButton(
              onPressed: () {
                ref.read(authControllerProvider).signOut();
                ref.read(authViewProvider.notifier).state = 'login';
                ref.read(activeTabProvider.notifier).state = 'home';
              },
              icon: const Icon(Icons.logout, color: AppColors.red),
              tooltip: "Log Out",
              padding: const EdgeInsets.all(16),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends ConsumerWidget {
  final IconData icon;
  final String tabKey;

  const _SidebarItem({required this.icon, required this.tabKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(activeTabProvider);
    final isDarkMode = ref.watch(themeModeProvider);
    final isActive = activeTab == tabKey;

    return GestureDetector(
      onTap: () => NavigationNotifier.switchTab(ref, tabKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive
              ? (isDarkMode
                    ? AppColors.indigo.withValues(alpha: 0.2)
                    : AppColors.indigo.withValues(alpha: 0.1))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          color: isActive
              ? AppColors.indigo
              : (isDarkMode
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted),
          size: 28,
        ),
      ),
    );
  }
}
