bool checkProfanity(String text) {
  if (text.trim().isEmpty) return false;
  final bannedPhrases = const [
    'putang ina',
    'tang ina',
    'tangina',
    'gago',
    'tarantado',
    'kupal',
    'puki',
    'puta',
    'pota',
    'bobo',
    'pakyu',
    'ulol',
    'salsal',
    'kantot',
    'fuck',
    'fucking',
    'fucker',
    'shit',
    'asshole',
    'bitch',
    'bastard',
    'cunt',
    'pussy',
    'dick',
    'cock',
  ];

  for (final phrase in bannedPhrases) {
    final pattern = RegExp(
      r'(^|[^\w])' + RegExp.escape(phrase) + r'([^\w]|$)',
      caseSensitive: false,
    );
    if (pattern.hasMatch(text)) {
      return true;
    }
  }
  return false;
}
