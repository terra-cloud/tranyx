import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../constants/category_data.dart';

class JobCategorySelector extends StatelessComponent {
  final ValueChanged<CategoryItem> onCategorySelected;
  final CategoryItem? selectedCategory;

  const JobCategorySelector({
    required this.onCategorySelected,
    this.selectedCategory,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return div(classes: 'space-y-8', [
      for (var entry in categoryMap.entries)
        div(classes: 'animate-fade-up', [
          div(classes: 'flex items-center gap-3 mb-4', [
            div(classes: 'p-2 rounded-xl ${entry.key.tailwindColor}', [
              i([], classes: '', attributes: {'data-lucide': entry.key.icon}),
            ]),
            h3(classes: 'text-lg font-semibold text-zinc-100', [
              Component.text(entry.key.label),
            ]),
          ]),
          div(classes: 'grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3', [
            for (var category in entry.value)
              button(
                classes:
                    'flex flex-col items-center gap-3 p-4 rounded-2xl border transition-all duration-300 '
                    '${selectedCategory?.id == category.id ? 'bg-indigo-600/10 border-indigo-500 shadow-[0_0_20px_rgba(79,70,229,0.1)]' : 'bg-zinc-900/50 border-zinc-800 hover:border-zinc-700 hover:bg-zinc-900'}',
                onClick: () => onCategorySelected(
                  CategoryItem(
                    id: category.id,
                    label: category.label,
                    icon: category.icon,
                    hasTracker: category.hasTracker,
                  ),
                ),
                [
                  div(
                    classes:
                        'p-2.5 rounded-full ${selectedCategory?.id == category.id ? 'bg-indigo-500 text-white' : 'bg-zinc-800 text-zinc-400'}',
                    [
                      i([], classes: 'w-5 h-5', attributes: {'data-lucide': category.icon}),
                    ],
                  ),
                  span(
                    classes:
                        'text-sm font-medium text-center ${selectedCategory?.id == category.id ? 'text-indigo-400' : 'text-zinc-400'}',
                    [
                      Component.text(category.label),
                    ],
                  ),
                ],
              ),
          ]),
        ]),
    ]);
  }
}
