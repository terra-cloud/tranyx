enum MessagePolicyResult {
  ok,
  piiBlocked,
  disintermediationBlocked,
}

class MessagePolicyFilter {
  /// Evaluates a chat message text for PII (phone, email, URLs) or off-platform payment attempts.
  static MessagePolicyResult check(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) return MessagePolicyResult.ok;

    // 1. Email check (standard & obfuscated)
    final emailRegex = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    final obfuscatedEmailRegex = RegExp(
      r'\b[a-zA-Z0-9._%+-]+\s*(?:@|\(at\)|\[at\]|\sat\s)\s*[a-zA-Z0-9.-]+\s*(?:\.|\(dot\)|\[dot\]|\sdot\s)\s*[a-zA-Z]{2,}\b',
    );
    if (emailRegex.hasMatch(text) || obfuscatedEmailRegex.hasMatch(lower)) {
      return MessagePolicyResult.piiBlocked;
    }

    // 2. Phone number check (PH mobile 09xx / +639xx, international, & spaced digits)
    final phoneRegex = RegExp(r'(\+?63\s*9|\b09)\d{2}[\s.-]?\d{3}[\s.-]?\d{4}\b');
    final generalPhoneRegex = RegExp(r'\b(?:\+?\d{1,3}[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b');
    final spacedDigitsRegex = RegExp(r'(?:\b\d[\s.-]){6,}\d\b');
    if (phoneRegex.hasMatch(text) || generalPhoneRegex.hasMatch(text) || spacedDigitsRegex.hasMatch(text)) {
      return MessagePolicyResult.piiBlocked;
    }

    // 3. External URLs / Web Links check
    final urlRegex = RegExp(r'https?://[^\s]+|www\.[^\s]+|\b[a-zA-Z0-9.-]+\.(?:com|ph|net|org|io|me|co|app)\b');
    final shortLinkRegex = RegExp(r'\b(?:t\.me|wa\.me|fb\.me|ig\.me|bit\.ly)/[^\s]+\b');
    if (urlRegex.hasMatch(lower) || shortLinkRegex.hasMatch(lower)) {
      return MessagePolicyResult.piiBlocked;
    }

    // 4. Off-platform contact & payment apps check
    final offPlatformPatterns = [
      RegExp(r'\bgcash\b'),
      RegExp(r'\bmaya\b'),
      RegExp(r'\bpaymaya\b'),
      RegExp(r'\bviber\b'),
      RegExp(r'\bwhatsapp\b'),
      RegExp(r'\btelegram\b'),
      RegExp(r'\bmessenger\b'),
      RegExp(r'\bfacebook\b'),
      RegExp(r'\binstagram\b'),
      RegExp(r'\bvenmo\b'),
      RegExp(r'\bpaypal\b'),
      RegExp(r'\bbank transfer\b'),
      RegExp(r'\bbdo\b'),
      RegExp(r'\bbpi\b'),
      RegExp(r'\bmetrobank\b'),
      RegExp(r'\blandbank\b'),
      RegExp(r'\bunionbank\b'),
      RegExp(r'\bremit\b'),
      RegExp(r'\bpay me\b'),
      RegExp(r'\bsend me\b.*money'),
      RegExp(r'\btransfer.*outside\b'),
      RegExp(r'outside.*platform'),
      RegExp(r'\bno need.*(tranyx|platform|app)\b'),
      RegExp(r'\bdeal outside\b'),
      RegExp(r'\bpay directly\b'),
      RegExp(r'\bdirect payment\b'),
    ];

    for (final pattern in offPlatformPatterns) {
      if (pattern.hasMatch(lower)) {
        return MessagePolicyResult.disintermediationBlocked;
      }
    }

    return MessagePolicyResult.ok;
  }
}

class MessageViolationTracker {
  static const int maxViolationsBeforeLock = 3;
  static final Map<String, int> _userViolationCounts = {};

  static int getViolationCount(String userId) {
    return _userViolationCounts[userId] ?? 0;
  }

  static bool isMessagingLocked(String userId) {
    return (_userViolationCounts[userId] ?? 0) >= maxViolationsBeforeLock;
  }

  /// Increments violation count for [userId]. Returns true if user reached threshold (>= 3).
  static bool recordViolation(String userId) {
    final current = (_userViolationCounts[userId] ?? 0) + 1;
    _userViolationCounts[userId] = current;
    return current >= maxViolationsBeforeLock;
  }

  static void reset(String userId) {
    _userViolationCounts.remove(userId);
  }

  /// Helper to generate the standardized Admin Ticket subject title.
  static String formatBanSubject(String userName) {
    return 'Subject for Ban: Repeated Chat Policy Violations ($userName)';
  }
}
