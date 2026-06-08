import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/ai_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';

class NyxChatView extends ConsumerStatefulWidget {
  final VoidCallback onBack;

  const NyxChatView({super.key, required this.onBack});

  @override
  ConsumerState<NyxChatView> createState() => _NyxChatViewState();
}

class _NyxChatViewState extends ConsumerState<NyxChatView> {
  final List<Map<String, String>> _messages = [
    {
      'role': 'assistant',
      'content': "Kumusta! I'm Nyx, your Tranyx AI support assistant. How can I help you today? I can guide you through our standard gigs escrow flow, delivery tracker checkpoints, or platform features. I can speak English, Tagalog, and Waray-Waray!"
    }
  ];

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isThinking = false;
  double? _supportTokens;

  @override
  void initState() {
    super.initState();
    _loadSupportTokens();
  }

  Future<void> _loadSupportTokens() async {
    final profile = ref.read(userProfileProvider).value;
    if (profile == null) return;
    final uid = profile.uid;
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = userDoc.data();
      if (data != null && data.containsKey('supportTokensAvailable')) {
        final double savedTokens = (data['supportTokensAvailable'] as num).toDouble();
        final int savedTime = (data['supportLastRequestedTimestamp'] as num).toInt();
        final now = DateTime.now().millisecondsSinceEpoch;
        final elapsedMs = now - savedTime;
        final recovered = elapsedMs / 3600000.0;
        if (mounted) {
          setState(() {
            _supportTokens = (savedTokens + recovered).clamp(0.0, 5.0);
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _supportTokens = 5.0;
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isThinking) return;

    final profile = ref.read(userProfileProvider).value;
    if (profile == null) return;
    final uid = profile.uid;

    _messageController.clear();
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isThinking = true;
    });
    _scrollToBottom();

    // Check for satisfaction / termination keywords
    final cleanText = text.toLowerCase().trim();
    final terminationKeywords = [
      'thank you', 'thanks', 'thank u', 'no more questions', 'no more question', 
      'no questions', "i'm good", 'im good', 'satisfied', 'all good', 'that is all', 
      'thats all', "that's all", 'nothing else', 'no need',
      'salamat', 'maraming salamat', 'wala na', 'ok na', 'okay na', 'ayos na', 
      'sapat na', 'walang anuman',
      'damo nga salamat', 'waray na', 'igo na', 'tolda na'
    ];
    final isTerminating = terminationKeywords.any((k) => cleanText.contains(k) || cleanText == k);

    if (isTerminating) {
      String partingMsg = "You're welcome! Glad I could help. Terminating the support session now. Have a great day!";
      if (cleanText.contains('damo') || cleanText.contains('waray na') || cleanText.contains('igo na')) {
        partingMsg = 'Waray anuman! Malipayon ako nga nakabulig. Awtomatiko ko na nga tatapuson ini nga chat. Maopay nga adlaw!';
      } else if (cleanText.contains('salamat') || cleanText.contains('wala na') || cleanText.contains('ok na') || cleanText.contains('okay na') || cleanText.contains('ayos na')) {
        partingMsg = 'Walang anuman! Masaya akong makatutulong. Awtomatiko ko nang tatapusin ang chat na ito. Magandang araw!';
      }

      if (mounted) {
        setState(() {
          _messages.add({'role': 'assistant', 'content': partingMsg});
          _isThinking = false;
        });
        _scrollToBottom();
      }

      // Terminate after 2 seconds by calling onBack
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          widget.onBack();
        }
      });
      return;
    }

    // Quota Rate Limiting: 5 tokens max, recovering 1 token/hour (3,600,000 ms)
    // Only check tokens for a new conversation session (the first user message)
    double? tokensToUpdate;
    int? timestampToUpdate;
    final isNewConversation = (_messages.length == 2);

    if (isNewConversation) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final data = userDoc.data();
        final now = DateTime.now().millisecondsSinceEpoch;

        double tokensAvailable = 5.0;
        int lastRequestedTimestamp = now;

        if (data != null && data.containsKey('supportTokensAvailable')) {
          final double savedTokens = (data['supportTokensAvailable'] as num).toDouble();
          final int savedTime = (data['supportLastRequestedTimestamp'] as num).toInt();

          final elapsedMs = now - savedTime;
          final recovered = elapsedMs / 3600000.0;
          tokensAvailable = (savedTokens + recovered).clamp(0.0, 5.0);
          lastRequestedTimestamp = now;
        }

        if (tokensAvailable < 1.0) {
          final timeNeededMs = (1.0 - tokensAvailable) * 3600000.0;
          final minutesLeft = (timeNeededMs / 60000.0).ceil();
          if (mounted) {
            setState(() {
              _messages.add({
                'role': 'assistant',
                'content': 'You have run out of free support questions. A new free question token will recover in $minutesLeft minutes. Other services like title, description, and cover note generation remain unlimited!'
              });
              _isThinking = false;
            });
            _scrollToBottom();
          }
          return;
        }

        // Keep track of the checked values, but don't save yet!
        tokensToUpdate = tokensAvailable - 1.0;
        timestampToUpdate = lastRequestedTimestamp;
      } catch (e) {
        // If Firestore quota check fails, log it and allow request to fail gracefully or proceed.
        // We proceed to avoid blocking the user if Firestore has transient issues.
      }
    }

    // Prepare history to send to Cloudflare (exclude the system prompt which is appended inside the service)
    final history = _messages.sublist(1);

    try {
      final aiService = ref.read(aiServiceProvider);
      final response = await aiService.getChatResponse(history);

      // Successfully connected to server AI and got response!
      // Now decrement token if this was a new conversation.
      if (isNewConversation && tokensToUpdate != null && timestampToUpdate != null) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(uid).update({
            'supportTokensAvailable': tokensToUpdate,
            'supportLastRequestedTimestamp': timestampToUpdate,
          });
          if (mounted) {
            setState(() {
              _supportTokens = tokensToUpdate;
            });
          }
        } catch (_) {
          // Silently ignore or fallback
        }
      }

      if (mounted) {
        setState(() {
          _messages.add({'role': 'assistant', 'content': response});
          _isThinking = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add({
            'role': 'assistant',
            'content': "Sorry, I had trouble connecting. Please check if your Cloudflare Account ID is configured correctly in the app."
          });
          _isThinking = false;
        });
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Chat with Nyx",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _supportTokens != null
                            ? "AI Assistant • Online • Tokens: ${_supportTokens! % 1 == 0 ? _supportTokens!.toInt() : _supportTokens!.toStringAsFixed(1)}/5"
                            : "AI Assistant • Online",
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Chat Box Area
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg['role'] == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.7,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? AppColors.indigo
                                : (isDarkMode
                                    ? AppColors.darkBorder
                                    : Colors.grey[200]),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isUser ? 16 : 0),
                              bottomRight: Radius.circular(isUser ? 0 : 16),
                            ),
                          ),
                          child: Text(
                            msg['content'] ?? '',
                            style: TextStyle(
                              color: isUser
                                  ? Colors.white
                                  : (isDarkMode ? Colors.white : Colors.black87),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_isThinking)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.indigo,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Nyx is typing...",
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Input Bar
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: isDarkMode ? AppColors.darkBg : Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TextField(
                          controller: _messageController,
                          style: TextStyle(
                            color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: "Ask Nyx a question...",
                            hintStyle: TextStyle(
                              color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                            ),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send, color: AppColors.indigo),
                      onPressed: _sendMessage,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
