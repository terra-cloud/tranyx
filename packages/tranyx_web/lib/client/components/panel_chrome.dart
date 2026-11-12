import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../../components/ui_helpers.dart';

/// Rentals side panel: back arrow row at the top of the panel (steps go back one step, step 1 closes).
Component rentalPanelBackRow({required bool isDark, required String label, required void Function() onBack}) {
  return div(
    classes: 'px-4 pt-3 pb-1 flex-none',
    [
      button(
        classes:
            'inline-flex items-center gap-1 text-sm font-medium bg-transparent border-0 p-1 -ml-1 cursor-pointer '
            '${isDark ? "text-indigo-300 hover:text-indigo-200" : "text-[#4f46e5] hover:text-indigo-700"}',
        attributes: {'type': 'button', 'aria-label': 'Back'},
        events: {'click': (_) => onBack()},
        [lIcon('arrow-left', cls: 'w-4 h-4'), Component.text(label)],
      ),
    ],
  );
}
