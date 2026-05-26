import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../services/web_interop.dart';
import '../../services/firebase_service.dart';

class KycIdModalComponent extends StatefulComponent {
  final TranyxAppState state;
  const KycIdModalComponent({required this.state, super.key});

  @override
  State<KycIdModalComponent> createState() => _KycIdModalState();
}

class _KycIdModalState extends State<KycIdModalComponent> {
  String _idType = "Driver's License";
  String _idNumber = "";
  String _frontUrl = "";
  String _backUrl = "";
  String _selfieUrl = "";

  bool _isUploadingFront = false;
  bool _isUploadingBack = false;
  bool _isUploadingSelfie = false;
  String? _error;

  final List<String> _philippineIds = [
    "Driver's License",
    "Philippine Passport",
    "Unified Multi-Purpose ID (UMID)",
    "Social Security System (SSS) ID",
    "GSIS ID",
    "Philippine National ID (PhilID)",
    "PRC ID",
    "Postal ID",
    "Voter's ID",
  ];

  Future<void> _handleFileSelected(web.Event event, String slot) async {
    setState(() {
      _error = null;
      if (slot == 'front') _isUploadingFront = true;
      if (slot == 'back') _isUploadingBack = true;
      if (slot == 'selfie') _isUploadingSelfie = true;
    });

    try {
      final files = await readFilesFromEvent(event);
      if (files.isEmpty) return;

      final file = files.first;
      final token = SessionStorage.idToken;
      final url = await ImgBBService(currentFirebaseConfig, idToken: token).uploadImageBytes(file.bytes, file.name);

      if (url != null) {
        setState(() {
          if (slot == 'front') _frontUrl = url;
          if (slot == 'back') _backUrl = url;
          if (slot == 'selfie') _selfieUrl = url;
        });
      } else {
        setState(() => _error = 'Failed to upload image. Please try again.');
      }
    } catch (e) {
      setState(() => _error = 'Upload error: $e');
    } finally {
      setState(() {
        if (slot == 'front') _isUploadingFront = false;
        if (slot == 'back') _isUploadingBack = false;
        if (slot == 'selfie') _isUploadingSelfie = false;
      });
    }
  }

  void _submit() {
    if (_idNumber.trim().isEmpty) {
      setState(() => _error = 'Please enter your ID Number.');
      return;
    }
    if (_frontUrl.isEmpty) {
      setState(() => _error = 'Please upload the front photo of your ID.');
      return;
    }
    // Passport doesn't usually require a back photo
    final needsBack = _idType != "Philippine Passport";
    if (needsBack && _backUrl.isEmpty) {
      setState(() => _error = 'Please upload the back photo of your ID.');
      return;
    }
    if (_selfieUrl.isEmpty) {
      setState(() => _error = 'Please upload a selfie holding your ID.');
      return;
    }

    component.state.submitIdVerification(
      idType: _idType,
      idNumber: _idNumber.trim(),
      frontUrl: _frontUrl,
      backUrl: _backUrl,
      selfieUrl: _selfieUrl,
    );
  }

