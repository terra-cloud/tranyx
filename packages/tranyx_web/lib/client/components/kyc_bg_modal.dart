import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../services/web_interop.dart';
import '../../services/firebase_service.dart';

class KycBgModalComponent extends StatefulComponent {
  final TranyxAppState state;
  const KycBgModalComponent({required this.state, super.key});

  @override
  State<KycBgModalComponent> createState() => _KycBgModalState();
}

class _KycBgModalState extends State<KycBgModalComponent> {
  String _clearanceType = "NBI Clearance";
  String _clearanceNumber = "";
  String _expiryDate = "";
  String _documentUrl = "";

  bool _isUploadingDocument = false;
  String? _error;

  final List<String> _clearanceTypes = [
    "NBI Clearance",
    "Police Clearance",
  ];

  Future<void> _handleFileSelected(web.Event event) async {
    setState(() {
      _error = null;
      _isUploadingDocument = true;
    });

    try {
      final files = await readFilesFromEvent(event);
      if (files.isEmpty) return;

      final file = files.first;
      final token = SessionStorage.idToken;
      final url = await ImgBBService(currentFirebaseConfig, idToken: token).uploadImageBytes(file.bytes, file.name);

      if (url != null) {
        setState(() {
          _documentUrl = url;
        });
      } else {
        setState(() => _error = 'Failed to upload document image. Please try again.');
      }
    } catch (e) {
      setState(() => _error = 'Upload error: $e');
    } finally {
      setState(() {
        _isUploadingDocument = false;
      });
    }
  }

  void _submit() {
    if (_clearanceNumber.trim().isEmpty) {
      setState(() => _error = 'Please enter your clearance Reference Number.');
      return;
    }
    if (_expiryDate.isEmpty) {
      setState(() => _error = 'Please enter or select the Clearance Expiry Date.');
      return;
    }
    if (_documentUrl.isEmpty) {
      setState(() => _error = 'Please upload a photo of your NBI or Police Clearance certificate.');
      return;
    }

    // Try parsing date simple check
    try {
      final parts = _expiryDate.split('-');
      if (parts.length == 3) {
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);
        final exp = DateTime(year, month, day);
        if (exp.isBefore(DateTime.now())) {
          setState(() => _error = 'Your clearance document has already expired.');
          return;
        }
      }
    } catch (_) {}

    component.state.submitBackgroundCheck(
      clearanceType: _clearanceType,
      clearanceNumber: _clearanceNumber.trim(),
      expiryDate: _expiryDate,
      documentUrl: _documentUrl,
    );
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final bgCls = isDark ? 'bg-zinc-950 border-zinc-800' : 'bg-white border-zinc-200';
    final textCls = isDark ? 'text-white' : 'text-zinc-900';
    final subTextCls = isDark ? 'text-zinc-400' : 'text-zinc-500';
    final inputCls = 'w-full p-3 rounded-xl border outline-none transition-all '
        '${isDark ? "bg-zinc-900 border-zinc-800 text-white focus:border-indigo-500/50" : "bg-white border-zinc-200 text-zinc-900 focus:border-indigo-500"}';

