import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_web/constants/category_data.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';

class CategoryModalComponent extends StatefulComponent {
  final TranyxAppState state;
  const CategoryModalComponent({required this.state, super.key});

  @override
  State<CategoryModalComponent> createState() => CategoryModalComponentState();
}

class CategoryModalComponentState extends State<CategoryModalComponent> {
  String _searchQuery = '';

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final bgCls = isDark ? 'bg-zinc-950/90' : 'bg-zinc-900/70';
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200';

    final lowercaseQuery = _searchQuery.trim().toLowerCase();
    final displayEntries = lowercaseQuery.isEmpty
        ? categoryMap.entries.toList()
        : categoryMap.entries
              .map((entry) {
                final group = entry.key;
                final categories = entry.value;

                final groupMatches = group.label.toLowerCase().contains(lowercaseQuery);
                final matchingCategories = categories.where((cat) {
                  return groupMatches || cat.label.toLowerCase().contains(lowercaseQuery);
                }).toList();

                return MapEntry(group, matchingCategories);
              })
              .where((entry) => entry.value.isNotEmpty)
              .toList();

    return div(
      classes: 'fixed inset-0 z-50 flex items-end md:items-center justify-center $bgCls backdrop-blur-sm',
      events: {'click': (_) => s.setState(() => s.showCategoryModal = false)},
      [
        div(
          classes:
              'w-full md:max-w-2xl max-h-[85vh] rounded-t-3xl md:rounded-3xl border flex flex-col overflow-hidden $cardCls',
          events: {
            'click': (e) {
              e.stopPropagation();
            },
          },
          [
            // Header
            div(
              classes:
                  'flex items-center justify-between px-6 py-5 border-b ${isDark ? "border-zinc-800" : "border-zinc-100"}',
              [
                h2(classes: 'text-lg font-bold', [Component.text('Browse Categories')]),
                button(
                  classes:
                      'p-2 rounded-xl ${isDark ? "bg-zinc-800 text-zinc-400 hover:text-white" : "bg-zinc-100 text-zinc-500"} transition-colors',
                  events: {'click': (_) => s.setState(() => s.showCategoryModal = false)},
                  [lIcon('x', cls: 'w-4 h-4')],
                ),
              ],
            ),

            // Search
            div(classes: 'px-6 py-4 border-b ${isDark ? "border-zinc-800" : "border-zinc-100"}', [
              div(
                classes:
                    'flex items-center gap-2 px-4 py-3 rounded-2xl ${isDark ? "bg-zinc-800" : "bg-zinc-50"} border ${isDark ? "border-zinc-700" : "border-zinc-200"}',
                [
                  lIcon('search', cls: 'w-4 h-4 ${isDark ? "text-zinc-600" : "text-zinc-400"}'),
                  input(
                    classes:
                        'bg-transparent border-none outline-none flex-1 text-sm ${isDark ? "text-white" : "text-zinc-900"}',
                    type: InputType.search,
                    attributes: {
                      'placeholder': 'Search categories...',
                      'value': _searchQuery,
                      'id': 'category-search-input',
                      'name': 'search',
                    },
                    events: {
                      'input': (e) {
                        setState(() {
                          _searchQuery = (e as dynamic).target.value as String? ?? '';
                        });
                      },
                    },
                  ),
                ],
              ),
            ]),

            // Groups + categories
            div(classes: 'flex-1 overflow-y-auto no-scrollbar px-6 py-4 space-y-6', [
              if (displayEntries.isEmpty)
                div(classes: 'text-center py-12 text-zinc-500 text-sm', [
                  Component.text('No categories match your search.'),
                ])
              else
                for (final entry in displayEntries)
                  div([
                    div(classes: 'flex items-center gap-2 mb-3', [
                      lIcon(entry.key.icon, cls: 'w-4 h-4 ${entry.key.color}'),
                      span(
                        classes:
                            'text-xs font-bold uppercase tracking-wider ${isDark ? "text-zinc-500" : "text-zinc-400"}',
                        [Component.text(entry.key.label)],
                      ),
                    ]),
                    div(classes: 'grid grid-cols-2 md:grid-cols-3 gap-2', [
                      for (final cat in entry.value)
                        button(
                          classes:
                              'flex items-center gap-2 p-3 rounded-xl border text-left transition-all card-hover ${isDark ? "bg-zinc-800/50 border-zinc-700 hover:border-indigo-500/50 text-zinc-300" : "bg-zinc-50 border-zinc-200 hover:border-indigo-400 text-zinc-700"}',
                          events: {
                            'click': (_) {
                              final isNyxian = s.currentViewMode == AccountType.nyxian;

                              if (isNyxian) {
                                s.handleHomeSearch(cat.label);
                                s.setState(() => s.showCategoryModal = false);
                                return;
                              }

                              s.selectedCategory = SelectedCategory(
                                id: cat.id,
                                label: cat.label,
                                iconName: cat.icon,
                                color: 'text-indigo-400',
                                hasTracker: cat.hasTracker,
                              );
                              s.selectedJobCategory = cat;
                              s.selectedJobCategoryGroup = entry.key;
                              s.postJobError = null;
                              if (cat.onSiteOnly) {
                                s.locType = LocType.onsite;
                              }

                              // Set tracker requirement based on category
                              // Groups 5 (Delivery) and 6 (Moving) require tracking, plus Towing (402)
                              final needsTracker = (cat.id >= 500 && cat.id < 700) || cat.id == 402;
                              s.hasTracker = needsTracker;

                              // Reset location data when category changes to avoid stale points
                              s.pickupLat = null;
                              s.pickupLng = null;
                              s.pickupAddress = '';
                              s.destinationLat = null;
                              s.destinationLng = null;
                              s.destinationAddress = '';

                              s.setState(() => s.showCategoryModal = false);
                            },
                          },
                          [
                            lIcon(cat.icon, cls: 'w-4 h-4 ${isDark ? "text-zinc-500" : "text-zinc-400"}'),
                            span(classes: 'text-sm truncate', [Component.text(cat.label)]),
                          ],
                        ),
                    ]),
                  ]),
            ]),
          ],
        ),
      ],
    );
  }
}