  Component _uploadBox({
    required String labelText,
    required String currentUrl,
    required String slot,
    required bool isUploading,
    required bool isDark,
  }) {
    return div(
      classes: 'relative aspect-video rounded-2xl overflow-hidden border border-dashed ${isDark ? "border-zinc-800 bg-zinc-900/30" : "border-zinc-200 bg-zinc-50/50"} flex items-center justify-center',
      [
        label(
          classes: 'w-full h-full flex flex-col items-center justify-center cursor-pointer transition-opacity hover:opacity-90',
          attributes: {'for': 'kyc-file-input-$slot'},
          [
            input(
              type: InputType.file,
              classes: 'hidden',
              attributes: {
                'id': 'kyc-file-input-$slot',
                'accept': 'image/*',
                'style': 'display: none;',
              },
              events: {
                'change': (e) => _handleFileSelected(e, slot),
              },
            ),
            if (currentUrl.isNotEmpty)
              img(
                src: currentUrl,
                classes: 'w-full h-full object-cover',
                attributes: {'alt': labelText},
              )
            else ...[
              lIcon('camera', cls: 'w-6 h-6 mb-2 ${isDark ? "text-zinc-500" : "text-zinc-400"}'),
              p(classes: 'text-xs font-semibold ${isDark ? "text-zinc-400" : "text-zinc-500"} text-center px-2', [
                Component.text(labelText),
              ]),
            ],
            if (isUploading)
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

    final needsBack = _idType != "Philippine Passport";

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
                  h2(classes: 'text-xl font-black tracking-tight $textCls', [Component.text('Verify Government ID')]),
                  p(classes: 'text-xs $subTextCls mt-1', [Component.text('Submit your valid ID to upgrade your trust level.')]),
                ]),
                button(
                  classes: 'p-2 rounded-full hover:bg-zinc-500/20 transition-colors',
                  events: {'click': (_) => s.setState(() => s.showKycIdModal = false)},
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

                // ID Type Dropdown
                div(
                  classes: 'space-y-1.5',
                  [
                    label(classes: 'text-xs font-bold $subTextCls', [Component.text('Select Government ID Type')]),
                    select(
                      classes: inputCls,
                      events: {
                        'change': (e) {
                          setState(() {
                            _idType = (e.target as web.HTMLSelectElement).value;
                          });
                        }
                      },
                      [
                        for (final type in _philippineIds)
                          option(
                            attributes: {'value': type, if (type == _idType) 'selected': 'true'},
                            [Component.text(type)],
                          ),
                      ],
                    ),
                  ],
                ),

                // ID Number
                div(
                  classes: 'space-y-1.5',
                  [
                    label(classes: 'text-xs font-bold $subTextCls', [Component.text('ID Document Number')]),
                    input(
                      type: InputType.text,
                      classes: inputCls,
                      attributes: {
                        'placeholder': 'Enter your official ID number',
                        'value': _idNumber,
                      },
                      events: {
                        'input': (e) => setState(() => _idNumber = (e.target as web.HTMLInputElement).value),
                      },
                    ),
                  ],
                ),

                // Photo Uploads
                div(
                  classes: 'space-y-3',
                  [
                    p(classes: 'text-xs font-bold $subTextCls', [Component.text('Upload ID Photos')]),
                    div(
                      classes: 'grid grid-cols-2 gap-4',
                      [
                        _uploadBox(
                          labelText: 'Front of ID Card',
                          currentUrl: _frontUrl,
                          slot: 'front',
                          isUploading: _isUploadingFront,
                          isDark: isDark,
                        ),
                        if (needsBack)
                          _uploadBox(
                            labelText: 'Back of ID Card',
                            currentUrl: _backUrl,
                            slot: 'back',
                            isUploading: _isUploadingBack,
                            isDark: isDark,
                          )
                        else
                          div(
                            classes: 'rounded-2xl border border-dashed flex flex-col items-center justify-center p-4 text-center opacity-40 '
                                '${isDark ? "border-zinc-800 bg-zinc-900/10" : "border-zinc-200 bg-zinc-50/10"}',
                            [
                              lIcon('lock', cls: 'w-6 h-6 mb-1 text-zinc-500'),
                              p(classes: 'text-[10px] font-medium text-zinc-500', [
                                Component.text('Back photo not required for Passport'),
                              ]),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),

                // Selfie Upload
                div(
                  classes: 'space-y-2',
                  [
                    p(classes: 'text-xs font-bold $subTextCls', [Component.text('Upload Selfie Holding ID')]),
                    p(
                      classes: 'text-[10px] ${isDark ? "text-zinc-500" : "text-zinc-550"} leading-relaxed',
                      [
                        Component.text('Take a photo holding your ID card close to your face. Make sure details on both your face and the ID are clear and legible.'),
                      ],
                    ),
                    _uploadBox(
                      labelText: 'Selfie holding your ID card',
                      currentUrl: _selfieUrl,
                      slot: 'selfie',
                      isUploading: _isUploadingSelfie,
                      isDark: isDark,
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
                  events: {'click': (_) => s.setState(() => s.showKycIdModal = false)},
                  [Component.text('Cancel')],
                ),
                button(
                  classes: 'px-6 py-2.5 rounded-xl text-xs font-bold text-white logo-gradient hover:opacity-95 transition-all flex items-center gap-1.5 cursor-pointer border-0',
                  events: s.isLoadingKyc ? {} : {'click': (_) => _submit()},
                  [
                    if (s.isLoadingKyc) lIcon('loader-2', cls: 'w-3.5 h-3.5 animate-spin'),
                    Component.text(s.isLoadingKyc ? 'Submitting...' : 'Submit Verification'),
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
