import 'package:web/web.dart' as web;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../services/web_interop.dart';

class ChatWidget extends StatefulComponent {
  final TranyxAppState state;
  const ChatWidget({required this.state});
  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> {
  final String _inputId = 'chat-msg-input';

  String _formatTime(dynamic raw) {
    try {
      final ms = raw is int ? raw : (raw as num).toInt();
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final uid = SessionStorage.uid ?? '';
    final msgs = s.chatMessages;

    // Real-time disintermediation keywords scanning
    final inputTextLower = s.chatInputText.toLowerCase();
    final hasDisintermediationKeywords =
        inputTextLower.contains('gcash') ||
        inputTextLower.contains('viber') ||
        inputTextLower.contains('whatsapp') ||
        inputTextLower.contains('direct payment') ||
        inputTextLower.contains('pay directly') ||
        inputTextLower.contains('outside');
    final phoneRegex = RegExp(r'(09|\+639)\d{9}|\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b');
    final hasPhoneNumber = phoneRegex.hasMatch(inputTextLower);
    final showRealtimeWarning = hasDisintermediationKeywords || hasPhoneNumber;

    final bg = isDark ? 'bg-zinc-950' : 'bg-white';
    final border = isDark ? 'border-zinc-800' : 'border-zinc-200';
    final inputBg = isDark ? 'bg-zinc-900 border-zinc-700 text-white' : 'bg-zinc-50 border-zinc-200 text-zinc-900';
    final headerBg = isDark ? 'bg-zinc-900/80' : 'bg-white/80';

    return div(
      classes:
          'fixed inset-0 z-[200] flex items-end sm:items-center justify-center p-0 sm:p-4 bg-black/60 backdrop-blur-sm',
      events: {
        'click': (e) {
          final target = (e).target;
          final self = e.currentTarget;
          if (target == self) s.closeChat();
        },
      },
      [
        div(
          classes:
              'w-full sm:max-w-lg h-[92dvh] sm:h-[75vh] flex flex-col rounded-t-3xl sm:rounded-3xl $bg border $border shadow-2xl overflow-hidden animate-fade-up',
          [
            // ── Header ──────────────────────────────────────────────────
            div(
              classes: '$headerBg backdrop-blur-md border-b $border flex items-center gap-3 px-5 py-4 flex-shrink-0',
              [
                div(
                  classes:
                      'p-2 rounded-xl ${s.currentChatIsArchived ? "bg-zinc-800 text-zinc-400" : "bg-indigo-500/20 text-indigo-400"}',
                  [
                    lIcon(s.currentChatIsArchived ? 'archive' : 'message-circle', cls: 'w-5 h-5'),
                  ],
                ),
                div(classes: 'flex-1 min-w-0', [
                  div(classes: 'flex items-center gap-2 flex-wrap', [
                    p(classes: 'font-bold text-sm truncate ${isDark ? "text-white" : "text-zinc-900"}', [
                      Component.text(
                        s.currentChatTitle.isNotEmpty
                            ? s.currentChatTitle
                            : (s.currentChatId.startsWith('rental_')
                                ? 'Rental Chat'
                                : (s.currentChatId.startsWith('property_')
                                    ? 'Property Chat'
                                    : 'Job Chat')),
                      ),
                    ]),
                    if (s.currentChatIsArchived)
                      span(
                        classes:
                            'text-[10px] font-extrabold px-2 py-0.5 rounded-full ${s.currentChatStatus.toLowerCase() == 'completed' || s.currentChatStatus.toLowerCase() == 'complete' ? "bg-emerald-500/15 text-emerald-400 border border-emerald-500/30" : "bg-rose-500/15 text-rose-400 border border-rose-500/30"}',
                        [
                          Component.text(s.currentChatStatus.isNotEmpty ? s.currentChatStatus : 'Archived'),
                        ],
                      ),
                  ]),
                  p(classes: 'text-[11px] truncate ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                    Component.text(
                      s.currentChatIsArchived
                          ? 'Archived Transaction History • Read-Only Reference'
                          : (s.currentChatCounterpartyName.isNotEmpty
                              ? 'Conversation with ${s.currentChatCounterpartyName}'
                              : 'Messages are monitored. No sharing of personal contact info.'),
                    ),
                  ]),
                ]),
                button(
                  classes:
                      'p-2 rounded-xl ${isDark ? "hover:bg-zinc-800 text-zinc-400" : "hover:bg-zinc-100 text-zinc-500"} transition-colors cursor-pointer',
                  events: {'click': (_) => s.closeChat()},
                  [lIcon('x', cls: 'w-5 h-5')],
                ),
              ],
            ),

            // ── Messages ────────────────────────────────────────────────
            div(
              classes: 'flex-1 overflow-y-auto px-4 py-4 space-y-3 no-scrollbar',
              attributes: {'id': 'chat-messages-container'},
              [
                if (msgs.isEmpty)
                  div(classes: 'h-full flex flex-col items-center justify-center gap-3 text-center', [
                    div(
                      classes: 'p-4 rounded-2xl ${s.currentChatIsArchived ? "bg-zinc-800 text-zinc-500" : "bg-indigo-500/10 text-indigo-400"}',
                      [lIcon(s.currentChatIsArchived ? 'archive' : 'message-circle', cls: 'w-8 h-8')],
                    ),
                    p(classes: 'text-sm font-semibold ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                      Component.text(s.currentChatIsArchived ? 'No archived messages found' : 'No messages yet'),
                    ]),
                    p(classes: 'text-xs ${isDark ? "text-zinc-600" : "text-zinc-400"}', [
                      Component.text(
                        s.currentChatIsArchived
                            ? 'This transaction has been closed.'
                            : 'Start the conversation below',
                      ),
                    ]),
                  ])
                else
                  for (final msg in msgs) _buildMessage(msg, uid, isDark),
              ],
            ),

            // ── Archived Notice Banner ──────────────────────────────────
            if (s.currentChatIsArchived)
              div(
                classes:
                    'mx-4 mb-2 p-3.5 rounded-2xl bg-amber-500/10 border border-amber-500/30 flex items-start gap-3 animate-fade-up',
                [
                  lIcon('archive', cls: 'w-5 h-5 text-amber-400 flex-shrink-0 mt-0.5'),
                  div([
                    p(classes: 'text-xs font-bold text-amber-400', [
                      Component.text('This conversation is archived.'),
                    ]),
                    p(classes: 'text-[11px] text-amber-300/90 mt-0.5 leading-relaxed', [
                      Component.text(
                        'This transaction was marked ${s.currentChatStatus.isNotEmpty ? s.currentChatStatus.toUpperCase() : "CLOSED"}${s.currentChatClosedDate.isNotEmpty ? " on ${s.currentChatClosedDate}" : ""}. The full chat history is preserved for reference, but messaging is disabled.',
                      ),
                    ]),
                  ]),
                ],
              ),

            // ── Locked messaging banner ──────────────────────────────────
            if (!s.currentChatIsArchived && (s.isChatLocked || MessageViolationTracker.isMessagingLocked(uid)))
              div(
                classes:
                    'mx-4 mb-2 px-4 py-3.5 rounded-2xl bg-red-500/15 border border-red-500/40 flex items-start gap-3 animate-fade-up',
                [
                  lIcon('lock', cls: 'w-5 h-5 text-red-400 flex-shrink-0 mt-0.5'),
                  div([
                    p(classes: 'text-xs font-bold text-red-400', [
                      Component.text('Messaging Locked — Subject for Ban Ticket Opened'),
                    ]),
                    p(classes: 'text-[11px] text-red-300/90 mt-1 leading-relaxed', [
                      Component.text(
                        'Your messaging access is temporarily locked due to repeated policy violations. An admin ticket titled "Subject for Ban: Repeated Chat Policy Violations" has been opened for account review.',
                      ),
                    ]),
                  ]),
                ],
              ),

            // ── PII warning banner ───────────────────────────────────────
            if (!s.currentChatIsArchived && s.chatPiiBlocked)
              div(
                classes:
                    'mx-4 mb-1 px-4 py-2.5 rounded-xl bg-red-500/10 border border-red-500/30 flex items-center gap-2 animate-fade-up',
                [
                  lIcon('shield-alert', cls: 'w-4 h-4 text-red-400 flex-shrink-0'),
                  p(classes: 'text-xs font-semibold text-red-400', [
                    Component.text('Message blocked: sharing phone numbers or emails is not allowed.'),
                  ]),
                ],
              ),

            // ── Disintermediation warning banner ────────────────────────
            if (!s.currentChatIsArchived && s.chatDisintermediationBlocked)
              div(
                classes: 'mx-4 mb-1 px-4 py-3 rounded-xl bg-orange-500/10 border border-orange-500/30 animate-fade-up',
                [
                  div(classes: 'flex items-start gap-2', [
                    lIcon('alert-triangle', cls: 'w-4 h-4 text-orange-400 flex-shrink-0 mt-0.5'),
                    div([
                      p(classes: 'text-xs font-bold text-orange-400', [
                        Component.text('Off-Platform Payment Attempt Blocked'),
                      ]),
                      p(classes: 'text-[10px] text-orange-300/80 mt-0.5', [
                        Component.text(
                          'Requesting payments outside Tranyx (GCash, Maya, bank transfer, etc.) violates our Terms of Service. Repeated violations may result in account suspension. All transactions are protected inside the platform.',
                        ),
                      ]),
                    ]),
                  ]),
                ],
              ),

            // ── Real-time warning banner ────────────────────────────────
            if (!s.currentChatIsArchived && showRealtimeWarning)
              div(
                classes:
                    'mx-4 mb-2 px-4 py-3 rounded-xl bg-amber-500/10 border border-amber-500/30 flex items-start gap-2 animate-fade-up',
                [
                  lIcon('shield-alert', cls: 'w-4 h-4 text-amber-400 flex-shrink-0 mt-0.5'),
                  div([
                    p(classes: 'text-xs font-bold text-amber-400', [
                      Component.text('Security Reminder'),
                    ]),
                    p(classes: 'text-[10px] text-amber-300/90 mt-0.5 font-medium leading-relaxed', [
                      Component.text(
                        'To protect your payment via Escrow, keep communications on-platform. Off-platform transactions lose platform coverage.',
                      ),
                    ]),
                  ]),
                ],
              ),

            // ── Input bar ───────────────────────────────────────────────
            if (s.currentChatIsArchived)
              div(
                classes:
                    'flex-shrink-0 px-5 py-4 border-t $border ${isDark ? "bg-zinc-900/90" : "bg-zinc-100/90"} flex items-center justify-center gap-2 text-center',
                [
                  lIcon('lock', cls: 'w-4 h-4 text-zinc-500'),
                  p(classes: 'text-xs font-bold text-zinc-500', [
                    Component.text('Messaging is disabled for closed transactions.'),
                  ]),
                ],
              )
            else
              div(
                classes:
                    'flex-shrink-0 px-4 py-3 border-t $border ${isDark ? "bg-zinc-900/80" : "bg-white/80"} backdrop-blur-md',
                [
                  div(classes: 'flex items-center gap-2', [
                    // Photo upload
                    if (!s.isChatLocked && !MessageViolationTracker.isMessagingLocked(uid))
                      div(classes: 'relative', [
                        button(
                          classes:
                              'p-2.5 rounded-xl ${isDark ? "bg-zinc-800 text-zinc-400 hover:text-indigo-400" : "bg-zinc-100 text-zinc-500 hover:text-indigo-500"} transition-colors',
                          attributes: {'title': 'Send photo'},
                          events: {},
                          [
                            if (s.isUploadingChatPhoto)
                              lIcon('loader-2', cls: 'w-5 h-5 animate-spin')
                            else
                              lIcon('image', cls: 'w-5 h-5'),
                          ],
                        ),
                        input(
                          type: InputType.file,
                          classes: 'absolute inset-0 opacity-0 cursor-pointer',
                          attributes: {
                            'accept': 'image/*',
                            'id': 'chat-photo-input',
                            'name': 'chat_photo',
                          },
                          events: {
                            'change': (e) => s.sendChatPhoto(e),
                          },
                        ),
                      ]),

                    // Text input
                    input(
                      type: InputType.text,
                      classes: (s.isChatLocked || MessageViolationTracker.isMessagingLocked(uid))
                          ? 'flex-1 px-4 py-3 rounded-xl text-sm border bg-zinc-800/40 border-zinc-800 text-zinc-500 outline-none cursor-not-allowed'
                          : 'flex-1 px-4 py-3 rounded-xl text-sm border $inputBg outline-none transition-colors focus:border-indigo-500',
                      attributes: {
                        'placeholder': (s.isChatLocked || MessageViolationTracker.isMessagingLocked(uid))
                            ? 'Messaging locked due to policy violations'
                            : 'Type a message...',
                        'id': _inputId,
                        'name': 'chat_message',
                        'value': s.chatInputText,
                        'autocomplete': 'off',
                        if (s.isChatLocked || MessageViolationTracker.isMessagingLocked(uid)) 'disabled': 'true',
                      },
                      events: (s.isChatLocked || MessageViolationTracker.isMessagingLocked(uid))
                          ? {}
                          : {
                              'input': (e) {
                                s.setState(() => s.chatInputText = getInputValue(e.target));
                              },
                              'keydown': (e) {
                                final ke = e as web.KeyboardEvent;
                                if (ke.key == 'Enter' && !ke.shiftKey) {
                                  ke.preventDefault();
                                  s.sendChatMessage();
                                }
                              },
                            },
                    ),

                    // Send button
                    button(
                      classes: (s.isChatLocked || MessageViolationTracker.isMessagingLocked(uid) || s.chatInputText.trim().isEmpty)
                          ? 'p-2.5 rounded-xl bg-indigo-500/30 text-white/50 cursor-not-allowed'
                          : 'p-2.5 rounded-xl logo-gradient text-white hover:opacity-90 transition-opacity',
                      attributes: (s.isChatLocked || MessageViolationTracker.isMessagingLocked(uid) || s.chatInputText.trim().isEmpty)
                          ? {'disabled': 'true'}
                          : {},
                      events: (s.isChatLocked || MessageViolationTracker.isMessagingLocked(uid) || s.chatInputText.trim().isEmpty)
                          ? {}
                          : {'click': (_) => s.sendChatMessage()},
                      [lIcon('send', cls: 'w-5 h-5')],
                    ),
                  ]),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Component _buildMessage(Map<String, dynamic> msg, String uid, bool isDark) {
    final senderId = msg['senderId'] as String? ?? '';
    final isMine = senderId == uid;
    final senderName = msg['senderName'] as String? ?? 'User';
    final text = msg['text'] as String? ?? '';
    final photoUrl = msg['photoUrl'] as String?;
    final timeRaw = msg['createdAt'];
    final timeStr = timeRaw != null ? _formatTime(timeRaw) : '';

    final bubbleBg = isMine
        ? 'logo-gradient text-white'
        : (isDark ? 'bg-zinc-800 text-zinc-100' : 'bg-zinc-100 text-zinc-900');

    return div(
      classes: 'flex ${isMine ? "justify-end" : "justify-start"} items-end gap-2',
      [
        if (!isMine)
          div(
            classes: 'w-7 h-7 rounded-full bg-indigo-600/30 flex items-center justify-center flex-shrink-0',
            [
              span(classes: 'text-[10px] font-bold text-indigo-400', [
                Component.text(senderName.isNotEmpty ? senderName[0].toUpperCase() : '?'),
              ]),
            ],
          ),
        div(classes: 'max-w-[72%] flex flex-col ${isMine ? "items-end" : "items-start"} gap-1', [
          if (!isMine)
            span(classes: 'text-[10px] font-bold px-1 ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
              Component.text(senderName),
            ]),
          div(
            classes: '$bubbleBg rounded-2xl ${isMine ? "rounded-br-md" : "rounded-bl-md"} px-4 py-2.5 shadow-sm',
            [
              if (photoUrl != null && photoUrl.isNotEmpty)
                img(
                  src: photoUrl,
                  classes:
                      'max-w-full rounded-xl max-h-48 object-cover cursor-zoom-in hover:opacity-95 transition-opacity',
                  events: {'click': (_) => component.state.showFullScreenPhoto(photoUrl)},
                )
              else
                p(classes: 'text-sm leading-relaxed', [Component.text(text)]),
            ],
          ),
          if (timeStr.isNotEmpty)
            span(
              classes: 'text-[9px] px-1 ${isDark ? "text-zinc-600" : "text-zinc-400"}',
              [Component.text(timeStr)],
            ),
        ]),
        if (isMine)
          div(
            classes: 'w-7 h-7 rounded-full bg-indigo-600 flex items-center justify-center flex-shrink-0',
            [
              span(classes: 'text-[10px] font-bold text-white', [
                Component.text(
                  (msg['senderName'] as String? ?? '?').isNotEmpty
                      ? (msg['senderName'] as String)[0].toUpperCase()
                      : '?',
                ),
              ]),
            ],
          ),
      ],
    );
  }
}
