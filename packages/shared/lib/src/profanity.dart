bool checkProfanity(String text) {
  if (text.isEmpty) return false;
  final cleanText = text.toLowerCase();
  final bannedWords = const [
    'putang ina', 'tangina', 'gago', 'tarantado', 'kupal', 'puki', 'kiki', 'puta', 'pota', 'bobo', 'pakyu', 'ulol', 'salsal',
    'fuck', 'shit', 'asshole', 'bitch', 'bastard', 'cunt', 'pussy', 'dick', 'cock'
  ];
  for (final word in bannedWords) {
    if (cleanText.contains(word)) {
      return true;
    }
  }
  return false;
}
