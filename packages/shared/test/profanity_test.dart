import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Profanity Moderation & False Positive Immunity Tests', () {
    test('Scenario 2: Common words with profanity substrings are NOT falsely blocked', () {
      final cleanPrompts = [
        'Need assistance with my plumbing system',
        'Fast pass delivery to Bacoor',
        'Meet at Kanto street corner for item pickup',
        'Paspas delivery service needed today',
        'Kikiam and street food cart assistant',
        'Hypothetical scenario for vehicle logistics',
        'Classic car transport with care',
        'Peacock farm maintenance worker',
        'Dictionary editing and transcription assistant',
        'Assessing electrical wiring damage',
      ];

      for (final text in cleanPrompts) {
        expect(
          checkProfanity(text),
          isFalse,
          reason: 'Expected "$text" to be clean, but was flagged as profanity.',
        );
      }
    });

    test('Actual profanity phrases are correctly detected and blocked', () {
      final profanePrompts = [
        'Gago ka ba',
        'Tangina this job is bad',
        'Putang ina mo',
        'Ulol huwag kang kupal',
        'You are a bitch and a bastard',
        'fuck this service',
        'shut up asshole',
      ];

      for (final text in profanePrompts) {
        expect(
          checkProfanity(text),
          isTrue,
          reason: 'Expected "$text" to be flagged as profanity, but was allowed.',
        );
      }
    });
  });
}
