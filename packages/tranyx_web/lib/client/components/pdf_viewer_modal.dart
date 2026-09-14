import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../services/web_interop.dart';

class PdfViewerModalComponent extends StatefulComponent {
  final TranyxAppState appState;
  final String pdfSource;
  final String fileName;
  final VoidCallback onClose;

  const PdfViewerModalComponent({
    required this.appState,
    required this.pdfSource,
    required this.fileName,
    required this.onClose,
    super.key,
  });

  @override
  State<PdfViewerModalComponent> createState() => _PdfViewerModalState();
}

class _PdfViewerModalState extends State<PdfViewerModalComponent> {
  int _currentPage = 1;
  int _totalPages = 1;
  double _scale = 1.2;
  bool _isLoading = true;
  String? _resolvedSource;
  String? _errorMessage;
  bool _useIframeFallback = false;

  late final String _canvasId;

  @override
  void initState() {
    super.initState();
    _canvasId = 'pdf-render-canvas-${DateTime.now().microsecondsSinceEpoch}';
    _resolveAndRender();
  }

  Future<void> _resolveAndRender() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    String source = component.pdfSource.trim();

    // Check if source is a contract_document document ID
    if (source.startsWith('contract_document:')) {
      final docId = source.replaceFirst('contract_document:', '').trim();
      try {
        final doc = await component.appState.firestore.getDocument('contract_documents/$docId');
        if (doc != null) {
          final storageUrl = doc['storageUrl']?.toString();
          final dataUrl = doc['dataUrl']?.toString();
          if (storageUrl != null && storageUrl.isNotEmpty) {
            source = storageUrl;
          } else if (dataUrl != null && dataUrl.isNotEmpty) {
            source = dataUrl;
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Could not load contract document record: $e';
          });
        }
        return;
      }
    }

    _resolvedSource = source;
    if (!mounted) return;

    _renderCurrentPage();
  }

  void _renderCurrentPage() async {
    if (_resolvedSource == null || _resolvedSource!.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No contract document source available.';
        });
      }
      return;
    }

    setState(() => _isLoading = true);

    // Give DOM a microtask to ensure canvas is attached
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    try {
      final result = await renderPdfPageJs(
        _canvasId,
        _resolvedSource!,
        _currentPage,
        _scale,
      );

      if (!mounted) return;

      if (result != null && result['success'] == true) {
        setState(() {
          _isLoading = false;
          _totalPages = (result['totalPages'] as num?)?.toInt() ?? _totalPages;
          _currentPage = (result['currentPage'] as num?)?.toInt() ?? _currentPage;
          _errorMessage = null;
        });
      } else {
        // Switch to iframe fallback if PDF.js is unavailable
        setState(() {
          _isLoading = false;
          _useIframeFallback = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _useIframeFallback = true;
        });
      }
    }
  }

  void _prevPage() {
    if (_currentPage > 1) {
      setState(() => _currentPage--);
      _renderCurrentPage();
    }
  }

  void _nextPage() {
    if (_currentPage < _totalPages) {
      setState(() => _currentPage++);
      _renderCurrentPage();
    }
  }

  void _zoomIn() {
    if (_scale < 3.0) {
      setState(() => _scale += 0.25);
      _renderCurrentPage();
    }
  }

  void _zoomOut() {
    if (_scale > 0.6) {
      setState(() => _scale -= 0.25);
      _renderCurrentPage();
    }
  }

  void _fitWidth() {
    setState(() => _scale = 1.0);
    _renderCurrentPage();
  }

  void _download() {
    if (_resolvedSource != null && _resolvedSource!.isNotEmpty) {
      downloadPdfFileJs(_resolvedSource!, component.fileName);
    }
  }

  @override
  Component build(BuildContext context) {
    final isDark = component.appState.isDark;

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-2 md:p-6 bg-black/80 backdrop-blur-md animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-5xl h-full max-h-[95vh] rounded-3xl shadow-2xl overflow-hidden flex flex-col '
              '${isDark ? "bg-zinc-900 border border-zinc-800 text-white" : "bg-white border border-zinc-200 text-zinc-900"}',
          [
            // ── Top Header Bar ───────────────────────────────────────────────
            div(
              classes:
                  'px-6 py-4 border-b flex items-center justify-between gap-4 '
                  '${isDark ? "border-zinc-800 bg-zinc-900/90" : "border-zinc-150 bg-zinc-50"}',
              [
                div(classes: 'flex items-center gap-3 min-w-0', [
                  div(classes: 'p-2 rounded-xl bg-purple-500/10 text-purple-400 shrink-0', [
                    lIcon('file-text', cls: 'w-5 h-5'),
                  ]),
                  div(classes: 'min-w-0', [
                    h3(classes: 'text-sm md:text-base font-bold truncate', [
                      Component.text(component.fileName),
                    ]),
                    p(classes: 'text-xs text-zinc-400', [
                      Component.text('Custom Contract Document Viewer'),
                    ]),
                  ]),
                ]),

                div(classes: 'flex items-center gap-2', [
                  button(
                    classes:
                        'px-3 py-1.5 rounded-xl text-xs font-bold transition-colors flex items-center gap-1.5 border '
                        '${isDark ? "border-zinc-700 bg-zinc-800 hover:bg-zinc-700 text-zinc-200" : "border-zinc-200 bg-white hover:bg-zinc-100 text-zinc-700"}',
                    events: {'click': (_) => _download()},
                    [
                      lIcon('download', cls: 'w-4 h-4'),
                      span(classes: 'hidden sm:inline', [Component.text('Download PDF')]),
                    ],
                  ),
                  button(
                    classes: 'p-2 rounded-xl hover:bg-zinc-700/20 text-zinc-400 hover:text-white transition-colors',
                    events: {'click': (_) => component.onClose()},
                    [lIcon('x', cls: 'w-5 h-5')],
                  ),
                ]),
              ],
            ),

            // ── Interactive Controls Toolbar ─────────────────────────────────
            div(
              classes:
                  'px-6 py-2.5 border-b flex flex-wrap items-center justify-between gap-3 text-xs '
                  '${isDark ? "border-zinc-800/80 bg-zinc-950/60" : "border-zinc-150 bg-zinc-100/60"}',
              [
                // Page navigation
                div(classes: 'flex items-center gap-2', [
                  button(
                    classes:
                        'p-1.5 rounded-lg border transition-all '
                        '${_currentPage > 1 ? (isDark ? "border-zinc-700 hover:bg-zinc-800 text-white cursor-pointer" : "border-zinc-200 hover:bg-zinc-200 text-zinc-800 cursor-pointer") : "border-transparent text-zinc-600 cursor-not-allowed"}',
                    events: _currentPage > 1 ? {'click': (_) => _prevPage()} : {},
                    disabled: _currentPage <= 1,
                    [lIcon('chevron-left', cls: 'w-4 h-4')],
                  ),
                  span(classes: 'font-semibold text-zinc-400 px-1', [
                    Component.text('Page $_currentPage of $_totalPages'),
                  ]),
                  button(
                    classes:
                        'p-1.5 rounded-lg border transition-all '
                        '${_currentPage < _totalPages ? (isDark ? "border-zinc-700 hover:bg-zinc-800 text-white cursor-pointer" : "border-zinc-200 hover:bg-zinc-200 text-zinc-800 cursor-pointer") : "border-transparent text-zinc-600 cursor-not-allowed"}',
                    events: _currentPage < _totalPages ? {'click': (_) => _nextPage()} : {},
                    disabled: _currentPage >= _totalPages,
                    [lIcon('chevron-right', cls: 'w-4 h-4')],
                  ),
                ]),

                // Zoom & Scale controls
                div(classes: 'flex items-center gap-2', [
                  button(
                    classes: 'p-1.5 rounded-lg border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-200 hover:bg-zinc-200"} transition-colors',
                    events: {'click': (_) => _zoomOut()},
                    [lIcon('zoom-out', cls: 'w-4 h-4')],
                  ),
                  span(classes: 'font-mono text-xs text-zinc-400 px-1', [
                    Component.text('${(_scale * 100).round()}%'),
                  ]),
                  button(
                    classes: 'p-1.5 rounded-lg border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-200 hover:bg-zinc-200"} transition-colors',
                    events: {'click': (_) => _zoomIn()},
                    [lIcon('zoom-in', cls: 'w-4 h-4')],
                  ),
                  button(
                    classes: 'px-2 py-1 rounded-lg border ${isDark ? "border-zinc-700 hover:bg-zinc-800" : "border-zinc-200 hover:bg-zinc-200"} font-semibold transition-colors',
                    events: {'click': (_) => _fitWidth()},
                    [Component.text('Fit Width')],
                  ),
                ]),
              ],
            ),

            // ── Document Viewport ────────────────────────────────────────────
            div(
              classes: 'flex-1 overflow-auto p-4 md:p-8 flex items-center justify-center relative bg-zinc-950/80',
              [
                if (_isLoading)
                  div(classes: 'absolute inset-0 flex flex-col items-center justify-center gap-3 bg-zinc-950/70 z-10', [
                    lIcon('loader', cls: 'w-8 h-8 animate-spin text-purple-500'),
                    p(classes: 'text-xs text-zinc-400', [Component.text('Rendering page $_currentPage...')]),
                  ]),

                if (_errorMessage != null)
                  div(classes: 'max-w-md p-6 rounded-2xl bg-red-500/10 border border-red-500/20 text-center space-y-3', [
                    lIcon('alert-triangle', cls: 'w-8 h-8 text-red-400 mx-auto'),
                    h4(classes: 'text-sm font-bold text-red-400', [Component.text('Unable to Render PDF')]),
                    p(classes: 'text-xs text-zinc-400 leading-relaxed', [Component.text(_errorMessage!)]),
                    button(
                      classes: 'px-4 py-2 rounded-xl text-xs font-bold bg-red-500 hover:bg-red-600 text-white transition-colors cursor-pointer border-0',
                      events: {'click': (_) => _resolveAndRender()},
                      [Component.text('Retry Rendering')],
                    ),
                  ])
                else if (_useIframeFallback && _resolvedSource != null)
                  div(classes: 'w-full h-full flex flex-col items-center justify-center space-y-3', [
                    Component.element(
                      tag: 'iframe',
                      classes: 'w-full h-full rounded-2xl border border-zinc-800 bg-white shadow-2xl',
                      attributes: {
                        'src': _resolvedSource!,
                        'title': component.fileName,
                      },
                    ),
                  ])
                else
                  div(
                    classes: 'shadow-2xl rounded-xl overflow-hidden bg-white max-w-full my-auto',
                    [
                      Component.element(
                        tag: 'canvas',
                        id: _canvasId,
                        classes: 'block max-w-full h-auto',
                      ),
                    ],
                  ),
              ],
            ),

            // ── Footer Bar ───────────────────────────────────────────────────
            div(
              classes:
                  'px-6 py-3 border-t flex items-center justify-between text-xs text-zinc-400 '
                  '${isDark ? "border-zinc-800 bg-zinc-900" : "border-zinc-150 bg-zinc-50"}',
              [
                p(classes: 'text-[11px] text-zinc-500', [
                  Component.text('Tranyx Secure Legal Document Framework • Official Host Custom Contract'),
                ]),
                button(
                  classes: 'px-5 py-2 rounded-xl font-bold bg-purple-600 hover:bg-purple-700 text-white transition-colors border-0 cursor-pointer',
                  events: {'click': (_) => component.onClose()},
                  [Component.text('Close Viewer')],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
