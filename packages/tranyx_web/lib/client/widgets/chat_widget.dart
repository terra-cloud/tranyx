import 'dart:async';
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
  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    // Live countdown ticker every 1 second
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }

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
    final type = msg['type'] as String? ?? 'text';

    if (senderId == 'system' || (type.isNotEmpty && type != 'text')) {
      return _buildSystemMessage(msg, uid, isDark);
    }

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

  Component _buildSystemMessage(Map<String, dynamic> msg, String uid, bool isDark) {
    final type = msg['type'] as String? ?? '';
    final s = component.state;
    final chatId = s.currentChatId;

    // Retrieve active job data if available
    final job = s.selectedJobData?['id'] == chatId
        ? s.selectedJobData
        : s.myJobs.firstWhere((j) => j['id'] == chatId, orElse: () => <String, dynamic>{});
    final acceptedNyxianId = job?['acceptedApplicantId'] as String? ?? '';
    final creatorId = job?['creatorId'] as String? ?? '';
    final isNyxian = uid == acceptedNyxianId;
    final isEmployer = uid == creatorId;

    if (type == 'acknowledgment_request') {
      final deadlineMs = (msg['deadline'] as num?)?.toInt() ?? (job?['acknowledgmentDeadline'] as num?)?.toInt();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final isExpired = deadlineMs != null && nowMs >= deadlineMs;
      final remainingMs = (deadlineMs != null) ? (deadlineMs - nowMs).clamp(0, 999999999) : 0;
      final remainingStr = JobSlaHelper.formatRemainingTime(Duration(milliseconds: remainingMs));
      final jobStatus = (job?['status'] as String? ?? '').toLowerCase();
      final isAcknowledged = jobStatus == 'in progress' ||
          jobStatus == 'completed' ||
          (job?['acknowledgmentStatus'] == 'acknowledged');

      final categoryId = msg['category'] as String? ?? job?['acknowledgmentCategory'] as String? ?? '';
      final category = JobSlaCategory.fromId(categoryId);

      return div(
        classes:
            'w-full my-2 p-4 rounded-2xl border ${isDark ? "bg-zinc-900/90 border-indigo-500/30" : "bg-indigo-50/70 border-indigo-200"} flex flex-col gap-3 shadow-md animate-fade-up',
        [
          div(classes: 'flex items-start gap-3', [
            div(classes: 'p-2.5 rounded-xl bg-indigo-500/20 text-indigo-400 flex-shrink-0 mt-0.5', [
              lIcon('clock', cls: 'w-5 h-5'),
            ]),
            div(classes: 'flex-1 min-w-0', [
              div(classes: 'flex items-center gap-2 flex-wrap', [
                p(classes: 'text-sm font-bold ${isDark ? "text-white" : "text-zinc-900"}', [
                  Component.text(isNyxian
                      ? '🎉 You have been hired for this task'
                      : '🎉 Nyxian hired — Awaiting Acknowledgment'),
                ]),
                span(
                  classes:
                      'text-[10px] font-extrabold px-2 py-0.5 rounded-full bg-indigo-500/15 text-indigo-400 border border-indigo-500/30',
                  [Component.text(category.label)],
                ),
              ]),
              p(classes: 'text-xs mt-1 leading-relaxed ${isDark ? "text-zinc-300" : "text-zinc-600"}', [
                Component.text(isNyxian
                    ? 'Please acknowledge that you have received the job and are ready to proceed.'
                    : 'Waiting for the Nyxian to confirm receipt of the job and proceed.'),
              ]),
            ]),
          ]),

          // Status & Live Countdown Row
          if (isAcknowledged)
            div(
              classes: 'px-3 py-2 rounded-xl bg-emerald-500/15 border border-emerald-500/30 flex items-center gap-2',
              [
                lIcon('check-circle-2', cls: 'w-4 h-4 text-emerald-400'),
                span(classes: 'text-xs font-semibold text-emerald-400', [
                  Component.text('✅ Nyxian has acknowledged the job and is proceeding with the task.'),
                ]),
              ],
            )
          else
            div(
              classes:
                  'px-3.5 py-2.5 rounded-xl ${isExpired ? "bg-rose-500/15 border border-rose-500/30" : "bg-amber-500/15 border border-amber-500/30"} flex items-center justify-between gap-2',
              [
                div(classes: 'flex items-center gap-2', [
                  lIcon(isExpired ? 'alert-triangle' : 'timer',
                      cls: 'w-4 h-4 ${isExpired ? "text-rose-400" : "text-amber-400"}'),
                  span(classes: 'text-xs font-bold ${isExpired ? "text-rose-400" : "text-amber-400"}', [
                    Component.text(isExpired
                        ? '⚠️ Acknowledgment period expired'
                        : '⏱️ Acknowledgment required within $remainingStr'),
                  ]),
                ]),
                if (!isExpired)
                  span(classes: 'w-2 h-2 rounded-full bg-amber-400 animate-ping', []),
              ],
            ),

          // Actions
          if (!isAcknowledged && isNyxian && !isExpired)
            button(
              classes:
                  'w-full py-3 rounded-xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2 shadow-lg shadow-indigo-500/20 cursor-pointer',
              events: {'click': (_) => s.acknowledgeJob(chatId)},
              [
                if (s.isUpdatingJobStatus) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
                lIcon('check', cls: 'w-4 h-4'),
                Component.text('ACKNOWLEDGE & START JOB'),
              ],
            ),

          if (!isAcknowledged && isEmployer && isExpired)
            button(
              classes:
                  'w-full py-2.5 rounded-xl font-bold text-white bg-rose-600 hover:bg-rose-500 transition-colors flex items-center justify-center gap-2 shadow-md cursor-pointer',
              events: {'click': (_) => s.cancelAndFindAnotherNyxian(chatId)},
              [
                if (s.isUpdatingJobStatus) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
                lIcon('user-x', cls: 'w-4 h-4'),
                Component.text('CANCEL & FIND ANOTHER NYXIAN'),
              ],
            ),
        ],
      );
    }

    if (type == 'acknowledgment_reminder') {
      return div(
        classes:
            'w-full my-2 px-4 py-3 rounded-2xl bg-amber-500/10 border border-amber-500/30 flex items-start gap-3 animate-fade-up',
        [
          lIcon('bell', cls: 'w-5 h-5 text-amber-400 flex-shrink-0 mt-0.5'),
          div([
            p(classes: 'text-xs font-bold text-amber-400', [
              Component.text('Acknowledgment Reminder'),
            ]),
            p(classes: 'text-xs text-amber-300/90 mt-0.5 leading-relaxed', [
              Component.text(msg['text'] as String? ??
                  'Acknowledgment required soon. Please acknowledge and start the job before the deadline.'),
            ]),
          ]),
        ],
      );
    }

    if (type == 'acknowledgment_confirmed') {
      return div(
        classes:
            'w-full my-2 px-4 py-3 rounded-2xl bg-emerald-500/15 border border-emerald-500/30 flex items-start gap-3 animate-fade-up',
        [
          lIcon('check-circle-2', cls: 'w-5 h-5 text-emerald-400 flex-shrink-0 mt-0.5'),
          div([
            p(classes: 'text-xs font-bold text-emerald-400', [
              Component.text('Job Acknowledged & Started'),
            ]),
            p(classes: 'text-xs text-emerald-300/90 mt-0.5 leading-relaxed', [
              Component.text(msg['text'] as String? ??
                  'Nyxian has acknowledged the job and is proceeding with the task.'),
            ]),
          ]),
        ],
      );
    }

    if (type == 'acknowledgment_expired') {
      return div(
        classes:
            'w-full my-2 p-4 rounded-2xl bg-rose-500/15 border border-rose-500/30 flex flex-col gap-3 animate-fade-up',
        [
          div(classes: 'flex items-start gap-3', [
            lIcon('alert-triangle', cls: 'w-5 h-5 text-rose-400 flex-shrink-0 mt-0.5'),
            div([
              p(classes: 'text-xs font-bold text-rose-400', [
                Component.text('Acknowledgment Expired'),
              ]),
              p(classes: 'text-xs text-rose-300/90 mt-0.5 leading-relaxed', [
                Component.text(msg['text'] as String? ??
                    'Nyxian did not acknowledge the job within the SLA period.'),
              ]),
            ]),
          ]),
          if (isEmployer)
            button(
              classes:
                  'w-full py-2.5 rounded-xl font-bold text-white bg-rose-600 hover:bg-rose-500 transition-colors flex items-center justify-center gap-2 text-xs shadow-md cursor-pointer',
              events: {'click': (_) => s.cancelAndFindAnotherNyxian(chatId)},
              [
                if (s.isUpdatingJobStatus) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
                lIcon('user-x', cls: 'w-4 h-4'),
                Component.text('CANCEL & FIND ANOTHER NYXIAN'),
              ],
            ),
        ],
      );
    }

    if (type == 'job_reopened') {
      return div(
        classes:
            'w-full my-2 px-4 py-3 rounded-2xl bg-indigo-500/15 border border-indigo-500/30 flex items-start gap-3 animate-fade-up',
        [
          lIcon('refresh-cw', cls: 'w-5 h-5 text-indigo-400 flex-shrink-0 mt-0.5'),
          div([
            p(classes: 'text-xs font-bold text-indigo-400', [
              Component.text('Gig Reopened'),
            ]),
            p(classes: 'text-xs text-indigo-300/90 mt-0.5 leading-relaxed', [
              Component.text(msg['text'] as String? ?? 'Gig reopened for other applicants.'),
            ]),
          ]),
        ],
      );
    }

    // Fallback for regular system text
    return div(
      classes: 'w-full my-2 p-3 text-center text-xs rounded-xl bg-zinc-500/10 text-zinc-400',
      [Component.text(msg['text'] as String? ?? '')],
    );
  }
}
