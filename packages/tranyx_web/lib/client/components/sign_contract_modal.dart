import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../services/web_interop.dart';

class SignContractModalComponent extends StatefulComponent {
  final TranyxAppState appState;
  final String title;
  final String contractTerms;
  final String rentalId;
  final bool isProperty;
  final VoidCallback onSigned;

  const SignContractModalComponent({
    required this.appState,
    required this.title,
    required this.contractTerms,
    required this.rentalId,
    required this.isProperty,
    required this.onSigned,
    super.key,
  });

  @override
  State<SignContractModalComponent> createState() => _SignContractModalState();
}

class _SignContractModalState extends State<SignContractModalComponent> {
  bool _isSigning = false;
  String? _error;
  String? _signatureHash;

  void _submitSignature() async {
    final canvasId = 'sign-contract-pad-${component.rentalId}';
    if (isSignaturePadEmptyJs(canvasId)) {
      setState(() => _error = 'Please draw your signature on the pad before proceeding.');
      return;
    }
    final signatureDataUrl = getSignatureDataUrlJs(canvasId);
    if (signatureDataUrl.isEmpty) {
      setState(() => _error = 'Could not capture signature. Please try again.');
      return;
    }

    // Compute SHA-256 signature hash for legal verification
    final uid = component.appState.userProfile?.uid ?? 'unknown';
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final hashInput = '$uid|${component.rentalId}|${component.contractTerms}|${component.title}|$timestamp';
    final hashBytes = sha256.convert(utf8.encode(hashInput));
    final hashHex = hashBytes.toString();

    setState(() {
      _isSigning = true;
      _error = null;
      _signatureHash = hashHex;
    });

    try {
      if (component.isProperty) {
        await component.appState.firestore.signPropertyContract(
          component.rentalId,
          signatureDataUrl,
          signatureHash: hashHex,
        );
      } else {
        await component.appState.firestore.signVehicleContract(
          component.rentalId,
          signatureDataUrl,
          signatureHash: hashHex,
        );
      }
      component.onSigned();
    } catch (e) {
      setState(() => _error = 'Signing failed: $e');
    } finally {
      setState(() => _isSigning = false);
    }
  }

  @override
  Component build(BuildContext context) {
    final isDark = component.appState.isDark;
    final canvasId = 'sign-contract-pad-${component.rentalId}';

    // Initialize signature pad after first paint
    Future.microtask(() => initSignaturePadJs(canvasId));

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-xl rounded-3xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh] '
              '${isDark ? "bg-zinc-900 border border-zinc-800 text-white" : "bg-white text-zinc-900 shadow-xl"}',
          [
            // Header
            div(
              classes:
                  'p-6 border-b ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center justify-between',
              [
                div([
                  h2(classes: 'text-xl font-black tracking-tight', [Component.text('Sign Agreement')]),
                  p(classes: 'text-xs text-zinc-500', [Component.text(component.title)]),
                ]),
                button(
                  classes: 'p-2 rounded-full hover:bg-zinc-800/20 transition-colors',
                  events: {'click': (_) => component.onSigned()}, // close modal
                  [lIcon('x', cls: 'w-6 h-6')],
                ),
              ],
            ),

            // Body
            div(classes: 'p-6 flex-1 overflow-y-auto space-y-5', [
              if (_error != null)
                div(classes: 'p-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-500 text-sm font-medium', [
                  Component.text(_error!),
                ]),

              p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                Component.text(
                  'Please read the agreement details and sign in the designated box below to activate the lease/rental.',
                ),
              ]),

              // Scrollable Terms
              div(
                classes:
                    'p-4 rounded-xl border border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-900/50 h-44 overflow-y-auto text-xs leading-relaxed ${isDark ? "text-zinc-400" : "text-zinc-600"}',
                [
                  p(classes: 'whitespace-pre-wrap', [Component.text(component.contractTerms)]),
                ],
              ),

              // Signature Canvas Box
              div([
                div(classes: 'flex items-center justify-between mb-2', [
                  label(
                    classes: 'block text-sm font-semibold ${isDark ? "text-zinc-300" : "text-zinc-700"}',
                    [Component.text('Draw your signature')],
                  ),
                  button(
                    classes: 'text-xs text-zinc-400 hover:text-red-400 underline transition-colors',
                    events: {'click': (_) => clearSignaturePadJs(canvasId)},
                    [Component.text('Clear')],
                  ),
                ]),
                div(
                  classes:
                      'rounded-2xl border-2 border-dashed ${isDark ? "border-zinc-700 bg-zinc-900/60" : "border-zinc-300 bg-zinc-50"} overflow-hidden',
                  [
                    Component.element(
                      tag: 'canvas',
                      id: canvasId,
                      classes: 'w-full touch-none cursor-crosshair block',
                      attributes: {'width': '500', 'height': '120'},
                    ),
                  ],
                ),
                p(classes: 'text-[10px] text-zinc-500 mt-1.5 flex items-center gap-1', [
                  lIcon('pen-tool', cls: 'w-3 h-3'),
                  Component.text('Sign using your mouse, trackpad, or touch screen'),
                ]),
              ]),

              // Signature hash display (shown after signing)
              if (_signatureHash != null)
                div(
                  classes: 'p-3 rounded-xl bg-green-500/10 border border-green-500/20 space-y-1',
                  [
                    p(classes: 'text-[10px] font-bold text-green-400 uppercase tracking-wider', [
                      Component.text('✓ Cryptographic Signature Hash (SHA-256)'),
                    ]),
                    p(
                      classes: 'text-[9px] font-mono text-green-300/80 break-all leading-relaxed',
                      [Component.text(_signatureHash!)],
                    ),
                    p(classes: 'text-[9px] text-zinc-500 mt-1', [
                      Component.text(
                        'This hash uniquely identifies this contract signing event and is stored on Firestore for legal verification.',
                      ),
                    ]),
                  ],
                ),
            ]),

            // Footer
            div(
              classes:
                  'p-6 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"} flex items-center justify-end gap-3',
              [
                button(
                  classes:
                      'px-5 py-2 rounded-xl font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-300 hover:bg-zinc-50"} transition-colors text-sm',
                  events: {'click': (_) => component.onSigned()},
                  [Component.text('Cancel')],
                ),
                button(
                  classes:
                      'px-6 py-2 rounded-xl font-bold text-white bg-green-500 hover:bg-green-600 transition-colors flex items-center gap-2 text-sm border-0 cursor-pointer',
                  events: {'click': (_) => _submitSignature()},
                  disabled: _isSigning,
                  [
                    if (_isSigning) lIcon('loader', cls: 'w-4 h-4 animate-spin'),
                    Component.text(_isSigning ? 'Activating...' : 'Sign & Activate'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
