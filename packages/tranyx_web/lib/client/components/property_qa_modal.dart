import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../services/web_interop.dart';

class PropertyQaModalComponent extends StatefulComponent {
  final TranyxAppState appState;
  const PropertyQaModalComponent({required this.appState, super.key});

  @override
  State<PropertyQaModalComponent> createState() => _PropertyQaModalState();
}

class _PropertyQaModalState extends State<PropertyQaModalComponent> {
  List<Map<String, dynamic>> _questions = [];
  String _newQuestionText = '';
  String? _answeringQuestionId;
  String _answerText = '';
  bool _isLoading = true;
  String? _currentPropertyId;

  @override
  void initState() {
    super.initState();
    _initListener();
  }

  void _initListener() {
    final prop = component.appState.selectedPropertyData;
    if (prop == null) return;
    _currentPropertyId = prop['id'];
    listenToPropertyQAJs(_currentPropertyId!, (String jsonStr) {
      try {
        final raw = jsonDecode(jsonStr) as List<dynamic>;
        setState(() {
          _questions = raw.map((q) => Map<String, dynamic>.from(q as Map)).toList();
          _isLoading = false;
        });
      } catch (e) {
        print('Error parsing property Q&A: $e');
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  void dispose() {
    if (_currentPropertyId != null) {
      unlistenPropertyQAJs(_currentPropertyId!);
    }
    super.dispose();
  }

  void _postQuestion() {
    final s = component.appState;
    final propertyId = _currentPropertyId;
    if (_newQuestionText.trim().isEmpty || s.userProfile?.uid == null || propertyId == null) return;

    postPropertyQuestionJs(
      propertyId,
      s.userProfile!.uid,
      s.userProfile?.name ?? s.userName,
      s.userProfile?.photoUrl ?? '',
      _newQuestionText.trim(),
    );
    setState(() => _newQuestionText = '');
  }

  void _postAnswer(String qId) {
    final propertyId = _currentPropertyId;
    if (_answerText.trim().isEmpty || propertyId == null) return;
    answerPropertyQuestionJs(propertyId, qId, _answerText.trim());
    setState(() {
      _answeringQuestionId = null;
      _answerText = '';
    });
  }

  @override
  Component build(BuildContext context) {
    final s = component.appState;
    final isDark = s.isDark;
    final prop = s.selectedPropertyData;
    if (prop == null) return div([]);

    // Re-initialize listener if selected property changed
    if (_currentPropertyId != prop['id']) {
      if (_currentPropertyId != null) {
        unlistenPropertyQAJs(_currentPropertyId!);
      }
      setState(() {
        _isLoading = true;
        _questions = [];
        _answeringQuestionId = null;
        _answerText = '';
      });
      _initListener();
    }

    final isHost = prop['hostId'] == s.userProfile?.uid;
    final bgCls = isDark ? 'bg-zinc-950 border-zinc-800' : 'bg-white border-zinc-200';
    final textCls = isDark ? 'text-white' : 'text-zinc-900';
    final subTextCls = isDark ? 'text-zinc-400' : 'text-zinc-500';

    return div(classes: 'fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm', [
      div(classes: 'w-full max-w-3xl max-h-[85vh] rounded-3xl border shadow-2xl flex flex-col animate-scale-up $bgCls', [
        // Header
        div(
          classes: 'p-6 border-b flex items-center justify-between ${isDark ? "border-zinc-800" : "border-zinc-100"}',
          [
            div([
              h2(classes: 'text-2xl font-bold $textCls', [Component.text('Public Q&A Forum')]),
              p(classes: 'text-sm $subTextCls mt-1', [Component.text(prop['title'] ?? '')]),
            ]),
            button(
              classes: 'p-2 rounded-full hover:bg-zinc-500/20 transition-colors',
              events: {'click': (_) => s.setState(() => s.showPropertyQaModal = false)},
              [lIcon('x', cls: 'w-6 h-6 $subTextCls')],
            ),
          ],
        ),

        // List
        div(classes: 'flex-1 overflow-y-auto p-6 space-y-6', [
          if (_isLoading)
            div(classes: 'flex justify-center p-10', [lIcon('loader', cls: 'w-8 h-8 animate-spin text-purple-500')])
          else if (_questions.isEmpty)
            div(classes: 'text-center p-10', [
              lIcon('message-circle-question', cls: 'w-12 h-12 mx-auto mb-3 $subTextCls opacity-55'),
              p(classes: 'text-lg font-bold text-zinc-550', [Component.text('No questions yet.')]),
              p(classes: 'text-sm $subTextCls mt-1', [
                Component.text('Be the first to ask the host a question about this property.'),
              ]),
            ])
          else
            for (final q in _questions)
              div(
                classes:
                    'p-5 rounded-2xl border ${isDark ? "border-zinc-800 bg-zinc-900/50" : "border-zinc-200 bg-zinc-50"}',
                [
                  // Question
                  div(classes: 'flex gap-3 mb-4', [
                    if (q['photoUrl'] != null && q['photoUrl'].toString().isNotEmpty)
                      img(
                        src: q['photoUrl'].toString(),
                        classes: 'w-10 h-10 rounded-full object-cover shrink-0',
                        attributes: {'alt': 'User'},
                      )
                    else
                      div(
                        classes: 'w-10 h-10 rounded-full bg-purple-500/20 flex items-center justify-center shrink-0',
                        [lIcon('user', cls: 'w-5 h-5 text-purple-400')],
                      ),
                    div(classes: 'flex-1', [
                      div(classes: 'flex justify-between items-baseline', [
                        p(classes: 'font-bold text-sm', [Component.text(q['name'] ?? 'User')]),
                      ]),
                      p(classes: 'mt-1 text-sm leading-relaxed $textCls', [Component.text(q['text'] ?? '')]),
                    ]),
                  ]),

                  // Answer
                  if (q['answer'] != null && q['answer'].toString().isNotEmpty)
                    div(classes: 'ml-13 pl-4 border-l-2 border-purple-500', [
                      div(classes: 'flex gap-2 items-center mb-1', [
                        badge('HOST RESPONSE', 'bg-purple-500/20 text-purple-400'),
                      ]),
                      p(classes: 'text-sm leading-relaxed $textCls', [Component.text(q['answer'])]),
                    ])
                  else if (isHost)
                    div(classes: 'ml-13 mt-2', [
                      if (_answeringQuestionId == q['id'])
                        div(classes: 'flex flex-col gap-2', [
                          textarea(
                            classes:
                                'w-full p-3 rounded-xl text-sm border focus:border-purple-500 outline-none transition-colors ${isDark ? "bg-zinc-950 border-zinc-700 text-white" : "bg-white border-zinc-300 text-zinc-900"}',
                            attributes: {'placeholder': 'Type your response...', 'rows': '2', 'value': _answerText},
                            events: {
                              'input': (e) {
                                // ignore: avoid_dynamic_calls
                                final val = (e as dynamic).target?.value as String? ?? '';
                                setState(() => _answerText = val);
                              }
                            },
                            [],
                          ),
                          div(classes: 'flex justify-end gap-2', [
                            button(
                              classes:
                                  'px-4 py-1.5 rounded-lg text-xs font-bold ${isDark ? "hover:bg-zinc-800" : "hover:bg-zinc-200"} cursor-pointer bg-transparent border-0',
                              events: {
                                'click': (_) => setState(() {
                                  _answeringQuestionId = null;
                                  _answerText = '';
                                }),
                              },
                              [Component.text('Cancel')],
                            ),
                            button(
                              classes:
                                  'px-4 py-1.5 rounded-lg text-xs font-bold text-white bg-purple-500 hover:bg-purple-600 cursor-pointer border-0',
                              events: {'click': (_) => _postAnswer(q['id'])},
                              [Component.text('Reply')],
                            ),
                          ]),
                        ])
                      else
                        button(
                          classes:
                              'text-xs font-bold text-purple-400 hover:text-purple-300 flex items-center gap-1 bg-transparent border-0 cursor-pointer',
                          events: {
                            'click': (_) => setState(() {
                              _answeringQuestionId = q['id'];
                              _answerText = '';
                            }),
                          },
                          [lIcon('corner-down-right', cls: 'w-3 h-3'), Component.text('Reply to question')],
                        ),
                    ]),
                ],
              ),
        ]),

        // Ask Input
        if (!isHost)
          div(
            classes:
                'p-4 border-t ${isDark ? "border-zinc-800 bg-zinc-900" : "border-zinc-200 bg-zinc-50"} rounded-b-3xl',
            [
              div(classes: 'flex gap-2', [
                input(
                  classes:
                      'flex-1 p-3 rounded-xl border focus:border-purple-500 outline-none transition-colors ${isDark ? "bg-zinc-950 border-zinc-700 text-white" : "bg-white border-zinc-300 text-zinc-900"}',
                  attributes: {
                    'placeholder': 'Ask a public question about this property...',
                    'value': _newQuestionText,
                  },
                  events: {
                    'input': (e) {
                      // ignore: avoid_dynamic_calls
                      final val = (e as dynamic).target?.value as String? ?? '';
                      setState(() => _newQuestionText = val);
                    },
                    'keydown': (e) {
                      if ((e as web.KeyboardEvent).key == 'Enter') _postQuestion();
                    },
                  },
                ),
                button(
                  classes:
                      'px-6 py-3 rounded-xl text-white font-bold logo-gradient hover:opacity-90 transition-opacity cursor-pointer border-0',
                  events: {'click': (_) => _postQuestion()},
                  [Component.text('Ask')],
                ),
              ]),
            ],
          ),
      ]),
    ]);
  }
}
