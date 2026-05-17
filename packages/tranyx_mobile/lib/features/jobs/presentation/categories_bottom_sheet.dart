import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/utils/enums.dart';
import 'package:tranyx_mobile/core/utils/string_extension.dart';
import 'package:tranyx_mobile/features/jobs/providers/jobs_provider.dart';
import 'package:tranyx_mobile/features/navigation/providers/navigation_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class CategoriesBottomSheet extends ConsumerStatefulWidget {
  const CategoriesBottomSheet({super.key});

  @override
  ConsumerState<CategoriesBottomSheet> createState() =>
      _CategoriesBottomSheetState();
}

class _CategoriesBottomSheetState extends ConsumerState<CategoriesBottomSheet> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final categoryMap = JobCategoryGroupExtension.categoryMap;

    // Filter categories based on search query
    Map<JobCategoryGroup, List<JobCategory>> filteredMap = {};
    if (_searchQuery.isEmpty) {
      filteredMap = categoryMap;
    } else {
      for (var entry in categoryMap.entries) {
        final matchingCategories = entry.value
            .where(
              (cat) =>
                  cat.label.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ) ||
                  entry.key.label.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ),
            )
            .toList();

        if (matchingCategories.isNotEmpty) {
          filteredMap[entry.key] = matchingCategories;
        }
      }
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "All Categories",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.x),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? AppColors.darkBorder.withValues(alpha: 0.5)
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: const InputDecoration(
                  icon: Icon(LucideIcons.search, size: 20),
                  hintText: "Search services...",
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Categories List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
              itemCount: filteredMap.length,
              itemBuilder: (context, index) {
                final group = filteredMap.keys.elementAt(index);
                final categories = filteredMap[group]!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Icon(group.iconData, color: group.colorValue, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              group.label,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: group.colorValue,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categories
                          .map(
                            (cat) => _CategoryChip(
                              category: cat,
                              onTap: () {
                                ref
                                        .read(jobSearchFilterProvider.notifier)
                                        .state =
                                    cat;
                                ref.read(jobsViewProvider.notifier).state =
                                    'list';
                                ref.read(activeTabProvider.notifier).state =
                                    'jobs';
                                Navigator.pop(context);
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends ConsumerWidget {
  final JobCategory category;
  final VoidCallback onTap;

  const _CategoryChip({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isDarkMode
              ? AppColors.darkBorder.withValues(alpha: 0.3)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDarkMode ? AppColors.darkBorder : Colors.grey[200]!,
          ),
          boxShadow: [
            if (!isDarkMode)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.iconData, size: 14, color: AppColors.indigo),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                category.label.capitalizeWords(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
