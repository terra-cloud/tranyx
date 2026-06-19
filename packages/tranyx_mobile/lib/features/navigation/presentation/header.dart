import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/core/providers/notifications_provider.dart';
import 'package:tranyx_mobile/core/router/app_router.dart';

class Header extends ConsumerWidget {
  final bool isTablet;

  const Header({super.key, required this.isTablet});

  void _showNotificationsBottomSheet(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.read(themeModeProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, child) {
            final notifsAsync = ref.watch(notificationsStreamProvider);
            final user = ref.read(userProvider);

            return Container(
              height: MediaQuery.of(sheetContext).size.height * 0.7,
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(
                  color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Notifications',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        if (user != null)
                          TextButton(
                            onPressed: () {
                              ref.read(notificationServiceProvider).markAllAsRead(user.uid);
                            },
                            child: const Text('Mark all as read'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  Expanded(
                    child: notifsAsync.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, stack) => Center(child: Text('Error: $err')),
                      data: (list) {
                        if (list.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.notifications_off_outlined,
                                  size: 64,
                                  color: isDarkMode ? Colors.white30 : Colors.black26,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No notifications yet',
                                  style: TextStyle(
                                    color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final item = list[index];
                            final id = item['id'] as String;
                            final title = item['title'] as String? ?? 'Notification';
                            final message = item['message'] as String? ?? '';
                            final isRead = item['isRead'] as bool? ?? false;
                            final jobId = item['jobId'] as String?;

                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: isRead
                                    ? Colors.transparent
                                    : (isDarkMode ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02)),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isRead
                                        ? Colors.transparent
                                        : AppColors.indigo.withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.notifications_active_outlined,
                                    color: isRead ? Colors.grey : AppColors.indigo,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  title,
                                  style: TextStyle(
                                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    message,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                                    ),
                                  ),
                                ),
                                trailing: !isRead
                                    ? Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppColors.indigo,
                                          shape: BoxShape.circle,
                                        ),
                                      )
                                    : null,
                                onTap: () async {
                                  Navigator.pop(sheetContext); // Close bottom sheet
                                  await ref.read(notificationServiceProvider).markAsRead(id);
                                  if (jobId != null) {
                                    // Navigate to the job details page
                                    ref.read(routerProvider).go('/job/$jobId');
                                  }
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);
    final currentViewMode = ref.watch(currentViewModeProvider);
    final unreadCount = ref.watch(unreadNotificationsCountProvider);

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 16,
            bottom: 16,
            left: 24,
            right: 24,
          ),
          decoration: BoxDecoration(
            color: (isDarkMode ? AppColors.darkBg : AppColors.lightBg)
                .withValues(alpha: 0.8),
            border: Border(
              bottom: BorderSide(
                color: isDarkMode
                    ? AppColors.darkBorder
                    : AppColors.lightBorder,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (!isTablet) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 30,
                        height: 30,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.indigo, AppColors.purple],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.widgets,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Tranyx",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? AppColors.darkText
                            : AppColors.lightText,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          (currentViewMode == AccountType.hybrid
                                  ? AppColors.amber
                                  : (currentViewMode == AccountType.employer
                                        ? AppColors.blue
                                        : AppColors.green))
                              .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${currentViewMode.label} View',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: currentViewMode == AccountType.hybrid
                            ? AppColors.amber
                            : (currentViewMode == AccountType.employer
                                  ? AppColors.blue
                                  : AppColors.green),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      isDarkMode ? Icons.light_mode : Icons.dark_mode,
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                    onPressed: () =>
                        ref.read(themeModeProvider.notifier).toggleTheme(),
                  ),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.notifications_none,
                          color: isDarkMode
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
                        ),
                        onPressed: () => _showNotificationsBottomSheet(context, ref),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

