import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/jobs/providers/jobs_provider.dart';

class JobSuccessView extends ConsumerWidget {
  const JobSuccessView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: AppColors.green,
              size: 64,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Success!",
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Action completed successfully.",
            style: TextStyle(
              color: isDarkMode
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 32),
          UIHelpers.buildPrimaryButton(
            "Back to Jobs",
            () => ref.read(jobsViewProvider.notifier).state = 'list',
            isDarkMode,
            isOutlined: true,
          ),
        ],
      ),
    );
  }
}
