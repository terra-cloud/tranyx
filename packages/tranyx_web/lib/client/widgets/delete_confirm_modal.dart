import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';

class DeleteConfirmModalComponent extends StatelessComponent {
  final TranyxAppState state;
  const DeleteConfirmModalComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final jobId = s.selectedJobData?['id'] as String? ?? '';
    final budget = (s.selectedJobData?['pricingValue'] as num?)?.toDouble() ?? 0.0;

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-md animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-md rounded-3xl border p-6 relative overflow-hidden transition-all duration-300 '
              '${isDark ? "bg-zinc-900 border-zinc-800 text-white" : "bg-white border-zinc-200 text-zinc-800 shadow-2xl"}',
          [
            // Close button
            button(
              classes: 'absolute top-4 right-4 p-1.5 rounded-xl hover:bg-zinc-500/10 transition-colors',
              events: {'click': (_) => s.setState(() => s.showDeleteConfirm = false)},
              [lIcon('x', cls: 'w-5 h-5 ${isDark ? "text-zinc-400" : "text-zinc-500"}')],
            ),

            // Header
            div(classes: 'flex flex-col items-center text-center gap-2 mb-6 mt-4', [
              div(
                classes: 'p-4 rounded-full bg-red-500/15 text-red-500 mb-2 border border-red-500/20',
                [lIcon('alert-triangle', cls: 'w-10 h-10 animate-bounce')],
              ),
              h3(classes: 'text-2xl font-bold tracking-tight', [
                Component.text('Delete Posting?'),
              ]),
              p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-500"} px-4 leading-relaxed', [
                Component.text('Are you sure you want to delete this job posting? This action cannot be undone.'),
              ]),
            ]),

            // Escrow info box
            div(
              classes:
                  'p-4 rounded-2xl border mb-6 flex flex-col gap-1.5 '
                  '${isDark ? "bg-zinc-950/40 border-zinc-800 text-zinc-300" : "bg-zinc-50 border-zinc-200 text-zinc-700"}',
              [
                div(classes: 'flex justify-between items-center text-sm', [
                  span([Component.text('Held Escrow:')]),
                  span(classes: 'font-bold text-green-500', [
                    Component.text('₱ ${budget.toStringAsFixed(0)}'),
                  ]),
                ]),
                p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-400"} mt-1 leading-normal', [
                  Component.text('The escrow funds will be immediately refunded back to your wallet balance upon deletion.'),
                ]),
              ],
            ),

            // Action Buttons
            div(classes: 'flex flex-col gap-2.5', [
              button(
                classes: s.isUpdatingJobStatus
                    ? 'w-full py-4 rounded-2xl font-bold text-white bg-red-500/50 cursor-not-allowed text-center'
                    : 'w-full py-4 rounded-2xl font-bold text-white bg-red-600 hover:bg-red-500 transition-colors flex items-center justify-center gap-2',
                events: s.isUpdatingJobStatus
                    ? {}
                    : {'click': (_) => s.handleDeletePosting(jobId)},
                [
                  if (s.isUpdatingJobStatus) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
                  Component.text(s.isUpdatingJobStatus ? 'Deleting...' : 'Delete & Refund Escrow'),
                ],
              ),
              button(
                classes:
                    'w-full py-3.5 rounded-2xl font-semibold text-center transition-colors '
                    '${isDark ? "text-zinc-400 hover:text-white bg-zinc-800/40 hover:bg-zinc-800" : "text-zinc-500 hover:text-zinc-700 bg-zinc-50 hover:bg-zinc-100"}',
                events: {'click': (_) => s.setState(() => s.showDeleteConfirm = false)},
                [Component.text('Cancel')],
              ),
            ]),
          ],
        ),
      ],
    );
  }
}
