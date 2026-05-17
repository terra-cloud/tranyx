import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';

class Header extends ConsumerWidget {
  final bool isTablet;

  const Header({super.key, required this.isTablet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);
    // final accountType = ref.watch(accountTypeProvider);
    final currentViewMode = ref.watch(currentViewModeProvider);
    // debugPrint(accountType.label.toString());

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
                    Container(
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
                  // Container(
                  //   padding: const EdgeInsets.symmetric(
                  //     horizontal: 8,
                  //     vertical: 4,
                  //   ),
                  // decoration: BoxDecoration(
                  //   color:
                  //       (accountType == AccountType.hybrid
                  //               ? AppColors.amber
                  //               : (accountType != AccountType.employer
                  //                     ? AppColors.blue
                  //                     : AppColors.green))
                  //           .withValues(alpha: 0.2),
                  //   borderRadius: BorderRadius.circular(6),
                  // ),
                  //   child: Text(
                  //     "${currentViewMode == AccountType.nyxian ? 'Nyxian' : currentViewMode.label} View"
                  //         .toUpperCase(),
                  // style: TextStyle(
                  //   fontSize: 10,
                  //   fontWeight: FontWeight.bold,
                  //   color: accountType == AccountType.hybrid
                  //       ? AppColors.amber
                  //       : (accountType != AccountType.employer
                  //             ? AppColors.blue
                  //             : AppColors.green),
                  // ),
                  //   ),
                  // ),
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
                  IconButton(
                    icon: Icon(
                      Icons.notifications_none,
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                    onPressed: () {},
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
