import 'package:flutter/material.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';

class JobSubHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final bool isDarkMode;

  const JobSubHeader({
    super.key,
    required this.title,
    required this.onBack,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        children: [
          IconButton.filled(
            icon: Icon(
              Icons.arrow_back,
              color: isDarkMode ? AppColors.darkText : AppColors.lightText,
            ),
            style: ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(
                (isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted)
                    .withValues(alpha: .25),
              ),
            ),
            onPressed: onBack,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? AppColors.darkText : AppColors.lightText,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
