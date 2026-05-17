import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_provider.dart';

class TransitView extends ConsumerWidget {
  final bool isTablet;

  const TransitView({super.key, required this.isTablet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);
    final transitMode = ref.watch(transitModeProvider);

    Widget buildToggleBtn(
      String text,
      IconData icon,
      bool isActive,
      VoidCallback onTap,
    ) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? (isDarkMode ? AppColors.darkBorder : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive
                    ? (isDarkMode ? Colors.white : AppColors.lightText)
                    : (isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted),
              ),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? (isDarkMode ? Colors.white : AppColors.lightText)
                      : (isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildVehicleCard(
      String model,
      String type,
      String price,
      String distance,
    ) {
      return Container(
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
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.darkBorder : AppColors.lightBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.directions_car,
                size: 32,
                color: isDarkMode
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? AppColors.darkText
                          : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    type,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        price,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.indigo,
                        ),
                      ),
                      Text(
                        distance,
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
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDarkMode
                ? AppColors.darkCard
                : AppColors.lightBorder.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: buildToggleBtn(
                  "Rent a Vehicle",
                  Icons.directions_car,
                  transitMode == 'rent',
                  () => ref.read(transitModeProvider.notifier).state = 'rent',
                ),
              ),
              Expanded(
                child: buildToggleBtn(
                  "Host (My Garage)",
                  Icons.garage,
                  transitMode == 'host',
                  () => ref.read(transitModeProvider.notifier).state = 'host',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        if (transitMode == 'rent') ...[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? AppColors.purple.withValues(alpha: 0.1)
                  : AppColors.purple.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.purple.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.purple,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "ACTIVE RENTAL",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            color: AppColors.purple,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      "Due in 2 hours",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  "Tesla Model 3",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode
                        ? AppColors.darkText
                        : AppColors.lightText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Pickup/Dropoff at 1280 Silicon Ave",
                  style: TextStyle(
                    fontSize: 14,
                    color: isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.purple.withValues(
                            alpha: 0.2,
                          ),
                          foregroundColor: AppColors.purple,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text("Extend Time"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.purple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text("Return Key"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          UIHelpers.buildTextField(
            Icons.location_on_outlined,
            "Current Location...",
            isDarkMode,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: isTablet ? 300 : double.infinity,
                child: buildVehicleCard(
                  "Tesla Model 3",
                  "Electric • 4 Seats",
                  "₱80/day",
                  "0.8 mi away",
                ),
              ),
              SizedBox(
                width: isTablet ? 300 : double.infinity,
                child: buildVehicleCard(
                  "Ford Transit Van",
                  "Cargo • Moving",
                  "₱120/day",
                  "2.1 mi away",
                ),
              ),
            ],
          ),
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
              border: Border.all(
                color: isDarkMode
                    ? AppColors.darkBorder
                    : AppColors.lightBorder,
              ),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDarkMode ? AppColors.darkBg : AppColors.lightBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.directions_car,
                    size: 48,
                    color: isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  "Turn your vehicle into earnings",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode
                        ? AppColors.darkText
                        : AppColors.lightText,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "List your car or truck for others to rent when you're not using it.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDarkMode
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
                const SizedBox(height: 32),
                UIHelpers.buildPrimaryButton(
                  "List a Vehicle",
                  () {},
                  isDarkMode,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