    return div(
      classes: 'fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm overflow-y-auto',
      [
        div(
          classes: 'w-full max-w-xl rounded-3xl border shadow-2xl flex flex-col my-8 animate-scale-up $bgCls',
          [
            // Header
            div(
              classes: 'p-6 border-b flex items-center justify-between ${isDark ? "border-zinc-800" : "border-zinc-100"}',
              [
                div([
                  h2(classes: 'text-xl font-black tracking-tight $textCls', [Component.text('Background Clearance')]),
                  p(classes: 'text-xs $subTextCls mt-1', [Component.text('Submit NBI or Police Clearance for verification.')]),
                ]),
                button(
                  classes: 'p-2 rounded-full hover:bg-zinc-500/20 transition-colors',
                  events: {'click': (_) => s.setState(() => s.showKycBgModal = false)},
                  [lIcon('x', cls: 'w-5 h-5 $subTextCls')],
                ),
              ],
            ),

            // Form Content
            div(
              classes: 'p-6 space-y-5 flex-1 overflow-y-auto max-h-[65vh]',
              [
                if (_error != null)
                  div(
                    classes: 'p-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 text-xs font-semibold flex items-center gap-2',
                    [
                      lIcon('alert-triangle', cls: 'w-4 h-4 shrink-0'),
                      Component.text(_error!),
                    ],
                  ),

                // Clearance Type Dropdown
                div(
                  classes: 'space-y-1.5',
                  [
                    label(classes: 'text-xs font-bold $subTextCls', [Component.text('Clearance Certificate Type')]),
                    select(
                      classes: inputCls,
                      events: {
                        'change': (e) {
                          setState(() {
                            _clearanceType = getInputValue(e.target);
                          });
                        }
                      },
                      [
                        for (final type in _clearanceTypes)
                          option(
                            attributes: {'value': type, if (type == _clearanceType) 'selected': 'true'},
                            [Component.text(type)],
                          ),
                      ],
                    ),
                  ],
                ),

                // Reference / Control Number
                div(
                  classes: 'space-y-1.5',
                  [
                    label(classes: 'text-xs font-bold $subTextCls', [Component.text('Clearance Reference Number')]),
                    input(
                      type: InputType.text,
                      classes: inputCls,
                      attributes: {
                        'placeholder': 'Enter NBI clearance code or reference number',
                        'value': _clearanceNumber,
                      },
                      events: {
                        'input': (e) => setState(() => _clearanceNumber = getInputValue(e.target)),
                      },
                    ),
                  ],
                ),

                // Expiry Date (type="date" works natively on all modern browsers)
                div(
                  classes: 'space-y-1.5',
                  [
                    label(classes: 'text-xs font-bold $subTextCls', [Component.text('Clearance Expiry Date')]),
                    input(
                      type: InputType.date,
                      classes: inputCls,
                      attributes: {
                        'value': _expiryDate,
                      },
                      events: {
                        'input': (e) => setState(() => _expiryDate = getInputValue(e.target)),
                      },
                    ),
                  ],
                ),

                // Clearance Photo Upload Box
                div(
                  classes: 'space-y-2',
                  [
                    p(classes: 'text-xs font-bold $subTextCls', [Component.text('Upload Clearance Document Photo')]),
                    div(
                      classes: 'relative aspect-video rounded-2xl overflow-hidden border border-dashed ${isDark ? "border-zinc-800 bg-zinc-900/30" : "border-zinc-200 bg-zinc-50/50"} flex items-center justify-center',
                      [
                        label(
                          classes: 'w-full h-full flex flex-col items-center justify-center cursor-pointer transition-opacity hover:opacity-90',
                          attributes: {'for': 'kyc-bg-file-input'},
                          [
                            input(
                              type: InputType.file,
                              classes: 'hidden',
                              attributes: {
                                'id': 'kyc-bg-file-input',
                                'accept': 'image/*,application/pdf',
                                'style': 'display: none;',
                              },
                              events: {
                                'change': _handleFileSelected,
                              },
                            ),
                            if (_documentUrl.isNotEmpty)
                              img(
                                src: _documentUrl,
                                classes: 'w-full h-full object-cover',
                                attributes: {'alt': 'Clearance document preview'},
                              )
                            else ...[
                              lIcon('upload-cloud', cls: 'w-8 h-8 mb-2 ${isDark ? "text-zinc-500" : "text-zinc-400"}'),
                              p(classes: 'text-xs font-semibold ${isDark ? "text-zinc-400" : "text-zinc-500"} text-center px-4', [
                                Component.text('Click to upload clearance image (JPEG or PNG)'),
                              ]),
                            ],
                            if (_isUploadingDocument)
                              div(
                                classes: 'absolute inset-0 bg-black/60 flex flex-col items-center justify-center text-white backdrop-blur-[2px] z-10 animate-fade-in',
                                [
                                  lIcon('loader', cls: 'w-6 h-6 animate-spin mb-2 text-purple-400'),
                                  p(classes: 'text-xs font-semibold', [Component.text('Uploading...')]),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),

            // Footer / Actions
            div(
              classes: 'p-6 border-t flex items-center justify-end gap-3 ${isDark ? "border-zinc-800 bg-zinc-900/10" : "border-zinc-100 bg-zinc-50/20"} rounded-b-3xl',
              [
                button(
                  classes: 'px-4 py-2.5 rounded-xl text-xs font-bold ${isDark ? "hover:bg-zinc-800 text-zinc-400" : "hover:bg-zinc-100 text-zinc-650"} transition-all cursor-pointer border-0 bg-transparent',
                  events: {'click': (_) => s.setState(() => s.showKycBgModal = false)},
                  [Component.text('Cancel')],
                ),
                button(
                  classes: 'px-6 py-2.5 rounded-xl text-xs font-bold text-white logo-gradient hover:opacity-95 transition-all flex items-center gap-1.5 cursor-pointer border-0',
                  events: s.isLoadingKyc ? {} : {'click': (_) => _submit()},
                  [
                    if (s.isLoadingKyc) lIcon('loader-2', cls: 'w-3.5 h-3.5 animate-spin'),
                    Component.text(s.isLoadingKyc ? 'Submitting...' : 'Submit Clearance'),
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
