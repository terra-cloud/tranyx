import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';

class PaymentModalComponent extends StatelessComponent {
  final TranyxAppState state;
  const PaymentModalComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final amount = s.depositAmount;

    return div(
      classes: 'fixed inset-0 z-[100] flex items-center justify-center bg-zinc-950/80 backdrop-blur-md px-4',
      [
        div(
          classes:
              'w-full max-w-md rounded-3xl border ${isDark ? "bg-zinc-900 border-zinc-800 shadow-2xl" : "bg-white border-zinc-200 shadow-xl"} overflow-hidden animate-fade-up',
          [
            // Header
            div(classes: 'p-6 text-center border-b ${isDark ? "border-zinc-800" : "border-zinc-100"}', [
              div(classes: 'w-16 h-16 rounded-2xl bg-indigo-500/10 flex items-center justify-center mx-auto mb-4', [
                lIcon('wallet', cls: 'w-8 h-8 text-indigo-400'),
              ]),
              h2(classes: 'text-xl font-bold mb-1', [Component.text('Top-up Tyxbit Balance')]),
              p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                Component.text('Your balance is insufficient. Top up now to post this job.'),
              ]),
            ]),

            // Body
            div(classes: 'p-8 space-y-6', [
              div(classes: 'text-center', [
                span(classes: 'text-sm font-medium ${isDark ? "text-zinc-500" : "text-zinc-400"} block mb-1', [
                  Component.text('Top-up Amount (₱)'),
                ]),
                div(classes: 'flex items-center justify-center gap-2 border-b-2 border-indigo-500/30 pb-2 mx-8', [
                  input(
                    type: InputType.number,
                    classes:
                        'w-full text-center text-4xl font-black text-indigo-400 bg-transparent border-none focus:outline-none placeholder:text-indigo-400/30',
                    value: amount > 0 ? amount.toString() : '',
                    attributes: {
                      'placeholder': '0.00',
                      'min': '1',
                      'step': '1',
                      'id': 'topup-amount-input',
                      'name': 'amount',
                    },
                    events: {
                      'input': (e) {
                        final val = (e.target as dynamic).value?.toString() ?? '';
                        s.setState(() => s.depositAmount = double.tryParse(val) ?? 0.0);
                      },
                    },
                  ),
                ]),
                span(classes: 'text-xs text-indigo-400/60 mt-3 block', [
                  Component.text('1 Tyxbit = 1 Peso (₱)'),
                ]),
              ]),

              div(classes: 'p-4 rounded-2xl ${isDark ? "bg-zinc-800/50" : "bg-zinc-50"} space-y-3', [
                _infoRow('Payment Method', 'Xendit Gateway', isDark),
                _infoRow('Tyxbit Equivalent', '${amount.toStringAsFixed(2)} Tyxbits', isDark),
                _infoRow('Status', 'Awaiting Top-up', isDark),
              ]),

              div(classes: 'space-y-3', [
                if (s.pendingXenditInvoiceId != null) ...[
                  button(
                    classes:
                        'w-full py-4 rounded-2xl font-bold text-white bg-green-500 hover:bg-green-600 transition-colors flex items-center justify-center gap-2',
                    events: {
                      'click': (_) => s.verifyXenditPayment(),
                    },
                    [
                      if (s.isVerifyingPayment) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                      Component.text(s.isVerifyingPayment ? 'Verifying...' : 'I already paid'),
                    ],
                  ),
                  if (s.postJobError != null)
                    p(classes: 'text-xs text-red-400 text-center mt-2 font-semibold', [
                      Component.text(s.postJobError!),
                    ]),
                  button(
                    classes:
                        'w-full py-4 rounded-2xl font-bold ${isDark ? "text-zinc-400 hover:text-zinc-200" : "text-zinc-500 hover:text-zinc-700"} transition-colors',
                    events: {
                      'click': (_) => s.setState(() {
                        s.pendingXenditInvoiceId = null;
                        s.showDepositModal = false;
                      }),
                    },
                    [Component.text('Cancel')],
                  ),
                ] else ...[
                  button(
                    classes:
                        'w-full py-4 rounded-2xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
                    events: {
                      'click': (_) => s.createXenditInvoice(),
                    },
                    [
                      if (s.isDepositing) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                      Component.text(s.isDepositing ? 'Processing...' : 'Pay with Xendit'),
                    ],
                  ),
                  if (s.postJobError != null)
                    p(classes: 'text-xs text-red-400 text-center mt-2 font-semibold', [
                      Component.text(s.postJobError!),
                    ]),
                  button(
                    classes:
                        'w-full py-4 rounded-2xl font-bold ${isDark ? "text-zinc-400 hover:text-zinc-200" : "text-zinc-500 hover:text-zinc-700"} transition-colors',
                    events: {
                      'click': (_) => s.setState(() => s.showDepositModal = false),
                    },
                    [Component.text('Cancel')],
                  ),
                ],
              ]),
            ]),

            // Footer
            div(classes: 'p-4 bg-zinc-500/5 text-center', [
              p(
                classes:
                    'text-[10px] uppercase tracking-widest font-bold ${isDark ? "text-zinc-600" : "text-zinc-400"}',
                [
                  Component.text('Powered by Xendit & Tranyx Secure'),
                ],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  Component _infoRow(String label, String value, bool isDark) {
    return div(classes: 'flex justify-between items-center', [
      span(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-400"}', [Component.text(label)]),
      span(classes: 'text-xs font-bold', [Component.text(value)]),
    ]);
  }
}
